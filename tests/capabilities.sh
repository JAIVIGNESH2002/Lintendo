#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/incus" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LINTENDO_MOCK_INCUS_LOG:?}"
MOCK
chmod +x "$tmpdir/incus"

export PATH="$tmpdir:$PATH"
export LINTENDO_MOCK_INCUS_LOG="$tmpdir/incus.log"
export LINTENDO_ROOT="$PWD"

# shellcheck source=../runtime/lib/scenario.sh
. runtime/lib/scenario.sh
# shellcheck source=../runtime/lib/instance.sh
. runtime/lib/instance.sh

cat > "$tmpdir/with-nesting.yaml" <<'YAML'
id: docker/unreachable-database
image: images:debian/13
environment:
  capabilities:
    - nesting
dependencies:
  packages:
    - docker.io
YAML

cat > "$tmpdir/without-capabilities.yaml" <<'YAML'
id: linux/silent-service
image: images:debian/13
dependencies:
  packages:
    - python3
YAML

cat > "$tmpdir/unknown.yaml" <<'YAML'
id: docker/bad
image: images:debian/13
environment:
  capabilities:
    - privileged
YAML

mapfile -t capabilities < <(lintendo_yaml_capabilities "$tmpdir/with-nesting.yaml")
[ "${#capabilities[@]}" -eq 1 ] && [ "${capabilities[0]}" = "nesting" ]

lintendo_create_instance images:debian/13 nested-test "${capabilities[@]}"
grep -Fxq 'launch images:debian/13 nested-test -c security.nesting=true' "$LINTENDO_MOCK_INCUS_LOG"

: > "$LINTENDO_MOCK_INCUS_LOG"
mapfile -t capabilities < <(lintendo_yaml_capabilities "$tmpdir/without-capabilities.yaml")
[ "${#capabilities[@]}" -eq 0 ]
lintendo_create_instance images:debian/13 ordinary-test "${capabilities[@]}"
grep -Fxq 'launch images:debian/13 ordinary-test' "$LINTENDO_MOCK_INCUS_LOG"
if grep -q 'security.nesting=true' "$LINTENDO_MOCK_INCUS_LOG"; then
  printf 'ordinary container launch unexpectedly enabled nesting\n' >&2
  exit 1
fi

if ( lintendo_validate_capabilities "$tmpdir/unknown.yaml" ) 2>/dev/null; then
  printf 'unknown capability was accepted\n' >&2
  exit 1
fi

printf 'Capability tests passed.\n'
