#!/usr/bin/env bash
set -Eeuo pipefail

# Run inside a clean base or disposable clone as the intended runner user.
test "$(uname -s)" = Linux
test "$(uname -m)" = aarch64
test "$(id -u)" -ne 0
sudo -n true
git --version
curl --version
python3 --version
command -v cc >/dev/null
command -v make >/dev/null
pkg-config --exists openssl
# Dbunk's keyring sync-secret-service feature builds libdbus-sys on Linux.
pkg-config --exists 'dbus-1 >= 1.6'
# Use lld after GNU ld was SIGKILLed linking the isolated-profile lib tests.
ld.lld --version
python3 -c 'import pathlib, tomllib; c = tomllib.loads((pathlib.Path.home() / ".cargo/config.toml").read_text()); assert c["target"]["aarch64-unknown-linux-gnu"]["rustflags"] == ["-C", "link-arg=-fuse-ld=lld"]'
docker info >/dev/null
docker compose version
test ! -e "$HOME/actions-runner/.runner"
test ! -e "$HOME/actions-runner/.credentials"
test ! -e "$HOME/.dbunk-sand-smoke-sentinel"

printf '%s\n' 'Dbunk guest preflight passed (Docker container execution is a separate gate).'
