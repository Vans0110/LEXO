@echo off
setlocal

set "ADB=%~1"
set "OUT_DIR=%~2"

if "%ADB%"=="" (
  echo Missing adb path.
  exit /b 1
)

if "%OUT_DIR%"=="" (
  echo Missing output dir.
  exit /b 1
)

mkdir "%OUT_DIR%" >nul 2>nul
set "LOG_FILE=%OUT_DIR%\live_logcat.txt"

echo Clearing logcat...
"%ADB%" logcat -c
echo Writing full logcat to:
echo %LOG_FILE%
echo.
echo Filter hints:
echo   onlinePageTranslated
echo   Local translate success
echo   FileDialog
echo   FlutterArchivePlugin
echo.

"%ADB%" logcat | powershell -NoProfile -Command ^
  "$log = '%LOG_FILE%';" ^
  "$patterns = 'onlinePageTranslated|Local translate success|Failed local translate|translateWithEngine|parallel\.align|parallel\.match|FileDialog|FlutterArchivePlugin';" ^
  "$input | Tee-Object -FilePath $log -Append | Select-String -Pattern $patterns"

endlocal
