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
  "scenarios/linux/silent-service/assets/blackmesa.service",
  "scenarios/linux/forbidden-config/quest.yaml",
  "scenarios/linux/forbidden-config/guest/setup.sh",
  "scenarios/linux/forbidden-config/guest/baseline.sh",
  "scenarios/linux/forbidden-config/guest/inject.sh",
  "scenarios/linux/forbidden-config/host/baseline.sh",
  "scenarios/linux/forbidden-config/host/incident-check.sh",
  "scenarios/linux/forbidden-config/host/verify.sh",
  "scenarios/linux/forbidden-config/assets/status-server.py",
  "scenarios/linux/forbidden-config/assets/blackmesa.service",
  "scenarios/linux/forbidden-config/assets/telemetry.conf",
  "scenarios/linux/restless-worker/quest.yaml",
  "scenarios/linux/restless-worker/guest/setup.sh",
  "scenarios/linux/restless-worker/guest/baseline.sh",
  "scenarios/linux/restless-worker/guest/inject.sh",
  "scenarios/linux/restless-worker/host/baseline.sh",
  "scenarios/linux/restless-worker/host/incident-check.sh",
  "scenarios/linux/restless-worker/host/verify.sh",
  "scenarios/linux/restless-worker/assets/status-server.py",
  "scenarios/linux/restless-worker/assets/blackmesa.service",
  "scenarios/linux/restless-worker/assets/worker.env",
  "tests/integration/forbidden-config-smoke.sh",
  "tests/integration/restless-worker-smoke.sh"
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
$forbiddenQuest = Join-Path $root "scenarios/linux/forbidden-config/quest.yaml"
$forbiddenService = Join-Path $root "scenarios/linux/forbidden-config/assets/blackmesa.service"
$forbiddenInject = Join-Path $root "scenarios/linux/forbidden-config/guest/inject.sh"
$forbiddenVerify = Join-Path $root "scenarios/linux/forbidden-config/host/verify.sh"
$workerQuest = Join-Path $root "scenarios/linux/restless-worker/quest.yaml"
$workerService = Join-Path $root "scenarios/linux/restless-worker/assets/blackmesa.service"
$workerEnv = Join-Path $root "scenarios/linux/restless-worker/assets/worker.env"
$workerInject = Join-Path $root "scenarios/linux/restless-worker/guest/inject.sh"
$workerIncident = Join-Path $root "scenarios/linux/restless-worker/host/incident-check.sh"
$workerVerify = Join-Path $root "scenarios/linux/restless-worker/host/verify.sh"

Assert-Contains $instance "bash -s <"
Assert-Contains $instance "--env `"LINTENDO_INSTANCE_NAME="
Assert-Contains $instance "lintendo_wait_instance_ip"
Assert-Contains $instance "ip -4 -o addr show dev"
Assert-Contains $lifecycle "LINTENDO_INSTANCE_IP="
Assert-Contains $lifecycle "host/verify\.sh"
Assert-NotContains $lifecycle "Endpoint externally reachable|Service operational"
Assert-Contains $quest "python3"
Assert-Contains $forbiddenQuest "python3"
Assert-Contains $workerQuest "python3"
Assert-Contains $forbiddenService "User=blackmesa"
Assert-NotContains $forbiddenService "Restart=on-failure"
Assert-Contains $forbiddenInject "telemetry.conf"
Assert-Contains $forbiddenInject "systemctl stop telemetry.service"
Assert-Contains $forbiddenInject "systemctl start telemetry.service"
Assert-Contains $forbiddenVerify "telemetry.service"
Assert-Contains $forbiddenVerify "Telemetry service active"
Assert-Contains $workerService "User=blackmesa"
Assert-Contains $workerService "Restart=on-failure"
Assert-Contains $workerService "EnvironmentFile=/etc/blackmesa/worker.env"
Assert-Contains $workerEnv "BLACKMESA_WORKER_MODE=process"
Assert-Contains $workerInject "BLACKMESA_WORKER_MODE=crash"
Assert-Contains $workerIncident "NRestarts"
Assert-Contains $workerVerify 'verify\$\(date \+%s%N\)\$\$'
Assert-Contains $workerVerify 'processed:\$token'
$workerFiles = Get-ChildItem (Join-Path $root "scenarios/linux/restless-worker") -Recurse -File
foreach ($file in $workerFiles) {
  Assert-NotContains $file.FullName "wget|curl|http|/health|8080"
}
Assert-Contains $hostVerify "wget"
Assert-Contains $hostBaseline "wget"
Assert-Contains $hostIncident "wget"

$readme = Join-Path $root "README.md"
$cli = Join-Path $root "lintendo"
Assert-Contains $readme "\./lintendo play linux/silent-service"
Assert-Contains $readme "\./lintendo play linux/forbidden-config"
Assert-Contains $readme "\./lintendo play linux/restless-worker"
Assert-NotContains $readme "\./lintendo run"
Assert-NotContains $cli "\srun\)"

Assert-NotContains $lifecycle "incus file push.*guest"
Assert-NotContains $lifecycle "incus file push.*host"
Assert-NotContains $lifecycle "search"
Assert-NotContains $lifecycle "leaderboard"

Write-Host "Static tests passed."
