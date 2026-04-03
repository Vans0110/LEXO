from __future__ import annotations

import hashlib
import shutil
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .assembler import assemble_paragraph
from .segmenter import split_paragraphs, split_sentences
from .text_loader import normalize_text
from .translator import TranslationProvider, create_default_provider
from .tts.tts_provider import TtsProvider, create_default_tts_provider
from .tts.tts_service import LexoTtsService
from .word_alignment import build_tap_word_payloads, build_word_mappings


ACTIVE_BOOK_STATE_KEY = "active_book_id"


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
        self.db_path = self.data_dir / "lexo.db"
        self.translator = translator or create_default_provider()
        self.tts_provider = tts_provider or create_default_tts_provider()
        self.tts_service = LexoTtsService(self.db_path, self.tts_dir, self.tts_provider)
        self._ensure_layout()

    def _ensure_layout(self) -> None:
        for path in (self.data_dir, self.books_dir, self.models_dir, self.logs_dir, self.tts_dir):
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
                    source_text TEXT NOT NULL,
                    audio_path TEXT NOT NULL,
                    duration_ms INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    hash TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_paragraphs_book_order
                ON paragraphs(book_id, order_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_segments_paragraph_order
                ON segments(paragraph_id, order_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_source_words_segment_order
                ON source_words(segment_id, order_index_in_segment);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_source_words_paragraph_order
                ON source_words(paragraph_id, order_index_in_paragraph);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tts_segments_job_order
                ON tts_segments(job_id, segment_index);
                """
            )
            self._ensure_book_columns(conn)
            self._ensure_tts_columns(conn)

    def _ensure_book_columns(self, conn: sqlite3.Connection) -> None:
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(books)").fetchall()}
        if "source_path" not in columns:
            conn.execute("ALTER TABLE books ADD COLUMN source_path TEXT")
        if "last_opened_at" not in columns:
            conn.execute("ALTER TABLE books ADD COLUMN last_opened_at TEXT")

    def _ensure_tts_columns(self, conn: sqlite3.Connection) -> None:
        job_columns = {row["name"] for row in conn.execute("PRAGMA table_info(tts_jobs)").fetchall()}
        job_additions = {
            "level_id": "INTEGER NOT NULL DEFAULT 1",
            "level_name": "TEXT NOT NULL DEFAULT ''",
            "target_wpm": "INTEGER NOT NULL DEFAULT 164",
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
        source = Path(source_path)
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
        source_path = self._book_source_path(book_id)
        source_text = source_path.read_text(encoding="utf-8", errors="ignore") if source_path.exists() else ""
        content_hash = hashlib.sha1(source_text.encode("utf-8")).hexdigest()
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
        }

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

    def list_books(self) -> dict:
        with self._connect() as conn:
            active_book_id = self._resolve_book_id(conn, None)
            rows = conn.execute(
                """
                SELECT id, title, source_name, source_lang, target_lang, status, model_name,
                       error_message, created_at, last_opened_at, current_paragraph_index
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
                       sw.segment_id, segments.target_text AS segment_target_text,
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
                    "segment_target_text": str(word_row["segment_target_text"] or ""),
                }
            )
        for (paragraph_id, _segment_id), segment_words in words_by_segment.items():
            paragraph_words = words_by_paragraph.setdefault(paragraph_id, [])
            paragraph_words.extend(
                build_tap_word_payloads(
                    segment_target_text=segment_words[0]["segment_target_text"] if segment_words else "",
                    words=segment_words,
                )
            )
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
                    "words": words_by_paragraph.get(str(item["id"]))
                    or self._build_runtime_word_payload(
                        source_text=item["source_text"],
                        target_text=item["target_text"],
                    ),
                }
                for item in paragraph_rows
            ],
        }

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

    def get_tts_levels(self) -> dict:
        return self.tts_service.get_levels()

    def generate_tts_jobs(
        self,
        book_id: str,
        voice_id: str,
        level_ids: list[int],
        mode: str = "play_from_current",
    ) -> dict:
        return self.tts_service.generate_jobs(
            book_id=book_id,
            voice_id=voice_id,
            level_ids=level_ids,
            mode=mode,
        )

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
                INSERT INTO segments(id, book_id, paragraph_id, order_index, source_text, target_text)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    (segment["id"], book_id, segment["paragraph_id"], segment["order_index"], segment["source_text"], segment["target_text"])
                    for paragraph in paragraph_payloads
                    for segment in paragraph["segments"]
                ],
            )
            conn.executemany(
                """
                INSERT INTO source_words(
                    id, book_id, paragraph_id, segment_id, order_index_in_paragraph, order_index_in_segment,
                    surface_text, normalized_text, is_function_word, anchor_source_word_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

    def _build_paragraph_payloads(self, paragraphs: list[str], source_lang: str, target_lang: str) -> list[dict]:
        payloads: list[dict] = []
        for index, paragraph_text in enumerate(paragraphs):
            source_segments = split_sentences(paragraph_text)
            translated = self.translator.translate_segments(source_segments, source_lang, target_lang)
            if len(translated) != len(source_segments):
                raise ValueError("Translator returned a mismatched number of segments")
            paragraph_id = str(uuid.uuid4())
            paragraph_words: list[dict] = []
            paragraph_alignments: list[dict] = []
            paragraph_word_offset = 0
            segment_payloads: list[dict] = []
            for segment_index, (source_text, target_text) in enumerate(zip(source_segments, translated, strict=True)):
                segment_id = str(uuid.uuid4())
                words, alignments = build_word_mappings(
                    source_text=source_text,
                    target_text=target_text,
                    paragraph_start_index=paragraph_word_offset,
                )
                local_to_global_ids: dict[str, str] = {}
                for word in words:
                    local_word_id = word["id"]
                    global_word_id = f"{paragraph_id}_{local_word_id}"
                    local_to_global_ids[local_word_id] = global_word_id
                    word["id"] = global_word_id
                    word["segment_id"] = segment_id
                    anchor_index = word.pop("anchor_order_index_in_segment")
                    anchor_paragraph_index = paragraph_word_offset + anchor_index
                    word["anchor_source_word_id"] = f"{paragraph_id}_w_{anchor_paragraph_index}"
                for alignment in alignments:
                    alignment["source_word_id"] = local_to_global_ids[alignment["source_word_id"]]
                paragraph_words.extend(words)
                paragraph_alignments.extend(alignments)
                paragraph_word_offset += len(words)
                segment_payloads.append(
                    {
                        "id": segment_id,
                        "paragraph_id": paragraph_id,
                        "order_index": segment_index,
                        "source_text": source_text,
                        "target_text": target_text,
                    }
                )
            payloads.append(
                {
                    "id": paragraph_id,
                    "order_index": index,
                    "source_text": paragraph_text,
                    "target_text": assemble_paragraph(translated),
                    "segments": segment_payloads,
                    "words": paragraph_words,
                    "alignments": paragraph_alignments,
                }
            )
        return payloads

    def _build_runtime_word_payload(self, source_text: str, target_text: str) -> list[dict]:
        words, alignments = build_word_mappings(
            source_text=source_text,
            target_text=target_text,
            paragraph_start_index=0,
        )
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
                }
            )
        return build_tap_word_payloads(segment_target_text=target_text, words=raw_words)

    def _build_mobile_tts_manifest(self, book_id: str) -> dict:
        with self._connect() as conn:
            job_rows = conn.execute(
                """
                SELECT id, book_id, engine_id, voice_id, mode, status, playback_state,
                       current_segment_index, level_id, level_name, target_wpm, rate,
                       pause_scale, total_segments, ready_segments, error_message, created_at, updated_at
                FROM tts_jobs
                WHERE book_id = ?
                ORDER BY created_at DESC
                """,
                (book_id,),
            ).fetchall()
            segment_rows = conn.execute(
                """
                SELECT job_id, segment_index, paragraph_index, source_text, duration_ms, pause_after_ms, status
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
                    "remote_audio_path": (
                        f"/mobile/books/audio?book_id={book_id}&job_id={job_id}&segment_index={segment_index}"
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
