@echo off
setlocal EnableDelayedExpansion

set "ADB=%~1"
set "OUT_DIR=%~2"
set "PACKAGE=%~3"

if "%ADB%"=="" exit /b 1
if "%OUT_DIR%"=="" exit /b 1
if "%PACKAGE%"=="" exit /b 1

mkdir "%OUT_DIR%" >nul 2>nul
set /a HIT=0

echo Watching transient ebooks directory...
echo Output: %OUT_DIR%
echo.

:loop
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"') do set "TS=%%I"
set "TREE_FILE=%OUT_DIR%\tree_!TS!.txt"

"%ADB%" shell "find /data/data/%PACKAGE%/app_flutter/ebooks -maxdepth 6 2>/dev/null | sort" > "!TREE_FILE!"
for /f %%L in ('find /c /v "" ^< "!TREE_FILE!"') do set "LINES=%%L"

if !LINES! GTR 1 (
  set /a HIT+=1
  set "PULL_DIR=%OUT_DIR%\pull_!TS!_!HIT!"
  mkdir "!PULL_DIR!" >nul 2>nul
  "%ADB%" pull "/data/data/%PACKAGE%/app_flutter/ebooks" "!PULL_DIR!" > "!OUT_DIR!\pull_!TS!_!HIT!.log" 2>&1
  echo EBOOKS !TS! lines=!LINES! dir=!PULL_DIR!
)

timeout /t 1 /nobreak >nul
goto loop
