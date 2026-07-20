from __future__ import annotations

import json
from pathlib import Path
from typing import Any


REQUIRED = ("seed_words_uk.json", "seed_blocks_uk.json", "book_layer_uk.json", "word_to_word_uk.json")


def load_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def require_verified_book(directory: Path, book_id: str) -> None:
    missing = [name for name in REQUIRED if not (directory / name).exists()]
    if missing:
        raise ValueError(f"{book_id}: incomplete UK four-file contract; missing {missing}")
    layer = load_object(directory / "book_layer_uk.json")
    proof = load_object(directory / "word_to_word_uk.json")
    if layer.get("book_id") != book_id or proof.get("book_id") != book_id:
        raise ValueError(f"{book_id}: book_id disagrees across UK artifacts")
    if layer.get("target_lang") != "uk" or proof.get("target_lang") != "uk":
        raise ValueError(f"{book_id}: target_lang must be uk")
    audit = layer.get("book_layer_audit")
    if not isinstance(audit, dict):
        raise ValueError(f"{book_id}: missing book_layer_audit")
    for pass_name in ("second_pass", "third_pass", "fourth_pass"):
        item = audit.get(pass_name)
        if not isinstance(item, dict) or item.get("status") != "passed" or item.get("unresolved") != []:
            raise ValueError(f"{book_id}: {pass_name} is not clean")
    if not isinstance(proof.get("entries"), list) or not isinstance(proof.get("block_occurrences"), list):
        raise ValueError(f"{book_id}: invalid UK verification proof")
