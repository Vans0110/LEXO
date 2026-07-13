@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

set "WORKSPACE_ROOT=%~dp0..\.."
set "BACKEND_LOG_DIR=%WORKSPACE_ROOT%\Studio\Runtime\backend_logs"
if not exist "%BACKEND_LOG_DIR%" mkdir "%BACKEND_LOG_DIR%" >nul 2>nul
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "LEXO_LOG_TS=%%I"
set "LEXO_LOG_PATH=%BACKEND_LOG_DIR%\run_backend_%LEXO_LOG_TS%.log"

set "PYTHON_CMD="
set "BACKEND_VENV=%~dp0.venv_backend\Scripts\python.exe"
set "LEXO_TRANSLATOR_MODE=mock"
set "LEXO_TTS_PROVIDER_MODE=mock"

if exist "%BACKEND_VENV%" (
  set "PYTHON_CMD=%BACKEND_VENV%"
  goto python_ready
)

where python >nul 2>nul
if not errorlevel 1 set "PYTHON_CMD=python"

if not defined PYTHON_CMD (
  where py >nul 2>nul
  if not errorlevel 1 set "PYTHON_CMD=py -3"
)

:python_ready

if not defined PYTHON_CMD (
  echo [LEXO] Python not found in PATH.
  pause
  exit /b 1
)

if exist "%~dp0data\models\nllb-200-3.3b\ct2\model.bin" (
  set "LEXO_TRANSLATOR_MODE=nllb33"
)
if exist "%~dp0.venv_kokoro\Scripts\python.exe" (
  set "LEXO_TTS_PROVIDER_MODE=kokoro"
)

echo [LEXO] Starting LAN engine on 0.0.0.0:8765
echo [LEXO] Open Windows Firewall for port 8765 if needed.
echo [LEXO] Use your Windows IPv4 in iPhone Host URL, for example:
echo [LEXO]   http://192.168.1.50:8765
echo [LEXO] Log: %LEXO_LOG_PATH%
echo.

set "LEXO_HOST=0.0.0.0"
set "LEXO_PORT=8765"
set "LEXO_TRANSLATOR=%LEXO_TRANSLATOR_MODE%"
set "LEXO_TTS_PROVIDER=%LEXO_TTS_PROVIDER_MODE%"

(
  echo [LEXO] Started at %date% %time%
  echo [LEXO] Root: %~dp0
  echo [LEXO] Python: %PYTHON_CMD%
  echo [LEXO] Host: %LEXO_HOST%
  echo [LEXO] Port: %LEXO_PORT%
  echo [LEXO] Translator: %LEXO_TRANSLATOR%
  echo [LEXO] TTS: %LEXO_TTS_PROVIDER%
  echo.
) > "%LEXO_LOG_PATH%"

call %PYTHON_CMD% -m engine.main >> "%LEXO_LOG_PATH%" 2>&1
set "LEXO_EXIT_CODE=%ERRORLEVEL%"
if not "%LEXO_EXIT_CODE%"=="0" (
  echo.
  echo [LEXO] Engine failed with exit code %LEXO_EXIT_CODE%.
  echo [LEXO] See log: %LEXO_LOG_PATH%
  echo.
  type "%LEXO_LOG_PATH%"
  pause
  exit /b %LEXO_EXIT_CODE%
)
