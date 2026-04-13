from __future__ import annotations

import re
from dataclasses import dataclass

from .models import LookupMode, SourceAnalysisResult, SourceToken, SourceUnit, UnitType


TOKEN_RE = re.compile(r"\d{1,2}:\d{2}|\d+|[A-Za-z]+(?:'[A-Za-z]+)?|[^\w\s]")
TIME_TOKEN_RE = re.compile(r"^\d{1,2}:\d{2}$")
CHAPTER_WORDS = {
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9",
    "ten": "10",
}
PHRASE_PATTERNS = {
    ("wake", "up"),
    ("wakes", "up"),
    ("look", "at"),
    ("good", "morning"),
    ("have", "to"),
}
GRAMMAR_PATTERNS = {
    ("it", "is"),
    ("there", "is"),
    ("going", "to"),
    ("used", "to"),
    ("do", "not"),
}
FUNCTION_WORDS = {
    "the",
    "a",
    "an",
    "in",
    "on",
    "to",
    "of",
    "at",
    "is",
    "are",
    "was",
    "were",
    "be",
}
PUNCTUATION_MARKERS = {'"', "'", ".", ",", "!", "?", ":", ";", "(", ")"}
TYPE_PRIORITY = {
    UnitType.META: 100,
    UnitType.PHRASE: 90,
    UnitType.GRAMMAR: 80,
    UnitType.FUNCTION: 70,
    UnitType.LEXICAL: 60,
}
LOOKUP_MODE_BY_TYPE = {
    UnitType.LEXICAL: LookupMode.TRANSLATE,
    UnitType.PHRASE: LookupMode.TRANSLATE,
    UnitType.FUNCTION: LookupMode.EXPLAIN,
    UnitType.GRAMMAR: LookupMode.EXPLAIN,
    UnitType.META: LookupMode.EXPLAIN,
}


@dataclass(slots=True)
class _SpanMatch:
    unit_type: UnitType
    start: int
    end: int
    metadata: dict[str, str]


class V2SourceAnalyzer:
    """Source-first unit detector for the V2 core.

    The analyzer intentionally ignores target translation. It produces a
    canonical source-unit graph that later layers can enrich with lookup and
    target coverage.
    """

    def analyze_segment(self, segment_id: str, source_text: str) -> SourceAnalysisResult:
        tokens = self.tokenize(source_text, segment_id)
        units: list[SourceUnit] = []
        claimed: set[int] = set()

        for matcher in (self._match_meta, self._match_phrase, self._match_grammar):
            for span in matcher(tokens):
                if any(index in claimed for index in range(span.start, span.end + 1)):
                    continue
                owner = self._build_owner_unit(segment_id, source_text, tokens, span)
                units.append(owner)
                claimed.update(range(span.start, span.end + 1))
                units.extend(self._build_attached_token_units(segment_id, source_text, tokens, owner))

        for token in tokens:
            if token.index in claimed:
                continue
            unit_type = UnitType.FUNCTION if token.normalized in FUNCTION_WORDS else UnitType.LEXICAL
            units.append(self._build_single_token_unit(segment_id, source_text, token, unit_type))

        units.sort(key=lambda item: (item.token_start, -item.priority, item.source_text))
        return SourceAnalysisResult(segment_id=segment_id, source_text=source_text, tokens=tokens, units=units)

    def resolve_tap_unit(self, analysis: SourceAnalysisResult, token_index: int) -> SourceUnit | None:
        token_units = [unit for unit in analysis.units if unit.token_start <= token_index <= unit.token_end]
        if not token_units:
            return None

        direct = next((unit for unit in token_units if unit.token_start == token_index and unit.token_end == token_index), None)
        if direct and direct.attached_to_unit_id:
            return next((unit for unit in analysis.units if unit.unit_id == direct.attached_to_unit_id), direct)
        return token_units[0]

    def tokenize(self, source_text: str, segment_id: str) -> list[SourceToken]:
        tokens: list[SourceToken] = []
        for index, match in enumerate(TOKEN_RE.finditer(source_text)):
            text = match.group(0)
            token_id = f"{segment_id}_tok_{index}"
            tokens.append(
                SourceToken(
                    token_id=token_id,
                    index=index,
                    text=text,
                    normalized=text.lower(),
                    start_offset=match.start(),
                    end_offset=match.end(),
                )
            )
        return tokens

    def _match_meta(self, tokens: list[SourceToken]) -> list[_SpanMatch]:
        spans: list[_SpanMatch] = []
        for index in range(len(tokens)):
            if self._is_chapter_heading(tokens, index):
                spans.append(_SpanMatch(UnitType.META, index, index + 1, {"meta_kind": "chapter"}))
            if self._is_time_marker(tokens, index):
                end = index + 1 if index + 1 < len(tokens) and tokens[index + 1].normalized in {"am", "pm"} else index
                spans.append(_SpanMatch(UnitType.META, index, end, {"meta_kind": "time"}))
            if tokens[index].text in PUNCTUATION_MARKERS:
                spans.append(_SpanMatch(UnitType.META, index, index, {"meta_kind": "punctuation"}))
        return spans

    def _match_phrase(self, tokens: list[SourceToken]) -> list[_SpanMatch]:
        return self._match_token_patterns(tokens, PHRASE_PATTERNS, UnitType.PHRASE, "phrase")

    def _match_grammar(self, tokens: list[SourceToken]) -> list[_SpanMatch]:
        return self._match_token_patterns(tokens, GRAMMAR_PATTERNS, UnitType.GRAMMAR, "grammar")

    def _match_token_patterns(
        self,
        tokens: list[SourceToken],
        patterns: set[tuple[str, ...]],
        unit_type: UnitType,
        kind: str,
    ) -> list[_SpanMatch]:
        spans: list[_SpanMatch] = []
        for pattern in sorted(patterns, key=len, reverse=True):
            width = len(pattern)
            for start in range(0, len(tokens) - width + 1):
                normals = tuple(token.normalized for token in tokens[start : start + width])
                if normals == pattern:
                    spans.append(_SpanMatch(unit_type, start, start + width - 1, {"pattern_kind": kind}))
        return spans

    def _build_owner_unit(
        self,
        segment_id: str,
        source_text: str,
        tokens: list[SourceToken],
        span: _SpanMatch,
    ) -> SourceUnit:
        start_token = tokens[span.start]
        end_token = tokens[span.end]
        return SourceUnit(
            unit_id=f"{segment_id}_unit_{span.unit_type.value.lower()}_{span.start}_{span.end}",
            segment_id=segment_id,
            type=span.unit_type,
            source_text=source_text[start_token.start_offset : end_token.end_offset],
            token_start=span.start,
            token_end=span.end,
            head_token_id=start_token.token_id,
            lookup_mode=LOOKUP_MODE_BY_TYPE[span.unit_type],
            priority=TYPE_PRIORITY[span.unit_type],
            metadata=span.metadata,
        )

    def _build_attached_token_units(
        self,
        segment_id: str,
        source_text: str,
        tokens: list[SourceToken],
        owner: SourceUnit,
    ) -> list[SourceUnit]:
        attached_units: list[SourceUnit] = []
        for token in tokens[owner.token_start : owner.token_end + 1]:
            attached_units.append(
                SourceUnit(
                    unit_id=f"{segment_id}_unit_attached_{token.index}",
                    segment_id=segment_id,
                    type=owner.type,
                    source_text=token.text,
                    token_start=token.index,
                    token_end=token.index,
                    head_token_id=token.token_id,
                    attached_to_unit_id=owner.unit_id,
                    phrase_owner_unit_id=owner.unit_id if owner.type == UnitType.PHRASE else None,
                    lookup_mode=LOOKUP_MODE_BY_TYPE[owner.type],
                    priority=TYPE_PRIORITY[owner.type] - 1,
                    metadata={"attached_role": "member"},
                )
            )
        return attached_units

    def _build_single_token_unit(
        self,
        segment_id: str,
        source_text: str,
        token: SourceToken,
        unit_type: UnitType,
    ) -> SourceUnit:
        return SourceUnit(
            unit_id=f"{segment_id}_unit_{unit_type.value.lower()}_{token.index}",
            segment_id=segment_id,
            type=unit_type,
            source_text=token.text,
            token_start=token.index,
            token_end=token.index,
            head_token_id=token.token_id,
            lookup_mode=LOOKUP_MODE_BY_TYPE[unit_type],
            priority=TYPE_PRIORITY[unit_type],
            metadata={},
        )

    def _is_chapter_heading(self, tokens: list[SourceToken], index: int) -> bool:
        if tokens[index].normalized != "chapter" or index + 1 >= len(tokens):
            return False
        next_token = tokens[index + 1].normalized
        return next_token.isdigit() or next_token in CHAPTER_WORDS

    def _is_time_marker(self, tokens: list[SourceToken], index: int) -> bool:
        if not TIME_TOKEN_RE.match(tokens[index].text):
            return False
        if index + 1 >= len(tokens):
            return True
        return tokens[index + 1].normalized in {"am", "pm"}
