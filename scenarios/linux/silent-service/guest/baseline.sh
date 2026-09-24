#!/usr/bin/env bash
set -euo pipefail

systemctl is-active --quiet blackmesa.service

health_ready() {
  bash -lc 'exec 3<>/dev/tcp/127.0.0.1/8080 || exit 1; printf "GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3 || exit 1; grep -q "Black Mesa systems operational" <&3' >/dev/null 2>&1
}

deadline=$((SECONDS + 10))
while (( SECONDS < deadline )); do
  if health_ready; then
    exit 0
  fi

  sleep 0.25
done

echo "blackmesa.service is active, but /health did not become ready within 10 seconds" >&2
exit 1
