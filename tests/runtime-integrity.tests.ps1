# Compile and validate a complete runtime in an isolated folder. ACL ownership
# is mocked here; real administrator ownership is checked during deployment.
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Maintenance.psm1') -Force
$fixture = Join-Path $root ('.test-tmp\runtime-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $fixture 'user') -Force
$module = Get-Module ClaudePrivacy.Maintenance
try {
  $result = & $module {
    param($Fixture,$SourceRoot)
    $script:fixtureState = Join-Path $Fixture 'user\state.json'
    function script:Get-PrivacyStatePath { $script:fixtureState }
    function script:Assert-PrivacyStateDirectory($Path,[switch]$Create) { }
    function script:Assert-PrivacyProtectedTree($Path) { }
    function script:Set-PrivacyAdministratorOwner($Path) { }
    function script:Save-PrivacyProtectedJson($Path,$Value) { [IO.File]::WriteAllText($Path, (ConvertTo-PrivacyJson $Value), (New-Object Text.UTF8Encoding($false))) }
    $manifest = Get-PrivacyRuntimeManifest $SourceRoot
    $runtime = Install-PrivacyRuntime $SourceRoot $manifest
    Assert-PrivacyRuntime $runtime
    $binary = Join-Path $runtime.runtimeRoot 'ClaudePrivacy.Host.exe'
    $initialHash = Get-PrivacyFileHash $binary
    $again = Install-PrivacyRuntime $SourceRoot $manifest
    $reused = (Test-PrivacyEqual $runtime $again) -and (Get-PrivacyFileHash $binary) -ceq $initialHash
    $bytes = [IO.File]::ReadAllBytes($binary)
    [IO.File]::WriteAllBytes($binary, ([byte[]]@($bytes + 0)))
    $binaryRejected = $false
    try { Assert-PrivacyRuntime $runtime } catch { $binaryRejected = $true }
    [IO.File]::WriteAllBytes($binary, $bytes)
    $buildPath = Join-Path $runtime.runtimeRoot 'runtime-build.json'
    $buildText = [IO.File]::ReadAllText($buildPath)
    $changed = $buildText.Replace($runtime.digest, 'ffffffffffffffffffffffff')
    [IO.File]::WriteAllText($buildPath, $changed)
    $buildRejected = $false
    try { Assert-PrivacyRuntime $runtime } catch { $buildRejected = $true }
    [IO.File]::WriteAllText($buildPath, $buildText)
    $stray = Join-Path $runtime.runtimeRoot 'ClaudePrivacy.Host.exe.config'
    [IO.File]::WriteAllText($stray, '<configuration/>')
    $extraRejected = $false
    try { Assert-PrivacyRuntime $runtime } catch { $extraRejected = $true }
    [IO.File]::Delete($stray)
    $source = Join-Path $runtime.runtimeRoot 'scripts\ClaudePrivacy.Host.cs'
    $sourceText = [IO.File]::ReadAllText($source)
    [IO.File]::AppendAllText($source, '// edited')
    $sourceRejected = $false
    try { Assert-PrivacyRuntime $runtime } catch { $sourceRejected = $true }
    [IO.File]::WriteAllText($source, $sourceText)
    Assert-PrivacyRuntime $runtime
    $legacyFiles = @($manifest.files | Where-Object { $_.relative -ne 'scripts/ClaudePrivacy.Host.cs' })
    $legacyDigest = (Get-PrivacyDigest (ConvertTo-PrivacyJson $legacyFiles)).Substring(0,24)
    $legacyRoot = Join-Path (Split-Path -Parent $script:fixtureState) ('runtime-' + $legacyDigest)
    [IO.Directory]::CreateDirectory((Join-Path $legacyRoot 'scripts')) | Out-Null
    foreach ($file in $legacyFiles) { [IO.File]::Copy((Join-Path $SourceRoot $file.relative), (Join-Path $legacyRoot $file.relative)) }
    $legacy = [pscustomobject]@{ runtimeRoot=$legacyRoot; digest=$legacyDigest; files=$legacyFiles }
    Assert-PrivacyRuntime $legacy
    [pscustomobject]@{ runtimeFormat=$runtime.runtimeFormat; fileCount=$runtime.files.Count; reused=$reused; binaryRejected=$binaryRejected; buildRejected=$buildRejected; extraRejected=$extraRejected; sourceRejected=$sourceRejected; legacyAccepted=$true }
  } $fixture $root
  Assert ($result.runtimeFormat -eq 2 -and $result.fileCount -eq 6 -and $result.reused) 'reviewed sources compile once into a pinned GUI executable and identical deployment reuses its verified build'
  Assert $result.binaryRejected 'runtime verification detects generated GUI executable tampering'
  Assert $result.buildRejected 'runtime verification rejects changed build provenance'
  Assert $result.extraRejected 'runtime verification rejects extra executable configuration files'
  Assert $result.sourceRejected 'runtime verification still checks every deployed source hash'
  Assert $result.legacyAccepted 'existing four-file runtime records remain readable for an ownership-aware upgrade'
} finally {
  $resolved = [IO.Path]::GetFullPath($fixture)
  $allowed = [IO.Path]::GetFullPath((Join-Path $root '.test-tmp')) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe runtime fixture cleanup target.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
Remove-Module ClaudePrivacy.Maintenance,ClaudePrivacy.Windows -ErrorAction SilentlyContinue
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force
