Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-KitHash([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Write-KitUtf8([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Install-KitScript {
  [CmdletBinding(SupportsShouldProcess)]
  param([string]$SourcePath, [string]$TargetRoot)
  # The UI owns registration and every subscription binding. Never parse/rewrite YAML.
  $destination = Join-Path $TargetRoot 'profiles\SteamRoutingKit.js'
  $statePath = Join-Path $TargetRoot 'steam-routing-kit-state.json'
  $sourceHash = Get-KitHash $SourcePath
  $state = $null
  if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.schemaVersion -ne 1 -or $state.file -ne 'SteamRoutingKit.js') { throw 'Unrecognized routing-kit ownership state.' }
  }
  if (Test-Path -LiteralPath $destination) {
    $currentHash = Get-KitHash $destination
    if (-not $state -or $currentHash -ne $state.sha256) {
      throw 'SteamRoutingKit.js is unowned or edited. Preserve it and resolve manually; no file was overwritten.'
    }
    if ($currentHash -eq $sourceHash) { return [pscustomobject]@{ Status = 'Unchanged'; Path = $destination } }
  }
  if ($PSCmdlet.ShouldProcess($destination, 'Install public routing script; preserve all subscription bindings')) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    if (Test-Path -LiteralPath $destination) {
      Copy-Item -LiteralPath $destination -Destination ($destination + '.' + [guid]::NewGuid().ToString('N') + '.bak')
    }
    Copy-Item -LiteralPath $SourcePath -Destination $destination
    Write-KitUtf8 $statePath ([ordered]@{ schemaVersion = 1; file = 'SteamRoutingKit.js'; sha256 = $sourceHash } | ConvertTo-Json)
  }
  [pscustomobject]@{ Status = 'InstallPlannedOrCompleted'; Path = $destination }
}
function Test-KitWatcherCommand([string]$CommandLine, [string]$ScriptPath) {
  # Recognize PowerShell launch options, not a -File string embedded in -Command.
  if ($CommandLine -match '(?i)^(?:"[^"]+"|\S+)\s+(?:(?:-NoLogo|-NoProfile|-NonInteractive|-ExecutionPolicy\s+\S+|-WindowStyle\s+\S+)\s+)*-File\s+(?:"([^"]+)"|([^\s]+))(?:\s|$)') {
    $path = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
    return [string]::Equals($path, $ScriptPath, [StringComparison]::OrdinalIgnoreCase)
  }
  return $false
}
function Test-KitLegacyScript([string]$Path) {
  $text = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Replace([string][char]13, '').Trim()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
  $hash -eq '1b32f13825c0d503c051e367ad19d640bc497c73a3e46dd4660df2c5815832f0'
}
function Get-KitLegacyWatchers([string]$TargetRoot) {
  $path = Join-Path $TargetRoot 'sync-clash-verge-steam-script.ps1'
  @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.ProcessId -ne $PID -and $_.Name -in @('powershell.exe', 'pwsh.exe') -and
    (Test-KitWatcherCommand ([string]$_.CommandLine) $path)
  })
}
function Get-KitComposition([string]$PublicScript, [string]$OwnerScript) {
  # Each script's helpers and main are lexically isolated. Neither is executed here.
  @"
// Generated explicitly: public routing first, owner enhancement second.
const __steamRoutingKit = (() => {
$PublicScript
return main;
})();
const __ownerEnhancement = (() => {
$OwnerScript
return main;
})();
function main(config, profileName) {
  const shared = __steamRoutingKit(config, profileName);
  const result = __ownerEnhancement(shared, profileName);
  if (!result || typeof result !== "object" || Array.isArray(result) || typeof result.then === "function") {
    throw new Error("Owner main must synchronously return a config object");
  }
  return result;
}
"@
}
Export-ModuleMember -Function *-Kit*
