param(
  [switch]$SkipUpdateCheck,
  [int]$TimeoutSec = 8,
  [string]$RepoOwner = "today080221",
  [string]$RepoName = "clash-verge-steam-routing-kit"
)

$ErrorActionPreference = "Stop"

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $packageRoot "install-steam-routing.ps1"
$versionFile = Join-Path $packageRoot "VERSION"
$cacheRoot = Join-Path $env:LOCALAPPDATA "ClashVergeSteamRoutingKit\\packages"
$apiHeaders = @{
  "User-Agent" = "clash-verge-steam-routing-kit-bootstrap"
  "Accept" = "application/vnd.github+json"
}

function Read-LocalVersion {
  if (Test-Path $versionFile) {
    $value = Get-Content -Path $versionFile -Encoding utf8 | Select-Object -First 1
    if ($null -ne $value) {
      $text = ([string]$value).Trim()
      if ($text) {
        return $text
      }
    }
  }

  return "v0.0.0"
}

function Convert-ToVersionObject {
  param([string]$Value)

  $normalized = ""
  if ($null -ne $Value) {
    $normalized = ([string]$Value).Trim()
  }

  if ($normalized.StartsWith("v") -or $normalized.StartsWith("V")) {
    $normalized = $normalized.Substring(1)
  }

  try {
    return [version]$normalized
  }
  catch {
    return [version]"0.0.0"
  }
}

function Test-IsTimeoutError {
  param([System.Exception]$Exception)

  $current = $Exception
  while ($null -ne $current) {
    $typeName = $current.GetType().FullName
    $message = ""

    if ($null -ne $current.Message) {
      $message = [string]$current.Message
    }

    if (
      $typeName -eq "System.TimeoutException" -or
      $typeName -eq "System.Threading.Tasks.TaskCanceledException" -or
      $typeName -eq "System.OperationCanceledException" -or
      $message -match "(?i)timed out" -or
      $message -match "(?i)timeout"
    ) {
      return $true
    }

    $current = $current.InnerException
  }

  return $false
}

function Invoke-InstallScript {
  param([string]$ScriptPath)

  if (-not (Test-Path $ScriptPath)) {
    throw "Install script not found: $ScriptPath"
  }

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
  return $LASTEXITCODE
}

function Get-LatestRelease {
  $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
  $release = Invoke-RestMethod -Uri $apiUrl -Headers $apiHeaders -TimeoutSec $TimeoutSec
  $asset = $release.assets | Where-Object { $_.name -like "clash-verge-steam-routing-kit-*.zip" } | Select-Object -First 1

  if (-not $asset) {
    throw "No release zip asset was found in the latest GitHub release."
  }

  return [pscustomobject]@{
    Tag = $release.tag_name
    Url = $release.html_url
    AssetName = $asset.name
    AssetUrl = $asset.browser_download_url
  }
}

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Ensure-ReleaseCached {
  param([pscustomobject]$Release)

  Ensure-Directory $cacheRoot

  $releaseDir = Join-Path $cacheRoot $Release.Tag
  $readyMarker = Join-Path $releaseDir ".ready"

  if (Test-Path $readyMarker) {
    return $releaseDir
  }

  $stagingRoot = Join-Path $env:TEMP ("clash-verge-steam-routing-kit-" + [guid]::NewGuid().ToString("N"))
  $zipPath = Join-Path $stagingRoot $Release.AssetName
  $extractDir = Join-Path $stagingRoot "package"

  Ensure-Directory $stagingRoot

  try {
    Write-Host "Found newer release $($Release.Tag). Downloading update from GitHub..."
    Invoke-WebRequest -Uri $Release.AssetUrl -OutFile $zipPath -Headers $apiHeaders -TimeoutSec $TimeoutSec

    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    if (Test-Path $releaseDir) {
      Remove-Item -Recurse -Force $releaseDir
    }

    Ensure-Directory $releaseDir
    Copy-Item -Path (Join-Path $extractDir "*") -Destination $releaseDir -Recurse -Force
    Set-Content -Path $readyMarker -Encoding utf8 -Value $Release.Tag

    return $releaseDir
  }
  finally {
    if (Test-Path $stagingRoot) {
      Remove-Item -Recurse -Force $stagingRoot
    }
  }
}

if ($SkipUpdateCheck) {
  Write-Host "Running local installer..."
  $exitCode = Invoke-InstallScript -ScriptPath $installScript
  exit $exitCode
}

try {
  $localVersion = Read-LocalVersion
  Write-Host "Current local launcher version: $localVersion"
  Write-Host "Checking GitHub for the latest release..."

  $latestRelease = Get-LatestRelease
  $latestVersion = Convert-ToVersionObject -Value $latestRelease.Tag
  $currentVersion = Convert-ToVersionObject -Value $localVersion

  if ($latestVersion -gt $currentVersion) {
    $cachedDir = Ensure-ReleaseCached -Release $latestRelease
    $cachedBootstrap = Join-Path $cachedDir "bootstrap-install.ps1"
    $cachedInstall = Join-Path $cachedDir "install-steam-routing.ps1"

    Write-Host "Switched to latest package $($latestRelease.Tag)."

    if (Test-Path $cachedBootstrap) {
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cachedBootstrap -SkipUpdateCheck
      exit $LASTEXITCODE
    }

    $exitCode = Invoke-InstallScript -ScriptPath $cachedInstall
    exit $exitCode
  }

  Write-Host "Local package is already at or above the latest release."
  $exitCode = Invoke-InstallScript -ScriptPath $installScript
  exit $exitCode
}
catch {
  if (Test-IsTimeoutError -Exception $_.Exception) {
    Write-Host "GitHub update check timed out."
    Write-Host "You can choose to run the local installer once, or exit."
    exit 20
  }

  Write-Host ("GitHub update check failed: " + $_.Exception.Message)
  exit 21
}
