Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ClaudePrivacy.Core.psm1')

function Assert-PrivacyEnablementProtection($Snapshot, $State, $ExpectedPolicy) {
  if ($Snapshot.firewallReadError) { throw $Snapshot.firewallReadError }
  if ($Snapshot.discoveryErrors.Count -gt 0 -or $Snapshot.paths.Count -eq 0) { throw 'Executable discovery is incomplete during acceptance.' }
  if (-not $State.enabled -or $State.phase -ne 'AppliedConfigurationOnly' -or $State.rules.Count -eq 0) { throw 'Protection state is not enabled/applied.' }
  if ((Get-PrivacyProtectionScope $Snapshot) -ne (Get-PrivacyProtectionScope $State)) { throw 'Applied protection scope differs from the reviewed scope.' }
  if ((@($Snapshot.paths | Sort-Object -Unique) -join '|') -ine (@($State.rules.program | Sort-Object -Unique) -join '|')) { throw 'Applied rules do not cover every verified executable in the selected scope.' }
  foreach ($rule in $State.rules) {
    $local = @($Snapshot.rules | Where-Object { $_.name -eq $rule.name })
    $active = @($Snapshot.activeRules | Where-Object { $_.name -eq $rule.name })
    if ($local.Count -ne 1 -or $active.Count -ne 1 -or -not (Test-PrivacyRuleSpec $local[0] $rule) -or -not (Test-PrivacyRuleSpec $active[0] $rule) -or $local[0].fingerprint -cne $rule.fingerprint) { throw 'Persistent/effective firewall readback mismatch.' }
  }
  if (-not (Test-PrivacyEqual $Snapshot.policy $ExpectedPolicy)) { throw 'Chrome policy differs from the reviewed apply plan.' }
}

function Invoke-PrivacyEnablementSequence([hashtable]$Adapter) {
  $checks = New-Object 'Collections.Generic.List[string]'
  $rollbackStarted = $false
  try {
    & $Adapter.Preview
    $checks.Add('Read-only previews completed without changes')
    & $Adapter.Apply
    & $Adapter.VerifyProtection
    $checks.Add('Exact program protection and active rule readback verified')
    & $Adapter.EnableMaintenance
    & $Adapter.VerifyMaintenance
    & $Adapter.RunMaintenance
    $checks.Add('Protected same-user task executed successfully')
    $rollbackStarted = $true
    & $Adapter.Rollback
    & $Adapter.VerifyRollback
    & $Adapter.ReplayDisabledRunner
    & $Adapter.VerifyRollback
    $checks.Add('Rollback removed owned task/rules and queued refresh could not re-enable them')
    & $Adapter.Apply
    & $Adapter.VerifyProtection
    & $Adapter.EnableMaintenance
    & $Adapter.VerifyMaintenance
    & $Adapter.RunMaintenance
    $checks.Add('Final protection and maintenance re-enabled and verified')
    $observations = & $Adapter.ObserveActualProcess
    [pscustomobject]@{ success = $true; checks = @($checks); observations = $observations; error = $null; recoveryError = $null }
  } catch {
    $failure = $_.Exception.Message; $recoveryError = $null
    # The requested final state is enabled. Only use ordinary ownership-aware paths.
    if ($rollbackStarted) {
      try { & $Adapter.Apply; & $Adapter.VerifyProtection; & $Adapter.EnableMaintenance; & $Adapter.VerifyMaintenance }
      catch { $recoveryError = $_.Exception.Message }
    }
    [pscustomobject]@{ success = $false; checks = @($checks); observations = $null; error = $failure; recoveryError = $recoveryError }
  }
}
function Invoke-PrivacyMaintenanceUpgradeSequence([hashtable]$Adapter) {
  $checks = New-Object 'Collections.Generic.List[string]'
  try {
    & $Adapter.RequireUnchangedProtection
    & $Adapter.Preview
    $checks.Add('Existing enabled protection and read-only previews verified')
    & $Adapter.EnableMaintenance
    & $Adapter.VerifyMaintenance
    & $Adapter.RunMaintenance
    $checks.Add('Updated protected maintenance task executed successfully')
    & $Adapter.RequireUnchangedProtection
    $checks.Add('Protection scope, ownership state, rules and Chrome policy retained unchanged')
    $observations = & $Adapter.ObserveActualProcess
    [pscustomobject]@{ success = $true; checks = @($checks); observations = $observations; error = $null; recoveryError = $null }
  } catch {
    # This mode never applies, disables or rolls back protection to upgrade a task.
    [pscustomobject]@{ success = $false; checks = @($checks); observations = $null; error = $_.Exception.Message; recoveryError = $null }
  }
}
Export-ModuleMember -Function Invoke-PrivacyEnablementSequence,Invoke-PrivacyMaintenanceUpgradeSequence,Assert-PrivacyEnablementProtection
