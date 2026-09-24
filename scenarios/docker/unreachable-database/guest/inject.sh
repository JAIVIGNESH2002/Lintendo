#!/usr/bin/env bash
set -euo pipefail

docker network create blackmesa-isolated >/dev/null 2>&1 || true

if ! docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' payments-api | grep -qx blackmesa-isolated; then
  docker network connect blackmesa-isolated payments-api
fi

if docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' payments-api | grep -qx blackmesa-payments; then
  docker network disconnect blackmesa-payments payments-api
fi

docker exec postgres pg_isready -U blackmesa -d payments >/dev/null

if docker exec payments-api python3 /opt/payments-api/app.py charge injection-probe >/dev/null 2>&1; then
  printf 'payments-api can still perform database-backed operations after injection\n' >&2
  exit 1
fi

