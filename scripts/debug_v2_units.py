from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from engine.v2_core import V2CoverageResolver, V2LookupResolver, V2SourceAnalyzer, V2TapPayloadBuilder


def main() -> None:
    parser = argparse.ArgumentParser(description="Debug V2 source units and lookups.")
    parser.add_argument("text", help="Source text to analyze")
    parser.add_argument("--segment-id", default="debug_segment", help="Synthetic segment id")
    parser.add_argument("--target", default="", help="Optional target text for V2 coverage debug")
    parser.add_argument("--tap-token", type=int, default=None, help="Optional token index to render final tap payload")
    args = parser.parse_args()

    analyzer = V2SourceAnalyzer()
    resolver = V2LookupResolver()
    coverage_resolver = V2CoverageResolver()
    tap_builder = V2TapPayloadBuilder()
    analysis = analyzer.analyze_segment(args.segment_id, args.text)
    lookups = resolver.resolve_analysis(analysis)
    coverages = coverage_resolver.resolve_analysis(analysis, lookups, args.target) if args.target else {}

    print(f"SOURCE: {analysis.source_text}")
    if args.target:
        print(f"TARGET: {args.target}")
    print("TOKENS:")
    for token in analysis.tokens:
        print(f"  [{token.index}] {token.text!r} normalized={token.normalized!r}")

    print("UNITS:")
    for unit in analysis.units:
        lookup = lookups[unit.unit_id]
        coverage = coverages.get(unit.unit_id)
        attached = f" attached_to={unit.attached_to_unit_id}" if unit.attached_to_unit_id else ""
        phrase_owner = f" phrase_owner={unit.phrase_owner_unit_id}" if unit.phrase_owner_unit_id else ""
        print(
            f"  {unit.type.value:<8} {unit.source_text!r} tokens={unit.token_start}-{unit.token_end}"
            f" lookup_mode={unit.lookup_mode.value} status={lookup.status.value} source={lookup.source.value}"
            f"{attached}{phrase_owner}"
        )
        print(f"    translation={lookup.base_translation!r}")
        print(f"    explanation={lookup.explanation!r}")
        if coverage is not None:
            owner = f" owner={coverage.owner_unit_id}" if coverage.owner_unit_id else ""
            host = f" host={coverage.host_unit_id}" if coverage.host_unit_id else ""
            print(
                f"    coverage={coverage.coverage_status.value!r} target_text={coverage.target_text!r}"
                f" span={coverage.target_token_start}-{coverage.target_token_end} confidence={coverage.confidence}{owner}{host}"
            )

    if args.tap_token is not None:
        payload = tap_builder.build_for_token(
            analysis=analysis,
            lookups=lookups,
            coverages=coverages,
            token_index=args.tap_token,
            segment_translation_learning=args.target,
        )
        print("TAP_PAYLOAD:")
        if payload is None:
            print("  <none>")
        else:
            print(f"  selected_unit_text={payload.selected_unit_text!r}")
            print(f"  selected_unit_type={payload.selected_unit_type.value!r}")
            print(f"  lookup_title={payload.lookup_title!r}")
            print(f"  lookup_body={payload.lookup_body!r}")
            print(f"  segment_source={payload.segment_source!r}")
            print(f"  segment_translation_learning={payload.segment_translation_learning!r}")
            print(f"  target_coverage_text={payload.target_coverage_text!r}")
            print(f"  coverage_status={payload.coverage_status.value!r}")
            print(f"  host_unit_text={payload.host_unit_text!r}")
            print(f"  phrase_owner_text={payload.phrase_owner_text!r}")


if __name__ == "__main__":
    main()
