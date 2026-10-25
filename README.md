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

## Development verification

This host no longer provides GitHub Actions runners. Sand, Tart, runner VMs,
credentials, caches, and the legacy container-runner definitions are retired.
Do not register listeners or provision CI guests as part of homeserver setup.

Project checks run on the device where development happens. Follow each project's
`docs/LOCAL_CHECKS.md` and report the checks run, results, and any unavailable
fixtures or platforms in its pull request. Removing CI does not remove the
requirement to verify changes locally.

For changes to this stack, validate without restarting unrelated services:

```sh
docker compose config --quiet
make help
bash -n setup.sh
```

## Accessing services

Services are meant to be accessed via their **Tailscale hostname** (HTTPS) rather than host ports.

Current hostnames (when enabled in `compose.yml`):
- `immich` — Immich
- `beszel` — Beszel monitoring
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

- `./data/` (internal SSD): fast storage for state, DBs, caches. Immich PostgreSQL stays here.
- `/Volumes/Backup/homeserver-data/immich/` (external SSD): the complete Immich storage tree, mounted at `/data` in Immich and `/mnt/immich` in ZeroByte.
- `/Volumes/Backup/Photos/` (external SSD): separate Immich external library, mounted at `/mnt/media/photos`.
- Mount the external SSD before starting services. The Immich storage mounts use `create_host_path: false` so a missing path fails instead of creating an empty directory. Do not create a replacement directory at this path while the SSD is disconnected.
- `/Volumes/Backup/` is currently ExFAT. Keep the PostgreSQL database on the internal APFS disk; maintain a separate backup of both the database and media (a copy on the same SSD is not protection against SSD failure).

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
