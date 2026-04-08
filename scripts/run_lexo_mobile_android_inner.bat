@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "ROOT_DIR=%~dp0.."
cd /d "%ROOT_DIR%"

set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "APP_DIR=%ROOT_DIR%\app"
set "LOG_DIR=%ROOT_DIR%\logs"
set "ANDROID_LOGCAT_FILE=%LOG_DIR%\android_logcat.txt"
set "DEFAULT_SDK=%LOCALAPPDATA%\Android\Sdk"
set "DEFAULT_JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_SDK_ROOT="
set "ADB_CMD="
set "EMULATOR_CMD="
set "TARGET_DEVICE="
set "AVD_NAME=LEXO_Pixel_6"
set "EMULATOR_ARGS=-avd %AVD_NAME% -no-snapshot-load"
set "LEXO_ANDROID_HOST_LINK=%LEXO_ANDROID_HOST_LINK%"
set "LEXO_ANDROID_DEFAULT_HOST_URL=%LEXO_ANDROID_DEFAULT_HOST_URL%"

if not defined LEXO_ANDROID_HOST_LINK set "LEXO_ANDROID_HOST_LINK=0"
if not defined LEXO_ANDROID_DEFAULT_HOST_URL set "LEXO_ANDROID_DEFAULT_HOST_URL=http://10.0.2.2:8765"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

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
  echo [LEXO] Emulator args: %EMULATOR_ARGS%
  start "LEXO Android Emulator" "%EMULATOR_CMD%" %EMULATOR_ARGS%
)

if not defined TARGET_DEVICE (
  for /l %%I in (1,1,150) do (
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
for /l %%I in (1,1,180) do (
  set "BOOT_DONE="
  set "BOOT_ANIM="
  for /f %%B in ('"%ADB_CMD%" -s %TARGET_DEVICE% shell getprop sys.boot_completed 2^>nul') do (
    if "%%B"=="1" set "BOOT_DONE=1"
  )
  for /f %%B in ('"%ADB_CMD%" -s %TARGET_DEVICE% shell getprop init.svc.bootanim 2^>nul') do (
    if /I "%%B"=="stopped" set "BOOT_ANIM=1"
  )
  if defined BOOT_DONE if defined BOOT_ANIM goto boot_done
  if defined BOOT_DONE (
    echo [LEXO] Boot flag is up, waiting for boot animation to stop...
  )
  timeout /t 2 /nobreak >nul
)

echo [LEXO] Emulator boot did not complete in time.
echo [LEXO] This usually means the AVD is stuck during startup or Quick Boot state is bad.
echo [LEXO] Recommended manual fixes:
echo [LEXO]   1. Device Manager -^> LEXO_Pixel_6 -^> Cold Boot Now
echo [LEXO]   2. If needed: Wipe Data
echo [LEXO]   3. Set RAM to 4096 MB in AVD settings
pause
exit /b 1

:boot_done
echo [LEXO] Emulator boot complete.
echo [LEXO] Using Android device: %TARGET_DEVICE%
echo [LEXO] Clearing adb logcat buffer...
"%ADB_CMD%" -s %TARGET_DEVICE% logcat -c >nul 2>nul
echo [LEXO] Android mobile launcher does not start host automatically.
if "%LEXO_ANDROID_HOST_LINK%"=="1" (
  echo [LEXO] Emulator host-link mode is enabled.
  echo [LEXO] This launcher only configures stable adb reverse transport.
  echo [LEXO] Start host separately:
  echo [LEXO]   run_lexo_engine_lan.bat
  echo [LEXO] Enabling adb reverse tcp:8765 -> tcp:8765...
  "%ADB_CMD%" -s %TARGET_DEVICE% reverse tcp:8765 tcp:8765 >nul 2>nul
  if errorlevel 1 (
    echo [LEXO] adb reverse failed.
    pause
    exit /b 1
  )
  echo [LEXO] adb reverse enabled.
) else (
  echo [LEXO] Offline mode is enabled.
  echo [LEXO] Android mobile launcher does not configure automatic host routing.
  echo [LEXO] If you need desktop/LAN sync, start host separately:
  echo [LEXO]   run_lexo_engine_lan.bat
  echo [LEXO] Then enter PC IP manually in mobile Settings -> Host URL.
  echo [LEXO] If you only test offline mobile UI, host is not required.
)
echo [LEXO] Waiting before starting mobile UI...
timeout /t 1 /nobreak >nul

echo [LEXO] Starting Flutter Android app...
echo [LEXO] Emulator default Host URL inside app: %LEXO_ANDROID_DEFAULT_HOST_URL%
pushd "%APP_DIR%"
call "%FLUTTER_CMD%" run -d "%TARGET_DEVICE%" --dart-define=LEXO_DEFAULT_MOBILE_HOST_URL=%LEXO_ANDROID_DEFAULT_HOST_URL%
set "FLUTTER_EXIT=%ERRORLEVEL%"
popd
if not "%FLUTTER_EXIT%"=="0" (
  echo [LEXO] Flutter Android app exited with an error.
  echo [LEXO] Saving adb logcat to:
  echo [LEXO]   %ANDROID_LOGCAT_FILE%
  "%ADB_CMD%" -s %TARGET_DEVICE% logcat -d > "%ANDROID_LOGCAT_FILE%" 2>&1
  pause
  exit /b 1
)

endlocal
exit /b 0
