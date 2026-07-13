from __future__ import annotations

from .tts_models import SpeechProfile


GENERATION_PROFILE = {
    "id": 1,
    "name": "Base",
    "tts_rate": 0.89,
    "pause_scale": 1.0,
}

PLAYBACK_PRESETS = [
    {
        "id": 1,
        "name": "Slow",
        "playback_speed": 0.85,
        "effective_playback_speed": 0.85,
        "audio_variant": "slow_native",
        "native_rate": 0.85,
        "word_gap_ms": 300,
        "expand_word_gaps": False,
    },
    {
        "id": 2,
        "name": "Normal",
        "playback_speed": 1.0,
        "effective_playback_speed": 1.0,
        "audio_variant": "base",
        "native_rate": 0.89,
        "word_gap_ms": 0,
        "expand_word_gaps": False,
    },
    {
        "id": 3,
        "name": "Fast",
        "playback_speed": 1.15,
        "effective_playback_speed": 1.15,
        "audio_variant": "base",
        "native_rate": 0.89,
        "word_gap_ms": 0,
        "expand_word_gaps": False,
    },
]


def list_levels() -> list[dict]:
    return [dict(item) for item in PLAYBACK_PRESETS]


def build_profile(level_id: int | None = None) -> SpeechProfile:
    selected = PLAYBACK_PRESETS[1]
    if level_id is not None:
        for item in PLAYBACK_PRESETS:
            if int(item["id"]) == int(level_id):
                selected = item
                break
    return SpeechProfile(
        level_id=int(selected["id"]),
        level_name=str(selected["name"]),
        target_wpm=0,
        audio_variant=str(selected["audio_variant"]),
        native_rate=float(selected["native_rate"]),
        word_gap_ms=int(selected["word_gap_ms"]),
        expand_word_gaps=bool(selected.get("expand_word_gaps", False)),
        playback_speed=float(selected["effective_playback_speed"]),
        rate=float(selected["native_rate"]),
        pause_scale=float(GENERATION_PROFILE["pause_scale"]),
    )
