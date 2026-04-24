#!/usr/bin/env bash
# 03-agents.sh -- Install new agents or sync definition files for existing ones
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
#
# Agent registration and scheduling config are handled by 02-config.sh.
# This script only manages workspace files (templates, configs, databases).

AGENT_TEMPLATES="/opt/openclaw-agents"
WORKSPACE="$HOME/.openclaw/workspace"

for agent_dir in "$AGENT_TEMPLATES"/*/; do
    [ -d "$agent_dir" ] || continue
    agent_name=$(basename "$agent_dir")

    # Overlord template installs into the pre-registered "main" agent workspace
    if [ "$agent_name" = "overlord" ]; then
        target="$WORKSPACE/agents/main"
    else
        target="$WORKSPACE/agents/$agent_name"
    fi

    # Fresh install gate: skip Discord-bound agents with no token set (user didn't pick them).
    # Existing workspaces still get synced below regardless.
    if [ ! -d "$target" ] && echo " $DISCORD_AGENTS " | grep -q " $agent_name "; then
        token_var="DISCORD_$(echo "$agent_name" | tr '[:lower:]' '[:upper:]')_TOKEN"
        if [ -z "${!token_var:-}" ]; then
            log "Skipping '$agent_name' (not selected during install)."
            continue
        fi
    fi

    if [ ! -d "$target" ]; then
        # --- New agent: install workspace files ---
        log "Installing agent '$agent_name'..."

        mkdir -p "$target"
        cp -r "$agent_dir"* "$target/"

        # Rename .example.* files to their real names
        for example in "$target"/*.example.*; do
            [ -f "$example" ] || continue
            real="${example/.example/}"
            mv "$example" "$real"
        done

        # Clear projects list (user adds repos via Discord)
        if [ -f "$target/config.json" ]; then
            jq '.projects = []' "$target/config.json" > "$target/config.json.tmp" \
                && mv "$target/config.json.tmp" "$target/config.json"
        fi

        log "Installed $agent_name."
    else
        # --- Existing agent: sync definition files ---
        log "Syncing agent '$agent_name'..."

        # Cache protected patterns (read .protected file once, not per-file)
        protected_patterns=()
        if [ -f "$agent_dir/.protected" ]; then
            while IFS= read -r pattern || [ -n "$pattern" ]; do
                [[ "$pattern" =~ ^[[:space:]]*$ || "$pattern" =~ ^# ]] && continue
                protected_patterns+=("$pattern")
            done < "$agent_dir/.protected"
        fi

        for src_file in "$agent_dir"*; do
            [ -e "$src_file" ] || continue
            filename=$(basename "$src_file")

            skip=false
            for pattern in "${protected_patterns[@]}"; do
                # shellcheck disable=SC2254
                [[ "$filename" == $pattern ]] && skip=true && break
            done
            if [ "$skip" = true ]; then
                if [ ! -e "$target/$filename" ]; then
                    cp -r "$src_file" "$target/$filename"
                    log "  Seeded: $filename"
                else
                    log "  Protected: $filename"
                fi
                continue
            fi

            cp -r "$src_file" "$target/$filename"
            log "  Synced: $filename"
        done

        log "Synced $agent_name."
    fi
done

# Shared USER.md: install once, copy into each agent
# (symlinks cause "outside its configured root" warnings from OpenClaw skill loader)
if [ -f "$AGENT_TEMPLATES/USER.example.md" ] && [ ! -f "$WORKSPACE/agents/USER.md" ]; then
    cp "$AGENT_TEMPLATES/USER.example.md" "$WORKSPACE/agents/USER.md"
    log "Installed shared USER.md (edit to configure your voice profile)."
fi
if [ -f "$WORKSPACE/agents/USER.md" ]; then
    for agent_dir in "$WORKSPACE"/agents/*/; do
        [ -d "$agent_dir" ] || continue
        target="$agent_dir/USER.md"
        [ -L "$target" ] && rm "$target"  # replace old symlink with copy
        cp "$WORKSPACE/agents/USER.md" "$target"
        log "Copied USER.md -> $(basename "$agent_dir")/"
    done
fi

# Initialize agent databases (idempotent: CREATE TABLE IF NOT EXISTS)
for db_script in "$WORKSPACE"/agents/*/*-db.sh; do
    [ -f "$db_script" ] || continue
    agent_name=$(basename "$(dirname "$db_script")")
    chmod +x "$db_script"
    "$db_script" init
    log "$agent_name database initialized."
done
