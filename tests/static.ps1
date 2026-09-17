$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Assert-Exists($Path) {
  if (!(Test-Path $Path)) {
    throw "Missing expected path: $Path"
  }
}

function Assert-Contains($Path, $Pattern) {
  $text = Get-Content -Raw $Path
  if ($text -notmatch $Pattern) {
    throw "Expected pattern not found in ${Path}: $Pattern"
  }
}

function Assert-NotContains($Path, $Pattern) {
  $text = Get-Content -Raw $Path
  if ($text -match $Pattern) {
    throw "Unexpected pattern found in ${Path}: $Pattern"
  }
}

$required = @(
  "lintendo",
  "runtime/lib/instance.sh",
  "runtime/lib/scenario.sh",
  "runtime/lib/lifecycle.sh",
  "runtime/README.md",
  "scenarios/linux/silent-service/quest.yaml",
  "scenarios/linux/silent-service/guest/setup.sh",
  "scenarios/linux/silent-service/guest/baseline.sh",
  "scenarios/linux/silent-service/guest/inject.sh",
  "scenarios/linux/silent-service/host/baseline.sh",
  "scenarios/linux/silent-service/host/incident-check.sh",
  "scenarios/linux/silent-service/host/verify.sh",
  "scenarios/linux/silent-service/assets/status-server.py",
  "scenarios/linux/silent-service/assets/blackmesa.service"
)

foreach ($item in $required) {
  Assert-Exists (Join-Path $root $item)
}

$lifecycle = Join-Path $root "runtime/lib/lifecycle.sh"
$instance = Join-Path $root "runtime/lib/instance.sh"
$quest = Join-Path $root "scenarios/linux/silent-service/quest.yaml"
$hostVerify = Join-Path $root "scenarios/linux/silent-service/host/verify.sh"
$hostBaseline = Join-Path $root "scenarios/linux/silent-service/host/baseline.sh"
$hostIncident = Join-Path $root "scenarios/linux/silent-service/host/incident-check.sh"

Assert-Contains $instance "bash -s <"
Assert-Contains $instance "--env `"LINTENDO_INSTANCE_NAME="
Assert-Contains $instance "lintendo_wait_instance_ip"
Assert-Contains $instance "ip -4 -o addr show dev"
Assert-Contains $lifecycle "LINTENDO_INSTANCE_IP="
Assert-Contains $lifecycle "host/verify\.sh"
Assert-Contains $quest "python3"
Assert-Contains $hostVerify "wget"
Assert-Contains $hostBaseline "wget"
Assert-Contains $hostIncident "wget"

Assert-NotContains $lifecycle "incus file push.*guest"
Assert-NotContains $lifecycle "incus file push.*host"
Assert-NotContains $lifecycle "search"
Assert-NotContains $lifecycle "leaderboard"

Write-Host "Static tests passed."
