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

lintendo_verbose_step() {
  [ "${LINTENDO_PLAY_VERBOSE:-0}" = "1" ] || return 0
  [ -n "${LINTENDO_VERBOSE_LOG:-}" ] || return 0
  printf '✓ %s\n' "$1" >> "$LINTENDO_VERBOSE_LOG"
}

lintendo_spinner_wait() {
  local pid="$1"
  local label="$2"
  local frame
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

  while kill -0 "$pid" >/dev/null 2>&1; do
    for frame in "${frames[@]}"; do
      kill -0 "$pid" >/dev/null 2>&1 || break
      printf '\r%s %s...' "$frame" "$label"
      sleep 0.1
    done
  done
}

lintendo_print_diagnostic() {
  local log="$1"
  [ -s "$log" ] || return 0

  printf '\nDiagnostic:\n' >&2
  tail -n 80 "$log" >&2
}

lintendo_run_play_stage() {
  local label="$1"
  local success="$2"
  local failure="$3"
  shift 3

  local raw_log safe_log status
  raw_log="$(mktemp)"
  safe_log="$(mktemp)"

  if [ -t 1 ]; then
    LINTENDO_VERBOSE_LOG="$safe_log" "$@" >"$raw_log" 2>&1 &
    local pid=$!
    lintendo_spinner_wait "$pid" "$label"
    if wait "$pid"; then
      status=0
    else
      status=$?
    fi
    printf '\r\033[K'
  else
    printf '%s...\n' "$label"
    if LINTENDO_VERBOSE_LOG="$safe_log" "$@" >"$raw_log" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi

  if [ "$status" -eq 0 ]; then
    if [ "${LINTENDO_PLAY_VERBOSE:-0}" = "1" ] && [ -s "$safe_log" ]; then
      cat "$safe_log"
    fi
    printf '✓ %s\n' "$success"
  else
    printf '✗ %s failed\n' "$label" >&2
    printf '\n%s\n' "$failure" >&2
    lintendo_print_diagnostic "$raw_log"
  fi

  rm -f "$raw_log" "$safe_log"
  return "$status"
}

lintendo_play_create_environment() {
  lintendo_create_instance "$LINTENDO_PLAY_IMAGE" "$LINTENDO_PLAY_INSTANCE" "${LINTENDO_PLAY_CAPABILITIES[@]}"
  lintendo_write_state "$LINTENDO_PLAY_SCENARIO_ID" "$LINTENDO_PLAY_SCENARIO_DIR" "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_STARTED_AT"
  lintendo_verbose_step "Instance created"

  lintendo_wait_ready "$LINTENDO_PLAY_INSTANCE"
  lintendo_verbose_step "Instance ready"

  local ip
  ip="$(lintendo_wait_instance_ip "$LINTENDO_PLAY_INSTANCE")"
  printf '%s\n' "$ip" > "$LINTENDO_PLAY_IP_FILE"
  lintendo_verbose_step "Network ready"
}

lintendo_play_prepare_quest() {
  lintendo_install_packages "$LINTENDO_PLAY_INSTANCE" "${LINTENDO_PLAY_PACKAGES[@]}"
  lintendo_verbose_step "Dependencies installed"

  lintendo_push_assets "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_SCENARIO_DIR/assets"
  lintendo_verbose_step "Scenario assets transferred"

  lintendo_exec_guest_script "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_SCENARIO_DIR/guest/setup.sh" "$LINTENDO_PLAY_INSTANCE_IP"
  lintendo_verbose_step "Scenario configured"
}

lintendo_play_verify_scenario() {
  lintendo_exec_guest_script "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_SCENARIO_DIR/guest/baseline.sh" "$LINTENDO_PLAY_INSTANCE_IP"
  lintendo_run_host_script "$LINTENDO_PLAY_SCENARIO_DIR/host/baseline.sh" "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_INSTANCE_IP" "$LINTENDO_PLAY_SCENARIO_DIR"
  lintendo_verbose_step "Baseline verified"

  lintendo_exec_guest_script "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_SCENARIO_DIR/guest/inject.sh" "$LINTENDO_PLAY_INSTANCE_IP"
  lintendo_verbose_step "Incident initialized"

  lintendo_run_host_script "$LINTENDO_PLAY_SCENARIO_DIR/host/incident-check.sh" "$LINTENDO_PLAY_INSTANCE" "$LINTENDO_PLAY_INSTANCE_IP" "$LINTENDO_PLAY_SCENARIO_DIR"
  lintendo_verbose_step "Incident verified"
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

lintendo_play() {
  local requested_id="$1"
  local verbose="${2:-0}"
  local scenario_dir manifest manifest_id image instance ip started_at title ip_file start_seconds elapsed
  local -a packages
  local -a capabilities

  if lintendo_load_state; then
    lintendo_die "an active quest already exists: ${scenario_id:-unknown} (${instance_name:-unknown})"
  fi

  scenario_dir="$(lintendo_scenario_path "$requested_id")" || lintendo_die "invalid scenario id: $requested_id"
  lintendo_validate_scenario "$scenario_dir"
  manifest="$scenario_dir/quest.yaml"
  manifest_id="$(lintendo_yaml_scalar "$manifest" id)"
  [ "$manifest_id" = "$requested_id" ] || lintendo_die "scenario id mismatch: requested $requested_id, manifest has $manifest_id"
  title="$(lintendo_yaml_scalar "$manifest" name)"
  [ -n "$title" ] || title="$requested_id"
  image="$(lintendo_yaml_scalar "$manifest" image)"
  mapfile -t packages < <(lintendo_yaml_packages "$manifest")
  mapfile -t capabilities < <(lintendo_yaml_capabilities "$manifest")

  lintendo_require_incus

  instance="$(lintendo_instance_name "$requested_id")"
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ip_file="$(mktemp)"
  start_seconds="$SECONDS"

  LINTENDO_PLAY_VERBOSE="$verbose"
  LINTENDO_PLAY_SCENARIO_ID="$requested_id"
  LINTENDO_PLAY_SCENARIO_DIR="$scenario_dir"
  LINTENDO_PLAY_IMAGE="$image"
  LINTENDO_PLAY_INSTANCE="$instance"
  LINTENDO_PLAY_STARTED_AT="$started_at"
  LINTENDO_PLAY_IP_FILE="$ip_file"
  LINTENDO_PLAY_PACKAGES=("${packages[@]}")
  LINTENDO_PLAY_CAPABILITIES=("${capabilities[@]}")

  lintendo_print_step "Preparing $title..."
  lintendo_print_step ""

  if ! lintendo_run_play_stage \
    "Creating environment" \
    "Environment created" \
    "Lintendo could not create a usable quest environment." \
    lintendo_play_create_environment; then
    lintendo_cleanup_after_init_failure "$instance"
    rm -f "$ip_file"
    return 1
  fi

  ip="$(cat "$ip_file")"
  LINTENDO_PLAY_INSTANCE_IP="$ip"

  if ! lintendo_run_play_stage \
    "Preparing quest" \
    "Quest prepared" \
    "Lintendo could not prepare the quest environment." \
    lintendo_play_prepare_quest; then
    lintendo_cleanup_after_init_failure "$instance"
    rm -f "$ip_file"
    return 1
  fi

  if ! lintendo_run_play_stage \
    "Verifying scenario" \
    "Scenario verified" \
    "Lintendo could not establish the quest's starting state." \
    lintendo_play_verify_scenario; then
    lintendo_cleanup_after_init_failure "$instance"
    rm -f "$ip_file"
    return 1
  fi

  rm -f "$ip_file"
  elapsed=$((SECONDS - start_seconds))

  lintendo_print_step ""
  lintendo_print_step "Ready in ${elapsed}s"
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
