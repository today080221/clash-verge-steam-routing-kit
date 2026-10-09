# Pure plans and isolated scheduler adapter. Never registers a real task.
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Maintenance.psm1') -Force
$module = Get-Module ClaudePrivacy.Maintenance
$xml = New-PrivacyTaskXml 'S-1-5-21-100-200-300-1001' 'C:\ProgramData\Private\runtime-reviewed' '2026-10-08T12:00:00+08:00'
[xml]$taskXml = $xml
Assert ($taskXml.Task.Principals.Principal.UserId -eq 'S-1-5-21-100-200-300-1001' -and $taskXml.Task.Principals.Principal.LogonType -eq 'InteractiveToken') 'maintenance uses exact interactive user identity, never SYSTEM'
Assert ($taskXml.Task.Principals.Principal.RunLevel -eq 'HighestAvailable' -and $taskXml.Task.Actions.Exec.Command -eq 'C:\ProgramData\Private\runtime-reviewed\ClaudePrivacy.Host.exe') 'elevated task action points to the protected GUI host, never a console executable'
Assert ($taskXml.Task.Actions.Exec.Arguments -eq '--scheduled') 'scheduled host receives only a fixed mode, never an arbitrary child command'
Assert ($taskXml.Task.Triggers.TimeTrigger.Repetition.Interval -eq 'PT2M' -and $taskXml.Task.Triggers.LogonTrigger.UserId -eq 'S-1-5-21-100-200-300-1001') 'two-minute interval and same-user logon trigger are explicit'
Assert ($taskXml.Task.Settings.MultipleInstancesPolicy -eq 'IgnoreNew' -and $taskXml.Task.Settings.ExecutionTimeLimit -eq 'PT1M') 'maintenance is bounded and ignores overlapping task instances'
$sddl = New-Object Security.AccessControl.RawSecurityDescriptor((Get-PrivacyTaskSddl 'S-1-5-21-100-200-300-1001'))
$userAce = @($sddl.DiscretionaryAcl | Where-Object { $_.SecurityIdentifier.Value -eq 'S-1-5-21-100-200-300-1001' })
Assert ($sddl.Owner.Value -eq 'S-1-5-32-544' -and $userAce.Count -eq 1 -and ($userAce[0].AccessMask -band 0x40000000) -eq 0 -and ($userAce[0].AccessMask -band 0x10000000) -eq 0) 'task ACL is administrator-owned and user gets no generic write/all permission'
$taskFixture = [pscustomobject]@{ xml = $xml; sddl = Get-PrivacyTaskSddl 'S-1-5-21-100-200-300-1001'; enabled = $true }
Assert-PrivacyTaskSecurity $taskFixture 'S-1-5-21-100-200-300-1001' 'C:\ProgramData\Private\runtime-reviewed'
$taskFixture.sddl = 'O:BAG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;S-1-5-21-100-200-300-1001)'
Throws { Assert-PrivacyTaskSecurity $taskFixture 'S-1-5-21-100-200-300-1001' 'C:\ProgramData\Private\runtime-reviewed' } 'task readback rejects writable non-administrator principal ACE'
$taskFixture.sddl = 'O:BAG:BAD:NO_ACCESS_CONTROL'
Throws { Assert-PrivacyTaskSecurity $taskFixture 'S-1-5-21-100-200-300-1001' 'C:\ProgramData\Private\runtime-reviewed' } 'task readback rejects a null DACL'
$taskFixture.sddl = Get-PrivacyTaskSddl 'S-1-5-21-100-200-300-1001'
$taskFixture.xml = $xml.Replace('HighestAvailable','LeastPrivilege')
Throws { Assert-PrivacyTaskSecurity $taskFixture 'S-1-5-21-100-200-300-1001' 'C:\ProgramData\Private\runtime-reviewed' } 'task readback rejects a changed privilege level'
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$fixtureSid = $currentIdentity.User.Value
$fixtureRoot = 'C:\ProgramData\Private\runtime-reviewed'
$registeredXml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\registered-maintenance-task.xml'))
$registeredXml = $registeredXml.Replace('{{USER_SID}}', $fixtureSid).Replace('{{USER_ACCOUNT}}', [Security.SecurityElement]::Escape($currentIdentity.Name)).Replace('{{WINDOWS_POWERSHELL}}', [Security.SecurityElement]::Escape((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))).Replace('{{RUNTIME_ROOT}}', $fixtureRoot)
# Keep the original registered legacy fixture, adapting only the reviewed action.
[xml]$registeredDocument = $registeredXml
$registeredDocument.Task.Actions.Exec.Command = [string](Join-Path $fixtureRoot 'ClaudePrivacy.Host.exe')
$registeredDocument.Task.Actions.Exec.Arguments = '--scheduled'
$registeredXml = $registeredDocument.OuterXml
$registeredTask = [pscustomobject]@{ xml = $registeredXml; enabled = $true; sddl = ('O:BAG:BAD:PAI(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200a9;;;' + $fixtureSid + ')') }
Assert-PrivacyTaskSecurity $registeredTask $fixtureSid $fixtureRoot
Assert ((Resolve-PrivacyTaskUserSid $currentIdentity.Name) -eq $fixtureSid) 'registered task XML accepts the same logon user normalized by Windows into an account name'
Assert ((Resolve-PrivacyTaskUserSid $fixtureSid) -eq $fixtureSid) 'task identity normalization preserves an explicit SID'
Throws { Resolve-PrivacyTaskUserSid '' } 'task identity normalization rejects empty any-user logon'
Throws { Resolve-PrivacyTaskUserSid ('CVSRK-unresolvable-' + [guid]::NewGuid().ToString('N')) } 'task identity normalization rejects an unresolvable account'
$otherUserTask = [pscustomobject]@{ xml = $registeredXml.Replace([Security.SecurityElement]::Escape($currentIdentity.Name), 'S-1-5-18'); enabled = $true; sddl = $registeredTask.sddl }
Throws { Assert-PrivacyTaskSecurity $otherUserTask $fixtureSid $fixtureRoot } 'registered task XML still rejects a different logon user after SID normalization'
$otherPrincipalTask = [pscustomobject]@{ xml = $registeredXml.Replace(('<UserId>' + $fixtureSid + '</UserId>'), '<UserId>S-1-5-18</UserId>'); enabled = $true; sddl = $registeredTask.sddl }
Throws { Assert-PrivacyTaskSecurity $otherPrincipalTask $fixtureSid $fixtureRoot } 'registered task XML still rejects a different execution principal'
$state = New-PrivacyState 'test-user'
$record = [pscustomobject]@{ enabled = $true; phase = 'Enabled'; ownerSid = 'test-user' }
Assert (-not (Test-PrivacyMaintenanceGate $state $record 'test-user')) 'maintenance never enables a new installation'
$state.enabled = $true; $state.phase = 'AppliedConfigurationOnly'
Assert (Test-PrivacyMaintenanceGate $state $record 'test-user') 'maintenance accepts successfully applied same-user protection'
Assert (-not (Test-PrivacyMaintenanceGate $state $record 'other-user')) 'maintenance rejects identity mismatch before mutation'
foreach ($phase in @('Pending','Failed','Conflict','RolledBack')) {
  $state.phase = $phase
  Assert (-not (Test-PrivacyMaintenanceGate $state $record 'test-user')) ('maintenance fails closed for phase ' + $phase)
}
$state.phase = 'AppliedConfigurationOnly'; $state.enabled = $false
Assert (-not (Test-PrivacyMaintenanceGate $state $record 'test-user')) 'durable rollback gate blocks stale queued refresh'
$state.enabled = $true; $record.enabled = $false
Assert (-not (Test-PrivacyMaintenanceGate $state $record 'test-user')) 'maintenance-disable gate blocks refresh while retaining rules'
Assert ((Get-PrivacyRunAge ([DateTime]::UtcNow.AddMinutes(-2))) -gt 1.9 -and (Get-PrivacyRunAge ([DateTime]::UtcNow.AddMinutes(-2))) -lt 2.1) 'maintenance timestamp handles DateTime objects without timezone roundtrip'
$manifest = Get-PrivacyRuntimeManifest $root
Assert ($manifest.files.Count -eq 5 -and @($manifest.files | Where-Object { $_.relative -match 'Owner|profiles.yaml|Script.js' }).Count -eq 0) 'runtime source manifest includes only fixed privacy files and the reviewed GUI host source'
$previewManifest = & { $WhatIfPreference = $true; Get-PrivacyRuntimeManifest $root }
Assert (Test-PrivacyEqual $manifest $previewManifest) 'runtime file hashes remain readable inside a WhatIf preview on Windows PowerShell 5.1'

$result = & $module {
  function script:Get-PrivacySid { 'S-1-5-21-100-200-300-1001' }
  function script:Test-PrivacyAdministrator { $true }
  function script:Get-PrivacyStatePath { 'C:\ProgramData\Private\state.json' }
  $script:testState = New-PrivacyState (Get-PrivacySid)
  $script:testState.enabled = $true; $script:testState.phase = 'AppliedConfigurationOnly'
  $script:testRecord = $null; $script:testWrites = 0; $script:deployments = 0
  function script:Read-PrivacyState { $script:testState }
  function script:Read-PrivacyMaintenance { if ($script:testRecord) { ConvertFrom-Json (ConvertTo-PrivacyJson $script:testRecord) } else { $null } }
  function script:Save-PrivacyProtectedJson($Path, $Value) { $script:testRecord = ConvertFrom-Json (ConvertTo-PrivacyJson $Value); $script:testWrites++ }
  function script:Assert-PrivacyRuntime($Record) { }
  function script:Get-PrivacyRuntimeManifest($SourceRoot) { [pscustomobject]@{ digest = 'aaaaaaaaaaaaaaaaaaaaaaaa'; files = @() } }
  function script:Install-PrivacyRuntime($SourceRoot, $Manifest) {
    $script:deployments++
    [pscustomobject]@{ runtimeFormat = 2; runtimeRoot = 'C:\ProgramData\Private\runtime-aaaaaaaaaaaaaaaaaaaaaaaa'; digest = $Manifest.digest; files = $Manifest.files }
  }
  $script:folder = [pscustomobject]@{ Current = $null; Registers = 0; Deletes = 0; LastSid = $null; LastLogon = $null }
  $script:folder | Add-Member ScriptMethod RegisterTask {
    param($Name,$Xml,$Flags,$Sid,$Password,$Logon,$Sddl)
    if ($Password -ne $null) { throw 'Password must never be supplied.' }
    if ($Flags -ne 22) { throw 'Registration must suppress implicit principal ACE.' }
    $this.Registers++; $this.LastSid = $Sid; $this.LastLogon = $Logon
    $this.Current = [pscustomobject]@{ xml = $Xml; sddl = $Sddl; enabled = $true }
    $this.Current
  }
  $script:folder | Add-Member ScriptMethod GetTask { param($Name) $this.Current }
  $script:folder | Add-Member ScriptMethod DeleteTask { param($Name,$Flags) $this.Deletes++; $this.Current = $null }
  function script:Get-PrivacyTaskFolder { $script:folder }
  function script:Get-PrivacyTask { $script:folder.Current }
  Enable-PrivacyMaintenance 'fixture' | Out-Null
  $firstRecord = Read-PrivacyMaintenance
  Enable-PrivacyMaintenance 'fixture' | Out-Null
  $idempotent = $script:folder.Registers -eq 1 -and $script:deployments -eq 1
  $correctPrincipal = $script:folder.LastSid -eq (Get-PrivacySid) -and $script:folder.LastLogon -eq 3
  $script:testRecord.phase = 'Pending'; $script:testRecord.enabled = $false
  Enable-PrivacyMaintenance 'fixture' | Out-Null
  $pendingRecovered = $script:testRecord.enabled -and $script:testRecord.phase -eq 'Enabled' -and $script:folder.Registers -eq 2
  Disable-PrivacyMaintenance | Out-Null
  $disabled = -not $script:testRecord.enabled -and $null -eq $script:folder.Current -and $script:folder.Deletes -eq 1
  Disable-PrivacyMaintenance | Out-Null
  $disableIdempotent = $script:folder.Deletes -eq 1
  Enable-PrivacyMaintenance 'fixture' | Out-Null
  $script:folder.Current.xml += '<!-- user edit -->'
  $rejected = $false
  try { Disable-PrivacyMaintenance | Out-Null } catch { $rejected = $true }
  $editedPreserved = $rejected -and -not $script:testRecord.enabled -and $null -ne $script:folder.Current
  $script:testRecord = $null; $writes = $script:testWrites
  $rejected = $false
  try { Enable-PrivacyMaintenance 'fixture' | Out-Null } catch { $rejected = $true }
  $collision = $rejected -and $writes -eq $script:testWrites
  $script:folder.Current = $null; $script:testState.enabled = $false
  $rejected = $false
  try { Enable-PrivacyMaintenance 'fixture' | Out-Null } catch { $rejected = $true }
  [pscustomobject]@{ idempotent = $idempotent; correctPrincipal = $correctPrincipal; pendingRecovered = $pendingRecovered; disabled = $disabled; disableIdempotent = $disableIdempotent; editedPreserved = $editedPreserved; collision = $collision; disabledCannotRegister = $rejected }
}
Assert $result.idempotent 'maintenance enable with unchanged code is idempotent'
Assert $result.correctPrincipal 'scheduler registration receives same-user interactive logon and no password'
Assert $result.pendingRecovered 'owned Pending task with matching fingerprint recovers through normal registration and security readback'
Assert $result.disabled 'maintenance disable persists gate and deletes owned task'
Assert $result.disableIdempotent 'maintenance disable is idempotent'
Assert $result.editedPreserved 'edited task is preserved but disabled journal prevents owned runner mutation'
Assert $result.collision 'unowned task collision causes no registration or journal mutation'
Assert $result.disabledCannotRegister 'maintenance cannot be registered before explicit protection apply'
Remove-Module ClaudePrivacy.Maintenance,ClaudePrivacy.Windows -ErrorAction SilentlyContinue
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force
