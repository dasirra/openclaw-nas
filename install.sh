#!/usr/bin/env bash
# install.sh — CrewDock interactive TUI installation wizard
# Entry point: git clone ... && cd crewdock && ./install.sh
# Power user alternative: cp .env.example .env && vim .env && make up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
# shellcheck source=installer/lib.sh
source "$SCRIPT_DIR/installer/lib.sh"

# Detect and install gum
# shellcheck source=installer/gum.sh
source "$SCRIPT_DIR/installer/gum.sh"
gum_ensure

# --- Dependency checks ---
check_deps jq curl docker

# --- Load manifest ---
MANIFEST="$SCRIPT_DIR/installer/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  print_error "installer/manifest.json not found. Installation cannot continue."
  exit 1
fi

# --- Detect mode ---
RECONFIG=0
EXISTING_ENV="$SCRIPT_DIR/.env"
if [ -f "$EXISTING_ENV" ]; then
  RECONFIG=1
fi

# --- Screen 1: Welcome ---
echo ""
gum style \
  --border double \
  --border-foreground 212 \
  --padding "1 4" \
  --align center \
  --width 60 \
  "CrewDock" \
  "Installation Wizard"
echo ""

if [ "$RECONFIG" -eq 1 ]; then
  # Detect currently configured agents from .env
  CURRENT_AGENTS=""
  ALL_AGENT_IDS=$(jq -r '.agents[].id' "$MANIFEST")
  for aid in $ALL_AGENT_IDS; do
    AID_UPPER=$(echo "$aid" | tr '[:lower:]' '[:upper:]')
    token_val=$(env_get "DISCORD_${AID_UPPER}_TOKEN")
    if [ -n "$token_val" ]; then
      aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
      CURRENT_AGENTS="$CURRENT_AGENTS $aname"
    fi
  done
  CURRENT_AGENTS="${CURRENT_AGENTS# }"
  print_info "Existing configuration found."
  if [ -n "$CURRENT_AGENTS" ]; then
    print_info "Current agents: $CURRENT_AGENTS"
  fi
  print_info "You can add, remove, or update settings."
  echo ""

  # Source all integration modules for reconfigure mode
  # shellcheck source=installer/discord.sh
  source "$SCRIPT_DIR/installer/discord.sh"
  # shellcheck source=installer/gws.sh
  source "$SCRIPT_DIR/installer/gws.sh"
  # shellcheck source=installer/xurl.sh
  source "$SCRIPT_DIR/installer/xurl.sh"
  # shellcheck source=installer/ollama.sh
  source "$SCRIPT_DIR/installer/ollama.sh"

  # --- Reconfigure: agent submenu ---
  _run_agent_submenu() {
    local agent_id="$1"
    local agent_name="$2"
    while true; do
      local menu_items=""
      # Integrations from manifest
      local intg_ids
      intg_ids=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .integrations | keys[]' "$MANIFEST")
      for intg in $intg_ids; do
        local intg_label intg_status
        intg_label=$(jq -r --arg intg "$intg" '.integrations[$intg].label' "$MANIFEST")
        intg_status=$(_integration_status "$agent_id" "$intg")
        menu_items="${menu_items}${intg_label} (${intg_status})\n"
      done
      menu_items="${menu_items}Back"

      print_header "$agent_name"
      local choice
      choice=$(printf "%b" "$menu_items" | gum choose --header "")
      [ -z "$choice" ] && break
      [ "$choice" = "Back" ] && break

      # Strip " (status)" suffix to get the label
      local label
      label=$(echo "$choice" | sed -E 's/ \([^)]*\)$//')
      # Resolve label back to integration key via manifest
      local intg_key
      intg_key=$(jq -r --arg label "$label" \
        '.integrations | to_entries[] | select(.value.label == $label) | .key' "$MANIFEST")
      case "$intg_key" in
        discord)
          if [ -z "$(env_get "DISCORD_GUILD")" ]; then
            run_discord_shared
          fi
          run_discord_agent "$agent_id" "$agent_name"
          ;;
        gws)
          run_gws
          ;;
        xurl)
          run_xurl
          ;;
      esac
    done
  }

  # --- Reconfigure: top-level menu ---
  run_reconfigure_menu() {
    # Build id|name pairs once; reused for menu rendering and choice resolution
    local agent_map
    agent_map=$(jq -r '.agents[] | .id + "|" + .name' "$MANIFEST")

    while true; do
      local menu_items=""
      local aid aname aid_upper token_val
      while IFS='|' read -r aid aname; do
        aid_upper=$(echo "$aid" | tr '[:lower:]' '[:upper:]')
        token_val=$(env_get "DISCORD_${aid_upper}_TOKEN")
        if [ -n "$token_val" ]; then
          menu_items="${menu_items}${aname}\n"
        else
          menu_items="${menu_items}${aname} (not installed)\n"
        fi
      done <<EOF
$agent_map
EOF
      # LLM provider entry
      local ollama_host ollama_status
      ollama_host=$(env_get "OLLAMA_HOST")
      [ -n "$ollama_host" ] && ollama_status="configured" || ollama_status="not configured"
      menu_items="${menu_items}Ollama LLM provider (${ollama_status})\n"
      menu_items="${menu_items}Done"

      local choice
      choice=$(printf "%b" "$menu_items" | gum choose --header "What would you like to configure?")
      [ -z "$choice" ] && break
      [ "$choice" = "Done" ] && break

      case "$choice" in
        "Ollama LLM provider"*)
          print_header "Ollama LLM Provider"
          run_ollama
          continue
          ;;
      esac

      # Resolve chosen display string back to agent id
      local chosen_id="" chosen_name=""
      while IFS='|' read -r aid aname; do
        if [ "$choice" = "$aname" ] || [ "$choice" = "$aname (not installed)" ]; then
          chosen_id="$aid"
          chosen_name="$aname"
          break
        fi
      done <<EOF
$agent_map
EOF
      [ -z "$chosen_id" ] && continue

      # Check if installed
      aid_upper=$(echo "$chosen_id" | tr '[:lower:]' '[:upper:]')
      token_val=$(env_get "DISCORD_${aid_upper}_TOKEN")
      if [ -z "$token_val" ]; then
        run_full_agent_setup "$chosen_id"
      else
        _run_agent_submenu "$chosen_id" "$chosen_name"
      fi
    done
  }

  # --- Reconfigure: full agent setup (for not-installed agents) ---
  run_full_agent_setup() {
    local agent_id="$1"
    local agent_name
    agent_name=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .name' "$MANIFEST")

    print_header "Setting up $agent_name"

    # Run each integration
    local intg_ids
    intg_ids=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .integrations | keys[]' "$MANIFEST")
    for intg in $intg_ids; do
      case "$intg" in
        discord)
          print_header "Discord Setup"
          if [ -z "$(env_get "DISCORD_GUILD")" ]; then
            run_discord_shared
          fi
          run_discord_agent "$agent_id" "$agent_name"
          ;;
        gws)
          print_header "Google Workspace Setup"
          run_gws
          ;;
        xurl)
          print_header "X/Twitter Setup"
          run_xurl
          ;;
      esac
    done
  }

  # --- Reconfigure: summary ---
  run_reconfigure_summary() {
    # Ensure gateway token key exists (auto-generated on boot)
    if ! grep -qE "^OPENCLAW_GATEWAY_TOKEN=" "$SCRIPT_DIR/.env" 2>/dev/null; then
      env_set "OPENCLAW_GATEWAY_TOKEN" ""
    fi

    # Create runtime directories
    mkdir -p \
      "$SCRIPT_DIR/home/.openclaw/workspace" \
      "$SCRIPT_DIR/home/.config/gws"
    [ -f "$SCRIPT_DIR/home/.xurl" ] || touch "$SCRIPT_DIR/home/.xurl"

    echo ""
    print_header "Configuration Updated"
    echo ""

    gum style --foreground 212 "Configured agents:"
    local all_agent_ids
    all_agent_ids=$(jq -r '.agents[].id' "$MANIFEST")
    for aid in $all_agent_ids; do
      local aid_upper token aname
      aid_upper=$(echo "$aid" | tr '[:lower:]' '[:upper:]')
      token=$(env_get "DISCORD_${aid_upper}_TOKEN")
      if [ -n "$token" ]; then
        aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
        echo "  ✓ $aname"
      fi
    done
    echo ""

    gum style --foreground 212 "Integrations:"
    local discord_guild x_token ollama_host ollama_model
    discord_guild=$(env_get "DISCORD_GUILD")
    [ -n "$discord_guild" ] && echo "  ✓ Discord (configured)" || true
    [ -f "$SCRIPT_DIR/home/.config/gws/credentials.json" ] && echo "  ✓ Google Workspace (configured)" || true
    x_token=$(env_get "X_BEARER_TOKEN")
    [ -n "$x_token" ] && echo "  ✓ X/Twitter (configured)" || true
    ollama_host=$(env_get "OLLAMA_HOST")
    ollama_model=$(env_get "OLLAMA_MODEL")
    if [ -n "$ollama_host" ]; then
      if [ -n "$ollama_model" ]; then
        echo "  ✓ Ollama ($ollama_host, $ollama_model)"
      else
        echo "  ✓ Ollama ($ollama_host)"
      fi
    fi
    echo ""

    if gum_confirm "Restart OpenClaw now? (make restart)"; then
      print_info "Running make restart..."
      make -C "$SCRIPT_DIR" restart
    else
      print_info "Run 'make restart' to apply changes."
    fi
  }

  run_reconfigure_menu
  run_reconfigure_summary
  exit 0
fi

# --- Screen 2: Agent Selection ---
print_header "Select Agents"
print_info "Choose which agents to configure:"
echo ""

# Build agent list for gum choose
AGENT_CHOICES=""
ALL_AGENTS=$(jq -r '.agents[] | .id + "|" + .name + " — " + .description' "$MANIFEST")
while IFS= read -r line; do
  AGENT_CHOICES="$AGENT_CHOICES
$(echo "$line" | cut -d'|' -f2)"
done <<EOF
$ALL_AGENTS
EOF
AGENT_CHOICES="${AGENT_CHOICES#$'\n'}"

SELECTED_DISPLAY=$(echo "$AGENT_CHOICES" | gum choose --no-limit --header "Space to select, Enter to confirm:")
if [ -z "$SELECTED_DISPLAY" ]; then
  print_warn "No agents selected. Exiting."
  exit 0
fi

# Map display names back to IDs
SELECTED_AGENT_IDS=""
while IFS= read -r line; do
  if [ -z "$line" ]; then continue; fi
  # Extract just the agent name (before " — ")
  display_name=$(echo "$line" | sed 's/ — .*//')
  agent_id=$(jq -r --arg name "$display_name" '.agents[] | select(.name == $name) | .id' "$MANIFEST")
  if [ -n "$agent_id" ]; then
    SELECTED_AGENT_IDS="$SELECTED_AGENT_IDS $agent_id"
  fi
done <<EOF
$SELECTED_DISPLAY
EOF
SELECTED_AGENT_IDS="${SELECTED_AGENT_IDS# }"

if [ -z "$SELECTED_AGENT_IDS" ]; then
  print_error "Could not map agent selection. Exiting."
  exit 1
fi

echo ""
print_success "Selected: $SELECTED_AGENT_IDS"
echo ""

# --- Helper: agents needing a given integration ---
# agents_for_integration INTEGRATION_KEY — returns "Agent1, Agent2 (optional)" string
agents_for_integration() {
  local intg="$1"
  local result=""
  for aid in $SELECTED_AGENT_IDS; do
    local needs
    needs=$(jq -r --arg id "$aid" --arg intg "$intg" \
      '.agents[] | select(.id == $id) | .integrations[$intg] // "none"' "$MANIFEST")
    if [ "$needs" != "none" ]; then
      local aname
      aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
      local label=""
      [ "$needs" = "optional" ] && label=" (optional)"
      if [ -n "$result" ]; then
        result="$result, $aname$label"
      else
        result="$aname$label"
      fi
    fi
  done
  echo "$result"
}

# --- Compute required and optional integrations ---
REQUIRED_INTEGRATIONS=""
OPTIONAL_INTEGRATIONS=""

for agent_id in $SELECTED_AGENT_IDS; do
  agent_required=$(jq -r --arg id "$agent_id" \
    '.agents[] | select(.id == $id) | .integrations | to_entries[] | select(.value == "required") | .key' \
    "$MANIFEST")
  agent_optional=$(jq -r --arg id "$agent_id" \
    '.agents[] | select(.id == $id) | .integrations | to_entries[] | select(.value == "optional") | .key' \
    "$MANIFEST")

  for intg in $agent_required; do
    # Add if not already in required
    case " $REQUIRED_INTEGRATIONS " in
      *" $intg "*) ;;
      *) REQUIRED_INTEGRATIONS="$REQUIRED_INTEGRATIONS $intg" ;;
    esac
    # Remove from optional if it was there
    OPTIONAL_INTEGRATIONS=$(echo "$OPTIONAL_INTEGRATIONS" | tr ' ' '\n' | grep -v "^${intg}$" | tr '\n' ' ')
  done

  for intg in $agent_optional; do
    # Add to optional only if not already required
    case " $REQUIRED_INTEGRATIONS " in
      *" $intg "*) ;;
      *)
        case " $OPTIONAL_INTEGRATIONS " in
          *" $intg "*) ;;
          *) OPTIONAL_INTEGRATIONS="$OPTIONAL_INTEGRATIONS $intg" ;;
        esac
        ;;
    esac
  done
done

REQUIRED_INTEGRATIONS="${REQUIRED_INTEGRATIONS# }"
OPTIONAL_INTEGRATIONS="${OPTIONAL_INTEGRATIONS# }"

# --- Track integration status for summary ---
# Status values: validated, unverified, skipped
INTG_STATUS_discord=""
INTG_STATUS_gws=""
INTG_STATUS_xurl=""
INTG_STATUS_ollama=""

# --- Run integration flows ---
# Order: discord > gws > xurl > ollama

# Source all modules
# shellcheck source=installer/discord.sh
source "$SCRIPT_DIR/installer/discord.sh"
# shellcheck source=installer/gws.sh
source "$SCRIPT_DIR/installer/gws.sh"
# shellcheck source=installer/xurl.sh
source "$SCRIPT_DIR/installer/xurl.sh"
# shellcheck source=installer/ollama.sh
source "$SCRIPT_DIR/installer/ollama.sh"

# Discord (shared + per-agent)
case " $REQUIRED_INTEGRATIONS $OPTIONAL_INTEGRATIONS " in
  *" discord "*)
    print_header "Discord Setup"
    print_info "Agents: $(agents_for_integration discord)"
    echo ""
    run_discord_shared
    for agent_id in $SELECTED_AGENT_IDS; do
      # Check if this agent needs discord
      needs_discord=$(jq -r --arg id "$agent_id" \
        '.agents[] | select(.id == $id) | .integrations.discord // "none"' "$MANIFEST")
      if [ "$needs_discord" != "none" ]; then
        aname=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
        run_discord_agent "$agent_id" "$aname"
      fi
    done
    INTG_STATUS_discord="${DISCORD_SETUP_STATUS:-unverified}"
    ;;
esac

# GWS
case " $REQUIRED_INTEGRATIONS " in
  *" gws "*)
    print_header "Google Workspace Setup"
    print_info "Agents: $(agents_for_integration gws)"
    echo ""
    run_gws
    INTG_STATUS_gws="${GWS_SETUP_STATUS:-unverified}"
    ;;
  *)
    case " $OPTIONAL_INTEGRATIONS " in
      *" gws "*)
        if gum_confirm "Set up Google Workspace integration? (optional for $(agents_for_integration gws))"; then
          print_header "Google Workspace Setup"
          print_info "Agents: $(agents_for_integration gws)"
          echo ""
          run_gws
          INTG_STATUS_gws="${GWS_SETUP_STATUS:-unverified}"
        else
          INTG_STATUS_gws="skipped"
        fi
        ;;
    esac
    ;;
esac

# X/Twitter
case " $REQUIRED_INTEGRATIONS " in
  *" xurl "*)
    print_header "X/Twitter Setup"
    print_info "Agents: $(agents_for_integration xurl)"
    echo ""
    run_xurl
    INTG_STATUS_xurl="${XURL_SETUP_STATUS:-unverified}"
    ;;
  *)
    case " $OPTIONAL_INTEGRATIONS " in
      *" xurl "*)
        XURL_AGENTS=$(agents_for_integration xurl)
        if gum_confirm "$XURL_AGENTS can optionally use X/Twitter for monitoring. Set it up?"; then
          print_header "X/Twitter Setup"
          print_info "Agents: $XURL_AGENTS"
          echo ""
          run_xurl
          INTG_STATUS_xurl="${XURL_SETUP_STATUS:-unverified}"
        else
          INTG_STATUS_xurl="skipped"
        fi
        ;;
    esac
    ;;
esac

# Ollama (required: agents need at least one LLM provider to work)
print_header "Ollama LLM Provider"
print_info "Agents: $(echo "$SELECTED_AGENT_IDS" | tr ' ' '\n' | while read -r aid; do
  [ -z "$aid" ] && continue
  jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST"
done | paste -sd ', ' -)"
echo ""
run_ollama
INTG_STATUS_ollama="${OLLAMA_SETUP_STATUS:-skipped}"

# Set OPENCLAW_GATEWAY_TOKEN as empty (auto-generated on boot)
env_set "OPENCLAW_GATEWAY_TOKEN" ""

# --- Create runtime directories ---
mkdir -p \
  "$SCRIPT_DIR/home/.openclaw/workspace" \
  "$SCRIPT_DIR/home/.config/gws"
[ -f "$SCRIPT_DIR/home/.xurl" ] || touch "$SCRIPT_DIR/home/.xurl"

# --- Summary Screen ---
echo ""
print_header "Setup Complete"
echo ""

gum style --foreground 212 "Selected agents:"
for agent_id in $SELECTED_AGENT_IDS; do
  aname=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
  echo "  ✓ $aname"
done
echo ""

gum style --foreground 212 "Integrations:"

_status_icon() {
  case "$1" in
    validated) echo "✓" ;;
    unverified) echo "⚠" ;;
    skipped) echo "—" ;;
    *) echo "—" ;;
  esac
}

# Verifiable integrations: show validation status
[ -n "$INTG_STATUS_discord" ] && echo "  $(_status_icon "$INTG_STATUS_discord") Discord ($INTG_STATUS_discord)"
[ -n "$INTG_STATUS_xurl" ]    && echo "  $(_status_icon "$INTG_STATUS_xurl") X/Twitter ($INTG_STATUS_xurl)"
[ -n "$INTG_STATUS_ollama" ]  && echo "  $(_status_icon "$INTG_STATUS_ollama") Ollama ($INTG_STATUS_ollama)"
# Non-verifiable integrations: show configured/skipped only
if [ -n "$INTG_STATUS_gws" ]; then
  if [ "$INTG_STATUS_gws" = "skipped" ]; then
    echo "  — Google Workspace (skipped)"
  elif [ "$INTG_STATUS_gws" = "validated" ]; then
    echo "  ✓ Google Workspace (validated)"
  else
    echo "  ✓ Google Workspace (configured)"
  fi
fi

echo ""

if [ "$INTG_STATUS_ollama" != "validated" ] && [ "$INTG_STATUS_ollama" != "unverified" ]; then
  gum style --foreground 3 "Heads up: Ollama not configured."
  echo ""
  print_info "Agents require Ollama to work."
  print_info "Re-run ./install.sh to configure it."
  echo ""
fi

if gum_confirm "Start OpenClaw now? (make up)"; then
  print_info "Running make up..."
  make -C "$SCRIPT_DIR" up
else
  print_info "Run 'make up' when ready."
fi
