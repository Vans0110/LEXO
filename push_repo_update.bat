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
git diff --name-only
echo.

echo [LEXO] Staging tracked changes only...
git add -u
if errorlevel 1 (
  echo [LEXO] git add failed.
  pause
  exit /b 1
)

echo.
echo [LEXO] Explicit safe new files...
if exist "push_repo_update.bat" git add "push_repo_update.bat"
if exist ".github" git add ".github"
if exist "scripts\make_github_repo.bat" git add "scripts\make_github_repo.bat"

echo [LEXO] Verifying there is something to commit...
git diff --cached --quiet
if errorlevel 1 goto :has_changes
echo [LEXO] Nothing staged for commit.
pause
exit /b 1

:has_changes
echo.
echo [LEXO] Staged changes:
git status --short
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
