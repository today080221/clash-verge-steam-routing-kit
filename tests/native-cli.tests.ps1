# Metadata classification and discovery fixtures; never starts an executable.
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Windows.psm1') -Force
$signer = 'CN="Anthropic, PBC", O="Anthropic, PBC", C=US'
Assert ((Get-PrivacyExecutableKind 'Valid' $signer 'Claude' 'Anthropic') -eq 'Desktop') 'valid desktop signature and exact product/company classify as Desktop'
Assert ((Get-PrivacyExecutableKind 'Valid' $signer 'Claude Code' 'Anthropic PBC') -eq 'NativeCli') 'valid native CLI signature and exact product/company classify separately'
foreach ($status in @('NotSigned','HashMismatch','UnknownError')) {
  Assert ((Get-PrivacyExecutableKind $status $signer 'Claude Code' 'Anthropic PBC') -eq 'Unverified') ('native CLI rejects untrusted signature status ' + $status)
}
Assert ((Get-PrivacyExecutableKind 'Valid' 'CN=Other, O=Other' 'Claude Code' 'Anthropic PBC') -eq 'Unverified') 'product strings alone never establish native CLI identity'
Assert ((Get-PrivacyExecutableKind 'Valid' $signer 'Claude Code' 'Anthropic') -eq 'Unverified') 'native CLI rejects the wrong company metadata even with a trusted signer'
Assert ((Get-PrivacyExecutableKind 'Valid' $signer 'Other Tool' 'Anthropic PBC') -eq 'Unverified') 'trusted publisher alone never accepts another product'
Assert ((Get-PrivacyExecutableIdentity 'C:\Unrelated\node.exe').kind -eq 'Unverified') 'native CLI support never accepts or targets a node.exe host'

$module = Get-Module ClaudePrivacy.Windows
$results = & $module {
  $desktop = 'C:\Program Files\WindowsApps\Claude_fixture\app\Claude.exe'
  $native = 'C:\Users\Fixture\.local\bin\claude.exe'
  $oldDesktop = 'C:\Program Files\WindowsApps\Claude_old\app\Claude.exe'
  $oldNative = 'C:\VerifiedOldCli\claude.exe'
  $unknown = 'C:\Unverified\claude.exe'
  $script:fixtureNativePath = $native
  $script:fixtureRunningPaths = @($native)
  $script:fixtureKinds = @{ $desktop='Desktop'; $native='NativeCli'; $oldDesktop='Desktop'; $oldNative='NativeCli' }
  function script:Get-AppxPackage { param($Name,$ErrorAction) [pscustomobject]@{ PackageFamilyName='Claude_pzs8sxrjxfjjc'; Status='Ok'; InstallLocation='C:\Program Files\WindowsApps\Claude_fixture' } }
  function script:Get-PrivacyNativeCliPath { $script:fixtureNativePath }
  function script:Get-Process { param($Name,$ErrorAction) foreach ($p in $script:fixtureRunningPaths) { [pscustomobject]@{ Path=$p } } }
  function script:Get-PrivacyExecutableIdentity([string]$Path) {
    $kind = if ($script:fixtureKinds.ContainsKey($Path)) { $script:fixtureKinds[$Path] } else { 'Unverified' }
    [pscustomobject]@{ path=$Path; kind=$kind; reason='Fixture identity result' }
  }
  $desktopOnly = Get-PrivacyDiscovery
  $both = Get-PrivacyDiscovery -ProtectionScope DesktopAndCli
  $script:fixtureRunningPaths = @()
  $notRunning = Get-PrivacyDiscovery -ProtectionScope DesktopAndCli
  $script:fixtureRunningPaths = @($oldDesktop,$oldNative)
  $coexist = Get-PrivacyDiscovery -ProtectionScope DesktopAndCli
  $script:fixtureRunningPaths = @($unknown)
  $unknownResult = Get-PrivacyDiscovery
  $script:fixtureRunningPaths = @()
  $explicitOutsideScope = Get-PrivacyDiscovery -ClaudePath @($native)
  $script:fixtureKinds.Remove($native)
  $missingNative = Get-PrivacyDiscovery -ProtectionScope DesktopAndCli
  $script:fixtureKinds[$native] = 'Desktop'
  $wrongNative = Get-PrivacyDiscovery -ProtectionScope DesktopAndCli
  $script:fixtureKinds[$native] = 'NativeCli'; $script:fixtureKinds[$desktop] = 'NativeCli'
  $wrongMsix = Get-PrivacyDiscovery -ProtectionScope DesktopAndCli
  $script:fixtureKinds[$desktop] = 'Desktop'; $script:fixtureRunningPaths = @($null)
  $unreadable = Get-PrivacyDiscovery
  [pscustomobject]@{ desktopOnly=$desktopOnly; both=$both; notRunning=$notRunning; coexist=$coexist; unknown=$unknownResult; explicitOutsideScope=$explicitOutsideScope; missingNative=$missingNative; wrongNative=$wrongNative; wrongMsix=$wrongMsix; unreadable=$unreadable }
}
Assert ($results.desktopOnly.errors.Count -eq 0 -and $results.desktopOnly.paths.Count -eq 1 -and $results.desktopOnly.excluded.Count -eq 1 -and $results.desktopOnly.excluded[0].kind -eq 'NativeCli') 'desktop-only discovery ignores a verified same-name CLI without expanding protection or failing refresh'
Assert ($results.both.errors.Count -eq 0 -and $results.both.paths.Count -eq 2 -and @($results.both.executables | Where-Object { $_.kind -eq 'NativeCli' }).Count -eq 1) 'explicit combined scope discovers and deduplicates the official native CLI and desktop paths'
Assert ($results.notRunning.errors.Count -eq 0 -and $results.notRunning.paths.Count -eq 2) 'native installation remains discovered and protected after its process exits'
Assert ($results.coexist.errors.Count -eq 0 -and $results.coexist.paths.Count -eq 4) 'verified running older desktop and CLI versions remain alongside current installations'
Assert ($results.unknown.errors.Count -eq 1) 'unverified same-name process still stops discovery instead of being silently excluded'
Assert ($results.explicitOutsideScope.errors.Count -eq 1) 'an explicit CLI path does not silently opt a desktop-only user into broader protection'
Assert ($results.missingNative.errors.Count -eq 1) 'missing or unverified selected native installation blocks pruning of existing protection'
Assert ($results.wrongNative.errors.Count -eq 1 -and $results.wrongMsix.errors.Count -eq 1) 'installation source and product kind must agree in both directions'
Assert ($results.unreadable.errors.Count -eq 1) 'unreadable running executable identity still fails closed'
Remove-Module ClaudePrivacy.Windows
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force

$s = Snapshot (Policy @((Entry 'https://[*.]claude.ai'),(Entry 'https://[*.]claude.com'),(Entry 'https://[*.]anthropic.com')))
$initial = New-PrivacyState $s.sid
$initial.PSObject.Properties.Remove('protectionScope')
Assert ((Get-PrivacyProtectionScope $initial) -eq 'Desktop') 'legacy journals without a scope remain desktop-only'
$adapter = Mock-Adapter $s
$desktopState = Invoke-PrivacyPlan (New-PrivacyPlan $s $initial 'apply') $initial $adapter
$script:mock | Add-Member NoteProperty protectionScope 'DesktopAndCli'
$script:mock.paths += 'C:\Users\Fixture\.local\bin\claude.exe'
$optIn = New-PrivacyPlan $script:mock $desktopState 'apply'
Assert ($optIn.steps.Count -eq 1 -and $optIn.steps[0].kind -eq 'AddRule' -and $optIn.nextState.protectionScope -eq 'DesktopAndCli') 'explicit opt-in adds only the native CLI rule and persists selected scope'
Throws { New-PrivacyPlan $script:mock $desktopState 'refresh' } 'automatic refresh cannot silently expand protection scope'
$combinedState = Invoke-PrivacyPlan $optIn $desktopState $adapter
Assert ((Get-PrivacyProtectionScope $combinedState) -eq 'DesktopAndCli' -and (New-PrivacyPlan $script:mock $combinedState 'refresh').steps.Count -eq 0) 'omitted scope preserves opted-in CLI protection on later refreshes'
$script:mock.protectionScope = 'Desktop'; $script:mock.paths = @($s.paths)
$desktopPlan = New-PrivacyPlan $script:mock $combinedState 'apply'
Assert ($desktopPlan.steps.Count -eq 1 -and $desktopPlan.steps[0].kind -eq 'RemoveRule' -and $desktopPlan.steps[0].rule.program -like '*\.local\bin\claude.exe') 'explicit desktop-only apply removes just the owned CLI rule while retaining desktop policy'
$desktopAgain = Invoke-PrivacyPlan $desktopPlan $combinedState $adapter
Assert ($desktopAgain.rules.Count -eq 1 -and $desktopAgain.protectionScope -eq 'Desktop') 'scope reduction preserves the existing desktop rule and persists the choice'
$rollback = New-PrivacyPlan $script:mock $desktopAgain 'rollback'
$rolled = Invoke-PrivacyPlan $rollback $desktopAgain $adapter
Assert (-not $rolled.enabled -and $rolled.rules.Count -eq 0 -and (Test-PrivacyEqual $s.policy $script:mock.policy)) 'scope-aware rollback retains preexisting Chrome policy and the disabled protection gate'
