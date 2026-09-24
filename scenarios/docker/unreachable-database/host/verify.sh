#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"

incus exec "$instance" -- docker exec postgres pg_isready -U blackmesa -d payments >/dev/null
incus exec "$instance" -- docker volume inspect blackmesa-postgres-data >/dev/null
incus exec "$instance" -- docker exec postgres psql -U blackmesa -d payments -c "SELECT 1;" >/dev/null
incus exec "$instance" -- test "$(incus exec "$instance" -- docker inspect -f '{{.State.Running}}' payments-api)" = "true"

token="verify$(date +%s%N)$$"
cleanup() {
  incus exec "$instance" -- docker exec postgres psql -U blackmesa -d payments -c "DELETE FROM payments WHERE token = '$token';" >/dev/null 2>&1 || true
}
trap cleanup EXIT

result="$(incus exec "$instance" -- docker exec payments-api python3 /opt/payments-api/app.py charge "$token")"
[ "$result" = "charged:$token" ]

printf '✓ PostgreSQL remains healthy\n'
printf '✓ database/data still exists\n'
printf '✓ payments API is operational\n'
printf '✓ API can communicate with PostgreSQL\n'
printf '✓ fresh database-backed operation succeeds\n'

