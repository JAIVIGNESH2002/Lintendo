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
  "scenarios/linux/forbidden-config/quest.yaml"
  "scenarios/linux/forbidden-config/guest/setup.sh"
  "scenarios/linux/forbidden-config/guest/baseline.sh"
  "scenarios/linux/forbidden-config/guest/inject.sh"
  "scenarios/linux/forbidden-config/host/baseline.sh"
  "scenarios/linux/forbidden-config/host/incident-check.sh"
  "scenarios/linux/forbidden-config/host/verify.sh"
  "scenarios/linux/forbidden-config/assets/status-server.py"
  "scenarios/linux/forbidden-config/assets/blackmesa.service"
  "scenarios/linux/forbidden-config/assets/telemetry.conf"
  "tests/integration/forbidden-config-smoke.sh"
)

for item in "${required[@]}"; do
  [ -e "$item" ] || {
    printf 'missing expected path: %s\n' "$item" >&2
    exit 1
  }
done

grep -q 'bash -s <' runtime/lib/instance.sh
grep -q 'LINTENDO_INSTANCE_NAME=' runtime/lib/instance.sh
grep -q 'lintendo_wait_instance_ip' runtime/lib/instance.sh
grep -q 'ip -4 -o addr show dev' runtime/lib/instance.sh
grep -q 'LINTENDO_INSTANCE_IP=' runtime/lib/lifecycle.sh
grep -q 'host/verify\.sh' runtime/lib/lifecycle.sh
grep -q 'python3' scenarios/linux/silent-service/quest.yaml
grep -q 'python3' scenarios/linux/forbidden-config/quest.yaml
grep -q 'User=blackmesa' scenarios/linux/forbidden-config/assets/blackmesa.service
if grep -q 'Restart=on-failure' scenarios/linux/forbidden-config/assets/blackmesa.service; then
  printf 'forbidden-config service should fail clearly instead of restart-looping\n' >&2
  exit 1
fi
grep -q 'telemetry.conf' scenarios/linux/forbidden-config/guest/inject.sh
grep -q 'systemctl stop telemetry.service' scenarios/linux/forbidden-config/guest/inject.sh
grep -q 'systemctl start telemetry.service' scenarios/linux/forbidden-config/guest/inject.sh
grep -q 'telemetry.service' scenarios/linux/forbidden-config/host/verify.sh
grep -q 'wget' scenarios/linux/silent-service/host/baseline.sh
grep -q 'wget' scenarios/linux/silent-service/host/incident-check.sh
grep -q 'wget' scenarios/linux/silent-service/host/verify.sh
grep -q 'wget' scenarios/linux/forbidden-config/host/baseline.sh
grep -q 'wget' scenarios/linux/forbidden-config/host/incident-check.sh
grep -q 'wget' scenarios/linux/forbidden-config/host/verify.sh

if grep -q './lintendo run' README.md tests/integration/*.sh lintendo; then
  printf 'old learner-facing run command still documented\n' >&2
  exit 1
fi

if grep -Eq 'search|leaderboard|registry|account|frontend|database' runtime/lib/*.sh lintendo; then
  printf 'unexpected future-scope term found in runtime\n' >&2
  exit 1
fi

printf 'Static tests passed.\n'
