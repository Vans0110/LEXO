@echo off
setlocal
chcp 65001 >nul

cd /d "%~dp0"

set "PYTHON_CMD="
set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
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

if defined FLUTTER_CMD goto flutter_ready

where flutter.bat >nul 2>nul
if not errorlevel 1 set "FLUTTER_CMD=flutter"

:flutter_ready

if not defined PYTHON_CMD (
  echo [LEXO] Python not found in PATH.
  echo Install Python and try again.
  pause
  exit /b 1
)

if not defined FLUTTER_CMD (
  echo [LEXO] Flutter not found in PATH.
  echo Install Flutter SDK and add it to PATH.
  echo.
  echo Or edit this file and set FLUTTER_CMD manually, for example:
  echo set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
  pause
  exit /b 1
)

if not exist "app\.dart_tool" (
  echo [LEXO] First Flutter run. Executing flutter pub get...
  call "%FLUTTER_CMD%" pub get --directory app
  if errorlevel 1 (
    echo [LEXO] Error during flutter pub get.
    pause
    exit /b 1
  )
)

echo [LEXO] Starting Python engine...
if exist "%~dp0data\models\nllb-200-distilled-600m\ct2\model.bin" (
  set "LEXO_TRANSLATOR_MODE=nllb"
)
if exist "%~dp0.venv_kokoro\Scripts\python.exe" (
  set "LEXO_TTS_PROVIDER_MODE=kokoro"
)
start "LEXO Engine" cmd /k "cd /d %~dp0 && set LEXO_TRANSLATOR=%LEXO_TRANSLATOR_MODE% && set LEXO_TTS_PROVIDER=%LEXO_TTS_PROVIDER_MODE% && %PYTHON_CMD% -m engine.main"

echo [LEXO] Waiting before starting UI...
timeout /t 2 /nobreak >nul

echo [LEXO] Starting Flutter desktop app...
pushd app
call "%FLUTTER_CMD%" run -d windows
set "FLUTTER_EXIT=%ERRORLEVEL%"
popd
if not "%FLUTTER_EXIT%"=="0" (
  echo [LEXO] Flutter app exited with an error.
  pause
  exit /b 1
)

endlocal
