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
  $mockSsh = Join-Path $tmp "ssh.ps1"
  @"
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$SshArgs)
if (`$SshArgs -is [array]) {
  `$line = [string]::Join(" ", `$SshArgs)
} else {
  `$line = [string]`$SshArgs
}
Add-Content -Encoding ASCII "$sshLog" `$line
`$compact = `$line -replace "\s", ""
`$mode = `$env:LINTENDO_MOCK_SSH_MODE
if (![string]::IsNullOrWhiteSpace(`$mode)) { `$mode = `$mode.Trim() } else { `$mode = "healthy" }

if (`$mode -eq "ssh-failure") {
  exit 255
}

if (`$compact -match "uname-s\|grep-qxLinux") {
  if (`$mode -eq "non-linux") { exit 1 }
  exit 0
}

if (`$compact -match "uname") {
  if (`$mode -eq "non-linux") {
    Write-Output "Darwin"
    Write-Output "x86_64"
    exit 0
  }
  Write-Output "Linux"
  Write-Output "x86_64"
  exit 0
}

if (`$compact -match "command-vsudo") {
  exit 0
}

if (`$compact -match "command-vincus") {
  if (`$mode -eq "incus-missing") { exit 1 }
  Write-Output "/usr/bin/incus"
  exit 0
}

if (`$compact -match "id-nG") {
  if (`$mode -eq "incus-inaccessible") {
    Write-Output "jv sudo incus-admin"
    exit 0
  }
  Write-Output "jv sudo incus-admin"
  exit 0
}

if (`$compact -match "incuslist--formatcsv") {
  if (`$mode -eq "incus-inaccessible" -or `$mode -eq "incus-missing") { exit 1 }
  exit 0
}

if (`$compact -match "incusprofileshowdefault") {
  if (`$mode -eq "incus-uninitialized") { exit 1 }
  exit 0
}

if (`$compact -match "incusstoragelist") {
  if (`$mode -eq "incus-uninitialized") { exit 1 }
  Write-Output "default"
  exit 0
}

if (`$compact -match "incusnetworklist") {
  if (`$mode -eq "incus-uninitialized") { exit 1 }
  Write-Output "incusbr0,bridge,YES"
  exit 0
}

if (`$compact -match "test-x.*/lintendo" -or `$compact -match "command-vlintendo") {
  if (`$mode -eq "runtime-missing") { exit 1 }
  exit 0
}

Write-Output "noisy-ssh-output"
exit 0
"@ | Set-Content -Encoding ASCII $mockSsh
  $oldPath = $env:PATH
  $oldSsh = $env:LINTENDO_SSH
  $env:PATH = "$mockBin;$oldPath"
  $env:LINTENDO_SSH = $mockSsh

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

  function Invoke-Doctor($mode) {
    if ($mode) {
      $env:LINTENDO_MOCK_SSH_MODE = $mode
    } else {
      Remove-Item Env:LINTENDO_MOCK_SSH_MODE -ErrorAction SilentlyContinue
    }
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller machine doctor phoenix 2>&1
    return @{ code = $LASTEXITCODE; text = ($output -join "`n") }
  }

  $doctor = Invoke-Doctor "healthy"
  if ($doctor.code -ne 0) { throw "healthy doctor should succeed: $($doctor.text)`nSSH log:`n$(Get-Content -Raw $sshLog)" }
  if ($doctor.text -notmatch "Machine is ready for Lintendo") { throw "healthy doctor did not report readiness" }
  if ($doctor.text -notmatch "Linux x86_64") { throw "healthy doctor did not report architecture" }
  if ($doctor.text -notmatch "Incus daemon access") { throw "healthy doctor did not check Incus access" }
  if ($doctor.text -notmatch "Storage available") { throw "healthy doctor did not check storage" }
  if ($doctor.text -notmatch "Networking available") { throw "healthy doctor did not check networking" }

  $doctor = Invoke-Doctor "ssh-failure"
  if ($doctor.code -eq 0 -or $doctor.text -notmatch "SSH connection failed") { throw "doctor did not distinguish SSH failure" }

  $doctor = Invoke-Doctor "non-linux"
  if ($doctor.code -eq 0 -or $doctor.text -notmatch "Remote OS is not Linux") { throw "doctor did not distinguish non-Linux target" }
  if ($doctor.text -notmatch "Incus not checked") { throw "doctor did not skip Incus on non-Linux" }

  $doctor = Invoke-Doctor "incus-missing"
  if ($doctor.code -eq 0 -or $doctor.text -notmatch "Incus not installed") { throw "doctor did not distinguish missing Incus" }
  if ($doctor.text -notmatch "Storage not checked") { throw "doctor did not skip storage when Incus is missing" }

  $doctor = Invoke-Doctor "incus-inaccessible"
  if ($doctor.code -eq 0 -or $doctor.text -notmatch "Current user cannot access Incus daemon") { throw "doctor did not distinguish inaccessible Incus" }
  if ($doctor.text -notmatch "Storage not checked") { throw "doctor did not skip storage when Incus is inaccessible" }

  $doctor = Invoke-Doctor "incus-uninitialized"
  if ($doctor.code -eq 0 -or $doctor.text -notmatch "Incus not initialized") { throw "doctor did not distinguish uninitialized Incus" }
  if ($doctor.text -notmatch "No usable storage pool") { throw "doctor did not report missing storage" }
  if ($doctor.text -notmatch "No usable managed bridge network") { throw "doctor did not report missing networking" }

  $doctor = Invoke-Doctor "runtime-missing"
  if ($doctor.code -eq 0 -or $doctor.text -notmatch "Runtime not found") { throw "doctor did not distinguish missing runtime" }

  Remove-Item Env:LINTENDO_MOCK_SSH_MODE -ErrorAction SilentlyContinue

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
  if ($controllerText -notmatch "Ssh-Executable") { throw "controller does not route through OpenSSH helper" }
  if ($controllerText -match "return \$LASTEXITCODE") { throw "Invoke-Ssh must stream output rather than returning it" }
  if ($controllerText -notmatch '-t') { throw "controller does not allocate a PTY for play" }
  if ($controllerText -match "sshpass|StrictHostKeyChecking=no|docker.sock") { throw "unsafe SSH/controller pattern found" }

  Write-Host "Controller tests passed."
} finally {
  if ($oldPath) { $env:PATH = $oldPath }
  if ($oldSsh) { $env:LINTENDO_SSH = $oldSsh } else { Remove-Item Env:LINTENDO_SSH -ErrorAction SilentlyContinue }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  Remove-Item Env:LINTENDO_CONTROLLER_HOME -ErrorAction SilentlyContinue
  Remove-Item Env:LINTENDO_MOCK_SSH_MODE -ErrorAction SilentlyContinue
}
