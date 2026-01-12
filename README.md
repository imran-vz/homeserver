# Homeserver

Docker Compose-based homeserver running on macOS (OrbStack). Services are exposed securely over **Tailscale** using a **Tailscale sidecar** per service.

## What’s in this repo

- `compose.yml` — main Docker Compose stack
- `setup.sh` — initial setup (networks, one-time prerequisites)
- `Makefile` — common workflows (`make up`, `make down`, `make ps`, etc.)
- `config/` — config files (notably `tailscale-*-serve.json` per service)
- `data/` — persistent volumes/state (gitignored)

## Architecture (Tailscale sidecar pattern)

Each externally-accessible app typically has two containers:

1. `<service>-tailscale` — runs Tailscale, terminates HTTPS, and proxies traffic to the app container.
2. `<service>` / `<service>-server` — the actual application, usually bound to `127.0.0.1` locally.

Services use two Docker networks:
- `homelab_frontend` — anything that needs Tailscale/external access
- `homelab_backend` — internal-only dependencies (e.g., databases)

Tailscale sidecars must become healthy before the app container starts.

## Prerequisites

- Docker / Docker Compose (OrbStack recommended on macOS)
- A Tailscale account
- A Tailscale auth key (tagged keys recommended)

Optional (depending on services):
- External SSD mounted at `/Volumes/Backup` (used for large media/backups)

## Configuration

Create a `.env` file alongside `compose.yml` (same directory) with at least:

- `TS_AUTHKEY` — your Tailscale auth key
- `TZ` — timezone (defaults to `Asia/Kolkata` if not set)

Other variables may be referenced by some services (e.g., Immich DB creds/version).

## First-time setup

1. Run the setup script:
   - `./setup.sh`

2. Start the stack:
   - `make up`

3. Check status:
   - `make ps`

## Common commands

- `make up` — start services
- `make down` — stop services
- `make restart` — restart services
- `make ps` — list services + ports
- `make help` — show available targets

## Accessing services

Services are meant to be accessed via their **Tailscale hostname** (HTTPS) rather than host ports.

Current hostnames (when enabled in `compose.yml`):
- `adguard` — AdGuard Home
- `immich` — Immich
- `beszel` — Beszel monitoring
- `stirling` — Stirling-PDF
- `vert` — VERT converter
- `zerobyte` — ZeroByte backups

In general:
- Preferred: `https://<hostname>.<your-tailnet-domain>/`
- Some services may also bind a loopback port for local-only access (`127.0.0.1:<port>`), but Tailscale is the intended entry point.

## Adding a new service

1. Add a Tailscale Serve config in `config/`:

- Create: `config/tailscale-<service>-serve.json`
- Proxy to the internal container + port.

2. Add two services to `compose.yml`:
- `<service>-tailscale` sidecar (Tailscale image, state volume under `data/tailscale/<service>`)
- `<service>-server` (or `<service>`) app container

3. Create persistent data directory:
- `data/<service>/`

Conventions used in this repo:
- Sidecar healthcheck uses `wget` against `http://localhost:9002/healthz`
- App containers use `curl`/`wget` healthchecks when possible
- Local ports bind to `127.0.0.1` only
- `security_opt: no-new-privileges:true`
- Resource limits configured per container

## Storage notes

- `./data/` (internal SSD): fast storage for state, DBs, caches
- `/Volumes/Backup/` (external SSD): large storage for media/backups (service-dependent)

## Troubleshooting

- If a service is unreachable over Tailscale:
  - Check the sidecar container logs and health
  - Verify `TS_AUTHKEY` is set and valid
  - Confirm the Serve config in `config/tailscale-<service>-serve.json` proxies to the correct container name and port
  - Ensure the relevant Docker networks exist (created by `setup.sh`)

## Security

This stack is designed to avoid exposing services directly to the LAN/WAN:
- Apps bind to loopback where applicable
- Tailscale provides authenticated, encrypted access
- Sidecars terminate HTTPS for services
