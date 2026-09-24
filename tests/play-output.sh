#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=../runtime/lib/lifecycle.sh
. runtime/lib/lifecycle.sh

assert_contains() {
  local text="$1"
  local expected="$2"
  case "$text" in
    *"$expected"*) ;;
    *)
      printf 'expected output to contain: %s\n' "$expected" >&2
      printf '%s\n' "$text" >&2
      exit 1
      ;;
  esac
}

assert_not_contains() {
  local text="$1"
  local unexpected="$2"
  case "$text" in
    *"$unexpected"*)
      printf 'expected output not to contain: %s\n' "$unexpected" >&2
      printf '%s\n' "$text" >&2
      exit 1
      ;;
    *) ;;
  esac
}

noisy_success() {
  printf 'apt package machinery\n'
  printf 'systemd setup machinery\n' >&2
  lintendo_verbose_step "Dependencies installed"
}

noisy_failure() {
  printf 'apt failed loudly\n'
  printf 'systemd failure details\n' >&2
  return 42
}

LINTENDO_PLAY_VERBOSE=0
normal_output="$(lintendo_run_play_stage "Preparing quest" "Quest prepared" "Lintendo could not prepare the quest environment." noisy_success 2>&1)"
assert_contains "$normal_output" "Preparing quest..."
assert_contains "$normal_output" "✓ Quest prepared"
assert_not_contains "$normal_output" "apt package machinery"
assert_not_contains "$normal_output" "systemd setup machinery"
assert_not_contains "$normal_output" "Dependencies installed"

LINTENDO_PLAY_VERBOSE=1
verbose_output="$(lintendo_run_play_stage "Preparing quest" "Quest prepared" "Lintendo could not prepare the quest environment." noisy_success 2>&1)"
assert_contains "$verbose_output" "✓ Dependencies installed"
assert_contains "$verbose_output" "✓ Quest prepared"
assert_not_contains "$verbose_output" "apt package machinery"
assert_not_contains "$verbose_output" "systemd setup machinery"

LINTENDO_PLAY_VERBOSE=0
set +e
failure_output="$(lintendo_run_play_stage "Preparing quest" "Quest prepared" "Lintendo could not prepare the quest environment." noisy_failure 2>&1)"
failure_status=$?
set -e
[ "$failure_status" -ne 0 ] || {
  printf 'failure stage unexpectedly succeeded\n' >&2
  exit 1
}
assert_contains "$failure_output" "✗ Preparing quest failed"
assert_contains "$failure_output" "Lintendo could not prepare the quest environment."
assert_contains "$failure_output" "Diagnostic:"
assert_contains "$failure_output" "apt failed loudly"
assert_contains "$failure_output" "systemd failure details"
assert_not_contains "$failure_output" "✓ Quest prepared"

if [ -t 1 ]; then
  printf 'play output tests require non-TTY execution for suppression assertions\n' >&2
  exit 1
fi

printf 'Play output tests passed.\n'
