from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)
SOURCE_SUFFIXES = {"s", "es", "ed", "ing"}
PHRASE_TYPES = {
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


def contains_source_phrase(source: str, phrase: str) -> bool:
    haystack = tokens(source)
    wanted = tokens(phrase)
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


def validate(payload: dict[str, Any]) -> tuple[list[str], list[str], dict[str, int]]:
    errors: list[str] = []
    warnings: list[str] = []
    parallel = [item for item in payload.get("parallel") or [] if isinstance(item, dict)]
    phrases = [item for item in payload.get("phrases") or [] if isinstance(item, dict)]
    parallel_pairs = {
        (
            str(item.get("source") or item.get("source_text") or "").strip(),
            str(item.get("translation") or item.get("target_text") or "").strip(),
        )
        for item in parallel
    }

    seen_sources: set[str] = set()
    for index, phrase in enumerate(phrases):
        label = f"phrases[{index}]"
        source = str(phrase.get("source") or "").strip()
        translation = str(phrase.get("translation") or "").strip()
        phrase_type = str(phrase.get("type") or "").strip()
        if not source:
            errors.append(f"{label}: missing source")
            continue
        canonical = " ".join(tokens(source))
        if canonical in seen_sources:
            errors.append(f"{label}: duplicate canonical source: {source}")
        seen_sources.add(canonical)
        if not translation:
            errors.append(f"{label}: missing translation")
        if phrase_type not in PHRASE_TYPES:
            errors.append(f"{label}: invalid or missing type: {phrase_type!r}")

        components = phrase.get("components")
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

        occurrences = phrase.get("occurrences")
        if not isinstance(occurrences, list) or not occurrences:
            errors.append(f"{label}: occurrences[] is required")
            continue
        for occurrence_index, occurrence in enumerate(occurrences):
            occurrence_label = f"{label}.occurrences[{occurrence_index}]"
            if not isinstance(occurrence, dict):
                errors.append(f"{occurrence_label}: expected object")
                continue
            source_text = str(occurrence.get("source_text") or "").strip()
            target_text = str(occurrence.get("target_text") or "").strip()
            source_form = str(occurrence.get("source_form") or source).strip()
            target_span = str(
                occurrence.get("target_span_text") or translation
            ).strip()
            if (source_text, target_text) not in parallel_pairs:
                errors.append(f"{occurrence_label}: segment is absent from parallel[]")
            if not contains_source_phrase(source_text, source_form):
                errors.append(
                    f"{occurrence_label}: source_form is absent from source_text"
                )
            if not contains_target_span(target_text, target_span):
                errors.append(
                    f"{occurrence_label}: target_span_text is absent from target_text"
                )

    audit = payload.get("phrase_audit")
    if not isinstance(audit, dict):
        errors.append("phrase_audit object is required")
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
            errors.append(f"phrase_audit misses {len(missing_reviews)} parallel segment(s)")
        if extra_reviews:
            errors.append(f"phrase_audit has {len(extra_reviews)} unknown segment(s)")
        second_pass = audit.get("second_pass")
        if not isinstance(second_pass, dict):
            errors.append("phrase_audit.second_pass object is required")
        else:
            if str(second_pass.get("status") or "") != "passed":
                errors.append("phrase_audit.second_pass.status must be 'passed'")
            unresolved = second_pass.get("unresolved_omissions")
            if not isinstance(unresolved, list):
                errors.append("unresolved_omissions must be a list")
            elif unresolved:
                errors.append(
                    f"second pass has {len(unresolved)} unresolved omission(s)"
                )

    if len(reviewed) != len(parallel):
        warnings.append(
            f"review count {len(reviewed)} differs from parallel count {len(parallel)}"
        )
    return errors, warnings, {
        "parallel": len(parallel),
        "phrases": len(phrases),
        "reviewed": len(reviewed),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a two-pass LEXO book phrase layer."
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