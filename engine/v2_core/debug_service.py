from __future__ import annotations

from .coverage import V2CoverageResolver
from .lookup import V2LookupResolver
from .source_analyzer import V2SourceAnalyzer
from .tap_builder import V2TapPayloadBuilder


def build_v2_debug_payload(
    source_text: str,
    target_text: str = "",
    tap_token: int | None = None,
    segment_id: str = "debug_segment",
) -> dict:
    analyzer = V2SourceAnalyzer()
    lookup_resolver = V2LookupResolver()
    coverage_resolver = V2CoverageResolver()
    tap_builder = V2TapPayloadBuilder()

    analysis = analyzer.analyze_segment(segment_id=segment_id, source_text=source_text)
    lookups = lookup_resolver.resolve_analysis(analysis)
    coverages = coverage_resolver.resolve_analysis(analysis, lookups, target_text) if target_text else {}

    selected = None
    if tap_token is not None:
        selected = tap_builder.build_for_token(
            analysis=analysis,
            lookups=lookups,
            coverages=coverages,
            token_index=tap_token,
            segment_translation_learning=target_text,
        )

    return {
        "segment_id": segment_id,
        "source_text": source_text,
        "target_text": target_text,
        "tokens": [token.to_dict() for token in analysis.tokens],
        "units": [
            {
                **unit.to_dict(),
                "lookup": lookups[unit.unit_id].to_dict(),
                "coverage": coverages[unit.unit_id].to_dict() if unit.unit_id in coverages else None,
            }
            for unit in analysis.units
        ],
        "tap_payload": selected.to_dict() if selected is not None else None,
    }
