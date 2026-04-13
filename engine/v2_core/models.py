from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import StrEnum


class UnitType(StrEnum):
    LEXICAL = "LEXICAL"
    PHRASE = "PHRASE"
    FUNCTION = "FUNCTION"
    GRAMMAR = "GRAMMAR"
    META = "META"


class LookupMode(StrEnum):
    TRANSLATE = "translate"
    EXPLAIN = "explain"
    NONE = "none"


class LookupStatus(StrEnum):
    FOUND = "found"
    GUESSED = "guessed"
    MISSING = "missing"


class LookupSource(StrEnum):
    PHRASE_DICT = "phrase_dict"
    LEMMA_DICT = "lemma_dict"
    FUNCTION_RULES = "function_rules"
    GRAMMAR_RULES = "grammar_rules"
    MT_FALLBACK = "mt_fallback"
    MANUAL_CURATED = "manual_curated"
    PATTERN_RULE = "pattern_rule"


class CoverageStatus(StrEnum):
    EXACT = "exact"
    REORDERED = "reordered"
    ABSORBED = "absorbed"
    PHRASE_OWNED = "phrase_owned"
    FUZZY = "fuzzy"
    NONE = "none"


@dataclass(slots=True)
class SourceToken:
    token_id: str
    index: int
    text: str
    normalized: str
    start_offset: int
    end_offset: int

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(slots=True)
class SourceUnit:
    unit_id: str
    segment_id: str
    type: UnitType
    source_text: str
    token_start: int
    token_end: int
    head_token_id: str
    attached_to_unit_id: str | None = None
    phrase_owner_unit_id: str | None = None
    lookup_mode: LookupMode = LookupMode.NONE
    priority: int = 0
    metadata: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["type"] = self.type.value
        payload["lookup_mode"] = self.lookup_mode.value
        return payload


@dataclass(slots=True)
class LookupResult:
    unit_id: str
    status: LookupStatus
    base_translation: str
    alt_translations: list[str]
    explanation: str
    source: LookupSource

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["status"] = self.status.value
        payload["source"] = self.source.value
        return payload


@dataclass(slots=True)
class TargetCoverage:
    unit_id: str
    target_text: str
    target_token_start: int | None
    target_token_end: int | None
    coverage_status: CoverageStatus
    host_unit_id: str | None = None
    owner_unit_id: str | None = None
    confidence: float = 0.0

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["coverage_status"] = self.coverage_status.value
        return payload


@dataclass(slots=True)
class TapPayload:
    selected_unit_id: str
    selected_unit_text: str
    selected_unit_type: UnitType
    lookup_translation: str
    lookup_explanation: str
    lookup_title: str
    lookup_body: str
    segment_source: str
    segment_translation_learning: str
    target_coverage_text: str
    coverage_status: CoverageStatus
    host_unit_text: str | None = None
    phrase_owner_text: str | None = None

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["selected_unit_type"] = self.selected_unit_type.value
        payload["coverage_status"] = self.coverage_status.value
        return payload


@dataclass(slots=True)
class SourceAnalysisResult:
    segment_id: str
    source_text: str
    tokens: list[SourceToken]
    units: list[SourceUnit]

    def to_dict(self) -> dict:
        return {
            "segment_id": self.segment_id,
            "source_text": self.source_text,
            "tokens": [token.to_dict() for token in self.tokens],
            "units": [unit.to_dict() for unit in self.units],
        }
