@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure_virgil_release_signing.ps1"
if errorlevel 1 (
  echo.
  echo [VIRGIL] Release signing configuration failed.
  pause
  exit /b 1
)
echo.
echo [VIRGIL] Configuration complete.
pause
