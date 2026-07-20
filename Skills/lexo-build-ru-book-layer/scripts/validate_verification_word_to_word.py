from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)
STATUSES = {
    "independent_translation",
    "block_component",
    "grammar_component",
    "zero_correspondence",
    "dictionary_fallback",
    "source_translation_omission",
    "unresolved",
}
COMPONENT_STATUSES = {"block_component", "grammar_component"}


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def tokens(value: object) -> list[str]:
    return [match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or ""))]


def load_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def sequence_count(source: str, form: str) -> int:
    haystack = tokens(source)
    wanted = tokens(form)
    if not wanted or len(wanted) > len(haystack):
        return 0
    return sum(
        haystack[index : index + len(wanted)] == wanted
        for index in range(len(haystack) - len(wanted) + 1)
    )


def validate(
    layer: dict[str, Any],
    proof: dict[str, Any],
) -> tuple[list[str], dict[str, int]]:
    errors: list[str] = []
    if clean(proof.get("book_id")) != clean(layer.get("book_id")):
        errors.append("verification book_id disagrees with book layer")
    if proof.get("source_lang") != "en" or proof.get("target_lang") != "ru":
        errors.append("verification languages must be en -> ru")

    parallel = [item for item in layer.get("parallel") or [] if isinstance(item, dict)]
    entries = [item for item in proof.get("entries") or [] if isinstance(item, dict)]
    blocks = [
        item for item in proof.get("block_occurrences") or [] if isinstance(item, dict)
    ]
    entries_by_segment: dict[int, list[dict[str, Any]]] = defaultdict(list)
    entries_by_id: dict[str, dict[str, Any]] = {}
    token_owners: dict[tuple[int, int], list[str]] = defaultdict(list)
    status_counts: Counter[str] = Counter()
    word_keys = {
        f"{clean(item.get('lemma')).casefold()}|{clean(item.get('pos')).upper()}"
        for item in layer.get("words") or []
        if isinstance(item, dict)
    }

    for index, entry in enumerate(entries):
        label = f"entries[{index}]"
        word_id = clean(entry.get("word_id"))
        if not word_id:
            errors.append(f"{label}.word_id is required")
        elif word_id in entries_by_id:
            errors.append(f"duplicate word_id: {word_id}")
        else:
            entries_by_id[word_id] = entry
        segment_index = entry.get("segment_index")
        source_order = entry.get("source_order")
        if not isinstance(segment_index, int) or not 0 <= segment_index < len(parallel):
            errors.append(f"{label}.segment_index is invalid")
        else:
            entries_by_segment[segment_index].append(entry)
        if not isinstance(source_order, int) or source_order < 0:
            errors.append(f"{label}.source_order is invalid")
        for field in ("surface", "lemma", "pos"):
            if not clean(entry.get(field)):
                errors.append(f"{label}.{field} is required")
        entry_key = (
            f"{clean(entry.get('lemma')).casefold()}|"
            f"{clean(entry.get('pos')).upper()}"
        )
        if entry_key not in word_keys:
            errors.append(f"{label} has no seed word {entry_key}")

        status = clean(entry.get("status"))
        status_counts[status] += 1
        if status not in STATUSES:
            errors.append(f"{label}.status is invalid: {status!r}")
            continue
        contextual = clean(entry.get("contextual_translation"))
        fallback = clean(entry.get("dictionary_translation"))
        reason = clean(entry.get("empty_reason"))
        owner = clean(entry.get("owner_unit_id"))
        tap = clean(entry.get("tap_unit_id"))
        start = entry.get("target_start_index")
        end = entry.get("target_end_index")

        if status == "unresolved":
            errors.append(f"{label} is unresolved")
        if not contextual and not reason:
            errors.append(f"{label} has empty contextual translation without reason")
        if status == "independent_translation" and not contextual:
            errors.append(f"{label} independent translation is empty")
        if status == "dictionary_fallback":
            if not fallback or contextual:
                errors.append(
                    f"{label} dictionary fallback requires fallback only, not context"
                )
            if isinstance(start, int) or isinstance(end, int):
                errors.append(f"{label} dictionary fallback must not claim target span")
            if len(tokens(fallback)) != 1:
                errors.append(f"{label} dictionary fallback must be one word")
        if status in {"zero_correspondence", "source_translation_omission"} and contextual:
            errors.append(f"{label} {status} must not have contextual translation")
        if status in COMPONENT_STATUSES and (not owner or not tap):
            errors.append(f"{label} component requires owner_unit_id and tap_unit_id")
        if status == "independent_translation":
            if not isinstance(start, int) or not isinstance(end, int) or start < 0 or end < start:
                errors.append(f"{label} independent translation requires target span")
            elif isinstance(segment_index, int):
                for target_index in range(start, end + 1):
                    token_owners[(segment_index, target_index)].append(word_id)

    for span, owners in token_owners.items():
        if len(owners) > 1:
            errors.append(f"independent target token {span} has owners {owners}")

    for segment_index, pair in enumerate(parallel):
        ordered = sorted(
            entries_by_segment.get(segment_index, []),
            key=lambda item: item.get("source_order", -1),
        )
        orders = [item.get("source_order") for item in ordered]
        if orders != list(range(len(ordered))):
            errors.append(f"segment {segment_index} source_order is not contiguous")
        actual = [token for item in ordered for token in tokens(item.get("surface"))]
        expected = tokens(pair.get("source"))
        if actual != expected:
            errors.append(
                f"segment {segment_index} occurrence tokens disagree: "
                f"expected={expected}, actual={actual}"
            )

    blocks_by_source: dict[str, list[dict[str, Any]]] = defaultdict(list)
    seen_unit_ids: set[str] = set()
    for index, block in enumerate(blocks):
        label = f"block_occurrences[{index}]"
        unit_id = clean(block.get("unit_id"))
        tap_id = clean(block.get("tap_unit_id"))
        block_source = clean(block.get("block_source")).casefold()
        source_form = clean(block.get("source_form"))
        word_ids = block.get("word_ids")
        if not unit_id or unit_id in seen_unit_ids:
            errors.append(f"{label}.unit_id is missing or duplicated")
        seen_unit_ids.add(unit_id)
        if not tap_id or tap_id != unit_id:
            errors.append(f"{label}.tap_unit_id must equal unit_id")
        if not block_source or not source_form or not clean(block.get("translation")):
            errors.append(f"{label} requires block_source, source_form, translation")
        if not isinstance(word_ids, list) or len(word_ids) < 2:
            errors.append(f"{label}.word_ids requires at least two entries")
            word_ids = []
        for word_id in word_ids:
            entry = entries_by_id.get(clean(word_id))
            if entry is None:
                errors.append(f"{label} references unknown word_id {word_id!r}")
                continue
            if clean(entry.get("status")) not in COMPONENT_STATUSES:
                errors.append(f"{label} word {word_id} is not a component")
            if clean(entry.get("owner_unit_id")) != unit_id:
                errors.append(f"{label} word {word_id} has another owner")
            if clean(entry.get("tap_unit_id")) != tap_id:
                errors.append(f"{label} word {word_id} has another tap unit")
        copied = [
            clean(entries_by_id.get(clean(word_id), {}).get("contextual_translation")).casefold()
            for word_id in word_ids
            if clean(entries_by_id.get(clean(word_id), {}).get("contextual_translation")).casefold()
            == clean(block.get("translation")).casefold()
        ]
        if len(copied) > 1:
            errors.append(f"{label} copies whole-block translation to multiple components")
        blocks_by_source[block_source].append(block)

    for block_index, block in enumerate(layer.get("blocks") or []):
        if not isinstance(block, dict):
            continue
        source = clean(block.get("source")).casefold()
        forms = [clean(item) for item in block.get("source_forms") or [] if clean(item)]
        block_occurrences = blocks_by_source.get(source, [])
        expected: Counter[tuple[int, str]] = Counter()
        for segment_index, pair in enumerate(parallel):
            for form in forms:
                expected[(segment_index, form.casefold())] += sequence_count(
                    clean(pair.get("source")), form
                )
        actual = Counter(
            (block.get("segment_index"), clean(block.get("source_form")).casefold())
            for block in block_occurrences
        )
        if actual != expected:
            errors.append(
                f"block {source!r} blocks disagree: expected={dict(expected)}, "
                f"actual={dict(actual)}"
            )
        for block in block_occurrences:
            if clean(block.get("translation")).casefold() != clean(
                block.get("translation")
            ).casefold():
                errors.append(
                    f"block block translation disagrees with blocks[{block_index}]"
                )

    extra_sources = set(blocks_by_source) - {
        clean(item.get("source")).casefold()
        for item in layer.get("blocks") or []
        if isinstance(item, dict)
    }
    if extra_sources:
        errors.append(f"verification has unknown block blocks {sorted(extra_sources)}")

    return errors, {
        "parallel": len(parallel),
        "entries": len(entries),
        "block_occurrences": len(blocks),
        "unresolved": status_counts["unresolved"],
        "fallbacks": status_counts["dictionary_fallback"],
        "zero_correspondences": status_counts["zero_correspondence"],
        "source_translation_omissions": status_counts["source_translation_omission"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a skill-owned occurrence-level word-to-word proof"
    )
    parser.add_argument("book_layer", type=Path)
    parser.add_argument("word_to_word", type=Path, nargs="?")
    args = parser.parse_args()
    try:
        layer_path = args.book_layer.resolve()
        proof_path = (args.word_to_word or layer_path.with_name("word_to_word_ru.json")).resolve()
        layer = load_object(layer_path)
        proof = load_object(proof_path)
        errors, counts = validate(layer, proof)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}")
        return 2
    print(json.dumps(counts, ensure_ascii=False))
    for error in errors:
        print(f"ERROR: {error}")
    if errors:
        print(f"FAILED: {len(errors)} error(s)")
        return 1
    print("OK: 0 errors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
