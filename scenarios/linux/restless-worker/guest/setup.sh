#!/usr/bin/env bash
set -euo pipefail

if ! getent group blackmesa >/dev/null; then
  groupadd --system blackmesa
fi

if ! id -u blackmesa >/dev/null 2>&1; then
  useradd --system --gid blackmesa --home-dir /var/lib/blackmesa --shell /usr/sbin/nologin blackmesa
fi

install -d -m 0755 /opt/blackmesa
install -d -m 0755 /etc/blackmesa
install -d -o blackmesa -g blackmesa -m 0755 /var/lib/blackmesa
install -d -o blackmesa -g blackmesa -m 0755 /var/lib/blackmesa/incoming
install -d -o blackmesa -g blackmesa -m 0755 /var/lib/blackmesa/processed

install -m 0755 /opt/blackmesa/status-server.py /opt/blackmesa/restless-worker.py
install -m 0644 /opt/blackmesa/worker.env /etc/blackmesa/worker.env
install -m 0644 /opt/blackmesa/blackmesa.service /etc/systemd/system/restless-worker.service
rm -f /opt/blackmesa/status-server.py /opt/blackmesa/worker.env /opt/blackmesa/blackmesa.service

systemctl daemon-reload
systemctl enable --now restless-worker.service

