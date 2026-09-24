#!/usr/bin/env bash
set -euo pipefail

chown root:root /etc/blackmesa/telemetry.conf
chmod 0600 /etc/blackmesa/telemetry.conf

if runuser -u blackmesa -- test -r /etc/blackmesa/telemetry.conf; then
  printf 'blackmesa can still read telemetry.conf after injection\n' >&2
  exit 1
fi

systemctl restart telemetry.service || true

if systemctl is-active --quiet telemetry.service; then
  printf 'telemetry.service is still active after config access regression\n' >&2
  exit 1
fi

