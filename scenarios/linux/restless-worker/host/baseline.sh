#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"

system_active="$(incus exec "$instance" -- systemctl is-active restless-worker.service)"
[ "$system_active" = "active" ]

main_pid="$(incus exec "$instance" -- systemctl show -p MainPID --value restless-worker.service)"
[ -n "$main_pid" ] && [ "$main_pid" != "0" ]

service_user="$(incus exec "$instance" -- ps -o user= -p "$main_pid" | awk '{print $1}')"
[ "$service_user" = "blackmesa" ]

token="hostbaseline$(date +%s%N)$$"
incus exec "$instance" -- bash -lc "rm -f /var/lib/blackmesa/incoming/$token.job /var/lib/blackmesa/processed/$token.done; printf '%s\n' '$token' > /var/lib/blackmesa/incoming/$token.job; chown blackmesa:blackmesa /var/lib/blackmesa/incoming/$token.job"

cleanup() {
  incus exec "$instance" -- rm -f "/var/lib/blackmesa/incoming/$token.job" "/var/lib/blackmesa/processed/$token.done" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 15); do
  if incus exec "$instance" -- bash -lc "test -f /var/lib/blackmesa/processed/$token.done && grep -qx 'processed:$token' /var/lib/blackmesa/processed/$token.done"; then
    exit 0
  fi
  sleep 1
done

printf 'worker did not process host baseline test job\n' >&2
exit 1

