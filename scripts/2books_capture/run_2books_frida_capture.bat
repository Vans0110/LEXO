@echo off
setlocal

set "ROOT=D:\Programs\LEXO"
set "PYTHON=%ROOT%\.venv\Scripts\python.exe"
set "SCRIPT=%ROOT%\scripts\capture_2books_frida_page_writes.py"
set "PACKAGE=su.x2books.app"
set "ADB=C:\Users\Ivan\AppData\Local\Android\Sdk\platform-tools\adb.exe"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "RUN_DIR=%ROOT%\tmp\x2_frida_capture\run_%STAMP%"

mkdir "%RUN_DIR%" >nul 2>nul

(
  echo 2Books Frida capture
  echo.
  echo Run dir: %RUN_DIR%
  echo Package: %PACKAGE%
  echo.
  echo 1. Открой или оставь открытым 2Books.
  echo 2. Этот hook подцепится к процессу и будет ждать.
  echo 3. После строки [ready] запускай import книги.
  echo 4. Для остановки нажми Ctrl+C в этом окне.
) > "%RUN_DIR%\summary.txt"

type "%RUN_DIR%\summary.txt"
echo.
echo Starting Frida page-write hook...
echo.

"%ADB%" shell su root sh -c "/data/local/tmp/frida-server >/data/local/tmp/frida.log 2>&1 &"
timeout /t 1 /nobreak >nul

"%PYTHON%" "%SCRIPT%" --package "%PACKAGE%" --output-dir "%RUN_DIR%"

echo.
echo Session ended. Run dir: %RUN_DIR%
pause

endlocal
