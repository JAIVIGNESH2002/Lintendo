#!/usr/bin/env bash
set -euo pipefail

sed -i 's/^BLACKMESA_WORKER_MODE=.*/BLACKMESA_WORKER_MODE=crash/' /etc/blackmesa/worker.env
grep -qx 'BLACKMESA_WORKER_MODE=crash' /etc/blackmesa/worker.env

systemctl restart restless-worker.service || true

