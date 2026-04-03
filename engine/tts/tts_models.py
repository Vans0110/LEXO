from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class TtsChunk:
    order_index: int
    paragraph_index: int
    source_text: str
    synthesis_text: str
    pause_after_ms: int


@dataclass(slots=True)
class SpeechProfile:
    level_id: int
    level_name: str
    target_wpm: int
    rate: float
    pause_scale: float

    @property
    def cache_key(self) -> str:
        rate_value = f"{self.rate:.3f}"
        pause_value = f"{self.pause_scale:.3f}"
        return f"level={self.level_id}|rate={rate_value}|pause={pause_value}"


@dataclass(slots=True)
class GeneratedAudio:
    audio_path: str
    duration_ms: int
