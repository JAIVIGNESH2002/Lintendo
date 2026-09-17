#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"
ip="${2:?instance IP required}"

command -v wget >/dev/null 2>&1 || {
  printf 'host baseline requires wget on the host\n' >&2
  exit 127
}

system_active="$(incus exec "$instance" -- systemctl is-active blackmesa.service)"
[ "$system_active" = "active" ]
wget -q -T 5 -O - "http://$ip:8080/health" | grep -q "Black Mesa systems operational"

