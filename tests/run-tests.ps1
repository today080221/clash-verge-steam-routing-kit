param([switch]$SkipNode)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\RoutingKit.psm1') -Force
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force
$script:count = 0
function Assert($Condition, [string]$Message) {
  if (-not $Condition) { throw "FAILED: $Message" }
  $script:count++; Write-Host "PASS $Message"
}
function Throws([scriptblock]$Body, [string]$Message) {
  $threw = $false
  try { & $Body | Out-Null } catch { $threw = $true }
  Assert $threw $Message
}
function Copy-Value($Value) { ConvertFrom-Json (ConvertTo-PrivacyJson $Value) }
function Policy($Entries) { [pscustomobject]@{ present = $true; kind = 'String'; raw = (ConvertTo-PrivacyJson @($Entries)) } }
function Entry([string]$Url, [string]$Handling = 'disable_non_proxied_udp') { [pscustomobject][ordered]@{ url = $Url; handling = $Handling } }
function Snapshot($Policy = $null, $Paths = @('C:\Program Files\WindowsApps\Claude_v1\app\Claude.exe')) {
  if (-not $Policy) { $Policy = [pscustomobject]@{ present = $false; kind = $null; raw = $null } }
  [pscustomobject]@{ sid = 'test-user'; policy = $Policy; paths = @($Paths); discoveryErrors = @(); rules = @() }
}
function Mock-Adapter($Snapshot) {
  $script:mock = Copy-Value $Snapshot
  $script:saved = $null; $script:failAdd = $false; $script:failPolicy = $false; $script:calls = @()
  @{
    SaveState = { param($s) $script:saved = Copy-Value $s }
    ReadPolicy = { $script:mock.policy }
    WritePolicy = { param($p) if ($script:failPolicy) { throw 'Simulated registry failure' }; $script:calls += 'Policy'; $script:mock.policy = Copy-Value $p }
    ReadRule = { param($n) $r = @($script:mock.rules | Where-Object { $_.name -eq $n }); if ($r.Count) { $r[0] } else { $null } }
    AddRule = { param($r) if ($script:failAdd) { throw 'Simulated access denied' }; $script:calls += 'AddRule'; $v = Copy-Value $r; $v.fingerprint = 'mock-filter-fingerprint'; $script:mock.rules += $v }
    RemoveRule = { param($n) $script:calls += 'RemoveRule'; $script:mock.rules = @($script:mock.rules | Where-Object { $_.name -ne $n }) }
  }
}

. (Join-Path $PSScriptRoot 'windows-adapter.tests.ps1')
. (Join-Path $PSScriptRoot 'native-cli.tests.ps1')
. (Join-Path $PSScriptRoot 'persistence.tests.ps1')
. (Join-Path $PSScriptRoot 'maintenance.tests.ps1')
. (Join-Path $PSScriptRoot 'quiet-host.tests.ps1')
. (Join-Path $PSScriptRoot 'runtime-integrity.tests.ps1')
. (Join-Path $PSScriptRoot 'noop-refresh.tests.ps1')
. (Join-Path $PSScriptRoot 'enablement.tests.ps1')

# Parse every PowerShell source without executing it (Windows PowerShell 5.1 too).
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') -and $_.FullName -notmatch '[\\/](?:\.git|\.test-tmp)[\\/]' } | ForEach-Object {
  $tokens = $null; $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  Assert ($errors.Count -eq 0) ('PowerShell parses: ' + $_.Name)
}

$s = Snapshot
$state = New-PrivacyState $s.sid
$plan = New-PrivacyPlan $s $state 'apply'
Assert ($plan.steps.Count -eq 2 -and $plan.steps[0].kind -eq 'AddRule') 'apply plans exact program rule before URL policy'
Assert ($null -eq $state.policy -and $state.rules.Count -eq 0) 'preview does not mutate state'
$a = Mock-Adapter $s
$applied = Invoke-PrivacyPlan $plan $state $a
Assert ($script:mock.rules.Count -eq 1 -and $script:mock.rules[0].protocol -eq 'UDP' -and $script:mock.rules[0].program -eq $s.paths[0]) 'only confirmed Claude executable receives UDP block'
$entries = Read-PrivacyPolicy $script:mock.policy
Assert ($entries.Count -eq 3 -and @($entries | Where-Object { $_.url -eq '*' -or $_.url -match 'usercontent|mcpcontent|claude.app' }).Count -eq 0) 'Chrome scope is three page domains, never global or all six network domains'
Assert ((New-PrivacyPlan $script:mock $applied 'apply').steps.Count -eq 0) 'apply is idempotent'
Assert ((New-PrivacyPlan $script:mock $applied 'refresh').steps.Count -eq 0) 'refresh is idempotent'
$rollback = New-PrivacyPlan $script:mock $applied 'rollback'
$rolled = Invoke-PrivacyPlan $rollback $applied $a
Assert (-not $script:mock.policy.present -and $script:mock.rules.Count -eq 0 -and $rolled.phase -eq 'RolledBack') 'rollback restores absent value and removes own exact rule'
Assert ((New-PrivacyPlan $script:mock $rolled 'rollback').steps.Count -eq 0) 'rollback is idempotent'
Throws { New-PrivacyPlan $script:mock $rolled 'refresh' } 'refresh after rollback cannot re-enable protection'

$pendingSnapshot = Snapshot
$pendingState = New-PrivacyState $pendingSnapshot.sid
$pendingState.phase = 'Pending'
$pendingPlan = New-PrivacyPlan $pendingSnapshot $pendingState 'apply'
$pendingAdapter = Mock-Adapter $pendingSnapshot
$recoveredState = Invoke-PrivacyPlan $pendingPlan $pendingState $pendingAdapter
Assert ($recoveredState.enabled -and $recoveredState.phase -eq 'AppliedConfigurationOnly' -and $script:mock.rules.Count -eq 1) 'explicit apply recovers a pending pre-rule journal through normal ownership checks'

$external = Entry 'https://[*.]example.org' 'default'
$s = Snapshot (Policy @($external))
$plan = New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply'
$merged = Read-PrivacyPolicy $plan.nextState.policy.applied
Assert ($merged.Count -eq 4 -and (Test-PrivacyEqual $merged[3] $external)) 'merge preserves unrelated policy and puts additions before broad matches'
$a = Mock-Adapter $s
$owned = Invoke-PrivacyPlan $plan (New-PrivacyState $s.sid) $a
$script:mock.policy = Policy @($merged + @(Entry 'https://later.example' 'default'))
$rb = New-PrivacyPlan $script:mock $owned 'rollback'
Invoke-PrivacyPlan $rb $owned $a | Out-Null
$remaining = Read-PrivacyPolicy $script:mock.policy
Assert ($remaining.Count -eq 2 -and $remaining[1].url -eq 'https://later.example') 'rollback retains unrelated user additions after apply'

$s = Snapshot (Policy @((Entry 'https://[*.]claude.ai'), (Entry 'https://[*.]claude.com'), (Entry 'https://[*.]anthropic.com')))
$plan = New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply'
Assert ($null -eq $plan.nextState.policy -and @($plan.steps | Where-Object { $_.kind -eq 'Policy' }).Count -eq 0) 'preexisting equal policy is never claimed or removed'
$s = Snapshot (Policy @((Entry 'https://[*.]claude.ai' 'default')))
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'conflicting existing URL policy is preserved'
$s = Snapshot (Policy @((Entry '*' 'default'), (Entry 'https://[*.]claude.ai')))
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'earlier wildcard precedence requires review'
$s = Snapshot (Policy @((Entry 'https://[*.]claude.ai'), (Entry 'https://[*.]claude.ai')))
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'duplicate policy entries fail closed'
$s = Snapshot ([pscustomobject]@{ present = $true; kind = 'DWord'; raw = '1' })
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'wrong registry type is preserved'
$s = Snapshot ([pscustomobject]@{ present = $true; kind = 'String'; raw = '[invalid' })
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'malformed policy JSON is preserved'
$s = Snapshot -Paths @()
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'no executable means no changes'
$s = Snapshot; $s.discoveryErrors = @('cannot inspect one running version')
Throws { New-PrivacyPlan $s (New-PrivacyState $s.sid) 'apply' } 'incomplete discovery cannot prune protection'
Throws { New-PrivacyRule 'C:\mihomo.exe' 'test-user' } 'proxy core cannot become UDP target'
Throws { New-PrivacyRule 'C:\*\Claude.exe' 'test-user' } 'wildcard executable path is forbidden'
Throws { New-PrivacyPlan (Snapshot) (New-PrivacyState 'other-user') 'apply' } 'cross-user state rejected'
Throws { New-PrivacyPlan (Snapshot) (New-PrivacyState 'test-user') 'refresh' } 'refresh cannot silently enable first-time protection'

$s = Snapshot; $a = Mock-Adapter $s; $st = New-PrivacyState $s.sid
$applied = Invoke-PrivacyPlan (New-PrivacyPlan $s $st 'apply') $st $a
$script:mock.paths = @('C:\Program Files\WindowsApps\Claude_v2\app\Claude.exe')
$refresh = New-PrivacyPlan $script:mock $applied 'refresh'
Assert ($refresh.steps.Count -eq 2 -and $refresh.steps[0].kind -eq 'AddRule' -and $refresh.steps[1].kind -eq 'RemoveRule') 'upgrade adds new path before retiring old path'
$updated = Invoke-PrivacyPlan $refresh $applied $a
Assert ($script:mock.rules.Count -eq 1 -and $script:mock.rules[0].program -match 'Claude_v2') 'refresh reconciles version paths'
$script:mock.paths += $s.paths[0]
Assert (@((New-PrivacyPlan $script:mock $updated 'refresh').nextState.rules).Count -eq 2) 'coexisting confirmed versions stay protected'
$script:mock.rules[0].fingerprint = 'user-changed-filter'
$conflict = New-PrivacyPlan $script:mock $updated 'rollback'
Assert ($conflict.conflicts.Count -eq 1 -and @($conflict.steps | Where-Object { $_.kind -eq 'RemoveRule' }).Count -eq 0) 'rollback preserves externally edited firewall filters'

$s = Snapshot; $st = New-PrivacyState $s.sid
$s.rules = @(New-PrivacyRule $s.paths[0] $s.sid)
$collision = New-PrivacyPlan $s $st 'apply'
Assert ($collision.conflicts.Count -eq 1) 'unowned firewall names are never adopted'
$a = Mock-Adapter $s
Throws { Invoke-PrivacyPlan $collision $st $a } 'apply conflict performs zero mutations'
Assert ($script:calls.Count -eq 0 -and $null -eq $script:saved) 'conflict does not write policy or ownership state'

$s = Snapshot; $st = New-PrivacyState $s.sid; $a = Mock-Adapter $s; $script:failAdd = $true
Throws { Invoke-PrivacyPlan (New-PrivacyPlan $s $st 'apply') $st $a } 'firewall access failure is visible'
Assert ($script:saved.phase -eq 'Failed' -and -not $script:mock.policy.present) 'firewall failure leaves Chrome unchanged with recoverable journal'
$a = Mock-Adapter $s; $script:failPolicy = $true
Throws { Invoke-PrivacyPlan (New-PrivacyPlan $s $st 'apply') $st $a } 'partial registry failure is visible'
Assert ($script:saved.phase -eq 'Failed' -and $script:mock.rules.Count -eq 1) 'partial success retains rule ownership'
$script:failPolicy = $false
$failed = Copy-Value $script:saved
Invoke-PrivacyPlan (New-PrivacyPlan $script:mock $failed 'rollback') $failed $a | Out-Null
Assert ($script:mock.rules.Count -eq 0 -and -not $script:mock.policy.present) 'rollback recovers partial failure'
$a = Mock-Adapter $s
$plan = New-PrivacyPlan $s $st 'apply'
$script:mock.policy = Policy @((Entry 'https://later.example' 'default'))
Throws { Invoke-PrivacyPlan $plan $st $a } 'concurrent Chrome modification is not overwritten'
Assert ((Read-PrivacyPolicy $script:mock.policy)[0].url -eq 'https://later.example') 'concurrent policy stays intact'

$s = Snapshot; $st = New-PrivacyState $s.sid; $a = Mock-Adapter $s
$owned = Invoke-PrivacyPlan (New-PrivacyPlan $s $st 'apply') $st $a
$edited = Read-PrivacyPolicy $script:mock.policy
$edited[0].handling = 'default'
$script:mock.policy = Policy $edited
Throws { New-PrivacyPlan $script:mock $owned 'refresh' } 'refresh never repairs user-edited Chrome values silently'
$rb = New-PrivacyPlan $script:mock $owned 'rollback'
Assert ($rb.conflicts.Count -eq 1) 'rollback reports modified managed Chrome entry'
$conflicted = Invoke-PrivacyPlan $rb $owned $a
$remaining = Read-PrivacyPolicy $script:mock.policy
Assert ($remaining.Count -eq 1 -and $remaining[0].handling -eq 'default' -and $conflicted.phase -eq 'Conflict') 'rollback removes only unchanged owned entries and preserves modified entry'
Assert ($script:mock.rules.Count -eq 0) 'Chrome conflict does not prevent safe firewall rollback'

$s = Snapshot; $st = New-PrivacyState $s.sid; $a = Mock-Adapter $s
$owned = Invoke-PrivacyPlan (New-PrivacyPlan $s $st 'apply') $st $a
$oldRule = Copy-Value $script:mock.rules[0]
$script:mock.paths = @('C:\Program Files\WindowsApps\Claude_v2\app\Claude.exe')
$script:failAdd = $true
Throws { Invoke-PrivacyPlan (New-PrivacyPlan $script:mock $owned 'refresh') $owned $a } 'upgrade failure to add new rule is visible'
Assert ($script:mock.rules.Count -eq 1 -and (Test-PrivacyEqual $script:mock.rules[0] $oldRule)) 'failed new-version protection never removes old rule'
$uncertain = Copy-Value $owned
$uncertain.rules[0].fingerprint = $null
Assert ((New-PrivacyPlan $script:mock $uncertain 'rollback').conflicts.Count -eq 1) 'interrupted creation without durable fingerprint requires manual review, never blind deletion'

# Fixture-only installation, synchronization, and legacy process migration.
$sandbox = Join-Path $root ('.test-tmp\' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox) | Out-Null
$target = Join-Path $sandbox 'clash'; $startup = Join-Path $sandbox 'startup'
[IO.Directory]::CreateDirectory((Join-Path $target 'profiles')) | Out-Null
[IO.Directory]::CreateDirectory($startup) | Out-Null
function global:Get-CimInstance { param($ClassName, $ErrorAction) @() }
try {
  $yamlPath = Join-Path $target 'profiles.yaml'; $customPath = Join-Path $target 'profiles\Script.js'
  Write-KitUtf8 $yamlPath "items:`n- uid: Owner`n  type: remote`n  option:`n    script: CustomOwner`n- uid: Other`n  type: remote`n  option:`n    script: null`n"
  Write-KitUtf8 $customPath 'const MANAGED_GROUP_NAMES = ["owner"]; function unique(items) { return items; } function main(config, profileName) { config.owner = unique(MANAGED_GROUP_NAMES)[0] === "owner"; config.ownerProfile = profileName; return config; }'
  $beforeYaml = Get-KitHash $yamlPath; $beforeCustom = Get-KitHash $customPath
  & (Join-Path $root 'install-steam-routing.ps1') -TargetRoot $target -StartupDir $startup -WhatIf
  Assert (-not (Test-Path -LiteralPath (Join-Path $target 'profiles\SteamRoutingKit.js'))) 'installer preview writes no managed script'
  & (Join-Path $root 'install-steam-routing.ps1') -TargetRoot $target -StartupDir $startup
  & (Join-Path $root 'sync-clash-verge-steam-script.ps1') -TargetRoot $target
  Assert ((Get-KitHash $yamlPath) -eq $beforeYaml -and (Get-KitHash $customPath) -eq $beforeCustom) 'install and sync preserve custom/empty bindings and legacy Script.js byte for byte'
  Assert (@(Get-ChildItem -LiteralPath $startup).Count -eq 0) 'ordinary install creates no autostart'
  $managed = Join-Path $target 'profiles\SteamRoutingKit.js'
  Write-KitUtf8 $managed 'user modification'
  Throws { & (Join-Path $root 'sync-clash-verge-steam-script.ps1') -TargetRoot $target } 'sync refuses to overwrite edited managed file'
  Assert ((Get-Content -LiteralPath $managed -Raw) -eq 'user modification') 'edited managed bytes preserved'
  $fresh = Join-Path $sandbox 'unowned'
  [IO.Directory]::CreateDirectory((Join-Path $fresh 'profiles')) | Out-Null
  Copy-Item -LiteralPath (Join-Path $root 'Script.js') -Destination (Join-Path $fresh 'profiles\SteamRoutingKit.js')
  Throws { Install-KitScript (Join-Path $root 'Script.js') $fresh } 'even equal unowned script requires explicit conflict resolution'
  Assert (Test-KitWatcherCommand 'powershell.exe -NoProfile -File "C:\Some Dir\sync.ps1"' 'C:\Some Dir\sync.ps1') 'legacy process argument exact match including spaces'
  Assert (-not (Test-KitWatcherCommand 'powershell.exe -Command "Get-Content C:\SomeDir\sync.ps1"' 'C:\SomeDir\sync.ps1')) 'diagnostic terminals are never killed by substring match'
  Assert (-not (Test-KitWatcherCommand 'powershell.exe -File C:\Other\sync.ps1' 'C:\SomeDir\sync.ps1')) 'other installation processes are excluded'
  Assert (-not (Test-KitWatcherCommand 'powershell.exe -Command Write-Host -File "C:\SomeDir\sync.ps1"' 'C:\SomeDir\sync.ps1')) 'embedded -File text inside -Command cannot match a watcher'
  Assert (Test-KitWatcherCommand 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Some Dir\sync.ps1" extra' 'C:\Some Dir\sync.ps1') 'exact watcher invocation still matches when script arguments follow'
  $legacy = Join-Path $fresh 'sync-clash-verge-steam-script.ps1'
  Write-KitUtf8 $legacy 'custom watcher'
  Throws { & (Join-Path $root 'install-steam-routing.ps1') -TargetRoot $fresh -StartupDir $startup -MigrateLegacy } 'migration refuses unknown/custom watcher before mutation'
  Assert ((Get-Content -LiteralPath $legacy -Raw) -eq 'custom watcher') 'custom watcher preserved'
  $migrationTarget = Join-Path $sandbox 'legacy-clash'
  [IO.Directory]::CreateDirectory((Join-Path $migrationTarget 'profiles')) | Out-Null
  $legacyPath = Join-Path $migrationTarget 'sync-clash-verge-steam-script.ps1'
  $startupPath = Join-Path $startup 'Start ClashVerge Steam Sync.vbs'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\legacy-sync.ps1.txt') -Destination $legacyPath
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\legacy-startup.vbs.txt') -Destination $startupPath
  Copy-Item -LiteralPath $yamlPath -Destination (Join-Path $migrationTarget 'profiles.yaml')
  Copy-Item -LiteralPath $customPath -Destination (Join-Path $migrationTarget 'profiles\Script.js')
  Assert (Test-KitLegacyScript $legacyPath) 'recognized legacy watcher fixture validates'
  $global:kitTestStopped = @(); $global:kitTestProcesses = @(
    [pscustomobject]@{ ProcessId = 10101; Name = 'powershell.exe'; CommandLine = ('powershell.exe -NoProfile -File "' + $legacyPath + '"') },
    [pscustomobject]@{ ProcessId = 10102; Name = 'powershell.exe'; CommandLine = 'powershell.exe -File C:\Other\sync-clash-verge-steam-script.ps1' }
  )
  function global:Get-CimInstance { param($ClassName, $ErrorAction) $global:kitTestProcesses }
  function global:Stop-Process { param($Id, [switch]$Force, $ErrorAction) $global:kitTestStopped += $Id }
  Throws { & (Join-Path $root 'install-steam-routing.ps1') -TargetRoot $migrationTarget -StartupDir $startup } 'ordinary install requires explicit legacy migration'
  & (Join-Path $root 'install-steam-routing.ps1') -TargetRoot $migrationTarget -StartupDir $startup -MigrateLegacy -WhatIf | Out-Null
  Assert ($global:kitTestStopped.Count -eq 0 -and (Test-Path -LiteralPath $legacyPath) -and (Test-Path -LiteralPath $startupPath)) 'migration preview cannot stop processes or disable autostart'
  & (Join-Path $root 'install-steam-routing.ps1') -TargetRoot $migrationTarget -StartupDir $startup -MigrateLegacy | Out-Null
  Assert ($global:kitTestStopped.Count -eq 1 -and $global:kitTestStopped[0] -eq 10101) 'migration stops only exact target legacy process (mock)'
  Assert (-not (Test-Path -LiteralPath $legacyPath) -and -not (Test-Path -LiteralPath $startupPath)) 'migration disables legacy script and startup entry'
  Assert (@(Get-ChildItem -LiteralPath $migrationTarget -Filter '*.disabled').Count -eq 1 -and @(Get-ChildItem -LiteralPath $startup -Filter '*.disabled').Count -eq 1) 'migration keeps both original files as backups'
  Assert ((Get-KitHash (Join-Path $migrationTarget 'profiles.yaml')) -eq $beforeYaml -and (Get-KitHash (Join-Path $migrationTarget 'profiles\Script.js')) -eq $beforeCustom) 'legacy migration preserves original scripts and subscription bindings'
  Remove-Item Function:\Stop-Process
  Remove-Variable kitTestStopped,kitTestProcesses -Scope Global
  $composition = Join-Path $sandbox 'composed.js'
  & (Join-Path $root 'compose-routing-script.ps1') -OwnerScriptPath $customPath -OutputPath $composition
  Throws { & (Join-Path $root 'compose-routing-script.ps1') -OwnerScriptPath $customPath -OutputPath $composition } 'composition refuses output overwrite'
  $zipPath = Join-Path $sandbox 'review.zip'
  & (Join-Path $root 'build-release.ps1') -OutputPath $zipPath -WhatIf
  Assert (-not (Test-Path -LiteralPath $zipPath)) 'packaging preview creates no archive'
  & (Join-Path $root 'build-release.ps1') -OutputPath $zipPath | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $actualEntries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') } | Sort-Object)
    $expectedEntries = @(Get-Content -LiteralPath (Join-Path $root 'release-files.txt') | Sort-Object)
    Assert (($actualEntries -join '|') -ceq ($expectedEntries -join '|')) 'release zip exactly matches explicit allowlist, including modules and domain interface'
    $scriptEntry = $zip.Entries | Where-Object { $_.FullName -eq 'Script.js' }
    $reader = New-Object IO.StreamReader($scriptEntry.Open())
    try { $packedScript = $reader.ReadToEnd() } finally { $reader.Dispose() }
    Assert ($packedScript -ceq (Get-Content -LiteralPath (Join-Path $root 'Script.js') -Raw -Encoding UTF8)) 'release uses current source bytes, not cached folders'
  } finally { $zip.Dispose() }
  Throws { & (Join-Path $root 'build-release.ps1') -OutputPath $zipPath } 'packaging preserves existing output'
  $zh = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw -Encoding UTF8
  $en = Get-Content -LiteralPath (Join-Path $root 'README.en.md') -Raw -Encoding UTF8
  Assert ([regex]::Matches($zh, '(?m)^## ').Count -eq [regex]::Matches($en, '(?m)^## ').Count -and [regex]::Matches($zh, '(?m)^### ').Count -eq [regex]::Matches($en, '(?m)^### ').Count) 'Chinese and English README section structure stays aligned'
  foreach ($entrypoint in @('install-steam-routing.bat','test-unity-routing.bat','claude-privacy.bat','enable-claude-privacy.bat')) {
    $content = Get-Content -LiteralPath (Join-Path $root $entrypoint) -Raw
    $expected = switch ($entrypoint) { 'install-steam-routing.bat' { 'bootstrap-install.ps1' }; 'test-unity-routing.bat' { 'test-unity-routing.ps1' }; 'claude-privacy.bat' { 'claude-privacy.ps1' }; 'enable-claude-privacy.bat' { 'enable-claude-privacy.ps1' } }
    Assert ($content.Contains($expected)) ('entrypoint retains expected target: ' + $entrypoint)
  }
  if (-not $SkipNode) {
    & node (Join-Path $PSScriptRoot 'routing.test.mjs') $composition
    Assert ($LASTEXITCODE -eq 0) 'public routing and composition behavior in JavaScript runtime'
  }
} finally {
  Remove-Item Function:\Get-CimInstance
  if (Test-Path Function:\Stop-Process) { Remove-Item Function:\Stop-Process }
  # Only delete this test's exact generated directory after containment validation.
  $resolved = [IO.Path]::GetFullPath($sandbox)
  $allowed = [IO.Path]::GetFullPath((Join-Path $root '.test-tmp')) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "All $script:count assertions passed. No machine policy/firewall/AppData writes were performed."
