# Real filesystem regression; no registry, firewall, task, or ProgramData writes.
# Uses the production Move/Replace commit path. Administrator ownership setup is
# separately verified during elevated installation, not simulated by this test.
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Windows.psm1') -Force
$persistenceRoot = Join-Path $root ('.test-tmp\persistence-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($persistenceRoot) | Out-Null
$target = Join-Path $persistenceRoot 'receipt.json'
$staged = Join-Path $persistenceRoot 'receipt.staged.json'
$preserved = Join-Path $persistenceRoot 'previous-failure.tmp'
$readHandle = $null; $lockedHandle = $null
$encoding = New-Object Text.UTF8Encoding($false)
try {
  [IO.File]::WriteAllText($preserved, 'preserve prior evidence', $encoding)
  [IO.File]::WriteAllText($staged, '{"status":"Running","success":false}', $encoding)
  Complete-PrivacyStagedFile $staged $target
  Assert (([IO.File]::ReadAllText($target) | ConvertFrom-Json).status -eq 'Running' -and -not (Test-Path -LiteralPath $staged)) 'real atomic writer creates an absent receipt by moving its complete staged file'

  # Give the destination a distinct explicit read ACE to prove Replace merges
  # its original ACL instead of silently replacing it with staging inheritance.
  $acl = Get-Acl -LiteralPath $target
  $readerSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($readerSid, 'ReadAndExecute', 'Allow')))
  Set-Acl -LiteralPath $target -AclObject $acl
  $securityBefore = (Get-Acl -LiteralPath $target).Sddl
  $oldBytes = [IO.File]::ReadAllText($target)
  $readHandle = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
  [IO.File]::WriteAllText($staged, '{"status":"Failed","success":false,"error":"fixture failure is durably reported"}', $encoding)
  Complete-PrivacyStagedFile $staged $target
  $receipt = [IO.File]::ReadAllText($target) | ConvertFrom-Json
  Assert ($receipt.status -eq 'Failed' -and $receipt.error -eq 'fixture failure is durably reported') 'real atomic replacement updates Running to a complete readable Failed receipt on this PowerShell runtime'
  Assert ((Get-Acl -LiteralPath $target).Sddl -ceq $securityBefore) 'replacement preserves destination owner and ACL without ignoring metadata errors'
  $oldReader = New-Object IO.StreamReader($readHandle)
  try { $oldReadback = $oldReader.ReadToEnd() } finally { $oldReader.Dispose(); $readHandle = $null }
  Assert ($oldReadback -ceq $oldBytes) 'reader holding the old file still sees complete old content, while new readers see complete replacement'
  Assert (-not (Test-Path -LiteralPath $staged)) 'successful replace consumes its staging file without leaving a backup path'

  [IO.File]::WriteAllText($staged, '{"status":"Completed","success":true}', $encoding)
  $failedReceiptBytes = [IO.File]::ReadAllText($target)
  $lockedHandle = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  Throws { Complete-PrivacyStagedFile $staged $target } 'atomic replace fails when an external reader disallows replacement'
  Assert (([IO.File]::ReadAllText($target) -ceq $failedReceiptBytes) -and (Test-Path -LiteralPath $staged)) 'failed replace preserves both the prior complete receipt and staged evidence'
  $lockedHandle.Dispose(); $lockedHandle = $null
  Complete-PrivacyStagedFile $staged $target
  Assert (([IO.File]::ReadAllText($target) | ConvertFrom-Json).success -eq $true) 'retry commits the retained staged file after the transient lock is released'
  Assert (([IO.File]::ReadAllText($preserved) -ceq 'preserve prior evidence') -and (Get-Acl -LiteralPath $target).Sddl -ceq $securityBefore) 'subsequent writes retain prior failure artifacts and destination ACL'
} finally {
  if ($readHandle) { $readHandle.Dispose() }
  if ($lockedHandle) { $lockedHandle.Dispose() }
  $resolved = [IO.Path]::GetFullPath($persistenceRoot)
  $allowed = [IO.Path]::GetFullPath((Join-Path $root '.test-tmp')) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe persistence test cleanup path.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
  Remove-Module ClaudePrivacy.Windows
}
