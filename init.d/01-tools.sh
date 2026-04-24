#!/usr/bin/env bash
# 00-tools.sh -- Install user-space tools into persistent $HOME volume
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
# Runs as `node` user. Tools are installed once and persist across restarts.

# Pinned versions (correspond to Dockerfile npm pins)
GWS_COMMIT="a52d297cdfafbc53dfed66a3721a9bbd1d50dc31"  # @googleworkspace/cli@0.22.1

if npx skills list 2>/dev/null | grep -q googleworkspace; then
    log "GWS skills already installed."
else
    log "Installing Google Workspace skills (pinned commit: ${GWS_COMMIT})..."
    GWS_TMP=$(mktemp -d)
    git clone --quiet https://github.com/googleworkspace/cli.git "$GWS_TMP" \
      && git -C "$GWS_TMP" checkout --quiet "$GWS_COMMIT" \
      && npx -y skills add "$GWS_TMP" -y
    rm -rf "$GWS_TMP"
    log "GWS skills installed."
fi

log "OK"
