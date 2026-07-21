from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def normalize_text(value: object) -> str:
    return str(value or "").strip()


def normalize_key_word(value: object) -> str:
    return normalize_text(value).lower()


def dictionary_key(lemma: str, pos: str) -> str:
    return f"{lemma.strip().lower()}|{pos.strip().upper()}"


def dedupe(items: list[str]) -> list[str]:
    result = []
    seen = set()
    for item in items:
        normalized = " ".join(str(item or "").split())
        key = normalized.lower()
        if not normalized or key in seen:
            continue
        seen.add(key)
        result.append(normalized)
    return result


def discover_book_dirs(workbench_output: Path) -> list[Path]:
    result = []
    for cover_path in workbench_output.rglob("cover.png"):
        book_dir = cover_path.parent
        if (book_dir / "dictionary_ru.json").exists() or (book_dir / "dictionary_uk.json").exists():
            result.append(book_dir)
    return sorted(set(result), key=lambda path: str(path).lower())


def entry_values(entry: dict[str, Any]) -> tuple[str, str, list[str]]:
    query = normalize_key_word(entry.get("query"))
    lemma = normalize_key_word(entry.get("lemma")) or query
    pos = normalize_text(
        entry.get("part_of_speech")
        or entry.get("detected_part_of_speech")
        or ""
    )
    translations = dedupe(
        [
            normalize_text(item)
            for item in entry.get("translations", [])
            if normalize_text(item)
        ]
    )
    return lemma, pos, translations


def merge_dictionary_file(
    core: dict[str, Any],
    dictionary_path: Path,
    lang: str,
) -> dict[str, int]:
    if not dictionary_path.exists():
        return {"files": 0, "entries_seen": 0, "created": 0, "languages_added": 0, "skipped": 0}
    payload = read_json(dictionary_path)
    stats = {"files": 1, "entries_seen": 0, "created": 0, "languages_added": 0, "skipped": 0}
    for raw_key, entry in sorted(payload.get("entries", {}).items()):
        if not isinstance(entry, dict):
            continue
        lemma, pos, translations = entry_values(entry)
        if not lemma or not translations:
            continue
        key = dictionary_key(lemma, pos)
        stats["entries_seen"] += 1
        record = core.get(key)
        if not isinstance(record, dict):
            core[key] = {
                "word": lemma,
                "pos": pos,
                "translations": {lang: translations},
            }
            stats["created"] += 1
            continue
        translations_by_lang = record.setdefault("translations", {})
        if not isinstance(translations_by_lang, dict):
            record["translations"] = {}
            translations_by_lang = record["translations"]
        if lang not in translations_by_lang:
            translations_by_lang[lang] = translations
            stats["languages_added"] += 1
        else:
            stats["skipped"] += 1
    return stats


def add_stats(total: dict[str, int], current: dict[str, int]) -> None:
    for key, value in current.items():
        total[key] = total.get(key, 0) + int(value)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(
        description="Extend the shared Virgil Core dictionary from generated Workbench book outputs."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("."),
        help="Repository root.",
    )
    parser.add_argument(
        "--workbench-output",
        type=Path,
        default=Path("Studio/Runtime/workbench_output"),
    )
    parser.add_argument(
        "--core",
        type=Path,
        default=Path("Studio/Backend/data/dictionaries/virgil_core/virgil_core_dictionary.json"),
    )
    parser.add_argument("--langs", nargs="+", default=["ru", "uk"], choices=["ru", "uk"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    workbench_output = (root / args.workbench_output).resolve()
    core_path = (root / args.core).resolve()
    core = read_json(core_path) if core_path.exists() else {}
    if not isinstance(core, dict):
        raise ValueError(f"Core dictionary must be a JSON object: {core_path}")

    book_dirs = discover_book_dirs(workbench_output)
    total = {
        "books": len(book_dirs),
        "files": 0,
        "entries_seen": 0,
        "created": 0,
        "languages_added": 0,
        "skipped": 0,
    }
    for book_dir in book_dirs:
        for lang in args.langs:
            add_stats(total, merge_dictionary_file(core, book_dir / f"dictionary_{lang}.json", lang))

    if not args.dry_run:
        write_json(core_path, core)
    total["core_entries"] = len(core)
    print(json.dumps(total, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
