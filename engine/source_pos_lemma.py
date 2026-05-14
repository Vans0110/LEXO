from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Any


@dataclass(frozen=True)
class SourceWordAnalysis:
    surface_text: str
    lemma: str
    pos: str
    tag: str


@lru_cache(maxsize=1)
def _load_en_model() -> Any | None:
    try:
        import spacy
    except Exception:
        return None
    try:
        return spacy.load("en_core_web_sm")
    except Exception:
        return None


class SourcePosLemmaAnalyzer:
    def __init__(self) -> None:
        self._nlp = _load_en_model()

    @property
    def is_available(self) -> bool:
        return self._nlp is not None

    def analyze_words(self, text: str, word_surfaces: list[str]) -> list[SourceWordAnalysis]:
        fallback = [self._fallback(surface) for surface in word_surfaces]
        if self._nlp is None or not word_surfaces:
            return fallback

        doc = self._nlp(str(text or ""))
        model_words = [token for token in doc if token.is_alpha or token.like_num]
        if len(model_words) != len(word_surfaces):
            return fallback

        analyses: list[SourceWordAnalysis] = []
        for surface, token in zip(word_surfaces, model_words, strict=True):
            if surface.lower() != token.text.lower():
                return fallback
            normalized = surface.lower()
            lemma = str(token.lemma_ or "").strip().lower() or normalized
            analyses.append(
                SourceWordAnalysis(
                    surface_text=surface,
                    lemma=lemma,
                    pos=str(token.pos_ or "").strip(),
                    tag=str(token.tag_ or "").strip(),
                )
            )
        return analyses

    def _fallback(self, surface: str) -> SourceWordAnalysis:
        normalized = str(surface or "").strip().lower()
        return SourceWordAnalysis(surface_text=str(surface or ""), lemma=normalized, pos="", tag="")
