from __future__ import annotations

from pathlib import Path

from .tts_cache import build_audio_path, build_cache_key, read_audio_duration_ms
from .tts_models import SpeechProfile, TtsChunk
from .tts_provider import TtsProvider


def generate_tts_segment(
    provider: TtsProvider,
    cache_dir: Path,
    book_id: str,
    voice_id: str,
    chunk: TtsChunk,
    profile: SpeechProfile,
) -> dict:
    cache_key = build_cache_key(
        book_id,
        provider.engine_id,
        voice_id,
        chunk.synthesis_text,
        profile.cache_key,
    )
    audio_path = build_audio_path(cache_dir, cache_key)
    if audio_path.exists():
        duration_ms = read_audio_duration_ms(audio_path, chunk.synthesis_text)
    else:
        audio = provider.synthesize(
            chunk.synthesis_text,
            voice_id,
            audio_path,
            rate=profile.rate,
        )
        duration_ms = audio.duration_ms
    return {
        "order_index": chunk.order_index,
        "paragraph_index": chunk.paragraph_index,
        "source_text": chunk.source_text,
        "synthesis_text": chunk.synthesis_text,
        "pause_after_ms": chunk.pause_after_ms,
        "audio_path": str(audio_path),
        "duration_ms": duration_ms,
        "status": "ready",
        "hash": cache_key,
    }
