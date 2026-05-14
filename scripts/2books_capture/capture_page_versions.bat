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
set "TARGET=/data/data/%PACKAGE%/app_flutter/books/%BOOK_SLUG%/pages/0.json.gz"
set "PREV_SIG="
set /a VERSION=0

echo Watching:
echo %TARGET%
echo Output: %OUT_DIR%
echo.

:loop
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"') do set "TS=%%I"
set "STAT_FILE=%OUT_DIR%\stat_!TS!.txt"

"%ADB%" shell "ls -ln !TARGET! 2>/dev/null || toybox ls -ln !TARGET! 2>/dev/null || true" > "!STAT_FILE!"
set "SIG="
set /p SIG=<"!STAT_FILE!"

if not "!SIG!"=="" (
  if not "!SIG!"=="!PREV_SIG!" (
    set "PREV_SIG=!SIG!"
    set /a VERSION+=1
    set "DEST=%OUT_DIR%\!TS!_!VERSION!_0.json.gz"
    "%ADB%" pull "!TARGET!" "!DEST!" > "!OUT_DIR!\!TS!_!VERSION!.log" 2>&1
    echo PAGE !TS! ^> !DEST! :: !SIG!
  )
)

timeout /t 1 /nobreak >nul
goto loop
