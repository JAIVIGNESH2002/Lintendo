#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /opt/blackmesa/payments-api
install -m 0644 /opt/blackmesa/status-server.py /opt/blackmesa/payments-api/status-server.py
install -m 0644 /opt/blackmesa/payments-api.Dockerfile /opt/blackmesa/payments-api/Dockerfile
rm -f /opt/blackmesa/status-server.py /opt/blackmesa/payments-api.Dockerfile /opt/blackmesa/blackmesa.service

systemctl enable --now docker

for _ in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker info >/dev/null 2>&1

docker rm -f payments-api postgres >/dev/null 2>&1 || true
docker network rm blackmesa-isolated blackmesa-payments >/dev/null 2>&1 || true

docker network create blackmesa-payments >/dev/null
docker volume create blackmesa-postgres-data >/dev/null

docker run -d \
  --name postgres \
  --network blackmesa-payments \
  --network-alias postgres \
  -e POSTGRES_USER=blackmesa \
  -e POSTGRES_PASSWORD=blackmesa \
  -e POSTGRES_DB=payments \
  -v blackmesa-postgres-data:/var/lib/postgresql/data \
  postgres:16-alpine >/dev/null

for _ in $(seq 1 60); do
  if docker exec postgres pg_isready -U blackmesa -d payments >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec postgres pg_isready -U blackmesa -d payments >/dev/null

docker build -t blackmesa/payments-api:local /opt/blackmesa/payments-api >/dev/null

docker run -d \
  --name payments-api \
  --network blackmesa-payments \
  -e DB_HOST=postgres \
  -e DB_NAME=payments \
  -e DB_USER=blackmesa \
  -e DB_PASSWORD=blackmesa \
  blackmesa/payments-api:local >/dev/null

for _ in $(seq 1 30); do
  if docker exec payments-api python3 /opt/payments-api/app.py charge setup-probe >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec payments-api python3 /opt/payments-api/app.py charge setup-probe >/dev/null 2>&1; then
  printf 'payments-api setup probe failed\n' >&2
  docker ps -a >&2 || true
  docker logs payments-api >&2 || true
  docker logs postgres >&2 || true
  exit 1
fi
docker exec postgres psql -U blackmesa -d payments -c "DELETE FROM payments WHERE token = 'setup-probe';" >/dev/null
