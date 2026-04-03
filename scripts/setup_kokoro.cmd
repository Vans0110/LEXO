@echo off
setlocal
chcp 65001 >nul

cd /d "%~dp0\.."

set "PY_CMD="
where py >nul 2>nul
if not errorlevel 1 (
  py -3.12 -V >nul 2>nul
  if not errorlevel 1 set "PY_CMD=py -3.12"
)

if not defined PY_CMD (
  where py >nul 2>nul
  if not errorlevel 1 (
    py -3.11 -V >nul 2>nul
    if not errorlevel 1 set "PY_CMD=py -3.11"
  )
)

if not defined PY_CMD (
  where py >nul 2>nul
  if not errorlevel 1 (
    py -3.10 -V >nul 2>nul
    if not errorlevel 1 set "PY_CMD=py -3.10"
  )
)

if not defined PY_CMD (
  echo [LEXO] Supported Python runtime for Kokoro not found.
  echo [LEXO] Kokoro requires Python 3.10, 3.11 or 3.12.
  echo [LEXO] Install Python 3.11 or 3.12, then rerun this script.
  py -0p 2>nul
  exit /b 1
)

set "KOKORO_VENV=%CD%\.venv_kokoro"

echo [LEXO] Using Python command: %PY_CMD%
%PY_CMD% -V
if errorlevel 1 exit /b 1

if not exist "%KOKORO_VENV%\Scripts\python.exe" (
  echo [LEXO] Creating Kokoro venv in .venv_kokoro ...
  %PY_CMD% -m venv "%KOKORO_VENV%"
  if errorlevel 1 exit /b 1
)

call "%KOKORO_VENV%\Scripts\activate.bat"
if errorlevel 1 exit /b 1

echo [LEXO] Upgrading pip...
python -m pip install --upgrade pip
if errorlevel 1 exit /b 1

echo [LEXO] Installing Kokoro packages...
python -m pip install -r engine\requirements-kokoro.txt
if errorlevel 1 exit /b 1

where espeak-ng.exe >nul 2>nul
if errorlevel 1 (
  echo [LEXO] Warning: espeak-ng.exe was not found in PATH.
  echo [LEXO] Official Kokoro docs recommend installing eSpeak-NG on Windows.
  echo [LEXO] If English fallback words sound wrong, install eSpeak-NG and rerun if needed.
)

echo [LEXO] Kokoro runtime is ready.
echo [LEXO] To use Kokoro in LEXO:
echo set LEXO_TTS_PROVIDER=kokoro
echo %KOKORO_VENV%\Scripts\python.exe %CD%\engine\tts\kokoro_runner.py --voice af_heart --output %CD%\data\tts\kokoro_test.wav --text Hello

endlocal
