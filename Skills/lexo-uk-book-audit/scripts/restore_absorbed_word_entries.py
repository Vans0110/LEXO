from __future__ import annotations

import argparse
import json
from pathlib import Path


def load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Restore absorbed words as empty UK entries")
    parser.add_argument("book_layer", type=Path)
    parser.add_argument("reader", type=Path)
    parser.add_argument("keys", nargs="+")
    args = parser.parse_args()
    layer_path = args.book_layer.resolve()
    seed_path = layer_path.parent / "seed_words_uk.json"
    layer = load(layer_path)
    seed = load(seed_path)
    reader = load(args.reader.resolve())
    if not isinstance(layer, dict) or not isinstance(seed, dict) or not isinstance(reader, dict):
        raise ValueError("expected object layer, seed, and reader")
    keys = {item.strip().lower() for item in args.keys if item.strip()}
    source_words: dict[str, dict] = {}
    for paragraph in reader.get("paragraphs") or []:
        for word in paragraph.get("words") or []:
            if not isinstance(word, dict):
                continue
            lemma = str(word.get("lemma") or word.get("text") or "").strip().lower()
            pos = str(word.get("pos") or "").strip().upper()
            key = f"{lemma}|{pos}".lower()
            source_words.setdefault(
                key,
                {"word": str(word.get("text") or lemma), "lemma": lemma, "pos": pos},
            )
    words = [item for item in layer.get("words") or [] if isinstance(item, dict)]
    existing = {
        f"{str(item.get('lemma') or '').lower()}|{str(item.get('pos') or '').upper()}".lower()
        for item in words
    }
    reason = "meaning is absorbed by a verified block or grammar block"
    for key in sorted(keys):
        if key not in source_words:
            raise ValueError(f"reader word not found: {key}")
        record = {**source_words[key], "translation": "", "translations": [], "empty_reason": reason}
        if key not in existing:
            words.append(record)
        canonical = f"{record['lemma']}|{record['pos']}"
        seed[canonical] = {"translation": "", "translations": [], "empty_reason": reason}
    layer["words"] = words
    audit = layer.get("book_layer_audit")
    if not isinstance(audit, dict):
        raise ValueError("book_layer_audit is required")
    audit["absorbed_word_keys"] = sorted(keys)
    write(seed_path, seed)
    write(layer_path, layer)
    print(json.dumps({"words": len(words), "absorbed": len(keys), "seed_keys": len(seed)}))


if __name__ == "__main__":
    main()

