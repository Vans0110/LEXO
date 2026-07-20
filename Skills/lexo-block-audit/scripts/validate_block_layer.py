from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)
SOURCE_SUFFIXES = {"s", "es", "ed", "ing"}
BLOCK_TYPES = {
    "phrasal_verb",
    "fixed_expression",
    "collocation",
    "grammar_construction",
    "prepositional_group",
    "name_group",
    "reordered_block",
}


def tokens(value: object) -> list[str]:
    return [match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or ""))]


def source_token_matches(expected: str, actual: str) -> bool:
    if expected == actual:
        return True
    if actual.startswith(expected) and actual[len(expected) :] in SOURCE_SUFFIXES:
        return True
    return False


def contains_source_block(source: str, block: str) -> bool:
    haystack = tokens(source)
    wanted = tokens(block)
    if not wanted or len(wanted) > len(haystack):
        return False
    return any(
        all(
            source_token_matches(wanted[offset], haystack[index + offset])
            for offset in range(len(wanted))
        )
        for index in range(len(haystack) - len(wanted) + 1)
    )


def contains_target_span(target: str, span: str) -> bool:
    haystack = tokens(target)
    wanted = tokens(span)
    if not wanted or len(wanted) > len(haystack):
        return False
    return any(
        haystack[index : index + len(wanted)] == wanted
        for index in range(len(haystack) - len(wanted) + 1)
    )


def load_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("book layer must be a JSON object")
    return payload


def corruption_paths(value: object, path: str = "$") -> list[str]:
    found: list[str] = []
    if isinstance(value, str) and ("???" in value or "�" in value):
        found.append(path)
    elif isinstance(value, dict):
        for key, item in value.items():
            found.extend(corruption_paths(item, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(corruption_paths(item, f"{path}[{index}]"))
    return found


def validate(payload: dict[str, Any]) -> tuple[list[str], list[str], dict[str, int]]:
    errors: list[str] = []
    warnings: list[str] = []
    for path in corruption_paths(payload):
        errors.append(f"encoding corruption at {path}")
    parallel = [item for item in payload.get("parallel") or [] if isinstance(item, dict)]
    blocks = [item for item in payload.get("blocks") or [] if isinstance(item, dict)]
    parallel_pairs = {
        (
            str(item.get("source") or item.get("source_text") or "").strip(),
            str(item.get("translation") or item.get("target_text") or "").strip(),
        )
        for item in parallel
    }

    seen_sources: set[str] = set()
    blocks_by_source: dict[str, dict[str, Any]] = {}
    for index, block in enumerate(blocks):
        label = f"blocks[{index}]"
        source = str(block.get("source") or "").strip()
        translation = str(block.get("translation") or "").strip()
        block_type = str(block.get("type") or "").strip()
        explanation = str(block.get("explanation") or "").strip()
        if not source:
            errors.append(f"{label}: missing source")
            continue
        canonical = " ".join(tokens(source))
        if canonical in seen_sources:
            errors.append(f"{label}: duplicate canonical source: {source}")
        seen_sources.add(canonical)
        blocks_by_source[canonical] = block
        if not translation:
            errors.append(f"{label}: missing translation")
        if block_type not in BLOCK_TYPES:
            errors.append(f"{label}: invalid or missing type: {block_type!r}")
        if not explanation:
            errors.append(f"{label}: missing reusable explanation")
        for forbidden in ("occurrences", "necessity"):
            if forbidden in block:
                errors.append(f"{label}: {forbidden} belongs in audit metadata")

        components = block.get("components")
        if not isinstance(components, list) or not components:
            errors.append(f"{label}: components[] is required")
            components = []
        for component_index, component in enumerate(components):
            component_label = f"{label}.components[{component_index}]"
            if not isinstance(component, dict):
                errors.append(f"{component_label}: expected object")
                continue
            component_source = str(component.get("source") or "").strip()
            component_translation = str(component.get("translation") or "").strip()
            if not component_source:
                errors.append(f"{component_label}: missing source")
            if not str(component.get("lemma") or "").strip():
                errors.append(f"{component_label}: missing lemma")
            if not str(component.get("pos") or "").strip():
                errors.append(f"{component_label}: missing pos")
            if not component_translation and not str(component.get("empty_reason") or "").strip():
                errors.append(
                    f"{component_label}: empty translation requires empty_reason"
                )

        source_forms = block.get("source_forms")
        if not isinstance(source_forms, list) or not source_forms:
            errors.append(f"{label}: source_forms[] is required")
        elif not any(
            contains_source_block(source_text, str(form))
            for source_text, target_text in parallel_pairs
            for form in source_forms
        ):
            errors.append(f"{label}: no supporting parallel segment")

    audit = payload.get("block_audit") or payload.get("book_layer_audit")
    if not isinstance(audit, dict):
        errors.append("block_audit object is required")
        reviewed = []
    else:
        reviewed = [
            item for item in audit.get("reviewed_segments") or [] if isinstance(item, dict)
        ]
        reviewed_pairs = {
            (
                str(item.get("source_text") or "").strip(),
                str(item.get("target_text") or "").strip(),
            )
            for item in reviewed
        }
        missing_reviews = sorted(parallel_pairs - reviewed_pairs)
        extra_reviews = sorted(reviewed_pairs - parallel_pairs)
        if missing_reviews:
            errors.append(f"block_audit misses {len(missing_reviews)} parallel segment(s)")
        if extra_reviews:
            errors.append(f"block_audit has {len(extra_reviews)} unknown segment(s)")
        second_pass = audit.get("second_pass")
        if not isinstance(second_pass, dict):
            errors.append("block_audit.second_pass object is required")
        else:
            if str(second_pass.get("status") or "") != "passed":
                errors.append("block_audit.second_pass.status must be 'passed'")
            unresolved = second_pass.get("unresolved_omissions")
            if unresolved is None:
                unresolved = second_pass.get("unresolved")
            if not isinstance(unresolved, list):
                errors.append("unresolved_omissions must be a list")
            elif unresolved:
                errors.append(
                    f"second pass has {len(unresolved)} unresolved omission(s)"
                )
        necessity_pass = audit.get("necessity_pass") or audit.get("fourth_pass")
        if not isinstance(necessity_pass, dict):
            errors.append("block_audit.necessity_pass object is required")
        else:
            if str(necessity_pass.get("status") or "") != "passed":
                errors.append("block_audit.necessity_pass.status must be 'passed'")
            unresolved = necessity_pass.get("unresolved")
            if not isinstance(unresolved, list):
                errors.append("necessity_pass.unresolved must be a list")
            elif unresolved:
                errors.append(f"necessity pass has {len(unresolved)} unresolved item(s)")
            accepted = {
                " ".join(tokens(item.get("source")))
                for item in necessity_pass.get("block_decisions") or []
                if isinstance(item, dict) and item.get("decision") == "accepted"
            }
            if accepted != seen_sources:
                errors.append("necessity-pass accepted blocks disagree with blocks[]")
            for index, item in enumerate(necessity_pass.get("block_decisions") or []):
                if not isinstance(item, dict):
                    continue
                segment_indexes = item.get("segment_indexes")
                if not isinstance(segment_indexes, list) or not segment_indexes or any(
                    not isinstance(value, int) or value < 0 or value >= len(parallel)
                    for value in segment_indexes
                ):
                    errors.append(
                        f"necessity_pass.block_decisions[{index}].segment_indexes[] is invalid"
                    )
                    continue
                if item.get("decision") != "accepted":
                    continue
                decision_source = " ".join(tokens(item.get("source")))
                block = blocks_by_source.get(decision_source) or {}
                block_translation = str(block.get("translation") or "").strip()
                for segment_index in segment_indexes:
                    segment = parallel[segment_index]
                    source_text = str(
                        segment.get("source") or segment.get("source_text") or ""
                    )
                    target_text = str(
                        segment.get("translation") or segment.get("target_text") or ""
                    )
                    if decision_source and not contains_source_block(
                        source_text, decision_source
                    ):
                        errors.append(
                            f"necessity_pass.block_decisions[{index}] source is absent "
                            f"from parallel[{segment_index}]"
                        )
                    if block_translation and not contains_target_span(
                        target_text, block_translation
                    ):
                        errors.append(
                            f"blocks[{decision_source}]: occurrence translation "
                            f"{block_translation!r} is absent from parallel[{segment_index}] target"
                        )

    if len(reviewed) != len(parallel):
        warnings.append(
            f"review count {len(reviewed)} differs from parallel count {len(parallel)}"
        )
    return errors, warnings, {
        "parallel": len(parallel),
        "blocks": len(blocks),
        "reviewed": len(reviewed),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a semantic-necessity LEXO book block layer."
    )
    parser.add_argument("book_layer", type=Path)
    args = parser.parse_args()
    try:
        payload = load_object(args.book_layer.resolve())
        errors, warnings, counts = validate(payload)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}")
        return 2
    print(json.dumps(counts, ensure_ascii=False))
    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    if errors:
        print(f"FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    print(f"OK: 0 errors, {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
