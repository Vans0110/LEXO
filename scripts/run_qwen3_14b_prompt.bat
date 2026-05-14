@echo off
setlocal
chcp 65001 >nul

cd /d "%~dp0\.."

set "PYTHON_EXE=%CD%\.venv\Scripts\python.exe"
set "MODEL_DIR=%CD%\data\models\qwen3-14b\original"

if not exist "%PYTHON_EXE%" (
  echo [QWEN] Project venv not found: %PYTHON_EXE%
  echo [QWEN] Create .venv first and install dependencies.
  pause
  exit /b 1
)

if not exist "%MODEL_DIR%" (
  echo [QWEN] Model not found: %MODEL_DIR%
  echo [QWEN] Download Qwen3-14B into data\models\qwen3-14b\original first.
  pause
  exit /b 1
)

echo [QWEN] Starting interactive prompt...
"%PYTHON_EXE%" "%CD%\scripts\qwen3_14b_prompt.py"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [QWEN] Process finished with error code %EXIT_CODE%.
  pause
)

endlocal
exit /b %EXIT_CODE%
