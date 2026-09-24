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
  "scenarios/linux/restless-worker/quest.yaml"
  "scenarios/linux/restless-worker/guest/setup.sh"
  "scenarios/linux/restless-worker/guest/baseline.sh"
  "scenarios/linux/restless-worker/guest/inject.sh"
  "scenarios/linux/restless-worker/host/baseline.sh"
  "scenarios/linux/restless-worker/host/incident-check.sh"
  "scenarios/linux/restless-worker/host/verify.sh"
  "scenarios/linux/restless-worker/assets/status-server.py"
  "scenarios/linux/restless-worker/assets/blackmesa.service"
  "scenarios/linux/restless-worker/assets/worker.env"
  "scenarios/docker/unreachable-database/quest.yaml"
  "scenarios/docker/unreachable-database/guest/setup.sh"
  "scenarios/docker/unreachable-database/guest/baseline.sh"
  "scenarios/docker/unreachable-database/guest/inject.sh"
  "scenarios/docker/unreachable-database/host/baseline.sh"
  "scenarios/docker/unreachable-database/host/incident-check.sh"
  "scenarios/docker/unreachable-database/host/verify.sh"
  "scenarios/docker/unreachable-database/assets/status-server.py"
  "scenarios/docker/unreachable-database/assets/blackmesa.service"
  "scenarios/docker/unreachable-database/assets/payments-api.Dockerfile"
  "tests/integration/forbidden-config-smoke.sh"
  "tests/integration/restless-worker-smoke.sh"
  "tests/integration/unreachable-database-smoke.sh"
  "tests/capabilities.sh"
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
grep -q 'lintendo_yaml_capabilities' runtime/lib/scenario.sh
grep -q 'unknown environment capability' runtime/lib/scenario.sh
grep -q 'security.nesting=true' runtime/lib/instance.sh
if grep -q 'security.privileged' runtime/lib/*.sh scenarios/*/*/quest.yaml; then
  printf 'runtime/scenarios must not enable privileged Incus containers\n' >&2
  exit 1
fi
if grep -Eq 'Endpoint externally reachable|Service operational' runtime/lib/lifecycle.sh; then
  printf 'generic lifecycle should not print scenario-specific success checks\n' >&2
  exit 1
fi
grep -q 'python3' scenarios/linux/silent-service/quest.yaml
grep -q 'python3' scenarios/linux/forbidden-config/quest.yaml
grep -q 'python3' scenarios/linux/restless-worker/quest.yaml
grep -q 'docker.io' scenarios/docker/unreachable-database/quest.yaml
grep -q 'capabilities:' scenarios/docker/unreachable-database/quest.yaml
grep -q 'nesting' scenarios/docker/unreachable-database/quest.yaml
grep -q 'User=blackmesa' scenarios/linux/forbidden-config/assets/blackmesa.service
if grep -q 'Restart=on-failure' scenarios/linux/forbidden-config/assets/blackmesa.service; then
  printf 'forbidden-config service should fail clearly instead of restart-looping\n' >&2
  exit 1
fi
grep -q 'telemetry.conf' scenarios/linux/forbidden-config/guest/inject.sh
grep -q 'systemctl stop telemetry.service' scenarios/linux/forbidden-config/guest/inject.sh
grep -q 'systemctl start telemetry.service' scenarios/linux/forbidden-config/guest/inject.sh
grep -q 'telemetry.service' scenarios/linux/forbidden-config/host/verify.sh
grep -q 'Telemetry service active' scenarios/linux/forbidden-config/host/verify.sh
grep -q 'User=blackmesa' scenarios/linux/restless-worker/assets/blackmesa.service
grep -q 'Restart=on-failure' scenarios/linux/restless-worker/assets/blackmesa.service
grep -q 'EnvironmentFile=/etc/blackmesa/worker.env' scenarios/linux/restless-worker/assets/blackmesa.service
grep -q 'BLACKMESA_WORKER_MODE=process' scenarios/linux/restless-worker/assets/worker.env
grep -q 'BLACKMESA_WORKER_MODE=crash' scenarios/linux/restless-worker/guest/inject.sh
grep -q 'NRestarts' scenarios/linux/restless-worker/host/incident-check.sh
grep -Fq 'verify$(date +%s%N)$$' scenarios/linux/restless-worker/host/verify.sh
grep -Fq 'processed:$token' scenarios/linux/restless-worker/host/verify.sh
if grep -REq 'wget|curl|http|/health|8080' scenarios/linux/restless-worker; then
  printf 'restless-worker should use non-HTTP behavioral verification\n' >&2
  exit 1
fi
grep -q 'wget' scenarios/linux/silent-service/host/baseline.sh
grep -q 'wget' scenarios/linux/silent-service/host/incident-check.sh
grep -q 'wget' scenarios/linux/silent-service/host/verify.sh
grep -q 'wget' scenarios/linux/forbidden-config/host/baseline.sh
grep -q 'wget' scenarios/linux/forbidden-config/host/incident-check.sh
grep -q 'wget' scenarios/linux/forbidden-config/host/verify.sh
grep -q 'docker network disconnect blackmesa-payments payments-api' scenarios/docker/unreachable-database/guest/inject.sh
grep -q 'docker network connect blackmesa-isolated payments-api' scenarios/docker/unreachable-database/guest/inject.sh
grep -q 'docker baseline failed' scenarios/docker/unreachable-database/guest/baseline.sh
grep -q 'payments-api could not perform a database-backed operation' scenarios/docker/unreachable-database/guest/baseline.sh
grep -q 'blackmesa-postgres-data' scenarios/docker/unreachable-database/host/verify.sh
grep -q 'fresh database-backed operation succeeds' scenarios/docker/unreachable-database/host/verify.sh

if grep -q './lintendo run' README.md tests/integration/*.sh lintendo; then
  printf 'old learner-facing run command still documented\n' >&2
  exit 1
fi

if grep -Eq 'search|leaderboard|registry|account|frontend|database' runtime/lib/*.sh lintendo; then
  printf 'unexpected future-scope term found in runtime\n' >&2
  exit 1
fi

printf 'Static tests passed.\n'
