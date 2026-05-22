@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0\..\.."

echo [NOVE] Repo: %CD%
echo [NOVE] Scope: production_mobile
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [NOVE] Git not found in PATH.
  pause
  exit /b 1
)

git remote set-url origin https://github.com/Vans0110/LEXO.git >nul 2>nul

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "STAMP=%%i"
set "COMMIT_MSG=Nove mobile update %STAMP%"

echo.
echo [NOVE] Auto commit message: %COMMIT_MSG%
echo.
echo [NOVE] Tracked changes before staging:
git --no-pager diff --name-only -- production_mobile history
echo.

echo [NOVE] Staging tracked changes only...
git add -u -- history
if errorlevel 1 (
  echo [NOVE] git add failed.
  pause
  exit /b 1
)

echo.
echo [NOVE] Staging safe new Nove project files...
if exist "history" git add "history"
if exist "production_mobile\pubspec.yaml" git add "production_mobile\pubspec.yaml"
if exist "production_mobile\pubspec.lock" git add "production_mobile\pubspec.lock"
if exist "production_mobile\analysis_options.yaml" git add "production_mobile\analysis_options.yaml"
if exist "production_mobile\README.md" git add "production_mobile\README.md"
if exist "production_mobile\run_nove_mobile_android.bat" git add "production_mobile\run_nove_mobile_android.bat"
if exist "production_mobile\lib" git add "production_mobile\lib"
if exist "production_mobile\android" git add "production_mobile\android"
if exist "production_mobile\test" git add "production_mobile\test"
if exist "production_mobile\tool" git add "production_mobile\tool"
if exist "production_mobile\workbench\README.md" git add "production_mobile\workbench\README.md"
if exist "production_mobile\workbench\*.bat" git add "production_mobile\workbench\*.bat"

echo.
echo [NOVE] Verifying there is something to commit...
git diff --cached --quiet
if errorlevel 1 goto :has_changes
echo [NOVE] Nothing staged for commit.
pause
exit /b 1

:has_changes
echo.
echo [NOVE] Staged changes:
git --no-pager status --short
echo.
echo [NOVE] Creating commit...
git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
  echo [NOVE] Commit failed or nothing to commit.
  pause
  exit /b 1
)

echo.
echo [NOVE] Pushing to origin/main...
git push origin main
if errorlevel 1 (
  echo [NOVE] Push failed.
  pause
  exit /b 1
)

echo.
echo [NOVE] Push completed successfully.
pause
