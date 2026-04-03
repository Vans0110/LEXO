@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "ROOT_DIR=%~dp0.."
cd /d "%ROOT_DIR%"

set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "APP_DIR=%ROOT_DIR%\app"
set "DEFAULT_SDK=%LOCALAPPDATA%\Android\Sdk"
set "DEFAULT_JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_SDK_ROOT="
set "SDKMANAGER_CMD="
set "AVDMANAGER_CMD="
set "ADB_CMD="
set "EMULATOR_CMD="
set "DEFAULT_AVD_NAME=LEXO_Pixel_6"
set "DEFAULT_SYSTEM_IMAGE=system-images;android-35;google_apis;x86_64"
set "DEFAULT_DEVICE=pixel_6"

call :resolve_flutter
if errorlevel 1 exit /b 1

call :resolve_java
if errorlevel 1 exit /b 1

call :resolve_android_tools
if errorlevel 1 exit /b 1

echo [LEXO] LEXO project Android setup
echo [LEXO] Flutter found: %FLUTTER_CMD%
echo [LEXO] Android SDK: %ANDROID_SDK_ROOT%
echo.

echo [LEXO] Enabling Android support in Flutter...
call "%FLUTTER_CMD%" config --enable-android
if errorlevel 1 (
  echo [LEXO] flutter config --enable-android failed.
  pause
  exit /b 1
)

if not exist "%APP_DIR%\.dart_tool" (
  echo [LEXO] Running flutter pub get...
  call "%FLUTTER_CMD%" pub get --directory "%APP_DIR%"
  if errorlevel 1 (
    echo [LEXO] flutter pub get failed.
    pause
    exit /b 1
  )
)

if not exist "%APP_DIR%\android" (
  echo [LEXO] Android platform is missing in app\. Creating it now...
  pushd "%APP_DIR%"
  call "%FLUTTER_CMD%" create --platforms=android .
  set "CREATE_EXIT=!ERRORLEVEL!"
  popd
  if not "%CREATE_EXIT%"=="0" if not exist "%APP_DIR%\android" (
    echo [LEXO] flutter create --platforms=android . failed.
    pause
    exit /b 1
  )
) else (
  echo [LEXO] app\android already exists.
)

echo.
echo [LEXO] Running flutter doctor...
call "%FLUTTER_CMD%" doctor

echo.
echo [LEXO] Installing required Android packages if available...
call "%SDKMANAGER_CMD%" --install "platform-tools" "platforms;android-35" "emulator" "%DEFAULT_SYSTEM_IMAGE%"
if errorlevel 1 (
  echo [LEXO] sdkmanager package install failed.
  echo [LEXO] Continue after Android Studio finishes SDK setup manually.
)

echo.
echo [LEXO] Checking AVD list...
set "AVD_EXISTS="
for /f "usebackq delims=" %%A in (`"%EMULATOR_CMD%" -list-avds 2^>nul`) do (
  if /I "%%A"=="%DEFAULT_AVD_NAME%" set "AVD_EXISTS=1"
)

if defined AVD_EXISTS (
  echo [LEXO] AVD "%DEFAULT_AVD_NAME%" already exists.
) else (
  echo [LEXO] Creating AVD "%DEFAULT_AVD_NAME%"...
  call "%AVDMANAGER_CMD%" create avd -n "%DEFAULT_AVD_NAME%" -k "%DEFAULT_SYSTEM_IMAGE%" -d "%DEFAULT_DEVICE%" --force
  if errorlevel 1 (
    echo [LEXO] AVD creation failed.
    echo [LEXO] Open Android Studio, finish SDK setup, then run this script again.
    pause
    exit /b 1
  )
)

echo.
echo [LEXO] Mobile Android setup complete.
echo [LEXO] Next step:
echo [LEXO]   run_lexo_mobile_android.bat
pause
exit /b 0

:resolve_flutter
if exist "%FLUTTER_CMD%" exit /b 0
where flutter.bat >nul 2>nul
if not errorlevel 1 (
  set "FLUTTER_CMD=flutter"
  exit /b 0
)
where flutter >nul 2>nul
if not errorlevel 1 (
  set "FLUTTER_CMD=flutter"
  exit /b 0
)
echo [LEXO] Flutter not found.
echo [LEXO] Install Flutter SDK and set FLUTTER_CMD in this file if needed.
pause
exit /b 1

:resolve_java
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" goto java_ready
if exist "%DEFAULT_JAVA_HOME%\bin\java.exe" set "JAVA_HOME=%DEFAULT_JAVA_HOME%"

:java_ready
if not defined JAVA_HOME (
  echo [LEXO] Java not found.
  echo [LEXO] Run fix_lexo_mobile_env.bat first or install Android Studio JBR.
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
exit /b 0

:resolve_android_tools
if defined ANDROID_HOME if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if not defined ANDROID_SDK_ROOT if exist "%DEFAULT_SDK%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%DEFAULT_SDK%"
if not defined ANDROID_SDK_ROOT if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"

:sdk_ready
if not defined ANDROID_SDK_ROOT (
  echo [LEXO] Android SDK not found.
  echo [LEXO] Run install_lexo_mobile_android.bat first
  echo [LEXO] or install Android Studio and Android SDK manually.
  pause
  exit /b 1
)

set "ADB_CMD=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_CMD=%ANDROID_SDK_ROOT%\emulator\emulator.exe"

if exist "%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat" (
  set "SDKMANAGER_CMD=%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"
  set "AVDMANAGER_CMD=%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\avdmanager.bat"
  exit /b 0
)

for /d %%D in ("%ANDROID_SDK_ROOT%\cmdline-tools\*") do (
  if exist "%%~fD\bin\sdkmanager.bat" set "SDKMANAGER_CMD=%%~fD\bin\sdkmanager.bat"
  if exist "%%~fD\bin\avdmanager.bat" set "AVDMANAGER_CMD=%%~fD\bin\avdmanager.bat"
)

if not exist "%ADB_CMD%" (
  echo [LEXO] adb.exe not found under Android SDK.
  pause
  exit /b 1
)
if not exist "%EMULATOR_CMD%" (
  echo [LEXO] emulator.exe not found under Android SDK.
  pause
  exit /b 1
)
if not defined SDKMANAGER_CMD (
  echo [LEXO] sdkmanager.bat not found under Android SDK cmdline-tools.
  echo [LEXO] Install Android SDK Command-line Tools from Android Studio.
  pause
  exit /b 1
)
if not defined AVDMANAGER_CMD (
  echo [LEXO] avdmanager.bat not found under Android SDK cmdline-tools.
  echo [LEXO] Install Android SDK Command-line Tools from Android Studio.
  pause
  exit /b 1
)
exit /b 0
