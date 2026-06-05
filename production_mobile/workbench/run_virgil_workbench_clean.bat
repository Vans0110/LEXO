@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "WORKBENCH_DIR=%~dp0"
set "APP_DIR=%WORKBENCH_DIR%.."
set "WINDOWS_BUILD_DIR=%APP_DIR%\build\windows"
set "PLUGIN_SYMLINKS=%APP_DIR%\windows\flutter\ephemeral\.plugin_symlinks"

if exist "%WINDOWS_BUILD_DIR%" (
  echo [VIRGIL WORKBENCH CLEAN] Clearing Windows build cache:
  echo [VIRGIL WORKBENCH CLEAN]   %WINDOWS_BUILD_DIR%
  rmdir /s /q "%WINDOWS_BUILD_DIR%"
) else (
  echo [VIRGIL WORKBENCH CLEAN] Windows build cache is already empty.
)

if exist "%PLUGIN_SYMLINKS%" (
  echo [VIRGIL WORKBENCH CLEAN] Clearing generated Flutter plugin symlinks:
  echo [VIRGIL WORKBENCH CLEAN]   %PLUGIN_SYMLINKS%
  rmdir /s /q "%PLUGIN_SYMLINKS%"
) else (
  echo [VIRGIL WORKBENCH CLEAN] Flutter plugin symlinks are already empty.
)

call "%WORKBENCH_DIR%run_virgil_workbench.bat"
exit /b %ERRORLEVEL%
