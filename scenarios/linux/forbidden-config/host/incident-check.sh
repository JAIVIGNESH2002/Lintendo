#!/usr/bin/env bash
set -euo pipefail

instance="${1:?instance name required}"
ip="${2:?instance IP required}"

command -v wget >/dev/null 2>&1 || {
  printf 'host incident check requires wget on the host\n' >&2
  exit 127
}

incus exec "$instance" -- test -f /etc/blackmesa/telemetry.conf
incus exec "$instance" -- test -f /opt/blackmesa/status-server.py

if incus exec "$instance" -- runuser -u blackmesa -- test -r /etc/blackmesa/telemetry.conf; then
  printf 'blackmesa can still read telemetry.conf\n' >&2
  exit 1
fi

for _ in $(seq 1 10); do
  if [ "$(incus exec "$instance" -- systemctl is-active telemetry.service || true)" != "active" ]; then
    break
  fi
  sleep 1
done

if [ "$(incus exec "$instance" -- systemctl is-active telemetry.service || true)" = "active" ]; then
  printf 'telemetry.service is unexpectedly active\n' >&2
  incus exec "$instance" -- systemctl status --no-pager telemetry.service >&2 || true
  exit 1
fi

if wget -q -T 5 -O - "http://$ip:8080/health" >/dev/null 2>&1; then
  printf 'telemetry health endpoint is unexpectedly reachable\n' >&2
  exit 1
fi
