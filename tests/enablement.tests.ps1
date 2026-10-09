Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Enablement.psm1') -Force
$cleanSnapshot = [pscustomobject]@{ sid = 'test-user'; policy = [pscustomobject]@{ present = $false; kind = $null; raw = $null }; paths = @('C:\Verified\Claude.exe'); discoveryErrors = @(); rules = @(); activeRules = @(); firewallReadError = $null }
$cleanPlan = New-PrivacyPlan $cleanSnapshot (New-PrivacyState 'test-user') 'apply'
$appliedState = $cleanPlan.nextState
$appliedState.rules[0].fingerprint = 'fixture-rule-fingerprint'
$readback = ConvertFrom-Json (ConvertTo-PrivacyJson $cleanSnapshot)
$readback.rules = $appliedState.rules; $readback.activeRules = $appliedState.rules; $readback.policy = $appliedState.policy.applied
Assert-PrivacyEnablementProtection $readback $appliedState $cleanPlan.nextState.policy.applied
Assert ($readback.policy.present -and -not $cleanSnapshot.policy.present) 'setup acceptance permits legitimate first-install Chrome policy additions from reviewed plan'
Throws { Assert-PrivacyEnablementProtection $readback $appliedState $cleanSnapshot.policy } 'setup acceptance rejects an incorrect original-policy baseline after first install'
$existingPlan = New-PrivacyPlan $readback (New-PrivacyState 'test-user') 'apply'
Assert ($existingPlan.nextState.policy -eq $null) 'identical preexisting Chrome policy is not claimed by setup'
$readback.activeRules = @()
Throws { Assert-PrivacyEnablementProtection $readback $appliedState $cleanPlan.nextState.policy.applied } 'setup acceptance rejects rules missing from effective policy'
function New-SetupFixture([string]$FailStep = '') {
  $trace = New-Object 'Collections.Generic.List[string]'
  $state = @{ fail = $FailStep; failedOnce = $false; enabled = $false }
  $adapter = @{}
  foreach ($step in @('Preview','Apply','VerifyProtection','EnableMaintenance','VerifyMaintenance','RunMaintenance','Rollback','VerifyRollback','ReplayDisabledRunner','ObserveActualProcess')) {
    $name = $step
    $adapter[$name] = {
      $trace.Add($name)
      if ($name -eq $state.fail -and -not $state.failedOnce) { $state.failedOnce = $true; throw 'Simulated setup failure' }
      if ($name -eq 'Apply') { $state.enabled = $true }
      if ($name -eq 'Rollback') { $state.enabled = $false }
      if ($name -eq 'VerifyRollback' -and $state.enabled) { throw 'Fixture protection unexpectedly enabled' }
      if ($name -eq 'ReplayDisabledRunner' -and $state.enabled) { throw 'Replay must run with gate closed' }
      if ($name -eq 'ObserveActualProcess') { return [pscustomobject]@{ actualClaudeUdpEnforcement = 'Not proven' } }
    }.GetNewClosure()
  }
  [pscustomobject]@{ adapter = $adapter; trace = $trace; state = $state }
}
$fixture = New-SetupFixture
$result = Invoke-PrivacyEnablementSequence $fixture.adapter
Assert ($result.success -and $fixture.state.enabled) 'one-time setup completes acceptance with protection enabled'
Assert ($fixture.trace.IndexOf('Preview') -lt $fixture.trace.IndexOf('Apply') -and $fixture.trace.IndexOf('Rollback') -lt $fixture.trace.IndexOf('ReplayDisabledRunner')) 'setup previews first and tests queued-run safety after rollback'
Assert (@($fixture.trace | Where-Object { $_ -eq 'RunMaintenance' }).Count -eq 2) 'setup verifies real task both before and after rollback cycle'
Assert ($result.observations.actualClaudeUdpEnforcement -eq 'Not proven') 'setup preserves unproven actual-process UDP result'
$fixture = New-SetupFixture 'ReplayDisabledRunner'
$result = Invoke-PrivacyEnablementSequence $fixture.adapter
Assert (-not $result.success -and $fixture.state.enabled -and $null -eq $result.recoveryError) 'setup failure after rollback attempts ownership-aware restoration, never claims success'
$fixture = New-SetupFixture 'Apply'
$result = Invoke-PrivacyEnablementSequence $fixture.adapter
Assert (-not $result.success -and $fixture.trace.Count -eq 2 -and -not $fixture.state.enabled) 'initial apply failure stops before task registration or rollback'
$fixture = New-SetupFixture
$fixture.state.enabled = $true
$fixture.adapter.RequireUnchangedProtection = { if (-not $fixture.state.enabled) { throw 'Existing protection must remain enabled.' }; $fixture.trace.Add('RequireUnchangedProtection') }
$result = Invoke-PrivacyMaintenanceUpgradeSequence $fixture.adapter
Assert ($result.success -and $fixture.state.enabled -and @($fixture.trace | Where-Object { $_ -in @('Apply','Rollback','VerifyRollback','ReplayDisabledRunner') }).Count -eq 0) 'maintenance-only upgrade never applies, disables or rolls back existing protection'
Assert (@($fixture.trace | Where-Object { $_ -eq 'RequireUnchangedProtection' }).Count -eq 2 -and @($fixture.trace | Where-Object { $_ -eq 'RunMaintenance' }).Count -eq 1) 'maintenance-only upgrade verifies protection before and after one real task execution'
$fixture = New-SetupFixture 'RunMaintenance'
$fixture.state.enabled = $true
$fixture.adapter.RequireUnchangedProtection = { $fixture.trace.Add('RequireUnchangedProtection') }
$result = Invoke-PrivacyMaintenanceUpgradeSequence $fixture.adapter
Assert (-not $result.success -and $fixture.state.enabled -and @($fixture.trace | Where-Object { $_ -in @('Apply','Rollback') }).Count -eq 0) 'maintenance task failure is reported without disabling protection or pretending recovery succeeded'
Remove-Module ClaudePrivacy.Enablement
