@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "DST=%~dp0..\LEXO_GITHUB"
if "%DST:~-1%"=="\" set "DST=%DST:~0,-1%"

echo [LEXO] Source:
echo [LEXO]   %SRC%
echo [LEXO] Destination:
echo [LEXO]   %DST%
echo.

if exist "%DST%" (
  echo [LEXO] Removing old clean repo folder...
  rmdir /s /q "%DST%"
  if exist "%DST%" (
    echo [LEXO] Failed to remove old destination folder.
    pause
    exit /b 1
  )
)

mkdir "%DST%"
if errorlevel 1 (
  echo [LEXO] Failed to create destination folder.
  pause
  exit /b 1
)

echo [LEXO] Copying app...
robocopy "%SRC%\app" "%DST%\app" /E /R:1 /W:1 /NFL /NDL /NJH /NJS ^
  /XD ".dart_tool" "build" ".idea" "windows\flutter\ephemeral"
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto robocopy_failed

echo [LEXO] Copying engine...
robocopy "%SRC%\engine" "%DST%\engine" /E /R:1 /W:1 /NFL /NDL /NJH /NJS ^
  /XD "__pycache__" "tts\__pycache__"
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto robocopy_failed

echo [LEXO] Copying MVP...
robocopy "%SRC%\MVP" "%DST%\MVP" /E /R:1 /W:1 /NFL /NDL /NJH /NJS
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto robocopy_failed

echo [LEXO] Copying history...
robocopy "%SRC%\history" "%DST%\history" /E /R:1 /W:1 /NFL /NDL /NJH /NJS
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto robocopy_failed

echo [LEXO] Copying scripts...
robocopy "%SRC%\scripts" "%DST%\scripts" /E /R:1 /W:1 /NFL /NDL /NJH /NJS
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto robocopy_failed

if exist "%SRC%\AGENTS.md" copy /Y "%SRC%\AGENTS.md" "%DST%\" >nul
if exist "%SRC%\README.md" copy /Y "%SRC%\README.md" "%DST%\" >nul
if exist "%SRC%\run_lexo_engine_lan.bat" copy /Y "%SRC%\run_lexo_engine_lan.bat" "%DST%\" >nul
if exist "%SRC%\run_lexo_mobile_android.bat" copy /Y "%SRC%\run_lexo_mobile_android.bat" "%DST%\" >nul
if exist "%SRC%\run_lexo_mvp.bat" copy /Y "%SRC%\run_lexo_mvp.bat" "%DST%\" >nul

(
echo .venv/
echo .venv_kokoro/
echo __pycache__/
echo *.pyc
echo app/.dart_tool/
echo app/build/
echo app/.idea/
echo app/windows/flutter/ephemeral/
echo data/
echo logs/
echo Books/
echo .vscode/
echo .DS_Store
echo Thumbs.db
) > "%DST%\.gitignore"

echo.
echo [LEXO] Clean GitHub-ready folder prepared:
echo [LEXO]   %DST%
echo.
echo [LEXO] Next commands:
echo [LEXO]   cd /d "%DST%"
echo [LEXO]   git init
echo [LEXO]   git config user.name "Vans0110"
echo [LEXO]   git config user.email "ivan.kurtinov@gmail.com"
echo [LEXO]   git add .
echo [LEXO]   git commit -m "Initial MVP10 baseline"
echo [LEXO]   git branch -M main
echo [LEXO]   git remote add origin https://github.com/ТВОЙ_ЛОГИН/lexo.git
echo [LEXO]   git push -u origin main
echo.
pause
exit /b 0

:robocopy_failed
echo [LEXO] robocopy failed with exit code %RC%.
pause
exit /b %RC%
