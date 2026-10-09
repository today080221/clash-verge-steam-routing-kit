Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ClaudePrivacy.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'ClaudePrivacy.Windows.psm1')
$script:LegacyRuntimeFiles = @('claude-privacy.ps1','scripts/ClaudePrivacy.Core.psm1','scripts/ClaudePrivacy.Windows.psm1','scripts/ClaudePrivacy.Maintenance.psm1')
$script:RuntimeFiles = @($script:LegacyRuntimeFiles) + @('scripts/ClaudePrivacy.Host.cs')
$script:HostFile = 'ClaudePrivacy.Host.exe'
$script:BuildRecordFile = 'runtime-build.json'

function ConvertTo-PrivacyProcessArgument([string]$Value) {
  # Windows argv quoting, including embedded quotes and trailing backslashes.
  $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  '"' + $escaped + '"'
}
function Invoke-PrivacyHiddenProcess([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory, [int]$TimeoutSeconds = 60) {
  if (-not [IO.Path]::IsPathRooted($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw 'Hidden child requires an existing absolute executable path.' }
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = $FilePath
  $start.Arguments = (@($Arguments | ForEach-Object { ConvertTo-PrivacyProcessArgument $_ }) -join ' ')
  $start.WorkingDirectory = $WorkingDirectory
  $start.UseShellExecute = $false; $start.CreateNoWindow = $true; $start.WindowStyle = 'Hidden'
  $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
  $start.EnvironmentVariables['PSModulePath'] = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\Modules'
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $start
  try {
    if (-not $process.Start()) { throw 'Could not start hidden child.' }
    $process.StandardInput.Close()
    $output = $process.StandardOutput.ReadToEndAsync(); $errorOutput = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      $process.Kill(); $process.WaitForExit()
      throw 'Hidden child timed out; its exact process was stopped.'
    }
    [pscustomobject]@{ exitCode = $process.ExitCode; output = $output.GetAwaiter().GetResult(); error = $errorOutput.GetAwaiter().GetResult() }
  } finally { $process.Dispose() }
}
function New-PrivacyHostExecutable([string]$SourcePath, [string]$OutputPath) {
  if (Test-Path -LiteralPath $OutputPath) { throw 'Refusing to replace an existing compiled host.' }
  $windows = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
  $framework = Join-Path $windows 'Microsoft.NET\Framework64\v4.0.30319'
  if (-not [Environment]::Is64BitOperatingSystem) { $framework = Join-Path $windows 'Microsoft.NET\Framework\v4.0.30319' }
  $compiler = Join-Path $framework 'csc.exe'
  $signature = Get-AuthenticodeSignature -LiteralPath $compiler
  if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') { throw 'Windows C# compiler identity could not be verified.' }
  $arguments = @('/nologo','/noconfig','/nostdlib+','/target:winexe','/platform:anycpu','/optimize+','/debug-','/codepage:65001',
    ('/reference:' + (Join-Path $framework 'mscorlib.dll')), ('/reference:' + (Join-Path $framework 'System.dll')), ('/out:' + $OutputPath), $SourcePath)
  $result = Invoke-PrivacyHiddenProcess $compiler $arguments (Split-Path -Parent $OutputPath)
  if ($result.exitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw ('GUI host compilation failed: ' + $result.output + $result.error) }
  $bytes = [IO.File]::ReadAllBytes($OutputPath)
  $pe = [BitConverter]::ToInt32($bytes, 0x3c)
  if ([BitConverter]::ToUInt16($bytes, ($pe + 24 + 68)) -ne 2) { throw 'Compiled host is not a Windows GUI-subsystem executable.' }
}

function Get-PrivacyMaintenancePath { Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) 'maintenance.json' }
function Get-PrivacyRunPath { Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) 'maintenance-last-run.json' }
function Get-PrivacyTaskName { 'CVSRK-ClaudePrivacy-' + (Get-PrivacyDigest (Get-PrivacySid)).Substring(0, 16) }
function Read-PrivacyMaintenance {
  $path = Get-PrivacyMaintenancePath
  Assert-PrivacyStateDirectory $path
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($value.schemaVersion -ne 1 -or $value.ownerSid -ne (Get-PrivacySid) -or $value.taskName -ne (Get-PrivacyTaskName)) { throw 'Maintenance ownership record mismatch.' }
  return $value
}
function Get-PrivacyTaskFolder {
  $service = New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $service.GetFolder('\')
}
function Get-PrivacyTask {
  $folder = Get-PrivacyTaskFolder
  try { $task = $folder.GetTask((Get-PrivacyTaskName)) }
  catch {
    if (($_.Exception.HResult -band 0xffff) -eq 2 -or ($_.Exception.InnerException -and ($_.Exception.InnerException.HResult -band 0xffff) -eq 2)) { return $null }
    throw
  }
  [pscustomobject]@{ xml = [string]$task.Xml; sddl = [string]$task.GetSecurityDescriptor(7); enabled = [bool]$task.Enabled; lastResult = $task.LastTaskResult; lastRun = $task.LastRunTime; nextRun = $task.NextRunTime; state = $task.State }
}
function Get-PrivacyTaskFingerprint($Task) {
  Get-PrivacyDigest ($Task.xml.Trim() + '|' + $Task.sddl.Trim())
}
function Get-PrivacyTaskSddl([string]$Sid) { 'O:BAG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGX;;;' + $Sid + ')' }
function Resolve-PrivacyTaskUserSid([string]$Identity) {
  if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'Scheduled task user identity is empty.' }
  try {
    if ($Identity -match '^S-[0-9]+-') { return (New-Object Security.Principal.SecurityIdentifier($Identity)).Value }
    # Task Scheduler can serialize a logon trigger SID as DOMAIN\account.
    # Resolve its identity, never compare display names or accept any-user logon.
    (New-Object Security.Principal.NTAccount($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
  } catch { throw 'Scheduled task user identity cannot be resolved to a SID.' }
}
function Assert-PrivacyTaskSecurity($Task, [string]$Sid, [string]$RuntimeRoot) {
  [xml]$actual = $Task.xml
  [xml]$expected = New-PrivacyTaskXml $Sid $RuntimeRoot '2026-01-01T00:00:00Z'
  if (-not $Task.enabled -or (Resolve-PrivacyTaskUserSid $actual.Task.Principals.Principal.UserId) -ne $Sid -or
      $actual.Task.Principals.Principal.LogonType -ne 'InteractiveToken' -or $actual.Task.Principals.Principal.RunLevel -ne 'HighestAvailable' -or
      $actual.Task.Principals.ChildNodes.Count -ne 1 -or $actual.Task.Triggers.ChildNodes.Count -ne 2 -or
      $actual.Task.Actions.ChildNodes.Count -ne 1 -or $actual.Task.Actions.Exec.Command -ine $expected.Task.Actions.Exec.Command -or
      $actual.Task.Actions.Exec.Arguments -cne $expected.Task.Actions.Exec.Arguments -or $actual.Task.Actions.Exec.WorkingDirectory -ine $RuntimeRoot -or
      $actual.Task.Triggers.TimeTrigger.Repetition.Interval -ne 'PT2M' -or (Resolve-PrivacyTaskUserSid $actual.Task.Triggers.LogonTrigger.UserId) -ne $Sid) { throw 'Scheduled task security readback mismatch.' }
  $descriptor = New-Object Security.AccessControl.RawSecurityDescriptor($Task.sddl)
  if ($descriptor.Owner.Value -notin @('S-1-5-18','S-1-5-32-544')) { throw 'Task owner must be Administrators or SYSTEM.' }
  if (-not $descriptor.DiscretionaryAcl -or $descriptor.DiscretionaryAcl.Count -eq 0) { throw 'Task ACL must explicitly restrict access.' }
  foreach ($ace in $descriptor.DiscretionaryAcl) {
    if ($ace.AceType -eq 'AccessAllowed' -and $ace.SecurityIdentifier.Value -notin @('S-1-5-18','S-1-5-32-544') -and
        ($ace.AccessMask -band 0x500D0116)) { throw 'Task ACL permits non-administrator changes.' }
  }
}
function New-PrivacyTaskXml([string]$Sid, [string]$RuntimeRoot, [string]$StartBoundary) {
  $exe = [Security.SecurityElement]::Escape((Join-Path $RuntimeRoot $script:HostFile))
  $arguments = '--scheduled'
  $directory = [Security.SecurityElement]::Escape($RuntimeRoot)
  @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>ClashVergeSteamRoutingKit</Author><Description>Explicitly enabled Claude UDP privacy refresh. Same user, protected code, every two minutes while logged on. Does not enable protection after rollback.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$Sid</UserId></LogonTrigger>
    <TimeTrigger><Repetition><Interval>PT2M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>$StartBoundary</StartBoundary><Enabled>true</Enabled></TimeTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$Sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>false</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT1M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>$exe</Command><Arguments>$arguments</Arguments><WorkingDirectory>$directory</WorkingDirectory></Exec></Actions>
</Task>
"@
}
function Get-PrivacyRuntimeManifest([string]$SourceRoot) {
  $records = @($script:RuntimeFiles | ForEach-Object {
    $path = Join-Path $SourceRoot $_
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Required runtime file missing: ' + $_) }
    [pscustomobject]@{ relative = $_; sha256 = Get-PrivacyFileHash $path }
  })
  [pscustomobject]@{ digest = (Get-PrivacyDigest (ConvertTo-PrivacyJson $records)).Substring(0, 24); files = $records }
}
function Assert-PrivacyProtectedTree([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Protected runtime may not traverse a reparse point.' }
  $items = @($item)
  if ($item.PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $Path -Force -Recurse) }
  foreach ($entry in $items) {
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Protected runtime contains a reparse point.' }
    $acl = Get-Acl -LiteralPath $entry.FullName
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')) { throw 'Protected runtime has a non-administrator owner.' }
    foreach ($access in $acl.Access) {
      $sid = $access.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
      $mask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
      if ($access.AccessControlType -eq 'Allow' -and ($access.FileSystemRights -band $mask) -and $sid -notin @('S-1-5-18','S-1-5-32-544')) { throw 'Protected runtime is writable without administrator rights.' }
    }
  }
}
function Set-PrivacyAdministratorOwner([string]$Path) {
  $acl = Get-Acl -LiteralPath $Path
  $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
  Set-Acl -LiteralPath $Path -AclObject $acl
}
function Assert-PrivacyRuntime($Record) {
  $expectedRoot = Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) ('runtime-' + $Record.digest)
  if ($Record.runtimeRoot -cne $expectedRoot -or $Record.digest -notmatch '^[a-f0-9]{24}$') { throw 'Invalid protected runtime root.' }
  $modern = $Record.PSObject.Properties['runtimeFormat'] -and $Record.runtimeFormat -eq 2
  if ($Record.PSObject.Properties['runtimeFormat'] -and -not $modern) { throw 'Unsupported runtime format.' }
  $expectedFiles = if ($modern) { @($script:RuntimeFiles) + @($script:HostFile) } else { @($script:LegacyRuntimeFiles) }
  if ((@($Record.files.relative | Sort-Object) -join '|') -cne (@($expectedFiles | Sort-Object) -join '|')) { throw 'Unexpected runtime manifest files.' }
  Assert-PrivacyStateDirectory (Get-PrivacyStatePath)
  Assert-PrivacyProtectedTree $expectedRoot
  $actualFiles = @(Get-ChildItem -LiteralPath $expectedRoot -File -Recurse)
  $expectedNames = @($expectedFiles)
  if ($modern) { $expectedNames += $script:BuildRecordFile }
  $actualNames = @($actualFiles | ForEach-Object { $_.FullName.Substring($expectedRoot.Length + 1).Replace('\','/') } | Sort-Object)
  if (($actualNames -join '|') -cne (@($expectedNames | Sort-Object) -join '|')) { throw 'Unexpected protected runtime contents.' }
  foreach ($file in $Record.files) {
    if ((Get-PrivacyFileHash (Join-Path $expectedRoot $file.relative)) -cne $file.sha256) { throw 'Protected runtime hash mismatch.' }
  }
  if ($modern) {
    $sources = @($Record.files | Where-Object { $_.relative -ne $script:HostFile })
    if ((Get-PrivacyDigest (ConvertTo-PrivacyJson $sources)).Substring(0, 24) -cne $Record.digest) { throw 'Runtime source digest mismatch.' }
    $build = Get-Content -LiteralPath (Join-Path $expectedRoot $script:BuildRecordFile) -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($build.runtimeFormat -ne 2 -or $build.digest -cne $Record.digest -or $build.runtimeRoot -cne $Record.runtimeRoot -or -not (Test-PrivacyEqual $build.files $Record.files)) { throw 'Protected build record differs from runtime ownership record.' }
  }
}
function Install-PrivacyRuntime([string]$SourceRoot, $Manifest) {
  $statePath = Get-PrivacyStatePath
  Assert-PrivacyStateDirectory $statePath -Create
  $root = Join-Path (Split-Path -Parent $statePath) ('runtime-' + $Manifest.digest)
  $record = [pscustomobject]@{ runtimeFormat = 2; runtimeRoot = $root; digest = $Manifest.digest; files = @($Manifest.files) }
  if (Test-Path -LiteralPath $root) {
    Assert-PrivacyProtectedTree $root
    $saved = Get-Content -LiteralPath (Join-Path $root $script:BuildRecordFile) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not (Test-PrivacyEqual @($saved.files | Where-Object { $_.relative -ne $script:HostFile }) $Manifest.files)) { throw 'Existing build does not match reviewed sources.' }
    Assert-PrivacyRuntime $saved
    return $saved
  }
  [IO.Directory]::CreateDirectory($root) | Out-Null
  Set-PrivacyAdministratorOwner $root
  [IO.Directory]::CreateDirectory((Join-Path $root 'scripts')) | Out-Null
  Set-PrivacyAdministratorOwner (Join-Path $root 'scripts')
  foreach ($file in $Manifest.files) {
    $target = Join-Path $root $file.relative
    Copy-Item -LiteralPath (Join-Path $SourceRoot $file.relative) -Destination $target
    Set-PrivacyAdministratorOwner $target
  }
  $hostPath = Join-Path $root $script:HostFile
  New-PrivacyHostExecutable (Join-Path $root 'scripts/ClaudePrivacy.Host.cs') $hostPath
  Set-PrivacyAdministratorOwner $hostPath
  $record.files += [pscustomobject]@{ relative = $script:HostFile; sha256 = Get-PrivacyFileHash $hostPath }
  Save-PrivacyProtectedJson (Join-Path $root $script:BuildRecordFile) $record
  Assert-PrivacyRuntime $record
  return $record
}
function Test-PrivacyMaintenanceGate($State, $Record, [string]$Sid) {
  $State -and $State.PSObject.Properties['enabled'] -and $State.enabled -and $State.phase -eq 'AppliedConfigurationOnly' -and
    $State.ownerSid -eq $Sid -and $Record -and $Record.enabled -and $Record.phase -eq 'Enabled' -and $Record.ownerSid -eq $Sid
}
function Get-PrivacyMaintenancePlan([string]$SourceRoot) {
  $manifest = Get-PrivacyRuntimeManifest $SourceRoot
  $runtimeRoot = Join-Path (Split-Path -Parent (Get-PrivacyStatePath)) ('runtime-' + $manifest.digest)
  [pscustomobject]@{ taskName = Get-PrivacyTaskName; ownerSid = Get-PrivacySid; logonType = 'InteractiveToken'; runLevel = 'HighestAvailable'; interval = 'PT2M'; logonTrigger = $true; runtimeFormat = 2; launcher = 'GUI host with CreateNoWindow'; runtimeRoot = $runtimeRoot; digest = $manifest.digest; files = $manifest.files; generatedFiles = @($script:HostFile, $script:BuildRecordFile) }
}
function Enable-PrivacyMaintenance([string]$SourceRoot) {
  if (-not (Test-PrivacyAdministrator)) { throw 'Maintenance enablement requires same-user elevation.' }
  $state = Read-PrivacyState
  if (-not $state.PSObject.Properties['enabled'] -or -not $state.enabled -or $state.phase -ne 'AppliedConfigurationOnly') { throw 'Apply protection successfully before enabling maintenance.' }
  $existing = Read-PrivacyMaintenance
  $task = Get-PrivacyTask
  if ($task -and (-not $existing -or -not $existing.taskFingerprint -or (Get-PrivacyTaskFingerprint $task) -cne $existing.taskFingerprint)) { throw 'Scheduled task is unowned or changed; preserved.' }
  $manifest = Get-PrivacyRuntimeManifest $SourceRoot
  if ($existing -and $existing.enabled -and $existing.phase -eq 'Enabled' -and $existing.digest -eq $manifest.digest -and $task) {
    Assert-PrivacyRuntime $existing
    Assert-PrivacyTaskSecurity $task (Get-PrivacySid) $existing.runtimeRoot
    return $existing
  }
  $runtime = Install-PrivacyRuntime $SourceRoot $manifest
  $sid = Get-PrivacySid
  $xml = New-PrivacyTaskXml $sid $runtime.runtimeRoot ([DateTimeOffset]::Now.AddMinutes(2).ToString('yyyy-MM-ddTHH:mm:sszzz'))
  $record = [pscustomobject][ordered]@{
    schemaVersion = 1; ownerSid = $sid; enabled = $false; phase = 'Pending'; taskName = Get-PrivacyTaskName
    taskFingerprint = $(if ($existing) { $existing.taskFingerprint } else { $null }); runtimeRoot = $runtime.runtimeRoot
    runtimeFormat = $runtime.runtimeFormat; digest = $runtime.digest; files = $runtime.files; intervalSeconds = 120; updatedUtc = [DateTime]::UtcNow.ToString('o')
  }
  Save-PrivacyProtectedJson (Get-PrivacyMaintenancePath) $record
  $folder = Get-PrivacyTaskFolder
  # CREATE_OR_UPDATE | DONT_ADD_PRINCIPAL_ACE prevents an implicit writable user ACE.
  # TASK_LOGON_INTERACTIVE_TOKEN=3. No password stored.
  $registered = $folder.RegisterTask($record.taskName, $xml, 22, $sid, $null, 3, (Get-PrivacyTaskSddl $sid))
  $actual = Get-PrivacyTask
  if (-not $actual) { throw 'Scheduled task registration readback failed.' }
  $record.taskFingerprint = Get-PrivacyTaskFingerprint $actual
  Save-PrivacyProtectedJson (Get-PrivacyMaintenancePath) $record
  Assert-PrivacyTaskSecurity $actual $sid $runtime.runtimeRoot
  $record.enabled = $true; $record.phase = 'Enabled'
  Save-PrivacyProtectedJson (Get-PrivacyMaintenancePath) $record
  return $record
}
function Disable-PrivacyMaintenance {
  if (-not (Test-PrivacyAdministrator)) { throw 'Maintenance disablement requires same-user elevation.' }
  $record = Read-PrivacyMaintenance
  $task = Get-PrivacyTask
  if (-not $record) {
    if ($task) { throw 'An unowned maintenance task exists; preserved.' }
    return
  }
  # Durable gate first: even a later task-removal failure cannot re-enable protection.
  $record.enabled = $false; $record.phase = 'Disabled'; $record.updatedUtc = [DateTime]::UtcNow.ToString('o')
  Save-PrivacyProtectedJson (Get-PrivacyMaintenancePath) $record
  if ($task) {
    if (-not $record.taskFingerprint -or (Get-PrivacyTaskFingerprint $task) -cne $record.taskFingerprint) { throw 'Maintenance disabled in journal; externally changed task preserved for review.' }
    $folder = Get-PrivacyTaskFolder
    $registered = $folder.GetTask($record.taskName)
    $registered.Enabled = $false
    $folder.DeleteTask($record.taskName, 0)
    if (Get-PrivacyTask) { throw 'Scheduled task removal readback failed.' }
  }
  return $record
}
function Save-PrivacyMaintenanceRun([string]$Result, [int]$Code, [string]$Message, $Metrics = $null) {
  $value = [pscustomobject]@{
    schemaVersion = 1; ownerSid = Get-PrivacySid; timeUtc = [DateTime]::UtcNow.ToString('o')
    result = $Result; exitCode = $Code; message = $Message
  }
  if ($Metrics) { $value | Add-Member NoteProperty metrics $Metrics }
  Save-PrivacyProtectedJson (Get-PrivacyRunPath) $value
}
function Get-PrivacyMaintenanceStatus {
  $record = Read-PrivacyMaintenance
  $task = Get-PrivacyTask
  $last = $null; $path = Get-PrivacyRunPath
  Assert-PrivacyStateDirectory $path
  if (Test-Path -LiteralPath $path) { $last = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
  $health = 'Disabled'
  if ($record -and $record.phase -eq 'Pending') { $health = 'NeedsReview' }
  elseif ($task -and (-not $record -or -not $record.enabled)) { $health = 'UnexpectedTask' }
  if ($record -and $record.enabled) {
    if (-not $task) { $health = 'TaskMissing' }
    elseif ((Get-PrivacyTaskFingerprint $task) -cne $record.taskFingerprint) { $health = 'TaskChanged' }
    elseif (-not $last) { $health = 'AwaitingFirstRun' }
    elseif ($last.exitCode -ne 0 -or $task.lastResult -notin @(0,267009,267011)) { $health = 'Failed' }
    elseif ((Get-PrivacyRunAge $last.timeUtc) -gt 6) { $health = 'Stale' }
    else { $health = 'RecentSuccess' }
    try { Assert-PrivacyRuntime $record } catch { $health = 'RuntimeChanged' }
  }
  [pscustomobject]@{ health = $health; record = $record; task = $task; lastRun = $last }
}
function Get-PrivacyRunAge($Time) {
  $when = if ($Time -is [DateTime]) { [DateTimeOffset]$Time.ToUniversalTime() } elseif ($Time -is [DateTimeOffset]) { $Time } else { [DateTimeOffset]::Parse([string]$Time, [Globalization.CultureInfo]::InvariantCulture) }
  ([DateTimeOffset]::UtcNow - $when).TotalMinutes
}
Export-ModuleMember -Function *-Privacy*
