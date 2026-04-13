from __future__ import annotations

import re

from .models import CoverageStatus, LookupResult, SourceAnalysisResult, TargetCoverage, UnitType


TARGET_TOKEN_RE = re.compile(r"\d{1,2}:\d{2}|\d+|[A-Za-zА-Яа-яЁё]+(?:'[A-Za-zА-Яа-яЁё]+)?|[^\w\s]")

NORMALIZED_EQUIVALENTS = {
    "том": "том",
    "солнце": "солнце",
    "яркий": "яркий",
    "яркое": "яркий",
    "яркая": "яркий",
    "яркие": "яркий",
    "счастлив": "счастлив",
    "счастливый": "счастлив",
    "счастлива": "счастлив",
    "красивый": "красивый",
    "красивое": "красивый",
    "красивыйй": "красивый",
    "день": "день",
    "завтрак": "завтрак",
    "мяу": "мяу",
    "глава": "глава",
    "утра": "утра",
    "вечера": "вечера",
    "говорит": "говорит",
    "анна": "анна",
    "просыпается": "просыпается",
    "просыпаться": "просыпается",
    "утро": "утро",
    "доброе": "доброе",
    "цветы": "цветы",
    "цветок": "цветок",
    "кухня": "кухня",
    "это": "это",
}


class V2CoverageResolver:
    """Target coverage resolver for the V2 core.

    Coverage is a visual aid and must never be treated as the source of meaning.
    This resolver therefore prefers conservative statuses over fake exact spans.
    """

    def resolve_analysis(
        self,
        analysis: SourceAnalysisResult,
        lookups: dict[str, LookupResult],
        target_text: str,
    ) -> dict[str, TargetCoverage]:
        target_tokens = self.tokenize_target(target_text)
        coverages: dict[str, TargetCoverage] = {}

        for unit in analysis.units:
            lookup = lookups[unit.unit_id]
            if unit.attached_to_unit_id:
                status = CoverageStatus.PHRASE_OWNED if unit.phrase_owner_unit_id else CoverageStatus.ABSORBED
                owner_id = unit.phrase_owner_unit_id or unit.attached_to_unit_id
                coverages[unit.unit_id] = TargetCoverage(
                    unit_id=unit.unit_id,
                    target_text="",
                    target_token_start=None,
                    target_token_end=None,
                    coverage_status=status,
                    owner_unit_id=owner_id,
                    confidence=1.0,
                )
                continue

            coverages[unit.unit_id] = self.resolve_unit(unit.type, unit.unit_id, lookup, target_tokens)
        return coverages

    def resolve_unit(
        self,
        unit_type: UnitType,
        unit_id: str,
        lookup: LookupResult,
        target_tokens: list[str],
    ) -> TargetCoverage:
        if unit_type in {UnitType.FUNCTION, UnitType.GRAMMAR}:
            return TargetCoverage(
                unit_id=unit_id,
                target_text="",
                target_token_start=None,
                target_token_end=None,
                coverage_status=CoverageStatus.ABSORBED,
                confidence=1.0,
            )

        candidates = self._lookup_candidates(lookup)
        if not candidates:
            return TargetCoverage(
                unit_id=unit_id,
                target_text="",
                target_token_start=None,
                target_token_end=None,
                coverage_status=CoverageStatus.NONE,
                confidence=0.0,
            )

        for candidate in candidates:
            match = self._match_candidate(target_tokens, candidate)
            if match is not None:
                start, end = match
                status = CoverageStatus.EXACT if start == 0 else CoverageStatus.REORDERED
                return TargetCoverage(
                    unit_id=unit_id,
                    target_text=" ".join(target_tokens[start : end + 1]),
                    target_token_start=start,
                    target_token_end=end,
                    coverage_status=status,
                    confidence=1.0 if status == CoverageStatus.EXACT else 0.9,
                )

        return TargetCoverage(
            unit_id=unit_id,
            target_text="",
            target_token_start=None,
            target_token_end=None,
            coverage_status=CoverageStatus.FUZZY if lookup.base_translation else CoverageStatus.NONE,
            confidence=0.25 if lookup.base_translation else 0.0,
        )

    def tokenize_target(self, target_text: str) -> list[str]:
        return [match.group(0) for match in TARGET_TOKEN_RE.finditer(target_text)]

    def _lookup_candidates(self, lookup: LookupResult) -> list[list[str]]:
        raw_candidates = [lookup.base_translation, *lookup.alt_translations]
        candidates: list[list[str]] = []
        for raw in raw_candidates:
            for variant in self._split_variants(raw):
                tokens = [self._normalize_target_token(token) for token in TARGET_TOKEN_RE.findall(variant) if self._normalize_target_token(token)]
                if tokens:
                    candidates.append(tokens)
        return candidates

    def _split_variants(self, raw: str) -> list[str]:
        raw = str(raw or "").strip()
        if not raw:
            return []
        return [part.strip() for part in raw.split("/") if part.strip()]

    def _match_candidate(self, target_tokens: list[str], candidate_tokens: list[str]) -> tuple[int, int] | None:
        normalized_target = [self._normalize_target_token(token) for token in target_tokens]
        width = len(candidate_tokens)
        for start in range(0, len(normalized_target) - width + 1):
            window = normalized_target[start : start + width]
            if window == candidate_tokens:
                return start, start + width - 1
        return None

    def _normalize_target_token(self, token: str) -> str:
        normalized = token.lower().strip()
        return NORMALIZED_EQUIVALENTS.get(normalized, normalized)
