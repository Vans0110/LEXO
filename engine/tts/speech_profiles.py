from __future__ import annotations

from .tts_models import SpeechProfile


BASE_WPM = 164
RATE_MIN = 0.75
RATE_MAX = 1.25

LEVELS = [
    {"id": 1, "name": "Start", "target_wpm": 90},
    {"id": 3, "name": "Transition", "target_wpm": 120},
    {"id": 4, "name": "Podcast", "target_wpm": 145},
    {"id": 6, "name": "Hardcore", "target_wpm": 200},
]


def list_levels() -> list[dict]:
    return [dict(item) for item in LEVELS]


def build_profile(level_id: int) -> SpeechProfile:
    level = next((item for item in LEVELS if int(item["id"]) == int(level_id)), None)
    if level is None:
        raise ValueError(f"Unsupported TTS level: {level_id}")
    target_wpm = int(level["target_wpm"])
    raw_rate = target_wpm / BASE_WPM
    if target_wpm <= 95:
        rate = 0.60
        pause_scale = _map_low_speed(target_wpm)
        return SpeechProfile(
            level_id=int(level["id"]),
            level_name=str(level["name"]),
            target_wpm=target_wpm,
            rate=round(rate, 3),
            pause_scale=round(pause_scale, 3),
        )
    if raw_rate < RATE_MIN:
        rate = RATE_MIN
        pause_scale = _map_low_speed(target_wpm)
    else:
        rate = _clamp(raw_rate, RATE_MIN, RATE_MAX)
        pause_scale = 1.0
    return SpeechProfile(
        level_id=int(level["id"]),
        level_name=str(level["name"]),
        target_wpm=target_wpm,
        rate=round(rate, 3),
        pause_scale=round(pause_scale, 3),
    )


def _map_low_speed(target_wpm: int) -> float:
    if target_wpm <= 95:
        return 3.0
    if target_wpm <= 110:
        return 1.25
    if target_wpm <= 125:
        return 1.1
    return 1.0


def _clamp(value: float, min_value: float, max_value: float) -> float:
    return min(max(value, min_value), max_value)
