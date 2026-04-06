@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

echo [LEXO] Repo: %CD%
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [LEXO] Git not found in PATH.
  pause
  exit /b 1
)

git remote set-url origin https://github.com/Vans0110/LEXO.git >nul 2>nul

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "STAMP=%%i"
set "COMMIT_MSG=Auto update %STAMP%"

echo.
echo [LEXO] Auto commit message: %COMMIT_MSG%
echo.
echo [LEXO] Tracked changes before staging:
git --no-pager diff --name-only
echo.

echo [LEXO] Staging tracked changes only...
git add -u
if errorlevel 1 (
  echo [LEXO] git add failed.
  pause
  exit /b 1
)

echo.
echo [LEXO] Staging safe new project files...
if exist "AGENTS.md" git add "AGENTS.md"
if exist "README.md" git add "README.md"
if exist "push_repo_update.bat" git add "push_repo_update.bat"
if exist "run_lexo_mvp.bat" git add "run_lexo_mvp.bat"
if exist ".github" git add ".github"
if exist "scripts" git add "scripts"
if exist "MVP" git add "MVP"
if exist "history" git add "history"
if exist "engine" git add "engine"
if exist "app\pubspec.yaml" git add "app\pubspec.yaml"
if exist "app\pubspec.lock" git add "app\pubspec.lock"
if exist "app\analysis_options.yaml" git add "app\analysis_options.yaml"
if exist "app\lib" git add "app\lib"
if exist "app\ios" git add "app\ios"
if exist "app\android" git add "app\android"
if exist "app\test" git add "app\test"
if exist "app\web" git add "app\web"
if exist "app\macos" git add "app\macos"
if exist "app\linux" git add "app\linux"
if exist "app\windows\runner" git add "app\windows\runner"
if exist "app\windows\CMakeLists.txt" git add "app\windows\CMakeLists.txt"
if exist "app\windows\flutter\generated_plugin_registrant.cc" git add "app\windows\flutter\generated_plugin_registrant.cc"
if exist "app\windows\flutter\generated_plugin_registrant.h" git add "app\windows\flutter\generated_plugin_registrant.h"
if exist "app\windows\flutter\generated_plugins.cmake" git add "app\windows\flutter\generated_plugins.cmake"

echo [LEXO] Verifying there is something to commit...
git diff --cached --quiet
if errorlevel 1 goto :has_changes
echo [LEXO] Nothing staged for commit.
pause
exit /b 1

:has_changes
echo.
echo [LEXO] Staged changes:
git --no-pager status --short
echo.
echo [LEXO] Creating commit...
git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
  echo [LEXO] Commit failed or nothing to commit.
  pause
  exit /b 1
)

echo.
echo [LEXO] Pushing to origin/main...
git push origin main
if errorlevel 1 (
  echo [LEXO] Push failed.
  pause
  exit /b 1
)

echo.
echo [LEXO] Push completed successfully.
pause
