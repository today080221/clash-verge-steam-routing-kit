[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$OwnerScriptPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\RoutingKit.psm1') -Force
if (Test-Path -LiteralPath $OutputPath) { throw 'Output already exists. Use a new output path to preserve your previous composition.' }
$public = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Script.js') -Raw -Encoding UTF8
$owner = Get-Content -LiteralPath $OwnerScriptPath -Raw -Encoding UTF8
if ($PSCmdlet.ShouldProcess($OutputPath, 'Compose public main then owner main without executing either')) {
  Write-KitUtf8 $OutputPath (Get-KitComposition $public $owner)
}
