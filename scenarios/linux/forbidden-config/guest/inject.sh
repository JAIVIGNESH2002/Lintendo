#!/usr/bin/env bash
set -euo pipefail

chown root:root /etc/blackmesa/telemetry.conf
chmod 0600 /etc/blackmesa/telemetry.conf

if runuser -u blackmesa -- test -r /etc/blackmesa/telemetry.conf; then
  printf 'blackmesa can still read telemetry.conf after injection\n' >&2
  exit 1
fi

systemctl stop telemetry.service
systemctl start telemetry.service || true
