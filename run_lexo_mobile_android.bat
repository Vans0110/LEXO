@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

if not exist "%~dp0logs" mkdir "%~dp0logs"
set "LEXO_RUN_LOG_FILE=%~dp0logs\run_lexo_mobile_android.log"

echo [LEXO] Writing log to:
echo [LEXO]   %LEXO_RUN_LOG_FILE%
call "%~dp0scripts\run_lexo_mobile_android_inner.bat" > "%LEXO_RUN_LOG_FILE%" 2>&1
set "LEXO_RUN_EXIT=%ERRORLEVEL%"
echo [LEXO] Exit code: %LEXO_RUN_EXIT%

if not "%LEXO_RUN_EXIT%"=="0" (
  echo [LEXO] Launch failed. Open the log file and send it to me:
  echo [LEXO]   %LEXO_RUN_LOG_FILE%
  pause
)

exit /b %LEXO_RUN_EXIT%
