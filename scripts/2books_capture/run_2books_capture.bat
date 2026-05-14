@echo off
setlocal

set "ROOT=D:\Programs\LEXO"
set "ADB=C:\Users\Ivan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
set "PACKAGE=su.x2books.app"
set "BOOK_SLUG=d457d4eaa0d14f17afde67a84dca9e74-f52886a18d"
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "RUN_DIR=%ROOT%\tmp\x2_capture\run_%STAMP%"

mkdir "%RUN_DIR%\logs" >nul 2>nul
mkdir "%RUN_DIR%\ebooks" >nul 2>nul
mkdir "%RUN_DIR%\page" >nul 2>nul
mkdir "%RUN_DIR%\state" >nul 2>nul

(
  echo 2Books capture run
  echo.
  echo Run dir: %RUN_DIR%
  echo Package: %PACKAGE%
  echo Book slug: %BOOK_SLUG%
  echo.
  echo 1. Запусти импорт книги в 2Books.
  echo 2. Подожди, пока в PAGE окне появится переход 709 ^> 1802 bytes или в LOGCAT появится onlinePageTranslated.
  echo 3. После завершения закрой watcher-окна вручную.
) > "%RUN_DIR%\summary.txt"

start "2Books SUMMARY" cmd /k "echo Run dir: %RUN_DIR% && echo. && type "%RUN_DIR%\summary.txt""
start "2Books LOGCAT" cmd /k ""%~dp0capture_logcat.bat" "%ADB%" "%RUN_DIR%\logs""
start "2Books EBOOKS" cmd /k ""%~dp0capture_ebooks.bat" "%ADB%" "%RUN_DIR%\ebooks" "%PACKAGE%""
start "2Books PAGE" cmd /k ""%~dp0capture_page_versions.bat" "%ADB%" "%RUN_DIR%\page" "%PACKAGE%" "%BOOK_SLUG%""
start "2Books STATE" cmd /k ""%~dp0capture_state.bat" "%ADB%" "%RUN_DIR%\state" "%PACKAGE%" "%BOOK_SLUG%""

echo Capture windows started.
echo Run dir: %RUN_DIR%
endlocal
