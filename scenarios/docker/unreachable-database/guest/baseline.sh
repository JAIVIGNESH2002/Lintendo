#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'docker baseline failed: %s\n' "$*" >&2
  docker ps -a >&2 || true
  exit 1
}

docker info >/dev/null 2>&1 || fail "Docker daemon is not operational"

api_running="$(docker inspect -f '{{.State.Running}}' payments-api 2>/dev/null || true)"
[ "$api_running" = "true" ] || fail "payments-api container is not running"

postgres_running="$(docker inspect -f '{{.State.Running}}' postgres 2>/dev/null || true)"
[ "$postgres_running" = "true" ] || fail "postgres container is not running"

docker exec postgres pg_isready -U blackmesa -d payments >/dev/null 2>&1 || fail "PostgreSQL is not healthy"

token="baseline$(date +%s%N)$$"
cleanup() {
  docker exec postgres psql -U blackmesa -d payments -c "DELETE FROM payments WHERE token = '$token';" >/dev/null 2>&1 || true
}
trap cleanup EXIT

result="$(docker exec payments-api python3 /opt/payments-api/app.py charge "$token" 2>&1)" || {
  printf '%s\n' "$result" >&2
  fail "payments-api could not perform a database-backed operation"
}
[ "$result" = "charged:$token" ] || fail "unexpected payments-api result: $result"
