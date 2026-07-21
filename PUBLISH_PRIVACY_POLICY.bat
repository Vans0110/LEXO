@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\PublishPrivacyPolicy.ps1" %*
exit /b %ERRORLEVEL%
