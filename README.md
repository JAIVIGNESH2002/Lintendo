# Lintendo

Lintendo is an open-source hands-on challenge platform prototype for Linux,
DevOps, infrastructure, and SRE skills.

This repository currently contains the V0 vertical slice:

- Bash runtime orchestration
- Incus system-container backend only
- Three scenarios: `linux/silent-service`, `linux/forbidden-config`, and
  `linux/restless-worker`
- Baseline, incident, and solution verification
- Minimal inspectable local state

The prototype is intentionally small. It does not implement search, publishing,
accounts, hosted environments, leaderboards, hints, or additional isolation
backends.

## Requirements

V0 is designed to run on a Linux host with Incus initialized.

For the first integration host, PHOENIX must provide:

- Debian 13 or compatible Linux host
- `bash`
- `incus` CLI configured for the current user
- Internet access from Incus instances
- Ability to launch `images:debian/13`
- Host `wget` for host-perspective HTTP verification

`wget` is isolated to the scenario host verifier scripts so it can later be
replaced by a self-contained verifier.

## Usage

```sh
./lintendo play linux/silent-service
./lintendo play linux/forbidden-config
./lintendo play linux/restless-worker
./lintendo verify
./lintendo status
./lintendo destroy
```

State is stored at:

```text
${LINTENDO_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/lintendo}/state
```

## Tests

Static tests that do not require Incus:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\static.ps1
```

Integration tests require a real Linux + Incus host:

```sh
tests/integration/silent-service-smoke.sh
tests/integration/forbidden-config-smoke.sh
tests/integration/restless-worker-smoke.sh
```
