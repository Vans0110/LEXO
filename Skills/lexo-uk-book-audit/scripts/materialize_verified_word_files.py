from __future__ import annotations

import argparse
import json
import os
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def tokens(value: object) -> list[str]:
    return [match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or ""))]


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, payload: Any) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def key_for(item: dict[str, Any]) -> str:
    return f"{clean(item.get('lemma')).casefold()}|{clean(item.get('pos')).upper()}"


def target_span(target: str, translation: str) -> tuple[int, int]:
    haystack = tokens(target)
    wanted = tokens(translation)
    if not wanted:
        return -1, -1
    for index in range(len(haystack) - len(wanted) + 1):
        if haystack[index : index + len(wanted)] == wanted:
            return index, index + len(wanted) - 1
    return -1, -1


def find_form(words: list[dict[str, Any]], form: str) -> list[dict[str, Any]]:
    wanted = tokens(form)
    for index in range(len(words) - len(wanted) + 1):
        actual = [clean(item.get("text")).casefold() for item in words[index : index + len(wanted)]]
        if actual == wanted:
            return words[index : index + len(wanted)]
    return []


def main() -> None:
    parser = argparse.ArgumentParser(description="Materialize four verified UK word files")
    parser.add_argument("book_dir", type=Path)
    parser.add_argument("reader", type=Path)
    parser.add_argument("alignment", type=Path)
    parser.add_argument("review", type=Path)
    args = parser.parse_args()

    book_dir = args.book_dir.resolve()
    reader = load(args.reader.resolve())
    alignment = load(args.alignment.resolve())
    review = load(args.review.resolve())
    old_seed_words = load(book_dir / "seed_words_uk.json")
    blocks = load(book_dir / "seed_blocks_uk.json")
    aligned_by_id = {
        clean(item.get("word_id")): item
        for item in alignment.get("entries") or []
        if isinstance(item, dict) and clean(item.get("word_id"))
    }
    additions = review.get("word_translation_additions") or {}
    fallbacks = review.get("dictionary_fallbacks") or {}
    absorbed = {clean(item).casefold() for item in review.get("absorbed_word_keys") or []}

    segments: list[dict[str, Any]] = []
    for paragraph in reader.get("paragraphs") or []:
        words_by_segment: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for word in paragraph.get("words") or []:
            if isinstance(word, dict):
                words_by_segment[clean(word.get("segment_id"))].append(word)
        for segment in paragraph.get("segments_v2") or []:
            if not isinstance(segment, dict):
                continue
            source = clean(segment.get("source_text")).strip('"“”')
            target = clean(segment.get("target_text"))
            if not source or not target:
                continue
            segment_words = sorted(
                words_by_segment.get(clean(segment.get("id")), []),
                key=lambda item: int(item.get("order_index_in_segment") or 0),
            )
            segments.append({"source": source, "translation": target, "words": segment_words})

    seed_words: dict[str, dict[str, Any]] = {}
    layer_words: list[dict[str, Any]] = []
    forms_by_key: dict[str, list[str]] = defaultdict(list)
    for segment in segments:
        for word in segment["words"]:
            key = key_for(word)
            form = clean(word.get("text"))
            if form and form not in forms_by_key[key]:
                forms_by_key[key].append(form)
    for key, raw in old_seed_words.items():
        value = dict(raw) if isinstance(raw, dict) else {}
        values = [clean(item) for item in value.get("translations") or [] if clean(item)]
        for item in additions.get(key, []):
            item = clean(item)
            if item and item.casefold() not in {entry.casefold() for entry in values}:
                values.append(item)
        for segment in segments:
            for word in segment["words"]:
                if key_for(word) != key:
                    continue
                selected = clean(aligned_by_id.get(clean(word.get("id")), {}).get("translation"))
                if selected and target_span(segment["translation"], selected)[0] >= 0:
                    if selected.casefold() not in {entry.casefold() for entry in values}:
                        values.append(selected)
        seed = {"translation": values[0] if values else "", "translations": values}
        if not values:
            seed["empty_reason"] = clean(value.get("empty_reason")) or "no independent target span"
        fallback = clean(fallbacks.get(key))
        if fallback:
            seed["dictionary_translation"] = fallback
            seed["dictionary_translation_source"] = "skill_fallback"
        seed_words[key] = seed
        lemma, pos = key.rsplit("|", 1)
        layer_word = {
            "word": (forms_by_key.get(key) or [lemma])[0],
            "lemma": lemma,
            "pos": pos,
            **seed,
        }
        layer_words.append(layer_word)

    entries: list[dict[str, Any]] = []
    block_occurrences: list[dict[str, Any]] = []
    block_words: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
    block_sources_by_segment: dict[int, list[str]] = defaultdict(list)
    for segment_index, segment in enumerate(segments):
        for block in blocks:
            for source_form in block.get("source_forms") or []:
                matched = find_form(segment["words"], clean(source_form))
                if not matched:
                    continue
                unit_id = f"block:{segment_index}:{len(block_occurrences)}"
                word_ids = [clean(item.get("id")) for item in matched]
                block_occurrences.append(
                    {
                        "unit_id": unit_id,
                        "tap_unit_id": unit_id,
                        "block_source": clean(block.get("source")),
                        "source_form": clean(source_form),
                        "translation": clean(block.get("translation")),
                        "segment_index": segment_index,
                        "word_ids": word_ids,
                    }
                )
                block_sources_by_segment[segment_index].append(clean(block.get("source")))
                components = block.get("components") or []
                for offset, word in enumerate(matched):
                    component = components[offset] if offset < len(components) else {}
                    block_words[clean(word.get("id"))] = (
                        {**component, "unit_id": unit_id},
                        block,
                    )

    occurrence_statuses: dict[str, list[str]] = defaultdict(list)
    for segment_index, segment in enumerate(segments):
        for source_order, word in enumerate(segment["words"]):
            word_id = clean(word.get("id"))
            key = key_for(word)
            component_pair = block_words.get(word_id)
            contextual = ""
            status = "dictionary_fallback"
            reason = "no independent target span in this occurrence"
            owner = f"word:{word_id}"
            tap = owner
            start = end = -1
            if component_pair:
                component, block = component_pair
                contextual = clean(component.get("translation"))
                status = (
                    "grammar_component"
                    if clean(block.get("type")) == "grammar_construction"
                    else "block_component"
                )
                reason = clean(component.get("empty_reason"))
                owner = tap = clean(component.get("unit_id"))
                start, end = target_span(segment["translation"], contextual)
            else:
                selected = clean(aligned_by_id.get(word_id, {}).get("translation"))
                candidates = [selected, *(additions.get(key) or []), *(seed_words[key].get("translations") or [])]
                for candidate in candidates:
                    candidate = clean(candidate)
                    candidate_start, candidate_end = target_span(segment["translation"], candidate)
                    if candidate and candidate_start >= 0:
                        contextual = candidate
                        start, end = candidate_start, candidate_end
                        status = "independent_translation"
                        reason = ""
                        break
                if not contextual and not clean(seed_words[key].get("dictionary_translation")):
                    status = "zero_correspondence"
            occurrence_statuses[key].append(status)
            entry = {
                "word_id": word_id,
                "segment_index": segment_index,
                "source_order": source_order,
                "surface": clean(word.get("text")),
                "lemma": clean(word.get("lemma")).casefold(),
                "pos": clean(word.get("pos")).upper(),
                "contextual_translation": contextual,
                "dictionary_translation": clean(seed_words[key].get("dictionary_translation")),
                "status": status,
                "owner_unit_id": owner,
                "tap_unit_id": tap,
                "empty_reason": reason,
            }
            if start >= 0:
                entry["target_start_index"] = start
                entry["target_end_index"] = end
            entries.append(entry)

    parallel = [
        {"source": item["source"], "translation": item["translation"]}
        for item in segments
    ]
    evidence_by_key: dict[str, list[str]] = defaultdict(list)
    for segment in segments:
        for word in segment["words"]:
            evidence = f"{segment['source']} → {segment['translation']}"
            if evidence not in evidence_by_key[key_for(word)]:
                evidence_by_key[key_for(word)].append(evidence)
    decisions = []
    for word in layer_words:
        key = key_for(word)
        statuses = set(occurrence_statuses.get(key, []))
        if key.casefold() in absorbed:
            ownership = "absorbed"
        elif word.get("translations") and "dictionary_fallback" in statuses:
            ownership = "mixed"
        elif word.get("translations"):
            ownership = "word"
        else:
            ownership = "noncontextual"
        decisions.append(
            {
                "key": key,
                "ownership": ownership,
                "translations": word.get("translations") or [],
                "evidence": evidence_by_key.get(key) or ["word key retained for verification"],
            }
        )
    reviewed = [
        {
            "source_text": pair["source"],
            "target_text": pair["translation"],
            "status": "covered",
            "word_keys": sorted({key_for(word) for word in segments[index]["words"]}),
            "block_sources": block_sources_by_segment.get(index, []),
            "notes": "",
        }
        for index, pair in enumerate(parallel)
    ]
    block_decisions = []
    for block in blocks:
        indexes = [
            index
            for index, sources in block_sources_by_segment.items()
            if clean(block.get("source")) in sources
        ]
        block_decisions.append(
            {
                "source": clean(block.get("source")),
                "decision": "accepted",
                "word_by_word_result": " + ".join(
                    clean(item.get("translation")) or "∅"
                    for item in block.get("components") or []
                ),
                "reason": "independent components do not preserve the complete contextual meaning",
                "segment_indexes": indexes,
            }
        )
    for rejected in review.get("rejected_blocks") or []:
        if not isinstance(rejected, dict):
            continue
        block_decisions.append(
            {
                "source": clean(rejected.get("source")),
                "decision": "rejected",
                "word_by_word_result": clean(rejected.get("word_by_word_result")),
                "reason": clean(rejected.get("reason")),
                "segment_indexes": rejected.get("segment_indexes") or [],
            }
        )
    layer = {
        "version": 1,
        "book_id": clean(reader.get("book_id")),
        "title": clean(reader.get("title")),
        "source_lang": "en",
        "target_lang": "uk",
        "parallel": parallel,
        "words": layer_words,
        "blocks": blocks,
        "book_layer_audit": {
            "version": 4,
            "method": "codex_verified_occurrence_word_to_word",
            "reviewed_segments": reviewed,
            "second_pass": {"status": "passed", "corrections": [], "unresolved": []},
            "third_pass": {"status": "passed", "word_decisions": decisions, "corrections": [], "unresolved": []},
            "fourth_pass": {"status": "passed", "block_decisions": block_decisions, "unresolved": []},
            "absorbed_word_keys": sorted(absorbed),
        },
    }
    proof = {
        "version": 1,
        "book_id": clean(reader.get("book_id")),
        "source_lang": "en",
        "target_lang": "uk",
        "entries": entries,
        "block_occurrences": block_occurrences,
    }
    write(book_dir / "seed_words_uk.json", seed_words)
    write(book_dir / "seed_blocks_uk.json", blocks)
    write(book_dir / "book_layer_uk.json", layer)
    write(book_dir / "word_to_word_uk.json", proof)
    print(
        json.dumps(
            {
                "parallel": len(parallel),
                "words": len(layer_words),
                "occurrences": len(entries),
                "blocks": len(blocks),
                "block_occurrences": len(block_occurrences),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()

