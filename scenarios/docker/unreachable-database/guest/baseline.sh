#!/usr/bin/env bash
set -euo pipefail

docker info >/dev/null

[ "$(docker inspect -f '{{.State.Running}}' payments-api)" = "true" ]
[ "$(docker inspect -f '{{.State.Running}}' postgres)" = "true" ]
docker exec postgres pg_isready -U blackmesa -d payments >/dev/null

token="baseline$(date +%s%N)$$"
cleanup() {
  docker exec postgres psql -U blackmesa -d payments -c "DELETE FROM payments WHERE token = '$token';" >/dev/null 2>&1 || true
}
trap cleanup EXIT

result="$(docker exec payments-api python3 /opt/payments-api/app.py charge "$token")"
[ "$result" = "charged:$token" ]
