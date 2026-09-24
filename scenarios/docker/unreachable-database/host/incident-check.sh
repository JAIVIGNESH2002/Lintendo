#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"

incus exec "$instance" -- docker exec postgres pg_isready -U blackmesa -d payments >/dev/null
incus exec "$instance" -- test "$(incus exec "$instance" -- docker inspect -f '{{.State.Running}}' payments-api)" = "true"

api_networks="$(incus exec "$instance" -- docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' payments-api)"
postgres_networks="$(incus exec "$instance" -- docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' postgres)"

printf '%s\n' "$postgres_networks" | grep -qx blackmesa-payments
printf '%s\n' "$api_networks" | grep -qx blackmesa-isolated
if printf '%s\n' "$api_networks" | grep -qx blackmesa-payments; then
  printf 'payments-api is still attached to the database network\n' >&2
  exit 1
fi

token="incident$(date +%s%N)$$"
cleanup() {
  incus exec "$instance" -- docker exec postgres psql -U blackmesa -d payments -c "DELETE FROM payments WHERE token = '$token';" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if incus exec "$instance" -- docker exec payments-api python3 /opt/payments-api/app.py charge "$token" >/dev/null 2>&1; then
  printf 'database-backed API operation unexpectedly succeeded\n' >&2
  exit 1
fi

printf '✓ PostgreSQL itself remains healthy\n'
printf '✓ API container exists/runs as intended\n'
printf '✓ database-backed API operation fails\n'
printf '✓ failure matches Docker network membership incident\n'

