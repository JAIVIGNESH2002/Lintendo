#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/incus" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

count_file="${LINTENDO_MOCK_COUNT:?}"
count="$(cat "$count_file" 2>/dev/null || printf '0')"
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

if [ "$1" = "exec" ]; then
  if [ "$count" -ge 3 ]; then
    printf '10.155.0.19\n'
  fi
  exit 0
fi

exit 1
MOCK

cat > "$tmpdir/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod +x "$tmpdir/incus" "$tmpdir/sleep"

export PATH="$tmpdir:$PATH"
export LINTENDO_MOCK_COUNT="$tmpdir/count"
export LINTENDO_IP_TIMEOUT_SECONDS=10
export LINTENDO_IP_POLL_INTERVAL_SECONDS=1

# shellcheck source=../runtime/lib/instance.sh
. runtime/lib/instance.sh

ip="$(lintendo_wait_instance_ip test-instance)"

if [ "$ip" != "10.155.0.19" ]; then
  printf 'expected delayed IP 10.155.0.19, got %s\n' "$ip" >&2
  exit 1
fi

printf 'IP discovery test passed.\n'
