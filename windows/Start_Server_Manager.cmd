@echo off
setlocal

cd /d "%~dp0"

rem Strip the Zone.Identifier so RemoteSigned policy doesn't block the unsigned script.
powershell.exe -NoLogo -NoProfile -Command "Unblock-File -LiteralPath '%~dp0Server_manager.ps1' -ErrorAction SilentlyContinue" >nul 2>&1

powershell.exe -NoLogo -NoProfile -File "%~dp0Server_manager.ps1" %*
set "exitCode=%ERRORLEVEL%"

echo.
echo Server Manager exited with code %exitCode%.
pause
exit /b %exitCode%
