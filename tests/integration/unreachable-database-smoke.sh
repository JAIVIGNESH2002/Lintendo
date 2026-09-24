#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

export LINTENDO_STATE_DIR="${LINTENDO_STATE_DIR:-$(mktemp -d)}"

cleanup() {
  ./lintendo destroy >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Starting interactive smoke test for docker/unreachable-database.\n'
printf 'When the learner shell opens, restore payments-api database connectivity without replacing the app or deleting the database, then exit.\n'

./lintendo play docker/unreachable-database

