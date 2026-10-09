Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:PolicyUrls = @('https://[*.]claude.ai', 'https://[*.]claude.com', 'https://[*.]anthropic.com')
$script:Group = 'ClashVergeSteamRoutingKit.ClaudePrivacy.v1'

function ConvertTo-PrivacyJson($Value) { ConvertTo-Json -InputObject $Value -Depth 40 -Compress }
function Test-PrivacyEqual($Left, $Right) { (ConvertTo-PrivacyJson $Left) -ceq (ConvertTo-PrivacyJson $Right) }
function Get-PrivacyDigest([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}
function Get-PrivacyFileHash([string]$Path) {
  # Windows PowerShell 5.1 Get-FileHash internally honors inherited WhatIf and
  # can return no hash. This read-only operation must work inside previews.
  $stream = [IO.File]::OpenRead($Path)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
  finally { $sha.Dispose(); $stream.Dispose() }
}
function New-PrivacyState([string]$Sid) {
  [pscustomobject][ordered]@{ schemaVersion = 1; ownerSid = $Sid; enabled = $false; phase = 'New'; protectionScope = 'Desktop'; policy = $null; rules = @(); lastError = $null }
}
function Get-PrivacyProtectionScope($State, [string]$RequestedScope) {
  $scope = if ($RequestedScope) { $RequestedScope } elseif ($State -and $State.PSObject.Properties['protectionScope']) { [string]$State.protectionScope } else { 'Desktop' }
  if ($scope -notin @('Desktop','DesktopAndCli')) { throw 'Unsupported privacy protection scope.' }
  return $scope
}
function Read-PrivacyPolicy($Policy) {
  if (-not $Policy.present) { return ,@() }
  if ($Policy.kind -ne 'String' -or -not $Policy.raw.Trim().StartsWith('[')) { throw 'Chrome WebRtcIPHandlingUrl must be a REG_SZ JSON array; preserved unchanged.' }
  $parsed = ConvertFrom-Json -InputObject $Policy.raw
  $entries = @($parsed)
  $seen = @{}
  foreach ($entry in $entries) {
    if (-not $entry -or -not $entry.PSObject.Properties['url'] -or -not $entry.PSObject.Properties['handling'] -or
        $entry.url -isnot [string] -or $entry.handling -notin @('default', 'default_public_and_private_interfaces', 'default_public_interface_only', 'disable_non_proxied_udp')) {
      throw 'Unsupported Chrome policy entry; preserved unchanged.'
    }
    if ($seen.ContainsKey($entry.url)) { throw 'Duplicate Chrome URL entries require manual review.' }
    $seen[$entry.url] = $true
  }
  return ,$entries
}
function New-PrivacyRule([string]$Path, [string]$Sid) {
  if (-not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetFileName($Path) -ine 'Claude.exe' -or $Path -match '[*?%]') {
    throw 'Only exact absolute Claude.exe paths are supported.'
  }
  [pscustomobject][ordered]@{
    name = 'CVSRK-ClaudeUDP-' + (Get-PrivacyDigest ($Sid + '|' + $Path.ToLowerInvariant())).Substring(0, 24)
    group = $script:Group
    program = $Path
    direction = 'Outbound'; action = 'Block'; enabled = 'True'; profile = 'Any'
    protocol = 'UDP'; localPort = 'Any'; remotePort = 'Any'; localAddress = 'Any'; remoteAddress = 'Any'
    service = 'Any'; package = 'Any'; interfaceAlias = 'Any'; interfaceType = 'Any'
    # Windows adapter also fingerprints the full rule + associated filter state.
    fingerprint = $null
  }
}
function Test-PrivacyRuleSpec($Current, $Expected) {
  foreach ($key in @('name','group','program','direction','action','enabled','profile','protocol','localPort','remotePort','localAddress','remoteAddress','service','package','interfaceAlias','interfaceType')) {
    if ([string]$Current.$key -ine [string]$Expected.$key) { return $false }
  }
  return $true
}
function New-PrivacyPlan {
  param($Snapshot, $State, [ValidateSet('apply','refresh','rollback')][string]$Action)
  if ($State.schemaVersion -ne 1 -or $State.ownerSid -ne $Snapshot.sid) { throw 'Privacy state schema/user mismatch.' }
  # Copy the state: previews must never mutate the caller's state.
  $next = ConvertFrom-Json (ConvertTo-PrivacyJson $State)
  if (-not $next.PSObject.Properties['enabled']) { $next | Add-Member NoteProperty enabled $false }
  $previousScope = Get-PrivacyProtectionScope $State
  $scope = if ($Action -eq 'rollback' -or -not $Snapshot.PSObject.Properties['protectionScope']) { $previousScope } else { Get-PrivacyProtectionScope $Snapshot }
  if ($Action -eq 'refresh' -and $scope -ne $previousScope) { throw 'Change protection scope through explicit apply, not refresh.' }
  if (-not $next.PSObject.Properties['protectionScope']) { $next | Add-Member NoteProperty protectionScope $scope }
  else { $next.protectionScope = $scope }
  $steps = New-Object 'Collections.Generic.List[object]'
  $conflicts = New-Object 'Collections.Generic.List[string]'
  $entries = Read-PrivacyPolicy $Snapshot.policy
  if ($Action -eq 'rollback') {
    if ($next.policy) {
      if (Test-PrivacyEqual $Snapshot.policy $next.policy.applied) {
        $steps.Add([pscustomobject]@{ kind = 'Policy'; before = $Snapshot.policy; after = $next.policy.original })
        $next.policy = $null
      } elseif (Test-PrivacyEqual $Snapshot.policy $next.policy.original) {
        $next.policy = $null
      } else {
        # Remove only our identical additions; preserve all later user edits.
        $remaining = @($entries)
        $unresolved = @()
        foreach ($added in @($next.policy.added)) {
          $matches = @($remaining | Where-Object { $_.url -ceq $added.url })
          if ($matches.Count -eq 0) { continue }
          if ($matches.Count -eq 1 -and (Test-PrivacyEqual $matches[0] $added)) {
            $remaining = @($remaining | Where-Object { $_.url -cne $added.url })
          } else { $unresolved += $added; $conflicts.Add('Chrome entry changed after apply: ' + $added.url) }
        }
        if (-not (Test-PrivacyEqual $remaining $entries)) {
          $after = [pscustomobject]@{ present = $true; kind = 'String'; raw = (ConvertTo-PrivacyJson @($remaining)) }
          $steps.Add([pscustomobject]@{ kind = 'Policy'; before = $Snapshot.policy; after = $after })
        }
        if ($unresolved.Count -eq 0) { $next.policy = $null } else { $next.policy.added = $unresolved }
      }
    }
  } else {
    if ($Action -eq 'refresh' -and (-not $next.enabled -or $State.phase -ne 'AppliedConfigurationOnly')) { throw 'Run apply explicitly before refresh; failed/rolled-back states need review.' }
    if ($Snapshot.discoveryErrors.Count -gt 0) { throw ('Claude discovery incomplete: ' + ($Snapshot.discoveryErrors -join '; ')) }
    if ($Snapshot.paths.Count -eq 0) { throw 'No confirmed Claude.exe found. No policy or firewall changes planned.' }
    $newEntries = @()
    foreach ($url in $script:PolicyUrls) {
      $found = @($entries | Where-Object { $_.url -ceq $url })
      if ($found.Count -gt 0) {
        if ($found[0].handling -ne 'disable_non_proxied_udp') { throw ('Existing Chrome entry has a different handling value: ' + $url) }
        # Conservatively reject earlier non-target patterns. Their matching semantics
        # may overlap the target; never claim enforcement based on registry alone.
        foreach ($earlier in $entries) {
          if ($earlier.url -ceq $url) { break }
          if ($earlier.url -notin $script:PolicyUrls -and $earlier.handling -ne 'disable_non_proxied_udp') {
            throw ('Earlier Chrome policy needs precedence review before ' + $url)
          }
        }
      } else { $newEntries += [pscustomobject][ordered]@{ url = $url; handling = 'disable_non_proxied_udp' } }
    }
    if ($next.policy -and -not (Test-PrivacyEqual $Snapshot.policy $next.policy.applied)) {
      throw 'Managed Chrome policy drift detected. Review/rollback before reapplying; later changes are preserved.'
    }
    if ($newEntries.Count -gt 0) {
      $after = [pscustomobject]@{ present = $true; kind = 'String'; raw = (ConvertTo-PrivacyJson @($newEntries + $entries)) }
      $next.policy = [pscustomobject]@{ original = $Snapshot.policy; applied = $after; added = $newEntries }
      $steps.Add([pscustomobject]@{ kind = 'Policy'; before = $Snapshot.policy; after = $after })
    }
  }
  $kept = @()
  foreach ($owned in @($next.rules)) {
    $expected = New-PrivacyRule $owned.program $Snapshot.sid
    if (-not (Test-PrivacyRuleSpec $owned $expected)) { throw 'Invalid rule ownership record.' }
    $current = @($Snapshot.rules | Where-Object { $_.name -eq $owned.name })
    $wanted = $Action -ne 'rollback' -and $owned.program -in $Snapshot.paths
    if ($current.Count -eq 0) {
      if ($wanted) { $steps.Add([pscustomobject]@{ kind = 'AddRule'; rule = $expected }); $kept += $expected }
      continue
    }
    if ($current.Count -ne 1 -or -not $owned.fingerprint -or -not (Test-PrivacyRuleSpec $current[0] $owned) -or
        $current[0].fingerprint -cne $owned.fingerprint) {
      $conflicts.Add('Managed firewall rule changed; preserved: ' + $owned.name)
      $kept += $owned
      continue
    }
    if ($wanted) { $kept += $current[0] }
    else { $steps.Add([pscustomobject]@{ kind = 'RemoveRule'; rule = $current[0] }) }
  }
  if ($Action -ne 'rollback') {
    foreach ($path in @($Snapshot.paths | Sort-Object -Unique)) {
      $expected = New-PrivacyRule $path $Snapshot.sid
      if (@($kept | Where-Object { $_.name -eq $expected.name }).Count -gt 0) { continue }
      if (@($Snapshot.rules | Where-Object { $_.name -eq $expected.name }).Count -gt 0) {
        $conflicts.Add('Unowned firewall name collision; preserved: ' + $expected.name)
        continue
      }
      $steps.Add([pscustomobject]@{ kind = 'AddRule'; rule = $expected }); $kept += $expected
    }
  }
  $next.rules = @($kept)
  $next.phase = if ($conflicts.Count) { 'Conflict' } elseif ($Action -eq 'rollback') { 'RolledBack' } else { 'AppliedConfigurationOnly' }
  $next.enabled = $Action -ne 'rollback' -and $conflicts.Count -eq 0
  # New version rules go in before stale version rules come out.
  $orderedSteps = @($steps | Sort-Object @{ Expression = { switch ($_.kind) { 'AddRule' { 0 } 'Policy' { 1 } 'RemoveRule' { 2 } } } })
  [pscustomobject]@{ action = $Action; steps = $orderedSteps; conflicts = @($conflicts); nextState = $next }
}

function Invoke-PrivacyPlan {
  param($Plan, $State, [hashtable]$Adapter)
  # Write-ahead ownership journal; partial failures stay recoverable via rollback.
  # Refuse all apply/refresh mutations on conflict. Rollback may remove safe entries.
  if ($Plan.conflicts.Count -gt 0 -and $Plan.action -ne 'rollback') { throw ($Plan.conflicts -join '; ') }
  # The fresh snapshot has already validated discovery, policy, ownership and
  # rule fingerprints. An identical no-op needs no Pending journal or repeated
  # whole-group rule reads. Mutation paths retain their immediate readbacks.
  if ($Plan.steps.Count -eq 0 -and (Test-PrivacyEqual $State $Plan.nextState)) {
    return (ConvertFrom-Json (ConvertTo-PrivacyJson $State))
  }
  $journal = ConvertFrom-Json (ConvertTo-PrivacyJson $State)
  $journal.phase = 'Pending'; $journal.lastError = $null
  & $Adapter.SaveState $journal
  try {
    foreach ($step in $Plan.steps) {
      switch ($step.kind) {
        'Policy' {
          $current = & $Adapter.ReadPolicy
          if (-not (Test-PrivacyEqual $current $step.before)) { throw 'Chrome policy changed since preview; no registry overwrite.' }
          if ($Plan.action -ne 'rollback') { $journal.policy = $Plan.nextState.policy }
          & $Adapter.SaveState $journal
          & $Adapter.WritePolicy $step.after
          if (-not (Test-PrivacyEqual (& $Adapter.ReadPolicy) $step.after)) { throw 'Chrome policy readback mismatch.' }
          if ($Plan.action -eq 'rollback') { $journal.policy = $Plan.nextState.policy }
        }
        'AddRule' {
          if ($null -ne (& $Adapter.ReadRule $step.rule.name)) { throw 'Firewall rule appeared since preview; preserved.' }
          $journal.rules = @($journal.rules | Where-Object { $_.name -ne $step.rule.name }) + @($step.rule)
          & $Adapter.SaveState $journal
          & $Adapter.AddRule $step.rule
          $actual = & $Adapter.ReadRule $step.rule.name
          if (-not $actual -or -not (Test-PrivacyRuleSpec $actual $step.rule)) { throw 'Firewall rule readback mismatch.' }
          $journal.rules = @($journal.rules | Where-Object { $_.name -ne $step.rule.name }) + @($actual)
        }
        'RemoveRule' {
          $current = & $Adapter.ReadRule $step.rule.name
          if (-not (Test-PrivacyEqual $current $step.rule)) { throw 'Firewall rule changed since preview; preserved.' }
          & $Adapter.RemoveRule $step.rule.name
          if ($null -ne (& $Adapter.ReadRule $step.rule.name)) { throw 'Firewall removal readback mismatch.' }
          $journal.rules = @($journal.rules | Where-Object { $_.name -ne $step.rule.name })
        }
      }
      & $Adapter.SaveState $journal
    }
    $final = $Plan.nextState
    $final.rules = @($final.rules | ForEach-Object {
      $actual = & $Adapter.ReadRule $_.name
      if ($actual -and (Test-PrivacyRuleSpec $actual $_) -and -not $_.fingerprint) { $actual } else { $_ }
    })
    & $Adapter.SaveState $final
    return (ConvertFrom-Json (ConvertTo-PrivacyJson $final))
  } catch {
    $journal.phase = 'Failed'; $journal.lastError = $_.Exception.Message
    & $Adapter.SaveState $journal
    throw
  }
}
Export-ModuleMember -Function *-Privacy*
