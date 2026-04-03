@echo off
setlocal
chcp 65001 >nul

cd /d "%~dp0"

set "PYTHON_CMD="
set "PROJECT_VENV=%~dp0.venv\Scripts\python.exe"
set "LEXO_TRANSLATOR_MODE=mock"
set "LEXO_TTS_PROVIDER_MODE=mock"

if exist "%PROJECT_VENV%" (
  set "PYTHON_CMD=%PROJECT_VENV%"
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

if exist "%~dp0data\models\nllb-200-distilled-600m\ct2\model.bin" (
  set "LEXO_TRANSLATOR_MODE=nllb"
)
if exist "%~dp0.venv_kokoro\Scripts\python.exe" (
  set "LEXO_TTS_PROVIDER_MODE=kokoro"
)

echo [LEXO] Starting LAN engine on 0.0.0.0:8765
echo [LEXO] Open Windows Firewall for port 8765 if needed.
echo [LEXO] Use your Windows IPv4 in iPhone Host URL, for example:
echo [LEXO]   http://192.168.1.50:8765
echo.

set "LEXO_HOST=0.0.0.0"
set "LEXO_PORT=8765"
set "LEXO_TRANSLATOR=%LEXO_TRANSLATOR_MODE%"
set "LEXO_TTS_PROVIDER=%LEXO_TTS_PROVIDER_MODE%"

%PYTHON_CMD% -m engine.main
