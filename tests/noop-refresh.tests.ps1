# Fresh planning still validates everything, but an identical result does not
# rewrite the journal or re-read the entire rule group for each owned rule.
$baseline = Snapshot (Policy @((Entry 'https://[*.]claude.ai'), (Entry 'https://[*.]claude.com'), (Entry 'https://[*.]anthropic.com')))
$adapter = Mock-Adapter $baseline
$applied = Invoke-PrivacyPlan (New-PrivacyPlan $baseline (New-PrivacyState $baseline.sid) 'apply') (New-PrivacyState $baseline.sid) $adapter
$noop = New-PrivacyPlan $script:mock $applied 'refresh'
$forbidden = @{
  SaveState = { throw 'An unchanged refresh must not rewrite state.' }
  ReadRule = { throw 'An unchanged refresh must not redundantly read rules.' }
  ReadPolicy = { throw 'An unchanged refresh must not redundantly read policy.' }
}
$unchanged = Invoke-PrivacyPlan $noop $applied $forbidden
Assert ($noop.steps.Count -eq 0 -and (Test-PrivacyEqual $unchanged $applied)) 'unchanged fresh plan returns without extra rule reads or state writes'
$unchanged.rules[0].fingerprint = 'caller-modified'
Assert ($applied.rules[0].fingerprint -ne 'caller-modified') 'no-op result is an independent copy of the ownership state'
$drift = Copy-Value $script:mock
$drift.rules[0].fingerprint = 'externally-changed'
$driftPlan = New-PrivacyPlan $drift $applied 'refresh'
Throws { Invoke-PrivacyPlan $driftPlan $applied $forbidden } 'no-op optimization does not bypass freshly detected ownership drift'
$badDiscovery = Copy-Value $script:mock
$badDiscovery.discoveryErrors = @('Unverified candidate')
Throws { New-PrivacyPlan $badDiscovery $applied 'refresh' } 'unchanged paths still require complete fresh executable discovery'

Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Windows.psm1') -Force
$module = Get-Module ClaudePrivacy.Windows
$result = & $module {
  $script:queries = @(); $script:deny = $false; $script:empty = $false
  function script:Get-NetFirewallRule {
    param($PolicyStore,$Name,$ErrorAction)
    $script:queries += [pscustomobject]@{ store=$PolicyStore; name=$Name; errorAction=$ErrorAction }
    if ($script:deny) { throw 'Access denied fixture' }
    if (-not $script:empty) { [pscustomobject]@{ Name='CVSRK-ClaudeUDP-unowned-collision' } }
  }
  function script:ConvertFrom-PrivacyFirewallRule($Rule) { [pscustomobject]@{ name=$Rule.Name } }
  $persistent = @(Get-PrivacyRules)
  $active = @(Get-PrivacyRules -PolicyStore ActiveStore)
  $script:empty = $true
  $empty = @(Get-PrivacyRules)
  $script:deny = $true; $denied = $false
  try { Get-PrivacyRules | Out-Null } catch { $denied = $true }
  [pscustomobject]@{ queries=$script:queries; persistent=$persistent; active=$active; emptyCount=$empty.Count; denied=$denied }
}
Assert (@($result.queries | Where-Object { $_.name -ne 'CVSRK-ClaudeUDP-*' -or $_.errorAction -ne 'Stop' }).Count -eq 0) 'firewall query is provider-scoped to every tool-prefix rule and still fails on access errors'
Assert ($result.queries[0].store -eq 'PersistentStore' -and $result.queries[1].store -eq 'ActiveStore') 'optimized queries retain both persistent and effective-policy stores'
Assert ($result.persistent.Count -eq 1 -and $result.active.Count -eq 1 -and $result.persistent[0].name -eq 'CVSRK-ClaudeUDP-unowned-collision') 'prefix query includes unowned collisions rather than querying only known owned names'
Assert ($result.emptyCount -eq 0 -and $result.denied) 'empty prefix results are supported without masking firewall read failures'
Remove-Module ClaudePrivacy.Windows
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force
