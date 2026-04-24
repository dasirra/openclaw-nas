#!/usr/bin/env bash
# 02-config.sh -- Generate openclaw.json on first boot, preserve on subsequent boots
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh
#
# Standalone usage (preview mode):
#   DISCORD_AGENTS="scouter alfred" bash init.d/02-config.sh --preview
#
# Force regeneration (used by 'make config-reset'):
#   CONFIG_RESET=1 (env var) or --reset (arg)

# Support standalone preview mode (used by 'make config-preview')
if [ -z "${SCRIPT_NAME:-}" ]; then
    SCRIPT_NAME="02-config"
    log() { echo "[preview] $*" >&2; }
    DISCORD_AGENTS="${DISCORD_AGENTS:-scouter alfred}"
fi

CONFIG_FILE="${HOME}/.openclaw/openclaw.json"
WORKSPACE="${HOME}/.openclaw/workspace"

PREVIEW=false
RESET=false
for arg in "$@"; do
    case "$arg" in
        --preview) PREVIEW=true ;;
        --reset)   RESET=true ;;
    esac
done
[ "${CONFIG_PREVIEW:-}" = "1" ] && PREVIEW=true
[ "${CONFIG_RESET:-}" = "1" ] && RESET=true

# ---------- Step 1: Resolve gateway token (always needed, even if config exists) ----------

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    log "Using gateway token from environment."
else
    TOKEN_FILE="$HOME/.openclaw/.gateway-token"
    if [ -f "$TOKEN_FILE" ]; then
        export OPENCLAW_GATEWAY_TOKEN=$(cat "$TOKEN_FILE")
        log "Using gateway token from persisted file."
    else
        export OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        echo "$OPENCLAW_GATEWAY_TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        log "Generated and persisted new gateway token."
    fi
fi

# ---------- Step 2: Skip generation if config exists (unless preview or reset) ----------

if [ "$PREVIEW" = false ] && [ "$RESET" = false ] && [ -f "$CONFIG_FILE" ]; then
    log "Config exists, preserving runtime state. Use 'make config-reset' to regenerate."
    return 0 2>/dev/null || exit 0
fi

if [ "$RESET" = true ] && [ -f "$CONFIG_FILE" ]; then
    log "CONFIG_RESET requested. Regenerating config from env vars."
fi

# ---------- Step 3: Build agents data from env vars ----------

AGENTS_DATA='[]'
for agent in $DISCORD_AGENTS; do
    upper=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
    token_var="DISCORD_${upper}_TOKEN"
    channel_var="DISCORD_${upper}_CHANNEL"
    model_var="OLLAMA_MODEL_${upper}"
    token="${!token_var:-}"
    channel="${!channel_var:-}"
    model="${!model_var:-}"

    [ -z "$token" ] && continue

    AGENTS_DATA=$(echo "$AGENTS_DATA" | jq \
        --arg id "$agent" \
        --arg channel "$channel" \
        --arg model "$model" \
        '. + [{id: $id, channel: $channel, model: $model}]')
done

log "Discord agents: $(echo "$AGENTS_DATA" | jq -r '[.[].id] | join(", ")') ($(echo "$AGENTS_DATA" | jq length) configured)"

# ---------- Step 4: Build core config with jq ----------

# Ollama is the only supported provider. OLLAMA_HOST is required.
# Cloud (default):  OLLAMA_HOST=https://ollama.com  +  OLLAMA_API_KEY=<key>
# Local:            OLLAMA_HOST=http://host.docker.internal:11434
if [ -z "${OLLAMA_HOST:-}" ]; then
    log "ERROR: OLLAMA_HOST is not set. Ollama is the only supported LLM provider."
    log "Set OLLAMA_HOST in .env (cloud default: https://ollama.com)."
    return 1 2>/dev/null || exit 1
fi

# Cloud hosts need an API key. Fail loudly so the mistake is visible at boot.
case "$OLLAMA_HOST" in
    https://ollama.com*|https://*.ollama.com*)
        if [ -z "${OLLAMA_API_KEY:-}" ]; then
            log "ERROR: OLLAMA_HOST points at Ollama Cloud but OLLAMA_API_KEY is not set."
            log "Get a key at https://ollama.com/settings/keys and set OLLAMA_API_KEY in .env."
            return 1 2>/dev/null || exit 1
        fi
        OLLAMA_MODE="cloud"
        ;;
    *)
        OLLAMA_MODE="local"
        ;;
esac

OLLAMA_API_KEY_VAL="${OLLAMA_API_KEY:-ollama-local}"
OLLAMA_MODEL_ID="${OLLAMA_MODEL:-gemma4:31b}"
MODEL_PRIMARY="ollama/${OLLAMA_MODEL_ID}"
OVERLORD_MODEL="${OLLAMA_MODEL_OVERLORD:-}"

log "Ollama ($OLLAMA_MODE): $OLLAMA_HOST (default model: ${OLLAMA_MODEL_ID})"

PROVIDERS=$(jq -n \
    --arg baseUrl "$OLLAMA_HOST" \
    --arg apiKey "$OLLAMA_API_KEY_VAL" \
    '{
        ollama: {
            baseUrl: $baseUrl,
            apiKey: $apiKey,
            api: "ollama",
            models: []
        }
    }')

CORE=$(jq -n \
    --arg bind "${OPENCLAW_GATEWAY_BIND:-loopback}" \
    --arg guild "${DISCORD_GUILD:-}" \
    --arg workspace "$WORKSPACE" \
    --argjson agents "$AGENTS_DATA" \
    --arg modelPrimary "$MODEL_PRIMARY" \
    --arg overlordModel "$OVERLORD_MODEL" \
    --argjson providers "$PROVIDERS" \
    '
    { models: { providers: $providers } }
    +
    {
        gateway: {
            mode: "local",
            bind: ($bind),
            auth: { token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" } },
            controlUi: { allowedOrigins: ["*"] }
        },

        agents: {
            defaults: {
                memorySearch: { enabled: false },
                model: {
                    primary: $modelPrimary,
                    fallbacks: []
                }
            },
            list: (
                [({
                    id: "main",
                    name: "Overlord",
                    identity: { name: "Overlord" },
                    workspace: ($workspace + "/agents/main"),
                    agentDir: ($workspace + "/agents/main")
                } + (if $overlordModel != "" then {
                    model: { primary: ("ollama/" + $overlordModel) }
                } else {} end))] + [
                    $agents[] | {
                        id: .id,
                        name: .id,
                        workspace: ($workspace + "/agents/" + .id),
                        agentDir: ($workspace + "/agents/" + .id)
                    } + (if .model != "" then {
                        model: { primary: ("ollama/" + .model) }
                    } else {} end)
                      + (if .channel != "" then {
                        heartbeat: {
                            target: "discord",
                            to: ("channel:" + .channel),
                            accountId: .id,
                            directPolicy: "block"
                        }
                    } else {} end)
                ]
            )
        },

        channels: {
            discord: {
                accounts: (
                    $agents | map({
                        key: .id,
                        value: (
                            { token: { source: "env", provider: "default", id: ("DISCORD_" + (.id | ascii_upcase) + "_TOKEN") }, groupPolicy: "open" }
                            + (if $guild != "" then {
                                guilds: {
                                    ($guild): (if .channel != "" then {
                                        channels: {
                                            (.channel): {
                                                allow: true,
                                                requireMention: false
                                            }
                                        }
                                    } else {} end)
                                }
                            } else {} end)
                        )
                    }) | from_entries
                )
            }
        },

        bindings: [
            $agents[] | {
                agentId: .id,
                match: { channel: "discord", accountId: .id }
            }
        ],

        plugins: {
            allow: ["acpx"],
            entries: {
                acpx: {
                    enabled: true,
                    config: { permissionMode: "approve-all" }
                }
            }
        },

        acp: {
            enabled: true,
            backend: "acpx"
        },

        hooks: {
            internal: {
                enabled: true,
                entries: {
                    "boot-md": { enabled: true }
                }
            }
        },

        session: {
            threadBindings: { enabled: true }
        }
    }
    ')

# ---------- Step 5: Write or preview ----------

if [ "$PREVIEW" = true ]; then
    echo "$CORE" | jq .
else
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$CORE" > "$CONFIG_FILE"
    log "Config written to $CONFIG_FILE"
fi
