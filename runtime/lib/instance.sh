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
  shift 2

  if [ "$#" -eq 0 ]; then
    incus launch "$image" "$name" >/dev/null
    return
  fi

  local capability
  local -a launch_args
  for capability in "$@"; do
    case "$capability" in
      nesting)
        launch_args+=("-c" "security.nesting=true")
        ;;
      *)
        lintendo_die "unknown environment capability: $capability"
        ;;
    esac
  done

  incus launch "$image" "$name" "${launch_args[@]}" >/dev/null
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

lintendo_ip_from_interface() {
  local name="$1"
  local interface="$2"
  incus exec "$name" -- sh -c 'ip -4 -o addr show dev "$1" scope global 2>/dev/null | while read -r _ _ _ cidr _; do ip="${cidr%/*}"; case "$ip" in 127.*|"") ;; *) printf "%s\n" "$ip"; exit 0 ;; esac; done' sh "$interface" 2>/dev/null || true
}

lintendo_ip_from_any_interface() {
  local name="$1"
  incus exec "$name" -- sh -c 'ip -4 -o addr show scope global 2>/dev/null | while read -r _ _ _ cidr _; do ip="${cidr%/*}"; case "$ip" in 127.*|"") ;; *) printf "%s\n" "$ip"; exit 0 ;; esac; done' 2>/dev/null || true
}

lintendo_instance_ip() {
  local name="$1"
  local ip
  ip="$(lintendo_ip_from_interface "$name" "${LINTENDO_INSTANCE_INTERFACE:-eth0}")"
  if [ -z "$ip" ]; then
    ip="$(lintendo_ip_from_any_interface "$name")"
  fi
  [ -n "$ip" ] || return 1
  printf '%s\n' "$ip"
}

lintendo_wait_instance_ip() {
  local name="$1"
  local timeout="${LINTENDO_IP_TIMEOUT_SECONDS:-60}"
  local interval="${LINTENDO_IP_POLL_INTERVAL_SECONDS:-2}"
  local elapsed=0
  local ip

  while [ "$elapsed" -lt "$timeout" ]; do
    ip="$(lintendo_instance_ip "$name" || true)"
    if [ -n "$ip" ]; then
      printf '%s\n' "$ip"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  printf 'timed out after %ss waiting for non-loopback IPv4 address on %s\n' "$timeout" "$name" >&2
  printf 'network interfaces reported by guest:\n' >&2
  incus exec "$name" -- ip -4 -o addr show >&2 2>/dev/null || printf '  unable to inspect guest IPv4 addresses\n' >&2
  return 1
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
