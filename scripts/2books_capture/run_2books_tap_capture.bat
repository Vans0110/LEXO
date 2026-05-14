@echo off
setlocal

set "ROOT=D:\Programs\LEXO"
set "ADB=C:\Users\Ivan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
set "SERIAL=emulator-5554"
set "MANIFEST=%ROOT%\tmp\2books_manifest_the_bus_driver.json"
set "SCRIPT=%ROOT%\scripts\capture_2books_tap_translations.py"

echo 2Books tap capture
echo.
echo Manifest: %MANIFEST%
echo ADB: %ADB%
echo Serial: %SERIAL%
echo.
echo Перед запуском:
echo 1. Открой нужную книгу и нужную страницу в 2Books.
echo 2. Заполни x/y в manifest.
echo 3. Оставь приложение на экране с текстом.
echo.
pause

python3 "%SCRIPT%" ^
  --manifest "%MANIFEST%" ^
  --adb-path "%ADB%" ^
  --serial "%SERIAL%" ^
  --pre-delay-ms 5000 ^
  --post-delay-ms 400 ^
  --dump-xml

echo.
echo Capture finished.
pause
endlocal
