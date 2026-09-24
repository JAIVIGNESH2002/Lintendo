#!/usr/bin/env bash
set -euo pipefail

if ! getent group blackmesa >/dev/null; then
  groupadd --system blackmesa
fi

if ! id -u blackmesa >/dev/null 2>&1; then
  useradd --system --gid blackmesa --home-dir /nonexistent --shell /usr/sbin/nologin blackmesa
fi

install -d -m 0755 /opt/blackmesa
install -d -m 0755 /etc/blackmesa
chmod 0755 /opt/blackmesa/status-server.py
install -o root -g blackmesa -m 0640 /opt/blackmesa/telemetry.conf /etc/blackmesa/telemetry.conf
install -m 0644 /opt/blackmesa/blackmesa.service /etc/systemd/system/telemetry.service
rm -f /opt/blackmesa/telemetry.conf /opt/blackmesa/blackmesa.service

systemctl daemon-reload
systemctl enable --now telemetry.service
