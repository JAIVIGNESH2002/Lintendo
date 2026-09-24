#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"
ip="${2:?instance IP required}"

command -v wget >/dev/null 2>&1 || {
  printf 'host solution verification requires wget on the host\n' >&2
  exit 127
}

system_active="$(incus exec "$instance" -- systemctl is-active telemetry.service)"
[ "$system_active" = "active" ]

main_pid="$(incus exec "$instance" -- systemctl show -p MainPID --value telemetry.service)"
[ -n "$main_pid" ] && [ "$main_pid" != "0" ]

service_user="$(incus exec "$instance" -- ps -o user= -p "$main_pid" | awk '{print $1}')"
[ "$service_user" = "blackmesa" ]

incus exec "$instance" -- runuser -u blackmesa -- test -r /etc/blackmesa/telemetry.conf
wget -q -T 5 -O - "http://$ip:8080/health" | grep -q "Black Mesa telemetry operational"

