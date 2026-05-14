@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0\.."

set "OLLAMA_EXE=%LocalAppData%\Programs\Ollama\ollama.exe"
set "MODEL_NAME=qwen2.5-14b-q5"
set "MODEL_ROOT=%CD%\data\models\qwen2.5-14b"
set "GGUF_PATH=%MODEL_ROOT%\gguf\Qwen2.5-14B-Instruct-Q5_K_M.gguf"
set "MODELFILE_PATH=%MODEL_ROOT%\Modelfile"
set "WRITE_MODELFILE_PS1=%CD%\scripts\write_qwen25_ollama_modelfile.ps1"

if not exist "%OLLAMA_EXE%" (
  echo [QWEN] Ollama not found: %OLLAMA_EXE%
  echo [QWEN] Install Ollama first.
  pause
  exit /b 1
)

if not exist "%GGUF_PATH%" (
  echo [QWEN] GGUF model not found: %GGUF_PATH%
  echo [QWEN] Download Qwen2.5-14B-Instruct-Q5_K_M.gguf first.
  pause
  exit /b 1
)

if not exist "%WRITE_MODELFILE_PS1%" (
  echo [QWEN] Helper script not found: %WRITE_MODELFILE_PS1%
  pause
  exit /b 1
)

2>nul mkdir "%MODEL_ROOT%"

echo [QWEN] Preparing Ollama model...
powershell -NoProfile -ExecutionPolicy Bypass -File "%WRITE_MODELFILE_PS1%" -GgufPath "%GGUF_PATH%" -ModelFilePath "%MODELFILE_PATH%"
if errorlevel 1 (
  echo [QWEN] Failed to write Modelfile.
  pause
  exit /b 1
)

if not exist "%MODELFILE_PATH%" (
  echo [QWEN] Modelfile not found after write: %MODELFILE_PATH%
  pause
  exit /b 1
)

echo [QWEN] Registering model in Ollama...
"%OLLAMA_EXE%" create "%MODEL_NAME%" -f "%MODELFILE_PATH%"
set "EXIT_CODE=!ERRORLEVEL!"
if not "!EXIT_CODE!"=="0" (
  echo.
  echo [QWEN] Ollama create failed with code !EXIT_CODE!.
  pause
  exit /b !EXIT_CODE!
)

echo [QWEN] Starting interactive chat...
echo [QWEN] Type /bye or Ctrl+C to exit.
"%OLLAMA_EXE%" run "%MODEL_NAME%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [QWEN] Ollama run finished with error code %EXIT_CODE%.
  pause
)

endlocal
exit /b %EXIT_CODE%
