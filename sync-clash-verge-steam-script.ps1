[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$TargetRoot = (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'),
  [switch]$Audit
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\RoutingKit.psm1') -Force
# Compatibility entrypoint: no loop, subscription rebinding, or Clash restart.
if ($Audit) {
  $state = Join-Path $TargetRoot 'steam-routing-kit-state.json'
  if (-not (Test-Path -LiteralPath $state)) { throw 'No managed routing-kit installation found.' }
  $manifest = Get-Content -LiteralPath $state -Raw -Encoding UTF8 | ConvertFrom-Json
  $file = Join-Path $TargetRoot 'profiles\SteamRoutingKit.js'
  [pscustomobject]@{ Status = $(if ((Test-Path -LiteralPath $file) -and (Get-KitHash $file) -eq $manifest.sha256) { 'OwnedFileUnchanged' } else { 'MissingOrEdited' }); Path = $file }
} else {
  Install-KitScript -SourcePath (Join-Path $PSScriptRoot 'Script.js') -TargetRoot $TargetRoot -WhatIf:$WhatIfPreference
}
