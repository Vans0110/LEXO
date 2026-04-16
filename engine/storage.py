from __future__ import annotations

import hashlib
import json
import re
import shutil
import sqlite3
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .assembler import assemble_paragraph
from .lexical_enrichment import (
    build_unit_lemma_text,
    build_unit_surface_text,
    direct_meaning_for_word,
    enrich_words,
    grammar_hint_for_word,
    morph_label_for_word,
)
from .segmenter import split_paragraphs, split_study_segments
from .text_loader import normalize_text
from .translator import TranslationProvider, create_default_provider, translate_segment_batch
from .tts.tts_provider import TtsProvider, create_default_tts_provider
from .tts.tts_service import LexoTtsService
from .word_alignment import (
    ARTICLE_WORDS,
    COPULA_WORDS,
    build_context_window,
    build_tap_word_payloads,
    build_word_mappings,
    tokenize_words,
)


ACTIVE_BOOK_STATE_KEY = "active_book_id"
MOBILE_PACKAGE_MAX_PART_BYTES = 64 * 1024


class LexoStorage:
    def __init__(
        self,
        root: Path,
        translator: TranslationProvider | None = None,
        tts_provider: TtsProvider | None = None,
    ) -> None:
        self.root = root
        self.data_dir = root / "data"
        self.books_dir = self.data_dir / "books"
        self.models_dir = self.data_dir / "models"
        self.logs_dir = self.data_dir / "logs"
        self.tts_dir = self.data_dir / "tts"
        self.word_audio_dir = self.data_dir / "word_audio"
        self.db_path = self.data_dir / "lexo.db"
        self.translator = translator or create_default_provider()
        self.tts_provider = tts_provider or create_default_tts_provider()
        self.tts_service = LexoTtsService(self.db_path, self.tts_dir, self.tts_provider)
        self._package_workers: dict[str, threading.Thread] = {}
        self._package_lock = threading.Lock()
        self._ensure_layout()

    def _ensure_layout(self) -> None:
        for path in (
            self.data_dir,
            self.books_dir,
            self.models_dir,
            self.logs_dir,
            self.tts_dir,
            self.word_audio_dir,
        ):
            path.mkdir(parents=True, exist_ok=True)
        self._init_db()
        self._migrate_legacy_current_book()
        self.tts_service.seed_profiles()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS app_state (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS books (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    source_name TEXT NOT NULL,
                    source_lang TEXT NOT NULL,
                    target_lang TEXT NOT NULL,
                    status TEXT NOT NULL,
                    model_name TEXT NOT NULL,
                    error_message TEXT,
                    created_at TEXT NOT NULL,
                    current_paragraph_index INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS paragraphs (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    source_text TEXT NOT NULL,
                    target_text TEXT NOT NULL,
                    FOREIGN KEY(book_id) REFERENCES books(id)
                );
                CREATE TABLE IF NOT EXISTS segments (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    paragraph_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    source_text TEXT NOT NULL,
                    target_text TEXT NOT NULL,
                    segment_type TEXT NOT NULL DEFAULT 'simple_action',
                    translation_kind TEXT NOT NULL DEFAULT 'provider_fallback',
                    FOREIGN KEY(book_id) REFERENCES books(id),
                    FOREIGN KEY(paragraph_id) REFERENCES paragraphs(id)
                );
                CREATE TABLE IF NOT EXISTS source_words (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    paragraph_id TEXT NOT NULL,
                    segment_id TEXT NOT NULL,
                    order_index_in_paragraph INTEGER NOT NULL,
                    order_index_in_segment INTEGER NOT NULL,
                    surface_text TEXT NOT NULL,
                    normalized_text TEXT NOT NULL,
                    is_function_word INTEGER NOT NULL DEFAULT 0,
                    anchor_source_word_id TEXT,
                    FOREIGN KEY(book_id) REFERENCES books(id),
                    FOREIGN KEY(paragraph_id) REFERENCES paragraphs(id),
                    FOREIGN KEY(segment_id) REFERENCES segments(id),
                    FOREIGN KEY(anchor_source_word_id) REFERENCES source_words(id)
                );
                CREATE TABLE IF NOT EXISTS word_alignments (
                    source_word_id TEXT PRIMARY KEY,
                    target_start_index INTEGER NOT NULL,
                    target_end_index INTEGER NOT NULL,
                    target_text TEXT NOT NULL,
                    confidence REAL NOT NULL DEFAULT 0.0,
                    FOREIGN KEY(source_word_id) REFERENCES source_words(id)
                );
                CREATE TABLE IF NOT EXISTS target_tokens (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    paragraph_id TEXT NOT NULL,
                    segment_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    surface_text TEXT NOT NULL,
                    normalized_text TEXT NOT NULL,
                    FOREIGN KEY(book_id) REFERENCES books(id),
                    FOREIGN KEY(paragraph_id) REFERENCES paragraphs(id),
                    FOREIGN KEY(segment_id) REFERENCES segments(id)
                );
                CREATE TABLE IF NOT EXISTS saved_words (
                    id TEXT PRIMARY KEY,
                    book_id TEXT,
                    word TEXT NOT NULL,
                    lemma TEXT NOT NULL,
                    translation TEXT NOT NULL,
                    unit_type TEXT NOT NULL DEFAULT 'LEXICAL',
                    added_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS saved_cards (
                    id TEXT PRIMARY KEY,
                    device_id TEXT NOT NULL DEFAULT '',
                    card_type TEXT NOT NULL,
                    head_text TEXT NOT NULL,
                    surface_text TEXT NOT NULL,
                    lemma TEXT NOT NULL,
                    translation TEXT NOT NULL,
                    example_text TEXT NOT NULL,
                    example_translation TEXT NOT NULL,
                    pos TEXT NOT NULL DEFAULT '',
                    grammar_label TEXT NOT NULL DEFAULT '',
                    morph_label TEXT NOT NULL DEFAULT '',
                    source_book_id TEXT,
                    source_paragraph_id TEXT,
                    source_segment_id TEXT,
                    source_word_id TEXT,
                    source_unit_id TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT,
                    status TEXT NOT NULL DEFAULT 'new',
                    progress_score INTEGER NOT NULL DEFAULT 0,
                    review_count INTEGER NOT NULL DEFAULT 0,
                    last_reviewed_at TEXT
                );
                CREATE TABLE IF NOT EXISTS tts_profiles (
                    id TEXT PRIMARY KEY,
                    engine_id TEXT NOT NULL,
                    voice_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    lang TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS tts_jobs (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    engine_id TEXT NOT NULL,
                    voice_id TEXT NOT NULL,
                    audio_variant TEXT NOT NULL DEFAULT 'base',
                    mode TEXT NOT NULL,
                    status TEXT NOT NULL,
                    playback_state TEXT NOT NULL,
                    current_segment_index INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS tts_segments (
                    id TEXT PRIMARY KEY,
                    job_id TEXT NOT NULL,
                    book_id TEXT NOT NULL,
                    segment_index INTEGER NOT NULL,
                    paragraph_index INTEGER NOT NULL,
                    engine_id TEXT NOT NULL,
                    voice_id TEXT NOT NULL,
                    audio_variant TEXT NOT NULL DEFAULT 'base',
                    source_text TEXT NOT NULL,
                    timings_path TEXT NOT NULL DEFAULT '',
                    audio_path TEXT NOT NULL,
                    duration_ms INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    hash TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS tts_package_jobs (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    voice_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    error_message TEXT
                );
                CREATE TABLE IF NOT EXISTS tts_package_stages (
                    id TEXT PRIMARY KEY,
                    package_job_id TEXT NOT NULL,
                    stage_key TEXT NOT NULL,
                    label TEXT NOT NULL,
                    status TEXT NOT NULL,
                    done_count INTEGER NOT NULL DEFAULT 0,
                    total_count INTEGER NOT NULL DEFAULT 0,
                    error_message TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(package_job_id) REFERENCES tts_package_jobs(id)
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_paragraphs_book_order
                ON paragraphs(book_id, order_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_segments_paragraph_order
                ON segments(paragraph_id, order_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_source_words_segment_order
                ON source_words(segment_id, order_index_in_segment);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_source_words_paragraph_order
                ON source_words(paragraph_id, order_index_in_paragraph);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_words_unique
                ON saved_words(COALESCE(book_id, ''), lemma, translation, unit_type);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_cards_unique
                ON saved_cards(
                    COALESCE(source_book_id, ''),
                    card_type,
                    lemma,
                    translation
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tts_segments_job_order
                ON tts_segments(job_id, segment_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tts_package_stage_unique
                ON tts_package_stages(package_job_id, stage_key);
                """
            )
            self._ensure_book_columns(conn)
            self._ensure_segment_columns(conn)
            self._ensure_source_word_columns(conn)
            self._ensure_target_token_columns(conn)
            self._ensure_saved_card_columns(conn)
            self._ensure_tts_columns(conn)

    def _ensure_book_columns(self, conn: sqlite3.Connection) -> None:
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(books)").fetchall()}
        if "source_path" not in columns:
            conn.execute("ALTER TABLE books ADD COLUMN source_path TEXT")
        if "last_opened_at" not in columns:
            conn.execute("ALTER TABLE books ADD COLUMN last_opened_at TEXT")

    def _ensure_source_word_columns(self, conn: sqlite3.Connection) -> None:
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(source_words)").fetchall()}
        additions = {
            "lemma": "TEXT",
            "pos": "TEXT",
            "morph": "TEXT",
            "lexical_unit_id": "TEXT",
            "lexical_unit_type": "TEXT",
        }
        for name, definition in additions.items():
            if name not in columns:
                conn.execute(f"ALTER TABLE source_words ADD COLUMN {name} {definition}")

    def _ensure_segment_columns(self, conn: sqlite3.Connection) -> None:
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(segments)").fetchall()}
        additions = {
            "segment_type": "TEXT NOT NULL DEFAULT 'simple_action'",
            "translation_kind": "TEXT NOT NULL DEFAULT 'provider_fallback'",
        }
        for name, definition in additions.items():
            if name not in columns:
                conn.execute(f"ALTER TABLE segments ADD COLUMN {name} {definition}")

    def _ensure_target_token_columns(self, conn: sqlite3.Connection) -> None:
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(target_tokens)").fetchall()}
        if not columns:
            return
        if "order_index" not in columns:
            conn.execute("ALTER TABLE target_tokens ADD COLUMN order_index INTEGER")
            if "order_index_in_segment" in columns:
                conn.execute(
                    """
                    UPDATE target_tokens
                    SET order_index = order_index_in_segment
                    WHERE order_index IS NULL
                    """
                )

    def _ensure_saved_card_columns(self, conn: sqlite3.Connection) -> None:
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(saved_cards)").fetchall()}
        additions = {
            "device_id": "TEXT NOT NULL DEFAULT ''",
            "updated_at": "TEXT",
            "deleted_at": "TEXT",
        }
        for name, definition in additions.items():
            if name not in columns:
                conn.execute(f"ALTER TABLE saved_cards ADD COLUMN {name} {definition}")
        conn.execute(
            """
            UPDATE saved_cards
            SET updated_at = COALESCE(updated_at, created_at)
            WHERE updated_at IS NULL OR updated_at = ''
            """
        )

    def _ensure_tts_columns(self, conn: sqlite3.Connection) -> None:
        job_columns = {row["name"] for row in conn.execute("PRAGMA table_info(tts_jobs)").fetchall()}
        job_additions = {
            "level_id": "INTEGER NOT NULL DEFAULT 1",
            "level_name": "TEXT NOT NULL DEFAULT ''",
            "target_wpm": "INTEGER NOT NULL DEFAULT 164",
            "audio_variant": "TEXT NOT NULL DEFAULT 'base'",
            "native_rate": "REAL NOT NULL DEFAULT 0.89",
            "rate": "REAL NOT NULL DEFAULT 1.0",
            "pause_scale": "REAL NOT NULL DEFAULT 1.0",
            "total_segments": "INTEGER NOT NULL DEFAULT 0",
            "ready_segments": "INTEGER NOT NULL DEFAULT 0",
            "error_message": "TEXT",
        }
        for name, definition in job_additions.items():
            if name not in job_columns:
                conn.execute(f"ALTER TABLE tts_jobs ADD COLUMN {name} {definition}")

        segment_columns = {row["name"] for row in conn.execute("PRAGMA table_info(tts_segments)").fetchall()}
        if "audio_variant" not in segment_columns:
            conn.execute("ALTER TABLE tts_segments ADD COLUMN audio_variant TEXT NOT NULL DEFAULT 'base'")
        if "timings_path" not in segment_columns:
            conn.execute("ALTER TABLE tts_segments ADD COLUMN timings_path TEXT NOT NULL DEFAULT ''")
        if "synthesis_text" not in segment_columns:
            conn.execute("ALTER TABLE tts_segments ADD COLUMN synthesis_text TEXT")
        if "pause_after_ms" not in segment_columns:
            conn.execute("ALTER TABLE tts_segments ADD COLUMN pause_after_ms INTEGER NOT NULL DEFAULT 0")
        conn.execute(
            """
            UPDATE tts_segments
            SET synthesis_text = source_text
            WHERE synthesis_text IS NULL OR synthesis_text = ''
            """
        )

    _PACKAGE_STAGE_LABELS = {
        "base_audio": "Base audio",
        "slow_audio": "Slow audio",
        "word_audio": "Word audio",
    }

    def _migrate_legacy_current_book(self) -> None:
        legacy_source = self.data_dir / "current_book" / "source.txt"
        if not legacy_source.exists():
            return
        migrated_source = self._book_source_path("current-book")
        migrated_source.parent.mkdir(parents=True, exist_ok=True)
        if not migrated_source.exists():
            shutil.copyfile(legacy_source, migrated_source)
        with self._connect() as conn:
            row = conn.execute("SELECT id, source_path, last_opened_at, created_at FROM books WHERE id = ?", ("current-book",)).fetchone()
            if row is None:
                return
            last_opened_at = row["last_opened_at"] or row["created_at"]
            conn.execute(
                "UPDATE books SET source_path = ?, last_opened_at = COALESCE(last_opened_at, ?) WHERE id = ?",
                (str(migrated_source), last_opened_at, "current-book"),
            )

    def import_book(self, source_path: str, source_lang: str = "en", target_lang: str = "ru") -> dict:
        source = self._normalize_import_source_path(source_path)
        if not source.exists() or not source.is_file():
            raise FileNotFoundError(f"TXT file not found: {source_path}")
        if source.suffix.lower() != ".txt":
            raise ValueError("Only .txt files are supported in MVP")

        raw_text = source.read_text(encoding="utf-8", errors="ignore")
        return self._import_book_text(
            title=source.stem,
            source_name=source.name,
            raw_text=raw_text,
            source_lang=source_lang,
            target_lang=target_lang,
            copy_from=source,
        )

    def import_book_text(
        self,
        title: str,
        source_text: str,
        source_lang: str = "en",
        target_lang: str = "ru",
    ) -> dict:
        return self._import_book_text(
            title=title,
            source_name=f"{self._normalize_title(title)}.txt",
            raw_text=source_text,
            source_lang=source_lang,
            target_lang=target_lang,
        )

    def _import_book_text(
        self,
        *,
        title: str,
        source_name: str,
        raw_text: str,
        source_lang: str,
        target_lang: str,
        copy_from: Path | None = None,
    ) -> dict:
        paragraphs = split_paragraphs(normalize_text(raw_text))
        if not paragraphs:
            raise ValueError("TXT file does not contain readable paragraphs")

        book_id = f"book_{uuid.uuid4().hex[:12]}"
        created_at = datetime.now(timezone.utc).isoformat()
        book_source_path = self._book_source_path(book_id)
        book_source_path.parent.mkdir(parents=True, exist_ok=True)
        if copy_from is not None:
            shutil.copyfile(copy_from, book_source_path)
        else:
            book_source_path.write_text("\n\n".join(paragraphs), encoding="utf-8")
        normalized_title = self._normalize_title(title)
        normalized_source_name = source_name or f"{normalized_title}.txt"

        self._mark_processing(
            book_id,
            normalized_title,
            normalized_source_name,
            source_lang,
            target_lang,
            created_at,
            str(book_source_path),
        )
        try:
            payloads = self._build_paragraph_payloads(paragraphs, source_lang, target_lang)
            self._replace_book_content(
                book_id,
                normalized_title,
                normalized_source_name,
                source_lang,
                target_lang,
                created_at,
                str(book_source_path),
                payloads,
            )
            self.set_active_book(book_id)
        except Exception as exc:
            self._mark_error(book_id, str(exc))
            raise
        return self.get_book_status(book_id)

    def build_mobile_book_package(self, book_id: str) -> dict:
        status = self.get_book_status(book_id)
        if not status.get("has_book"):
            raise ValueError(f"Book not found: {book_id}")
        reader_payload = self.get_paragraphs(book_id)
        source_text = self._read_book_source_text(book_id)
        content_hash = self._compute_content_hash(source_text)
        return {
            "meta": {
                "local_book_id": book_id,
                "desktop_book_id": book_id,
                "title": status.get("title"),
                "source_name": status.get("source_name"),
                "source_lang": status.get("source_lang"),
                "target_lang": status.get("target_lang"),
                "model_name": status.get("model_name"),
                "status": status.get("status"),
                "current_paragraph_index": status.get("current_paragraph_index", 0),
                "package_version": 1,
                "content_hash": content_hash,
                "exported_at": datetime.now(timezone.utc).isoformat(),
            },
            "source_text": source_text,
            "reader_payload": reader_payload,
            "tts_manifest": self._build_mobile_tts_manifest(book_id),
            "word_audio_manifest": self._build_mobile_word_audio_manifest(book_id),
            "detail_manifest": self._build_mobile_detail_manifest(book_id, reader_payload),
        }

    def build_mobile_book_package_manifest(self, book_id: str) -> dict:
        package = self.build_mobile_book_package(book_id)
        parts = self._build_mobile_book_package_parts(package)
        return {
            "book_id": book_id,
            "meta": package["meta"],
            "parts": [
                {
                    "part_id": part["part_id"],
                    "kind": part["kind"],
                    "size_bytes": len(json.dumps(part["payload"], ensure_ascii=False).encode("utf-8")),
                }
                for part in parts
            ],
        }

    def build_mobile_book_package_part(self, book_id: str, part_id: str) -> dict:
        package = self.build_mobile_book_package(book_id)
        parts = self._build_mobile_book_package_parts(package)
        for part in parts:
            if part["part_id"] == part_id:
                return {
                    "book_id": book_id,
                    "part_id": part_id,
                    "kind": part["kind"],
                    "payload": part["payload"],
                }
        raise ValueError(f"Package part not found: {part_id}")

    def get_tts_audio_path(self, book_id: str, job_id: str, segment_index: int) -> Path:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT audio_path
                FROM tts_segments
                WHERE book_id = ? AND job_id = ? AND segment_index = ?
                """,
                (book_id, job_id, segment_index),
            ).fetchone()
        if row is None:
            raise ValueError("TTS segment not found")
        audio_path = Path(str(row["audio_path"]))
        if not audio_path.exists() or not audio_path.is_file():
            raise FileNotFoundError(f"Audio file not found: {audio_path}")
        return audio_path

    def get_tts_timings(self, book_id: str, job_id: str, segment_index: int) -> list[dict]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT timings_path
                FROM tts_segments
                WHERE book_id = ? AND job_id = ? AND segment_index = ?
                """,
                (book_id, job_id, segment_index),
            ).fetchone()
        if row is None:
            raise ValueError("TTS segment not found")
        timings_path_raw = str(row["timings_path"] or "")
        if not timings_path_raw:
            return []
        timings_path = Path(timings_path_raw)
        if not timings_path.exists() or not timings_path.is_file():
            return []
        payload = json.loads(timings_path.read_text(encoding="utf-8"))
        if not isinstance(payload, list):
            return []
        return [item for item in payload if isinstance(item, dict)]

    def get_word_audio_path(self, word: str, voice_id: str | None = None) -> Path:
        return self._ensure_word_audio_path(word, voice_id=voice_id, overwrite=False)

    def list_books(self) -> dict:
        with self._connect() as conn:
            active_book_id = self._resolve_book_id(conn, None)
            rows = conn.execute(
                """
                SELECT id, title, source_name, source_lang, target_lang, status, model_name,
                       error_message, created_at, last_opened_at, current_paragraph_index, source_path
                FROM books
                ORDER BY COALESCE(last_opened_at, created_at) DESC, created_at DESC
                """
            ).fetchall()
        return {
            "active_book_id": active_book_id,
            "items": [
                {
                    "id": row["id"],
                    "title": row["title"],
                    "source_name": row["source_name"],
                    "source_lang": row["source_lang"],
                    "target_lang": row["target_lang"],
                    "status": row["status"],
                    "model_name": row["model_name"],
                    "error_message": row["error_message"],
                    "created_at": row["created_at"],
                    "last_opened_at": row["last_opened_at"],
                    "current_paragraph_index": row["current_paragraph_index"],
                    "content_hash": self._book_content_hash(str(row["id"])),
                    "is_active": row["id"] == active_book_id,
                }
                for row in rows
            ],
        }

    def set_active_book(self, book_id: str) -> dict:
        timestamp = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            exists = conn.execute("SELECT id FROM books WHERE id = ?", (book_id,)).fetchone()
            if exists is None:
                raise ValueError(f"Book not found: {book_id}")
            conn.execute(
                """
                INSERT INTO app_state(key, value) VALUES(?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (ACTIVE_BOOK_STATE_KEY, book_id),
            )
            conn.execute("UPDATE books SET last_opened_at = ? WHERE id = ?", (timestamp, book_id))
        return self.get_book_status(book_id)

    def delete_book(self, book_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute("SELECT id FROM books WHERE id = ?", (book_id,)).fetchone()
            if row is None:
                raise ValueError(f"Book not found: {book_id}")
            active_book_id = self._get_active_book_id(conn)
            busy_job = conn.execute(
                """
                SELECT id FROM tts_jobs
                WHERE book_id = ? AND status IN ('queued', 'generating')
                LIMIT 1
                """,
                (book_id,),
            ).fetchone()
            if busy_job is not None:
                raise ValueError("Cannot delete book while TTS generation is in progress")

            conn.execute("DELETE FROM tts_segments WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM tts_jobs WHERE book_id = ?", (book_id,))
            conn.execute(
                "DELETE FROM word_alignments WHERE source_word_id IN (SELECT id FROM source_words WHERE book_id = ?)",
                (book_id,),
            )
            conn.execute("DELETE FROM target_tokens WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM source_words WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM segments WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM paragraphs WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM books WHERE id = ?", (book_id,))

            next_active_book_id = active_book_id
            if active_book_id == book_id:
                next_row = conn.execute(
                    "SELECT id FROM books ORDER BY COALESCE(last_opened_at, created_at) DESC LIMIT 1"
                ).fetchone()
                if next_row is None:
                    conn.execute("DELETE FROM app_state WHERE key = ?", (ACTIVE_BOOK_STATE_KEY,))
                    next_active_book_id = None
                else:
                    next_active_book_id = str(next_row["id"])
                    conn.execute(
                        """
                        INSERT INTO app_state(key, value) VALUES(?, ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """,
                        (ACTIVE_BOOK_STATE_KEY, next_active_book_id),
                    )

        shutil.rmtree(self.books_dir / book_id, ignore_errors=True)
        shutil.rmtree(self.tts_dir / book_id, ignore_errors=True)
        return {"ok": True, "deleted_book_id": book_id, "active_book_id": next_active_book_id}

    def get_book_status(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
            if resolved_book_id is None:
                return {"has_book": False, "status": "empty"}
            row = conn.execute("SELECT * FROM books WHERE id = ?", (resolved_book_id,)).fetchone()
            count_row = conn.execute(
                "SELECT COUNT(*) AS count FROM paragraphs WHERE book_id = ?",
                (resolved_book_id,),
            ).fetchone()
        if row is None:
            return {"has_book": False, "status": "empty"}
        return self._book_row_to_status(row, int(count_row["count"]) if count_row is not None else 0)

    def get_paragraphs(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
            if resolved_book_id is None:
                return {"book_id": None, "title": None, "status": "empty", "current_paragraph_index": 0, "paragraphs": []}
            row = conn.execute("SELECT * FROM books WHERE id = ?", (resolved_book_id,)).fetchone()
            paragraph_rows = conn.execute(
                """
                SELECT id, order_index, source_text, target_text
                FROM paragraphs
                WHERE book_id = ?
                ORDER BY order_index
                """,
                (resolved_book_id,),
            ).fetchall()
            word_rows = conn.execute(
                """
                SELECT sw.id, sw.paragraph_id, sw.order_index_in_paragraph, sw.surface_text, sw.normalized_text, sw.anchor_source_word_id,
                       sw.lemma, sw.pos, sw.morph, sw.lexical_unit_id, sw.lexical_unit_type,
                       sw.segment_id, segments.source_text AS segment_source_text, segments.target_text AS segment_target_text,
                       segments.segment_type, segments.translation_kind AS segment_translation_kind,
                       wa.target_start_index, wa.target_end_index, wa.target_text
                FROM source_words sw
                JOIN segments ON segments.id = sw.segment_id
                LEFT JOIN word_alignments wa ON wa.source_word_id = sw.id
                WHERE sw.book_id = ?
                ORDER BY sw.paragraph_id, sw.order_index_in_paragraph
                """,
                (resolved_book_id,),
            ).fetchall()
        if row is None:
            return {"book_id": None, "title": None, "status": "empty", "current_paragraph_index": 0, "paragraphs": []}
        words_by_paragraph: dict[str, list[dict]] = {}
        words_by_segment: dict[tuple[str, str], list[dict]] = {}
        for word_row in word_rows:
            segment_key = (str(word_row["paragraph_id"]), str(word_row["segment_id"]))
            words_by_segment.setdefault(segment_key, []).append(
                {
                    "id": word_row["id"],
                    "text": word_row["surface_text"],
                    "normalized_text": word_row["normalized_text"],
                    "order_index": int(word_row["order_index_in_paragraph"]),
                    "anchor_word_id": word_row["anchor_source_word_id"],
                    "target_start_index": int(word_row["target_start_index"]) if word_row["target_start_index"] is not None else -1,
                    "target_end_index": int(word_row["target_end_index"]) if word_row["target_end_index"] is not None else -1,
                    "translation_span_text": word_row["target_text"] or "",
                    "segment_source_text": str(word_row["segment_source_text"] or ""),
                    "segment_target_text": str(word_row["segment_target_text"] or ""),
                    "segment_type": str(word_row["segment_type"] or "simple_action"),
                    "segment_translation_kind": str(word_row["segment_translation_kind"] or "provider_fallback"),
                    "lemma": str(word_row["lemma"] or ""),
                    "pos": str(word_row["pos"] or ""),
                    "morph": str(word_row["morph"] or ""),
                    "lexical_unit_id": str(word_row["lexical_unit_id"] or ""),
                    "lexical_unit_type": str(word_row["lexical_unit_type"] or ""),
                    "grammar_hint": grammar_hint_for_word(word_row),
                    "morph_label": morph_label_for_word(word_row),
                }
            )
        for (paragraph_id, _segment_id), segment_words in words_by_segment.items():
            paragraph_words = words_by_paragraph.setdefault(paragraph_id, [])
            payload_words = build_tap_word_payloads(
                segment_target_text=segment_words[0]["segment_target_text"] if segment_words else "",
                words=segment_words,
            )
            paragraph_words.extend(self._annotate_quality_payloads(payload_words))
        for paragraph_words in words_by_paragraph.values():
            paragraph_words.sort(key=lambda item: int(item["order_index"]))
        return {
            "book_id": resolved_book_id,
            "title": row["title"],
            "status": row["status"],
            "source_lang": row["source_lang"],
            "target_lang": row["target_lang"],
            "current_paragraph_index": row["current_paragraph_index"],
            "paragraphs": [
                {
                    "index": item["order_index"],
                    "source_text": item["source_text"],
                    "target_text": item["target_text"],
                    "words": paragraph_words,
                    "tokens": self._build_reader_tokens(
                        source_text=item["source_text"],
                        words=paragraph_words,
                    ),
                }
                for item in paragraph_rows
                for paragraph_words in [
                    words_by_paragraph.get(str(item["id"]))
                    or self._annotate_quality_payloads(self._build_runtime_word_payload(
                        source_text=item["source_text"],
                        target_text=item["target_text"],
                    ))
                ]
            ],
        }

    def _build_reader_tokens(self, source_text: str, words: list[dict]) -> list[dict]:
        if not source_text:
            return []

        tokens: list[dict] = []
        cursor = 0
        previous_word: dict | None = None

        for word in words:
            word_text = str(word.get("text") or "")
            if not word_text:
                continue

            match_index = source_text.find(word_text, cursor)
            if match_index < 0:
                match_index = cursor

            if match_index > cursor:
                self._append_gap_tokens(
                    tokens=tokens,
                    gap_text=source_text[cursor:match_index],
                    tap_unit_id=self._resolve_gap_tap_unit_id(previous_word, word),
                )

            tokens.append(
                {
                    "id": f"t_{len(tokens)}",
                    "text": word_text,
                    "kind": "word",
                    "order_index": len(tokens),
                    "tap_unit_id": word.get("tap_unit_id"),
                    "word_id": word.get("id"),
                }
            )
            cursor = match_index + len(word_text)
            previous_word = word

        if cursor < len(source_text):
            self._append_gap_tokens(
                tokens=tokens,
                gap_text=source_text[cursor:],
                tap_unit_id=None,
            )

        return tokens

    def _append_gap_tokens(
        self,
        tokens: list[dict],
        gap_text: str,
        tap_unit_id: str | None,
    ) -> None:
        if not gap_text:
            return

        for piece in re.findall(r"\s+|[^\s]+", gap_text):
            tokens.append(
                {
                    "id": f"t_{len(tokens)}",
                    "text": piece,
                    "kind": "whitespace" if piece.isspace() else "punctuation",
                    "order_index": len(tokens),
                    "tap_unit_id": tap_unit_id,
                    "word_id": None,
                }
            )

    def _resolve_gap_tap_unit_id(self, previous_word: dict | None, next_word: dict | None) -> str | None:
        if previous_word is None or next_word is None:
            return None
        previous_unit_id = previous_word.get("tap_unit_id")
        next_unit_id = next_word.get("tap_unit_id")
        if previous_unit_id and previous_unit_id == next_unit_id:
            return str(previous_unit_id)
        return None

    def save_reader_position(self, book_id: str, paragraph_index: int) -> dict:
        with self._connect() as conn:
            updated = conn.execute(
                "UPDATE books SET current_paragraph_index = ? WHERE id = ?",
                (paragraph_index, book_id),
            ).rowcount
        if updated == 0:
            raise ValueError(f"No such book: {book_id}")
        return {"ok": True, "book_id": book_id, "current_paragraph_index": paragraph_index}

    def get_tts_profiles(self) -> dict:
        return self.tts_service.get_profiles()

    def get_detail_sheet(self, book_id: str, word_id: str) -> dict:
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
            if resolved_book_id is None:
                raise ValueError(f"Book not found: {book_id}")
            selected_row = conn.execute(
                """
                SELECT paragraph_id
                FROM source_words
                WHERE id = ? AND book_id = ?
                """,
                (word_id, resolved_book_id),
            ).fetchone()
            if selected_row is None:
                raise ValueError(f"Word not found: {word_id}")
            paragraph_id = str(selected_row["paragraph_id"])
            word_rows = conn.execute(
                """
                SELECT sw.id, sw.paragraph_id, sw.segment_id, sw.order_index_in_paragraph, sw.surface_text, sw.normalized_text,
                       sw.anchor_source_word_id, sw.lemma, sw.pos, sw.morph, sw.lexical_unit_id, sw.lexical_unit_type,
                       segments.source_text AS segment_source_text, segments.target_text AS segment_target_text,
                       segments.segment_type, segments.translation_kind AS segment_translation_kind,
                       wa.target_start_index, wa.target_end_index, wa.target_text
                FROM source_words sw
                JOIN segments ON segments.id = sw.segment_id
                LEFT JOIN word_alignments wa ON wa.source_word_id = sw.id
                WHERE sw.book_id = ? AND sw.paragraph_id = ?
                ORDER BY sw.segment_id, sw.order_index_in_segment
                """,
                (resolved_book_id, paragraph_id),
            ).fetchall()

        paragraph_words = [
            {
                "id": str(word_row["id"]),
                "segment_id": str(word_row["segment_id"]),
                "text": str(word_row["surface_text"]),
                "normalized_text": str(word_row["normalized_text"]),
                "order_index": int(word_row["order_index_in_paragraph"]),
                "anchor_word_id": word_row["anchor_source_word_id"],
                "target_start_index": int(word_row["target_start_index"]) if word_row["target_start_index"] is not None else -1,
                "target_end_index": int(word_row["target_end_index"]) if word_row["target_end_index"] is not None else -1,
                "translation_span_text": str(word_row["target_text"] or ""),
                "segment_source_text": str(word_row["segment_source_text"] or ""),
                "segment_target_text": str(word_row["segment_target_text"] or ""),
                "segment_type": str(word_row["segment_type"] or "simple_action"),
                "segment_translation_kind": str(word_row["segment_translation_kind"] or "provider_fallback"),
                "lemma": str(word_row["lemma"] or ""),
                "pos": str(word_row["pos"] or ""),
                "morph": str(word_row["morph"] or ""),
                "lexical_unit_id": str(word_row["lexical_unit_id"] or ""),
                "lexical_unit_type": str(word_row["lexical_unit_type"] or ""),
                "grammar_hint": grammar_hint_for_word(word_row),
                "morph_label": morph_label_for_word(word_row),
            }
            for word_row in word_rows
        ]
        tap_words = self._annotate_quality_payloads(self._build_detail_tap_words(paragraph_words))
        selected_word = next((item for item in tap_words if item["id"] == word_id), None)
        if selected_word is None:
            raise ValueError(f"Word not found in reader payload: {word_id}")

        selected_tap_unit_id = str(selected_word.get("tap_unit_id") or "")
        selected_unit_words = [
            item
            for item in tap_words
            if str(item.get("tap_unit_id") or "") == selected_tap_unit_id
        ]
        selected_unit_words.sort(key=lambda item: int(item["order_index"]))
        special_detail = self._build_special_detail_sheet(selected_word, selected_unit_words)
        if special_detail is not None:
            return special_detail
        detail_units = self._build_detail_units(selected_unit_words)
        selected_lexical_unit_id = str(selected_word.get("lexical_unit_id") or "")
        if selected_lexical_unit_id:
            detail_units.sort(
                key=lambda item: 0 if str(item.get("id") or "") == selected_lexical_unit_id else 1
            )
        if selected_word.get("quality_state") == "untranslated" and detail_units:
            detail_units[0]["translation"] = (
                str(detail_units[0].get("surface_text") or detail_units[0].get("text") or "").strip()
            )
        return {
            "word_id": word_id,
            "tap_unit_id": selected_tap_unit_id,
            "sheet_source_text": str(selected_word.get("source_unit_text") or selected_word.get("text") or ""),
            "sheet_translation_text": str(
                selected_word.get("unit_translation_focus_text")
                or selected_word.get("unit_translation_span_text")
                or selected_word.get("translation_focus_text")
                or selected_word.get("translation_span_text")
                or ""
            ),
            "example_source_text": str(selected_word.get("segment_source_text") or ""),
            "example_translation_text": str(selected_word.get("segment_target_text") or ""),
            "quality_state": str(selected_word.get("quality_state") or ""),
            "rule_id": str(selected_word.get("rule_id") or ""),
            "rule_type": str(selected_word.get("rule_type") or ""),
            "is_phrase_member": int(selected_word.get("is_phrase_member") or 0),
            "grammar_hint": str(selected_word.get("grammar_hint") or ""),
            "units": detail_units,
        }

    def save_detail_unit(self, book_id: str, word_id: str, unit_id: str) -> dict:
        detail = self.get_detail_sheet(book_id, word_id)
        unit = next((item for item in detail["units"] if str(item.get("id") or "") == unit_id), None)
        if unit is None:
            raise ValueError(f"Detail unit not found: {unit_id}")
        unit_type = str(unit.get("type") or "LEXICAL")
        if unit_type == "GRAMMAR":
            raise ValueError("Grammar rows are not saved by default")

        added_at = datetime.now(timezone.utc).isoformat()
        word = str(unit.get("surface_text") or unit.get("text") or "").strip()
        lemma = str(unit.get("lemma") or unit.get("text") or word).strip()
        translation = str(unit.get("translation") or "").strip()
        if not translation and unit_type != "LEXICAL":
            translation = str(detail.get("sheet_translation_text") or "").strip()
        word_row = self._get_source_word_row(word_id)
        card_type = unit_type.lower()
        head_text = str(unit.get("text") or lemma or word).strip()
        example_text = str(unit.get("example_source_text") or detail.get("example_source_text") or "").strip()
        example_translation = str(
            unit.get("example_translation_text") or detail.get("example_translation_text") or ""
        ).strip()
        pos = str(word_row["pos"] or "")
        grammar_label = str(unit.get("grammar_hint") or "").strip()
        morph_label = str(unit.get("morph_label") or "").strip()
        with self._connect() as conn:
            existing_card = conn.execute(
                """
                SELECT *
                FROM saved_cards
                WHERE COALESCE(source_book_id, '') = COALESCE(?, '')
                  AND card_type = ?
                  AND lemma = ?
                  AND translation = ?
                LIMIT 1
                """,
                (book_id, card_type, lemma, translation),
            ).fetchone()
            if existing_card is not None:
                return {
                    "ok": True,
                    "saved": False,
                    "item": self._saved_card_to_payload(existing_card),
                }
            existing_word = conn.execute(
                """
                SELECT id, word, lemma, translation, unit_type, added_at
                FROM saved_words
                WHERE COALESCE(book_id, '') = COALESCE(?, '')
                  AND lemma = ?
                  AND translation = ?
                  AND unit_type = ?
                LIMIT 1
                """,
                (book_id, lemma, translation, unit_type),
            ).fetchone()
            card_id = f"card_{uuid.uuid4().hex[:12]}"
            conn.execute(
                """
                INSERT INTO saved_cards(
                    id,
                    device_id,
                    card_type,
                    head_text,
                    surface_text,
                    lemma,
                    translation,
                    example_text,
                    example_translation,
                    pos,
                    grammar_label,
                    morph_label,
                    source_book_id,
                    source_paragraph_id,
                    source_segment_id,
                    source_word_id,
                    source_unit_id,
                    created_at,
                    updated_at,
                    deleted_at,
                    status,
                    progress_score,
                    review_count,
                    last_reviewed_at
                )
                VALUES (?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 'new', 0, 0, NULL)
                """,
                (
                    card_id,
                    card_type,
                    head_text,
                    word,
                    lemma,
                    translation,
                    example_text,
                    example_translation,
                    pos,
                    grammar_label,
                    morph_label,
                    book_id,
                    str(word_row["paragraph_id"] or ""),
                    str(word_row["segment_id"] or ""),
                    word_id,
                    unit_id,
                    added_at,
                    added_at,
                ),
            )
            if existing_word is None:
                conn.execute(
                    """
                    INSERT INTO saved_words(id, book_id, word, lemma, translation, unit_type, added_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (f"saved_{uuid.uuid4().hex[:12]}", book_id, word, lemma, translation, unit_type, added_at),
                )
        return {
            "ok": True,
            "saved": True,
            "item": {
                "id": card_id,
                "device_id": "",
                "card_type": card_type,
                "head_text": head_text,
                "surface_text": word,
                "lemma": lemma,
                "translation": translation,
                "example_text": example_text,
                "example_translation": example_translation,
                "pos": pos,
                "grammar_label": grammar_label,
                "morph_label": morph_label,
                "source_book_id": book_id,
                "source_unit_id": unit_id,
                "created_at": added_at,
                "updated_at": added_at,
                "deleted_at": "",
                "sync_state": "synced",
                "status": "new",
                "progress_score": 0,
                "review_count": 0,
                "last_reviewed_at": None,
            },
        }

    def list_saved_cards(self, status: str | None = None) -> dict:
        query = """
            SELECT *
            FROM saved_cards
            WHERE deleted_at IS NULL OR deleted_at = ''
        """
        params: list[object] = []
        normalized_status = (status or "").strip().lower()
        if normalized_status:
            query += " AND status = ?"
            params.append(normalized_status)
        query += " ORDER BY updated_at DESC, created_at DESC"
        with self._connect() as conn:
            rows = conn.execute(query, tuple(params)).fetchall()
        items = [self._saved_card_to_payload(row) for row in rows]
        return {
            "items": items,
            "summary": self._build_cards_summary(items),
        }

    def get_review_cards(self) -> dict:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT *
                FROM saved_cards
                WHERE card_type IN ('lexical', 'phrase')
                  AND (deleted_at IS NULL OR deleted_at = '')
                ORDER BY progress_score ASC, created_at ASC
                LIMIT 50
                """
            ).fetchall()
        items = [self._saved_card_to_payload(row) for row in rows]
        return {
            "items": items,
            "summary": self._build_cards_summary(items),
        }

    def apply_review_result(self, card_id: str, direction: str) -> dict:
        normalized_direction = (direction or "").strip().lower()
        if normalized_direction not in {"left", "right"}:
            raise ValueError("Direction must be left or right")
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM saved_cards WHERE id = ? AND (deleted_at IS NULL OR deleted_at = '')",
                (card_id,),
            ).fetchone()
            if row is None:
                raise ValueError(f"Card not found: {card_id}")
            current_score = int(row["progress_score"] or 0)
            if normalized_direction == "right":
                next_score = min(7, current_score + 1)
            else:
                next_score = max(0, current_score - 1) if current_score > 1 else current_score
            next_status = self._status_for_score(next_score)
            reviewed_at = datetime.now(timezone.utc).isoformat()
            review_count = int(row["review_count"] or 0) + 1
            conn.execute(
                """
                UPDATE saved_cards
                SET progress_score = ?, status = ?, review_count = ?, last_reviewed_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (next_score, next_status, review_count, reviewed_at, reviewed_at, card_id),
            )
            updated = conn.execute("SELECT * FROM saved_cards WHERE id = ?", (card_id,)).fetchone()
        return {
            "ok": True,
            "item": self._saved_card_to_payload(updated),
        }

    def delete_saved_card(self, card_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT *
                FROM saved_cards
                WHERE id = ?
                LIMIT 1
                """,
                (card_id,),
            ).fetchone()
            if row is None:
                raise ValueError(f"Card not found: {card_id}")
            deleted_at = datetime.now(timezone.utc).isoformat()
            conn.execute(
                """
                UPDATE saved_cards
                SET deleted_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (deleted_at, deleted_at, card_id),
            )
        return {
            "ok": True,
            "deleted": True,
            "item": self._saved_card_to_payload(row),
        }

    def sync_mobile_cards_full(
        self,
        device_id: str,
        cards_delta: list[dict],
        last_sync_at: str | None = None,
    ) -> dict:
        del last_sync_at
        with self._connect() as conn:
            for payload in cards_delta:
                self._merge_mobile_card(conn, device_id, payload)
            rows = conn.execute(
                """
                SELECT *
                FROM saved_cards
                ORDER BY updated_at DESC, created_at DESC
                """
            ).fetchall()
        return {
            "merged_cards_count": len(rows),
            "server_sync_time": datetime.now(timezone.utc).isoformat(),
        }

    def _merge_mobile_card(self, conn: sqlite3.Connection, device_id: str, payload: dict) -> None:
        card_id = str(payload.get("id") or payload.get("card_uuid") or "").strip()
        if not card_id:
            return
        existing = conn.execute("SELECT * FROM saved_cards WHERE id = ?", (card_id,)).fetchone()
        if existing is None:
            existing = conn.execute(
                """
                SELECT *
                FROM saved_cards
                WHERE COALESCE(source_book_id, '') = ?
                  AND card_type = ?
                  AND lemma = ?
                  AND translation = ?
                LIMIT 1
                """,
                (
                    str(payload.get("source_book_id") or payload.get("origin_book_uuid") or ""),
                    str(payload.get("card_type") or "lexical"),
                    str(payload.get("lemma") or ""),
                    str(payload.get("translation") or ""),
                ),
            ).fetchone()
        incoming_updated_at = self._normalize_sync_timestamp(payload.get("updated_at") or payload.get("created_at"))
        incoming_deleted_at = self._normalize_optional_sync_timestamp(payload.get("deleted_at"))
        if existing is not None:
            existing_updated_at = self._normalize_sync_timestamp(existing["updated_at"] or existing["created_at"])
            existing_deleted_at = self._normalize_optional_sync_timestamp(existing["deleted_at"])
            if existing_deleted_at and not incoming_deleted_at and incoming_updated_at <= existing_updated_at:
                return
            if incoming_deleted_at and incoming_updated_at < existing_updated_at:
                return
            if not existing_deleted_at and incoming_updated_at < existing_updated_at and not incoming_deleted_at:
                return
        values = self._card_payload_to_row_values(device_id, payload, incoming_updated_at, incoming_deleted_at)
        if existing is None:
            conn.execute(
                """
                INSERT INTO saved_cards(
                    id, device_id, card_type, head_text, surface_text, lemma, translation,
                    example_text, example_translation, pos, grammar_label, morph_label,
                    source_book_id, source_paragraph_id, source_segment_id, source_word_id,
                    source_unit_id, created_at, updated_at, deleted_at, status, progress_score,
                    review_count, last_reviewed_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', '', '', ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values,
            )
            return
        conn.execute(
            """
            UPDATE saved_cards
            SET device_id = ?, card_type = ?, head_text = ?, surface_text = ?, lemma = ?, translation = ?,
                example_text = ?, example_translation = ?, pos = ?, grammar_label = ?, morph_label = ?,
                source_book_id = ?, source_unit_id = ?, created_at = ?, updated_at = ?, deleted_at = ?,
                status = ?, progress_score = ?, review_count = ?, last_reviewed_at = ?
            WHERE id = ?
            """,
            values[1:] + (str(existing["id"]),),
        )

    def _card_payload_to_row_values(
        self,
        device_id: str,
        payload: dict,
        updated_at: str,
        deleted_at: str | None,
    ) -> tuple[object, ...]:
        created_at = self._normalize_sync_timestamp(payload.get("created_at") or updated_at)
        return (
            str(payload.get("id") or payload.get("card_uuid") or ""),
            str(payload.get("device_id") or device_id or ""),
            str(payload.get("card_type") or "lexical"),
            str(payload.get("head_text") or ""),
            str(payload.get("surface_text") or ""),
            str(payload.get("lemma") or ""),
            str(payload.get("translation") or ""),
            str(payload.get("example_text") or payload.get("context_source") or ""),
            str(payload.get("example_translation") or payload.get("context_target") or ""),
            str(payload.get("pos") or ""),
            str(payload.get("grammar_label") or ""),
            str(payload.get("morph_label") or ""),
            str(payload.get("source_book_id") or payload.get("origin_book_uuid") or ""),
            str(payload.get("source_unit_id") or payload.get("origin_unit_id") or ""),
            created_at,
            updated_at,
            deleted_at,
            str(payload.get("status") or "new"),
            int(payload.get("progress_score") or 0),
            int(payload.get("review_count") or 0),
            str(payload.get("last_reviewed_at") or ""),
        )

    def _normalize_sync_timestamp(self, value: object | None) -> str:
        text = str(value or "").strip()
        if not text:
            return datetime.now(timezone.utc).isoformat()
        return text

    def _normalize_optional_sync_timestamp(self, value: object | None) -> str | None:
        text = str(value or "").strip()
        return text or None

    def list_saved_words(self) -> dict:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT word, lemma, translation, added_at
                FROM saved_words
                ORDER BY added_at DESC
                """
            ).fetchall()
        return {
            "items": [
                {
                    "word": str(row["word"]),
                    "lemma": str(row["lemma"]),
                    "translation": str(row["translation"]),
                    "added_at": str(row["added_at"]),
                }
                for row in rows
            ]
        }

    def save_raw_word(self, word: str) -> dict:
        normalized_word = (word or "").strip()
        if not normalized_word:
            raise ValueError("Word is empty")
        added_at = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            existing = conn.execute(
                """
                SELECT word, lemma, translation, added_at
                FROM saved_words
                WHERE COALESCE(book_id, '') = ''
                  AND lemma = ?
                  AND translation = ''
                  AND unit_type = 'LEXICAL'
                LIMIT 1
                """,
                (normalized_word.lower(),),
            ).fetchone()
            if existing is not None:
                return {
                    "ok": True,
                    "saved": False,
                    "item": {
                        "word": str(existing["word"]),
                        "lemma": str(existing["lemma"]),
                        "translation": str(existing["translation"]),
                        "added_at": str(existing["added_at"]),
                    },
                }
            conn.execute(
                """
                INSERT INTO saved_words(id, book_id, word, lemma, translation, unit_type, added_at)
                VALUES (?, NULL, ?, ?, '', 'LEXICAL', ?)
                """,
                (f"saved_{uuid.uuid4().hex[:12]}", normalized_word, normalized_word.lower(), added_at),
            )
        return {
            "ok": True,
            "saved": True,
            "item": {
                "word": normalized_word,
                "lemma": normalized_word.lower(),
                "translation": "",
                "added_at": added_at,
            },
        }

    def _get_source_word_row(self, word_id: str) -> sqlite3.Row:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT id, paragraph_id, segment_id, pos
                FROM source_words
                WHERE id = ?
                LIMIT 1
                """,
                (word_id,),
            ).fetchone()
        if row is None:
            raise ValueError(f"Word not found: {word_id}")
        return row

    def _saved_card_to_payload(self, row: sqlite3.Row) -> dict:
        return {
            "id": str(row["id"]),
            "device_id": str(row["device_id"] or ""),
            "card_type": str(row["card_type"]),
            "head_text": str(row["head_text"]),
            "surface_text": str(row["surface_text"]),
            "lemma": str(row["lemma"]),
            "translation": str(row["translation"]),
            "example_text": str(row["example_text"]),
            "example_translation": str(row["example_translation"]),
            "pos": str(row["pos"]),
            "grammar_label": str(row["grammar_label"]),
            "morph_label": str(row["morph_label"]),
            "source_book_id": str(row["source_book_id"] or ""),
            "source_unit_id": str(row["source_unit_id"] or ""),
            "created_at": str(row["created_at"]),
            "updated_at": str(row["updated_at"] or row["created_at"]),
            "deleted_at": str(row["deleted_at"] or ""),
            "sync_state": "synced",
            "status": str(row["status"]),
            "progress_score": int(row["progress_score"] or 0),
            "review_count": int(row["review_count"] or 0),
            "last_reviewed_at": str(row["last_reviewed_at"] or ""),
        }

    def _build_cards_summary(self, items: list[dict]) -> dict:
        summary = {
            "total": len(items),
            "new": 0,
            "learning": 0,
            "known": 0,
            "mastered": 0,
        }
        for item in items:
            status = str(item.get("status") or "new")
            if status in summary:
                summary[status] += 1
        return summary

    def _status_for_score(self, score: int) -> str:
        if score <= 0:
            return "new"
        if score <= 3:
            return "learning"
        if score <= 5:
            return "known"
        return "mastered"

    def get_tts_levels(self) -> dict:
        return self.tts_service.get_levels()

    def generate_tts_jobs(
        self,
        book_id: str,
        voice_id: str,
        level_ids: list[int],
        mode: str = "play_from_current",
        overwrite: bool = False,
    ) -> dict:
        return self.tts_service.generate_jobs(
            book_id=book_id,
            voice_id=voice_id,
            level_ids=level_ids,
            mode=mode,
            overwrite=overwrite,
        )

    def generate_tts_package(
        self,
        book_id: str,
        voice_id: str,
        overwrite: bool = False,
        overwrite_word_audio: bool = False,
    ) -> dict:
        return self.start_tts_package_generation(
            book_id=book_id,
            voice_id=voice_id,
            overwrite=overwrite,
            overwrite_word_audio=overwrite_word_audio,
        )

    def get_tts_package(self, book_id: str, voice_id: str) -> dict:
        return self.get_tts_package_state(book_id=book_id, voice_id=voice_id)

    def start_tts_job(self, book_id: str, job_id: str) -> dict:
        return self.tts_service.start_playback(book_id=book_id, job_id=job_id)

    def control_tts(self, book_id: str, job_id: str, action: str) -> dict:
        return self.tts_service.control(book_id=book_id, job_id=job_id, action=action)

    def get_tts_state(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
        if resolved_book_id is None:
            return {"jobs": [], "active_job": None, "active_segments": []}
        return self.tts_service.get_state(book_id=resolved_book_id)

    def start_tts_package_generation(
        self,
        book_id: str,
        voice_id: str,
        overwrite: bool = False,
        overwrite_word_audio: bool = False,
    ) -> dict:
        timestamp = datetime.now(timezone.utc).isoformat()
        package_job_id = f"tts_package_{uuid.uuid4().hex[:12]}"
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
            if resolved_book_id is None:
                raise ValueError(f"Book not found: {book_id}")
            existing = conn.execute(
                """
                SELECT id
                FROM tts_package_jobs
                WHERE book_id = ? AND voice_id = ? AND status IN ('queued', 'running')
                LIMIT 1
                """,
                (resolved_book_id, voice_id),
            ).fetchone()
            if existing is not None:
                raise ValueError("TTS package generation is already in progress for this voice")
            conn.execute(
                """
                INSERT INTO tts_package_jobs(id, book_id, voice_id, status, created_at, updated_at, error_message)
                VALUES (?, ?, ?, ?, ?, ?, NULL)
                """,
                (package_job_id, resolved_book_id, voice_id, "queued", timestamp, timestamp),
            )
            for stage_key, label in self._PACKAGE_STAGE_LABELS.items():
                conn.execute(
                    """
                    INSERT INTO tts_package_stages(
                        id, package_job_id, stage_key, label, status, done_count, total_count,
                        error_message, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, 0, 0, NULL, ?, ?)
                    """,
                    (f"{package_job_id}_{stage_key}", package_job_id, stage_key, label, "pending", timestamp, timestamp),
                )
        self._start_tts_package_worker(
            package_job_id=package_job_id,
            overwrite=overwrite,
            overwrite_word_audio=overwrite_word_audio,
        )
        return self.get_tts_package_state(book_id=book_id, voice_id=voice_id)

    def get_tts_package_state(self, book_id: str, voice_id: str) -> dict:
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
            if resolved_book_id is None:
                return {
                    "book_id": book_id,
                    "voice_id": voice_id,
                    "status": "idle",
                    "package_job_id": "",
                    "stages": [],
                }
            job = conn.execute(
                """
                SELECT *
                FROM tts_package_jobs
                WHERE book_id = ? AND voice_id = ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (resolved_book_id, voice_id),
            ).fetchone()
            if job is None:
                return {
                    "book_id": resolved_book_id,
                    "voice_id": voice_id,
                    "status": "idle",
                    "package_job_id": "",
                    "stages": [],
                }
            stage_rows = conn.execute(
                """
                SELECT stage_key, label, status, done_count, total_count, error_message
                FROM tts_package_stages
                WHERE package_job_id = ?
                ORDER BY CASE stage_key
                    WHEN 'base_audio' THEN 1
                    WHEN 'slow_audio' THEN 2
                    WHEN 'word_audio' THEN 3
                    ELSE 99
                END
                """,
                (job["id"],),
            ).fetchall()
        return {
            "book_id": resolved_book_id,
            "voice_id": voice_id,
            "package_job_id": str(job["id"]),
            "status": str(job["status"] or "idle"),
            "error_message": str(job["error_message"] or ""),
            "stages": [
                {
                    "stage_key": str(row["stage_key"]),
                    "label": str(row["label"]),
                    "status": str(row["status"]),
                    "done_count": int(row["done_count"] or 0),
                    "total_count": int(row["total_count"] or 0),
                    "error_message": str(row["error_message"] or ""),
                }
                for row in stage_rows
            ],
        }

    def _start_tts_package_worker(
        self,
        *,
        package_job_id: str,
        overwrite: bool,
        overwrite_word_audio: bool,
    ) -> None:
        worker = threading.Thread(
            target=self._run_tts_package_job,
            args=(package_job_id, overwrite, overwrite_word_audio),
            daemon=True,
        )
        with self._package_lock:
            self._package_workers[package_job_id] = worker
        worker.start()

    def _run_tts_package_job(
        self,
        package_job_id: str,
        overwrite: bool,
        overwrite_word_audio: bool,
    ) -> None:
        try:
            with self._connect() as conn:
                job = conn.execute(
                    "SELECT book_id, voice_id FROM tts_package_jobs WHERE id = ?",
                    (package_job_id,),
                ).fetchone()
            if job is None:
                return
            book_id = str(job["book_id"])
            voice_id = str(job["voice_id"])
            base_level_id = self._resolve_level_id_for_variant("base")
            slow_level_id = self._resolve_level_id_for_variant("slow_native")
            self._update_package_job_status(package_job_id, "running")
            self._run_package_audio_stage(
                package_job_id=package_job_id,
                stage_key="base_audio",
                book_id=book_id,
                voice_id=voice_id,
                level_id=base_level_id,
                audio_variant="base",
                overwrite=overwrite,
            )
            self._run_package_audio_stage(
                package_job_id=package_job_id,
                stage_key="slow_audio",
                book_id=book_id,
                voice_id=voice_id,
                level_id=slow_level_id,
                audio_variant="slow_native",
                overwrite=overwrite,
            )
            self._run_package_word_stage(
                package_job_id=package_job_id,
                book_id=book_id,
                voice_id=voice_id,
                overwrite_word_audio=overwrite_word_audio,
            )
            self._update_package_job_status(package_job_id, "done")
        except Exception as exc:
            self._update_package_job_status(package_job_id, "error", error_message=str(exc))
        finally:
            with self._package_lock:
                self._package_workers.pop(package_job_id, None)

    def _run_package_audio_stage(
        self,
        *,
        package_job_id: str,
        stage_key: str,
        book_id: str,
        voice_id: str,
        level_id: int,
        audio_variant: str,
        overwrite: bool,
    ) -> None:
        self._update_package_stage(package_job_id, stage_key, status="running", error_message="")
        existing = self._find_tts_job_for_variant(book_id=book_id, voice_id=voice_id, audio_variant=audio_variant)
        if not overwrite:
            if existing is not None and existing["status"] == "ready":
                total = int(existing["total_segments"] or 0)
                ready = int(existing["ready_segments"] or 0)
                self._update_package_stage(
                    package_job_id,
                    stage_key,
                    status="done",
                    done_count=ready,
                    total_count=total,
                    error_message="",
                )
                return
            if existing is not None and existing["status"] in {"queued", "generating"}:
                self._poll_package_audio_stage(
                    package_job_id=package_job_id,
                    stage_key=stage_key,
                    book_id=book_id,
                    voice_id=voice_id,
                    audio_variant=audio_variant,
                )
                return
        else:
            if existing is not None and existing["status"] in {"queued", "generating"}:
                raise RuntimeError(f"Cannot overwrite {audio_variant} while generation is already in progress")
        self.tts_service.generate_jobs(
            book_id=book_id,
            voice_id=voice_id,
            level_ids=[level_id],
            overwrite=overwrite,
        )
        self._poll_package_audio_stage(
            package_job_id=package_job_id,
            stage_key=stage_key,
            book_id=book_id,
            voice_id=voice_id,
            audio_variant=audio_variant,
        )

    def _poll_package_audio_stage(
        self,
        *,
        package_job_id: str,
        stage_key: str,
        book_id: str,
        voice_id: str,
        audio_variant: str,
    ) -> None:
        while True:
            state = self.tts_service.get_state(book_id)
            job = next(
                (
                    item
                    for item in state["jobs"]
                    if str(item.get("voice_id") or "") == voice_id
                    and str(item.get("audio_variant") or "base") == audio_variant
                ),
                None,
            )
            if job is None:
                time.sleep(0.2)
                continue
            total = int(job.get("total_segments") or 0)
            ready = int(job.get("ready_segments") or 0)
            status = str(job.get("status") or "queued")
            self._update_package_stage(
                package_job_id,
                stage_key,
                status="running" if status in {"queued", "generating"} else status,
                done_count=ready,
                total_count=total,
                error_message=str(job.get("error_message") or ""),
            )
            if status == "ready":
                self._update_package_stage(
                    package_job_id,
                    stage_key,
                    status="done",
                    done_count=ready,
                    total_count=total,
                    error_message="",
                )
                return
            if status == "error":
                raise RuntimeError(str(job.get("error_message") or f"{audio_variant} generation failed"))
            time.sleep(0.35)

    def _run_package_word_stage(
        self,
        *,
        package_job_id: str,
        book_id: str,
        voice_id: str,
        overwrite_word_audio: bool,
    ) -> None:
        self._update_package_stage(package_job_id, "word_audio", status="running", error_message="")
        entries = self._collect_book_word_audio_entries(book_id)
        total = len(entries)
        self._update_package_stage(package_job_id, "word_audio", status="running", total_count=total)
        for index, entry in enumerate(entries, start=1):
            self._ensure_word_audio_path(entry, voice_id=voice_id, overwrite=overwrite_word_audio)
            self._update_package_stage(
                package_job_id,
                "word_audio",
                status="running",
                done_count=index,
                total_count=total,
                error_message="",
            )
        self._update_package_stage(
            package_job_id,
            "word_audio",
            status="done",
            done_count=total,
            total_count=total,
            error_message="",
        )

    def _collect_book_word_audio_entries(self, book_id: str) -> list[str]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT lemma, normalized_text, lexical_unit_type
                FROM source_words
                WHERE book_id = ?
                ORDER BY order_index_in_paragraph
                """,
                (book_id,),
            ).fetchall()
        entries: list[str] = []
        seen: set[str] = set()
        for row in rows:
            lexical_unit_type = str(row["lexical_unit_type"] or "").upper()
            normalized = str(row["normalized_text"] or "").strip().lower()
            lemma = str(row["lemma"] or "").strip().lower()
            candidate = lemma or normalized
            if not candidate:
                continue
            if lexical_unit_type == "GRAMMAR":
                continue
            if candidate in ARTICLE_WORDS or candidate in COPULA_WORDS:
                continue
            if not re.search(r"[a-z]", candidate):
                continue
            if candidate in seen:
                continue
            seen.add(candidate)
            entries.append(candidate)
        return entries

    def _ensure_word_audio_path(self, word: str, voice_id: str | None = None, overwrite: bool = False) -> Path:
        normalized = str(word or "").strip()
        if not normalized:
            raise ValueError("Word is required")
        profiles = [item for item in self.tts_provider.list_profiles() if int(item.get("is_enabled", 0)) == 1]
        if not profiles:
            raise ValueError("No TTS voice profiles available")
        selected_profile = profiles[0]
        if voice_id is not None:
            for item in profiles:
                if str(item.get("voice_id") or "") == voice_id:
                    selected_profile = item
                    break
        selected_voice_id = str(selected_profile.get("voice_id") or "")
        engine_id = str(selected_profile.get("engine_id") or self.tts_provider.engine_id)
        cache_key = hashlib.sha256(f"{engine_id}|{selected_voice_id}|{normalized.lower()}".encode("utf-8")).hexdigest()
        audio_dir = self.word_audio_dir / engine_id / selected_voice_id
        audio_dir.mkdir(parents=True, exist_ok=True)
        audio_path = audio_dir / f"{cache_key}.wav"
        if audio_path.exists() and audio_path.is_file() and not overwrite:
            return audio_path
        if overwrite and audio_path.exists() and audio_path.is_file():
            audio_path.unlink(missing_ok=True)
        self.tts_provider.synthesize(
            normalized,
            selected_voice_id,
            audio_path,
            rate=0.89,
        )
        if not audio_path.exists() or not audio_path.is_file():
            raise FileNotFoundError(f"Word audio file not found: {audio_path}")
        return audio_path

    def _find_tts_job_for_variant(self, *, book_id: str, voice_id: str, audio_variant: str) -> sqlite3.Row | None:
        with self._connect() as conn:
            return conn.execute(
                """
                SELECT *
                FROM tts_jobs
                WHERE book_id = ? AND voice_id = ? AND audio_variant = ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (book_id, voice_id, audio_variant),
            ).fetchone()

    def _resolve_level_id_for_variant(self, audio_variant: str) -> int:
        levels = self.tts_service.get_levels().get("items", [])
        for item in levels:
            if str(item.get("audio_variant") or "base") == audio_variant:
                return int(item["id"])
        raise ValueError(f"No TTS level configured for audio variant '{audio_variant}'")

    def _update_package_job_status(self, package_job_id: str, status: str, error_message: str | None = None) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE tts_package_jobs
                SET status = ?, error_message = ?, updated_at = ?
                WHERE id = ?
                """,
                (status, error_message, datetime.now(timezone.utc).isoformat(), package_job_id),
            )

    def _update_package_stage(
        self,
        package_job_id: str,
        stage_key: str,
        *,
        status: str | None = None,
        done_count: int | None = None,
        total_count: int | None = None,
        error_message: str | None = None,
    ) -> None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT status, done_count, total_count, error_message FROM tts_package_stages WHERE package_job_id = ? AND stage_key = ?",
                (package_job_id, stage_key),
            ).fetchone()
            if row is None:
                return
            conn.execute(
                """
                UPDATE tts_package_stages
                SET status = ?, done_count = ?, total_count = ?, error_message = ?, updated_at = ?
                WHERE package_job_id = ? AND stage_key = ?
                """,
                (
                    status if status is not None else row["status"],
                    done_count if done_count is not None else int(row["done_count"] or 0),
                    total_count if total_count is not None else int(row["total_count"] or 0),
                    error_message if error_message is not None else str(row["error_message"] or ""),
                    datetime.now(timezone.utc).isoformat(),
                    package_job_id,
                    stage_key,
                ),
            )

    def _mark_processing(
        self,
        book_id: str,
        title: str,
        source_name: str,
        source_lang: str,
        target_lang: str,
        created_at: str,
        source_path: str,
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO books(
                    id, title, source_name, source_lang, target_lang, status, model_name,
                    error_message, created_at, current_paragraph_index, source_path, last_opened_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, 0, ?, ?)
                """,
                (
                    book_id,
                    title,
                    source_name,
                    source_lang,
                    target_lang,
                    "processing",
                    self.translator.model_name,
                    created_at,
                    source_path,
                    created_at,
                ),
            )

    def _replace_book_content(
        self,
        book_id: str,
        title: str,
        source_name: str,
        source_lang: str,
        target_lang: str,
        created_at: str,
        source_path: str,
        paragraph_payloads: list[dict],
    ) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE books
                SET title = ?, source_name = ?, source_lang = ?, target_lang = ?, status = ?,
                    model_name = ?, error_message = NULL, created_at = ?, current_paragraph_index = 0,
                    source_path = ?, last_opened_at = ?
                WHERE id = ?
                """,
                (
                    title,
                    source_name,
                    source_lang,
                    target_lang,
                    "ready",
                    self.translator.model_name,
                    created_at,
                    source_path,
                    created_at,
                    book_id,
                ),
            )
            conn.executemany(
                "INSERT INTO paragraphs(id, book_id, order_index, source_text, target_text) VALUES (?, ?, ?, ?, ?)",
                [(item["id"], book_id, item["order_index"], item["source_text"], item["target_text"]) for item in paragraph_payloads],
            )
            conn.executemany(
                """
                INSERT INTO segments(
                    id, book_id, paragraph_id, order_index, source_text, target_text, segment_type, translation_kind
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        segment["id"],
                        book_id,
                        segment["paragraph_id"],
                        segment["order_index"],
                        segment["source_text"],
                        segment["target_text"],
                        segment.get("segment_type", "simple_action"),
                        segment.get("translation_kind", "provider_fallback"),
                    )
                    for paragraph in paragraph_payloads
                    for segment in paragraph["segments"]
                ],
            )
            conn.executemany(
                """
                INSERT INTO source_words(
                    id, book_id, paragraph_id, segment_id, order_index_in_paragraph, order_index_in_segment,
                    surface_text, normalized_text, is_function_word, anchor_source_word_id,
                    lemma, pos, morph, lexical_unit_id, lexical_unit_type
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        word["id"],
                        book_id,
                        paragraph["id"],
                        word["segment_id"],
                        word["order_index_in_paragraph"],
                        word["order_index_in_segment"],
                        word["surface_text"],
                        word["normalized_text"],
                        word["is_function_word"],
                        word["anchor_source_word_id"],
                        word.get("lemma"),
                        word.get("pos"),
                        word.get("morph"),
                        word.get("lexical_unit_id"),
                        word.get("lexical_unit_type"),
                    )
                    for paragraph in paragraph_payloads
                    for word in paragraph["words"]
                ],
            )
            conn.executemany(
                """
                INSERT INTO word_alignments(
                    source_word_id, target_start_index, target_end_index, target_text, confidence
                ) VALUES (?, ?, ?, ?, ?)
                """,
                [
                    (
                        alignment["source_word_id"],
                        alignment["target_start_index"],
                        alignment["target_end_index"],
                        alignment["target_text"],
                        alignment["confidence"],
                    )
                    for paragraph in paragraph_payloads
                    for alignment in paragraph["alignments"]
                ],
            )
            target_token_columns = {
                row["name"] for row in conn.execute("PRAGMA table_info(target_tokens)").fetchall()
            }
            target_token_rows = [
                token
                for paragraph in paragraph_payloads
                for token in paragraph.get("target_tokens", [])
            ]
            if target_token_rows:
                if "order_index_in_segment" in target_token_columns:
                    conn.executemany(
                        """
                        INSERT INTO target_tokens(
                            id, book_id, paragraph_id, segment_id, order_index_in_segment, order_index, surface_text, normalized_text
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            (
                                token["id"],
                                book_id,
                                token["paragraph_id"],
                                token["segment_id"],
                                token["order_index_in_segment"],
                                token["order_index"],
                                token["surface_text"],
                                token["normalized_text"],
                            )
                            for token in target_token_rows
                        ],
                    )
                else:
                    conn.executemany(
                        """
                        INSERT INTO target_tokens(
                            id, book_id, paragraph_id, segment_id, order_index, surface_text, normalized_text
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            (
                                token["id"],
                                book_id,
                                token["paragraph_id"],
                                token["segment_id"],
                                token["order_index"],
                                token["surface_text"],
                                token["normalized_text"],
                            )
                            for token in target_token_rows
                        ],
                    )

    def _build_paragraph_payloads(self, paragraphs: list[str], source_lang: str, target_lang: str) -> list[dict]:
        payloads: list[dict] = []
        for index, paragraph_text in enumerate(paragraphs):
            source_segments = split_study_segments(paragraph_text)
            translated_payloads = translate_segment_batch(
                provider=self.translator,
                segments=source_segments,
                source_lang=source_lang,
                target_lang=target_lang,
            )
            if len(translated_payloads) != len(source_segments):
                raise ValueError("Translator returned a mismatched number of segments")
            paragraph_id = str(uuid.uuid4())
            paragraph_words: list[dict] = []
            paragraph_alignments: list[dict] = []
            paragraph_target_tokens: list[dict] = []
            paragraph_word_offset = 0
            segment_payloads: list[dict] = []
            global_target_token_index = 0
            for segment_index, (segment_spec, translated_payload) in enumerate(
                zip(source_segments, translated_payloads, strict=True)
            ):
                source_text = str(segment_spec.get("source_text") or "")
                target_text = str(translated_payload.get("target_text") or "")
                segment_id = str(uuid.uuid4())
                words, alignments = build_word_mappings(
                    source_text=source_text,
                    target_text=target_text,
                    paragraph_start_index=paragraph_word_offset,
                )
                enrich_words(words)
                local_to_global_ids: dict[str, str] = {}
                for word in words:
                    local_word_id = word["id"]
                    global_word_id = f"{paragraph_id}_{local_word_id}"
                    local_to_global_ids[local_word_id] = global_word_id
                    lexical_unit_id = str(word.get("lexical_unit_id") or "")
                    for local_prefix, global_prefix in local_to_global_ids.items():
                        if lexical_unit_id.startswith(local_prefix):
                            word["lexical_unit_id"] = lexical_unit_id.replace(local_prefix, global_prefix, 1)
                            break
                    word["id"] = global_word_id
                    word["segment_id"] = segment_id
                    anchor_index = word.pop("anchor_order_index_in_segment")
                    anchor_paragraph_index = paragraph_word_offset + anchor_index
                    word["anchor_source_word_id"] = f"{paragraph_id}_w_{anchor_paragraph_index}"
                for alignment in alignments:
                    alignment["source_word_id"] = local_to_global_ids[alignment["source_word_id"]]
                paragraph_words.extend(words)
                paragraph_alignments.extend(alignments)
                for segment_token_index, token in enumerate(tokenize_words(target_text)):
                    paragraph_target_tokens.append(
                        {
                            "id": f"{segment_id}_tt_{global_target_token_index}",
                            "paragraph_id": paragraph_id,
                            "segment_id": segment_id,
                            "order_index_in_segment": segment_token_index,
                            "order_index": global_target_token_index,
                            "surface_text": token["text"],
                            "normalized_text": token["normalized"],
                        }
                    )
                    global_target_token_index += 1
                paragraph_word_offset += len(words)
                segment_payloads.append(
                    {
                        "id": segment_id,
                        "paragraph_id": paragraph_id,
                        "order_index": segment_index,
                        "source_text": source_text,
                        "target_text": target_text,
                        "segment_type": str(segment_spec.get("segment_type") or "simple_action"),
                        "translation_kind": str(
                            translated_payload.get("translation_kind")
                            or segment_spec.get("translation_kind")
                            or "provider_fallback"
                        ),
                    }
                )
            payloads.append(
                {
                    "id": paragraph_id,
                    "order_index": index,
                    "source_text": paragraph_text,
                    "target_text": assemble_paragraph(
                        [str(item.get("target_text") or "") for item in translated_payloads]
                    ),
                    "segments": segment_payloads,
                    "words": paragraph_words,
                    "alignments": paragraph_alignments,
                    "target_tokens": paragraph_target_tokens,
                }
            )
        return payloads

    def _build_runtime_word_payload(self, source_text: str, target_text: str) -> list[dict]:
        words, alignments = build_word_mappings(
            source_text=source_text,
            target_text=target_text,
            paragraph_start_index=0,
        )
        enrich_words(words)
        alignment_by_word_id = {item["source_word_id"]: item for item in alignments}
        raw_words: list[dict] = []
        for word in words:
            alignment = alignment_by_word_id.get(word["id"])
            raw_words.append(
                {
                    "id": word["id"],
                    "text": word["surface_text"],
                    "normalized_text": word["normalized_text"],
                    "order_index": word["order_index_in_paragraph"],
                    "anchor_word_id": f"w_{word['anchor_order_index_in_segment']}",
                    "target_start_index": alignment["target_start_index"] if alignment is not None else -1,
                    "target_end_index": alignment["target_end_index"] if alignment is not None else -1,
                    "translation_span_text": alignment["target_text"] if alignment is not None else "",
                    "segment_source_text": source_text,
                    "segment_target_text": target_text,
                    "segment_type": "simple_action",
                    "segment_translation_kind": "provider_fallback",
                    "lemma": word.get("lemma", ""),
                    "pos": word.get("pos", ""),
                    "morph": word.get("morph", ""),
                    "lexical_unit_id": word.get("lexical_unit_id", ""),
                    "lexical_unit_type": word.get("lexical_unit_type", ""),
                    "grammar_hint": grammar_hint_for_word(word),
                    "morph_label": morph_label_for_word(word),
                }
            )
        return build_tap_word_payloads(segment_target_text=target_text, words=raw_words)

    def _annotate_quality_payloads(self, words: list[dict]) -> list[dict]:
        annotated: list[dict] = []
        for word in words:
            normalized = str(word.get("normalized_text") or word.get("text") or "").lower()
            source_text = str(word.get("text") or "")
            translation_span = str(word.get("translation_span_text") or "").strip()
            direct_meaning = str(direct_meaning_for_word(word) or "").strip()
            segment_kind = str(word.get("segment_translation_kind") or "provider_fallback")
            segment_source = str(word.get("segment_source_text") or "")
            is_phrase_member = self._is_phrase_rule_member(word)
            is_it_be = self._is_it_be_word(word)
            is_grammar_only = normalized in ARTICLE_WORDS or normalized in COPULA_WORDS
            translation_has_latin = any("a" <= char.lower() <= "z" for char in translation_span)
            is_untranslated = (
                not is_grammar_only
                and (
                    (
                        source_text.strip()
                        and translation_span.strip().lower() == source_text.strip().lower()
                    )
                    or (
                        segment_kind == "provider_fallback"
                        and translation_has_latin
                    )
                )
            )
            quality_state = "aligned"
            translation_kind = segment_kind
            alignment_kind = "lexical"
            matched_by = "alignment"
            rule_id = ""
            rule_type = ""

            if is_it_be:
                rule_id = "it_be"
                rule_type = "grammar"
            elif is_phrase_member:
                rule_id = self._phrase_rule_id(word)
                rule_type = "phrase"

            if is_grammar_only:
                quality_state = "grammar_only"
                translation_kind = "grammar_only"
                alignment_kind = "grammar_rule"
                matched_by = "grammar_rule"
            elif is_untranslated:
                quality_state = "untranslated"
                translation_kind = "literal_partial"
                alignment_kind = "identity"
                matched_by = "literal_fallback"
            elif is_phrase_member:
                quality_state = "phrase"
                translation_kind = "rule_exact"
                alignment_kind = "phrase_span"
                matched_by = "phrase_rule"
            elif segment_kind == "rule_exact":
                translation_kind = "rule_exact"

            annotated.append(
                {
                    **word,
                    "translation_kind": translation_kind,
                    "alignment_kind": alignment_kind,
                    "matched_by": matched_by,
                    "quality_state": quality_state,
                    "is_untranslated": int(is_untranslated),
                    "is_inherited": 0,
                    "is_grammar_only": int(is_grammar_only),
                    "is_phrase_member": int(is_phrase_member),
                    "direct_meaning_text": direct_meaning,
                    "rule_id": rule_id,
                    "rule_type": rule_type,
                }
            )
        return annotated

    def _is_phrase_rule_member(self, word: dict) -> bool:
        return False

    def _phrase_rule_id(self, word: dict) -> str:
        return ""

    def _is_it_be_word(self, word: dict) -> bool:
        segment_source = str(word.get("segment_source_text") or "").lower().strip()
        normalized = str(word.get("normalized_text") or "").lower()
        return segment_source.startswith("it is ") and normalized in {"it", "is"}

    def _build_detail_tap_words(self, paragraph_words: list[dict]) -> list[dict]:
        words_by_segment: dict[str, list[dict]] = {}
        for word in paragraph_words:
            words_by_segment.setdefault(str(word["segment_id"]), []).append(word)
        tap_words: list[dict] = []
        for segment_words in words_by_segment.values():
            segment_words.sort(key=lambda item: int(item["order_index"]))
            tap_words.extend(
                build_tap_word_payloads(
                    segment_target_text=str(segment_words[0].get("segment_target_text") or ""),
                    words=segment_words,
                )
            )
        tap_words.sort(key=lambda item: int(item["order_index"]))
        return tap_words

    def _build_special_detail_sheet(self, selected_word: dict, words: list[dict]) -> dict | None:
        return None

    def _build_detail_units(self, words: list[dict]) -> list[dict]:
        if self._is_time_block(words):
            return [
                {
                    "id": str(words[0].get("tap_unit_id") or words[0]["id"]),
                    "type": "PHRASE",
                    "text": build_unit_surface_text(words),
                    "surface_text": build_unit_surface_text(words),
                    "lemma": build_unit_surface_text(words),
                    "translation": self._build_detail_unit_translation(words),
                    "grammar_hint": "",
                    "morph_label": "",
                    "is_primary": True,
                    "example_source_text": str(words[0].get("segment_source_text") or ""),
                    "example_translation_text": str(words[0].get("segment_target_text") or ""),
                }
            ]
        units: list[dict] = []
        index = 0
        while index < len(words):
            current = words[index]
            lexical_unit_id = str(current.get("lexical_unit_id") or f"{current['id']}:lex")
            lexical_unit_type = str(current.get("lexical_unit_type") or "LEXICAL")
            end_index = index
            while end_index + 1 < len(words) and str(words[end_index + 1].get("lexical_unit_id") or "") == lexical_unit_id:
                end_index += 1
            unit_words = words[index : end_index + 1]
            surface_text = build_unit_surface_text(unit_words)
            lemma_text = build_unit_lemma_text(unit_words) or surface_text
            display_text = lemma_text if lexical_unit_type in {"LEXICAL", "PHRASE"} else surface_text
            grammar_hint = next((str(item.get("grammar_hint") or "") for item in unit_words if str(item.get("grammar_hint") or "").strip()), "")
            morph_label = next((str(item.get("morph_label") or "") for item in unit_words if str(item.get("morph_label") or "").strip()), "")
            direct_meaning = self._build_direct_meaning(unit_words)
            translation = self._build_detail_unit_translation(unit_words)
            if lexical_unit_type == "GRAMMAR":
                translation = direct_meaning
            elif direct_meaning and not translation:
                translation = direct_meaning
            units.append(
                {
                    "id": lexical_unit_id,
                    "type": lexical_unit_type,
                    "text": display_text,
                    "surface_text": surface_text,
                    "lemma": lemma_text,
                    "translation": translation,
                    "grammar_hint": grammar_hint,
                    "morph_label": morph_label,
                    "is_primary": lexical_unit_type != "GRAMMAR",
                    "example_source_text": str(unit_words[0].get("segment_source_text") or ""),
                    "example_translation_text": str(unit_words[0].get("segment_target_text") or ""),
                }
            )
            index = end_index + 1
        return units

    def _build_detail_unit_translation(self, words: list[dict]) -> str:
        valid_words = [
            word
            for word in words
            if int(word.get("target_start_index", -1)) >= 0 and int(word.get("target_end_index", -1)) >= 0
        ]
        if not valid_words:
            return str(words[0].get("translation_span_text") or "")
        segment_target_text = str(valid_words[0].get("segment_target_text") or "")
        start_index = min(int(word["target_start_index"]) for word in valid_words)
        end_index = max(int(word["target_end_index"]) for word in valid_words)
        _, focus_text, _ = build_context_window(
            target_text=segment_target_text,
            target_start_index=start_index,
            target_end_index=end_index,
        )
        if focus_text.strip():
            return focus_text
        return " ".join(
            str(word.get("translation_span_text") or "").strip()
            for word in valid_words
            if str(word.get("translation_span_text") or "").strip()
        ).strip()

    def _build_direct_meaning(self, words: list[dict]) -> str:
        meanings = [
            str(direct_meaning_for_word(word) or "").strip()
            for word in words
            if str(direct_meaning_for_word(word) or "").strip()
        ]
        if not meanings:
            return ""
        return " ".join(meanings).strip()

    def _is_time_block(self, words: list[dict]) -> bool:
        if not words:
            return False
        texts = [str(word.get("text") or "").upper() for word in words]
        if texts[-1] not in {"AM", "PM"}:
            return False
        return all(text.isdigit() for text in texts[:-1])

    def _build_mobile_tts_manifest(self, book_id: str) -> dict:
        with self._connect() as conn:
            job_rows = conn.execute(
                """
                SELECT id, book_id, engine_id, voice_id, mode, status, playback_state,
                       current_segment_index, level_id, level_name, target_wpm, audio_variant, native_rate, rate,
                       pause_scale, total_segments, ready_segments, error_message, created_at, updated_at
                FROM tts_jobs
                WHERE book_id = ?
                ORDER BY created_at DESC
                """,
                (book_id,),
            ).fetchall()
            segment_rows = conn.execute(
                """
                SELECT job_id, segment_index, paragraph_index, source_text, timings_path,
                       duration_ms, pause_after_ms, status
                FROM tts_segments
                WHERE book_id = ?
                ORDER BY job_id, segment_index
                """,
                (book_id,),
            ).fetchall()

        segments_by_job: dict[str, list[dict]] = {}
        for row in segment_rows:
            job_id = str(row["job_id"])
            segment_index = int(row["segment_index"])
            segments_by_job.setdefault(job_id, []).append(
                {
                    "segment_index": segment_index,
                    "paragraph_index": int(row["paragraph_index"]),
                    "source_text": str(row["source_text"]),
                    "audio_path": "",
                    "duration_ms": int(row["duration_ms"] or 0),
                    "pause_after_ms": int(row["pause_after_ms"] or 0),
                    "status": str(row["status"]),
                    "job_id": job_id,
                    "timings_path": str(row["timings_path"] or ""),
                    "remote_audio_path": (
                        f"/mobile/books/audio?book_id={book_id}&job_id={job_id}&segment_index={segment_index}"
                    ),
                    "remote_timings_path": (
                        f"/mobile/books/audio-timings?book_id={book_id}&job_id={job_id}&segment_index={segment_index}"
                    ),
                }
            )

        jobs = []
        for row in job_rows:
            job_payload = self.tts_service._job_payload(dict(row))
            job_payload["segments"] = segments_by_job.get(str(row["id"]), [])
            jobs.append(job_payload)

        return {
            "profiles": self.get_tts_profiles()["items"],
            "levels": self.get_tts_levels()["items"],
            "jobs": jobs,
        }

    def _build_mobile_word_audio_manifest(self, book_id: str) -> dict:
        entries = self._collect_book_word_audio_entries(book_id)
        voice_id = ""
        with self._connect() as conn:
            ready_job = conn.execute(
                """
                SELECT voice_id
                FROM tts_jobs
                WHERE book_id = ? AND status = 'ready'
                ORDER BY updated_at DESC, created_at DESC
                LIMIT 1
                """,
                (book_id,),
            ).fetchone()
        if ready_job is not None:
            voice_id = str(ready_job["voice_id"] or "")
        if not voice_id:
            profiles = self.get_tts_profiles()["items"]
            if profiles:
                voice_id = str(profiles[0].get("voice_id") or "")
        return {
            "voice_id": voice_id,
            "items": entries,
        }

    def _build_mobile_detail_manifest(self, book_id: str, reader_payload: dict) -> dict:
        manifest: dict[str, dict] = {}
        for paragraph in reader_payload.get("paragraphs", []):
            for word in paragraph.get("words", []):
                word_id = str(word.get("id") or "")
                if not word_id or word_id in manifest:
                    continue
                try:
                    manifest[word_id] = self.get_detail_sheet(book_id, word_id)
                except Exception:
                    continue
        return manifest

    def _build_mobile_book_package_parts(self, package: dict) -> list[dict]:
        meta = dict(package.get("meta") or {})
        source_text = str(package.get("source_text") or "")
        reader_payload = dict(package.get("reader_payload") or {})
        tts_manifest = dict(package.get("tts_manifest") or {})
        word_audio_manifest = dict(package.get("word_audio_manifest") or {})
        detail_manifest = dict(package.get("detail_manifest") or {})
        paragraphs = list(reader_payload.get("paragraphs") or [])

        reader_meta = {
            "book_id": reader_payload.get("book_id"),
            "title": reader_payload.get("title"),
            "status": reader_payload.get("status"),
            "source_lang": reader_payload.get("source_lang"),
            "target_lang": reader_payload.get("target_lang"),
            "current_paragraph_index": reader_payload.get("current_paragraph_index", 0),
            "paragraph_count": len(paragraphs),
        }

        parts: list[dict] = [
            {"part_id": "meta", "kind": "meta", "payload": meta},
            {"part_id": "source_text", "kind": "source_text", "payload": {"source_text": source_text}},
            {"part_id": "reader_meta", "kind": "reader_meta", "payload": reader_meta},
        ]
        chunk_index = 1
        current_chunk: list[dict] = []
        current_size = 0
        for paragraph in paragraphs:
            paragraph_size = len(json.dumps(paragraph, ensure_ascii=False).encode("utf-8"))
            projected_size = current_size + paragraph_size
            if current_chunk and projected_size > MOBILE_PACKAGE_MAX_PART_BYTES:
                parts.append(
                    {
                        "part_id": f"reader_paragraphs_{chunk_index}",
                        "kind": "reader_paragraphs",
                        "payload": {
                            "chunk_index": chunk_index,
                            "paragraphs": current_chunk,
                        },
                    }
                )
                chunk_index += 1
                current_chunk = []
                current_size = 0
            current_chunk.append(paragraph)
            current_size += paragraph_size
        if current_chunk:
            parts.append(
                {
                    "part_id": f"reader_paragraphs_{chunk_index}",
                    "kind": "reader_paragraphs",
                    "payload": {
                        "chunk_index": chunk_index,
                        "paragraphs": current_chunk,
                    },
                }
            )
        parts.append({"part_id": "tts_manifest", "kind": "tts_manifest", "payload": tts_manifest})
        parts.append({"part_id": "word_audio_manifest", "kind": "word_audio_manifest", "payload": word_audio_manifest})
        parts.append({"part_id": "detail_manifest", "kind": "detail_manifest", "payload": detail_manifest})
        return parts


    def _mark_error(self, book_id: str, message: str) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE books SET status = ?, error_message = ? WHERE id = ?", ("error", message, book_id))

    def _book_row_to_status(self, row: sqlite3.Row, paragraph_count: int) -> dict:
        return {
            "id": row["id"],
            "has_book": True,
            "status": row["status"],
            "title": row["title"],
            "source_name": row["source_name"],
            "source_lang": row["source_lang"],
            "target_lang": row["target_lang"],
            "model_name": row["model_name"],
            "error_message": row["error_message"],
            "paragraph_count": paragraph_count,
            "current_paragraph_index": row["current_paragraph_index"],
        }

    def _book_source_path(self, book_id: str) -> Path:
        return self.books_dir / book_id / "source.txt"

    def _normalize_import_source_path(self, source_path: str) -> Path:
        raw = (source_path or "").strip()
        if not raw:
            return Path(raw)
        direct = Path(raw)
        if direct.exists():
            return direct
        windows_drive_match = re.match(r"^([A-Za-z]):[\\/](.*)$", raw)
        if windows_drive_match:
            drive = windows_drive_match.group(1).lower()
            tail = windows_drive_match.group(2).replace("\\", "/")
            fallback = Path(f"/mnt/{drive}/{tail}")
            return fallback if fallback.exists() else direct
        if raw.startswith("file:///"):
            normalized = raw[8:]
            direct_normalized = Path(normalized)
            if direct_normalized.exists():
                return direct_normalized
            windows_uri_match = re.match(r"^([A-Za-z]):[\\/](.*)$", normalized)
            if windows_uri_match:
                drive = windows_uri_match.group(1).lower()
                tail = windows_uri_match.group(2).replace("\\", "/")
                fallback = Path(f"/mnt/{drive}/{tail}")
                return fallback if fallback.exists() else direct_normalized
            return direct_normalized
        return direct

    def _read_book_source_text(self, book_id: str) -> str:
        source_path = self._book_source_path(book_id)
        if not source_path.exists():
            return ""
        return source_path.read_text(encoding="utf-8", errors="ignore")

    def _compute_content_hash(self, source_text: str) -> str:
        return hashlib.sha1(source_text.encode("utf-8")).hexdigest()

    def _book_content_hash(self, book_id: str) -> str:
        return self._compute_content_hash(self._read_book_source_text(book_id))

    def _normalize_title(self, title: str) -> str:
        normalized = (title or "").strip()
        if not normalized:
            return "Untitled Book"
        return normalized[:120]

    def _resolve_book_id(self, conn: sqlite3.Connection, explicit_book_id: str | None) -> str | None:
        if explicit_book_id:
            return explicit_book_id
        active_book_id = self._get_active_book_id(conn)
        if active_book_id is not None:
            exists = conn.execute("SELECT id FROM books WHERE id = ?", (active_book_id,)).fetchone()
            if exists is not None:
                return active_book_id
            conn.execute("DELETE FROM app_state WHERE key = ?", (ACTIVE_BOOK_STATE_KEY,))
            active_book_id = None
        if active_book_id is not None:
            return active_book_id
        row = conn.execute("SELECT id FROM books ORDER BY COALESCE(last_opened_at, created_at) DESC LIMIT 1").fetchone()
        if row is None:
            return None
        conn.execute(
            """
            INSERT INTO app_state(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            (ACTIVE_BOOK_STATE_KEY, row["id"]),
        )
        return row["id"]

    def _get_active_book_id(self, conn: sqlite3.Connection) -> str | None:
        row = conn.execute("SELECT value FROM app_state WHERE key = ?", (ACTIVE_BOOK_STATE_KEY,)).fetchone()
        if row is None:
            return None
        exists = conn.execute("SELECT id FROM books WHERE id = ?", (row["value"],)).fetchone()
        if exists is not None:
            return row["value"]
        conn.execute("DELETE FROM app_state WHERE key = ?", (ACTIVE_BOOK_STATE_KEY,))
        return None
