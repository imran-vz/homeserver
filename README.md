# Homeserver

Docker Compose-based homeserver running on macOS (OrbStack). Containerized services use **Tailscale sidecars**. Jellyfin runs directly on macOS and uses the Mac mini's Tailscale connection.

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

### Jellyfin

Jellyfin runs natively on the Mac mini and has no Tailscale sidecar.

- Tailscale: `http://imrans-mac-mini:8096`
- LAN fallback: `http://192.168.1.35:8096` (the current DHCP address)

Keep Tailscale connected on the Mac mini and viewing device when using the
Tailscale address. The former `https://jellyfin.tuna-mirzam.ts.net` sidecar
address is retired. Jellyfin media, settings, and saved sidecar state are preserved.

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

## Automatic startup, recovery, and free alerts

The host-side supervisor in `scripts/watchdog.py` runs outside Docker. Every
minute it checks the **OrbStack** Docker context and every service in this
Compose file (including missing/stopped containers). Healthy means running and,
when an image/container provides a healthcheck, `healthy`—not `starting`.

On failure it:

1. Requests `orbctl start` if Docker is unavailable, then waits for Docker.
2. Checks `/Volumes/Backup` is a real mount and Photos, Books, and Immich storage
   directories exist. It never creates substitute media directories.
3. Validates Compose, then runs **`docker compose stop --timeout 30` followed by
   `docker compose up -d --wait`**, preserving volumes and respecting dependency
   health ordering. Missing images are pulled by Compose; it does not update
   already-present images automatically. It does not use `restart` or `down`.
4. Allows at most **20 minutes per recovery attempt**, including engine startup,
   image loading and health waiting. Failed attempts are retried after a
   **5-minute cooldown**, rather than continuously cycling the stack.

An unhealthy container triggers recovery of the **whole stack**, so a failing
optional service can interrupt working apps. Fix persistent unhealthy checks
rather than allowing this to cycle indefinitely. The watchdog checks container
health, not end-to-end Tailscale access, and does not supervise host-native Jellyfin.
An unresponsive engine is asked to start but is **not forcibly killed**; if it
cannot recover within the deadline, monitoring reports failure and retries later.

### Install on this Mac

Requires Python 3 (`/usr/bin/python3` is available on this host). First check:

```sh
python3 -m unittest discover -s tests -v
python3 scripts/watchdog.py --check  # read-only; nonzero if anything is not healthy
```

Installing immediately enables recovery, including stopping an unhealthy stack:

```sh
python3 scripts/install-watchdog.py
```

The installer creates a user LaunchAgent with `KeepAlive` so macOS restarts the
watchdog if it exits. This starts **at login**, not before login. OrbStack's
`app.start_at_login` should remain enabled. After a power loss, FileVault/unlock
and login may still require a person; this setup does not bypass that boundary.

Logs rotate at `~/Library/Application Support/homeserver-watchdog/watchdog.log`.
To inspect the agent:

```sh
launchctl print gui/$(id -u)/com.imran.homeserver-watchdog
```

### Free off-host alerts (Healthchecks.io)

Create two checks on the Healthchecks.io hosted free plan (subject to its current
limits), choose an email or other supported notification integration, and copy
each check's secret HTTPS ping URL into:

`~/Library/Application Support/homeserver-watchdog/config.json`

```json
{
  "host_ping_url": "https://hc-ping.com/YOUR-HOST-CHECK-UUID",
  "stack_ping_url": "https://hc-ping.com/YOUR-STACK-CHECK-UUID"
}
```

- **Mac/watchdog:** period **1 minute**, grace **5 minutes**. An independent thread
  pings even while recovery waits. A missing heartbeat alerts if the Mac sleeps,
  loses power/network, logs out, or the watchdog stops. It cannot distinguish
  those causes; it does not prove the hardware itself is down.
- **Docker/apps:** period **1 minute**, grace **2 minutes**. Only a fully healthy
  stack sends success. An observed failure sends `/fail` immediately; missing
  heartbeats also detect a hung supervisor. Recovery sends success again.

Keep URLs private (they allow anyone holding them to spoof heartbeats). The config
is created with mode `0600`, outside the repository. Restart the agent after
editing it, and use each check's test-notification feature to verify delivery:

```sh
launchctl kickstart -k gui/$(id -u)/com.imran.homeserver-watchdog
```

Alert delivery requires configuring this external account; without URLs the
watchdog only logs locally. A service running on the Mac cannot independently
alert when the Mac loses power. The host heartbeat monitors the Mac session and
watchdog, **not an externally reachable HTTP endpoint**.

### Maintenance / intentional shutdown

Pause **before** stopping containers (do not pause during an active recovery;
first unload the agent if one is already running):

```sh
touch "$HOME/Library/Application Support/homeserver-watchdog/paused"
make down
# Later:
rm "$HOME/Library/Application Support/homeserver-watchdog/paused"
```

Pausing suppresses stack success heartbeats, so also pause the Docker/apps check
in Healthchecks.io during planned maintenance. The host heartbeat continues.
To disable completely:

```sh
launchctl bootout gui/$(id -u)/com.imran.homeserver-watchdog
rm "$HOME/Library/LaunchAgents/com.imran.homeserver-watchdog.plist"
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
