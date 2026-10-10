#!/usr/bin/env bash
set -Eeuo pipefail

runner_distribution=/home/runner
runner_root=${RUNNER_ROOT:-/runner}
runner_workdir=${RUNNER_WORKDIR:-_work}

mkdir -p "$runner_root"

# Keep the runner distribution and its credentials in persistent state. The
# image supplies the initial files; subsequent container restarts reuse them.
if [[ ! -x "$runner_root/config.sh" || ! -x "$runner_root/run.sh" ]]; then
  cp -R --no-preserve=ownership "$runner_distribution/." "$runner_root/"
fi

cd "$runner_root"

if [[ ! -f .runner ]]; then
  : "${RUNNER_URL:?RUNNER_URL is required for initial registration}"
  : "${RUNNER_TOKEN:?RUNNER_TOKEN is required for initial registration}"
  : "${RUNNER_NAME:?RUNNER_NAME is required for initial registration}"

  config_args=(
    --unattended
    --replace
    --url "$RUNNER_URL"
    --token "$RUNNER_TOKEN"
    --name "$RUNNER_NAME"
    --work "$runner_workdir"
  )

  if [[ -n "${RUNNER_LABELS:-}" ]]; then
    config_args+=(--labels "$RUNNER_LABELS")
  fi

  ./config.sh "${config_args[@]}"
  unset RUNNER_TOKEN
fi

if [[ "${RUNNER_CONFIG_ONLY:-false}" == "true" ]]; then
  exit 0
fi

exec ./run.sh
