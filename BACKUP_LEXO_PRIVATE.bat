@echo off
setlocal
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\PrivateBackup\Backup-LexoPrivate.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Backup stopped with code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
