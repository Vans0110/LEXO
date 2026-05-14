@echo off
setlocal EnableDelayedExpansion

set "ADB=%~1"
set "OUT_DIR=%~2"
set "PACKAGE=%~3"
set "BOOK_SLUG=%~4"

if "%ADB%"=="" exit /b 1
if "%OUT_DIR%"=="" exit /b 1
if "%PACKAGE%"=="" exit /b 1
if "%BOOK_SLUG%"=="" exit /b 1

mkdir "%OUT_DIR%" >nul 2>nul
set /a SNAP=0

echo Watching cache / databases / books...
echo Output: %OUT_DIR%
echo.

:loop
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"') do set "TS=%%I"
set "STATE_FILE=%OUT_DIR%\state_!TS!.txt"

(
  echo === CACHE ===
  "%ADB%" shell "find /data/data/%PACKAGE%/cache -maxdepth 2 -type f -print0 2>/dev/null | xargs -0 -r ls -lh"
  echo === DATABASES ===
  "%ADB%" shell "find /data/data/%PACKAGE%/databases -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 -r ls -lh"
  echo === BOOKS ===
  "%ADB%" shell "find /data/data/%PACKAGE%/app_flutter/books/%BOOK_SLUG% -maxdepth 3 -type f -print0 2>/dev/null | xargs -0 -r ls -lh"
) > "!STATE_FILE!"

set /a SNAP+=1
if !SNAP! GEQ 10 (
  echo SNAP !TS!
  set /a SNAP=0
)

timeout /t 1 /nobreak >nul
goto loop
