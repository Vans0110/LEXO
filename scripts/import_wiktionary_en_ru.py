from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import Kaikki/Wiktionary English -> Russian JSONL into SQLite.")
    parser.add_argument(
        "--source",
        default="data/dictionary_sources/wiktionary/kaikki.org-dictionary-English.jsonl",
        help="Path to downloaded Kaikki English JSONL dump.",
    )
    parser.add_argument(
        "--output",
        default="data/dictionaries/wiktionary_en_ru.sqlite",
        help="Output SQLite path.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Optional limit for test imports.",
    )
    return parser.parse_args()


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DROP TABLE IF EXISTS entries;
        DROP TABLE IF EXISTS forms;
        DROP TABLE IF EXISTS translations;
        DROP TABLE IF EXISTS definitions;

        CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lemma TEXT NOT NULL,
            pos TEXT NOT NULL,
            transcript TEXT NOT NULL,
            entry_type TEXT NOT NULL,
            source_lang TEXT NOT NULL
        );

        CREATE TABLE forms (
            form TEXT NOT NULL,
            lemma TEXT NOT NULL,
            pos TEXT NOT NULL
        );

        CREATE TABLE translations (
            entry_id INTEGER NOT NULL,
            translation TEXT NOT NULL,
            sense_index INTEGER NOT NULL,
            priority INTEGER NOT NULL
        );

        CREATE TABLE definitions (
            entry_id INTEGER NOT NULL,
            definition TEXT NOT NULL,
            sense_index INTEGER NOT NULL
        );

        CREATE INDEX idx_entries_lemma ON entries(lemma);
        CREATE INDEX idx_forms_form ON forms(form);
        CREATE INDEX idx_forms_lemma ON forms(lemma);
        CREATE INDEX idx_translations_entry ON translations(entry_id);
        CREATE INDEX idx_definitions_entry ON definitions(entry_id);
        """
    )


def normalize_translation(word: str) -> str:
    return word.replace("[[", "").replace("]]", "").strip()


def entry_type_for_lemma(lemma: str) -> str:
    words = [part for part in lemma.split() if part.strip()]
    if len(words) >= 2:
        return "phrase"
    return "word"


def extract_transcript(item: dict) -> str:
    sounds = item.get("sounds") or []
    ipa = []
    for sound in sounds:
        text = str(sound.get("ipa") or sound.get("enpr") or "").strip()
        if text and text not in ipa:
            ipa.append(text)
    return ", ".join(ipa[:4])


def import_dump(source: Path, output: Path, limit: int = 0) -> tuple[int, int]:
    output.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(output) as conn:
        init_db(conn)
        entry_count = 0
        translation_count = 0
        with source.open("r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                word = str(item.get("word") or "").strip().lower()
                pos = str(item.get("pos") or "").strip().lower()
                if not word or not pos:
                    continue
                senses = item.get("senses") or []
                translations: list[tuple[str, int, int]] = []
                definitions: list[tuple[str, int]] = []
                for sense_index, sense in enumerate(senses):
                    glosses = [str(gloss).strip() for gloss in sense.get("glosses") or [] if str(gloss).strip()]
                    if glosses:
                        definitions.append((glosses[0], sense_index))
                    sense_translations = []
                    for trans in sense.get("translations") or []:
                        if str(trans.get("code") or "") != "ru":
                            continue
                        russian = normalize_translation(str(trans.get("word") or ""))
                        if russian:
                            sense_translations.append(russian)
                    for priority, russian in enumerate(sense_translations):
                        translations.append((russian, sense_index, priority))
                if not translations:
                    continue

                cursor = conn.execute(
                    """
                    INSERT INTO entries(lemma, pos, transcript, entry_type, source_lang)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        word,
                        pos,
                        extract_transcript(item),
                        entry_type_for_lemma(word),
                        "en",
                    ),
                )
                entry_id = int(cursor.lastrowid)
                entry_count += 1

                form_rows = []
                for form in item.get("forms") or []:
                    form_text = str(form.get("form") or "").strip().lower()
                    if form_text:
                        form_rows.append((form_text, word, pos))
                if form_rows:
                    conn.executemany("INSERT INTO forms(form, lemma, pos) VALUES (?, ?, ?)", form_rows)

                conn.executemany(
                    "INSERT INTO translations(entry_id, translation, sense_index, priority) VALUES (?, ?, ?, ?)",
                    [(entry_id, translation, sense_index, priority) for translation, sense_index, priority in translations],
                )
                translation_count += len(translations)

                if definitions:
                    conn.executemany(
                        "INSERT INTO definitions(entry_id, definition, sense_index) VALUES (?, ?, ?)",
                        [(entry_id, definition, sense_index) for definition, sense_index in definitions],
                    )

                if entry_count % 1000 == 0:
                    conn.commit()
                if limit and entry_count >= limit:
                    break
        conn.commit()
    return entry_count, translation_count


def main() -> None:
    args = parse_args()
    source = Path(args.source)
    output = Path(args.output)
    if not source.exists():
        raise SystemExit(f"Source dump not found: {source}")
    entries, translations = import_dump(source=source, output=output, limit=args.limit)
    print(
        json.dumps(
            {
                "ok": True,
                "source": str(source),
                "output": str(output),
                "entries": entries,
                "translations": translations,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
