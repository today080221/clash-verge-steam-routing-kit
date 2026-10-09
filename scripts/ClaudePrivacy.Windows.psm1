Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ClaudePrivacy.Core.psm1')
$script:ChromeKey = 'Software\Policies\Google\Chrome'
$script:PolicyName = 'WebRtcIPHandlingUrl'

function Get-PrivacySid { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Test-PrivacyAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-PrivacyPolicy {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:ChromeKey, $false)
  try {
    if ($key -and $key.GetValueNames() -contains $script:PolicyName) {
      return [pscustomobject]@{ present = $true; kind = [string]$key.GetValueKind($script:PolicyName); raw = [string]$key.GetValue($script:PolicyName) }
    }
    [pscustomobject]@{ present = $false; kind = $null; raw = $null }
  } finally { if ($key) { $key.Dispose() } }
}
function Set-PrivacyPolicy($Policy) {
  if ($Policy.present) {
    if ($Policy.kind -ne 'String') { throw 'Refusing non-string Chrome policy write.' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:ChromeKey)
    try { $key.SetValue($script:PolicyName, $Policy.raw, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
  } else {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:ChromeKey, $true)
    try { if ($key) { $key.DeleteValue($script:PolicyName, $false) } }
    finally { if ($key) { $key.Dispose() } }
  }
}
function Get-PrivacyExecutableKind([string]$SignatureStatus, [string]$SignerSubject, [string]$ProductName, [string]$CompanyName) {
  if ($SignatureStatus -ne 'Valid' -or $SignerSubject -notmatch '(?:^|,\s*)O="?Anthropic,? PBC"?(?:,|$)') { return 'Unverified' }
  if ($ProductName -ceq 'Claude' -and $CompanyName -ceq 'Anthropic') { return 'Desktop' }
  if ($ProductName -ceq 'Claude Code' -and $CompanyName -ceq 'Anthropic PBC') { return 'NativeCli' }
  return 'Unverified'
}
function Get-PrivacyExecutableIdentity([string]$Path) {
  $result = [pscustomobject]@{ path = $Path; kind = 'Unverified'; reason = 'Candidate is not an exact absolute Claude.exe file.' }
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetFileName($Path) -ine 'Claude.exe' -or $Path -match '[*?%]') { return $result }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $result.reason = 'Candidate file was not found.'; return $result }
  $item = Get-Item -LiteralPath $Path
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $result.reason = 'Candidate file is a reparse point.'; return $result }
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  $subject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
  $result.kind = Get-PrivacyExecutableKind ([string]$signature.Status) $subject $item.VersionInfo.ProductName $item.VersionInfo.CompanyName
  $result.reason = if ($result.kind -eq 'Unverified') { 'Signature or exact product/company identity is not recognized.' } else { $null }
  return $result
}
function Test-PrivacyExecutable([string]$Path) { (Get-PrivacyExecutableIdentity $Path).kind -in @('Desktop','NativeCli') }
function Get-PrivacyNativeCliPath {
  Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.local\bin\claude.exe'
}
function Get-PrivacyDiscovery([string[]]$ClaudePath = @(), [ValidateSet('Desktop','DesktopAndCli')][string]$ProtectionScope = 'Desktop') {
  $paths = @(); $errors = @(); $executables = @(); $excluded = @()
  $candidates = @($ClaudePath | ForEach-Object { [pscustomobject]@{ path = $_; source = 'Explicit'; expectedKind = $null } })
  try {
    foreach ($package in @(Get-AppxPackage -Name Claude -ErrorAction Stop)) {
      if ($package.PackageFamilyName -ne 'Claude_pzs8sxrjxfjjc' -or $package.Status -ne 'Ok') {
        $errors += 'Unrecognized or unhealthy Claude MSIX package.'; continue
      }
      $candidates += [pscustomobject]@{ path = (Join-Path $package.InstallLocation 'app\Claude.exe'); source = 'MSIX'; expectedKind = 'Desktop' }
    }
    if ($ProtectionScope -eq 'DesktopAndCli') {
      $nativePath = Get-PrivacyNativeCliPath
      $candidates += [pscustomobject]@{ path = $nativePath; source = 'NativeInstallation'; expectedKind = 'NativeCli' }
    }
    # Retain older still-running versions until their processes have exited.
    foreach ($process in @(Get-Process -Name Claude -ErrorAction SilentlyContinue)) {
      if (-not $process.Path) { $errors += 'A running Claude process path could not be read.' }
      else { $candidates += [pscustomobject]@{ path = $process.Path; source = 'Running'; expectedKind = $null } }
    }
  } catch { $errors += 'Package/process discovery failed: ' + $_.Exception.Message }
  foreach ($group in @($candidates | Group-Object -Property path)) {
    $path = [string]$group.Group[0].path
    try {
      $identity = Get-PrivacyExecutableIdentity $path
      if ($identity.kind -eq 'Unverified') { $errors += ('Claude candidate could not be confirmed: ' + $path + '; ' + $identity.reason); continue }
      if (@($group.Group | Where-Object { $_.expectedKind -and $_.expectedKind -ne $identity.kind }).Count) { $errors += ('Claude installation identity does not match its source: ' + $path); continue }
      if ($identity.kind -eq 'NativeCli' -and $ProtectionScope -eq 'Desktop') {
        if (@($group.Group | Where-Object { $_.source -eq 'Explicit' }).Count) { $errors += ('Explicit CLI path requires DesktopAndCli scope: ' + $path) }
        else { $excluded += [pscustomobject]@{ path = $path; kind = $identity.kind; reason = 'Verified CLI is outside the selected Desktop scope.' } }
        continue
      }
      $paths += [IO.Path]::GetFullPath($path)
      $executables += [pscustomobject]@{ path = [IO.Path]::GetFullPath($path); kind = $identity.kind; sources = @($group.Group.source | Sort-Object -Unique) }
    } catch { $errors += 'Claude candidate inspection failed: ' + $path }
  }
  [pscustomobject]@{ paths = @($paths | Sort-Object -Unique); errors = @($errors); executables = @($executables); excluded = @($excluded); protectionScope = $ProtectionScope }
}
function ConvertFrom-PrivacyFirewallRule($Rule) {
  $app = $Rule | Get-NetFirewallApplicationFilter
  $port = $Rule | Get-NetFirewallPortFilter
  $addr = $Rule | Get-NetFirewallAddressFilter
  $svc = $Rule | Get-NetFirewallServiceFilter
  $iface = $Rule | Get-NetFirewallInterfaceFilter
  $type = $Rule | Get-NetFirewallInterfaceTypeFilter
  $security = $Rule | Get-NetFirewallSecurityFilter
  # Include all configurable filter details in the ownership fingerprint.
  $detail = [ordered]@{}
  $objects = @($Rule, $app, $port, $addr, $svc, $iface, $type, $security)
  $fields = @(
    @('Name','DisplayName','Description','Group','Enabled','Profile','Platform','Direction','Action','EdgeTraversalPolicy','LooseSourceMapping','LocalOnlyMapping','Owner'),
    @('Program','Package'), @('Protocol','LocalPort','RemotePort','IcmpType','DynamicTarget'),
    @('LocalAddress','RemoteAddress'), @('Service'), @('InterfaceAlias'), @('InterfaceType'),
    @('Authentication','Encryption','OverrideBlockRules','LocalUser','RemoteUser','RemoteMachine')
  )
  for ($i = 0; $i -lt $objects.Count; $i++) {
    foreach ($field in $fields[$i]) { $detail["$i.$field"] = @($objects[$i].$field | ForEach-Object { [string]$_ }) }
  }
  [pscustomobject][ordered]@{
    name = [string]$Rule.Name; group = [string]$Rule.Group; program = [string]$app.Program
    direction = [string]$Rule.Direction; action = [string]$Rule.Action; enabled = [string]$Rule.Enabled; profile = [string]$Rule.Profile
    protocol = $(if ([string]$port.Protocol -eq '17') { 'UDP' } else { [string]$port.Protocol })
    localPort = [string]($port.LocalPort -join ','); remotePort = [string]($port.RemotePort -join ',')
    localAddress = [string]($addr.LocalAddress -join ','); remoteAddress = [string]($addr.RemoteAddress -join ',')
    service = [string]$svc.Service; package = $(if ([string]::IsNullOrEmpty([string]$app.Package)) { 'Any' } else { [string]$app.Package })
    interfaceAlias = [string]($iface.InterfaceAlias -join ','); interfaceType = [string]$type.InterfaceType
    fingerprint = Get-PrivacyDigest (ConvertTo-PrivacyJson $detail)
  }
}
function Get-PrivacyRules([ValidateSet('PersistentStore','ActiveStore')][string]$PolicyStore = 'PersistentStore') {
  # Provider-side prefix query, including unowned collisions; never enumerate
  # every unrelated firewall rule and then filter it in PowerShell.
  @(Get-NetFirewallRule -PolicyStore $PolicyStore -Name 'CVSRK-ClaudeUDP-*' -ErrorAction Stop | ForEach-Object { ConvertFrom-PrivacyFirewallRule $_ })
}
function Get-PrivacyRule([string]$Name) {
  # Enumerating avoids treating access-denied as the ordinary no-match case.
  $rules = @(Get-PrivacyRules | Where-Object { $_.name -eq $Name })
  if ($rules.Count -gt 1) { throw 'Duplicate firewall rule names.' }
  if ($rules.Count -eq 1) { return $rules[0] }
  return $null
}
function Add-PrivacyRule($Rule) {
  # Revalidate executable just before mutation. No package-SID/full-trust assumption.
  if (-not (Test-PrivacyExecutable $Rule.program)) { throw 'Claude executable changed or is no longer verifiable.' }
  New-NetFirewallRule -PolicyStore PersistentStore -Name $Rule.name -DisplayName 'Claude UDP privacy (routing kit)' -Group $Rule.group `
    -Description 'Owned by routing kit. Exact Claude.exe outbound UDP only. Use claude-privacy.ps1 rollback.' `
    -Program $Rule.program -Direction Outbound -Action Block -Enabled True -Profile Any -Protocol UDP | Out-Null
}
function Remove-PrivacyRule([string]$Name) {
  Remove-NetFirewallRule -PolicyStore PersistentStore -Name $Name -ErrorAction Stop
}
function Get-PrivacySnapshot([string[]]$ClaudePath = @(), [ValidateSet('Desktop','DesktopAndCli')][string]$ProtectionScope = 'Desktop') {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $discovery = Get-PrivacyDiscovery $ClaudePath $ProtectionScope
  $timings = [ordered]@{ discoveryMs = $watch.ElapsedMilliseconds; persistentRulesMs = 0; activeRulesMs = 0; profilesMs = 0 }
  $rules = @(); $activeRules = @(); $profiles = @(); $firewallError = $null
  try {
    $watch.Restart()
    $rules = @(Get-PrivacyRules)
    $timings.persistentRulesMs = $watch.ElapsedMilliseconds; $watch.Restart()
    $activeRules = @(Get-PrivacyRules -PolicyStore ActiveStore)
    $timings.activeRulesMs = $watch.ElapsedMilliseconds; $watch.Restart()
    $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Select-Object Name, Enabled, AllowLocalFirewallRules)
    $timings.profilesMs = $watch.ElapsedMilliseconds
  } catch { $firewallError = $_.Exception.Message }
  [pscustomobject]@{
    sid = Get-PrivacySid; policy = Get-PrivacyPolicy; paths = $discovery.paths
    protectionScope = $ProtectionScope; executables = $discovery.executables; excludedExecutables = $discovery.excluded
    discoveryErrors = $discovery.errors; rules = $rules; activeRules = $activeRules; firewallProfiles = $profiles; firewallReadError = $firewallError
    administrator = Test-PrivacyAdministrator
    timings = [pscustomobject]$timings
    runtimeAcceptance = 'Not verified: Chrome policy loading/ICE, Claude UDP attribution and proxy health require live acceptance.'
  }
}
function Get-PrivacyStatePath {
  Join-Path $env:ProgramData ('ClashVergeSteamRoutingKit-ClaudePrivacy\' + (Get-PrivacySid) + '\state.json')
}
function Assert-PrivacyStateDirectory([string]$Path, [switch]$Create) {
  $dir = Split-Path -Parent $Path
  # Check every existing ancestor before creating/writing privileged state.
  $ancestor = $dir
  while ($ancestor) {
    if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw 'Privacy state directory may not traverse a reparse point.'
    }
    $ancestor = Split-Path -Parent $ancestor
  }
  $base = Split-Path -Parent $dir
  foreach ($secureDir in @($base, $dir)) {
    if (Test-Path -LiteralPath $secureDir) { continue }
    if (-not $Create) { return }
    [IO.Directory]::CreateDirectory($secureDir) | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
      $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
      $acl.AddAccessRule($rule)
    }
    $reader = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier((Get-PrivacySid))), 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($reader)
    Set-Acl -LiteralPath $secureDir -AclObject $acl
  }
  foreach ($item in @($base, $dir, $Path)) {
    if (-not (Test-Path -LiteralPath $item)) { continue }
    if ((Get-Item -LiteralPath $item).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Privacy state may not be a reparse point.' }
    $acl = Get-Acl -LiteralPath $item
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18', 'S-1-5-32-544')) {
      throw 'Privacy ownership state must be owned by Administrators or SYSTEM.'
    }
    foreach ($access in $acl.Access) {
      $sid = $access.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
      $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
      if ($access.AccessControlType -eq 'Allow' -and ($access.FileSystemRights -band $writeMask) -and $sid -notin @('S-1-5-18', 'S-1-5-32-544')) {
        throw 'Privacy ownership state is writable by a non-administrator. Refusing to trust it.'
      }
    }
  }
}
function Read-PrivacyState {
  $path = Get-PrivacyStatePath
  Assert-PrivacyStateDirectory $path
  if (-not (Test-Path -LiteralPath $path)) { return New-PrivacyState (Get-PrivacySid) }
  Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Save-PrivacyState($State) {
  $path = Get-PrivacyStatePath
  Save-PrivacyProtectedJson $path $State
}
function Complete-PrivacyStagedFile([string]$Temp, [string]$Path) {
  # PowerShell 5.1 converts ordinary $null to an empty string for this .NET
  # string parameter. NullString preserves a real null backup path.
  # Keep Replace's metadata/ACL error checking and never delete the target first.
  if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($Temp, $Path, [NullString]::Value) }
  else { [IO.File]::Move($Temp, $Path) }
}
function Save-PrivacyProtectedJson([string]$Path, $Value) {
  Assert-PrivacyStateDirectory $Path -Create
  $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  [IO.File]::WriteAllText($temp, (ConvertTo-PrivacyJson $Value), (New-Object Text.UTF8Encoding($false)))
  $acl = Get-Acl -LiteralPath $temp
  $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
  Set-Acl -LiteralPath $temp -AclObject $acl
  Complete-PrivacyStagedFile $temp $Path
}
function Get-PrivacyAdapter {
  @{
    SaveState = { param($s) Save-PrivacyState $s }; ReadPolicy = { Get-PrivacyPolicy }
    WritePolicy = { param($p) Set-PrivacyPolicy $p }; ReadRule = { param($n) Get-PrivacyRule $n }
    AddRule = { param($r) Add-PrivacyRule $r }; RemoveRule = { param($n) Remove-PrivacyRule $n }
  }
}
Export-ModuleMember -Function *-Privacy*
