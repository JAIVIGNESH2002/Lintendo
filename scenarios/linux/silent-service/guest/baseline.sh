#!/usr/bin/env bash
set -euo pipefail

systemctl is-active --quiet blackmesa.service
bash -lc 'exec 3<>/dev/tcp/127.0.0.1/8080; printf "GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3; grep -q "Black Mesa systems operational" <&3'

