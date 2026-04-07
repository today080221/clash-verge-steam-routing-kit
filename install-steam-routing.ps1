$ErrorActionPreference = "Stop"

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetRoot = Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev"
$targetProfiles = Join-Path $targetRoot "profiles"
$startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$watcherScriptPath = Join-Path $targetRoot "sync-clash-verge-steam-script.ps1"

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Ensure-ScriptItem {
  param([string]$ProfilesPath)

  if (-not (Test-Path $ProfilesPath)) {
    return
  }

  $lines = Get-Content -Path $ProfilesPath -Encoding utf8
  $hasScriptItem = $false
  $inScript = $false
  $changed = $false
  $insertAt = -1

  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]

    if ($line -eq "items:" -and $insertAt -lt 0) {
      $insertAt = $i + 1
    }

    if ($line -match "^- uid: Script$") {
      $hasScriptItem = $true
      $inScript = $true
      continue
    }

    if ($inScript -and $line -match "^  updated: ") {
      $lines[$i] = "  updated: 1775490000"
      $changed = $true
      $inScript = $false
      continue
    }

    if ($inScript -and $line -match "^- uid: ") {
      $inScript = $false
    }
  }

  if (-not $hasScriptItem -and $insertAt -ge 0) {
    $scriptBlock = @(
      "- uid: Script"
      "  type: script"
      "  name: null"
      "  file: Script.js"
      "  updated: 1775490000"
    )
    $before = if ($insertAt -gt 0) { $lines[0..($insertAt - 1)] } else { @() }
    $after = if ($insertAt -lt $lines.Length) { $lines[$insertAt..($lines.Length - 1)] } else { @() }
    $lines = @($before + $scriptBlock + $after)
    $changed = $true
  }

  if ($changed) {
    Set-Content -Path $ProfilesPath -Encoding utf8 -Value $lines
  }
}

function Get-WatcherProcesses {
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'sync-clash-verge-steam-script\.ps1' }
}

function Stop-WatcherProcesses {
  $processes = @(Get-WatcherProcesses)
  foreach ($process in $processes) {
    try {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    }
    catch {
    }
  }

  return $processes.Count -gt 0
}

Ensure-Directory $targetRoot
Ensure-Directory $targetProfiles
Ensure-Directory $startupDir

$watcherWasRunning = Stop-WatcherProcesses

Copy-Item -Force (Join-Path $sourceRoot "Script.js") (Join-Path $targetProfiles "Script.js")
Copy-Item -Force (Join-Path $sourceRoot "Merge.yaml") (Join-Path $targetProfiles "Merge.yaml")
Copy-Item -Force (Join-Path $sourceRoot "sync-clash-verge-steam-script.ps1") $watcherScriptPath
Copy-Item -Force (Join-Path $sourceRoot "Start ClashVerge Steam Sync.vbs") (Join-Path $startupDir "Start ClashVerge Steam Sync.vbs")

$profilesPath = Join-Path $targetRoot "profiles.yaml"
Ensure-ScriptItem $profilesPath

if ($watcherWasRunning -or -not (Get-WatcherProcesses)) {
  Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $watcherScriptPath | Out-Null
}

Write-Host "Installed Clash Verge Steam and Unity routing pack."
Write-Host "If Clash Verge Rev is open, restart it once or switch subscriptions once."
