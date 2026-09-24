#!/usr/bin/env bash
set -euo pipefail

systemctl is-active --quiet telemetry.service

main_pid="$(systemctl show -p MainPID --value telemetry.service)"
[ -n "$main_pid" ] && [ "$main_pid" != "0" ]

service_user="$(ps -o user= -p "$main_pid" | awk '{print $1}')"
[ "$service_user" = "blackmesa" ]

runuser -u blackmesa -- test -r /etc/blackmesa/telemetry.conf
bash -lc 'exec 3<>/dev/tcp/127.0.0.1/8080; printf "GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3; grep -q "Black Mesa telemetry operational" <&3'

