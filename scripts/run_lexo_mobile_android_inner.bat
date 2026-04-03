@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "ROOT_DIR=%~dp0.."
cd /d "%ROOT_DIR%"

set "PYTHON_CMD="
set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "PROJECT_VENV=%ROOT_DIR%\.venv\Scripts\python.exe"
set "APP_DIR=%ROOT_DIR%\app"
set "DEFAULT_SDK=%LOCALAPPDATA%\Android\Sdk"
set "DEFAULT_JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_SDK_ROOT="
set "ADB_CMD="
set "EMULATOR_CMD="
set "TARGET_DEVICE="
set "AVD_NAME=LEXO_Pixel_6"
set "LEXO_TRANSLATOR_MODE=mock"
set "LEXO_TTS_PROVIDER_MODE=mock"

if exist "%PROJECT_VENV%" (
  set "PYTHON_CMD=%PROJECT_VENV%"
) else (
  where python >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_CMD=python"
  ) else (
    where py >nul 2>nul
    if not errorlevel 1 (
      set "PYTHON_CMD=py -3"
    )
  )
)

if not defined PYTHON_CMD (
  echo [LEXO] Python not found in PATH.
  pause
  exit /b 1
)

if not exist "%FLUTTER_CMD%" (
  where flutter.bat >nul 2>nul
  if not errorlevel 1 (
    set "FLUTTER_CMD=flutter"
  ) else (
    where flutter >nul 2>nul
    if not errorlevel 1 set "FLUTTER_CMD=flutter"
  )
)

if not defined FLUTTER_CMD (
  echo [LEXO] Flutter not found.
  pause
  exit /b 1
)

if not defined JAVA_HOME (
  if exist "%DEFAULT_JAVA_HOME%\bin\java.exe" set "JAVA_HOME=%DEFAULT_JAVA_HOME%"
)

if not defined JAVA_HOME (
  echo [LEXO] Java not found.
  echo [LEXO] Run fix_lexo_mobile_env.bat first.
  pause
  exit /b 1
)

set "PATH=%JAVA_HOME%\bin;%PATH%"
where java >nul 2>nul
if errorlevel 1 (
  echo [LEXO] java command not available.
  echo [LEXO] Run fix_lexo_mobile_env.bat first.
  pause
  exit /b 1
)

if defined ANDROID_HOME if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if not defined ANDROID_SDK_ROOT if exist "%DEFAULT_SDK%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%DEFAULT_SDK%"
if not defined ANDROID_SDK_ROOT if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"

if not defined ANDROID_SDK_ROOT (
  echo [LEXO] Android SDK not found.
  echo [LEXO] Run setup_lexo_mobile_android.bat first.
  pause
  exit /b 1
)

set "ADB_CMD=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_CMD=%ANDROID_SDK_ROOT%\emulator\emulator.exe"

if not exist "%ADB_CMD%" (
  echo [LEXO] adb.exe not found.
  pause
  exit /b 1
)
if not exist "%EMULATOR_CMD%" (
  echo [LEXO] emulator.exe not found.
  pause
  exit /b 1
)

if not exist "%APP_DIR%\android" (
  echo [LEXO] app\android is missing.
  echo [LEXO] Run setup_lexo_mobile_android.bat first.
  pause
  exit /b 1
)

if not exist "%APP_DIR%\.dart_tool" (
  echo [LEXO] First Flutter run. Executing flutter pub get...
  call "%FLUTTER_CMD%" pub get --directory "%APP_DIR%"
  if errorlevel 1 (
    echo [LEXO] Error during flutter pub get.
    pause
    exit /b 1
  )
)

echo [LEXO] Checking emulator list...
set "AVD_EXISTS="
for /f "usebackq delims=" %%A in (`"%EMULATOR_CMD%" -list-avds 2^>nul`) do (
  if /I "%%A"=="%AVD_NAME%" set "AVD_EXISTS=1"
)
if not defined AVD_EXISTS (
  echo [LEXO] AVD "%AVD_NAME%" not found.
  echo [LEXO] Run setup_lexo_mobile_android.bat first.
  pause
  exit /b 1
)

set "TARGET_DEVICE="
for /f "skip=1 tokens=1,2" %%D in ('"%ADB_CMD%" devices') do (
  echo %%D| findstr /B /C:"emulator-" >nul
  if not errorlevel 1 if /I "%%E"=="device" set "TARGET_DEVICE=%%D"
)

if not defined TARGET_DEVICE (
  echo [LEXO] Starting Android emulator "%AVD_NAME%"...
  start "LEXO Android Emulator" "%EMULATOR_CMD%" -avd "%AVD_NAME%"
)

if not defined TARGET_DEVICE (
  for /l %%I in (1,1,90) do (
    set "TARGET_DEVICE="
    for /f "skip=1 tokens=1,2" %%D in ('"%ADB_CMD%" devices') do (
      echo %%D| findstr /B /C:"emulator-" >nul
      if not errorlevel 1 if /I "%%E"=="device" set "TARGET_DEVICE=%%D"
    )
    if defined TARGET_DEVICE goto wait_for_boot
    timeout /t 2 /nobreak >nul
  )
)

if not defined TARGET_DEVICE (
  echo [LEXO] Emulator did not become ready in time.
  pause
  exit /b 1
)

:wait_for_boot
echo [LEXO] Waiting for Android boot completion...
for /l %%I in (1,1,120) do (
  for /f %%B in ('"%ADB_CMD%" -s %TARGET_DEVICE% shell getprop sys.boot_completed 2^>nul') do (
    if "%%B"=="1" goto boot_done
  )
  timeout /t 2 /nobreak >nul
)

echo [LEXO] Emulator boot did not complete in time.
pause
exit /b 1

:boot_done
echo [LEXO] Emulator boot complete.
echo [LEXO] Using Android device: %TARGET_DEVICE%

echo [LEXO] Starting Python engine...
if exist "%ROOT_DIR%\data\models\nllb-200-distilled-600m\ct2\model.bin" (
  set "LEXO_TRANSLATOR_MODE=nllb"
)
if exist "%ROOT_DIR%\.venv_kokoro\Scripts\python.exe" (
  set "LEXO_TTS_PROVIDER_MODE=kokoro"
)
start "LEXO Engine" cmd /k "cd /d %ROOT_DIR% && set LEXO_HOST=0.0.0.0 && set LEXO_PORT=8765 && set LEXO_TRANSLATOR=%LEXO_TRANSLATOR_MODE% && set LEXO_TTS_PROVIDER=%LEXO_TTS_PROVIDER_MODE% && %PYTHON_CMD% -m engine.main"

echo [LEXO] Waiting before starting mobile UI...
timeout /t 3 /nobreak >nul

echo [LEXO] Starting Flutter Android app...
pushd "%APP_DIR%"
call "%FLUTTER_CMD%" run -d "%TARGET_DEVICE%"
set "FLUTTER_EXIT=%ERRORLEVEL%"
popd
if not "%FLUTTER_EXIT%"=="0" (
  echo [LEXO] Flutter Android app exited with an error.
  pause
  exit /b 1
)

endlocal
exit /b 0
