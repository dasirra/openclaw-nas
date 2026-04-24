#!/usr/bin/env bash
set -euo pipefail

INIT_DIR="/usr/local/lib/openclaw-init.d"

# Agents with Discord integration (used by 01-config.sh and 03-agents.sh)
DISCORD_AGENTS="scouter alfred"

# If running as root: fix volume permissions, then re-exec as node.
# The re-exec falls through to the non-root path below, which sources
# init scripts in-process — no subshell, so exports propagate naturally.
if [ "$(id -u)" = "0" ]; then
    chown -R node:node /home/node
    exec gosu node "$0" "$@"
fi

# --- Running as node (either directly or after re-exec from root) ---

# Shared helpers for init scripts (sourced into same shell)
log() { echo "[init] $SCRIPT_NAME: $*"; }

# Run pre-boot init scripts (gateway is NOT running yet)
for script in "$INIT_DIR"/*.sh; do
    [ -f "$script" ] || continue
    SCRIPT_NAME="$(basename "$script" .sh)"
    echo "[init] Running $(basename "$script")..."
    # shellcheck source=/dev/null
    source "$script"
done

echo "[init] Init complete. Starting gateway..."
exec "$@"
