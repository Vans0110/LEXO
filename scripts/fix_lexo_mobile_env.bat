@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "ROOT_DIR=%~dp0.."
cd /d "%ROOT_DIR%"

set "JAVA_HOME_VALUE=C:\Program Files\Android\Android Studio\jbr"
set "FLUTTER_BIN=C:\src\flutter\bin"

if not exist "%JAVA_HOME_VALUE%\bin\java.exe" (
  echo [LEXO] Java runtime not found:
  echo [LEXO]   %JAVA_HOME_VALUE%
  echo [LEXO] Install Android Studio first or edit this file with the correct path.
  pause
  exit /b 1
)

if not exist "%FLUTTER_BIN%\flutter.bat" (
  echo [LEXO] Flutter not found:
  echo [LEXO]   %FLUTTER_BIN%
  echo [LEXO] Install Flutter SDK there or edit this file with the correct path.
  pause
  exit /b 1
)

echo [LEXO] Setting persistent JAVA_HOME...
setx JAVA_HOME "%JAVA_HOME_VALUE%" >nul
if errorlevel 1 (
  echo [LEXO] Failed to set JAVA_HOME.
  pause
  exit /b 1
)

echo [LEXO] Updating user PATH with Java and Flutter...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$javaBin = '%JAVA_HOME_VALUE%\bin';" ^
  "$flutterBin = '%FLUTTER_BIN%';" ^
  "$path = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
  "$parts = @();" ^
  "if ($path) { $parts = $path -split ';' | Where-Object { $_ -and $_.Trim() -ne '' } };" ^
  "if (-not ($parts -contains $javaBin)) { $parts += $javaBin };" ^
  "if (-not ($parts -contains $flutterBin)) { $parts += $flutterBin };" ^
  "[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')"
if errorlevel 1 (
  echo [LEXO] Failed to update user PATH.
  pause
  exit /b 1
)

echo.
echo [LEXO] Environment variables saved.
echo [LEXO] Close this CMD window and open a new one.
echo [LEXO] Then run once:
echo [LEXO]   flutter doctor --android-licenses
echo [LEXO] After that you can use:
echo [LEXO]   run_lexo_mobile_android.bat
pause
exit /b 0
