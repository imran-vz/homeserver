# Implementation plans

Prepared on 2026-10-07 against homeserver commit `e248485` plus the existing uncommitted runner setup. Read each plan completely before executing. Preserve all unrelated working-tree changes.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| [001](001-dbunk-sand-pilot.md) | Pilot an ephemeral Linux ARM64 Sand runner for Dbunk | P1 | M | — | DONE — backend CI/service acceptance passed; legacy preserved; reviewed; manual unclean-reboot recovery documented |

Status values: TODO, IN PROGRESS, DONE, BLOCKED, REJECTED. Record acceptance evidence and blockers, never secret values.

## Dependency notes

- Dbunk is the only pilot. Other repository runners and all homeserver application services remain unchanged.
- Prove credential-free VM lifecycle before creating a live GitHub listener.
- Prove real job execution and clean VM replacement before stopping the existing Dbunk listener.
- The Dbunk workflow change belongs in the Dbunk repository, not this repository's cached runner checkout.

## Findings considered and rejected

- Switch current Linux workflows to macOS guests: rejected for the pilot because existing workflows use apt and Linux ARM64 labels.
- Forward OrbStack's Docker socket into the guest: rejected because it defeats the CI/homeserver isolation goal.
- Remove the old listener immediately: rejected because it eliminates the straightforward rollback path.
- Modify host DHCP/power settings preemptively: deferred pending evidence and explicit approval.

## Repository note

Added narrow `.gitignore` exceptions for `plans/` during implementation. Pre-existing changes in `.env.example`, `README.md`, `compose.yml`, `setup.sh`, deleted Tailscale configs and untracked `github-runner/` remain intact. The pilot only appends documentation to the existing README; no runner definitions or state were changed.

## Plan 001 execution evidence — 2026-10-07

**Current status: DONE — runtime acceptance and independent review complete.**
Backend CI passes on 8 GiB / 2 CPU Sand guests; the Homebrew login service is
running with one healthy online slot. Old listener is stopped with state preserved.
Host installation, base preparation, App setup, workflow publication and the
8 GiB resume were explicitly approved and completed. The evidence below is
chronological: early blocked/stopped states are historical, not current status.
No private credential values are recorded. An unclean host reboot during the
pause required scoped manual recovery; this limitation is documented below.

### Baseline and preservation

- Drift check against `e248485..HEAD` was empty; live runner excerpts match the plan.
- macOS 26.6.2 (25G83), Apple Silicon ARM64, 32 GiB RAM, 10 CPUs.
- Home filesystem: 94 GiB available. Image size/digest and peak memory pressure
  remain unchecked because installation stopped before the image gate.
- `gh` and `docker` available; neither `sand` nor `tart` installed before or after
  the failed installation. No existing `~/sand.yml` was found or overwritten.
- All 17 Compose containers remain running; the 13 application/sidecar containers
  report healthy and all four runner listeners remain up. All start timestamps
  predate this execution (2026-10-04); no stack stop/recreation was performed.
- Preserved Dbunk container ID prefix `6867d7cbc26b`, started
  `2026-10-04T08:21:39.896101875Z`. Other runner ID prefixes:
  kaalam `bb4f219ba6e8`, kadai `f3e436a3dd1f`, synco `140581cb27e1`.
- No Compose legacy profile was added: that is an **after-acceptance** step.

### Host installation attempt and provenance

- Homebrew 7.0.8; automatic update advanced Homebrew revision
  `1b0b73c84b` → `c9862112a6`. No unrelated formula/cask upgrade was requested.
- Trusted/tapped `khoi/sand` and `openai/tools` following current upstream docs.
  Tap revisions: `2d0e5565ce09369aae7315f33bf68ea9eb340042` and
  `0a94c58aa3807449db5071bc86be4568b5a0b0a9` respectively.
- Current upstream Sand main still resolves to the plan's research revision
  `4263d2ee1d60d7276592d14f82403dd73bb067b4`.
- `brew install sand` failed: its formula actually packages **1.4.0** and depends
  on `cirruslabs/cli/tart`, not the README's `openai/tools/tart`.
- Tried the formula's declared dependency tap (trusted `cirruslabs/cli`).
  `brew tap cirruslabs/cli` failed Homebrew syntax validation: `tart.rb` and
  `softnet.rb` combine disabled `depends_on :macos` / `depends_on macos:` forms;
  the `chamber` cask also lacks required platform stanzas. The failed tap was
  removed by Homebrew; its trust entry may remain. No tap patches were made.
- Inspected the packaged v1.4.0 README/sample and formula. This release's cache
  is guest-writable and unsupported on the default Ubuntu image; the formula
  lacks a service definition. These violate the required verified host-only
  cache and planned service lifecycle. Do not install 1.4.0 for this pilot.
- Stopped rather than retrying installation, substituting HEAD, bypassing
  Homebrew checks or installing an unapproved custom LaunchAgent.

### Initial prepared changes and validation (before GitHub installation)

- Added nonsecret planned-release template `config/sand/dbunk.example.yml`,
  one-slot script smoke `scripts/sand/dbunk-smoke.yml`, executable guest preflight
  `scripts/sand/check-dbunk-guest.sh`, opt-in Make targets and README procedures.
- PASS: `bash -n` for guest preflight, existing runner entrypoint and setup script.
- PASS: YAML parsing with Ruby Psych for both new YAML templates. This is **not**
  Sand schema/runtime validation; templates intentionally lack private SSH auth
  and the App ID is a placeholder.
- PASS: `docker compose config --quiet`, `make help`, `git diff --check`.
- PASS: Compose service enumeration includes all four existing runner services.
- BLOCKED: `make sand-validate` and `make sand-status` fail because Sand is absent.
- NOT RUN: guest execution, pinned image download, Docker container smoke,
  disposable VM cleanup, App permission tests, job recycling/failure/cancellation,
  actual Dbunk backend CI, service recovery and memory/duration measurements.
- No repository typecheck/lint/unit-test suite exists. Shell syntax/YAML parsing
  are static checks only. No fresh-subagent review tool is available in this
  session; independent review remains pending before final implementation commit.
- No commit or push was made while gates remain blocked; unrelated work remains
  unstaged. No private runtime files were created in this repository.

### Resume gates

1. DONE for foreground tools: operator approved latest GitHub source; pinned
   build installed and doctor passes. Source includes the planned compatible
   service formula, but Homebrew service packaging is still pending. Resolve
   upstream test SDK availability before claiming a full unit-test pass.
2. DONE: pinned image size/digest checked, clean stopped base prepared,
   preflight passed on base and clones, and credential-free lifecycle smoke passed.
3. DONE for setup/config: operator installed App 5233889 restricted to Dbunk
   with repository Administration read/write. Runtime modes, registration-token
   and remove-token APIs verified privately; actual DELETE awaits pilot teardown.
   DONE: operator approved all-outside-collaborator workflow approval requirements;
   the setting is verified before listener start. No untrusted runs are approved.
4. DONE: protected runtime config validation, supervised registration/teardown,
   two-job clean-VM recycling, failure and cancellation recovery; approved
   temporary workflow published, tested, then removed.
5. DONE: explicitly approved backend-only label change published as 1bceb4c.
6. DONE: approved RAM increase, corrected base tooling, full backend/native CI,
   clean replacement, Homebrew service stop/start cleanup/recovery, and idle legacy
   listener stop with state preserved. Independent final review and focused
   documentation fix passed; final static/runtime gates passed.

## GitHub installation follow-up — 2026-10-07

Operator instruction: use GitHub to install the latest build.

- GitHub's latest Sand release remains v1.4.0; instead cloned and built latest
  main, detached at `4263d2ee1d60d7276592d14f82403dd73bb067b4`. Read that source's
  instructions, package, formula, SSH client and cache/config implementation.
  Work/build directory: `/tmp/homeserver-sand-install/source` (not project source).
- PASS: `swift build --disable-sandbox -c release` with Swift 6.3.3. Build used
  committed `Package.resolved`; source working tree remains clean.
- Installed Sand at
  `~/.local/share/homeserver-tools/sand/4263d2ee1d60d7276592d14f82403dd73bb067b4/sand`.
  Binary SHA-256:
  `2fdf330a3589e97c1018b5bc5d4d0e85dda73aef56b9a79970be3b340351c87c`.
- Downloaded Tart 2.40.1 from `openai/tart` GitHub release. Archive SHA-256:
  `363e2701154a8155cbc1bb6d845430c9b42697d2a186bc49574471ca2877db46`.
  Matched GitHub asset digest and release checksum file. PASS:
  `codesign --verify --deep --strict`; signed by Cirrus Labs, Inc., team
  `9M2P8L4D89`. Installed complete bundle at
  `~/.local/share/homeserver-tools/tart/2.40.1/tart.app`.
- Added `/opt/homebrew/bin/sand` and `/opt/homebrew/bin/tart` symlinks after
  verifying neither path already existed. These are direct installs, not
  Homebrew packages. Deliberate future upgrades must preserve this provenance.
- Installed sshpass 1.10 via Homebrew. Homebrew automatically attempted cleanup
  of an older Tailscale Cellar directory (reported a permission warning) and
  removed cached Chrome/Raycast downloads and Ruby/bootsnap caches. No explicit
  unrelated package upgrade or live service restart was requested.
- PASS: Sand help, Tart version, clone/run help, `tart list` (empty), and
  `sand doctor` (dependencies and Tart health). No runtime Sand config exists,
  so doctor does **not** prove App/SSH configuration or a guest works.
- BLOCKED: `swift test --disable-sandbox -c release` cannot compile upstream
  tests: `no such module 'XCTest'`. Active developer directory is
  `/Library/Developer/CommandLineTools`; no Xcode installation/switch was attempted.
- Source formula has a Homebrew service definition; manual binary installation
  does not register it. Prepared service targets cannot work until service
  packaging is resolved after foreground acceptance. No LaunchAgent was created.
- This revision only supports password SSH and defaults an omitted password.
  Added explicit empty password placeholders to both tracked templates so they
  fail validation until authentication is resolved privately.
- `doctor` uses `sand.yml` relative to the current directory; run it from `$HOME`
  once private `~/sand.yml` exists. The successful check above had no config.
- PASS: Compose quiet parsing and whitespace checks after installation. Existing
  runner/services remain running. No VM download, boot, service start, GitHub
  App mutation, workflow change, commit or publication was performed.
- Those base/clone smoke gates were completed in the follow-up below. The
  mandatory manual GitHub App/key pause is now reached; GitHub acceptance remains pending.

## Base preparation and credential-free acceptance — 2026-10-07

Operator instruction: go ahead with the remaining preparation. The original
manual App/key and workflow publication boundaries remain in force.

### Image, provisioning and secret handling

- Fresh baseline: all 17 Compose containers still running, applications healthy;
  no local Tart VM existed. Disk had 93 GiB free; memory-pressure snapshot showed
  74% system-wide free memory (not a peak measurement).
- Resolved public GHCR Ubuntu **24.04 ARM64** metadata before downloading:
  `ghcr.io/cirruslabs/ubuntu@sha256:e004f7f4f6765e2b3ae2738a95040c5d03867b667eb21a57ea0c3729aad640b6`.
  Uploaded `2026-10-03T09:53:38Z`; compressed image size **3,061,426,611 bytes**,
  logical disk **20,000,000,000 bytes**. Image config confirms Linux/arm64.
- Initial download reached 15% before a command timeout interrupted it. Retried
  the **same immutable digest** in a supervised background download, which
  completed. `TART_NO_AUTO_PRUNE=1` prevented automatic pruning of other state.
- Created `homeserver-dbunk-base`, configured **2 CPUs / 4096 MiB**, booted
  headlessly without clipboard/audio or directory shares. Ubuntu 24.04 confirmed.
- Created protected `~/.config/sand/` (700) and `dbunk-vm-password` (600) with a
  generated VM-local password. Used the documented bootstrap credential
  privately, changed the guest account password over SSH stdin, and removed the
  temporary bootstrap password file. No credential was printed or put in Git.
- Created a dedicated host `dbunk-base-ssh` private key (600); only its public key
  was added to guest `authorized_keys`. Host private keys were not copied in.
  Private `dbunk-known-hosts` is 600. Sand uses password auth from protected config.
- Read Docker's official Ubuntu apt instructions and the Actions runner Linux
  dependency script. Installed Git, curl, certificates, Python, build-essential,
  pkg-config, libssl-dev, libkrb5-3, zlib1g, liblttng-ust1t64, libssl3t64 and
  libicu74. Installed Docker from its official signed Ubuntu apt repository,
  enabled its service and added admin to its docker group.
- Verified using a fresh login: admin UID 1000 (non-root), passwordless sudo,
  **Docker 29.8.2**, **Compose 5.6.0**, Git 2.43.0, Python 3.12.3 and OpenSSL
  pkg-config availability. Ubuntu kernel `7.0.0-38-generic`.
- ARM64 container execution passed. Docker resolved Alpine 3.22 to
  `sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8`;
  this digest is now pinned in the tracked smoke template. Removed its image
  from the base so later guests have no inherited Docker/build cache.
- Clean-base inspection passed: no repository checkout, listener registration,
  personal private key, runtime GitHub/registry credential, host filesystem
  mount or Docker container/image. No Actions runner was installed in the base.
  Shut down from inside the guest and verified Tart reports the base stopped.

### Clone and Sand lifecycle gates

- PASS: `scripts/sand/check-dbunk-guest.sh` on the base and disposable preflight
  clone. Added an explicit no-smoke-sentinel assertion to the preflight script.
- Shut down preflight clone cleanly, verified stopped, then deleted **only** that
  disposable clone. Base kept unchanged.
- Resolved `~/.config/sand/dbunk-smoke.yml` privately (600), using the VM-local
  password and the tracked one-slot config: stopAfter 1, 4 GiB, 2 CPUs, no mounts.
- PASS: `sand validate --config <private-smoke>` and `sand run --dry-run`.
- PASS: live Sand smoke; repeated with explicit private `--log-file` because
  ordinary stdout redirection produces no unified-log evidence. Sand's process
  exit status alone was not used to claim script completion.
- Logged acceptance run: start **17:59:31.336Z**, provisioner command exit 0 and
  script completion **17:59:43.280Z**, ephemeral `dbunk-smoke` deletion/cleanup
  **17:59:43.437Z** (about 12.1 seconds). Log confirms Linux/aarch64/non-root
  assertions, guest Docker execution and sentinel creation, with **no mounts**.
  Private `~/.config/sand/dbunk-smoke.log` is 600. Credentials were redacted before
  inspecting any copied log evidence; raw config was never dumped.
- PASS: later disposable clone of the stopped base ran the updated fail-fast
  preflight and explicitly verified **no sentinel and no Docker image carryover**.
  Shut down, verified stopped and deleted the clone.
- PASS: final Tart inventory contains **only** the stopped local base and its
  stopped immutable OCI source. No smoke/manual-test guest or live Sand slot
  remains. Disk snapshot after smoke: 86 GiB available; memory snapshot 80% free.
  Peak memory during actual GitHub CI still needs measuring.

### Boundaries and next operator action

- Read authoritative CI via GitHub API (inspection only, no cached checkout edit).
  Dbunk is **public**, default branch main; CI triggers on push to main and PRs
  to main, backend still targets orbstack, native still hosted macOS. No workflow
  file or repository setting was edited/published.
- **STOP: operator must create/install the Dbunk-only GitHub App**, granting
  repository Administration read/write, and save its PEM privately at
  `~/.config/sand/dbunk-app.private-key.pem` (600; parent already 700).
  The numeric App ID is nonsecret; PEM/tokens/passwords must not be sent in chat.
- Before publishing workflow changes, agree on prevention of untrusted fork-PR
  execution. Generic approval to continue preparation is not an explicit decision
  to run public fork code on this host. No untrusted job was executed.
- After operator confirms App setup: privately resolve `~/sand.yml`, verify
  registration/deletion permissions without printing token responses, then run
  supervised GitHub registration and approved two-job/failure/cancellation smoke.
  Obtain explicit confirmation for any published smoke/backend workflow diff.
- GitHub job recycling, actual backend CI, service packaging/start-stop acceptance,
  independent review and final pilot-only commit remain pending. The old Dbunk
  listener stays running and its state/Compose definition is preserved.
- No `~/sand.yml`, App key/token or Homebrew/LaunchAgent service was created.
  No commit/push was made. Static shell/YAML/Compose and whitespace checks pass;
  upstream XCTest SDK blocker remains unchanged.
- Final verification: all 17 container IDs and start timestamps match the earlier
  recorded inventory; services are still healthy/running. GitHub reports the old
  `homeserver` Dbunk runner **online and idle**, with only the existing
  self-hosted/Linux/ARM64/docker/orbstack/homeserver labels. No Sand GitHub runner
  exists yet. No PEM/password/private-key/log path is tracked by Git.

## Manual App completion and API/config gates — 2026-10-08

- Operator supplied nonsecret App ID **5233889**, confirmed private key mode 600
  and installation. Screenshot shows installation **169148557**, Administration
  read/write, Metadata read and selected repository `imran-vz/dbunk` only.
- Independently verified App identity, exact permissions and single-repository
  selection with the App JWT/installation APIs. PEM/JWT/access/registration/
  removal tokens were handled only in memory or protected local files; no API
  response containing a credential was printed or stored in acceptance evidence.
- PASS: repository registration-token and remove-token POSTs both returned HTTP
  201. Tokens were discarded; temporary installation access token revoked via
  DELETE `/installation/token` (HTTP 204). This is **not** yet proof of runner
  DELETE cleanup, which requires an actual pilot registration.
- Created protected `~/sand.yml` with numeric App ID and private VM-local SSH
  password. Existing file check and exclusive creation prevented overwrite.
- PASS: `make sand-validate` including dry-run; doctor from `$HOME`; runtime
  config and PEM modes 600; App directory mode 700; Git tracks none of these
  private files. No configuration contents or key material were dumped.
- Existing old runner `homeserver` remains online/idle with orbstack labels.
  Base remains stopped; no Sand GitHub listener was started.
- Read-only query shows Dbunk's external PR approval policy is
  **`first_time_contributors`**, insufficient to gate previously contributing
  external authors. A fork can change workflow labels, so absence of orbstack on
  the new runner is **not** a security boundary against fork code targeting it.
- **STOP before listener start:** obtain explicit approval for requiring review
  of **all outside collaborators**, with no untrusted external/fork execution
  approved during the pilot. No repository setting was changed automatically.
- At this stage no workflow change was prepared/published, no service started,
  and no old registration removed. Publication and final acceptance remained pending.

## External-approval policy and supervised registration — 2026-10-08

- Operator explicitly approved changing Dbunk's approval policy and keeping
  untrusted external/fork jobs unapproved throughout the pilot.
- Updated the Actions repository setting via PUT and read it back:
  **`all_external_contributors`**. This is a repository setting mutation, not
  workflow publication. Do not weaken it automatically during rollback.
- Verified recent workflow runs are completed and none is an untrusted active
  fork job before registration. Old runner still online/idle.
- Confirmed Sand's GitHub provisioner passes its registration token to the
  logger's redaction mechanism before running the foreground test. Protected
  logs were created mode 600; no raw token/SSH password was printed.
- Ran Sand under a supervised process, polled GitHub, and verified new runner
  **`homeserver-dbunk-sand-2323a`** online/idle with exactly
  ARM64/Linux/docker/homeserver/sand/self-hosted labels, **no orbstack**.
- After confirming idle again, sent SIGINT to that supervised process. Sand
  stopped gracefully; App cleanup log records deregistration and guest deletion
  at **2026-10-08T07:22:37.510Z**. GitHub API confirmed no pilot registration
  remained. This proves actual App-authorized runner DELETE cleanup.
- Tart inventory again contains only the stopped local base and immutable OCI
  source. Old runner remains online/idle. No new listener/service is left running.
- Verified protected log uses `[REDACTED]` for all logged registration-token
  arguments and contains no VM-local SSH password. No sensitive config/key/log
  contents were published; scope and whitespace checks pass.
- Prepared an **unpublished draft only** at
  `/tmp/homeserver-dbunk-sand-pilot-smoke.yml`, proposed destination
  `.github/workflows/sand-pilot.yml` in the authoritative Dbunk repository.
  It is manual-dispatch-only, owner-actor-only, has no token permissions, no
  checkout or repository code, and four scenarios: seed, clean, intentional
  failure and operator cancellation. It targets only the Sand label set.
- **STOP for explicit publication confirmation** before adding/pushing that
  temporary smoke workflow. It must be present on Dbunk's default branch for
  workflow_dispatch discovery. Publishing it may trigger existing main-push CI
  on the old runner; backend/native routing remains unchanged at this stage.
- After approved publication: restart supervised Sand, run all four scenarios,
  confirm distinct runner names/no sentinel carryover and one-slot recovery with
  no leaked guests/registrations. Only then request backend label-change
  publication approval. Service packaging/activation and final review/commit
  remain later acceptance gates.

## Approved smoke publication and live job acceptance — 2026-10-08

Operator explicitly approved publishing the temporary workflow to Dbunk main,
testing it and removing it. Backend switching remains separately gated.

### Publication and scope

- Created clean authoritative checkout `/tmp/homeserver-dbunk-pilot` from
  `imran-vz/dbunk`, starting at **04be082**; read its repository instructions.
  No cached runner worktree was edited.
- YAML parsing and all embedded Bash syntax passed for the owner-actor-only,
  manual-dispatch-only workflow; no checkout, repository code, secrets or token
  permissions were requested by it.
- Committed only `.github/workflows/sand-pilot.yml` as
  **52bda3296acb23fd0afe12695f817d15a54c3b2a**,
  `Add temporary Sand pilot smoke workflow`.
- HTTPS push was rejected because the existing OAuth token lacks `workflow`
  scope. Confirmed existing SSH authentication belongs to imran-vz and published
  using SSH, without changing credentials/App permissions or force-pushing.
- GitHub validated/discovered the workflow as active, ID **378192680**.
  Publication also triggered ordinary legacy CI run **37743806232**.
- After acceptance, fetched main and removed only that temporary file in commit
  **2a940cd17033d8640fb312833c2102e46c7b967a**,
  `Remove temporary Sand pilot smoke workflow`, then published via SSH.
  Net repository diff from 04be082 through 2a940cd is empty.
- Cleanup push triggered ordinary CI run **37744580699**. At evidence capture,
  add-commit CI was still in progress and cleanup CI pending. Neither is claimed
  as a Sand backend pass; existing CI concurrency may supersede an earlier run.
  No unrelated run was manually cancelled or stopped.

### Live acceptance results

Each workflow job first asserted Linux/aarch64, non-root UID, no sentinel in
home, working Docker/Compose, and pinned ARM64 container execution. Sand ran
supervised; no untrusted external/fork job was approved or executed.

| Scenario | GitHub run | Runner | UTC start → finish | Conclusion |
|---|---|---|---|---|
| seed | 37744057404 | homeserver-dbunk-sand-125cb | 07:32:29 → 07:32:42 | success |
| clean | 37744143328 | homeserver-dbunk-sand-69c04 | 07:33:18 → 07:33:31 | success; no sentinel |
| failure | 37744232422 | homeserver-dbunk-sand-7b161 | 07:34:12 → 07:34:29 | expected failure (exit 42) |
| cancel | 37744321753 | homeserver-dbunk-sand-65ba8 | 07:35:03 → 07:36:27 | operator-authorized cancellation |

- PASS: first and second jobs use distinct registrations; second sees no marker
  created by first. All four job runner names are distinct.
- PASS: after **each** scenario, including failure/cancellation, exactly one
  online idle healthy replacement slot appeared with correct labels. Local Tart
  inventory was exactly stopped base + one running `dbunk` guest; no extra guest
  or offline pilot registration accumulation.
- After cancellation, recovered slot **homeserver-dbunk-sand-2f353** was online
  and idle before supervised SIGINT. Final cleanup verification found no pilot
  registration or ephemeral guest. Base remains stopped; old listener preserved.
- Minimum sampled system memory-free percentage: **53%** during the smoke tests
  and concurrent legacy CI. This is a sampled indicator, not a claim of peak
  backend-on-Sand memory pressure. Guest allocation stayed at 4 GiB / 2 CPUs.
- Nonsecret evidence JSON is protected at
  `~/.config/sand/dbunk-job-acceptance.json`; runtime logs are mode 600 under the
  same mode-700 directory. No config/key/token contents were exposed.
- All 17 homeserver containers remain running/healthy as before. Old Dbunk
  runner is online and **busy with ordinary CI**; it was not stopped or forcibly
  cancelled. Other runners/Compose definitions/volumes remain untouched.

### Next publication boundary

- Prepared **one local, uncommitted line** in authoritative
  `.github/workflows/ci.yml`: backend label `orbstack` → `sand`. No other line,
  native job or release workflow changed. The diff is not yet published.
- **STOP for explicit backend-switch publication confirmation.** After approval,
  start supervised Sand, publish that line only, and observe every existing
  backend fmt/clippy/test command on Sand plus clean replacement and App cleanup.
- Actual backend CI, service packaging/login recovery, idle legacy listener stop,
  independent review and final homeserver pilot-only commit remain pending.
  At that stage no Homebrew/LaunchAgent Sand service had been created or enabled.

## Backend publication, base correction and resource stop — 2026-10-08

Operator explicitly approved publishing the backend switch and proceeding with
actual CI/service acceptance. All application code/check commands stay unchanged.

### Published switch and first attempt

- Committed/published **1bceb4c5626a1ce4bb9e8c40b5409a6044bacf83**,
  `Run Dbunk backend CI on Sand`, in the authoritative checkout. Diff is exactly
  one backend runner-label replacement; native/release definitions unchanged.
- Started supervised Sand; runner **homeserver-dbunk-sand-95556** selected for
  actual push-triggered CI **37745172897**, backend job **113205152612**.
- Attempt 1: setup, rustup, stable toolchain, cache restore, system dependencies
  and fmt passed. First Clippy failed: `libdbus-sys v0.2.7` could not find
  **dbus-1.pc**; later commands skipped. This was a base dependency omission,
  not waived/suppressed and not claimed pre-existing.
- Tight repro: guest command
  `pkg-config --libs --cflags dbus-1 'dbus-1 >= 1.6'` exited 1 with missing package.
  Package query confirmed **libdbus-1-dev absent**; default pkg-config search
  paths were correct. Backend keyring uses `sync-secret-service` on Linux.
- Added the real dependency probe to tracked preflight and smoke **before** the
  fix; updated preflight failed on the uncorrected base as expected.
- Gracefully stopped the idle recycled slot; verified GitHub/VM cleanup before
  booting the base. Installed only **libdbus-1-dev 1.14.10-4ubuntu4.1** (200 kB
  download, about 1.1 MB installed). No Rust/workflow command changes needed.
- PASS: exact pkg-config repro, updated base preflight, clean-base inspection,
  clean shutdown, private resolved `dbunk-smoke-dbus.yml` validation/dry-run,
  and updated clone Docker smoke with explicit log evidence/cleanup. Base remains
  free of checkout/listener/runtime credentials and host mounts.

### Pinned Homebrew packaging (not service activation)

- Created/trusted local-only tap **homeserver/pilot**; no remote/publishing and
  no upstream tap patch. Formula path:
  `/opt/homebrew/Library/Taps/homeserver/homebrew-pilot/Formula/sand.rb`.
- Formula **homeserver/pilot/sand 0.0.0-4263d2e** builds the previously tested
  GitHub revision from the immutable codeload archive. SHA-256:
  `6479f3e848385abe17ef2db3167e48049ec62a36da3c3916ef03f4e3096ce680`.
  Swift build uses `--force-resolved-versions`, release mode and two workers.
- Retains upstream pinned service definition (interactive user LaunchAgent,
  `~/sand.yml`, home working directory, standard service PATH, unified/file logs).
  sshpass is a declared dependency; verified Tart 2.40.1 remains a direct signed
  app-bundle install, checked by doctor. No stale cirruslabs dependency used.
- Build succeeded. Initial link conflict was the known manual Sand symlink;
  removed **only** that exact symlink after verifying its target, then linked
  Homebrew package without overwrite. Original binary remains for tool rollback.
- PASS: `brew test homeserver/pilot/sand` (CLI help smoke), doctor, Make help,
  `make sand-validate`, `make sand-status`, shell/YAML/Compose/whitespace checks.
  Brew CLI smoke is not the upstream unit suite; XCTest SDK blocker remains.
- Make targets now explicitly use the qualified local formula and validate the
  **same fixed `~/sand.yml`** that the service runs. Status runs doctor from HOME
  so it checks actual private runtime config rather than an absent repo config.
- No Sand LaunchAgent was loaded or service started. Homebrew auto-update/cleanup
  were disabled during this package install; brew test fetched its standard Ruby
  test-harness gems. No unrelated application service was stopped/recreated.

### Second attempt and STOP condition

- Hosted native job completed **success**, including all fmt/clippy/test,
  fixture checks, Python tests and packaging. No forced cancellation was issued.
  A backend-only rerun while native was active was rejected; after native finished,
  `gh run rerun 37745172897 --failed` started attempt 2 without a new workflow diff.
- Backend job **113213548988**, runner **homeserver-dbunk-sand-3ff3b**:
  **fmt passed, default Clippy passed, default cargo test passed**.
- Isolated-profile Clippy then failed: `clippy-driver` compiling the lib test was
  terminated by **signal 9 / SIGKILL**, not a Clippy lint. Isolated-profile tests
  were skipped. There was no no-space diagnostic.
- VM allocation remained exactly **4 GiB / 2 CPUs**. Fresh same-base guest reports
  3896 MiB usable memory, **zero swap**, and 12 GiB free root disk. Minimum sampled
  host free-memory percentage during retry was **75%**. This strongly suggests
  guest memory exhaustion, but **OOM is not proven**: failed guest was recycled
  before its kernel log could be captured. Do not silently adjust allocation.
- Sand recovered after both failures to one healthy replacement slot, last
  **homeserver-dbunk-sand-b0309**. At the plan's **two-failure STOP gate**, confirmed
  idle and sent supervised SIGINT. Guest and GitHub registration cleanup passed.
- Final state: only stopped base/OCI source in Tart, old runner online/idle,
  all 17 homeserver containers healthy/running, Sand service running/loaded false.
  Backend workflow **still targets sand**, so new backend jobs queue while paused.
  No workflow rollback was published without confirmation.
- **Operator decision required:** approve increasing the single pilot guest from
  4 to **8 GiB**, still 2 CPUs, and resuming a backend-only acceptance attempt;
  or explicitly approve publishing the rollback label change to orbstack.
- Full backend/service acceptance, legacy listener stop, independent review and
  final pilot-only homeserver commit remain incomplete. No unrelated work staged
  or committed. A fresh review can be launched with the available Pi CLI/model
  once acceptance resumes; no review pass was claimed at this historical stop gate.

## Approved 8 GiB resume and completed runtime acceptance — 2026-10-08

Operator explicitly approved raising the single slot from 4 to 8 GiB, retaining
2 CPUs, and retrying the failed backend. No code/check suppression authorized.

### Allocation and linker correction

- Compared existing protected runtime config against expected one-slot/App/
  repository/hardware state. Backed it up mode 600 as
  `~/.config/sand/sand-before-8gb.yml`, then atomically changed **only ramGb** to 8.
  Tracked templates now match the approved allocation. Validation/dry-run passed.
- Verified actual guest memory **8,104,148 KiB** (~7914 MiB usable), **2 CPUs**,
  no swap. 8 GiB script smoke completed and deleted its test guest.
- Attempt 3 backend job **113219126995**, runner **homeserver-dbunk-sand-2ab7f**,
  passed fmt, both Clippy modes and default tests. Final isolated-profile test
  failed **at link time**: GNU `ld` killed with signal 9 before tests executed.
  No lint/test assertion failure or no-space error. Allocation stayed approved 8.
- After idle-slot cleanup, installed Ubuntu **lld 18.1.3** (two packages, about
  1.3 MB download / 5.2 MB installed) and configured guest-only Cargo target:
  `[target.aarch64-unknown-linux-gnu]`,
  `rustflags = ["-C", "link-arg=-fuse-ld=lld"]`.
  This changes linker choice only, not tests/checks/debug flags or application code.
- Added regression preflight/smoke checks for lld and exact guest linker config
  before the fix; preflight rejected missing lld, then passed on the corrected
  base. GCC/lld link-and-execute fixture passed. Clean-base inspection and shutdown
  passed; no Cargo credentials, repository state, listener or host mount added.
- Updated private `dbunk-smoke-lld.yml` (600): validation, dry-run, 8 GiB clone
  smoke, actual Docker ARM64 execution and explicit log/VM cleanup all passed.

### Full CI acceptance

- Retried **only failed backend**, keeping native's prior success and every
  existing backend command. No additional workflow diff or application change.
- **CI 37745172897, attempt 4: SUCCESS**. Backend job **113224257396**, runner
  **homeserver-dbunk-sand-399a8**, UTC **08:37:53 → 08:51:29** (13m 36s).
- PASS: fmt, default Clippy, default cargo test, isolated-profile Clippy and
  isolated-profile cargo test. Every required step conclusion is success.
- PASS: hosted native fmt/clippy/tests, fixture/Python checks and packaging.
  `gh run watch 37745172897 --exit-status` returned success.
- After job completion, a different fresh runner **homeserver-dbunk-sand-a3fc8**
  became online/idle. No extra guest or offline registration accumulation.
- Minimum sampled host memory-free percentage during successful backend: **78%**.
  This is sampled pressure/headroom evidence, not an asserted exact peak. No host
  memory/storage compromise or allocation beyond one 8 GiB / 2 CPU slot observed.

### Service acceptance and legacy stop

- Gracefully handed off the idle foreground slot, verifying App/VM cleanup,
  then started qualified Homebrew service **homeserver/pilot/sand** after CI pass.
  Protected `~/Library/Logs/sand.log` mode 600; user LaunchAgent label **sh.brew.sand**.
- First service-stop test removed guest but left offline registration
  **homeserver-dbunk-sand-447f1**, ID **36**. Did **not** claim a pass or silently
  accumulate registrations. Verified offline/idle identity and deleted only this
  test registration; old runner ID 21 untouched.
- Added **stop_timeout 120** to the local formula so launchd allows App cleanup.
  Generated plist verified `ExitTimeOut=120`. No upstream source/tap patch or
  custom/system daemon created.
- Repeated service acceptance: **homeserver-dbunk-sand-ff11f** online/idle,
  `make sand-stop` followed by **no guest/no pilot registration**, then
  `make sand-start` recovered different **homeserver-dbunk-sand-3cd13** online/idle.
  Doctor/service info report running=true, loaded=true; stop/start gates passed.
- Fresh service guest verified 2 CPUs/~8 GiB, lld configured, **no repository
  workspace, sentinel or inherited Docker image**. Base remains stopped.
- Confirmed legacy runner ID 21 idle, then stopped **only**
  `docker compose stop github-runner-dbunk`. Its `.runner`, `.credentials`, distro,
  volumes/work directory and original container ID remain intact for rollback.
- All other **16 containers** retain original IDs/start timestamps and health;
  other three runners still running. No Compose profile was added because the
  runner implementation is pre-existing uncommitted work. README explicitly warns
  generic `make up` resurrects the preserved legacy listener.
- Service starts at user login, not guaranteed pre-login boot. Sleep/power/DHCP
  settings were not changed. App/key remains restricted/private, external approval
  policy remains all_external_contributors, and no untrusted run was approved.
- Remaining completion work is read-only fresh-agent review, any authorized fixes,
  final static/runtime gates, scope/staging inspection and pilot-only commit.
  Upstream XCTest SDK limitation is recorded separately; no pilot runtime gate
  remains blocked.

### Unclean reboot during the final-review pause — 2026-10-08

- On continuation, `/tmp` review artifacts were gone, host uptime was about
  2h 36m, and other containers had restarted with the host (same container IDs).
  No agent command initiated reboot or recreated those containers.
- Sand was loaded but crash-looping: 932 launches, exit 1; unified logging showed
  `VM "dbunk" already exists`. Old `dbunk` clone was stopped, pilot registration
  **homeserver-dbunk-sand-3cd13**, ID **38**, offline and not busy. Base stopped;
  preserved old listener ID 21 offline, with data still present.
- Stopped Homebrew service; verified exact pilot name/ID/offline/idle and stopped
  VM before deleting **only** registration 38 and local VM `dbunk`. No overwrite,
  other runner deletion, base mutation or workflow publication.
- Restarted same qualified service/config; new **homeserver-dbunk-sand-b1e21**
  online/idle, one slot only; doctor passes, running=true, loaded=true.
- README now documents safe manual unclean-reboot recovery. The pinned upstream
  revision does not auto-reclaim stale named VMs; this is an explicit **manual
  recovery limitation**. Approved graceful stop/start acceptance remains passed.
  No automatic crash-recovery claim or silent source patch is made.

### Final independent review and validation — 2026-10-08

- Fresh read-only **openai/gpt-5.6-sol, xhigh** reviewer received the complete
  pilot-only diff, plan, scope/preservation rules and runtime receipts. No private
  runtime files or credentials were supplied; tools disabled for the review.
- One low-severity actionable finding: README must warn that broad `make restart`
  and `make recreate`, as well as `make up`, can restart the legacy listener;
  recreation replaces container identities. A **new fresh fix agent** corrected
  only the pilot paragraph, preserving the user's existing documentation.
- A **new fresh xhigh reviewer** reviewed the updated complete diff and returned
  **No actionable findings**. No implementation/reviewer context was reused.
- Final gates: Bash syntax, both YAML parses, Compose quiet validation, help,
  Sand validate/dry-run/doctor/service status, Homebrew CLI test and whitespace
  checks pass. Actual backend/native full CI remains the passing attempt 4;
  only documentation changed afterward, so no check weakening or extra rerun.
- SDK limitation: upstream Sand Swift unit tests cannot compile XCTest under
  this Command Line Tools environment. This is explicitly not a claimed unit
  test pass; all required pilot runtime/CI gates passed independently.
- Commit scope is eight pilot files only; README is staged via a candidate blob
  containing only the new pilot section, leaving all earlier user edits intact.
  No workflow rollback/new publication, other-runner mutation or secret staged.
- Plan DONE means this **bounded pilot** meets the listed stop/start/CI/isolation
  criteria, not guaranteed unattended reboot recovery. Retain manual recovery,
  outside-collaborator approval policy and the old listener state for rollback.
