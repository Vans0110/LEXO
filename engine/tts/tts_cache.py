from __future__ import annotations

import hashlib
import wave
from pathlib import Path


def build_cache_key(
    book_id: str,
    engine_id: str,
    voice_id: str,
    text: str,
    profile_key: str,
) -> str:
    payload = f"{book_id}|{engine_id}|{voice_id}|{profile_key}|{text}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def build_audio_path(cache_dir: Path, cache_key: str) -> Path:
    return cache_dir / f"{cache_key}.wav"


def build_timings_path(cache_dir: Path, cache_key: str) -> Path:
    return cache_dir / f"{cache_key}.timings.json"


def read_audio_duration_ms(path: Path, text_fallback: str = "") -> int:
    if not path.exists():
        return max(800, len(text_fallback) * 45)
    try:
        with wave.open(str(path), "rb") as wav_file:
            frames = wav_file.getnframes()
            framerate = wav_file.getframerate() or 24000
        return int(frames / framerate * 1000)
    except wave.Error:
        return max(800, len(text_fallback) * 45)
