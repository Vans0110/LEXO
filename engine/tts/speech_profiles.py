from __future__ import annotations

from .tts_models import SpeechProfile


GENERATION_PROFILE = {
    "id": 1,
    "name": "Base",
    "tts_rate": 0.89,
    "pause_scale": 1.0,
}

PLAYBACK_PRESETS = [
    {"id": 1, "name": "Slow", "playback_speed": 0.85},
    {"id": 2, "name": "Normal", "playback_speed": 1.0},
    {"id": 3, "name": "Fast", "playback_speed": 1.15},
]


def list_levels() -> list[dict]:
    return [dict(item) for item in PLAYBACK_PRESETS]


def build_profile(_level_id: int | None = None) -> SpeechProfile:
    return SpeechProfile(
        level_id=int(GENERATION_PROFILE["id"]),
        level_name=str(GENERATION_PROFILE["name"]),
        target_wpm=0,
        rate=float(GENERATION_PROFILE["tts_rate"]),
        pause_scale=float(GENERATION_PROFILE["pause_scale"]),
    )
