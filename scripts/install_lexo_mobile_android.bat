@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "ROOT_DIR=%~dp0.."
cd /d "%ROOT_DIR%"

set "ANDROID_STUDIO_ID=Google.AndroidStudio"
set "ANDROID_STUDIO_EXE=%ProgramFiles%\Android\Android Studio\bin\studio64.exe"
set "DEFAULT_JAVA_HOME=%ProgramFiles%\Android\Android Studio\jbr"
set "DEFAULT_SDK=%LOCALAPPDATA%\Android\Sdk"
set "SDKMANAGER_CMD="
set "AVDMANAGER_CMD="
set "EMULATOR_CMD="
set "ADB_CMD="
set "ANDROID_SDK_ROOT="
set "DEFAULT_AVD_NAME=LEXO_Pixel_6"
set "DEFAULT_SYSTEM_IMAGE=system-images;android-35;google_apis;x86_64"
set "DEFAULT_DEVICE=pixel_6"

echo [LEXO] Mobile Android install for Windows
echo.

where winget >nul 2>nul
if errorlevel 1 (
  echo [LEXO] winget not found.
  echo [LEXO] Install App Installer from Microsoft Store or install Android Studio manually.
  pause
  exit /b 1
)

call :ensure_android_studio
if errorlevel 1 exit /b 1

call :resolve_java
if errorlevel 1 exit /b 1

call :find_android_sdk
if errorlevel 1 exit /b 1

echo.
echo [LEXO] Android SDK found: %ANDROID_SDK_ROOT%
echo [LEXO] Installing Android SDK packages...
call "%SDKMANAGER_CMD%" --install "platform-tools" "platforms;android-35" "emulator" "cmdline-tools;latest" "%DEFAULT_SYSTEM_IMAGE%"
if errorlevel 1 (
  echo [LEXO] sdkmanager install failed.
  echo [LEXO] Open Android Studio once, finish SDK setup, then run this script again.
  pause
  exit /b 1
)

echo.
echo [LEXO] Checking AVD "%DEFAULT_AVD_NAME%"...
set "AVD_EXISTS="
for /f "usebackq delims=" %%A in (`"%EMULATOR_CMD%" -list-avds 2^>nul`) do (
  if /I "%%A"=="%DEFAULT_AVD_NAME%" set "AVD_EXISTS=1"
)

if defined AVD_EXISTS (
  echo [LEXO] AVD already exists.
) else (
  echo [LEXO] Creating AVD "%DEFAULT_AVD_NAME%"...
  call "%AVDMANAGER_CMD%" create avd -n "%DEFAULT_AVD_NAME%" -k "%DEFAULT_SYSTEM_IMAGE%" -d "%DEFAULT_DEVICE%" --force
  if errorlevel 1 (
    echo [LEXO] AVD creation failed.
    echo [LEXO] Open Android Studio -> Device Manager and finish emulator setup manually if needed.
    pause
    exit /b 1
  )
)

echo.
echo [LEXO] External Android install is ready.
echo [LEXO] Now running project setup for LEXO...
call "%ROOT_DIR%\scripts\setup_lexo_mobile_android.bat"
exit /b %ERRORLEVEL%

:ensure_android_studio
if exist "%ANDROID_STUDIO_EXE%" (
  echo [LEXO] Android Studio already installed.
  exit /b 0
)

echo [LEXO] Installing Android Studio via winget...
powershell -NoProfile -Command "winget install -e --id %ANDROID_STUDIO_ID% --accept-package-agreements --accept-source-agreements"
if errorlevel 1 (
  echo [LEXO] Android Studio install failed.
  pause
  exit /b 1
)

if exist "%ANDROID_STUDIO_EXE%" exit /b 0

echo [LEXO] Android Studio was installed, but default path was not found yet.
echo [LEXO] Open Android Studio once and finish first-run setup.
pause
exit /b 1

:resolve_java
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" goto java_ready
if exist "%DEFAULT_JAVA_HOME%\bin\java.exe" set "JAVA_HOME=%DEFAULT_JAVA_HOME%"

:java_ready
if not defined JAVA_HOME (
  echo [LEXO] Java not found in Android Studio.
  echo [LEXO] Run Android Studio once or run fix_lexo_mobile_env.bat later.
  pause
  exit /b 1
)
set "PATH=%JAVA_HOME%\bin;%PATH%"
where java >nul 2>nul
if errorlevel 1 (
  echo [LEXO] java command not available.
  pause
  exit /b 1
)
exit /b 0

:find_android_sdk
if exist "%DEFAULT_SDK%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%DEFAULT_SDK%"

if not defined ANDROID_SDK_ROOT (
  echo [LEXO] Android SDK not found yet.
  echo [LEXO] Opening Android Studio. Complete first-run SDK setup, then rerun this script.
  if exist "%ANDROID_STUDIO_EXE%" start "" "%ANDROID_STUDIO_EXE%"
  pause
  exit /b 1
)

set "ADB_CMD=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_CMD=%ANDROID_SDK_ROOT%\emulator\emulator.exe"

if exist "%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat" (
  set "SDKMANAGER_CMD=%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"
  set "AVDMANAGER_CMD=%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\avdmanager.bat"
)

if not defined SDKMANAGER_CMD (
  for /d %%D in ("%ANDROID_SDK_ROOT%\cmdline-tools\*") do (
    if exist "%%~fD\bin\sdkmanager.bat" set "SDKMANAGER_CMD=%%~fD\bin\sdkmanager.bat"
    if exist "%%~fD\bin\avdmanager.bat" set "AVDMANAGER_CMD=%%~fD\bin\avdmanager.bat"
  )
)

if not exist "%ADB_CMD%" (
  echo [LEXO] adb.exe not found inside Android SDK.
  pause
  exit /b 1
)
if not exist "%EMULATOR_CMD%" (
  echo [LEXO] emulator.exe not found inside Android SDK.
  pause
  exit /b 1
)
if not defined SDKMANAGER_CMD (
  echo [LEXO] sdkmanager.bat not found.
  echo [LEXO] In Android Studio install Android SDK Command-line Tools.
  pause
  exit /b 1
)
if not defined AVDMANAGER_CMD (
  echo [LEXO] avdmanager.bat not found.
  echo [LEXO] In Android Studio install Android SDK Command-line Tools.
  pause
  exit /b 1
)
exit /b 0
