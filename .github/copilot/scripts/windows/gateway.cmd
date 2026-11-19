@echo off
rem Launcher for gateway.ps1: the one command Copilot agents may run on Windows (allowed by exact path in the crew runner).
rem Starts its own PowerShell with -ExecutionPolicy Bypass, so the machine's execution policy cannot block the script.
setlocal
set "PSEXE=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PSEXE=powershell.exe"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0gateway.ps1" %*
exit /b %ERRORLEVEL%
