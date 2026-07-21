from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Any

from .tokenization import normalize_apostrophes


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
        model_tokens = [token for token in doc if not token.is_space]
        analyses: list[SourceWordAnalysis] = []
        cursor = 0
        for surface in word_surfaces:
            token_span = self._find_token_span(
                model_tokens,
                surface,
                start_index=cursor,
            )
            if token_span is None:
                analyses.append(self._fallback(surface))
                continue
            start, end = token_span
            cursor = end
            span = model_tokens[start:end]
            token = next(
                (
                    candidate
                    for candidate in span
                    if candidate.is_alpha or candidate.like_num
                ),
                span[0],
            )
            normalized = normalize_apostrophes(surface).lower()
            is_possessive = (
                normalized.endswith("'s")
                and len(span) > 1
                and str(span[-1].tag_ or "").upper() == "POS"
            )
            lemma = (
                str(token.lemma_ or "").strip().lower()
                if is_possessive or len(span) == 1
                else normalized
            ) or normalized
            analyses.append(
                SourceWordAnalysis(
                    surface_text=surface,
                    lemma=lemma,
                    pos=str(token.pos_ or "").strip(),
                    tag=str(token.tag_ or "").strip(),
                )
            )
        return analyses

    def _find_token_span(
        self,
        tokens: list[Any],
        surface: str,
        *,
        start_index: int,
    ) -> tuple[int, int] | None:
        target = normalize_apostrophes(surface).lower()
        for start in range(start_index, len(tokens)):
            combined = ""
            for end in range(start, len(tokens)):
                combined += normalize_apostrophes(tokens[end].text).lower()
                if combined == target:
                    return start, end + 1
                if len(combined) >= len(target) or not target.startswith(combined):
                    break
        return None

    def _fallback(self, surface: str) -> SourceWordAnalysis:
        normalized = str(surface or "").strip().lower()
        return SourceWordAnalysis(surface_text=str(surface or ""), lemma=normalized, pos="", tag="")
