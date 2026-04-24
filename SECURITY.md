# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in CrewDock, please report it responsibly:

1. **Do not** open a public issue
2. Email **crewdock@proton.me** with details
3. Include steps to reproduce if possible
4. Allow reasonable time for a fix before public disclosure

## Scope

CrewDock runs as a Docker container and manages credentials for Discord, Google Workspace, and X/Twitter APIs. Security-relevant areas include:

- **Credential storage**: `.env` file permissions and secrets handling
- **SQL injection**: SQLite helpers in `scouter-db.sh`
- **Container security**: Dockerfile, entrypoint, and volume mount configuration
- **Input validation**: Install wizard credential validation

## Design Decisions

- `.env` files are created with `chmod 600` (owner-only read/write)
- All SQL inputs are escaped via `esc()` and validated via `assert_int()`
- The container runs as user `node`, not root (root is used only for initial permission fixing)
- Runtime data (`home/`) is gitignored to prevent accidental credential commits
