#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"
ip="${2:?instance IP required}"

command -v wget >/dev/null 2>&1 || {
  printf 'host incident check requires wget on the host\n' >&2
  exit 127
}

system_active="$(incus exec "$instance" -- systemctl is-active blackmesa.service)"
[ "$system_active" = "active" ]

incus exec "$instance" -- bash -lc 'exec 3<>/dev/tcp/127.0.0.1/8080; printf "GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3; grep -q "Black Mesa systems operational" <&3'

if wget -q -T 5 -O - "http://$ip:8080/health" >/dev/null 2>&1; then
  printf 'endpoint is still externally reachable\n' >&2
  exit 1
fi
