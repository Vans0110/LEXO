from __future__ import annotations

import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
MODELS_DIR = DATA_DIR / "models"
HF_HOME_DIR = MODELS_DIR / "hf_home"
os.environ.setdefault("HF_HOME", str(HF_HOME_DIR))
os.environ.setdefault("TRANSFORMERS_CACHE", str(HF_HOME_DIR / "transformers"))
NLLB_DIR = MODELS_DIR / "nllb-200-distilled-600m"
NLLB_ORIGINAL_DIR = NLLB_DIR / "original"
NLLB_CT2_DIR = NLLB_DIR / "ct2"
NLLB33_DIR = MODELS_DIR / "nllb-200-3.3b"
NLLB33_ORIGINAL_DIR = NLLB33_DIR / "original"
NLLB33_CT2_DIR = NLLB33_DIR / "ct2"
M2M100_DIR = MODELS_DIR / "m2m100_1.2B"
M2M100_ORIGINAL_DIR = M2M100_DIR / "original"
M2M100_CT2_DIR = M2M100_DIR / "ct2"
MADLAD_DIR = MODELS_DIR / "madlad400-10b-mt"
MADLAD_ORIGINAL_DIR = MADLAD_DIR / "original"
MADLAD_CT2_DIR = MADLAD_DIR / "ct2"
MARIAN_OPUS_DIR = MODELS_DIR / "marian-opus-en-ru"
MARIAN_OPUS_ORIGINAL_DIR = MARIAN_OPUS_DIR / "original"
MARIAN_OPUS_CT2_DIR = MARIAN_OPUS_DIR / "ct2"
MARIAN_OPUS_EN_UK_DIR = MODELS_DIR / "marian-opus-en-uk"
MARIAN_OPUS_EN_UK_ORIGINAL_DIR = MARIAN_OPUS_EN_UK_DIR / "original"
MARIAN_OPUS_EN_UK_CT2_DIR = MARIAN_OPUS_EN_UK_DIR / "ct2"
MARIAN_OPUS_RU_EN_DIR = MODELS_DIR / "marian-opus-ru-en"
MARIAN_OPUS_RU_EN_ORIGINAL_DIR = MARIAN_OPUS_RU_EN_DIR / "original"
MARIAN_OPUS_RU_EN_CT2_DIR = MARIAN_OPUS_RU_EN_DIR / "ct2"
ARGOS_EN_RU_MODEL = MODELS_DIR / "translate-en_ru-1_9.argosmodel"
KOKORO_VENV_DIR = ROOT / ".venv_kokoro"
KOKORO_PYTHON = KOKORO_VENV_DIR / "Scripts" / "python.exe"
KOKORO_RUNNER = ROOT / "engine" / "tts" / "kokoro_runner.py"
STANZA_RESOURCES_DIR = MODELS_DIR / "stanza_resources"
MULTILINGUAL_E5_SMALL_DIR = MODELS_DIR / "multilingual-e5-small"

def tts_mode() -> str:
    return os.getenv("LEXO_TTS_PROVIDER", "mock").strip().lower() or "mock"


def segment_qa_rerank_enabled() -> bool:
    value = os.getenv("LEXO_SEGMENT_QA_RERANK", "1").strip().lower()
    return value not in {"0", "false", "no", "off"}


def segment_rerank_mode() -> str:
    value = os.getenv("LEXO_SEGMENT_RERANK_MODE", "hybrid").strip().lower()
    aliases = {
        "0": "off",
        "false": "off",
        "no": "off",
        "none": "off",
        "qa": "dictionary",
        "dict": "dictionary",
        "structure": "structural",
        "semantic_e5": "semantic",
    }
    value = aliases.get(value, value)
    if value not in {"off", "dictionary", "structural", "semantic", "hybrid"}:
        return "hybrid"
    return value


def segment_qa_candidate_count() -> int:
    try:
        value = int(os.getenv("LEXO_SEGMENT_QA_CANDIDATES", "10"))
    except ValueError:
        value = 10
    return max(1, min(value, 20))
