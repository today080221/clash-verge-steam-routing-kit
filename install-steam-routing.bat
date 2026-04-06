@echo off
setlocal

cd /d "%~dp0"

echo Clash Verge Steam Routing Kit
echo.
echo This will install the shared Steam routing files for Clash Verge Rev.
echo Make sure Clash Verge Rev has been opened at least once on this PC.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-steam-routing.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
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
