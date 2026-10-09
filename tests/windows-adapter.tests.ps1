# Sourced by run-tests.ps1. Replace cmdlets INSIDE the module; no real mutations.
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Windows.psm1') -Force
$windowsModule = Get-Module ClaudePrivacy.Windows
$adapterResults = & $windowsModule {
  $script:fixtureCalls = @()
  $script:fixtureVerified = $true
  function script:Test-PrivacyExecutable([string]$Path) { $script:fixtureVerified }
  function script:New-NetFirewallRule {
    param($PolicyStore, $Name, $DisplayName, $Group, $Description, $Program, $Direction, $Action, $Enabled, $Profile, $Protocol)
    $script:fixtureCalls += [pscustomobject]$PSBoundParameters
  }
  function script:Remove-NetFirewallRule { param($PolicyStore, $Name, $ErrorAction) $script:fixtureCalls += [pscustomobject]$PSBoundParameters }
  $rule = New-PrivacyRule 'C:\Verified\Claude.exe' 'test-user'
  Add-PrivacyRule $rule
  $add = $script:fixtureCalls[0]
  $script:fixtureVerified = $false
  $rejected = $false
  try { Add-PrivacyRule $rule } catch { $rejected = $true }
  Remove-PrivacyRule $rule.name
  [pscustomobject]@{ add = $add; refusedUnverified = $rejected; callCount = $script:fixtureCalls.Count; remove = $script:fixtureCalls[1] }
}
Assert ($adapterResults.add.Program -eq 'C:\Verified\Claude.exe' -and $adapterResults.add.Direction -eq 'Outbound' -and $adapterResults.add.Protocol -eq 'UDP' -and $adapterResults.add.Action -eq 'Block') 'Windows adapter forwards exact program/UDP/outbound/block to firewall cmdlet'
Assert ($adapterResults.add.Profile -eq 'Any' -and $adapterResults.add.PolicyStore -eq 'PersistentStore' -and -not $adapterResults.add.PSObject.Properties['Package']) 'Windows adapter uses all profiles and never package identity or global program scope'
Assert ($adapterResults.refusedUnverified -and $adapterResults.callCount -eq 2) 'executable is revalidated at write time before any firewall call'
Assert ($adapterResults.remove.Name -eq $adapterResults.add.Name -and $adapterResults.remove.PolicyStore -eq 'PersistentStore') 'Windows removal is exact-name scoped, never group-wide deletion'
Remove-Module ClaudePrivacy.Windows
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force
