@echo off
setlocal

cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -File "%~dp0Server_manager.ps1" %*
set "exitCode=%ERRORLEVEL%"

echo.
echo Server Manager exited with code %exitCode%.
pause
exit /b %exitCode%
