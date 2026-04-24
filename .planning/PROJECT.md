# CrewDock: Obsidian Vault Sync

## What This Is

A Syncthing sidecar container for CrewDock that provides bidirectional sync with the user's Obsidian vault. All agents (Alfred, Scouter, Overlord) gain read/write access to the vault as a shared knowledge base, mounted at `/home/node/vault`.

## Core Value

Every agent in CrewDock can read and write to the user's Obsidian vault in real time, keeping the knowledge base synchronized bidirectionally with the user's local Obsidian instance.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Syncthing runs as a Docker sidecar container alongside existing CrewDock services
- [ ] Vault mounts at `/home/node/vault` inside the main container, accessible by all agents
- [ ] Bidirectional sync: agents can read and write notes that sync back to local Obsidian
- [ ] install.sh wizard includes an optional step to enable vault sync
- [ ] Minimal config: installer only asks for local vault path on the host
- [ ] Syncthing peers with the user's existing Syncthing instance
- [ ] Sync works with the full vault (no folder filtering)

### Out of Scope

- Per-agent vault access control — all agents share the same mount
- Vault folder filtering or partial sync — full vault only for v1
- Conflict resolution UI — rely on Syncthing's built-in conflict handling
- Obsidian plugin integration — this is file-level sync, not plugin-level

## Context

- CrewDock runs 3 agents: Alfred (GWS assistant), Scouter (content radar), Overlord (sysadmin)
- User already runs Syncthing to sync the Obsidian vault across devices
- The vault lives at `/Users/dasirra/Vault` locally (the "Second Brain")
- Docker setup uses host networking, single persistent volume at `./home` -> `/home/node`
- install.sh is a TUI wizard with modular setup scripts under `installer/`
- The existing install flow supports selective reconfiguration of integrations

## Constraints

- **Docker**: Syncthing must run as a separate container (sidecar), not inside the main OpenClaw container
- **Networking**: CrewDock uses host networking; Syncthing needs ports 8384 (web UI, optional) and 22000 (sync protocol)
- **Permissions**: Container user is `node`; vault files must be readable/writable by this user
- **Existing Syncthing**: Must peer with an already-running Syncthing instance, not replace it

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Sidecar container vs in-container install | Separation of concerns, independent updates, cleaner Docker architecture | — Pending |
| Mount at /home/node/vault | Consistent with existing home volume pattern, accessible by all agents | — Pending |
| Optional install step | Not all users have Obsidian; keep core CrewDock lightweight | — Pending |
| Minimal config (vault path only) | Reduce friction; Syncthing device pairing can happen via web UI post-install | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-25 after initialization*
