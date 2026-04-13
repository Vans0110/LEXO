from __future__ import annotations

from .models import CoverageStatus, LookupResult, SourceAnalysisResult, SourceUnit, TapPayload, TargetCoverage, UnitType


class V2TapPayloadBuilder:
    """Builds final tap payloads from V2 source/lookup/coverage layers."""

    def build_for_token(
        self,
        analysis: SourceAnalysisResult,
        lookups: dict[str, LookupResult],
        coverages: dict[str, TargetCoverage],
        token_index: int,
        segment_translation_learning: str,
    ) -> TapPayload | None:
        unit = self._resolve_selected_unit(analysis, token_index)
        if unit is None:
            return None
        return self.build_for_unit(
            analysis=analysis,
            unit=unit,
            lookups=lookups,
            coverages=coverages,
            segment_translation_learning=segment_translation_learning,
        )

    def build_for_unit(
        self,
        analysis: SourceAnalysisResult,
        unit: SourceUnit,
        lookups: dict[str, LookupResult],
        coverages: dict[str, TargetCoverage],
        segment_translation_learning: str,
    ) -> TapPayload:
        lookup = lookups[unit.unit_id]
        coverage = coverages.get(unit.unit_id) or TargetCoverage(
            unit_id=unit.unit_id,
            target_text="",
            target_token_start=None,
            target_token_end=None,
            coverage_status=CoverageStatus.NONE,
            confidence=0.0,
        )
        host_unit_text = self._resolve_host_unit_text(analysis, unit, coverages)
        phrase_owner_text = self._resolve_phrase_owner_text(analysis, unit, coverages)

        lookup_title = self._build_lookup_title(unit)
        lookup_body = self._build_lookup_body(unit, lookup)

        return TapPayload(
            selected_unit_id=unit.unit_id,
            selected_unit_text=unit.source_text,
            selected_unit_type=unit.type,
            lookup_translation=lookup.base_translation,
            lookup_explanation=lookup.explanation,
            lookup_title=lookup_title,
            lookup_body=lookup_body,
            segment_source=analysis.source_text,
            segment_translation_learning=segment_translation_learning,
            target_coverage_text=coverage.target_text,
            coverage_status=coverage.coverage_status,
            host_unit_text=host_unit_text,
            phrase_owner_text=phrase_owner_text,
        )

    def _resolve_selected_unit(self, analysis: SourceAnalysisResult, token_index: int) -> SourceUnit | None:
        token_units = [unit for unit in analysis.units if unit.token_start <= token_index <= unit.token_end]
        if not token_units:
            return None

        direct = next((unit for unit in token_units if unit.token_start == token_index and unit.token_end == token_index), None)
        if direct and direct.attached_to_unit_id:
            return next((unit for unit in analysis.units if unit.unit_id == direct.attached_to_unit_id), direct)
        return token_units[0]

    def _build_lookup_title(self, unit: SourceUnit) -> str:
        if unit.type == UnitType.PHRASE:
            return f"Phrase: {unit.source_text}"
        if unit.type == UnitType.GRAMMAR:
            return f"Grammar: {unit.source_text}"
        if unit.type == UnitType.FUNCTION:
            return f"Function: {unit.source_text}"
        if unit.type == UnitType.META:
            return f"Meta: {unit.source_text}"
        return unit.source_text

    def _build_lookup_body(self, unit: SourceUnit, lookup: LookupResult) -> str:
        body_parts: list[str] = []
        if lookup.base_translation:
            body_parts.append(lookup.base_translation)
        if lookup.explanation:
            body_parts.append(lookup.explanation)
        if unit.type == UnitType.FUNCTION and not lookup.base_translation:
            body_parts.append("отдельный target span не обязателен")
        if unit.type == UnitType.GRAMMAR and not lookup.base_translation:
            body_parts.append("смысл задаётся всей конструкцией")
        return " | ".join(part for part in body_parts if part).strip()

    def _resolve_host_unit_text(
        self,
        analysis: SourceAnalysisResult,
        unit: SourceUnit,
        coverages: dict[str, TargetCoverage],
    ) -> str | None:
        coverage = coverages.get(unit.unit_id)
        if coverage is None or not coverage.host_unit_id:
            return None
        host_unit = next((candidate for candidate in analysis.units if candidate.unit_id == coverage.host_unit_id), None)
        return host_unit.source_text if host_unit is not None else None

    def _resolve_phrase_owner_text(
        self,
        analysis: SourceAnalysisResult,
        unit: SourceUnit,
        coverages: dict[str, TargetCoverage],
    ) -> str | None:
        coverage = coverages.get(unit.unit_id)
        owner_id = None
        if coverage is not None and coverage.owner_unit_id:
            owner_id = coverage.owner_unit_id
        elif unit.phrase_owner_unit_id:
            owner_id = unit.phrase_owner_unit_id
        if not owner_id:
            return None
        owner_unit = next((candidate for candidate in analysis.units if candidate.unit_id == owner_id), None)
        return owner_unit.source_text if owner_unit is not None else None
