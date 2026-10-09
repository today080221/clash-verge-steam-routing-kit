# Real GUI-host compilation and isolated child execution. No actual privacy runner.
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Maintenance.psm1') -Force
$fixture = Join-Path $root ('.test-tmp\quiet host ' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
try {
  $hostPath = Join-Path $fixture 'ClaudePrivacy.Host.exe'
  New-PrivacyHostExecutable (Join-Path $root 'scripts\ClaudePrivacy.Host.cs') $hostPath
  $bytes = [IO.File]::ReadAllBytes($hostPath)
  $pe = [BitConverter]::ToInt32($bytes, 0x3c)
  Assert ([BitConverter]::ToUInt16($bytes, ($pe + 24 + 68)) -eq 2) 'compiled scheduled host has the GUI subsystem and does not allocate a console'
  $nativeSource = Join-Path $fixture 'NativeProbe.cs'
  [IO.File]::WriteAllText($nativeSource, 'using System; using System.Runtime.InteropServices; public static class PrivacyConsoleProbe { [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); }', (New-Object Text.UTF8Encoding($false)))
  $framework = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'Microsoft.NET\Framework64\v4.0.30319'
  if (-not [Environment]::Is64BitOperatingSystem) { $framework = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'Microsoft.NET\Framework\v4.0.30319' }
  $compiled = Invoke-PrivacyHiddenProcess (Join-Path $framework 'csc.exe') @('/nologo','/noconfig','/target:library',('/out:' + (Join-Path $fixture 'NativeProbe.dll')), $nativeSource) $fixture
  if ($compiled.exitCode) { throw ($compiled.output + $compiled.error) }
  $runner = @'
param([string]$Action, [switch]$Scheduled)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'NativeProbe.dll')
$result = [pscustomobject]@{ action=$Action; scheduled=[bool]$Scheduled; consoleHandle=[PrivacyConsoleProbe]::GetConsoleWindow().ToInt64(); modulePath=$env:PSModulePath; pid=$PID }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'child.json'), ($result | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
exit 7
'@
  [IO.File]::WriteAllText((Join-Path $fixture 'claude-privacy.ps1'), $runner, (New-Object Text.UTF8Encoding($false)))
  # Start the already-verified GUI executable without hiding a console for it.
  # Only its own CreateNoWindow child creation can make the child's handle zero.
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = $hostPath; $start.Arguments = '--scheduled'; $start.UseShellExecute = $false
  $start.EnvironmentVariables['PSModulePath'] = 'C:\UntrustedInheritedModules'
  $process = [Diagnostics.Process]::Start($start)
  try {
    if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Fixture host timed out.' }
    $exitCode = $process.ExitCode
  } finally { $process.Dispose() }
  $child = Get-Content -LiteralPath (Join-Path $fixture 'child.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Assert ($child.consoleHandle -eq 0) 'real PowerShell child starts without a console, not merely a hidden window'
  Assert ($child.action -eq 'refresh' -and $child.scheduled -and $exitCode -eq 7) 'GUI host invokes only scheduled refresh and propagates the real child exit code'
  # PowerShell adds its own default paths at startup. The real privacy runner
  # sanitizes again before imports; the host must discard inherited overrides.
  Assert ($child.modulePath -notmatch 'UntrustedInheritedModules' -and $child.modulePath.Contains((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\Modules'))) 'GUI host discards inherited module-path overrides before PowerShell startup'
  $before = Get-PrivacyFileHash (Join-Path $fixture 'child.json')
  $invalid = Invoke-PrivacyHiddenProcess $hostPath @('--scheduled','unexpected-command') $fixture
  Assert ($invalid.exitCode -eq 64 -and (Get-PrivacyFileHash (Join-Path $fixture 'child.json')) -ceq $before) 'GUI host rejects extra arguments before executing any child'
  Throws { New-PrivacyHostExecutable (Join-Path $root 'scripts\ClaudePrivacy.Host.cs') $hostPath } 'host build never overwrites an existing executable'
  $argumentRunner = Join-Path $fixture 'arguments.ps1'
  [IO.File]::WriteAllText($argumentRunner, 'param([string]$Value) [Console]::Out.Write($Value)', (New-Object Text.UTF8Encoding($false)))
  $powerShell = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
  foreach ($value in @('space value','quote"value','C:\Trailing Slash\','')) {
    $result = Invoke-PrivacyHiddenProcess $powerShell @('-NoProfile','-NonInteractive','-File',$argumentRunner,'-Value',$value) $fixture
    Assert ($result.exitCode -eq 0 -and $result.output -ceq $value) ('hidden child preserves a Windows argument of length ' + $value.Length)
  }
} finally {
  $resolved = [IO.Path]::GetFullPath($fixture)
  $allowed = [IO.Path]::GetFullPath((Join-Path $root '.test-tmp')) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup target.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
Remove-Module ClaudePrivacy.Maintenance,ClaudePrivacy.Windows -ErrorAction SilentlyContinue
Import-Module (Join-Path $root 'scripts\ClaudePrivacy.Core.psm1') -Force
