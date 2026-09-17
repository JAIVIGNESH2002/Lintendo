#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /opt/blackmesa
install -m 0644 /opt/blackmesa/blackmesa.service /etc/systemd/system/blackmesa.service
systemctl daemon-reload
systemctl enable --now blackmesa.service

