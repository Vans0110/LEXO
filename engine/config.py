from __future__ import annotations

import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
MODELS_DIR = DATA_DIR / "models"
NLLB_DIR = MODELS_DIR / "nllb-200-distilled-600m"
NLLB_ORIGINAL_DIR = NLLB_DIR / "original"
NLLB_CT2_DIR = NLLB_DIR / "ct2"
KOKORO_VENV_DIR = ROOT / ".venv_kokoro"
KOKORO_PYTHON = KOKORO_VENV_DIR / "Scripts" / "python.exe"
KOKORO_RUNNER = ROOT / "engine" / "tts" / "kokoro_runner.py"

DEFAULT_TRANSLATOR = os.getenv("LEXO_TRANSLATOR", "mock").strip().lower() or "mock"
DEFAULT_TTS_PROVIDER = os.getenv("LEXO_TTS_PROVIDER", "mock").strip().lower() or "mock"


def translator_mode() -> str:
    return DEFAULT_TRANSLATOR


def tts_mode() -> str:
    return DEFAULT_TTS_PROVIDER
