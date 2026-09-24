$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("lintendo-controller-test-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  $env:LINTENDO_CONTROLLER_HOME = $tmp
  $controller = Join-Path $root "controller/lintendo.ps1"

  & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine add phoenix --runtime-path /home/jv/Lintendo | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "machine add failed" }

  $configPath = Join-Path $tmp "machines.json"
  if (!(Test-Path $configPath)) { throw "machines.json was not created" }
  $config = Get-Content -Raw $configPath | ConvertFrom-Json
  if ($config.machines.phoenix.host -ne "phoenix") { throw "default host was not stored" }
  if ($config.machines.phoenix.runtime_path -ne "/home/jv/Lintendo") { throw "runtime path was not stored" }

  $list = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine list
  if ($list -notmatch "phoenix") { throw "machine list did not include phoenix" }

  & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine remove phoenix | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "machine remove failed" }
  $config = Get-Content -Raw $configPath | ConvertFrom-Json
  if ($config.machines.PSObject.Properties.Name -contains "phoenix") { throw "machine was not removed" }

  $controllerText = Get-Content -Raw $controller
  if ($controllerText -notmatch "ssh @sshArgs") { throw "controller does not use OpenSSH" }
  if ($controllerText -notmatch '-t') { throw "controller does not allocate a PTY for play" }
  if ($controllerText -match "sshpass|StrictHostKeyChecking=no|docker.sock") { throw "unsafe SSH/controller pattern found" }

  Write-Host "Controller tests passed."
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  Remove-Item Env:LINTENDO_CONTROLLER_HOME -ErrorAction SilentlyContinue
}

