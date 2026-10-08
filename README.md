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

## Dbunk Sand runner

Dbunk's backend CI now runs in a fresh Linux ARM64 Tart VM managed by Sand.
The single slot has **8 GiB RAM / 2 CPUs** and is replaced after every job.
Native/release jobs remain hosted; the other three repository runners still use
OrbStack. The old Dbunk listener is **stopped**, with its Compose definition,
registration, work directory and volumes preserved for rollback.

Sand runs as a Homebrew user service at login, using `~/sand.yml` (600).
It keeps one slot online; this is not scale-to-zero. Plan and acceptance evidence:
[Plan 001](plans/001-dbunk-sand-pilot.md) and [plans/README.md](plans/README.md).

### Installed tools and provenance

The operator approved using the latest GitHub build after the stale Homebrew
formula failed. Sand was built from GitHub revision
`4263d2ee1d60d7276592d14f82403dd73bb067b4` using Swift 6.3.3; Tart **2.40.1** was
installed from its checksum-verified, signed GitHub release. `sshpass` **1.10**
is installed through Homebrew. Doctor, real GitHub jobs and service recovery pass.
Sand unit tests are blocked by the Command Line Tools SDK lacking `XCTest`.

Sand is now Homebrew-managed through the **local-only** tap
`homeserver/pilot/sand`, version `0.0.0-4263d2e`. Its formula is at
`/opt/homebrew/Library/Taps/homeserver/homebrew-pilot/Formula/sand.rb`; it builds
that exact GitHub commit with locked SwiftPM dependencies and two build workers,
uses the upstream service definition with a **120-second stop grace period**
for App cleanup, and depends on the installed sshpass.
Source archive SHA-256:
`6479f3e848385abe17ef2db3167e48049ec62a36da3c3916ef03f4e3096ce680`.
`brew test homeserver/pilot/sand`, doctor and `make sand-status` pass. The service
is running and registered at login; stop/start acceptance verified guest and
registration cleanup and a different healthy runner after restart.
The stale `khoi/sand` tap was not patched; do not install its older 1.4.0 release,
which uses a guest-writable runner cache.

Tart remains a direct GitHub install under
`~/.local/share/homeserver-tools/tart/2.40.1/tart.app`, linked in
`/opt/homebrew/bin/`; Homebrew will not update it. The original directly built
Sand binary is also retained under `~/.local/share/homeserver-tools/sand/<revision>/`
for tool rollback, but its PATH link now points to the Homebrew package.
Keep a backup of the nonsecret local formula, record checksums/revisions, and
re-run smoke acceptance before deliberately updating either tool. No custom
LaunchAgent or system/pre-login daemon was installed. This revision supports **password
SSH only**, not public-key login; use a VM-local password in protected runtime
config, never a personal password. Explicit empty password placeholders in the
tracked templates prevent fallback to the image's default password.

`doctor` checks `sand.yml` in its working directory, not automatically
`~/sand.yml`. Run it from `$HOME` once the protected runtime config exists;
explicit `--config` paths remain required for validation and foreground runs.

### Prepared base and smoke evidence

`homeserver-dbunk-base` is prepared and **stopped**, using Ubuntu 24.04 ARM64:

- Image: `ghcr.io/cirruslabs/ubuntu@sha256:e004f7f4f6765e2b3ae2738a95040c5d03867b667eb21a57ea0c3729aad640b6`
- Download: 3,061,426,611 bytes compressed; 20,000,000,000-byte logical disk.
  Downloads used `TART_NO_AUTO_PRUNE=1` to avoid pruning other Tart state.
- Stopped base defaults: 2 CPUs / 4 GiB; Sand config allocates each job clone
  2 CPUs / 8 GiB. Docker Engine 29.8.2, Compose 5.6.0, lld 18.1.3.
- Guest preflight passed on the base and disposable clones; no registered
  listener, repository checkout, host mount or runtime token/key is baked in.
- Sand private smoke validation and dry-run passed; the script provisioner
  completed with exit 0, and its ephemeral `dbunk-smoke` VM was deleted.
- A later clone passed preflight with no sentinel or Docker image carryover.
  All manual test clones were shut down and deleted; the base remains stopped.
- Docker smoke uses the pinned Alpine 3.22 image digest in
  `scripts/sand/dbunk-smoke.yml`. Full evidence is in `plans/README.md`.

Host-only files under `~/.config/sand/` are protected by directory mode 700:
`dbunk-vm-password` (VM-local password, 600), `dbunk-base-ssh` (dedicated private
SSH key, 600), `dbunk-base-ssh.pub`, `dbunk-known-hosts` (600),
resolved smoke configs including current `dbunk-smoke-lld.yml` (600) and
private smoke/registration/job logs (600).
Only the **public** SSH key was added to the base. Never print or commit the
password, private key or resolved config. The image's bootstrap password was
rotated; its temporary host password file was removed.

To repeat smoke, validate/dry-run then use the existing protected config:

```sh
sand validate --config "$HOME/.config/sand/dbunk-smoke-lld.yml"
sand run --dry-run --config "$HOME/.config/sand/dbunk-smoke-lld.yml"
sand run --config "$HOME/.config/sand/dbunk-smoke-lld.yml" \
  --log-file "$HOME/.config/sand/dbunk-smoke-lld.log"
tart list
```

The normal logger uses macOS unified logging; stdout redirection alone is not
acceptance evidence. Require the log's provisioner exit 0, script completion
and VM cleanup, not just the Sand process exit status. Inspect logs privately.

### Base preparation and rebuild

For a deliberate rebuild, inspect installed `sand`/`tart` help and run
`sand doctor`. Check free disk and host memory headroom, then resolve a supported
Ubuntu ARM64 image to an immutable registry digest and record its compressed and
expanded size **before** downloading. Clone it as `homeserver-dbunk-base` using
the verified Tart CLI; never overwrite an existing base without approval.

Boot headlessly with no host mounts. Establish SSH access privately using the
image's documented bootstrap account, then a VM-local credential supported by
Sand. Never copy a personal private key into the guest. Install Git, curl,
certificates, Python 3.11+, build-essential, pkg-config, libssl-dev,
**libdbus-1-dev** (Dbunk's Linux keyring dependency), **lld**, and Linux ARM64
Actions runner dependencies. Install Docker Engine/Compose from Docker's official
Ubuntu instructions. Configure guest-only `~/.cargo/config.toml` as follows to
avoid the GNU linker's high-memory path, keeping every CI check unchanged:

```toml
[target.aarch64-unknown-linux-gnu]
rustflags = ["-C", "link-arg=-fuse-ld=lld"]
```

Do not put registry credentials or build caches in the base. Enable Docker and add the non-root runner account to the Docker
group; test after a fresh login. Require passwordless sudo for that account.
Do **not** install or register a listener in the base.

Run `scripts/sand/check-dbunk-guest.sh` inside the guest and prove an ARM64 Docker
container runs. Inspect for repository workspaces, registration/runtime
credentials and host mounts; the base must contain none. Shut down cleanly and
verify Tart reports it stopped. Repeat preflight against a disposable clone.
For rebuilds, retain the old stopped base until the replacement passes all these
checks; record Ubuntu, Docker, image digest, tool versions and source revisions.
Docker/build caches are discarded per guest, not shared with the homeserver.

### Credential-free lifecycle gate

For a new runtime smoke config, copy `scripts/sand/dbunk-smoke.yml` to a private
mode-600 file outside this repo and resolve SSH authentication there. Keep the
ARM64 Docker test image pinned by digest (re-resolve deliberately on updates).
Run `sand validate` and `sand run --dry-run` against that private config first.
Only then run the one-slot foreground smoke. Require exit 0 and disappearance of
the ephemeral VM. A later disposable clone of the stopped base must not contain
`$HOME/.dbunk-sand-smoke-sentinel`. Delete only the test clone after confirming it
is stopped; retain the base. Do not treat static YAML checks as a runtime pass.

### GitHub App and private runtime config

The operator created App **5233889**, installed on Dbunk only. API verification
confirmed Administration write / Metadata read, and both registration-token
and remove-token endpoints returned HTTP 201 without printing their responses.
The temporary installation access token was revoked. A supervised foreground
run registered `homeserver-dbunk-sand-2323a` online with the intended labels.
Graceful interruption deregistered it through the App and deleted its guest;
actual runner DELETE cleanup is verified, including Homebrew service stop/start.

`~/sand.yml` now exists with mode 600 and passed `make sand-validate` (including
dry-run); doctor from `$HOME` passes. The PEM is 600 and its parent is 700.
Only one Sand GitHub listener is kept online. With operator approval, Dbunk's Actions
setting now requires approval for **all outside collaborators**
(`all_external_contributors`). No untrusted external/fork run will be approved
during the pilot. This protection depends on careful approval of the exact code;
runner labels alone are not a trust boundary. Keep this approval policy on
rollback unless a separate security decision authorizes changing it.

For future manual setup, create a GitHub App with **repository Administration: read/write**, installed on
**only `imran-vz/dbunk`**. Organization self-hosted-runner permissions alone are
not sufficient for this personal-account repository. Save the PEM privately at
`~/.config/sand/dbunk-app.private-key.pem` (directory 700, file 600).
Never paste the PEM, password or token into chat, tracked files or shell history.
Verify both repository runner-registration and deletion API permissions without
printing token responses before starting a listener.

Copy `config/sand/dbunk.example.yml` to `~/sand.yml` (600), replacing `APP_ID` with
a numeric App ID and resolving SSH authentication privately. Compare and obtain
approval before replacing an existing runtime file. Check modes with
`stat -f '%Lp %N'` and ensure runtime files are outside Git. The host-only verified
runner tarball cache is `~/.cache/sand/actions-runner`; no host directory/socket
is shared with a guest. Keep Sand's default reachability health check, not a
macOS listener path. `make sand-validate` runs validation and dry-run only.

### Live GitHub job evidence

The owner-only/manual-only diagnostic workflow passed four supervised scenarios:

| Scenario | Run ID | Runner suffix | Result |
|---|---|---|---|
| Seed sentinel | 37744057404 | `125cb` | Success |
| Clean second VM | 37744143328 | `69c04` | Success; no sentinel carryover |
| Intentional failure | 37744232422 | `7b161` | Expected failure; slot recovered |
| Operator cancellation | 37744321753 | `65ba8` | Cancelled; slot recovered |

All runner names were distinct (`homeserver-dbunk-sand-<suffix>`), and each job
was followed by exactly one healthy online replacement slot with no guest or
registration buildup. Supervised shutdown then removed the final slot and
registration. The stopped base and preserved legacy listener remain available.
Minimum sampled host memory-free percentage was 53% during these smoke tests
and concurrent legacy CI.

Temporary workflow commits in Dbunk: `52bda32` (add), `2a940cd` (remove).
The temporary workflow is no longer on main; its add/remove commits have no net
workflow change. The approved backend-only `orbstack` → `sand` label change was
published separately as **`1bceb4c`**. Native/release routing remains unchanged.

Actual CI **37745172897, attempt 4, passed every existing backend fmt/clippy/test
command**, including isolated-profile checks, on `homeserver-dbunk-sand-399a8`.
Hosted native checks also passed. Backend job duration: **13m 36s**; minimum
sampled host memory-free percentage: **78%**. A different clean replacement
runner came online after completion.

Acceptance fixes were confined to VM tooling/resources: add libdbus-1-dev,
obtain approval for 8 GiB, and use lld after GNU ld was SIGKILLed at link time.
Regression preflight/smoke rejects missing D-Bus/lld or the wrong linker config.
No Rust code or CI check was modified, suppressed or skipped in the passing run.

### Service operation

- `make sand-validate` checks the same `~/sand.yml` loaded by the service.
- The pinned formula's stop timeout must remain **120 seconds**. Initial default
  grace left an offline registration; after increasing it, stop/start completed
  full guest/App cleanup with no residual registrations.
- Check GitHub's runner is idle before stopping; never force-cancel a job for
  maintenance. A configured slot is named `homeserver-dbunk-sand-<suffix>` with
  Linux/ARM64/self-hosted/sand/homeserver/docker labels, **not orbstack**.
- Dbunk is public. Keep all-outside-collaborator approval requirements and never
  approve untrusted code during this pilot. Any later workflow publication still
  requires confirmation.

- `make sand-start` / `make sand-stop` use Homebrew, independent of Compose.
- `make sand-status` runs doctor and reports the Homebrew service.
- The service loads `~/sand.yml`; the user LaunchAgent starts at login, not
  guaranteed pre-login boot. Keep the host logged in and awake during jobs;
  do not change sleep/power settings silently.
- Logs: `~/Library/Logs/sand.log` for the planned formula, plus
  `log show --predicate 'subsystem == "sand"' --last 1h --info`.
  Treat logs as potentially sensitive; do not publish raw logs/configs.
- The old listener is stopped without a Compose profile change to preserve the
  user's uncommitted runner implementation. **Generic `make up` will start it;
  `make restart` also starts stopped services, and `make recreate` starts or
  recreates every service, losing the original container identities.** After any
  of these broad lifecycle targets, check that `github-runner-dbunk` is idle,
  then stop only it with `docker compose stop github-runner-dbunk`. Its orbstack
  label cannot select Sand jobs. Never use stack-wide down for this.

### Recovery after an unclean reboot

The pinned Sand revision does **not** automatically reclaim a stale named VM.
A host reboot during this pilot left a stopped `dbunk` VM and offline registration;
the login service then failed repeatedly with `VM "dbunk" already exists`.
Manual scoped cleanup and restart restored a fresh online slot.

1. Stop the restart loop with `make sand-stop`.
2. Inspect `tart list` and GitHub runner name/status/busy. Obtain approval before
   cleanup. Require the exact pilot registration to be offline/idle and the
   `dbunk` VM stopped; refuse cleanup if a job or guest is active.
3. Delete **only that verified pilot registration ID** through GitHub's runner
   API, then `tart delete dbunk`. Never delete `homeserver-dbunk-base`, the legacy
   `homeserver` registration, or unrelated VMs. Do not use `--overwrite`.
4. `make sand-start`; require exactly one new online/idle pilot registration,
   no old offline pilot entry, one running `dbunk` guest and a stopped base.

Graceful service stop/start with the 120-second grace period passes. Crash/reboot
recovery remains a **manual pilot limitation**, not an unattended availability
claim. No reboot, power or sleep policy was changed by the agent.

### Rollback

1. Stop Sand with `make sand-stop`, or interrupt its supervised foreground run.
   Check guest cleanup; use `sand destroy` only after verifying command scope,
   checking no active job and obtaining approval.
2. Restore Dbunk's backend `orbstack` label in the authoritative repository;
   obtain confirmation before publishing the workflow revert.
3. Run `docker compose up -d github-runner-dbunk` and verify it is online in
   GitHub and successfully executes a backend job.
4. Keep old registration/work state until a separately approved cleanup.

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
