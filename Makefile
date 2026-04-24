.PHONY: up down restart restart-gateway logs logs-all status version config-preview config-reset shell dashboard auth test clean help

OPENCLAW_VERSION := $(shell cat .openclaw-version 2>/dev/null || echo latest)
export OPENCLAW_VERSION

# --- Daily operations ---

up:                ## Build and start all services (pulls base image if version changed)
	@[ -f .env ] || { echo "No .env found. Run ./install.sh first (or copy .env.example manually)."; exit 1; }
	@mkdir -p home/.openclaw/workspace home/.config/gws projects
	@[ -f home/.xurl ] || touch home/.xurl
	@IMAGE_ID=$$(docker images -q ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION) 2>/dev/null); \
	if [ -z "$$IMAGE_ID" ]; then \
		echo "Pulling ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION)..."; \
		docker pull ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION); \
	fi
	docker compose up -d --build

down:              ## Stop all services
	docker compose down

restart:           ## Restart all services
	docker compose restart

restart-gateway:   ## Restart only the gateway
	docker compose restart openclaw-gateway

logs:              ## Tail gateway logs
	docker compose logs -f --tail 50 openclaw-gateway

logs-all:          ## Tail all service logs
	docker compose logs -f --tail 50

status:            ## Show running containers
	docker compose ps

version:           ## Show pinned, running, and latest versions
	@echo "Pinned:    $(OPENCLAW_VERSION)"
	@echo "Running:   $$(docker compose exec -T openclaw-gateway node dist/index.js --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 'not running')"
	@LATEST=$$(curl -sf "https://api.github.com/orgs/openclaw/packages/container/openclaw/versions?per_page=1" \
	  | jq -r '.[0].metadata.container.tags[0]' 2>/dev/null || echo 'unknown'); \
	echo "Latest:    $$LATEST"

config-preview:    ## Preview openclaw.json that would be generated (no Docker needed)
	@set -a && [ -f .env ] && . ./.env || true && set +a && \
	  DISCORD_AGENTS="scouter alfred" \
	  HOME="." \
	  bash init.d/02-config.sh --preview

config-reset:      ## Regenerate openclaw.json from .env (discards runtime config changes)
	@echo "This will regenerate openclaw.json from .env, discarding any runtime changes."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	docker compose exec -e CONFIG_RESET=1 openclaw-gateway bash -c 'source /usr/local/lib/openclaw-init.d/02-config.sh'
	$(MAKE) restart-gateway

# --- CLI tools ---

shell:             ## Open bash shell in the gateway container
	docker compose exec openclaw-gateway bash

dashboard:         ## Open dashboard: auto-approve pending devices, print URL
	@TOKEN=$$(docker compose exec openclaw-gateway cat /home/node/.openclaw/.gateway-token 2>/dev/null) && \
	PENDING=$$(docker compose exec -e OPENCLAW_GATEWAY_TOKEN=$$TOKEN openclaw-gateway \
		node dist/index.js devices list --json 2>/dev/null | jq -r '.pending[]?.requestId // empty' 2>/dev/null) && \
	if [ -n "$$PENDING" ]; then \
		for req in $$PENDING; do \
			docker compose exec -e OPENCLAW_GATEWAY_TOKEN=$$TOKEN openclaw-gateway \
				node dist/index.js devices approve "$$req" 2>/dev/null; \
			echo "Approved device: $$req"; \
		done; \
	fi && \
	echo "http://localhost:18789/?token=$$TOKEN"

auth:              ## Reconfigure Ollama host/model at runtime (hot-reload)
	@if ! docker compose ps --status running 2>/dev/null | grep -q openclaw-gateway; then \
	  echo "Error: Gateway is not running. Run 'make up' first."; exit 1; \
	fi
	@DEFAULT_HOST="http://host.docker.internal:11434"; \
	read -p "Ollama host URL [$$DEFAULT_HOST]: " INPUT_HOST; \
	HOST=$${INPUT_HOST:-$$DEFAULT_HOST}; \
	echo ""; \
	case "$$HOST" in \
	  http://*|https://*) ;; \
	  *) echo "  Error: URL must start with http:// or https://"; exit 1;; \
	esac; \
	echo "  Checking connectivity..."; \
	if RESPONSE=$$(curl -sf --max-time 5 "$$HOST/api/tags" 2>/dev/null); then \
	  echo "  Connected to Ollama at $$HOST"; \
	  echo ""; \
	  MODELS=$$(echo "$$RESPONSE" | jq -r '.models[].name // empty' 2>/dev/null | sed 's|^|  ollama/|'); \
	  if [ -n "$$MODELS" ]; then \
	    echo "  Available models:"; \
	    echo "$$MODELS"; \
	  else \
	    echo "  No models found. Pull one with: ollama pull <model>"; \
	  fi; \
	else \
	  echo "  Could not reach Ollama at $$HOST"; \
	  echo "  Make sure Ollama is running: ollama serve"; \
	  exit 1; \
	fi; \
	echo ""; \
	echo "  Registering Ollama provider with OpenClaw..."; \
	docker compose exec openclaw-gateway openclaw config set models.providers.ollama \
	  '{"baseUrl":"'"$$HOST"'","apiKey":"ollama-local","api":"ollama","models":[]}'; \
	echo "  Ollama registered. Run 'make shell' then 'openclaw models list' to verify."

# --- Maintenance ---

test:              ## Run all bats tests (requires: brew install bats-core)
	bats tests/

clean:             ## Remove old/dangling Docker images
	docker image prune -f
	@echo "Cleaned up unused images"

help:              ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
