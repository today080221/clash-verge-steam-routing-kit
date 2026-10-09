[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('audit','status','apply','refresh','rollback','maintenance-enable','maintenance-disable')][string]$Action = 'status',
  [string[]]$ClaudePath = @(),
  [ValidateSet('Desktop','DesktopAndCli')][string]$ProtectionScope,
  [switch]$Scheduled
)
$ErrorActionPreference = 'Stop'
$runWatch = [Diagnostics.Stopwatch]::StartNew()
$oldModulePath = $env:PSModulePath
# Elevated scheduled execution must not autoload modules from user-writable folders.
$env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules')
Import-Module (Join-Path $PSScriptRoot 'scripts\ClaudePrivacy.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts\ClaudePrivacy.Windows.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts\ClaudePrivacy.Maintenance.psm1') -Force
$mutex = $null; $locked = $false; $scheduledValidated = $false
try {
  if ($Scheduled -and $Action -ne 'refresh') { throw 'Scheduled mode can only refresh existing enabled protection.' }
  $mutex = New-Object Threading.Mutex($false, ('Local\CVSRK-ClaudePrivacy-' + (Get-PrivacySid)))
  try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
  if (-not $locked) {
    if ($Scheduled) { exit 0 }
    throw 'Another privacy operation is running.'
  }
  $state = Read-PrivacyState
  if ($ProtectionScope -and $Action -notin @('apply','status','audit')) { throw 'Specify protection scope only for apply or read-only status/audit.' }
  $effectiveScope = Get-PrivacyProtectionScope $state $ProtectionScope
  if ($Scheduled) {
    $record = Read-PrivacyMaintenance
    if (-not $record -or $record.runtimeRoot -ine $PSScriptRoot) { throw 'Scheduled execution requires the recorded protected deployment.' }
    Assert-PrivacyRuntime $record
    if (-not (Test-PrivacyAdministrator)) { throw 'Scheduled task lacks the same-user elevated token.' }
    $scheduledValidated = $true
    if (-not (Test-PrivacyMaintenanceGate $state $record (Get-PrivacySid))) {
      if ($record.enabled -and $state.PSObject.Properties['enabled'] -and $state.enabled) {
        Save-PrivacyMaintenanceRun 'NeedsReview' 2 'Protection is not in a successfully applied state. Automatic changes stopped; inspect state.lastError.'
        exit 2
      }
      Save-PrivacyMaintenanceRun 'SkippedDisabled' 0 'Protection or maintenance is disabled. No changes made.'
      exit 0
    }
    $task = Get-PrivacyTask
    if (-not $task -or (Get-PrivacyTaskFingerprint $task) -cne $record.taskFingerprint) { throw 'Scheduled task ownership verification failed.' }
  }
  if ($Action -eq 'maintenance-enable') {
    Get-PrivacyMaintenancePlan $PSScriptRoot | ConvertTo-Json -Depth 10
    if ($PSCmdlet.ShouldProcess('Protected runtime and same-user two-minute/logon scheduled task', 'Enable/update explicitly requested maintenance')) {
      Enable-PrivacyMaintenance $PSScriptRoot | ConvertTo-Json -Depth 10
    }
    exit 0
  }
  if ($Action -eq 'maintenance-disable') {
    if ($PSCmdlet.ShouldProcess((Get-PrivacyTaskName), 'Persist disabled gate and remove only owned task; retain protection')) {
      Disable-PrivacyMaintenance | ConvertTo-Json -Depth 10
    }
    exit 0
  }
  if ($Action -eq 'rollback' -and -not $WhatIfPreference) {
    if (-not (Test-PrivacyAdministrator)) { throw 'Rollback requires same-user elevation.' }
    if (-not $PSCmdlet.ShouldProcess('Maintenance gate, owned task, Chrome additions and exact Claude UDP rules', 'Rollback')) { exit 0 }
    if (-not $state.PSObject.Properties['enabled']) { $state | Add-Member NoteProperty enabled $false }
    $state.enabled = $false
    Save-PrivacyState $state
    Disable-PrivacyMaintenance | Out-Null
  }
  $snapshot = Get-PrivacySnapshot $ClaudePath $effectiveScope
  if ($Action -in @('audit','status')) {
    $plan = $null; $planningError = $null; $maintenance = $null
    try {
      if ($snapshot.firewallReadError) { throw $snapshot.firewallReadError }
      $plan = New-PrivacyPlan $snapshot $state 'apply'
    } catch { $planningError = $_.Exception.Message }
    try { $maintenance = Get-PrivacyMaintenanceStatus } catch { $maintenance = [pscustomobject]@{ health = 'InspectionFailed'; error = $_.Exception.Message } }
    [pscustomobject]@{ action = $Action; snapshot = $snapshot; state = $state; proposedApply = $plan; planningError = $planningError; maintenance = $maintenance } | ConvertTo-Json -Depth 40
    if ($planningError -or ($plan -and $plan.conflicts.Count) -or $maintenance.health -in @('Failed','Stale','TaskMissing','TaskChanged','InspectionFailed','NeedsReview','UnexpectedTask','RuntimeChanged')) { exit 2 }
    exit 0
  }
  if ($snapshot.firewallReadError) { throw ('Cannot inspect firewall: ' + $snapshot.firewallReadError) }
  $plan = New-PrivacyPlan $snapshot $state $Action
  if (-not $Scheduled) { $plan | ConvertTo-Json -Depth 40 }
  if ($plan.conflicts.Count -gt 0 -and $Action -ne 'rollback') { throw ($plan.conflicts -join '; ') }
  $execute = if ($Action -eq 'rollback' -and -not $WhatIfPreference) { $true } else { $PSCmdlet.ShouldProcess('HKCU Chrome URL policy and exact verified Claude.exe UDP rules', $Action) }
  if ($execute) {
    if (-not $snapshot.administrator) { throw 'Run an elevated PowerShell as the SAME Windows user. No settings were changed.' }
    if ($Action -ne 'rollback' -and ($snapshot.firewallProfiles.Count -eq 0 -or @($snapshot.firewallProfiles | Where-Object { [string]$_.Enabled -ne 'True' -or [string]$_.AllowLocalFirewallRules -eq 'False' }).Count)) {
      throw 'Firewall disabled or local rules disallowed by policy. No settings were changed.'
    }
    $result = Invoke-PrivacyPlan $plan $state (Get-PrivacyAdapter)
    if (-not $Scheduled) { $result | ConvertTo-Json -Depth 40 }
    else {
      $metrics = [pscustomobject]@{ workerPid = $PID; wallMs = $runWatch.ElapsedMilliseconds; workerCpuMs = [math]::Round([Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds, 1); operations = $plan.steps.Count; snapshot = $snapshot.timings }
      Save-PrivacyMaintenanceRun 'Refreshed' 0 ('Reconciled enabled protection; operations: ' + $plan.steps.Count + '. Runtime UDP enforcement still requires actual process evidence.') $metrics
    }
  }
  if ($plan.conflicts.Count) { exit 2 }
} catch {
  if ($Scheduled -and $scheduledValidated) {
    try { Save-PrivacyMaintenanceRun 'Failed' 1 $_.Exception.Message } catch { }
  }
  [pscustomobject]@{ action = $Action; status = 'Failed'; message = $_.Exception.Message; runtimeAcceptance = 'Not verified' } | ConvertTo-Json
  exit 1
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  if ($mutex) { $mutex.Dispose() }
  $env:PSModulePath = $oldModulePath
}
