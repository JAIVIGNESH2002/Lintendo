#!/usr/bin/env bash

lintendo_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

lintendo_state_dir() {
  printf '%s\n' "${LINTENDO_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/lintendo}"
}

lintendo_state_file() {
  printf '%s/state\n' "$(lintendo_state_dir)"
}

lintendo_repo_root() {
  printf '%s\n' "$LINTENDO_ROOT"
}

lintendo_scenario_path() {
  local scenario_id="$1"
  case "$scenario_id" in
    *..*|/*|*" "*|"")
      return 1
      ;;
  esac
  printf '%s/scenarios/%s\n' "$(lintendo_repo_root)" "$scenario_id"
}

lintendo_yaml_scalar() {
  local file="$1"
  local key="$2"
  awk -F ':' -v key="$key" '
    $1 == key {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$file"
}

lintendo_yaml_packages() {
  local file="$1"
  awk '
    /^[[:space:]]*packages:[[:space:]]*$/ { in_packages=1; next }
    in_packages && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      print
      next
    }
    in_packages && /^[^[:space:]-]/ { exit }
  ' "$file"
}

lintendo_yaml_capabilities() {
  local file="$1"
  awk '
    /^[[:space:]]*environment:[[:space:]]*$/ { in_environment=1; next }
    in_environment && /^[^[:space:]]/ { in_environment=0; in_capabilities=0 }
    in_environment && /^[[:space:]]*capabilities:[[:space:]]*$/ { in_capabilities=1; next }
    in_capabilities && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      print
      next
    }
    in_capabilities && /^[[:space:]]*[A-Za-z0-9_-]+:/ { in_capabilities=0 }
  ' "$file"
}

lintendo_validate_capabilities() {
  local manifest="$1"
  local capability
  while IFS= read -r capability; do
    case "$capability" in
      ""|nesting)
        ;;
      *)
        lintendo_die "unknown environment capability: $capability"
        ;;
    esac
  done < <(lintendo_yaml_capabilities "$manifest")
}

lintendo_yaml_block() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    $0 ~ "^" key ":[[:space:]]*\\|[[:space:]]*$" { in_block=1; next }
    in_block && /^[^[:space:]]/ { exit }
    in_block {
      sub(/^  /, "")
      print
    }
  ' "$file"
}

lintendo_validate_scenario() {
  local scenario_dir="$1"
  local manifest="$scenario_dir/quest.yaml"

  [ -d "$scenario_dir" ] || lintendo_die "scenario not found: $scenario_dir"
  [ -f "$manifest" ] || lintendo_die "missing quest.yaml"

  local required=(
    "guest/setup.sh"
    "guest/baseline.sh"
    "guest/inject.sh"
    "host/baseline.sh"
    "host/incident-check.sh"
    "host/verify.sh"
    "assets/status-server.py"
    "assets/blackmesa.service"
  )

  local item
  for item in "${required[@]}"; do
    [ -f "$scenario_dir/$item" ] || lintendo_die "missing scenario file: $item"
  done

  local id image
  id="$(lintendo_yaml_scalar "$manifest" id)"
  image="$(lintendo_yaml_scalar "$manifest" image)"
  [ -n "$id" ] || lintendo_die "quest.yaml missing id"
  [ -n "$image" ] || lintendo_die "quest.yaml missing image"
  lintendo_validate_capabilities "$manifest"
}

lintendo_load_state() {
  local file
  file="$(lintendo_state_file)"
  [ -f "$file" ] || return 1
  # shellcheck disable=SC1090
  . "$file"
}

lintendo_write_state() {
  local scenario_id="$1"
  local scenario_path="$2"
  local instance_name="$3"
  local started_at="$4"
  local dir file
  dir="$(lintendo_state_dir)"
  file="$(lintendo_state_file)"
  mkdir -p "$dir"
  {
    printf 'scenario_id=%q\n' "$scenario_id"
    printf 'scenario_path=%q\n' "$scenario_path"
    printf 'instance_name=%q\n' "$instance_name"
    printf 'started_at=%q\n' "$started_at"
  } > "$file"
}

lintendo_clear_state() {
  rm -f "$(lintendo_state_file)"
}

lintendo_require_active_state() {
  lintendo_load_state || lintendo_die "no active quest state found"
  [ -n "${scenario_id:-}" ] || lintendo_die "state missing scenario_id"
  [ -n "${scenario_path:-}" ] || lintendo_die "state missing scenario_path"
  [ -n "${instance_name:-}" ] || lintendo_die "state missing instance_name"
}
