@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0\..\.."

echo [VIRGIL] Repo: %CD%
echo [VIRGIL] Scope: production_mobile
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [VIRGIL] Git not found in PATH.
  pause
  exit /b 1
)

git remote set-url origin https://github.com/Vans0110/LEXO.git >nul 2>nul

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "STAMP=%%i"
set "COMMIT_MSG=Virgil mobile update %STAMP%"

echo.
echo [VIRGIL] Auto commit message: %COMMIT_MSG%
echo.
echo [VIRGIL] Tracked changes before staging:
git --no-pager diff --name-only -- .github production_mobile history
echo.

echo [VIRGIL] Staging tracked changes only...
git add -u -- .github history
if errorlevel 1 (
  echo [VIRGIL] git add failed.
  pause
  exit /b 1
)

echo.
echo [VIRGIL] Staging safe new Virgil project files...
if exist "history" git add "history"
if exist "production_mobile\pubspec.yaml" git add "production_mobile\pubspec.yaml"
if exist "production_mobile\pubspec.lock" git add "production_mobile\pubspec.lock"
if exist "production_mobile\analysis_options.yaml" git add "production_mobile\analysis_options.yaml"
if exist "production_mobile\README.md" git add "production_mobile\README.md"
if exist "production_mobile\run_virgil_mobile_android.bat" git add "production_mobile\run_virgil_mobile_android.bat"
if exist "production_mobile\lib" git add "production_mobile\lib"
if exist "production_mobile\assets\ui" git add "production_mobile\assets\ui"
if exist "production_mobile\android" git add "production_mobile\android"
if exist "production_mobile\ios" git add "production_mobile\ios"
if exist "production_mobile\test" git add "production_mobile\test"
if exist "production_mobile\tool" git add "production_mobile\tool"
if exist "production_mobile\workbench\README.md" git add "production_mobile\workbench\README.md"
if exist "production_mobile\workbench\*.bat" git add "production_mobile\workbench\*.bat"
if exist ".github\workflows\build-virgil-ios.yml" git add ".github\workflows\build-virgil-ios.yml"

echo.
echo [VIRGIL] Verifying there is something to commit...
git diff --cached --quiet
if errorlevel 1 goto :has_changes
echo [VIRGIL] Nothing staged for commit.
pause
exit /b 1

:has_changes
echo.
echo [VIRGIL] Staged changes:
git --no-pager status --short
echo.
echo [VIRGIL] Creating commit...
git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
  echo [VIRGIL] Commit failed or nothing to commit.
  pause
  exit /b 1
)

echo.
echo [VIRGIL] Pushing to origin/main...
git push origin main
if errorlevel 1 (
  echo [VIRGIL] Push failed.
  pause
  exit /b 1
)

echo.
echo [VIRGIL] Push completed successfully.
pause
