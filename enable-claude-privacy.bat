@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0enable-claude-privacy.ps1" %*
exit /b %ERRORLEVEL%
