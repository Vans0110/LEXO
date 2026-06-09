@echo off
setlocal

set "KEYTOOL=C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
set "KEY_DIR=%~dp0keys"
set "KEYSTORE=%KEY_DIR%\virgil-upload.jks"

if not exist "%KEYTOOL%" (
  echo [VIRGIL] keytool was not found:
  echo %KEYTOOL%
  echo Install Android Studio or update KEYTOOL in this script.
  exit /b 1
)

if exist "%KEYSTORE%" (
  echo [VIRGIL] Upload key already exists:
  echo %KEYSTORE%
  echo The existing key was not changed.
  exit /b 1
)

if not exist "%KEY_DIR%" mkdir "%KEY_DIR%"

echo [VIRGIL] Creating the Google Play upload key.
echo [VIRGIL] Store the password securely. It cannot be recovered from this project.
echo.

"%KEYTOOL%" -genkeypair -v ^
  -keystore "%KEYSTORE%" ^
  -alias virgil-upload ^
  -keyalg RSA ^
  -keysize 2048 ^
  -validity 10000

if errorlevel 1 (
  echo.
  echo [VIRGIL] Upload key creation failed.
  exit /b 1
)

echo.
echo [VIRGIL] Upload key created:
echo %KEYSTORE%
echo.
echo Next:
echo 1. Copy android\key.properties.example to android\key.properties
echo 2. Replace both password placeholders
echo 3. Keep the JKS file and passwords outside Git and make two backups

endlocal
