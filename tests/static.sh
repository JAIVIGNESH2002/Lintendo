#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required=(
  "lintendo"
  "runtime/lib/instance.sh"
  "runtime/lib/scenario.sh"
  "runtime/lib/lifecycle.sh"
  "runtime/README.md"
  "scenarios/linux/silent-service/quest.yaml"
  "scenarios/linux/silent-service/guest/setup.sh"
  "scenarios/linux/silent-service/guest/baseline.sh"
  "scenarios/linux/silent-service/guest/inject.sh"
  "scenarios/linux/silent-service/host/baseline.sh"
  "scenarios/linux/silent-service/host/incident-check.sh"
  "scenarios/linux/silent-service/host/verify.sh"
  "scenarios/linux/silent-service/assets/status-server.py"
  "scenarios/linux/silent-service/assets/blackmesa.service"
)

for item in "${required[@]}"; do
  [ -e "$item" ] || {
    printf 'missing expected path: %s\n' "$item" >&2
    exit 1
  }
done

grep -q 'bash -s <' runtime/lib/instance.sh
grep -q 'LINTENDO_INSTANCE_NAME=' runtime/lib/instance.sh
grep -q 'LINTENDO_INSTANCE_IP=' runtime/lib/lifecycle.sh
grep -q 'host/verify\.sh' runtime/lib/lifecycle.sh
grep -q 'python3' scenarios/linux/silent-service/quest.yaml
grep -q 'wget' scenarios/linux/silent-service/host/baseline.sh
grep -q 'wget' scenarios/linux/silent-service/host/incident-check.sh
grep -q 'wget' scenarios/linux/silent-service/host/verify.sh

if grep -Eq 'search|leaderboard|registry|account|frontend|database' runtime/lib/*.sh lintendo; then
  printf 'unexpected future-scope term found in runtime\n' >&2
  exit 1
fi

printf 'Static tests passed.\n'

