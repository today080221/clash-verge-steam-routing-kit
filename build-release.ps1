[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
$destination = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($destination) -ne '.zip') { throw 'OutputPath must end in .zip.' }
if (Test-Path -LiteralPath $destination) { throw 'Output already exists; refusing to overwrite.' }
$files = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-files.txt') -Encoding UTF8 | Where-Object { $_.Trim() -and -not $_.StartsWith('#') })
if (@($files | Sort-Object -Unique).Count -ne $files.Count) { throw 'Duplicate release entries.' }
foreach ($file in $files) {
  if ($file -match '(^[/\\]|\.\.|[:*?])' -or -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw "Invalid or missing release file: $file" }
}
if (-not $PSCmdlet.ShouldProcess($destination, 'Build zip from current files in release-files.txt (no publishing)')) { return }
$stage = Join-Path $env:TEMP ('routing-kit-package-' + [guid]::NewGuid().ToString('N'))
try {
  [IO.Directory]::CreateDirectory($stage) | Out-Null
  foreach ($file in $files) {
    $target = Join-Path $stage $file
    [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $target
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($stage, $destination)
  Write-Output $destination
} finally {
  $resolved = [IO.Path]::GetFullPath($stage)
  $allowed = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\routing-kit-package-'
  if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe packaging cleanup path.' }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
