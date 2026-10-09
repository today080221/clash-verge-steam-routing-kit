Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\sync-clash-verge-steam-script.ps1""", 0, False
