// Compiled locally as a Windows GUI-subsystem program. Never allocates a console.
// The task may invoke only the adjacent reviewed runner, with fixed arguments.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal static class ClaudePrivacyHost
{
    [DllImport("kernel32.dll")]
    private static extern uint SetErrorMode(uint mode);

    private static int Main(string[] args)
    {
        // Prevent OS error dialogs in this unattended process and its children.
        SetErrorMode(0x0001 | 0x0002 | 0x8000);
        try
        {
            if (args.Length != 1 || args[0] != "--scheduled") return 64;
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string runner = Path.Combine(root, "claude-privacy.ps1");
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(runner) || !File.Exists(powershell)) return 2;
            var start = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + runner + "\" -Action refresh -Scheduled",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            start.EnvironmentVariables["PSModulePath"] = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\Modules");
            using (var child = new Process { StartInfo = start })
            {
                if (!child.Start()) return 1;
                child.StandardInput.Close();
                var output = child.StandardOutput.ReadToEndAsync();
                var error = child.StandardError.ReadToEndAsync();
                // Finish before the scheduler's one-minute bound. No orphaned worker.
                if (!child.WaitForExit(55000))
                {
                    child.Kill();
                    child.WaitForExit();
                    return 124;
                }
                output.GetAwaiter().GetResult();
                error.GetAwaiter().GetResult();
                return child.ExitCode;
            }
        }
        catch { return 1; }
    }
}
