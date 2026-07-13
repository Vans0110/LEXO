from __future__ import annotations

from pathlib import Path

from .audio_postprocess import expand_word_gaps_in_place
from .tts_cache import build_audio_path, build_cache_key, build_timings_path, read_audio_duration_ms
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
    synthesis_text = chunk.synthesis_text
    cache_key = build_cache_key(
        book_id,
        provider.engine_id,
        voice_id,
        synthesis_text,
        profile.cache_key,
    )
    audio_path = build_audio_path(cache_dir, cache_key)
    timings_path = build_timings_path(cache_dir, cache_key)
    if audio_path.exists():
        duration_ms = read_audio_duration_ms(audio_path, synthesis_text)
        resolved_timings_path = str(timings_path) if timings_path.exists() else ""
    else:
        audio = provider.synthesize(
            synthesis_text,
            voice_id,
            audio_path,
            rate=profile.native_rate,
        )
        duration_ms = audio.duration_ms
        resolved_timings_path = str(Path(audio.timings_path)) if audio.timings_path else ""
        if (
            profile.expand_word_gaps
            and profile.audio_variant == "slow_native"
            and profile.word_gap_ms > 0
            and resolved_timings_path
            and Path(resolved_timings_path).exists()
        ):
            duration_ms = expand_word_gaps_in_place(
                audio_path=audio_path,
                timings_path=Path(resolved_timings_path),
                min_gap_ms=profile.word_gap_ms,
            )
    return {
        "order_index": chunk.order_index,
        "paragraph_index": chunk.paragraph_index,
        "source_text": chunk.source_text,
        "synthesis_text": synthesis_text,
        "pause_after_ms": chunk.pause_after_ms,
        "audio_path": str(audio_path),
        "timings_path": resolved_timings_path,
        "duration_ms": duration_ms,
        "status": "ready",
        "hash": cache_key,
    }
