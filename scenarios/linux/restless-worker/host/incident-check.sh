#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"

incus exec "$instance" -- test -f /opt/blackmesa/restless-worker.py
incus exec "$instance" -- test -f /etc/systemd/system/restless-worker.service
incus exec "$instance" -- test -f /etc/blackmesa/worker.env
incus exec "$instance" -- grep -qx 'BLACKMESA_WORKER_MODE=crash' /etc/blackmesa/worker.env

if [ "$(incus exec "$instance" -- systemctl is-enabled restless-worker.service)" != "enabled" ]; then
  printf 'restless-worker.service is not enabled\n' >&2
  exit 1
fi

for _ in $(seq 1 10); do
  restarts="$(incus exec "$instance" -- systemctl show -p NRestarts --value restless-worker.service || printf '0')"
  if [ "${restarts:-0}" -ge 1 ] 2>/dev/null; then
    break
  fi
  sleep 1
done

restarts="$(incus exec "$instance" -- systemctl show -p NRestarts --value restless-worker.service || printf '0')"
if ! [ "${restarts:-0}" -ge 1 ] 2>/dev/null; then
  printf 'restless-worker.service has not entered a restart cycle\n' >&2
  incus exec "$instance" -- systemctl status --no-pager restless-worker.service >&2 || true
  exit 1
fi

token="incident$(date +%s%N)$$"
incus exec "$instance" -- bash -lc "rm -f /var/lib/blackmesa/incoming/$token.job /var/lib/blackmesa/processed/$token.done; printf '%s\n' '$token' > /var/lib/blackmesa/incoming/$token.job; chown blackmesa:blackmesa /var/lib/blackmesa/incoming/$token.job"

cleanup() {
  incus exec "$instance" -- rm -f "/var/lib/blackmesa/incoming/$token.job" "/var/lib/blackmesa/processed/$token.done" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 5); do
  if incus exec "$instance" -- test -f "/var/lib/blackmesa/processed/$token.done"; then
    printf 'worker unexpectedly processed incident test job\n' >&2
    exit 1
  fi
  sleep 1
done

