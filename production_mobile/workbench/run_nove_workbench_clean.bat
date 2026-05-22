@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "WORKBENCH_DIR=%~dp0"
set "APP_DIR=%WORKBENCH_DIR%.."
set "WINDOWS_BUILD_DIR=%APP_DIR%\build\windows"
set "PLUGIN_SYMLINKS=%APP_DIR%\windows\flutter\ephemeral\.plugin_symlinks"

if exist "%WINDOWS_BUILD_DIR%" (
  echo [NOVE WORKBENCH CLEAN] Clearing Windows build cache:
  echo [NOVE WORKBENCH CLEAN]   %WINDOWS_BUILD_DIR%
  rmdir /s /q "%WINDOWS_BUILD_DIR%"
) else (
  echo [NOVE WORKBENCH CLEAN] Windows build cache is already empty.
)

if exist "%PLUGIN_SYMLINKS%" (
  echo [NOVE WORKBENCH CLEAN] Clearing generated Flutter plugin symlinks:
  echo [NOVE WORKBENCH CLEAN]   %PLUGIN_SYMLINKS%
  rmdir /s /q "%PLUGIN_SYMLINKS%"
) else (
  echo [NOVE WORKBENCH CLEAN] Flutter plugin symlinks are already empty.
)

call "%WORKBENCH_DIR%run_nove_workbench.bat"
exit /b %ERRORLEVEL%
