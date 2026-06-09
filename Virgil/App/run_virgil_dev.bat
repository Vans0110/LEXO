@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "APP_DIR=%~dp0"
set "WORKSPACE_DIR=%APP_DIR%..\.."
cd /d "%APP_DIR%"

set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "LOG_DIR=%WORKSPACE_DIR%\Studio\Runtime\dev_logs"
set "ANDROID_LOGCAT_FILE=%LOG_DIR%\android_logcat.txt"
set "DEFAULT_SDK=%LOCALAPPDATA%\Android\Sdk"
set "DEFAULT_JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_SDK_ROOT="
set "ADB_CMD="
set "EMULATOR_CMD="
set "TARGET_DEVICE="
set "AVD_NAME=LEXO_Pixel_6"
set "EMULATOR_ARGS=-avd %AVD_NAME% -no-snapshot-load"
set "VIRGIL_LIBRARY_BASE_URL=https://pub-05fee08c1a5741d6a9a57d087c327c96.r2.dev/virgil/library"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "VIRGIL_RUN_TS="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd_HHmmss'"`) do set "VIRGIL_RUN_TS=%%I"
if not defined VIRGIL_RUN_TS set "VIRGIL_RUN_TS=latest"
set "VIRGIL_RUN_LOG_FILE=%LOG_DIR%\run_virgil_mobile_android_%VIRGIL_RUN_TS%.log"

echo [VIRGIL] Writing log to:
echo [VIRGIL]   %VIRGIL_RUN_LOG_FILE%

call :run > "%VIRGIL_RUN_LOG_FILE%" 2>&1
set "VIRGIL_RUN_EXIT=%ERRORLEVEL%"

type "%VIRGIL_RUN_LOG_FILE%"
echo [VIRGIL] Exit code: %VIRGIL_RUN_EXIT%

if not "%VIRGIL_RUN_EXIT%"=="0" (
  echo [VIRGIL] Launch failed. Log file:
  echo [VIRGIL]   %VIRGIL_RUN_LOG_FILE%
)

echo [VIRGIL] Press any key to close this window.
pause >nul
exit /b %VIRGIL_RUN_EXIT%

:run
echo [VIRGIL] App dir: %APP_DIR%

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
  echo [VIRGIL] Flutter not found.
  exit /b 1
)

if not defined JAVA_HOME (
  if exist "%DEFAULT_JAVA_HOME%\bin\java.exe" set "JAVA_HOME=%DEFAULT_JAVA_HOME%"
)

if not defined JAVA_HOME (
  echo [VIRGIL] Java not found.
  echo [VIRGIL] Install Android Studio JBR or set JAVA_HOME.
  exit /b 1
)

set "PATH=%JAVA_HOME%\bin;%PATH%"
where java >nul 2>nul
if errorlevel 1 (
  echo [VIRGIL] java command not available.
  exit /b 1
)

if defined ANDROID_HOME if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if not defined ANDROID_SDK_ROOT if exist "%DEFAULT_SDK%\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%DEFAULT_SDK%"
if not defined ANDROID_SDK_ROOT if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"

if not defined ANDROID_SDK_ROOT (
  echo [VIRGIL] Android SDK not found.
  exit /b 1
)

set "ADB_CMD=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set "EMULATOR_CMD=%ANDROID_SDK_ROOT%\emulator\emulator.exe"

if not exist "%ADB_CMD%" (
  echo [VIRGIL] adb.exe not found.
  exit /b 1
)
if not exist "%EMULATOR_CMD%" (
  echo [VIRGIL] emulator.exe not found.
  exit /b 1
)

if not exist "%APP_DIR%android" (
  echo [VIRGIL] android folder is missing.
  exit /b 1
)

if not exist "%APP_DIR%.dart_tool" (
  echo [VIRGIL] First Flutter run. Executing flutter pub get...
  call "%FLUTTER_CMD%" pub get
  if errorlevel 1 (
    echo [VIRGIL] Error during flutter pub get.
    exit /b 1
  )
)

echo [VIRGIL] Checking emulator list...
set "AVD_EXISTS="
for /f "usebackq delims=" %%A in (`"%EMULATOR_CMD%" -list-avds 2^>nul`) do (
  if /I "%%A"=="%AVD_NAME%" set "AVD_EXISTS=1"
)
if not defined AVD_EXISTS (
  echo [VIRGIL] AVD "%AVD_NAME%" not found.
  exit /b 1
)

set "TARGET_DEVICE="
for /f "skip=1 tokens=1,2" %%D in ('"%ADB_CMD%" devices') do (
  echo %%D| findstr /B /C:"emulator-" >nul
  if not errorlevel 1 if /I "%%E"=="device" set "TARGET_DEVICE=%%D"
)

if not defined TARGET_DEVICE (
  echo [VIRGIL] Starting Android emulator "%AVD_NAME%"...
  echo [VIRGIL] Emulator args: %EMULATOR_ARGS%
  start "Virgil Android Emulator" "%EMULATOR_CMD%" %EMULATOR_ARGS%
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
  echo [VIRGIL] Emulator did not become ready in time.
  exit /b 1
)

:wait_for_boot
echo [VIRGIL] Waiting for Android boot completion...
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
  timeout /t 2 /nobreak >nul
)

echo [VIRGIL] Emulator boot did not complete in time.
exit /b 1

:boot_done
echo [VIRGIL] Emulator boot complete.
echo [VIRGIL] Using Android device: %TARGET_DEVICE%
echo [VIRGIL] Clearing adb logcat buffer...
"%ADB_CMD%" -s %TARGET_DEVICE% logcat -c >nul 2>nul

if not defined VIRGIL_LIBRARY_BASE_URL (
  echo [VIRGIL] VIRGIL_LIBRARY_BASE_URL is empty.
  echo [VIRGIL] Set it in this bat to your public R2 URL, for example:
  echo [VIRGIL]   https://YOUR_PUBLIC_DOMAIN/virgil/library
  exit /b 1
)

echo [VIRGIL] Starting Flutter Android app...
echo [VIRGIL] Cloud library: %VIRGIL_LIBRARY_BASE_URL%
call "%FLUTTER_CMD%" run -d "%TARGET_DEVICE%" --dart-define=VIRGIL_MODE=mobile --dart-define=VIRGIL_LIBRARY_BASE_URL="%VIRGIL_LIBRARY_BASE_URL%"
set "FLUTTER_EXIT=%ERRORLEVEL%"
if not "%FLUTTER_EXIT%"=="0" (
  echo [VIRGIL] Flutter Android app exited with an error.
  echo [VIRGIL] Saving adb logcat to:
  echo [VIRGIL]   %ANDROID_LOGCAT_FILE%
  "%ADB_CMD%" -s %TARGET_DEVICE% logcat -d > "%ANDROID_LOGCAT_FILE%" 2>&1
  exit /b 1
)

exit /b 0
