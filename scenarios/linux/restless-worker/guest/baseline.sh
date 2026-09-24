#!/usr/bin/env bash
set -euo pipefail

systemctl is-active --quiet restless-worker.service

main_pid="$(systemctl show -p MainPID --value restless-worker.service)"
[ -n "$main_pid" ] && [ "$main_pid" != "0" ]

service_user="$(ps -o user= -p "$main_pid" | awk '{print $1}')"
[ "$service_user" = "blackmesa" ]

token="baseline$(date +%s%N)$$"
job="/var/lib/blackmesa/incoming/$token.job"
result="/var/lib/blackmesa/processed/$token.done"

cleanup() {
  rm -f "$job" "$result"
}
trap cleanup EXIT

printf '%s\n' "$token" > "$job"
chown blackmesa:blackmesa "$job"

for _ in $(seq 1 15); do
  if [ -f "$result" ] && grep -qx "processed:$token" "$result"; then
    exit 0
  fi
  sleep 1
done

printf 'worker did not process baseline test job\n' >&2
exit 1

