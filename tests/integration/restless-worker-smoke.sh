#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

export LINTENDO_STATE_DIR="${LINTENDO_STATE_DIR:-$(mktemp -d)}"

cleanup() {
  ./lintendo destroy >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Starting interactive smoke test for linux/restless-worker.\n'
printf 'When the learner shell opens, restore worker runtime configuration, restart restless-worker.service, then exit.\n'

./lintendo play linux/restless-worker

