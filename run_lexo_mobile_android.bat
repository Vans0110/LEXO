@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

if not exist "%~dp0logs" mkdir "%~dp0logs"
set "LEXO_RUN_TS="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd_HHmmss'"`) do set "LEXO_RUN_TS=%%I"
if not defined LEXO_RUN_TS set "LEXO_RUN_TS=latest"
set "LEXO_RUN_LOG_FILE=%~dp0logs\run_lexo_mobile_android_%LEXO_RUN_TS%.log"

echo [LEXO] Writing log to:
echo [LEXO]   %LEXO_RUN_LOG_FILE%
call "%~dp0scripts\run_lexo_mobile_android_inner.bat" > "%LEXO_RUN_LOG_FILE%" 2>&1
set "LEXO_RUN_EXIT=%ERRORLEVEL%"
echo [LEXO] Exit code: %LEXO_RUN_EXIT%

if not "%LEXO_RUN_EXIT%"=="0" (
  echo [LEXO] Launch failed. Open the log file and send it to me:
  echo [LEXO]   %LEXO_RUN_LOG_FILE%
)

echo [LEXO] Press any key to close this window.
pause >nul

exit /b %LEXO_RUN_EXIT%
