@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "WORKBENCH_DIR=%~dp0"
set "PROJECT_ROOT=%WORKBENCH_DIR%..\.."
set "APP_DIR=%PROJECT_ROOT%\Virgil\App"
set "BACKEND_BAT=%PROJECT_ROOT%\Studio\Backend\run_backend.bat"
cd /d "%APP_DIR%"

set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "DEFAULT_JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "LOG_DIR=%PROJECT_ROOT%\Studio\Runtime\workbench_logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "VIRGIL_WORKBENCH_TS="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd_HHmmss'"`) do set "VIRGIL_WORKBENCH_TS=%%I"
if not defined VIRGIL_WORKBENCH_TS set "VIRGIL_WORKBENCH_TS=latest"
set "VIRGIL_WORKBENCH_LOG_FILE=%LOG_DIR%\run_virgil_workbench_%VIRGIL_WORKBENCH_TS%.log"

echo [VIRGIL WORKBENCH] Writing log to:
echo [VIRGIL WORKBENCH]   %VIRGIL_WORKBENCH_LOG_FILE%

echo [VIRGIL WORKBENCH] Live output is shown in this window.
echo [VIRGIL WORKBENCH] Log file is reserved for future crash copies.

call :run
set "VIRGIL_WORKBENCH_EXIT=%ERRORLEVEL%"

echo [VIRGIL WORKBENCH] Exit code: %VIRGIL_WORKBENCH_EXIT%

if not "%VIRGIL_WORKBENCH_EXIT%"=="0" (
  echo [VIRGIL WORKBENCH] Launch failed. Log file:
  echo [VIRGIL WORKBENCH]   %VIRGIL_WORKBENCH_LOG_FILE%
)

echo [VIRGIL WORKBENCH] Press any key to close this window.
pause >nul
exit /b %VIRGIL_WORKBENCH_EXIT%

:run
echo [VIRGIL WORKBENCH] App dir: %APP_DIR%

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
  echo [VIRGIL WORKBENCH] Flutter not found.
  exit /b 1
)

if not defined JAVA_HOME (
  if exist "%DEFAULT_JAVA_HOME%\bin\java.exe" set "JAVA_HOME=%DEFAULT_JAVA_HOME%"
)

if defined JAVA_HOME set "PATH=%JAVA_HOME%\bin;%PATH%"

if not exist "%APP_DIR%\windows" (
  echo [VIRGIL WORKBENCH] windows folder is missing.
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
  echo [VIRGIL WORKBENCH] Dependencies changed or missing. Executing flutter pub get...
  call "%FLUTTER_CMD%" pub get
  if errorlevel 1 (
    echo [VIRGIL WORKBENCH] Error during flutter pub get.
    exit /b 1
  )
)

call :ensure_backend
if errorlevel 1 exit /b 1

echo [VIRGIL WORKBENCH] Starting Flutter Windows Workbench...
call "%FLUTTER_CMD%" run --no-pub -d windows ^
  --dart-define=VIRGIL_MODE=workbench ^
  --dart-define=VIRGIL_WORKSPACE_ROOT="%PROJECT_ROOT%"
exit /b %ERRORLEVEL%

:ensure_backend
call :is_backend_running
if not errorlevel 1 (
  echo [VIRGIL WORKBENCH] Backend already running on 127.0.0.1:8765.
  exit /b 0
)

if not exist "%BACKEND_BAT%" (
  echo [VIRGIL WORKBENCH] Backend launcher not found:
  echo [VIRGIL WORKBENCH]   %BACKEND_BAT%
  exit /b 1
)

echo [VIRGIL WORKBENCH] Starting backend...
start "LEXO Backend" cmd /c ""%BACKEND_BAT%""

for /l %%I in (1,1,20) do (
  timeout /t 1 /nobreak >nul
  call :is_backend_running
  if not errorlevel 1 (
    echo [VIRGIL WORKBENCH] Backend is ready on 127.0.0.1:8765.
    exit /b 0
  )
)

echo [VIRGIL WORKBENCH] Backend start requested, but port 8765 is not ready yet.
echo [VIRGIL WORKBENCH] Continuing; backend may still be loading.
exit /b 0

:is_backend_running
powershell -NoProfile -Command "$c=New-Object Net.Sockets.TcpClient; try { $iar=$c.BeginConnect('127.0.0.1',8765,$null,$null); if(-not $iar.AsyncWaitHandle.WaitOne(300)){ exit 1 }; $c.EndConnect($iar); exit 0 } catch { exit 1 } finally { $c.Close() }"
exit /b %ERRORLEVEL%
