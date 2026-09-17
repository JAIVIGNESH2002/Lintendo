#!/usr/bin/env bash

lintendo_require_incus() {
  command -v incus >/dev/null 2>&1 || lintendo_die "incus CLI not found"
}

lintendo_instance_name() {
  local scenario_id="$1"
  local slug short
  slug="${scenario_id##*/}"
  slug="$(printf '%s' "$slug" | tr -cs 'a-zA-Z0-9-' '-' | tr 'A-Z' 'a-z' | sed 's/^-//; s/-$//')"
  short="$(date +%s)-$$"
  printf 'lintendo-%s-%s\n' "$slug" "$short"
}

lintendo_create_instance() {
  local image="$1"
  local name="$2"
  incus launch "$image" "$name" >/dev/null
}

lintendo_wait_ready() {
  local name="$1"
  local attempt
  for attempt in $(seq 1 60); do
    if incus exec "$name" -- test -x /bin/bash >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

lintendo_instance_ip() {
  local name="$1"
  local ip
  ip="$(incus list "$name" -c 4 --format csv | tr ',' '\n' | awk '/\(eth0\)/ && /inet/ { print $1; exit }')"
  if [ -z "$ip" ]; then
    ip="$(incus exec "$name" -- sh -c "hostname -I | awk '{print \$1}'" 2>/dev/null || true)"
  fi
  [ -n "$ip" ] || return 1
  printf '%s\n' "$ip"
}

lintendo_install_packages() {
  local name="$1"
  shift
  [ "$#" -gt 0 ] || return 0

  local pkg
  for pkg in "$@"; do
    case "$pkg" in
      ''|*[!a-zA-Z0-9+_.:-]*)
        lintendo_die "unsafe package name in scenario manifest: $pkg"
        ;;
    esac
  done

  incus exec "$name" -- bash -lc 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"' bash "$@"
}

lintendo_push_assets() {
  local name="$1"
  local assets_dir="$2"
  local asset
  incus exec "$name" -- mkdir -p /opt/blackmesa
  for asset in "$assets_dir"/*; do
    [ -f "$asset" ] || continue
    incus file push "$asset" "$name/opt/blackmesa/$(basename "$asset")" >/dev/null
  done
}

lintendo_exec_guest_script() {
  local name="$1"
  local script="$2"
  local ip="$3"
  incus exec "$name" \
    --env "LINTENDO_INSTANCE_NAME=$name" \
    --env "LINTENDO_INSTANCE_IP=$ip" \
    -- bash -s < "$script"
}

lintendo_destroy_instance() {
  local name="$1"
  if incus info "$name" >/dev/null 2>&1; then
    incus delete --force "$name" >/dev/null
  fi
}
