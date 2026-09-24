$ErrorActionPreference = "Stop"
Set-PSDebug -Off

function Usage {
  @"
Usage:
  lintendo machine add <name> [--host <host>] [--user <user>] [--port <port>] [--identity <path>] [--runtime-path <path>]
  lintendo machine list
  lintendo machine remove <name>
  lintendo machine check <name>

  lintendo play <quest> --machine <name>
  lintendo status --machine <name>
  lintendo verify --machine <name>
  lintendo destroy --machine <name>

Remote Play V0 uses OpenSSH and an existing Lintendo runtime on the remote Linux machine.
"@
}

function Config-Dir {
  if ($env:LINTENDO_CONTROLLER_HOME) {
    return $env:LINTENDO_CONTROLLER_HOME
  }
  return Join-Path $env:APPDATA "Lintendo"
}

function Config-Path {
  return Join-Path (Config-Dir) "machines.json"
}

function Load-Config {
  $path = Config-Path
  if (!(Test-Path $path)) {
    return [ordered]@{ machines = @{} }
  }
  $raw = Get-Content -Raw $path
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [ordered]@{ machines = @{} }
  }
  $data = $raw | ConvertFrom-Json
  $machines = @{}
  if ($data.machines) {
    $data.machines.PSObject.Properties | ForEach-Object {
      $machines[$_.Name] = $_.Value
    }
  }
  return [ordered]@{ machines = $machines }
}

function Save-Config($config) {
  $dir = Config-Dir
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = [ordered]@{ machines = [ordered]@{} }
  foreach ($key in ($config.machines.Keys | Sort-Object)) {
    $out.machines[$key] = $config.machines[$key]
  }
  $out | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Config-Path)
}

function Require-Name($name) {
  if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[^A-Za-z0-9_.-]') {
    throw "Invalid machine name: $name"
  }
}

function Parse-Options($argv, $start) {
  $options = @{}
  $positionals = @()
  $i = $start
  while ($i -lt $argv.Count) {
    $arg = $argv[$i]
    switch ($arg) {
      "--host" { $i++; $options.host = $argv[$i] }
      "--user" { $i++; $options.user = $argv[$i] }
      "--port" { $i++; $options.port = [int]$argv[$i] }
      "--identity" { $i++; $options.identity = $argv[$i] }
      "--runtime-path" { $i++; $options.runtime_path = $argv[$i] }
      "--machine" { $i++; $options.machine = $argv[$i] }
      default { $positionals += $arg }
    }
    $i++
  }
  return @{ options = $options; positionals = $positionals }
}

function Get-Machine($name) {
  Require-Name $name
  $config = Load-Config
  if (!$config.machines.ContainsKey($name)) {
    throw "Unknown machine: $name"
  }
  return $config.machines[$name]
}

function Ssh-Args($machine, [bool]$tty) {
  $sshArgs = @()
  if ($tty) { $sshArgs += "-t" }
  if ($machine.port) {
    $sshArgs += @("-p", [string]$machine.port)
  }
  if ($machine.identity) {
    $sshArgs += @("-i", [string]$machine.identity)
  }
  $target = [string]$machine.host
  if ($machine.user) {
    $target = "$($machine.user)@$target"
  }
  $sshArgs += $target
  return $sshArgs
}

function Shell-Quote($value) {
  return "'" + ([string]$value).Replace("'", "'\''") + "'"
}

function Remote-Lintendo-Command($machine, $runtimeArgs) {
  $joinedArgs = ($runtimeArgs | ForEach-Object { Shell-Quote $_ }) -join " "
  if ($machine.runtime_path) {
    $path = Shell-Quote $machine.runtime_path
    return "cd $path && ./lintendo $joinedArgs"
  }
  return "lintendo $joinedArgs"
}

function Invoke-Ssh($machine, $remoteCommand, [bool]$tty) {
  $sshArgs = Ssh-Args $machine $tty
  $sshArgs += $remoteCommand
  & ssh @sshArgs
}

function Machine-Add($argv) {
  if ($argv.Count -lt 1) { throw "machine add requires a name" }
  $name = $argv[0]
  Require-Name $name
  $parsed = Parse-Options $argv 1
  $options = $parsed.options
  $machine = [ordered]@{
    name = $name
    host = $(if ($options.host) { $options.host } else { $name })
  }
  if ($options.user) { $machine.user = $options.user }
  if ($options.port) { $machine.port = $options.port }
  if ($options.identity) { $machine.identity = $options.identity }
  if ($options.runtime_path) { $machine.runtime_path = $options.runtime_path }

  $config = Load-Config
  $config.machines[$name] = [pscustomobject]$machine
  Save-Config $config
  Write-Host "Machine added: $name"
}

function Machine-List {
  $config = Load-Config
  foreach ($name in ($config.machines.Keys | Sort-Object)) {
    $machine = $config.machines[$name]
    $runtime = if ($machine.runtime_path) { $machine.runtime_path } else { "(PATH)" }
    Write-Host "$name`t$($machine.host)`t$runtime"
  }
}

function Machine-Remove($argv) {
  if ($argv.Count -ne 1) { throw "machine remove requires a name" }
  $name = $argv[0]
  Require-Name $name
  $config = Load-Config
  if (!$config.machines.ContainsKey($name)) {
    throw "Unknown machine: $name"
  }
  $config.machines.Remove($name)
  Save-Config $config
  Write-Host "Machine removed: $name"
}

function Machine-Check($argv) {
  if ($argv.Count -ne 1) { throw "machine check requires a name" }
  $machine = Get-Machine $argv[0]

  Invoke-Ssh $machine "true" $false
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Cannot connect to $($machine.name) over SSH" }
  Write-Host "✓ SSH connection works"

  Invoke-Ssh $machine 'uname -s | grep -qx Linux' $false
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Connected to $($machine.name), but remote OS is not Linux" }
  Write-Host "✓ Remote OS is Linux"

  if ($machine.runtime_path) {
    $runtimeCheck = "test -x $(Shell-Quote $machine.runtime_path)/lintendo"
  } else {
    $runtimeCheck = 'command -v lintendo >/dev/null 2>&1'
  }
  Invoke-Ssh $machine $runtimeCheck $false
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Connected to $($machine.name), but Lintendo runtime was not found" }
  Write-Host "✓ Lintendo runtime exists/reachable"

  Invoke-Ssh $machine 'command -v incus >/dev/null 2>&1 && incus list --format csv >/dev/null' $false
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Connected to $($machine.name), but Incus is not usable by this user" }
  Write-Host "✓ Incus is usable by remote user"
}

function Remote-Runtime($command, $argv) {
  $parsed = Parse-Options $argv 0
  $machineName = $parsed.options.machine
  if (!$machineName) {
    throw "Remote Play V0 requires --machine for controller commands on Windows"
  }
  $machine = Get-Machine $machineName
  $runtimeArgs = @($command) + $parsed.positionals
  $remoteCommand = Remote-Lintendo-Command $machine $runtimeArgs
  $needsTty = ($command -eq "play")
  Invoke-Ssh $machine $remoteCommand $needsTty
  exit $LASTEXITCODE
}

try {
  if ($args.Count -eq 0 -or $args[0] -in @("-h", "--help", "help")) {
    Usage
    exit 0
  }

  switch ($args[0]) {
    "machine" {
      if ($args.Count -lt 2) { throw "machine requires a subcommand" }
      $rest = @($args | Select-Object -Skip 2)
      switch ($args[1]) {
        "add" { Machine-Add $rest }
        "list" { Machine-List }
        "remove" { Machine-Remove $rest }
        "check" { Machine-Check $rest }
        default { throw "Unknown machine subcommand: $($args[1])" }
      }
    }
    "play" {
      if ($args.Count -lt 2) { throw "play requires a quest id" }
      $quest = $args[1]
      $rest = @($args | Select-Object -Skip 2)
      Remote-Runtime "play" (@($quest) + $rest)
    }
    "status" { Remote-Runtime "status" (@($args | Select-Object -Skip 1)) }
    "verify" { Remote-Runtime "verify" (@($args | Select-Object -Skip 1)) }
    "destroy" { Remote-Runtime "destroy" (@($args | Select-Object -Skip 1)) }
    default { throw "Unknown command: $($args[0])" }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
