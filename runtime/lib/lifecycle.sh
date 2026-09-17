#!/usr/bin/env bash

lintendo_run_host_script() {
  local script="$1"
  local instance="$2"
  local ip="$3"
  local scenario_dir="$4"
  LINTENDO_INSTANCE_NAME="$instance" \
    LINTENDO_INSTANCE_IP="$ip" \
    LINTENDO_SCENARIO_DIR="$scenario_dir" \
    bash "$script" "$instance" "$ip"
}

lintendo_print_step() {
  printf '%s\n' "$1"
}

lintendo_prompt_yes_no() {
  local prompt="$1"
  local default_yes="${2:-yes}"
  local answer
  read -r -p "$prompt " answer || answer=""
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    "")
      [ "$default_yes" = "yes" ]
      ;;
    *) return 1 ;;
  esac
}

lintendo_cleanup_after_init_failure() {
  local instance="$1"
  if [ "${LINTENDO_PRESERVE_ON_FAILURE:-}" = "1" ]; then
    printf 'Preserving failed instance for debugging: %s\n' "$instance" >&2
    return
  fi

  if lintendo_prompt_yes_no "Destroy failed environment? [Y/n]" "yes"; then
    lintendo_destroy_instance "$instance" || true
    lintendo_clear_state
  else
    printf 'Preserved failed instance: %s\n' "$instance" >&2
  fi
}

lintendo_run() {
  local requested_id="$1"
  local scenario_dir manifest manifest_id image instance ip started_at
  local -a packages

  if lintendo_load_state; then
    lintendo_die "an active quest already exists: ${scenario_id:-unknown} (${instance_name:-unknown})"
  fi

  scenario_dir="$(lintendo_scenario_path "$requested_id")" || lintendo_die "invalid scenario id: $requested_id"
  lintendo_validate_scenario "$scenario_dir"
  manifest="$scenario_dir/quest.yaml"
  manifest_id="$(lintendo_yaml_scalar "$manifest" id)"
  [ "$manifest_id" = "$requested_id" ] || lintendo_die "scenario id mismatch: requested $requested_id, manifest has $manifest_id"
  image="$(lintendo_yaml_scalar "$manifest" image)"
  mapfile -t packages < <(lintendo_yaml_packages "$manifest")

  lintendo_require_incus

  instance="$(lintendo_instance_name "$requested_id")"
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  lintendo_print_step "Preparing environment..."
  lintendo_create_instance "$image" "$instance"
  lintendo_write_state "$requested_id" "$scenario_dir" "$instance" "$started_at"
  printf '✓ Instance created: %s\n' "$instance"

  if ! lintendo_wait_ready "$instance"; then
    printf '✗ Instance did not become ready\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  ip="$(lintendo_instance_ip "$instance")" || {
    printf '✗ Could not determine instance IP\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  }
  printf '✓ Instance ready: %s\n' "$ip"

  if ! lintendo_install_packages "$instance" "${packages[@]}"; then
    printf '✗ Dependency installation failed\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  printf '✓ Dependencies installed\n'

  if ! lintendo_push_assets "$instance" "$scenario_dir/assets"; then
    printf '✗ Asset transfer failed\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  printf '✓ Scenario assets transferred\n'

  if ! lintendo_exec_guest_script "$instance" "$scenario_dir/guest/setup.sh" "$ip"; then
    printf '✗ Guest setup failed\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  printf '✓ Scenario configured\n'

  lintendo_print_step ""
  lintendo_print_step "Checking baseline..."
  if ! lintendo_exec_guest_script "$instance" "$scenario_dir/guest/baseline.sh" "$ip"; then
    printf '✗ Guest baseline validation failed\n' >&2
    printf 'Scenario could not establish a known-good state.\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  if ! lintendo_run_host_script "$scenario_dir/host/baseline.sh" "$instance" "$ip" "$scenario_dir"; then
    printf '✗ Host baseline validation failed\n' >&2
    printf 'Scenario could not establish a known-good state.\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  printf '✓ Baseline verified\n'

  lintendo_print_step ""
  lintendo_print_step "Injecting incident..."
  if ! lintendo_exec_guest_script "$instance" "$scenario_dir/guest/inject.sh" "$ip"; then
    printf '✗ Injection failed\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  printf '✓ Injection executed\n'

  lintendo_print_step ""
  lintendo_print_step "Checking incident..."
  if ! lintendo_run_host_script "$scenario_dir/host/incident-check.sh" "$instance" "$ip" "$scenario_dir"; then
    printf '✗ Expected failure was not reproduced\n' >&2
    printf 'Scenario initialization failed.\n' >&2
    lintendo_cleanup_after_init_failure "$instance"
    return 1
  fi
  printf '✓ Incident verified\n'

  lintendo_print_step ""
  lintendo_yaml_block "$manifest" mission
  lintendo_print_step ""
  lintendo_print_step "Entering learner shell. Exit the shell to return to Lintendo."
  incus exec "$instance" -- bash

  if lintendo_prompt_yes_no "Verify solution? [Y/n]" "yes"; then
    if lintendo_verify; then
      if lintendo_prompt_yes_no "Destroy environment? [Y/n]" "yes"; then
        lintendo_destroy
      fi
    fi
  fi
}

lintendo_verify() {
  lintendo_require_active_state
  lintendo_validate_scenario "$scenario_path"
  lintendo_require_incus

  local ip
  ip="$(lintendo_instance_ip "$instance_name")" || lintendo_die "could not determine instance IP"

  if lintendo_run_host_script "$scenario_path/host/verify.sh" "$instance_name" "$ip" "$scenario_path"; then
    printf '✓ Endpoint externally reachable\n'
    printf '✓ Service operational\n'
    printf '\nINCIDENT RESOLVED\n'
  else
    printf 'INCIDENT NOT RESOLVED\n' >&2
    return 1
  fi
}

lintendo_status() {
  lintendo_require_active_state
  printf 'Active quest: %s\n' "$scenario_id"
  printf 'Instance: %s\n' "$instance_name"
  printf 'Scenario path: %s\n' "$scenario_path"
  printf 'Started: %s\n' "$started_at"
  if command -v incus >/dev/null 2>&1 && incus info "$instance_name" >/dev/null 2>&1; then
    incus list "$instance_name"
  fi
}

lintendo_destroy() {
  lintendo_require_active_state
  lintendo_require_incus
  lintendo_destroy_instance "$instance_name"
  lintendo_clear_state
  printf 'Destroyed environment: %s\n' "$instance_name"
}

