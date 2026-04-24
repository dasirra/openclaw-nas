#!/usr/bin/env bash
# installer/lib.sh — Shared helpers for the CrewDock installer
# Bash 3.2+ compatible: no associative arrays, no bash 4+ features

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

print_header() {
  echo ""
  gum style --bold --foreground 212 "── $1 ──"
  echo ""
}

print_success() {
  gum style --foreground 2 "  ✓ $1"
}

print_warn() {
  gum style --foreground 3 "  ⚠ $1"
}

print_error() {
  gum style --foreground 1 "  ✗ $1"
}

print_info() {
  gum style --foreground 8 "  $1"
}

# ---------------------------------------------------------------------------
# gum wrappers
# ---------------------------------------------------------------------------

# gum_confirm PROMPT — returns 0 if confirmed, 1 if declined
gum_confirm() {
  gum confirm "$1"
}

# gum_input PROMPT [PLACEHOLDER] — returns user input
gum_input() {
  local prompt="$1"
  local placeholder="${2:-}"
  if [ -n "$placeholder" ]; then
    gum input --placeholder "$placeholder" --prompt "$prompt: "
  else
    gum input --prompt "$prompt: "
  fi
}

# gum_input_password PROMPT — returns masked input
gum_input_password() {
  local prompt="$1"
  gum input --password --prompt "$prompt: "
}

# gum_write PROMPT — multiline input, returns content
gum_write() {
  local prompt="$1"
  echo "$prompt" >&2
  gum write --placeholder "Paste content here..."
}

# gum_choose PROMPT [--no-limit] ITEMS... — returns selected items
# Usage: gum_choose "Select one:" item1 item2 item3
# Usage: gum_choose "Select many:" --no-limit item1 item2 item3
gum_choose() {
  local prompt="$1"
  shift
  local no_limit=0
  if [ "$1" = "--no-limit" ]; then
    no_limit=1
    shift
  fi
  if [ "$no_limit" -eq 1 ]; then
    printf '%s\n' "$@" | gum choose --no-limit --header "$prompt"
  else
    printf '%s\n' "$@" | gum choose --header "$prompt"
  fi
}

# ---------------------------------------------------------------------------
# Token masking
# ---------------------------------------------------------------------------

# mask_token TOKEN — shows last 4 chars: ****...a1b2
mask_token() {
  local token="$1"
  local len="${#token}"
  if [ "$len" -le 4 ]; then
    echo "****"
  else
    local suffix="${token: -4}"
    echo "****...$suffix"
  fi
}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------

# check_deps CMD... — exits with error if any command is missing
check_deps() {
  local missing=""
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing="$missing $cmd"
    fi
  done
  if [ -n "$missing" ]; then
    print_error "Missing required tools:$missing"
    print_info "Please install them and re-run ./install.sh"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# .env file management
# Wizard-managed keys:
#   DISCORD_GUILD, DISCORD_*_TOKEN, DISCORD_*_CHANNEL,
#   X_BEARER_TOKEN, X_CLIENT_ID, X_CLIENT_SECRET,
#   OLLAMA_HOST, OLLAMA_MODEL,
#   OPENCLAW_GATEWAY_TOKEN
# ---------------------------------------------------------------------------

# SCRIPT_DIR must be set before sourcing lib.sh; unset will fail loudly under set -u.
_ENV_FILE="${SCRIPT_DIR}/.env"

# env_get KEY — reads value from .env, returns empty if not found
env_get() {
  local key="$1"
  if [ ! -f "$_ENV_FILE" ]; then
    echo ""
    return 0
  fi
  # Match KEY=VALUE or KEY="VALUE" or KEY='VALUE'
  local raw
  raw=$(grep -E "^${key}=" "$_ENV_FILE" 2>/dev/null | tail -1 || true)
  if [ -z "$raw" ]; then
    echo ""
    return 0
  fi
  local val="${raw#*=}"
  # Strip surrounding quotes if present
  if [ "${val#\"}" != "$val" ] && [ "${val%\"}" != "$val" ]; then
    val="${val#\"}"
    val="${val%\"}"
  elif [ "${val#\'}" != "$val" ] && [ "${val%\'}" != "$val" ]; then
    val="${val#\'}"
    val="${val%\'}"
  fi
  echo "$val"
}

# env_set KEY VALUE — writes/updates key in .env
env_set() {
  local key="$1"
  local value="$2"

  # Create .env if it doesn't exist
  if [ ! -f "$_ENV_FILE" ]; then
    touch "$_ENV_FILE"
    chmod 600 "$_ENV_FILE"
  fi

  # Escape special characters in value for sed
  # We'll write as KEY=value (no quotes unless needed)
  local escaped_value
  escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|&]/\\&/g')

  if grep -qE "^${key}=" "$_ENV_FILE" 2>/dev/null; then
    # Update existing line
    # Use a temp file approach for Bash 3.2 compat
    local tmpfile
    tmpfile=$(mktemp)
    sed "s|^${key}=.*|${key}=${escaped_value}|" "$_ENV_FILE" > "$tmpfile"
    mv "$tmpfile" "$_ENV_FILE"
    chmod 600 "$_ENV_FILE"
  else
    # Append new key
    echo "${key}=${value}" >> "$_ENV_FILE"
    chmod 600 "$_ENV_FILE"
  fi
}

# env_blank KEY — sets key to empty string in .env
env_blank() {
  local key="$1"
  env_set "$key" ""
}

# ---------------------------------------------------------------------------
# Integration status
# ---------------------------------------------------------------------------

# _integration_status AGENT_ID INTEGRATION_KEY — returns "configured" or "not configured"
_integration_status() {
  local agent_id="$1"
  local intg="$2"
  local agent_upper
  agent_upper=$(echo "$agent_id" | tr '[:lower:]' '[:upper:]')
  case "$intg" in
    discord)
      local token
      token=$(env_get "DISCORD_${agent_upper}_TOKEN")
      [ -n "$token" ] && echo "configured" || echo "not configured"
      ;;
    gws)
      [ -f "$SCRIPT_DIR/home/.config/gws/credentials.json" ] && echo "configured" || echo "not configured"
      ;;
    xurl)
      local token
      token=$(env_get "X_BEARER_TOKEN")
      [ -n "$token" ] && echo "configured" || echo "not configured"
      ;;
    *)
      echo "not configured"
      ;;
  esac
}
