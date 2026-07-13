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
    audio_variant: str
    native_rate: float
    word_gap_ms: int
    expand_word_gaps: bool
    playback_speed: float
    rate: float
    pause_scale: float

    @property
    def cache_key(self) -> str:
        variant_value = self.audio_variant or "base"
        native_rate_value = f"{self.native_rate:.3f}"
        word_gap_value = int(self.word_gap_ms or 0)
        pause_value = f"{self.pause_scale:.3f}"
        return (
            f"variant={variant_value}|native_rate={native_rate_value}|"
            f"word_gap={word_gap_value}|pause={pause_value}"
        )


@dataclass(slots=True)
class GeneratedAudio:
    audio_path: str
    duration_ms: int
    timings_path: str | None = None
    timings: list[dict] | None = None
