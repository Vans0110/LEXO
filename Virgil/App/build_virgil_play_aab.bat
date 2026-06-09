@echo off
setlocal

set "PROJECT_DIR=%~dp0"
set "WORKSPACE_DIR=%PROJECT_DIR%..\.."
set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
set "KEYTOOL=C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
set "KEY_PROPERTIES=%PROJECT_DIR%android\key.properties"
set "KEYSTORE=%PROJECT_DIR%keys\virgil-upload.jks"
set "CLOUD_URL=https://pub-05fee08c1a5741d6a9a57d087c327c96.r2.dev/virgil/library"
set "AAB=%PROJECT_DIR%build\app\outputs\bundle\release\app-release.aab"

if not exist "%FLUTTER_CMD%" (
  echo [VIRGIL] Flutter was not found:
  echo %FLUTTER_CMD%
  exit /b 1
)
if not exist "%KEYTOOL%" (
  echo [VIRGIL] keytool was not found:
  echo %KEYTOOL%
  exit /b 1
)
if not exist "%KEY_PROPERTIES%" (
  echo [VIRGIL] Release signing is not configured:
  echo %KEY_PROPERTIES%
  exit /b 1
)
if not exist "%KEYSTORE%" (
  echo [VIRGIL] Upload key was not found:
  echo %KEYSTORE%
  exit /b 1
)

echo [VIRGIL] Checking cloud library...
powershell.exe -NoProfile -Command ^
  "$response = Invoke-WebRequest -Uri '%CLOUD_URL%/library_index.json' -UseBasicParsing -TimeoutSec 30; if ($response.StatusCode -ne 200) { exit 1 }"
if errorlevel 1 (
  echo [VIRGIL] Cloud library check failed.
  exit /b 1
)

echo [VIRGIL] Building Google Play AAB...
pushd "%PROJECT_DIR%"
call "%FLUTTER_CMD%" build appbundle --release ^
  --dart-define=VIRGIL_MODE=mobile ^
  --dart-define=VIRGIL_LIBRARY_BASE_URL="%CLOUD_URL%"
set "BUILD_EXIT=%ERRORLEVEL%"
popd
if not "%BUILD_EXIT%"=="0" (
  echo [VIRGIL] AAB build failed.
  exit /b %BUILD_EXIT%
)

if not exist "%AAB%" (
  echo [VIRGIL] Build completed but AAB was not found:
  echo %AAB%
  exit /b 1
)

echo.
echo [VIRGIL] AAB certificate:
"%KEYTOOL%" -printcert -jarfile "%AAB%"
if errorlevel 1 exit /b 1

echo.
powershell.exe -NoProfile -Command ^
  "$file = Get-Item -LiteralPath '%AAB%'; $hash = Get-FileHash -LiteralPath '%AAB%' -Algorithm SHA256; Write-Host ('[VIRGIL] AAB: ' + $file.FullName); Write-Host ('[VIRGIL] Size: ' + $file.Length + ' bytes'); Write-Host ('[VIRGIL] SHA-256: ' + $hash.Hash)"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%V in (`powershell.exe -NoProfile -Command "$line = Get-Content -LiteralPath '%PROJECT_DIR%pubspec.yaml' | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1; if (-not $line) { exit 1 }; ($line -replace '^version:\s*','').Trim()"`) do set "VIRGIL_VERSION=%%V"
if not defined VIRGIL_VERSION (
  echo [VIRGIL] Could not read version from pubspec.yaml.
  exit /b 1
)

set "RELEASE_DIR=%WORKSPACE_DIR%\Release\Builds\%VIRGIL_VERSION%"
if not exist "%RELEASE_DIR%" mkdir "%RELEASE_DIR%"
copy /y "%AAB%" "%RELEASE_DIR%\Virgil-%VIRGIL_VERSION%.aab" >nul
"%KEYTOOL%" -printcert -jarfile "%AAB%" > "%RELEASE_DIR%\certificate.txt"
powershell.exe -NoProfile -Command ^
  "$hash = Get-FileHash -LiteralPath '%AAB%' -Algorithm SHA256; Set-Content -LiteralPath '%RELEASE_DIR%\SHA256.txt' -Value ($hash.Hash + '  Virgil-%VIRGIL_VERSION%.aab') -Encoding ASCII"
if not exist "%RELEASE_DIR%\release-notes.md" (
  > "%RELEASE_DIR%\release-notes.md" echo # Virgil %VIRGIL_VERSION%
  >> "%RELEASE_DIR%\release-notes.md" echo.
  >> "%RELEASE_DIR%\release-notes.md" echo Release notes pending.
)

echo.
echo [VIRGIL] Google Play AAB is ready.
echo [VIRGIL] Release package:
echo [VIRGIL]   %RELEASE_DIR%
endlocal
