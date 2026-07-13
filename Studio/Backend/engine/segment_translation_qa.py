from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from .tokenization import WORD_RE


ZERO_WEIGHT_SOURCE_WORDS = {"a", "an", "the", "am", "is", "are"}
ZERO_WEIGHT_POS = {"DET"}
WEAK_POS = {"AUX", "PART"}
EXTRA_INTENSIFIERS = {
    "очень",
    "немного",
    "сильно",
    "слегка",
    "дуже",
    "трохи",
}
EXTRA_PHASE_WORDS = {
    "начинает",
    "начал",
    "начала",
    "начали",
    "начинать",
    "стал",
    "стала",
    "стали",
    "становится",
    "починає",
    "почав",
    "почала",
    "почали",
    "став",
    "стала",
    "стали",
}
@dataclass(frozen=True)
class SegmentQaWord:
    surface: str
    lemma: str
    pos: str
    translations: tuple[str, ...]


@dataclass(frozen=True)
class SegmentQaResult:
    selected: str
    score: float
    explanation: dict


class SegmentTranslationQa:
    def select(self, source_text: str, words: Iterable[SegmentQaWord], candidates: list[str]) -> SegmentQaResult:
        clean_candidates = [candidate.strip() for candidate in candidates if candidate and candidate.strip()]
        if not clean_candidates:
            return SegmentQaResult("", 0.0, {"reason": "no_candidates"})

        scored = [
            (candidate, self._score_candidate(source_text, words, candidate))
            for candidate in clean_candidates
        ]
        scored.sort(key=lambda item: item[1][0], reverse=True)
        selected, (score, coverage, penalties) = scored[0]
        return SegmentQaResult(
            selected=selected,
            score=score,
            explanation={
                "source": source_text,
                "selected": selected,
                "score": score,
                "coverage": coverage,
                "penalties": penalties,
                "candidates": [
                    {
                        "text": candidate,
                        "score": candidate_score,
                    }
                    for candidate, (candidate_score, _, _) in scored
                ],
            },
        )

    def _score_candidate(
        self,
        source_text: str,
        words: Iterable[SegmentQaWord],
        candidate: str,
    ) -> tuple[float, list[dict], list[dict]]:
        target_tokens = self._tokens(candidate)
        source_tokens = self._tokens(source_text)
        coverage: list[dict] = []
        covered_score = 0.0
        possible_score = 0.0

        for word in words:
            source_key = (word.lemma or word.surface).strip().lower()
            surface_key = word.surface.strip().lower()
            pos = word.pos.strip().upper()
            if source_key in ZERO_WEIGHT_SOURCE_WORDS or surface_key in ZERO_WEIGHT_SOURCE_WORDS or pos in ZERO_WEIGHT_POS:
                coverage.append({
                    "source": word.surface,
                    "lemma": word.lemma,
                    "pos": word.pos,
                    "status": "ignored",
                })
                continue
            weight = 0.35 if pos in WEAK_POS else 1.0
            translations = tuple(
                translation
                for translation in word.translations
                if translation.strip()
            )
            if not translations:
                coverage.append({
                    "source": word.surface,
                    "lemma": word.lemma,
                    "pos": word.pos,
                    "status": "no_dictionary_evidence",
                })
                continue
            possible_score += weight
            matched = self._best_translation_match(translations, target_tokens)
            if matched:
                covered_score += weight * matched[1]
                coverage.append({
                    "source": word.surface,
                    "lemma": word.lemma,
                    "pos": word.pos,
                    "status": "covered",
                    "translation": matched[0],
                    "match_score": matched[1],
                })
            else:
                coverage.append({
                    "source": word.surface,
                    "lemma": word.lemma,
                    "pos": word.pos,
                    "status": "missing",
                })

        coverage_score = covered_score / possible_score if possible_score > 0 else 0.0
        penalties = self._penalties(source_tokens, target_tokens, candidate)
        penalty_score = sum(item["value"] for item in penalties)
        length_score = self._length_score(source_tokens, target_tokens)
        return coverage_score + length_score - penalty_score, coverage, penalties

    def _best_translation_match(
        self,
        translations: tuple[str, ...],
        target_tokens: list[str],
    ) -> tuple[str, float] | None:
        best: tuple[str, float] | None = None
        for translation in translations:
            translation_tokens = self._tokens(translation)
            if not translation_tokens:
                continue
            match_count = sum(
                1
                for token in translation_tokens
                if self._token_matches_any(token, target_tokens)
            )
            if match_count <= 0:
                continue
            score = match_count / len(translation_tokens)
            if best is None or score > best[1]:
                best = (translation, score)
        return best

    def _token_matches_any(self, token: str, target_tokens: list[str]) -> bool:
        if token in target_tokens:
            return True
        if len(token) < 5:
            return False
        prefix = token[:5]
        return any(target.startswith(prefix) or token.startswith(target[:5]) for target in target_tokens if len(target) >= 5)

    def _penalties(
        self,
        source_tokens: list[str],
        target_tokens: list[str],
        candidate: str,
    ) -> list[dict]:
        penalties: list[dict] = []
        source_set = set(source_tokens)
        if not ({"very", "really", "little", "slightly", "strongly"} & source_set):
            for token in target_tokens:
                if token in EXTRA_INTENSIFIERS:
                    penalties.append({"type": "extra_intensifier", "token": token, "value": 0.22})
        if not ({"start", "starts", "started", "begin", "begins", "began"} & source_set):
            for token in target_tokens:
                if token in EXTRA_PHASE_WORDS:
                    penalties.append({"type": "extra_phase", "token": token, "value": 0.28})
        if candidate.lstrip().startswith("-"):
            penalties.append({"type": "leading_dash", "token": "-", "value": 0.2})
        return penalties

    def _length_score(self, source_tokens: list[str], target_tokens: list[str]) -> float:
        source_content_count = max(
            1,
            len([token for token in source_tokens if token not in ZERO_WEIGHT_SOURCE_WORDS]),
        )
        if not target_tokens:
            return -0.5
        ratio = len(target_tokens) / source_content_count
        if ratio <= 0:
            return -0.5
        return max(-0.25, 0.12 - abs(1.0 - min(ratio, 2.0)) * 0.12)

    def _tokens(self, text: str) -> list[str]:
        normalized = str(text or "").lower().replace("ё", "е")
        return WORD_RE.findall(normalized)
