from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from validate_block_layer import validate as validate_blocks
from validate_uk_book_layer import load, normalized_block_map, normalized_word_map, validate as validate_layer
from validate_verification_word_to_word import validate as validate_proof


TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)
REQUIRED = ("seed_words_uk.json", "seed_blocks_uk.json", "book_layer_uk.json", "word_to_word_uk.json")


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def source_tokens(layer: dict[str, Any]) -> list[str]:
    return [match.group(0).casefold() for item in layer.get("parallel") or [] if isinstance(item, dict) for match in TOKEN_RE.finditer(clean(item.get("source")))]


def word_keys(layer: dict[str, Any]) -> set[str]:
    return {f"{clean(item.get('lemma')).casefold()}|{clean(item.get('pos')).upper()}" for item in layer.get("words") or [] if isinstance(item, dict) and clean(item.get("lemma")) and clean(item.get("pos"))}


def ru_layers(root: Path) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    by_id: dict[str, dict[str, Any]] = {}
    by_title: dict[str, dict[str, Any]] = {}
    books = root / "Studio" / "Backend" / "data" / "dictionaries" / "library_ru" / "books"
    for path in books.glob("*/book_layer_ru.json"):
        if not path.with_name("word_to_word_ru.json").exists():
            continue
        try:
            layer = load(path)
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        by_id[clean(layer.get("book_id")) or path.parent.name] = layer
        by_title[clean(layer.get("title")).casefold()] = layer
    return by_id, by_title


def audit_directory(directory: Path, ru_by_id: dict[str, dict[str, Any]], ru_by_title: dict[str, dict[str, Any]]) -> dict[str, Any]:
    missing = [name for name in REQUIRED if not (directory / name).exists()]
    if missing:
        return {"status": "not_created", "missing_files": missing}
    try:
        layer = load(directory / "book_layer_uk.json")
        proof = load(directory / "word_to_word_uk.json")
        seed_words = load(directory / "seed_words_uk.json")
        seed_blocks = json.loads((directory / "seed_blocks_uk.json").read_text(encoding="utf-8"))
        layer_errors, counts = validate_layer(layer)
        block_errors, warnings, _ = validate_blocks(layer)
        proof_errors, proof_counts = validate_proof(layer, proof)
        errors = [*layer_errors, *block_errors, *(f"word_to_word: {item}" for item in proof_errors)]
        if normalized_word_map(seed_words) != normalized_word_map(layer.get("words")):
            errors.append("seed_words_uk.json disagrees with book_layer_uk.json words[]")
        if normalized_block_map(seed_blocks) != normalized_block_map(layer.get("blocks")):
            errors.append("seed_blocks_uk.json disagrees with book_layer_uk.json blocks[]")
        if errors:
            return {"status": "invalid", "errors": errors, "warnings": warnings}
        book_id = clean(layer.get("book_id")) or directory.name
        reference = ru_by_id.get(book_id) or ru_by_title.get(clean(layer.get("title")).casefold())
        discrepancies: list[str] = []
        if reference:
            if source_tokens(layer) != source_tokens(reference):
                discrepancies.append("English source token coverage differs from verified RU reference")
            if word_keys(layer) != word_keys(reference):
                discrepancies.append("lemma|POS coverage differs from verified RU reference")
        status = "stale" if discrepancies else "valid"
        return {"status": status, "counts": {**counts, **{f"word_to_word_{key}": value for key, value in proof_counts.items()}}, "warnings": warnings, "ru_reference": bool(reference), "discrepancies": discrepancies}
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"status": "invalid", "errors": [str(exc)]}


def audit_root(root: Path) -> dict[str, Any]:
    books = root / "Studio" / "Backend" / "data" / "dictionaries" / "library_uk" / "books"
    ru_by_id, ru_by_title = ru_layers(root)
    results = {directory.name: audit_directory(directory, ru_by_id, ru_by_title) for directory in sorted(path for path in books.iterdir() if path.is_dir())}
    return {"books": results, "counts": dict(Counter(item["status"] for item in results.values()))}


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Audit every UK book dictionary contour")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    result = audit_root(args.root.resolve())
    print(json.dumps(result, ensure_ascii=False, indent=2))
    incomplete = sum(value for key, value in result["counts"].items() if key != "valid")
    return 1 if args.strict and incomplete else 0


if __name__ == "__main__":
    sys.exit(main())
