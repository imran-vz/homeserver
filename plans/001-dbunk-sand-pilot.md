# Plan 001: Pilot an ephemeral Linux ARM64 Sand runner for Dbunk

> **Executor instructions:** Read this whole plan, preserve the existing working-tree changes, and run every gate before proceeding. This plan authorizes preparation of implementation changes, not publication of repository changes or unattended host installation. Obtain explicit operator approval before installing software, configuring the GitHub App, starting VMs/services, or changing the live Dbunk workflow. Never print credentials. Update `plans/README.md` with progress and blocked prerequisites.
>
> **Drift check:** `git diff --stat e248485..HEAD -- compose.yml README.md Makefile .gitignore github-runner config/sand scripts/sand plans`
> Also inspect `git status --short`: the current runner implementation is uncommitted, so comparing HEAD alone is insufficient. Compare the current-state excerpts below with the live files. Do not reset, stash, overwrite, or commit unrelated work.

## Status

- Priority: P1
- Effort: M
- Risk: MED — new privileged host software and CI authentication; limited to one repository
- Depends on: none
- Category: migration
- Planned at: commit `e248485`, 2026-10-07; includes the uncommitted runner implementation observed during research
- Upstream researched: khoi/sand commit `4263d2ee1d60d7276592d14f82403dd73bb067b4`

## Why this matters

Dbunk currently runs CI in a persistent container with the same Docker daemon as the homeserver. A disposable Ubuntu VM can preserve Linux ARM64 workflow compatibility while separating job workspaces and Docker state from the homeserver. Prove single-job recycling and rollback before migrating any other repository. This is a pilot, not removal of the current runner implementation.

## Current state

- Host observed: Apple M4 Mac mini, 32 GB RAM, 10 CPU cores, macOS 26.6.2.
- `gh` and `docker` are available; `sand` and `tart` were not found in PATH. Recheck before installation.
- `README.md` describes OrbStack-hosted services and four repository-scoped runners.
- `compose.yml:11–32` defines shared runner configuration:

```yaml
x-github-runner-environment: &github-runner-environment
  RUNNER_NAME: homeserver
  RUNNER_LABELS: docker,orbstack,homeserver
  RUNNER_WORKDIR: _work
  DOCKER_HOST: unix:///var/run/docker.sock
```

- `compose.yml:258–267` defines Dbunk's listener:

```yaml
github-runner-dbunk:
  <<: *github-runner
  container_name: github-runner-dbunk
  environment:
    <<: *github-runner-environment
    RUNNER_URL: https://github.com/imran-vz/dbunk
    RUNNER_ROOT: /Users/imran/homeserver/data/github-runner-dbunk
  volumes:
    - ./data/github-runner-dbunk:/Users/imran/homeserver/data/github-runner-dbunk
    - /var/run/docker.sock:/var/run/docker.sock
```

- `github-runner/entrypoint.sh` persists runner distribution and registration and runs `./run.sh`. Do not reuse its registered state in the VM.
- `Makefile` uses explicit targets and a manually maintained help section. Existing `up` starts the entire Compose stack. Sand should be managed separately; do not attach it to `make up` or `make down`.
- `.gitignore` ignores `data/`, `*.log`, and **all Markdown except README.md**. Add a narrow exception for `plans/` when implementing so these handoff files can be tracked.
- The cached checkout at `data/github-runner-dbunk/_work/dbunk/dbunk/.github/workflows/ci.yml` is inspection evidence, NOT the authoritative location to edit.
- That workflow's `backend` job currently uses `[self-hosted, Linux, ARM64, homeserver, docker, orbstack]`, installs Rust with rustup, installs `build-essential pkg-config libssl-dev`, and runs:

```sh
cargo fmt -- --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo clippy --features isolated-profile --all-targets -- -D warnings
cargo test --features isolated-profile
```

- Its `native` job and release workflow use hosted macOS runners; leave these unchanged.
- No homeserver unit-test, lint, or typecheck suite was discovered. Validation is shell syntax, Compose parsing, Sand validation, and live acceptance jobs. Do not claim a runtime pass from static validation.

## Scope

### Homeserver tracked changes allowed

- `config/sand/dbunk.example.yml` (new nonsecret template)
- `scripts/sand/create-dbunk-base.sh` (optional, after verifying installed Tart commands)
- `scripts/sand/check-dbunk-guest.sh` (new guest preflight)
- `scripts/sand/dbunk-smoke.yml` (new script-provisioner smoke configuration)
- `README.md`, `Makefile`, `.gitignore`, `plans/README.md`
- `compose.yml`: only after acceptance, optionally assign **Dbunk only** `profiles: [legacy-dbunk-runner]` to prevent generic `make up` from restarting it. Preserve its definition and volumes for rollback.

### Separate Dbunk change, with explicit approval

In a clean, operator-approved checkout of `imran-vz/dbunk`, modify only `.github/workflows/ci.yml` to replace the backend runner label `orbstack` with `sand`. Native and release jobs stay hosted. An optional temporary `workflow_dispatch` smoke workflow is permitted if the operator approves its addition; remove it after acceptance or document its retained diagnostic purpose.

### Host runtime state (operator-approved, not Git)

- Local Tart base VM `homeserver-dbunk-base` under Tart's storage.
- `~/sand.yml` for the single Dbunk slot, mode 600. Do not overwrite an existing file without comparing and getting approval.
- A GitHub App PEM under `~/.config/sand/`, directory mode 700, key mode 600.
- `~/.cache/sand/actions-runner` for Sand's verified tarballs.

### Out of scope

Other runners/services, `.env` secrets, broad Compose lifecycle changes, shared host caches/mounts, OrbStack socket forwarding, Tailscale configuration, macOS runner migration, queue-based autoscaling, automatic DHCP changes, removal of old runner data, and publication/pushing without explicit permission.

## Git workflow

Use a dedicated branch if the operator permits it. There is substantial pre-existing uncommitted work: stage only agreed pilot changes. Match the repository's plain imperative commit messages, e.g. `Add Dbunk Sand runner pilot`. Keep the Dbunk workflow change in its own repository/commit. Do not edit files inside the runner's active work directory.

## Reference documentation

Read the current installed-version docs before running mutating commands:

- https://github.com/khoi/sand — requirements, install, service, lifecycle
- https://github.com/khoi/sand/blob/main/fixtures/sample_full_config.yml — supported configuration keys
- https://tart.run/quick-start/ and Linux VM/SSH documentation
- GitHub REST create-registration-token and delete-runner endpoints for repository-level runners

Sand's `organization` field acts as repository owner when `repository` is supplied. Its repository mode uses `/repos/<owner>/<repo>/installation` and runner APIs. GitHub App repository **Administration: read/write** is needed; organization runner permissions alone are not the correct personal-account setup.

## Steps

### 1. Establish the baseline and approvals

Run:

```sh
git status --short
sw_vers
uname -m
sysctl -n hw.memsize hw.ncpu
command -v gh docker
command -v sand tart || true
docker compose config --quiet
docker compose ps github-runner-dbunk
```

Expected: ARM64 Mac host, Compose parses successfully, existing runner status recorded. Do not emit full Compose config because interpolation can reveal secrets. Record an inventory of other services so acceptance can prove they were not stopped/recreated.

Get approval for Homebrew installation, the local base VM, and App creation. Check disk availability with `df -h "$HOME"`; VM image size must be checked before downloading. Stop if storage/headroom is insufficient.

### 2. Install and inspect Sand/Tart

After approval, follow Sand's install instructions:

```sh
brew trust khoi/sand openai/tools
brew tap khoi/sand
brew tap openai/tools
brew install sand
sand --help
tart --version
tart clone --help
tart run --help
sand doctor
```

Expected: tools installed; doctor exits 0 after resolving prerequisite issues. If `brew trust` is unavailable, consult installed Homebrew docs instead of blindly changing trust/security settings. Record actual tool versions and source revision: upstream can drift. Do not start a Homebrew service yet.

### 3. Prepare a clean Ubuntu ARM64 base

Confirm the documented `ghcr.io/cirruslabs/ubuntu` image exists and note the exact resolved version/digest; do not silently rely on a moving `latest` for repeatable rebuilds. Clone it to `homeserver-dbunk-base`, using the installed Tart CLI. Boot headlessly and obtain its address with `tart ip homeserver-dbunk-base`.

Use the documented image bootstrap SSH credentials privately, then establish host SSH key access. Do not print passwords or place personal SSH private keys in the guest. Confirm the installed Sand release supports the chosen SSH method; password authentication is documented, so a protected runtime config may be necessary. Use a VM-local account credential, not a personal password.

Inside the guest, install Git, curl, certificates, Python, build-essential, pkg-config, libssl-dev and the dependencies documented for the Linux ARM64 GitHub runner. Prefer a current supported Ubuntu release. Install Docker Engine and its Compose plugin using Docker's official Ubuntu instructions. Enable the Docker service; add the runner account to its docker group and verify membership after a fresh login.

Do not install/register an Actions listener in the base: Sand installs it. Do not install or configure Docker Desktop/OrbStack in the guest. Docker Engine in a Linux guest needs no nested virtualization.

Create `scripts/sand/check-dbunk-guest.sh`, matching `github-runner/entrypoint.sh`'s Bash style (`#!/usr/bin/env bash`, `set -Eeuo pipefail`). It must exit nonzero unless all of these succeed when executed as the intended guest runner user:

```sh
test "$(uname -s)" = Linux
test "$(uname -m)" = aarch64
test "$(id -u)" -ne 0
sudo -n true
git --version
python3 --version
pkg-config --exists openssl
docker info >/dev/null
docker compose version
test ! -e "$HOME/actions-runner/.runner"
test ! -e "$HOME/actions-runner/.credentials"
```

Verify shell syntax with `bash -n scripts/sand/check-dbunk-guest.sh`, run the script inside the guest successfully, and prove Docker containers can run with an ARM64 test image. Before shutting down, verify no repository checkout, runtime credentials, or host filesystem mounts exist. Shut down the base cleanly and confirm Tart reports it stopped. Re-run the script against a clone, not only the base.

### 4. Prove VM lifecycle without GitHub credentials

Create `scripts/sand/dbunk-smoke.yml` using one slot, the local base, the intended SSH configuration, `stopAfter: 1`, `ramGb: 4`, `cpuCores: 2`, no mounts, and the script provisioner. Its script should assert Linux/aarch64, non-root execution, functioning guest Docker, and write a sentinel file inside the guest.

Use a disposable clone test to prove a later clone of the stopped base lacks that sentinel. Retain the base; verify the ephemeral VM disappears after Sand exits.

**Gates:** `sand validate --config <smoke-config>` and `sand run --dry-run --config <smoke-config>` exit 0, then the approved live smoke exits 0. Keep runtime SSH secrets outside the tracked example and pass a private resolved smoke config when needed. Confirm `tart list` has no leftover smoke VM and still contains the stopped base.

### 5. Configure the GitHub App and Dbunk slot

The operator creates/installs a GitHub App restricted to `imran-vz/dbunk`, with repository Administration read/write, and saves its private key privately. Do not request the PEM or access tokens in chat. Verify registration and teardown API permissions without printing token responses.

Create the nonsecret template `config/sand/dbunk.example.yml` with this shape. `APP_ID` is an intentional placeholder that must be replaced with a numeric App ID in the protected runtime file before validation:

```yaml
runners:
  - name: dbunk
    vm:
      source:
        type: local
        name: homeserver-dbunk-base
      hardware:
        ramGb: 4
        cpuCores: 2
      cache:
        host: ~/.cache/sand/actions-runner
      run:
        noGraphics: true
        noClipboard: true
        nested: false
      ssh:
        user: admin
        port: 22
        # Resolve supported authentication privately in ~/sand.yml.
    provisioner:
      type: github
      config:
        appId: APP_ID
        organization: imran-vz
        repository: dbunk
        privateKeyPath: ~/.config/sand/dbunk-app.private-key.pem
        runnerName: homeserver-dbunk-sand
        extraLabels: [homeserver, docker]
```

Use Sand's default reachability health check initially. Do not copy the README's macOS `/Users/admin` process-healthcheck path into Ubuntu; a listener process check can also fail before provisioning finishes. Verify configuration against the actual installed release.

**Gates:** `sand validate --config "$HOME/sand.yml"` and `sand run --dry-run --config "$HOME/sand.yml"` exit 0. Confirm private runtime files have restrictive modes with `stat -f '%Lp %N' <paths>`; do not dump their contents. Confirm no sensitive runtime file is tracked (`git ls-files`).

### 6. Run Sand in the foreground and prove job recycling

With operator approval, run `sand run --config "$HOME/sand.yml"` in a supervised session. Keep the old Compose runner running during initial registration. The new runner must have default Linux/ARM64/self-hosted labels plus sand/homeserver/docker; do NOT add orbstack, so existing jobs cannot accidentally select it.

Inspect registration without exposing tokens:

```sh
gh api repos/imran-vz/dbunk/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
tart list
```

Expected: a distinct `homeserver-dbunk-sand-<suffix>` online runner and one guest slot. Sand keeps a configured slot online; this is not scale-to-zero.

Use an approved temporary workflow_dispatch smoke job targeting the new labels to print uname/id, exercise guest Docker, and create a sentinel in the guest home. On a second job assert the sentinel is absent. Record runner names and require them to differ. Test a failing job and cancellation as well, then verify the slot recovers without extra guests or offline registration buildup. No untrusted fork-PR execution during the pilot.

### 7. Switch only Dbunk's Linux backend job

In an authoritative clean Dbunk checkout, replace:

```yaml
runs-on: [self-hosted, Linux, ARM64, homeserver, docker, orbstack]
```

with:

```yaml
runs-on: [self-hosted, Linux, ARM64, homeserver, docker, sand]
```

Publish only with explicit approval. Trigger CI using the existing push/pull_request events; the existing CI file has no workflow_dispatch trigger, so `gh workflow run ci.yml` is not a valid baseline command. Observe it with `gh run list --repo imran-vz/dbunk --workflow ci.yml` and `gh run watch <run-id> --repo imran-vz/dbunk --exit-status`.

Expected: backend runs every existing fmt/clippy/test command successfully on the Sand runner. Hosted native job configuration remains unchanged; unrelated pre-existing hosted failures must be distinguished from pilot failures. Verify the next job gets a clean workspace/VM, App cleanup works, and homeserver services remain healthy. Record peak host memory pressure and guest/job duration. If 4 GB is insufficient, obtain approval before adjusting the single guest allocation.

### 8. Enable service operation and preserve rollback

Only after acceptance, use `brew services start sand` and verify `brew services list`, `sand doctor`, and GitHub runner status. The formula loads `~/sand.yml`; it is a user LaunchAgent starting at login, not a guaranteed pre-login boot daemon. Document host sleep/login expectations; do not change power settings silently.

Stop the old listener with `docker compose stop github-runner-dbunk`, not stack-wide down. To prevent `make up` resurrecting it, optionally put only that service behind `profiles: [legacy-dbunk-runner]`. Explicit service targeting supports rollback. Verify Compose still parses and other three runners remain enabled normally.

Add opt-in Makefile targets `sand-validate`, `sand-start`, `sand-stop`, and `sand-status`, updating `.PHONY` and help; start/stop act on Homebrew's service, not Compose. Document the runtime path, local base rebuild procedure, logs, acceptance evidence and rollback in README.md. Add narrow `.gitignore` exceptions `!plans/` and `!plans/**/*.md` so handoff files are visible.

**Gates:** `docker compose config --quiet`, `make help`, `make sand-validate`, `make sand-status`, and `git diff --check` exit 0. `docker compose config --services` must show all three nonpilot runners; if the profile is adopted, Dbunk appears when explicitly enabling `--profile legacy-dbunk-runner`. Record other homeserver service states to prove no unintended recreation.

## Rollback

1. Stop Sand (`brew services stop sand`, or interrupt the supervised foreground process). Verify its guest is cleaned up; use `sand destroy --config "$HOME/sand.yml"` only after verifying no active job and confirming the installed command's scope.
2. Revert the Dbunk backend labels to `orbstack` in the authoritative repository, with publication approval.
3. Start the preserved listener: `docker compose up -d github-runner-dbunk`.
4. Verify GitHub reports the old listener online and a backend job succeeds.
5. Leave old registration/work state intact throughout the pilot. Do not deregister it until an explicitly approved later cleanup.

## Test plan and done criteria

- [ ] Tracked shell scripts pass `bash -n`; `git diff --check` passes.
- [ ] `docker compose config --quiet` passes; no unrelated services or runner definitions changed.
- [ ] Private resolved Sand configuration validates; no App key, SSH credential, registration token, or interpolated secrets are in Git/logged acceptance evidence.
- [ ] Script smoke proves Linux ARM64, non-root execution, Docker functionality, and disposable guest cleanup.
- [ ] Two dispatched smoke jobs use different runner names; second sees no sentinel from the first.
- [ ] Failure/cancellation tests return to one healthy online slot without leaked guests/registrations.
- [ ] Dbunk's actual backend job passes its existing commands using sand labels; native/release routing unchanged.
- [ ] Homebrew service recovers after an approved stop/start; login limitation documented.
- [ ] Existing Dbunk container is stopped but preserved; other runners and services remain healthy.
- [ ] Rollback commands and image/tool provenance documented in README.md.
- [ ] Scope checked in both repositories, and plan index updated. Do not mark DONE with operator prerequisites outstanding.

## STOP conditions

- A current-state excerpt no longer matches, or unrelated work would be overwritten.
- The operator has not approved a required host/API/workflow mutation.
- The App cannot be restricted to Dbunk or lacks registration/deletion permissions.
- Tart Linux image access, SSH authentication, or runner dependency support differs from the assumptions.
- A proposed workaround requires exposing the OrbStack daemon, home directory, private key or writable shared host cache to a guest.
- The base contains credentials, an existing registration or repository work state.
- Unexpected active jobs prevent safely stopping a listener; no forced cancellation without approval.
- Host memory pressure/storage compromises other homeserver services.
- Validation fails twice, teardown leaves persistent leaks, or GitHub runner registrations accumulate.
- Untrusted public/fork pull requests would execute on the pilot without an explicit security decision.

## Maintenance notes

Rebuild the stopped base deliberately for Ubuntu/Docker/security updates. Record versions/digests and smoke-test every rebuild. Sand verifies and caches Actions runner tarballs; this is separate from Docker/build caches, which are discarded per guest. Never bake a registered listener into the base.

High VM churn can exhaust macOS DHCP leases; Sand documents a shorter lease setting, but modifying Internet Sharing is deferred until observed/approved. Limit this pilot to one slot. Additional slots and macOS jobs are separate decisions. Retain the old runner implementation until the whole migration is independently approved.
