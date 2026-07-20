from __future__ import annotations

import argparse
import copy
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def block_key(value: object) -> str:
    return " ".join(match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or "")))


def word_key(value: object) -> str:
    lemma, separator, pos = clean(value).partition("|")
    return f"{lemma.casefold()}|{pos.upper()}" if separator else ""


def load_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def load_list(path: Path) -> list[Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError(f"expected JSON list: {path}")
    return payload


def write_object(path: Path, payload: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def append_unique(values: list[str], value: str) -> bool:
    if value.casefold() in {clean(item).casefold() for item in values}:
        return False
    values.append(value)
    return True


def seed_dir(root: Path, book_id: str) -> Path:
    return root / "Studio" / "Backend" / "data" / "dictionaries" / "library_ru" / "books" / book_id


def load_book(root: Path, book_id: str) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    directory = seed_dir(root, book_id)
    words_path = directory / "seed_words_ru.json"
    if not words_path.exists():
        raise ValueError(f"{book_id}: missing seed_words_ru.json")
    words = load_object(words_path)
    blocks_path = directory / "seed_blocks_ru.json"
    if blocks_path.exists():
        raw_blocks = json.loads(blocks_path.read_text(encoding="utf-8"))
        if isinstance(raw_blocks, list):
            blocks = [item for item in raw_blocks if isinstance(item, dict)]
        elif isinstance(raw_blocks, dict):
            blocks = []
            for source, value in raw_blocks.items():
                if isinstance(value, dict):
                    translations = value.get("translations") or []
                    translation = clean(value.get("translation")) or next(
                        (clean(item) for item in translations if clean(item)), ""
                    )
                    blocks.append(
                        {
                            **value,
                            "source": source,
                            "translation": translation,
                            "source_forms": value.get("source_forms") or [source],
                        }
                    )
                else:
                    blocks.append(
                        {
                            "source": source,
                            "translation": clean(value),
                            "source_forms": [source],
                        }
                    )
        else:
            raise ValueError(f"expected block seed object or list: {blocks_path}")
    else:
        layer_path = directory / "book_layer_ru.json"
        layer = load_object(layer_path) if layer_path.exists() else {}
        if layer.get("blocks") != []:
            raise ValueError(f"{book_id}: missing block seed without explicit empty layer")
        blocks = []
    return words, blocks


def contributions(root: Path, book_id: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    words, blocks = load_book(root, book_id)
    word_items: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for raw_key, value in words.items():
        if not isinstance(value, dict) or not word_key(raw_key):
            raise ValueError(f"{book_id}: invalid word seed {raw_key!r}")
        key = word_key(raw_key)
        lemma, pos = key.rsplit("|", 1)
        translations = [clean(item) for item in value.get("translations") or [] if clean(item)]
        primary = clean(value.get("translation"))
        if primary and primary.casefold() not in {item.casefold() for item in translations}:
            translations.insert(0, primary)
        normalized_values = [item.casefold() for item in translations]
        if len(normalized_values) != len(set(normalized_values)):
            raise ValueError(f"{book_id}: duplicate translations in word seed {key}")
        kind = "contextual"
        if not translations:
            fallback = clean(value.get("dictionary_translation"))
            if fallback:
                translations = [fallback]
                kind = "dictionary_fallback"
        if not translations:
            skipped.append({"type": "word", "key": key, "reason": "skipped_empty"})
            continue
        source_form = clean(value.get("word") or value.get("surface") or lemma)
        for translation in dict.fromkeys(item.casefold() for item in translations):
            canonical = next(item for item in translations if item.casefold() == translation)
            word_items.append({"key": key, "lemma": lemma, "pos": pos, "translation": canonical, "kind": kind, "source_form": source_form})
    block_items: list[dict[str, Any]] = []
    for item in blocks:
        source = block_key(item.get("source"))
        translation = clean(item.get("translation"))
        block_type = clean(item.get("type"))
        explanation = clean(item.get("explanation"))
        forms = [clean(form) for form in item.get("source_forms") or [] if clean(form)]
        if not source or not translation or not block_type or not explanation or not forms:
            raise ValueError(f"{book_id}: invalid block seed {item!r}")
        if len([form.casefold() for form in forms]) != len(
            {form.casefold() for form in forms}
        ):
            raise ValueError(f"{book_id}: duplicate source_forms in block {source}")
        block_items.append({"key": source, "translation": translation, "kind": "contextual", "type": block_type, "explanation": explanation, "source_forms": forms, "components": item.get("components") or []})
    block_identities = [
        (item["key"], item["translation"].casefold()) for item in block_items
    ]
    if len(block_identities) != len(set(block_identities)):
        raise ValueError(f"{book_id}: duplicate block seed identity")
    return word_items, block_items, skipped


def variant(record: dict[str, Any], translation: str) -> dict[str, Any] | None:
    return next((item for item in record.get("variants") or [] if isinstance(item, dict) and clean(item.get("translation")).casefold() == translation.casefold()), None)


def merge_variant(record: dict[str, Any], item: dict[str, Any], book_id: str, forms: list[str]) -> tuple[str, str]:
    translations = record.setdefault("translations", [])
    is_new_translation = append_unique(translations, item["translation"])
    current = variant(record, item["translation"])
    if current is None:
        current = {"translation": item["translation"], "translation_kind": item["kind"], "book_ids": [], "source_forms": []}
        record.setdefault("variants", []).append(current)
    if item["kind"] == "contextual":
        current["translation_kind"] = "contextual"
    changed_provenance = append_unique(current.setdefault("book_ids", []), book_id)
    for form in forms:
        changed_provenance = append_unique(current.setdefault("source_forms", []), form) or changed_provenance
    if is_new_translation:
        return ("added" if len(translations) == 1 else "new_translation", "translation was absent")
    if changed_provenance:
        return "provenance_supplemented", "translation existed; provenance supplemented"
    return "skipped_existing", "identical key and translation already exist"


def merge_components(record: dict[str, Any], components: list[Any], book_id: str) -> None:
    target = record.setdefault("components", [])
    for component in components:
        if not isinstance(component, dict) or not clean(component.get("translation")):
            continue
        identity = (block_key(component.get("source")), clean(component.get("lemma")).casefold(), clean(component.get("pos")).upper(), clean(component.get("translation")).casefold())
        existing = next((item for item in target if isinstance(item, dict) and (block_key(item.get("source")), clean(item.get("lemma")).casefold(), clean(item.get("pos")).upper(), clean(item.get("translation")).casefold()) == identity), None)
        if existing is None:
            existing = {"source": clean(component.get("source")), "lemma": clean(component.get("lemma")).casefold(), "pos": clean(component.get("pos")).upper(), "translation": clean(component.get("translation")), "book_ids": []}
            target.append(existing)
        append_unique(existing.setdefault("book_ids", []), book_id)


def apply_books(root: Path, book_ids: list[str], words: dict[str, Any], blocks: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], list[str]]:
    next_words, next_blocks = copy.deepcopy(words), copy.deepcopy(blocks)
    report: dict[str, Any] = {"books": {}, "totals": Counter()}
    errors: list[str] = []
    for book_id in book_ids:
        actions: list[dict[str, Any]] = []
        try:
            word_items, block_items, skipped = contributions(root, book_id)
            actions.extend(skipped)
            for item in word_items:
                record = next_words.setdefault(item["key"], {"lemma": item["lemma"], "pos": item["pos"], "translations": [], "variants": []})
                action, reason = merge_variant(record, item, book_id, [item["source_form"]])
                actions.append({"type": "word", "key": item["key"], "translation": item["translation"], "action": action, "reason": reason})
            for item in block_items:
                record = next_blocks.setdefault(item["key"], {"translations": [], "variants": [], "components": []})
                existing_type = clean(record.get("type"))
                existing_explanation = clean(record.get("explanation"))
                if existing_type and existing_type != item["type"]:
                    raise ValueError(f"{book_id}: conflicting block type for {item['key']}")
                if existing_explanation and existing_explanation != item["explanation"]:
                    raise ValueError(f"{book_id}: conflicting block explanation for {item['key']}")
                record["type"] = item["type"]
                record["explanation"] = item["explanation"]
                action, reason = merge_variant(record, item, book_id, item["source_forms"])
                merge_components(record, item["components"], book_id)
                actions.append({"type": "block", "key": item["key"], "translation": item["translation"], "action": action, "reason": reason})
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append(str(exc))
        counts = Counter(item.get("action") or item.get("reason") for item in actions)
        report["books"][book_id] = {"counts": dict(counts), "actions": actions}
        report["totals"].update(counts)
    report["totals"] = dict(report["totals"])
    return next_words, next_blocks, report, errors


def duplicates(payload: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    for key, record in payload.items():
        if label == "block" and (not clean(record.get("type")) or not clean(record.get("explanation"))):
            errors.append(f"{label} {key}: missing type or explanation")
        translations = [clean(item).casefold() for item in record.get("translations") or []]
        if len(translations) != len(set(translations)):
            errors.append(f"{label} {key}: duplicate translations")
        variants = [clean(item.get("translation")).casefold() for item in record.get("variants") or [] if isinstance(item, dict)]
        if len(variants) != len(set(variants)) or set(variants) != set(translations):
            errors.append(f"{label} {key}: variants disagree with translations")
        for item in record.get("variants") or []:
            for field in ("book_ids", "source_forms"):
                values = [clean(value).casefold() for value in item.get(field) or []]
                if len(values) != len(set(values)):
                    errors.append(f"{label} {key}: duplicate {field}")
        component_ids = [
            (
                block_key(item.get("source")),
                clean(item.get("lemma")).casefold(),
                clean(item.get("pos")).upper(),
                clean(item.get("translation")).casefold(),
            )
            for item in record.get("components") or []
            if isinstance(item, dict)
        ]
        if len(component_ids) != len(set(component_ids)):
            errors.append(f"{label} {key}: duplicate components")
    return errors


def preservation_errors(before: dict[str, Any], after: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    for key, record in before.items():
        current = after.get(key)
        if not isinstance(current, dict):
            errors.append(f"{label} {key}: existing record was lost")
            continue
        old_values = {clean(item).casefold() for item in record.get("translations") or []}
        new_values = {clean(item).casefold() for item in current.get("translations") or []}
        if not old_values <= new_values:
            errors.append(f"{label} {key}: existing translations were lost")
        for old_variant in record.get("variants") or []:
            if not isinstance(old_variant, dict):
                continue
            current_variant = variant(current, clean(old_variant.get("translation")))
            if current_variant is None:
                errors.append(f"{label} {key}: existing variant was lost")
                continue
            for field in ("book_ids", "source_forms"):
                old_items = {clean(item).casefold() for item in old_variant.get(field) or []}
                new_items = {clean(item).casefold() for item in current_variant.get(field) or []}
                if not old_items <= new_items:
                    errors.append(f"{label} {key}: existing {field} were lost")
    return errors


def audit_book(root: Path, book_id: str, words: dict[str, Any], blocks: dict[str, Any]) -> tuple[int, int, list[str]]:
    word_items, block_items, _ = contributions(root, book_id)
    expected = len(word_items) + len(block_items)
    present = 0
    missing: list[str] = []
    for item in word_items:
        current = variant(words.get(item["key"], {}), item["translation"])
        forms = {clean(value).casefold() for value in (current or {}).get("source_forms", [])}
        if current and book_id in current.get("book_ids", []) and item["source_form"].casefold() in forms:
            present += 1
        else:
            missing.append(f"word {item['key']} -> {item['translation']}")
    for item in block_items:
        current = variant(blocks.get(item["key"], {}), item["translation"])
        forms = {clean(value).casefold() for value in (current or {}).get("source_forms", [])}
        expected_forms = {clean(value).casefold() for value in item["source_forms"]}
        if current and book_id in current.get("book_ids", []) and expected_forms <= forms:
            present += 1
        else:
            missing.append(f"block {item['key']} -> {item['translation']}")
    return present, expected, missing


def paths(root: Path) -> tuple[Path, Path, Path]:
    library = root / "Studio" / "Backend" / "data" / "dictionaries" / "library_ru"
    return library / "global_words_ru.json", library / "global_blocks_ru.json", library / "books"


def command_add(args: argparse.Namespace) -> int:
    words_path, blocks_path, _ = paths(args.root)
    words, blocks = load_object(words_path), load_object(blocks_path)
    next_words, next_blocks, report, errors = apply_books(args.root, list(dict.fromkeys(args.book_id)), words, blocks)
    errors.extend(duplicates(next_words, "word"))
    errors.extend(duplicates(next_blocks, "block"))
    errors.extend(preservation_errors(words, next_words, "word"))
    errors.extend(preservation_errors(blocks, next_blocks, "block"))
    for book_id in dict.fromkeys(args.book_id):
        try:
            present, expected, missing = audit_book(args.root, book_id, next_words, next_blocks)
            if present != expected:
                errors.append(f"{book_id}: second audit missing {missing}")
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append(str(exc))
    report.update({"write": bool(args.write), "errors": errors})
    if args.write and not errors:
        write_object(words_path, next_words)
        write_object(blocks_path, next_blocks)
        reloaded_words, reloaded_blocks = load_object(words_path), load_object(blocks_path)
        if reloaded_words != next_words or reloaded_blocks != next_blocks:
            report["errors"].append("post-write reload differs")
    print(json.dumps(report, ensure_ascii=False, indent=2, default=dict))
    return 1 if report["errors"] else 0


def command_report(args: argparse.Namespace) -> int:
    words_path, blocks_path, books_path = paths(args.root)
    words, blocks = load_object(words_path), load_object(blocks_path)
    result: dict[str, Any] = {"books": {}, "counts": Counter()}
    for directory in sorted(path.parent for path in books_path.glob("*/seed_words_ru.json")):
        book_id = directory.name
        try:
            present, expected, missing = audit_book(args.root, book_id, words, blocks)
            status = "fully_applied" if present == expected else "not_applied" if present == 0 else "partially_applied"
            result["books"][book_id] = {"status": status, "present": present, "expected": expected, "missing": missing}
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            status = "invalid"
            result["books"][book_id] = {"status": status, "error": str(exc)}
        result["counts"][status] += 1
    result["counts"] = dict(result["counts"])
    print(json.dumps(result, ensure_ascii=False, indent=2, default=dict))
    return 1 if result["counts"].get("invalid") else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Incrementally add selected RU book seeds to Globals")
    subparsers = parser.add_subparsers(dest="command", required=True)
    add = subparsers.add_parser("add")
    add.add_argument("--root", type=Path, required=True)
    add.add_argument("--book-id", action="append", required=True)
    add.add_argument("--write", action="store_true")
    add.set_defaults(run=command_add)
    report = subparsers.add_parser("report")
    report.add_argument("--root", type=Path, required=True)
    report.set_defaults(run=command_report)
    args = parser.parse_args()
    args.root = args.root.resolve()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
