from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any


WORD_RE = re.compile(r"[^\W_]+(?:['’][^\W_]+)*", re.UNICODE)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normalize_word(value: str) -> str:
    return str(value or "").strip().lower().replace("’", "'")


def word_tokens(value: str) -> list[str]:
    return [normalize_word(token) for token in WORD_RE.findall(str(value or ""))]


def short_text(value: str, limit: int = 220) -> str:
    text = " ".join(str(value or "").split())
    return text if len(text) <= limit else f"{text[: limit - 1]}…"


def markdown_escape(value: object) -> str:
    text = str(value or "")
    return text.replace("|", "\\|").replace("\n", "<br>")


def extract_reader_contexts(reader_payload: dict[str, Any]) -> dict[tuple[str, str], list[dict[str, str]]]:
    contexts: dict[tuple[str, str], list[dict[str, str]]] = {}
    for paragraph in reader_payload.get("paragraphs", []):
        for word in paragraph.get("words", []):
            text = normalize_word(word.get("text", ""))
            lemma = normalize_word(word.get("lemma", ""))
            pos = str(word.get("pos") or "").strip()
            context = {
                "source_word": str(word.get("text") or ""),
                "source_segment": str(
                    word.get("segment_source_text")
                    or paragraph.get("source_text")
                    or ""
                ),
                "target_segment": str(
                    word.get("segment_target_text")
                    or paragraph.get("target_text")
                    or ""
                ),
                "focus": str(
                    word.get("effective_focus_text")
                    or word.get("unit_translation_focus_text")
                    or ""
                ),
            }
            for key in {(text, pos), (lemma, pos), (text, ""), (lemma, "")}:
                if key[0]:
                    contexts.setdefault(key, []).append(context)
    return contexts


def context_key(entry: dict[str, Any]) -> tuple[str, str]:
    lemma = normalize_word(entry.get("lemma") or entry.get("query") or "")
    pos = str(entry.get("part_of_speech") or entry.get("detected_part_of_speech") or "").strip()
    return lemma, pos


def context_for_entry(
    entry: dict[str, Any],
    contexts: dict[tuple[str, str], list[dict[str, str]]],
    max_contexts: int,
) -> list[dict[str, str]]:
    lemma, pos = context_key(entry)
    query = normalize_word(entry.get("query") or "")
    candidates = []
    for key in ((lemma, pos), (query, pos), (lemma, ""), (query, "")):
        candidates.extend(contexts.get(key, []))
    seen = set()
    result = []
    for item in candidates:
        marker = (item["source_segment"], item["target_segment"])
        if marker in seen:
            continue
        seen.add(marker)
        result.append(item)
        if len(result) >= max_contexts:
            break
    if result:
        return result
    source_segment = str(entry.get("source_segment") or "")
    target_segment = str(entry.get("target_segment") or "")
    if source_segment or target_segment:
        return [
            {
                "source_word": str(entry.get("query") or ""),
                "source_segment": source_segment,
                "target_segment": target_segment,
                "focus": "",
            }
        ]
    return []


def entry_rows(book_dir: Path, lang: str, max_contexts: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    dictionary_path = book_dir / f"dictionary_{lang}.json"
    reader_path = book_dir / f"reader_{lang}.json"
    if not dictionary_path.exists():
        raise FileNotFoundError(dictionary_path)
    if not reader_path.exists():
        raise FileNotFoundError(reader_path)

    dictionary_payload = read_json(dictionary_path)
    reader_payload = read_json(reader_path)
    contexts = extract_reader_contexts(reader_payload)
    rows = []
    for dictionary_key, entry in dictionary_payload.get("entries", {}).items():
        translations = [
            str(item or "").strip()
            for item in entry.get("translations", [])
            if str(item or "").strip()
        ]
        nested_sources = [
            str(item.get("source") or "").strip()
            for item in entry.get("entries", [])
            if isinstance(item, dict) and str(item.get("source") or "").strip()
        ]
        entry_contexts = context_for_entry(entry, contexts, max_contexts)
        context_lines = [
            f"EN: {short_text(item['source_segment'])}\n{lang.upper()}: {short_text(item['target_segment'])}"
            for item in entry_contexts
        ]
        rows.append(
            {
                "lang": lang,
                "dictionary_key": dictionary_key,
                "query": str(entry.get("query") or ""),
                "lemma": str(entry.get("lemma") or ""),
                "pos": str(
                    entry.get("part_of_speech")
                    or entry.get("detected_part_of_speech")
                    or ""
                ),
                "first_translation": translations[0] if translations else "",
                "translations": "; ".join(translations[:12]),
                "translation_count": len(translations),
                "source": dictionary_payload.get("source", ""),
                "entry_sources": "; ".join(dict.fromkeys(nested_sources)),
                "mt_generated": bool(entry.get("mt_generated")),
                "definitions": " | ".join(str(item) for item in entry.get("definitions", [])[:3]),
                "contexts": "\n\n".join(context_lines),
                "review": "",
                "suggested_override": "",
                "notes": "",
            }
        )
    rows.sort(
        key=lambda row: (
            str(row["pos"]),
            normalize_word(str(row["lemma"] or row["query"])),
            normalize_word(str(row["dictionary_key"])),
        )
    )
    return dictionary_payload, rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "lang",
        "dictionary_key",
        "query",
        "lemma",
        "pos",
        "first_translation",
        "translations",
        "translation_count",
        "source",
        "entry_sources",
        "mt_generated",
        "definitions",
        "contexts",
        "review",
        "suggested_override",
        "notes",
    ]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(path: Path, book_title: str, lang: str, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"# Dictionary Audit: {book_title} [{lang.upper()}]",
        "",
        "Fill `review`, `suggested_override`, and `notes` manually after reading the context.",
        "",
        "| # | key | translation | all translations | context | review | suggested override | notes |",
        "|---:|---|---|---|---|---|---|---|",
    ]
    for index, row in enumerate(rows, start=1):
        key = f"{row['query']} / {row['lemma']} / {row['pos']}"
        lines.append(
            "| "
            + " | ".join(
                [
                    str(index),
                    markdown_escape(key),
                    markdown_escape(row["first_translation"]),
                    markdown_escape(row["translations"]),
                    markdown_escape(row["contexts"]),
                    "",
                    "",
                    "",
                ]
            )
            + " |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(
        description="Build per-book dictionary audit tables for manual review."
    )
    parser.add_argument("book_dir", type=Path, help="Workbench output book directory.")
    parser.add_argument("--langs", nargs="+", default=["ru", "uk"], choices=["ru", "uk"])
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("Studio/Runtime/dictionary_audit"),
    )
    parser.add_argument("--max-contexts", type=int, default=2)
    parser.add_argument("--json", action="store_true", help="Also write combined JSON.")
    args = parser.parse_args()

    manifest_path = args.book_dir / "manifest.json"
    manifest = read_json(manifest_path) if manifest_path.exists() else {}
    book_id = str(manifest.get("book_id") or args.book_dir.name)
    book_title = str(manifest.get("title") or args.book_dir.name)
    output_root = args.out_dir / book_id
    combined = []
    for lang in args.langs:
        _, rows = entry_rows(args.book_dir, lang, args.max_contexts)
        write_csv(output_root / f"dictionary_audit_{lang}.csv", rows)
        write_markdown(output_root / f"dictionary_audit_{lang}.md", book_title, lang, rows)
        combined.extend(rows)
        print(
            f"{lang.upper()}: wrote {len(rows)} rows to "
            f"{output_root / f'dictionary_audit_{lang}.md'}"
        )
    if args.json:
        (output_root / "dictionary_audit.json").write_text(
            json.dumps(combined, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
