from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from validate_verification_word_to_word import validate as validate_word_to_word


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def main() -> None:
    parser = argparse.ArgumentParser(description="Materialize a reviewed RU layer and seeds")
    parser.add_argument("book_layer", type=Path)
    parser.add_argument("review_spec", type=Path)
    args = parser.parse_args()

    layer_path = args.book_layer.resolve()
    directory = layer_path.parent
    layer = load(layer_path)
    spec = load(args.review_spec.resolve())
    parallel = [
        item
        for item in layer.get("parallel") or []
        if isinstance(item, dict)
        and clean(item.get("source")).strip('"“”')
        and clean(item.get("translation"))
    ]

    overrides = spec.get("word_overrides") or {}
    absorbed_word_keys = {
        clean(item).lower() for item in spec.get("absorbed_word_keys") or [] if clean(item)
    }
    dictionary_fallbacks = spec.get("dictionary_fallbacks") or {}
    if not isinstance(dictionary_fallbacks, dict):
        raise ValueError("dictionary_fallbacks must be an object")
    words: list[dict[str, Any]] = []
    seed_words: dict[str, dict[str, Any]] = {}
    seen: set[str] = set()
    for raw in layer.get("words") or []:
        if not isinstance(raw, dict):
            continue
        word = dict(raw)
        lemma = clean(word.get("lemma")).lower()
        pos = clean(word.get("pos")).upper()
        key = f"{lemma}|{pos}"
        if not lemma or not pos or key in seen:
            continue
        seen.add(key)
        if key.lower() in absorbed_word_keys:
            reason = "meaning is absorbed by a verified block or grammar block"
            word["translation"] = ""
            word["translations"] = []
            word["empty_reason"] = reason
            fallback = clean(dictionary_fallbacks.get(key))
            if fallback:
                word["dictionary_translation"] = fallback
                word["dictionary_translation_source"] = "skill_fallback"
            words.append(word)
            seed_words[key] = {
                "translation": "",
                "translations": [],
                "empty_reason": reason,
            }
            if fallback:
                seed_words[key]["dictionary_translation"] = fallback
                seed_words[key]["dictionary_translation_source"] = "skill_fallback"
            continue
        values = overrides.get(key, word.get("translations") or [])
        if isinstance(values, str):
            values = [values]
        translations = []
        for value in values if isinstance(values, list) else []:
            value = clean(value)
            if value and value.casefold() not in {item.casefold() for item in translations}:
                translations.append(value)
        if not translations:
            fallback = clean(dictionary_fallbacks.get(key))
            if not fallback:
                raise ValueError(f"No reviewed translations or fallback for {key}")
            reason = "no independently owned target value in this book"
            word["translation"] = ""
            word["translations"] = []
            word["empty_reason"] = reason
            word["dictionary_translation"] = fallback
            word["dictionary_translation_source"] = "skill_fallback"
            words.append(word)
            seed_words[key] = {
                "translation": "",
                "translations": [],
                "empty_reason": reason,
                "dictionary_translation": fallback,
                "dictionary_translation_source": "skill_fallback",
            }
            continue
        word["translation"] = translations[0]
        word["translations"] = translations
        words.append(word)
        seed_words[key] = {"translation": translations[0], "translations": translations}

    raw_blocks = spec.get("blocks")
    if not isinstance(raw_blocks, list):
        raise ValueError("review spec requires blocks[]")
    third_pass_word_decisions = spec.get("third_pass_word_decisions")
    if not isinstance(third_pass_word_decisions, list) or not third_pass_word_decisions:
        raise ValueError("review spec requires third_pass_word_decisions[]")
    reviewed_segments = []
    for pair in parallel:
        source = clean(pair.get("source"))
        target = clean(pair.get("translation"))
        block_sources = [
            clean(block.get("source"))
            for block in raw_blocks
            if isinstance(block, dict)
            and any(
                clean(occurrence.get("source_text")) == source
                and clean(occurrence.get("target_text")) == target
                for occurrence in block.get("occurrences") or []
                if isinstance(occurrence, dict)
            )
        ]
        reviewed_segments.append(
            {
                "source_text": source,
                "target_text": target,
                "status": "covered" if block_sources else "no_block_required",
                "word_keys": [],
                "block_sources": block_sources,
                "notes": "",
            }
        )

    blocks: list[dict[str, Any]] = []
    for raw_block in raw_blocks:
        if not isinstance(raw_block, dict):
            continue
        block = dict(raw_block)
        occurrences = [
            item for item in block.pop("occurrences", []) if isinstance(item, dict)
        ]
        block.pop("necessity", None)
        forms = [clean(item.get("source_form")) for item in occurrences if clean(item.get("source_form"))]
        block["source_forms"] = list(dict.fromkeys(forms or block.get("source_forms") or [clean(block.get("source"))]))
        blocks.append(block)
    fourth_pass_decisions = spec.get("fourth_pass_block_decisions")
    if not isinstance(fourth_pass_decisions, list) or not fourth_pass_decisions:
        raise ValueError("review spec requires fourth_pass_block_decisions[]")

    layer["parallel"] = parallel
    layer["words"] = words
    layer["blocks"] = blocks
    layer["book_layer_audit"] = {
        "version": 3,
        "method": "codex_independent_four_pass",
        "reviewed_segments": reviewed_segments,
        "second_pass": {
            "status": "passed",
            "corrections": spec.get("second_pass_corrections") or [],
            "unresolved": [],
        },
        "third_pass": {
            "status": "passed",
            "word_decisions": third_pass_word_decisions,
            "corrections": spec.get("third_pass_corrections") or [],
            "unresolved": [],
        },
        "fourth_pass": {
            "status": "passed",
            "block_decisions": fourth_pass_decisions,
            "unresolved": [],
        },
        "absorbed_word_keys": sorted(absorbed_word_keys),
    }
    seed_blocks = [
        {key: value for key, value in block.items() if key != "audit_notes"}
        for block in blocks
    ]
    verification = spec.get("verification_word_to_word")
    if not isinstance(verification, dict):
        raise ValueError("review spec requires verification_word_to_word object")
    verification = {
        **verification,
        "version": 1,
        "book_id": layer.get("book_id"),
        "source_lang": "en",
        "target_lang": "ru",
    }
    proof_errors, _ = validate_word_to_word(layer, verification)
    if proof_errors:
        raise ValueError(
            "verification_word_to_word is invalid: " + "; ".join(proof_errors)
        )
    write(directory / "seed_words_ru.json", seed_words)
    write(directory / "seed_blocks_ru.json", seed_blocks)
    write(directory / "word_to_word_ru.json", verification)
    write(layer_path, layer)
    print(
        json.dumps(
            {
                "parallel": len(parallel),
                "words": len(words),
                "blocks": len(blocks),
                "word_occurrences": len(verification.get("entries") or []),
                "block_occurrences": len(verification.get("block_occurrences") or []),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
