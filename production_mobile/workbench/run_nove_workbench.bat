@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "WORKBENCH_DIR=%~dp0"
set "APP_DIR=%WORKBENCH_DIR%.."
cd /d "%APP_DIR%"

set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "DEFAULT_JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "LOG_DIR=%WORKBENCH_DIR%logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "NOVE_WORKBENCH_TS="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd_HHmmss'"`) do set "NOVE_WORKBENCH_TS=%%I"
if not defined NOVE_WORKBENCH_TS set "NOVE_WORKBENCH_TS=latest"
set "NOVE_WORKBENCH_LOG_FILE=%LOG_DIR%\run_nove_workbench_%NOVE_WORKBENCH_TS%.log"

echo [NOVE WORKBENCH] Writing log to:
echo [NOVE WORKBENCH]   %NOVE_WORKBENCH_LOG_FILE%

echo [NOVE WORKBENCH] Live output is shown in this window.
echo [NOVE WORKBENCH] Log file is reserved for future crash copies.

call :run
set "NOVE_WORKBENCH_EXIT=%ERRORLEVEL%"

echo [NOVE WORKBENCH] Exit code: %NOVE_WORKBENCH_EXIT%

if not "%NOVE_WORKBENCH_EXIT%"=="0" (
  echo [NOVE WORKBENCH] Launch failed. Log file:
  echo [NOVE WORKBENCH]   %NOVE_WORKBENCH_LOG_FILE%
)

echo [NOVE WORKBENCH] Press any key to close this window.
pause >nul
exit /b %NOVE_WORKBENCH_EXIT%

:run
echo [NOVE WORKBENCH] App dir: %APP_DIR%

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
  echo [NOVE WORKBENCH] Flutter not found.
  exit /b 1
)

if not defined JAVA_HOME (
  if exist "%DEFAULT_JAVA_HOME%\bin\java.exe" set "JAVA_HOME=%DEFAULT_JAVA_HOME%"
)

if defined JAVA_HOME set "PATH=%JAVA_HOME%\bin;%PATH%"

if not exist "%APP_DIR%\windows" (
  echo [NOVE WORKBENCH] windows folder is missing.
  exit /b 1
)

set "PACKAGE_CONFIG=%APP_DIR%\.dart_tool\package_config.json"
set "NEEDS_PUB_GET="
if not exist "%PACKAGE_CONFIG%" set "NEEDS_PUB_GET=1"
if not defined NEEDS_PUB_GET (
  for %%I in ("%APP_DIR%\pubspec.lock") do set "PUBSPEC_LOCK_TS=%%~tI"
  for %%I in ("%PACKAGE_CONFIG%") do set "PACKAGE_CONFIG_TS=%%~tI"
  powershell -NoProfile -Command "exit ([datetime](Get-Item -LiteralPath '%APP_DIR%\pubspec.lock').LastWriteTime -gt [datetime](Get-Item -LiteralPath '%PACKAGE_CONFIG%').LastWriteTime)"
  if errorlevel 1 set "NEEDS_PUB_GET=1"
)

if defined NEEDS_PUB_GET (
  echo [NOVE WORKBENCH] Dependencies changed or missing. Executing flutter pub get...
  call "%FLUTTER_CMD%" pub get
  if errorlevel 1 (
    echo [NOVE WORKBENCH] Error during flutter pub get.
    exit /b 1
  )
)

echo [NOVE WORKBENCH] Starting Flutter Windows Workbench...
call "%FLUTTER_CMD%" run --no-pub -d windows --dart-define=NOVE_MODE=workbench
exit /b %ERRORLEVEL%
