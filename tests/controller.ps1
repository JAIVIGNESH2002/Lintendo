$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("lintendo-controller-test-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  $env:LINTENDO_CONTROLLER_HOME = $tmp
  $controller = Join-Path $root "controller/lintendo.ps1"
  $mockBin = Join-Path $tmp "bin"
  New-Item -ItemType Directory -Force -Path $mockBin | Out-Null
  $sshLog = Join-Path $tmp "ssh.log"
  $mockSsh = Join-Path $mockBin "ssh.cmd"
  @"
@echo off
echo %*>>"$sshLog"
echo noisy-ssh-output
exit /b 0
"@ | Set-Content -Encoding ASCII $mockSsh
  $oldPath = $env:PATH
  $env:PATH = "$mockBin;$oldPath"

  & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine add phoenix --runtime-path /home/jv/Lintendo | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "machine add failed" }

  $configPath = Join-Path $tmp "machines.json"
  if (!(Test-Path $configPath)) { throw "machines.json was not created" }
  $config = Get-Content -Raw $configPath | ConvertFrom-Json
  if ($config.machines.phoenix.host -ne "phoenix") { throw "default host was not stored" }
  if ($config.machines.phoenix.runtime_path -ne "/home/jv/Lintendo") { throw "runtime path was not stored" }

  $list = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine list
  if ($list -notmatch "phoenix") { throw "machine list did not include phoenix" }

  $check = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine check phoenix
  if ($LASTEXITCODE -ne 0) { throw "machine check failed with mocked ssh" }
  $checkText = $check -join "`n"
  if ($checkText -notmatch "connection works") { throw "machine check did not report SSH success" }
  Set-Content -Encoding ASCII $sshLog ""
  & powershell -NoProfile -ExecutionPolicy Bypass -File $controller play linux/silent-service --verbose --machine phoenix | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "remote play forwarding failed with mocked ssh" }
  $sshText = Get-Content -Raw $sshLog
  if ($sshText -notmatch "--verbose") { throw "remote play did not forward --verbose" }
  if ($sshText -notmatch "linux/silent-service") { throw "remote play did not forward quest id" }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine remove phoenix | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "machine remove failed" }
  $config = Get-Content -Raw $configPath | ConvertFrom-Json
  if ($config.machines.PSObject.Properties.Name -contains "phoenix") { throw "machine was not removed" }

  $controllerText = Get-Content -Raw $controller
  if ($controllerText -notmatch "ssh @sshArgs") { throw "controller does not use OpenSSH" }
  if ($controllerText -match "return \$LASTEXITCODE") { throw "Invoke-Ssh must stream output rather than returning it" }
  if ($controllerText -notmatch '-t') { throw "controller does not allocate a PTY for play" }
  if ($controllerText -match "sshpass|StrictHostKeyChecking=no|docker.sock") { throw "unsafe SSH/controller pattern found" }

  Write-Host "Controller tests passed."
} finally {
  if ($oldPath) { $env:PATH = $oldPath }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  Remove-Item Env:LINTENDO_CONTROLLER_HOME -ErrorAction SilentlyContinue
}
