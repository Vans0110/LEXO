from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


BOOK_IDS = (
    "book_07a16679df53",
    "book_70823d828e5a",
    "book_cad03a8f1779",
    "book_21b2a5a230d7",
    "book_1414bc86ec40",
)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def runtime_dir(runtime_root: Path, book_id: str) -> Path:
    matches = list(runtime_root.rglob(f"{book_id}_*"))
    directories = [path for path in matches if path.is_dir()]
    if len(directories) != 1:
        raise RuntimeError(f"Expected one runtime directory for {book_id}, got {directories}")
    return directories[0]


def canonical_graph(conn: sqlite3.Connection, book_id: str) -> dict:
    paragraphs = conn.execute(
        "SELECT id, order_index, source_text FROM paragraphs WHERE book_id=? ORDER BY order_index",
        (book_id,),
    ).fetchall()
    result = []
    for paragraph in paragraphs:
        segments = conn.execute(
            "SELECT id, order_index, source_text FROM segments WHERE paragraph_id=? ORDER BY order_index",
            (paragraph["id"],),
        ).fetchall()
        segment_items = []
        for segment in segments:
            words = conn.execute(
                """
                SELECT id, order_index_in_segment, surface_text
                FROM source_words WHERE segment_id=? ORDER BY order_index_in_segment
                """,
                (segment["id"],),
            ).fetchall()
            segment_items.append(
                {
                    "id": str(segment["id"]),
                    "order": int(segment["order_index"]),
                    "source": str(segment["source_text"]),
                    "words": [dict(row) for row in words],
                }
            )
        result.append(
            {
                "id": str(paragraph["id"]),
                "order": int(paragraph["order_index"]),
                "source": str(paragraph["source_text"]),
                "segments": segment_items,
            }
        )
    return {"paragraphs": result}


def reader_mapping(reader: dict, canonical: dict) -> tuple[dict[str, str], dict[str, str]]:
    reader_paragraphs = reader.get("paragraphs") or []
    canonical_paragraphs = canonical["paragraphs"]
    if len(reader_paragraphs) != len(canonical_paragraphs):
        raise RuntimeError("Paragraph count mismatch")
    segment_map: dict[str, str] = {}
    word_map: dict[str, str] = {}
    for source_paragraph, target_paragraph in zip(reader_paragraphs, canonical_paragraphs):
        if str(source_paragraph.get("source_text") or "").strip() != target_paragraph["source"].strip():
            raise RuntimeError("Paragraph source mismatch")
        source_segments = source_paragraph.get("segments_v2") or []
        target_segments = target_paragraph["segments"]
        if len(source_segments) != len(target_segments):
            raise RuntimeError("Segment count mismatch")
        words_by_segment: dict[str, list[dict]] = {}
        for word in source_paragraph.get("words") or []:
            words_by_segment.setdefault(str(word.get("segment_id") or ""), []).append(word)
        for source_segment, target_segment in zip(source_segments, target_segments):
            old_segment_id = str(source_segment.get("id") or "")
            if str(source_segment.get("source_text") or "").strip() != target_segment["source"].strip():
                raise RuntimeError("Segment source mismatch")
            segment_map[old_segment_id] = target_segment["id"]
            source_words = sorted(
                words_by_segment.get(old_segment_id, []),
                key=lambda item: int(item.get("order_index_in_segment") or 0),
            )
            target_words = target_segment["words"]
            if len(source_words) != len(target_words):
                raise RuntimeError("Word count mismatch")
            for source_word, target_word in zip(source_words, target_words):
                if str(source_word.get("text") or "").casefold() != str(
                    target_word["surface_text"]
                ).casefold():
                    raise RuntimeError("Word surface mismatch")
                word_map[str(source_word.get("id") or "")] = str(target_word["id"])
    return segment_map, word_map


def replace_ids(value, replacements: dict[str, str]):
    if isinstance(value, dict):
        return {key: replace_ids(item, replacements) for key, item in value.items()}
    if isinstance(value, list):
        return [replace_ids(item, replacements) for item in value]
    if isinstance(value, str):
        if value in replacements:
            return replacements[value]
        for prefix in ("word:", "block:"):
            if value.startswith(prefix) and value[len(prefix) :] in replacements:
                return prefix + replacements[value[len(prefix) :]]
    return value


def migrate(root: Path, apply: bool) -> dict:
    backend = root / "Studio" / "Backend"
    db_path = backend / "data" / "lexo.db"
    runtime_root = root / "Studio" / "Runtime" / "workbench_output"
    dictionaries = backend / "data" / "dictionaries"
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_root = backend / "data" / "migration_backups" / timestamp
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS book_translations (
            book_id TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'ready',
            model_name TEXT NOT NULL DEFAULT '',
            error_message TEXT,
            source_content_hash TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(book_id, target_lang),
            FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS segment_translations (
            segment_id TEXT NOT NULL,
            book_id TEXT NOT NULL,
            target_lang TEXT NOT NULL,
            target_text TEXT NOT NULL DEFAULT '',
            translation_kind TEXT NOT NULL DEFAULT 'none',
            provider_used TEXT NOT NULL DEFAULT '',
            analysis_version TEXT NOT NULL DEFAULT 'source_only_v1',
            segment_meta_json TEXT NOT NULL DEFAULT '{}',
            candidate_count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(segment_id, target_lang),
            FOREIGN KEY(segment_id) REFERENCES segments(id) ON DELETE CASCADE,
            FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
        );
        """
    )
    report = {"apply": apply, "books": [], "backup": str(backup_root)}
    try:
        if apply:
            backup_root.mkdir(parents=True, exist_ok=False)
            shutil.copy2(db_path, backup_root / "lexo.db")
        for book_id in BOOK_IDS:
            canonical = canonical_graph(conn, book_id)
            package_dir = runtime_dir(runtime_root, book_id)
            book_report = {"book_id": book_id, "languages": {}}
            for lang in ("ru", "uk"):
                reader_path = package_dir / f"reader_{lang}.json"
                reader = load_json(reader_path)
                segment_map, word_map = reader_mapping(reader, canonical)
                replacements = {**segment_map, **word_map}
                changed_files = []
                dictionary_dir = dictionaries / f"library_{lang}" / "books" / book_id
                for path in sorted(dictionary_dir.glob("*.json")):
                    payload = load_json(path)
                    migrated = replace_ids(payload, replacements)
                    if migrated != payload:
                        changed_files.append(path.name)
                        if apply:
                            relative = path.relative_to(backend)
                            backup_path = backup_root / relative
                            backup_path.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copy2(path, backup_path)
                            write_json(path, migrated)
                if apply:
                    now = datetime.now(timezone.utc).isoformat()
                    source_hash = conn.execute(
                        "SELECT content_hash FROM books WHERE id=?", (book_id,)
                    ).fetchone()[0]
                    conn.execute(
                        """
                        INSERT INTO book_translations(
                            book_id,target_lang,status,model_name,error_message,
                            source_content_hash,created_at,updated_at
                        ) VALUES (?,?, 'ready','migration',NULL,?,?,?)
                        ON CONFLICT(book_id,target_lang) DO UPDATE SET
                            status='ready', source_content_hash=excluded.source_content_hash,
                            updated_at=excluded.updated_at
                        """,
                        (book_id, lang, source_hash, now, now),
                    )
                    conn.execute(
                        "DELETE FROM segment_translations WHERE book_id=? AND target_lang=?",
                        (book_id, lang),
                    )
                    for paragraph in reader.get("paragraphs") or []:
                        for segment in paragraph.get("segments_v2") or []:
                            conn.execute(
                                """
                                INSERT INTO segment_translations(
                                    segment_id,book_id,target_lang,target_text,
                                    translation_kind,provider_used,analysis_version,
                                    segment_meta_json,candidate_count,updated_at
                                ) VALUES (?,?,?,?,?,?,?,?,?,?)
                                """,
                                (
                                    segment_map[str(segment["id"])],
                                    book_id,
                                    lang,
                                    str(segment.get("target_text") or ""),
                                    str(segment.get("translation_kind") or "none"),
                                    "migration",
                                    str(segment.get("analysis_version") or "source_only_v1"),
                                    "{}",
                                    0,
                                    now,
                                ),
                            )
                book_report["languages"][lang] = {
                    "segments": len(segment_map),
                    "words": len(word_map),
                    "changed_files": changed_files,
                }
            report["books"].append(book_report)
        if apply:
            conn.commit()
    finally:
        conn.close()
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(json.dumps(migrate(args.root.resolve(), args.apply), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
