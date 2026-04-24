# AGENTS.md

Guidance for AI coding assistants working on this repository.

## What This Is

CrewDock — a self-hosted AI crew running 24/7 on your server via Docker, built on [OpenClaw](https://github.com/openclaw/openclaw). When working with OpenClaw APIs, cron jobs, sessions, config, or agent features, query the context7 MCP server (`/openclaw/openclaw`) for up-to-date documentation before guessing. For general upstream troubleshooting, check the [documentation](https://docs.openclaw.ai/start/getting-started).

The OpenClaw Gateway runs as an always-on LLM agent backed by Ollama (the only supported LLM provider — fixed by design). Current agents: **Scouter** (source monitoring) and **Alfred** (Google Workspace assistant), with **Overlord** as the sysadmin orchestrator.

## Ollama Configuration

Ollama env vars live in `.env` and are consumed by `init.d/02-config.sh` on first boot to generate `openclaw.json`.

**Cloud is the default.** Mode is inferred from `OLLAMA_HOST`; a cloud host without `OLLAMA_API_KEY` fails at boot.

| Var | Cloud (default) | Local |
|---|---|---|
| `OLLAMA_HOST` | `https://ollama.com` | `http://host.docker.internal:11434` |
| `OLLAMA_API_KEY` | required — from ollama.com/settings/keys | (empty) |
| `OLLAMA_MODEL` | e.g. `gemma4:31b` | e.g. `llama3.1:8b` |

**Per-agent model overrides:** optional. Default comes from `OLLAMA_MODEL`; override with `OLLAMA_MODEL_<AGENT_ID_UPPER>`. The `main` agent uses `OLLAMA_MODEL_OVERLORD`.

Example:
```
OLLAMA_MODEL=llama3.1:8b               # default for every agent
OLLAMA_MODEL_SCOUTER=qwen2.5:14b       # Scouter only
OLLAMA_MODEL_OVERLORD=llama3.1:70b     # Overlord only
# Alfred → falls through to OLLAMA_MODEL
```

The override lands at `agents.list[N].model.primary` in `openclaw.json`; agents without an override inherit `agents.defaults.model.primary`.

## Commands

```bash
./install.sh            # TUI installation wizard (first-time setup or reconfigure)
make up                 # Build and start services
make down               # Stop services
make restart            # Restart all; make restart-gateway for just gateway
make logs               # Tail gateway logs; make logs-all for all services
make auth               # Reconfigure Ollama host/model at runtime
make shell              # Bash into the gateway container
make config-preview     # Preview generated openclaw.json (no Docker needed)
make test               # Run all bats tests (requires: brew install bats-core)
```

## Project Structure

```
install.sh              # TUI installation wizard (entry point for new users)
installer/              # Wizard modules (manifest, integration setup scripts, TUI helpers)
agents/                 # Agent templates (tracked in git, copied to workspace on first boot)
home/                   # Persistent /home/node volume — all runtime config and data (gitignored)
```

Only `install.sh`, `installer/`, `agents/`, `docker-compose.yaml`, `Dockerfile`, `docker-entrypoint.sh`, `init.d/`, `Makefile`, and `docs/` are tracked in git. Everything under `home/` is gitignored runtime data.

## Version Pinning

The OpenClaw base image version is pinned in `.openclaw-version` (CalVer `YYYY.M.D-patch`). The Dockerfile receives it as a build arg `OPENCLAW_VERSION`. Base image is `ghcr.io/openclaw/openclaw`. `make up` pulls the base image if the pinned version isn't cached locally. `make version` shows pinned, running, and latest versions.

## Docker Setup

- Base image: `ghcr.io/openclaw/openclaw:<version>` (Debian-based, version from `.openclaw-version`)
- `Dockerfile` adds: git, jq, sqlite3, python3, build-essential
- `Dockerfile.local` — personal tool additions (gitignored, built from `.example`)
- `docker-compose.override.yaml` — personal service additions (gitignored, merges automatically)
- Container user: `node`. Home: `/home/node`

Volume mount: `./home` -> `/home/node` (single persistent volume for all runtime data)

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System). Run `make test` before committing. All tests must pass before any commit.

```
tests/
  test_helper.bash       # Shared setup/teardown helpers
  scouter-db.bats        # Scouter SQLite helper tests
  lib.bats               # installer/lib.sh utility tests (env_get, env_set, mask_token)
  reconfigure.bats       # _integration_status helper tests
```

When modifying shell scripts, add or update corresponding tests. Tests run against real SQLite databases in temp directories, no Docker needed.

## Git Conventions

- Branch naming: `feat/`, `fix/`, `chore/` prefixes, or issue-number based (`1-sqlite-tracking`)
- Commit messages: `feat:`, `fix:`, `chore:`, `merge:` prefixes
- **Run `make test` before committing.** All tests must pass.
- Never push to main directly — always feature branches + PRs

## Config Hot-Reload

OpenClaw watches `openclaw.json` and hot-applies most changes without restart (default mode: `hybrid`). Agents can use `config set` or `config.patch` to modify settings at runtime.

**Hot-applies instantly (no restart):** channels, agent routing, models, heartbeat, cron, automation, sessions, tools, logging.

**Requires gateway restart:** gateway server settings (port, auth, TLS), plugins, discovery, canvasHost.

For partial config updates from agent code, use `config.patch` RPC (requires `baseHash` from `config.get`). For single keys, use `openclaw config set`. Both trigger hot-reload automatically.

## Key Patterns

- **Agent installation:** Agent templates are baked into the Docker image at `/opt/openclaw-agents/` and copied to the workspace volume on first boot by `init.d/03-agents.sh`. Edit templates in `agents/<name>/`, rebuild the image with `make up` to pick up changes. The init script skips agents whose workspace directory already exists.
