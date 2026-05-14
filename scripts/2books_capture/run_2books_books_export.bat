@echo off
setlocal

set "ROOT=D:\Programs\LEXO"
set "ADB=C:\Users\Ivan\AppData\Local\Android\Sdk\platform-tools\adb.exe"
set "PACKAGE=su.x2books.app"
set "REMOTE_DIR=/data/data/%PACKAGE%/app_flutter/books"
set "STAGE_DIR=/sdcard/Download/lexo_books_export"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "RUN_DIR=%ROOT%\tmp\x2_books_export\run_%STAMP%"
set "BOOKS_DIR=%RUN_DIR%\books"

mkdir "%RUN_DIR%" >nul 2>nul
mkdir "%BOOKS_DIR%" >nul 2>nul

(
  echo 2Books books export
  echo.
  echo Run dir: %RUN_DIR%
  echo Package: %PACKAGE%
  echo Remote dir: %REMOTE_DIR%
  echo.
  echo Этот launcher вытягивает финальные книги из app_flutter/books.
  echo Нужны именно pages/*.json.gz, meta.json, toc.json.
) > "%RUN_DIR%\summary.txt"

echo Exporting 2Books books...
echo Run dir: %RUN_DIR%
echo.

echo [1/4] Listing remote books...
"%ADB%" shell "find %REMOTE_DIR% -maxdepth 2 -type f \( -name '*.json.gz' -o -name 'meta.json' -o -name 'toc.json' \) | sort" > "%RUN_DIR%\remote_files.txt"

echo [2/4] Staging books to shared storage ...
"%ADB%" shell su root rm -rf "%STAGE_DIR%" > "%RUN_DIR%\adb_stage.txt" 2>&1
"%ADB%" shell su root mkdir -p "%STAGE_DIR%" >> "%RUN_DIR%\adb_stage.txt" 2>&1
"%ADB%" shell su root cp -R "%REMOTE_DIR%" "%STAGE_DIR%" >> "%RUN_DIR%\adb_stage.txt" 2>&1

echo [3/5] Pulling staged books ...
"%ADB%" pull "%STAGE_DIR%/books" "%BOOKS_DIR%" > "%RUN_DIR%\adb_pull.txt"

echo [4/5] Building local report ...
powershell -NoProfile -Command ^
  "$booksRoot = '%BOOKS_DIR%\books';" ^
  "$report = @();" ^
  "if (Test-Path $booksRoot) {" ^
  "  Get-ChildItem $booksRoot -Directory | Sort-Object Name | ForEach-Object {" ^
  "    $slug = $_.Name;" ^
  "    $pages = @(Get-ChildItem $_.FullName -Recurse -File -Filter '*.json.gz' -ErrorAction SilentlyContinue);" ^
  "    $meta = Test-Path (Join-Path $_.FullName 'meta.json');" ^
  "    $toc = Test-Path (Join-Path $_.FullName 'toc.json');" ^
  "    $report += [PSCustomObject]@{ slug = $slug; page_count = $pages.Count; has_meta = $meta; has_toc = $toc };" ^
  "  }" ^
  "}" ^
  "$report | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 '%RUN_DIR%\books_report.json';" ^
  "$report | Format-Table -AutoSize | Out-String -Width 200 | Set-Content -Encoding UTF8 '%RUN_DIR%\books_report.txt';"

echo [5/5] Cleaning stage dir ...
"%ADB%" shell su root rm -rf "%STAGE_DIR%" > "%RUN_DIR%\adb_cleanup.txt" 2>&1

echo Done.
echo.
type "%RUN_DIR%\summary.txt"
echo.
echo Export complete.
echo Remote list: %RUN_DIR%\remote_files.txt
echo Report: %RUN_DIR%\books_report.txt
echo Files: %BOOKS_DIR%
pause

endlocal
