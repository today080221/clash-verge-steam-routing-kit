[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('Desktop','DesktopAndCli')][string]$ProtectionScope,
  [switch]$MaintenanceOnly,
  [switch]$Elevated,
  [string]$ExpectedSid,
  [string]$ExpectedSourceDigest
)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$sourceFiles = @('enable-claude-privacy.ps1','scripts/ClaudePrivacy.Enablement.psm1','claude-privacy.ps1','scripts/ClaudePrivacy.Core.psm1','scripts/ClaudePrivacy.Windows.psm1','scripts/ClaudePrivacy.Maintenance.psm1','scripts/ClaudePrivacy.Host.cs')
$sourceHashes = @($sourceFiles | ForEach-Object {
  $stream = [IO.File]::OpenRead((Join-Path $PSScriptRoot $_))
  $fileSha = [Security.Cryptography.SHA256]::Create()
  try { $_ + ':' + ([BitConverter]::ToString($fileSha.ComputeHash($stream))).Replace('-', '') }
  finally { $fileSha.Dispose(); $stream.Dispose() }
})
$sha = [Security.Cryptography.SHA256]::Create()
try { $digest = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($sourceHashes -join '|'))))).Replace('-', '') }
finally { $sha.Dispose() }
if ($Elevated -and ($sid -ne $ExpectedSid -or $digest -cne $ExpectedSourceDigest -or -not $isAdmin)) { throw 'Elevation identity/source verification failed. No configuration changes were attempted.' }
Import-Module (Join-Path $PSScriptRoot 'scripts\ClaudePrivacy.Maintenance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'scripts\ClaudePrivacy.Enablement.psm1') -Force
if ($WhatIfPreference) {
  $state = Read-PrivacyState
  $scope = Get-PrivacyProtectionScope $state $ProtectionScope
  $snapshot = Get-PrivacySnapshot -ProtectionScope $scope
  if ($snapshot.firewallReadError) { throw $snapshot.firewallReadError }
  $plan = New-PrivacyPlan $snapshot $state 'apply'
  if ($MaintenanceOnly -and (-not $state.enabled -or $state.phase -ne 'AppliedConfigurationOnly' -or $scope -ne (Get-PrivacyProtectionScope $state) -or $plan.steps.Count -or $plan.conflicts.Count)) { throw 'Maintenance-only upgrade requires unchanged, already enabled protection.' }
  [pscustomobject]@{
    status = 'PreviewOnly'; needsUac = -not $isAdmin; sourceDigest = $digest; protectionScope = $scope; maintenanceOnly = [bool]$MaintenanceOnly
    protection = $plan
    maintenance = Get-PrivacyMaintenancePlan $PSScriptRoot
    acceptanceSequence = $(if ($MaintenanceOnly) { @('verify unchanged protection','upgrade maintenance','run real task','verify protection retained') } else { @('apply','enable maintenance','run real task','rollback','replay disabled runner','apply','enable maintenance','run real task') })
    receipt = Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) 'enablement-result.json'
  } | ConvertTo-Json -Depth 40
  exit 0
}
if (-not $isAdmin) {
  if (-not $PSCmdlet.ShouldProcess('Windows PowerShell (Microsoft Windows)', 'Request one same-user UAC elevation for reviewed setup and acceptance')) { exit 0 }
  $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Elevated -ExpectedSid "' + $sid + '" -ExpectedSourceDigest "' + $digest + '"'
  if ($ProtectionScope) { $args += ' -ProtectionScope ' + $ProtectionScope }
  if ($MaintenanceOnly) { $args += ' -MaintenanceOnly' }
  # The coordinator triggers this entry once and explains the UAC click to the user.
  $process = Start-Process -FilePath $exe -ArgumentList $args -Verb RunAs -WindowStyle Hidden -PassThru
  [pscustomobject]@{ status = 'ElevatedSetupStarted'; processId = $process.Id; receipt = Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) 'enablement-result.json' } | ConvertTo-Json
  exit 0
}
$setupAction = if ($MaintenanceOnly) { 'Upgrade maintenance only; retain existing protection throughout' } else { 'Enable, validate rollback coordination, then leave protection enabled' }
if (-not $PSCmdlet.ShouldProcess('Claude program UDP rules, protected runtime and owned maintenance task', $setupAction)) { exit 0 }
$receiptPath = Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) 'enablement-result.json'
$setupMutex = New-Object Threading.Mutex($false, ('Local\CVSRK-ClaudePrivacy-Setup-' + $sid))
$acquired = $false
try {
  try { $acquired = $setupMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { throw 'Another setup is running.' }
  Save-PrivacyProtectedJson $receiptPath ([pscustomobject]@{ status = 'Running'; success = $false; startedUtc = [DateTime]::UtcNow.ToString('o'); sourceDigest = $digest; maintenanceOnly = [bool]$MaintenanceOnly })
  $runtimeManifest = Get-PrivacyRuntimeManifest $PSScriptRoot
  foreach ($file in $runtimeManifest.files) {
    if (($file.relative + ':' + $file.sha256) -cnotin $sourceHashes) { throw 'Runtime sources changed after the elevation source check.' }
  }
  $runtime = Install-PrivacyRuntime $PSScriptRoot $runtimeManifest
  $script:runtimeEntry = Join-Path $runtime.runtimeRoot 'claude-privacy.ps1'
  $script:setupInitialState = Read-PrivacyState
  $script:setupScope = Get-PrivacyProtectionScope $script:setupInitialState $ProtectionScope
  function Get-SetupSnapshot { Get-PrivacySnapshot -ProtectionScope $script:setupScope }
  $script:setupBefore = Get-SetupSnapshot
  $script:rollbackPolicy = if ($script:setupInitialState.policy) { $script:setupInitialState.policy.original } else { $script:setupBefore.policy }
  $initialPlan = New-PrivacyPlan $script:setupBefore $script:setupInitialState 'apply'
  if ($MaintenanceOnly -and (-not $script:setupInitialState.enabled -or $script:setupInitialState.phase -ne 'AppliedConfigurationOnly' -or $script:setupScope -ne (Get-PrivacyProtectionScope $script:setupInitialState) -or $initialPlan.steps.Count -or $initialPlan.conflicts.Count)) { throw 'Maintenance-only upgrade requires unchanged, already enabled protection.' }
  $script:appliedPolicy = if ($initialPlan.nextState.policy) { $initialPlan.nextState.policy.applied } else { $script:setupBefore.policy }
  function Invoke-SetupCommand([string]$Action, [switch]$Preview, [switch]$Scheduled, [int]$ExpectedExit = 0) {
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$script:runtimeEntry,'-Action',$Action)
    if ($Action -eq 'apply') { $arguments += @('-ProtectionScope',$script:setupScope) }
    if ($Preview) { $arguments += '-WhatIf' }
    if ($Scheduled) { $arguments += '-Scheduled' }
    $child = Invoke-PrivacyHiddenProcess (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') $arguments (Split-Path -Parent $script:runtimeEntry)
    if ($child.exitCode -ne $ExpectedExit) { throw ('Setup step failed: ' + $Action + '; exit=' + $child.exitCode + '; ' + $child.output + $child.error) }
  }
  function Assert-SetupProtection {
    $state = Read-PrivacyState
    $snapshot = Get-SetupSnapshot
    Assert-PrivacyEnablementProtection $snapshot $state $script:appliedPolicy
    Assert-PrivacyStateDirectory (Get-PrivacyStatePath)
  }
  function Assert-SetupMaintenance {
    $maintenance = Read-PrivacyMaintenance
    if (-not $maintenance -or -not $maintenance.enabled) { throw 'Maintenance gate not enabled.' }
    Assert-PrivacyRuntime $maintenance
    $task = Get-PrivacyTask
    if (-not $task -or (Get-PrivacyTaskFingerprint $task) -cne $maintenance.taskFingerprint) { throw 'Scheduled task ownership/ACL readback mismatch.' }
  }
  function Invoke-SetupTask {
    $started = [DateTimeOffset]::UtcNow
    $folder = Get-PrivacyTaskFolder
    $folder.GetTask((Get-PrivacyTaskName)).Run($null) | Out-Null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
      Start-Sleep -Milliseconds 1000
      $status = Get-PrivacyMaintenanceStatus
      if ($status.lastRun -and [DateTimeOffset]::Parse([string]$status.lastRun.timeUtc) -ge $started -and $status.task.state -ne 4) {
        if ($status.lastRun.result -ne 'Refreshed' -or $status.lastRun.exitCode -ne 0 -or $status.task.lastResult -ne 0) { throw 'Real maintenance task did not finish successfully.' }
        return
      }
    } while ($watch.Elapsed.TotalSeconds -lt 45)
    throw 'Timed out waiting for a verified real maintenance task run.'
  }
  function Assert-SetupRollback {
    $state = Read-PrivacyState
    $snapshot = Get-SetupSnapshot
    if ($state.enabled -or $state.phase -ne 'RolledBack' -or $state.rules.Count -ne 0 -or (Get-PrivacyTask)) { throw 'Rollback left protection gate or task active.' }
    if (@($snapshot.rules | Where-Object { $_.name -in $script:ownedNames }).Count -gt 0) { throw 'Rollback left an owned firewall rule.' }
    if (-not (Test-PrivacyEqual $snapshot.policy $script:rollbackPolicy)) { throw 'Rollback changed externally owned Chrome policy.' }
  }
  $adapter = @{
    RequireUnchangedProtection = {
      $state = Read-PrivacyState
      $snapshot = Get-SetupSnapshot
      Assert-PrivacyEnablementProtection $snapshot $state $script:appliedPolicy
      if (-not (Test-PrivacyEqual $state $script:setupInitialState)) { throw 'Protection ownership state changed during maintenance-only upgrade.' }
      if (-not (Test-PrivacyEqual $snapshot.policy $script:setupBefore.policy) -or -not (Test-PrivacyEqual $snapshot.rules $script:setupBefore.rules)) { throw 'Protection rules/policy changed during maintenance-only upgrade.' }
    }
    Preview = {
      $before = Get-SetupSnapshot; $state = Read-PrivacyState; $maintenance = Read-PrivacyMaintenance
      Invoke-SetupCommand 'apply' -Preview
      Invoke-SetupCommand 'maintenance-enable' -Preview
      $after = Get-SetupSnapshot
      if (-not (Test-PrivacyEqual $before.policy $after.policy) -or -not (Test-PrivacyEqual $before.rules $after.rules) -or -not (Test-PrivacyEqual $state (Read-PrivacyState)) -or -not (Test-PrivacyEqual $maintenance (Read-PrivacyMaintenance))) { throw 'Preview made unexpected changes.' }
    }
    Apply = { Invoke-SetupCommand 'apply' }
    VerifyProtection = { Assert-SetupProtection; $script:ownedNames = @((Read-PrivacyState).rules.name) }
    EnableMaintenance = { Invoke-SetupCommand 'maintenance-enable' }
    VerifyMaintenance = { Assert-SetupMaintenance }
    RunMaintenance = { Invoke-SetupTask }
    Rollback = { Invoke-SetupCommand 'rollback' }
    VerifyRollback = { Assert-SetupRollback }
    ReplayDisabledRunner = { Invoke-SetupCommand 'refresh' -Scheduled; Invoke-SetupCommand 'refresh' -ExpectedExit 1 }
    ObserveActualProcess = {
      $verifiedProcesses = @(Get-Process -Name Claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -and (Test-PrivacyExecutable $_.Path) })
      $endpoints = @()
      foreach ($p in $verifiedProcesses) { $endpoints += @(Get-NetUDPEndpoint -OwningProcess $p.Id -ErrorAction SilentlyContinue) }
      $events = @(); $eventAvailability = 'Read'
      try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = @(5152,5157); StartTime = (Get-Date).AddMinutes(-15) } -MaxEvents 300 -ErrorAction Stop | Where-Object {
          [xml]$eventXml = $_.ToXml()
          $data = @{}; foreach ($d in $eventXml.Event.EventData.Data) { $data[$d.Name] = [string]$d.'#text' }
          $data['Protocol'] -eq '17' -and $data['Application'] -match '(?i)\\WindowsApps\\Claude_[^\\]+\\app\\Claude.exe$'
        })
      } catch { $eventAvailability = 'UnavailableOrNoMatchingAuditEvents' }
      [pscustomobject]@{ protectionScope = $script:setupScope; verifiedClaudeProcessCount = $verifiedProcesses.Count; currentUdpEndpointCount = $endpoints.Count; matchingUdpBlockEventCount = $events.Count; eventAvailability = $eventAvailability; eventObservationScope = 'Desktop WindowsApps event paths only; not a native CLI enforcement test.'; actualClaudeUdpEnforcement = 'Not proven by this setup; no synthetic or renamed executable probe was used.' }
    }
  }
  $result = if ($MaintenanceOnly) { Invoke-PrivacyMaintenanceUpgradeSequence $adapter } else { Invoke-PrivacyEnablementSequence $adapter }
  $finalSnapshot = Get-SetupSnapshot
  $receipt = [pscustomobject]@{
    status = $(if ($result.success) { 'Completed' } else { 'Failed' }); success = $result.success; completedUtc = [DateTime]::UtcNow.ToString('o'); sourceDigest = $digest
    protectionScope = $script:setupScope; maintenanceOnly = [bool]$MaintenanceOnly; result = $result; finalState = Read-PrivacyState; maintenance = Get-PrivacyMaintenanceStatus
    chromePolicyUnchanged = Test-PrivacyEqual $script:setupBefore.policy $finalSnapshot.policy
    persistentRules = $finalSnapshot.rules; activeRules = $finalSnapshot.activeRules; firewallProfiles = $finalSnapshot.firewallProfiles
  }
  Save-PrivacyProtectedJson $receiptPath $receipt
  if (-not $result.success) { exit 1 }
} catch {
  $setupFailure = $_
  try { Save-PrivacyProtectedJson $receiptPath ([pscustomobject]@{ status = 'Failed'; success = $false; timeUtc = [DateTime]::UtcNow.ToString('o'); error = $setupFailure.Exception.Message; sourceDigest = $digest }) }
  catch { Write-Error ('Failed to persist the failure receipt; existing receipt and staged evidence were preserved. ' + $_.Exception.Message) -ErrorAction Continue }
  throw $setupFailure
} finally {
  if ($acquired) { $setupMutex.ReleaseMutex() }
  $setupMutex.Dispose()
}
