from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from engine.library_dictionary import LibraryDictionaryStore


def _load_object(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return payload


def _validate_records(records: dict, *, label: str) -> None:
    for key, record in records.items():
        if not isinstance(record, dict):
            raise ValueError(f"Invalid {label} record: {key}")
        translations = record.get("translations")
        variants = record.get("variants")
        if not isinstance(translations, list) or not translations:
            raise ValueError(f"Missing translations: {label}:{key}")
        if len(translations) != len(set(translations)):
            raise ValueError(f"Duplicate translations: {label}:{key}")
        if not isinstance(variants, list) or not variants:
            raise ValueError(f"Missing variants: {label}:{key}")
        variant_translations = []
        for variant in variants:
            if not isinstance(variant, dict):
                raise ValueError(f"Invalid variant: {label}:{key}")
            translation = str(variant.get("translation") or "").strip()
            book_ids = variant.get("book_ids")
            source_forms = variant.get("source_forms")
            if not translation or translation not in translations:
                raise ValueError(f"Detached variant: {label}:{key}")
            if not isinstance(book_ids, list) or not book_ids:
                raise ValueError(f"Variant without book provenance: {label}:{key}:{translation}")
            if len(book_ids) != len(set(book_ids)):
                raise ValueError(f"Duplicate book provenance: {label}:{key}:{translation}")
            if not isinstance(source_forms, list) or not source_forms:
                raise ValueError(f"Variant without source form: {label}:{key}:{translation}")
            if len(source_forms) != len(set(source_forms)):
                raise ValueError(f"Duplicate source forms: {label}:{key}:{translation}")
            variant_translations.append(translation)
        if set(variant_translations) != set(translations):
            raise ValueError(f"Translations/variants mismatch: {label}:{key}")
        if label.endswith(":block"):
            if not str(record.get("type") or "").strip():
                raise ValueError(f"Missing block type: {label}:{key}")
            if not str(record.get("explanation") or "").strip():
                raise ValueError(f"Missing block explanation: {label}:{key}")


def _atomic_write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def rebuild(root: Path, languages: list[str], *, check: bool) -> dict:
    source_store = LibraryDictionaryStore(root)
    summary: dict[str, dict] = {}
    with tempfile.TemporaryDirectory(prefix="lexo_dictionary_rebuild_") as temp_dir:
        temp_root = Path(temp_dir)
        target_store = LibraryDictionaryStore(temp_root)
        for lang in languages:
            layer_paths = sorted(
                source_store.books_dir(lang).glob(f"*/book_layer_{lang}.json")
            )
            if not layer_paths:
                raise ValueError(f"No book layers for language: {lang}")
            for layer_path in layer_paths:
                payload = _load_object(layer_path)
                payload["target_lang"] = lang
                if not str(payload.get("book_id") or "").strip():
                    payload["book_id"] = layer_path.parent.name
                target_store.merge_book_layer(payload)

            words = _load_object(target_store.global_words_path_for(lang))
            blocks = _load_object(target_store.global_blocks_path_for(lang))
            _validate_records(words, label=f"{lang}:word")
            _validate_records(blocks, label=f"{lang}:block")

            words_path = source_store.global_words_path_for(lang)
            blocks_path = source_store.global_blocks_path_for(lang)
            changed = (
                (not words_path.exists() or _load_object(words_path) != words)
                or (not blocks_path.exists() or _load_object(blocks_path) != blocks)
            )
            if not check:
                _atomic_write(words_path, words)
                _atomic_write(blocks_path, blocks)
            summary[lang] = {
                "books": len(layer_paths),
                "words": len(words),
                "blocks": len(blocks),
                "changed": changed,
            }
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--languages", nargs="+", default=["ru", "uk"])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    summary = rebuild(args.root.resolve(), args.languages, check=args.check)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
