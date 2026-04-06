@echo off
setlocal

cd /d "%~dp0"

echo Clash Verge Steam Routing Kit
echo.
echo Every run checks GitHub for updates before installation.
echo Please make sure Clash Verge Rev has been opened at least once on this PC.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap-install.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="20" (
  echo GitHub update check timed out.
  echo You can run the local installer once, or exit now.
  choice /C LE /N /M "[L] Local once / [E] Exit: "
  if errorlevel 2 (
    exit /b 20
  )

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-steam-routing.ps1"
  set "EXITCODE=%ERRORLEVEL%"
  echo.
)

if not "%EXITCODE%"=="0" (
  echo Installation failed with exit code %EXITCODE%.
  echo If needed, try again after opening Clash Verge Rev once.
  pause
  exit /b %EXITCODE%
)

echo Installation completed successfully.
echo Restart Clash Verge Rev once, or switch subscriptions once.
pause
exit /b 0
