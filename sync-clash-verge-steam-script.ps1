$ErrorActionPreference = "Stop"

$mutexName = "ClashVergeSteamScriptWatcher"
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
  exit 0
}

$rootDir = Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev"
$profilesPath = Join-Path $rootDir "profiles.yaml"
$logPath = Join-Path $rootDir "steam-script-sync.log"

function Write-Log {
  param([string]$Message)
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $logPath -Encoding utf8 -Value "[$timestamp] $Message"
}

function Restart-ClashVerge {
  $app = Get-Process clash-verge -ErrorAction SilentlyContinue
  $core = Get-Process verge-mihomo -ErrorAction SilentlyContinue

  if (-not $app) {
    Write-Log "Clash Verge not running, skip restart."
    return
  }

  $appPath = $app.Path

  if ($core) {
    Stop-Process -Id $core.Id -Force
  }

  Stop-Process -Id $app.Id -Force
  Start-Sleep -Seconds 2
  Start-Process -FilePath $appPath
  Write-Log "Clash Verge restarted to apply shared Steam script."
}

function Sync-ProfilesYaml {
  if (-not (Test-Path $profilesPath)) {
    return
  }

  $lines = Get-Content -Path $profilesPath -Encoding utf8
  $changed = $false
  $currentType = $null
  $inOption = $false

  for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]

    if ($line -match "^- uid: ") {
      $currentType = $null
      $inOption = $false
      continue
    }

    if ($line -match "^  type: (.+)$") {
      $currentType = $Matches[1]
      continue
    }

    if ($currentType -eq "remote" -and $line -eq "  option:") {
      $inOption = $true
      continue
    }

    if ($inOption -and $line -match "^    script: (.+)$") {
      if ($Matches[1] -ne "Script") {
        $lines[$i] = "    script: Script"
        $changed = $true
      }
      continue
    }

    if ($inOption -and $line -match "^  [^ ]") {
      $inOption = $false
    }
  }

  if ($changed) {
    Set-Content -Path $profilesPath -Encoding utf8 -Value $lines
    Write-Log "profiles.yaml updated: rebound remote scripts to Script."
    Restart-ClashVerge
  }
}

try {
  Write-Log "Steam script watcher started."

  while ($true) {
    Sync-ProfilesYaml
    Start-Sleep -Seconds 2
  }
}
finally {
  if ($mutex) {
    $mutex.ReleaseMutex() | Out-Null
    $mutex.Dispose()
  }
}
