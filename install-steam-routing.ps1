[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$TargetRoot = (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'),
  [string]$StartupDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
  [switch]$MigrateLegacy
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\RoutingKit.psm1') -Force
# Migration is explicit. Never overwrite Script.js, Merge.yaml or profiles.yaml.
$watchers = @(Get-KitLegacyWatchers $TargetRoot)
$startupPath = Join-Path $StartupDir 'Start ClashVerge Steam Sync.vbs'
$legacyScript = Join-Path $TargetRoot 'sync-clash-verge-steam-script.ps1'
if (($watchers.Count -gt 0 -or (Test-Path -LiteralPath $startupPath) -or (Test-Path -LiteralPath $legacyScript)) -and -not $MigrateLegacy) {
  throw 'Legacy sync detected. Close Clash, then preview/run install-steam-routing.ps1 -MigrateLegacy. Existing bindings and custom scripts will be preserved.'
}
if ($MigrateLegacy) {
  $legacyScript = Join-Path $TargetRoot 'sync-clash-verge-steam-script.ps1'
  if ((Test-Path -LiteralPath $legacyScript) -and -not (Test-KitLegacyScript $legacyScript)) {
    throw 'Installed watcher is not the recognized legacy version. Review and disable it manually; no process or file was changed.'
  }
  if ($watchers.Count -gt 0 -and -not (Test-Path -LiteralPath $legacyScript)) {
    throw 'Running watcher has no inspectable source. Review and stop it manually.'
  }
  $legacyLauncher = @'
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\sync-clash-verge-steam-script.ps1""", 0, False
'@
  if (Test-Path -LiteralPath $startupPath) {
    $actual = (Get-Content -LiteralPath $startupPath -Raw).Replace([string][char]13, '').Trim()
    if ($actual -cne $legacyLauncher.Replace([string][char]13, '').Trim()) {
      throw 'Startup launcher was customized. Disable it manually after review; migration did not overwrite it.'
    }
  }
  foreach ($watcher in $watchers) {
    if ($PSCmdlet.ShouldProcess("Legacy watcher PID $($watcher.ProcessId)", 'Stop exact installed watcher')) {
      $stillSame = @(Get-KitLegacyWatchers $TargetRoot | Where-Object { $_.ProcessId -eq $watcher.ProcessId -and $_.CommandLine -ceq $watcher.CommandLine })
      if ($stillSame.Count -eq 1) { Stop-Process -Id $watcher.ProcessId -Force -ErrorAction Stop }
    }
  }
  if ((Test-Path -LiteralPath $startupPath) -and $PSCmdlet.ShouldProcess($startupPath, 'Disable legacy autostart, keeping a backup')) {
    Move-Item -LiteralPath $startupPath -Destination ($startupPath + '.' + [guid]::NewGuid().ToString('N') + '.disabled')
  }
  $legacyScript = Join-Path $TargetRoot 'sync-clash-verge-steam-script.ps1'
  if ((Test-Path -LiteralPath $legacyScript) -and $PSCmdlet.ShouldProcess($legacyScript, 'Disable legacy sync script, keeping a backup')) {
    Move-Item -LiteralPath $legacyScript -Destination ($legacyScript + '.' + [guid]::NewGuid().ToString('N') + '.disabled')
  }
}
Install-KitScript -SourcePath (Join-Path $PSScriptRoot 'Script.js') -TargetRoot $TargetRoot -WhatIf:$WhatIfPreference
Write-Host 'Public script: profiles\SteamRoutingKit.js. All existing subscription bindings were preserved.'
Write-Host 'In Clash Verge, create a script enhancement card and copy this file into it; explicitly select that card for each desired subscription.'
Write-Host 'After future updates, copy the updated file into the same card. There is no background rebinding or automatic restart.'
