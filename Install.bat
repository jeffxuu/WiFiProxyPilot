@echo off
setlocal DisableDelayedExpansion
set "WIFI_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "WIFI_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%WIFI_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Control.ps1" -Action Install %*
set "WIFI_RESULT=%ERRORLEVEL%"
if not "%WIFI_NO_PAUSE%"=="1" pause
exit /b %WIFI_RESULT%
