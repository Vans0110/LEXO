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

from .config import segment_qa_candidate_count, segment_qa_rerank_enabled, segment_rerank_mode
from .context_dictionary_resolver import (
    CONTEXT_DICTIONARY_SOURCE,
    ContextDictionaryResolver,
)
from .dictionary_lookup import DictionaryLookup
from .google_translator import GoogleTranslator, default_google_usage_tracker
from .hybrid_translation_rerank import HybridTranslationReranker
from .library_dictionary import LIBRARY_DICTIONARY_SOURCE, LibraryDictionaryStore, library_dictionary_source
from .semantic_translation_rerank import SemanticTranslationReranker
from .segment_translation_qa import SegmentQaWord, SegmentTranslationQa, ZERO_WEIGHT_POS
from .source_pos_lemma import SourcePosLemmaAnalyzer
from .text_loader import normalize_text
from .structural_translation_rerank import StructuralTranslationReranker
from .tokenization import TOKEN_RE, WORD_RE
from .tts.tts_provider import TtsProvider, create_default_tts_provider
from .tts.tts_service import LexoTtsService


ACTIVE_BOOK_STATE_KEY = "active_book_id"
MOBILE_PACKAGE_MAX_PART_BYTES = 64 * 1024
BOOK_STATUS_READY = "ready"
SENTENCE_RE = re.compile(r"[^.!?]+[.!?]?|[.!?]+")


class LexoStorage:
    _PACKAGE_STAGE_LABELS = {
        "base_audio": "Base audio",
        "slow_audio": "Slow audio",
        "word_audio": "Word audio",
    }

    def __init__(self, root: Path, tts_provider: TtsProvider | None = None) -> None:
        self.root = root
        self.data_dir = root / "data"
        self.books_dir = self.data_dir / "books"
        self.library_dictionary_store = LibraryDictionaryStore(root)
        self.logs_dir = self.data_dir / "logs"
        self.tts_dir = self.data_dir / "tts"
        self.word_audio_dir = self.data_dir / "word_audio"
        self.db_path = self.data_dir / "lexo.db"
        self.dictionary_lookup = DictionaryLookup(root)
        self.google_usage_tracker = default_google_usage_tracker()
        self.book_translation_providers = {
            "ru": GoogleTranslator("ru", usage_tracker=self.google_usage_tracker),
            "uk": GoogleTranslator("uk", usage_tracker=self.google_usage_tracker),
        }
        self.context_dictionary_resolver = ContextDictionaryResolver(root)
        self.source_pos_lemma = SourcePosLemmaAnalyzer()
        self.segment_translation_qa = SegmentTranslationQa()
        self.structural_translation_reranker = StructuralTranslationReranker()
        self.semantic_translation_reranker = SemanticTranslationReranker()
        self.hybrid_translation_reranker = HybridTranslationReranker()
        self._dictionary_manifest_cache: dict[tuple[str, str], dict] = {}
        self.tts_provider = tts_provider or create_default_tts_provider()
        self.tts_service = LexoTtsService(self.db_path, self.tts_dir, self.tts_provider)
        self._package_workers: dict[str, threading.Thread] = {}
        self._package_lock = threading.Lock()
        self._ensure_layout()

    def google_translate_usage_summary(self, month: str | None = None) -> dict:
        return self.google_usage_tracker.summary(month)

    def _ensure_layout(self) -> None:
        for path in (self.data_dir, self.books_dir, self.logs_dir, self.tts_dir, self.word_audio_dir):
            path.mkdir(parents=True, exist_ok=True)
        self._init_db()
        self.tts_service.seed_profiles()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

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
                    model_name TEXT NOT NULL DEFAULT '',
                    error_message TEXT,
                    created_at TEXT NOT NULL,
                    current_paragraph_index INTEGER NOT NULL DEFAULT 0,
                    source_path TEXT NOT NULL DEFAULT '',
                    last_opened_at TEXT,
                    content_hash TEXT NOT NULL DEFAULT ''
                );
                CREATE TABLE IF NOT EXISTS paragraphs (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    source_text TEXT NOT NULL,
                    target_text TEXT NOT NULL DEFAULT '',
                    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS segments (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    paragraph_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    source_text TEXT NOT NULL,
                    target_text TEXT NOT NULL DEFAULT '',
                    segment_type TEXT NOT NULL DEFAULT 'source_segment',
                    segment_meta_json TEXT NOT NULL DEFAULT '{}',
                    translation_kind TEXT NOT NULL DEFAULT 'none',
                    quality_score INTEGER NOT NULL DEFAULT 100,
                    quality_status TEXT NOT NULL DEFAULT 'pass',
                    quality_flags TEXT NOT NULL DEFAULT '[]',
                    translation_attempt_count INTEGER NOT NULL DEFAULT 0,
                    provider_used TEXT NOT NULL DEFAULT '',
                    alignment_confidence REAL NOT NULL DEFAULT 0.0,
                    semantic_score REAL NOT NULL DEFAULT 0.0,
                    back_translation TEXT NOT NULL DEFAULT '',
                    source_entities_json TEXT NOT NULL DEFAULT '[]',
                    back_entities_json TEXT NOT NULL DEFAULT '[]',
                    entity_preservation_score REAL NOT NULL DEFAULT 0.0,
                    entity_flags TEXT NOT NULL DEFAULT '[]',
                    source_frame_json TEXT NOT NULL DEFAULT '{}',
                    back_frame_json TEXT NOT NULL DEFAULT '{}',
                    frame_preservation_score REAL NOT NULL DEFAULT 0.0,
                    frame_flags TEXT NOT NULL DEFAULT '[]',
                    ru_quality_score REAL NOT NULL DEFAULT 0.0,
                    ru_quality_flags TEXT NOT NULL DEFAULT '[]',
                    retry_reason_flags TEXT NOT NULL DEFAULT '[]',
                    decision_status TEXT NOT NULL DEFAULT 'accept',
                    winner_reason TEXT NOT NULL DEFAULT '',
                    candidate_count INTEGER NOT NULL DEFAULT 0,
                    source_verb_frame_json TEXT NOT NULL DEFAULT '{}',
                    back_verb_frame_json TEXT NOT NULL DEFAULT '{}',
                    verb_score REAL NOT NULL DEFAULT 0.0,
                    verb_flags TEXT NOT NULL DEFAULT '[]',
                    analysis_version TEXT NOT NULL DEFAULT 'source_only_v1',
                    source_analysis_json TEXT NOT NULL DEFAULT '{}',
                    source_lookup_json TEXT NOT NULL DEFAULT '{}',
                    source_coverage_json TEXT NOT NULL DEFAULT '{}',
                    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
                    FOREIGN KEY(paragraph_id) REFERENCES paragraphs(id) ON DELETE CASCADE
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
                    lemma TEXT NOT NULL DEFAULT '',
                    pos TEXT NOT NULL DEFAULT '',
                    lexical_unit_type TEXT NOT NULL DEFAULT 'LEXICAL',
                    target_start_index INTEGER,
                    target_end_index INTEGER,
                    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
                    FOREIGN KEY(paragraph_id) REFERENCES paragraphs(id) ON DELETE CASCADE,
                    FOREIGN KEY(segment_id) REFERENCES segments(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS target_tokens (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    paragraph_id TEXT NOT NULL,
                    segment_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    order_index_in_segment INTEGER NOT NULL DEFAULT 0,
                    surface_text TEXT NOT NULL,
                    normalized_text TEXT NOT NULL,
                    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
                    FOREIGN KEY(paragraph_id) REFERENCES paragraphs(id) ON DELETE CASCADE,
                    FOREIGN KEY(segment_id) REFERENCES segments(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS segment_alignments (
                    segment_id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    provider TEXT NOT NULL DEFAULT '',
                    source_tokens_json TEXT NOT NULL DEFAULT '[]',
                    target_tokens_json TEXT NOT NULL DEFAULT '[]',
                    raw_links_json TEXT NOT NULL DEFAULT '[]',
                    block_links_json TEXT NOT NULL DEFAULT '[]',
                    alignment_status TEXT NOT NULL DEFAULT '',
                    error_message TEXT NOT NULL DEFAULT '',
                    FOREIGN KEY(segment_id) REFERENCES segments(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS segment_resolved_alignments (
                    segment_id TEXT PRIMARY KEY,
                    resolver_version TEXT NOT NULL DEFAULT 'source_only_v1',
                    alignment_json TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL DEFAULT '',
                    FOREIGN KEY(segment_id) REFERENCES segments(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS book_dictionary_entries (
                    book_id TEXT NOT NULL,
                    dictionary_key TEXT NOT NULL,
                    lemma TEXT NOT NULL,
                    pos TEXT NOT NULL DEFAULT '',
                    entry_json TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY(book_id, dictionary_key),
                    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS saved_cards (
                    id TEXT PRIMARY KEY,
                    head_text TEXT NOT NULL,
                    translation TEXT NOT NULL DEFAULT '',
                    grammar_label TEXT NOT NULL DEFAULT '',
                    example_source_text TEXT NOT NULL DEFAULT '',
                    example_translation_text TEXT NOT NULL DEFAULT '',
                    source_word_id TEXT,
                    source_unit_id TEXT,
                    source_paragraph_id TEXT,
                    source_segment_id TEXT,
                    source_book_id TEXT,
                    status TEXT NOT NULL DEFAULT 'new',
                    box INTEGER NOT NULL DEFAULT 0,
                    due_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT,
                    desktop_card_id TEXT,
                    device_id TEXT NOT NULL DEFAULT 'desktop',
                    sync_updated_at TEXT NOT NULL DEFAULT ''
                );
                CREATE TABLE IF NOT EXISTS tts_profiles (
                    id TEXT PRIMARY KEY,
                    engine_id TEXT NOT NULL,
                    voice_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    lang TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL DEFAULT 1
                );
                CREATE TABLE IF NOT EXISTS tts_jobs (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    engine_id TEXT NOT NULL,
                    voice_id TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    status TEXT NOT NULL,
                    playback_state TEXT NOT NULL DEFAULT 'idle',
                    current_segment_index INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    level_id INTEGER NOT NULL DEFAULT 1,
                    level_name TEXT NOT NULL DEFAULT 'Normal',
                    target_wpm INTEGER NOT NULL DEFAULT 150,
                    audio_variant TEXT NOT NULL DEFAULT 'base',
                    native_rate REAL NOT NULL DEFAULT 1.0,
                    rate REAL NOT NULL DEFAULT 1.0,
                    pause_scale REAL NOT NULL DEFAULT 1.0,
                    total_segments INTEGER NOT NULL DEFAULT 0,
                    ready_segments INTEGER NOT NULL DEFAULT 0,
                    error_message TEXT
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
                    synthesis_text TEXT,
                    pause_after_ms INTEGER NOT NULL DEFAULT 0,
                    audio_path TEXT NOT NULL,
                    timings_path TEXT NOT NULL DEFAULT '',
                    duration_ms INTEGER NOT NULL DEFAULT 0,
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
                    updated_at TEXT NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_paragraphs_book_order ON paragraphs(book_id, order_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_segments_paragraph_order ON segments(paragraph_id, order_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_source_words_segment_order ON source_words(segment_id, order_index_in_segment);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_source_words_paragraph_order ON source_words(paragraph_id, order_index_in_paragraph);
                CREATE INDEX IF NOT EXISTS idx_book_dictionary_entries_book ON book_dictionary_entries(book_id);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tts_segments_job_order ON tts_segments(job_id, segment_index);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_tts_package_stage_unique ON tts_package_stages(package_job_id, stage_key);
                """
            )
            self._ensure_columns(conn)
            conn.execute(
                """
                UPDATE books
                SET status = ?, error_message = NULL
                WHERE status != ?
                """,
                (BOOK_STATUS_READY, BOOK_STATUS_READY),
            )

    def _ensure_columns(self, conn: sqlite3.Connection) -> None:
        self._ensure_table_columns(
            conn,
            "books",
            {
                "source_path": "TEXT NOT NULL DEFAULT ''",
                "last_opened_at": "TEXT",
                "content_hash": "TEXT NOT NULL DEFAULT ''",
            },
        )
        self._ensure_table_columns(
            conn,
            "source_words",
            {
                "lemma": "TEXT NOT NULL DEFAULT ''",
                "pos": "TEXT NOT NULL DEFAULT ''",
                "lexical_unit_type": "TEXT NOT NULL DEFAULT 'LEXICAL'",
                "target_start_index": "INTEGER",
                "target_end_index": "INTEGER",
            },
        )
        self._ensure_table_columns(
            conn,
            "target_tokens",
            {"order_index_in_segment": "INTEGER NOT NULL DEFAULT 0"},
        )
        self._ensure_table_columns(
            conn,
            "saved_cards",
            {
                "card_type": "TEXT NOT NULL DEFAULT 'lexical'",
                "surface_text": "TEXT NOT NULL DEFAULT ''",
                "lemma": "TEXT NOT NULL DEFAULT ''",
                "example_text": "TEXT NOT NULL DEFAULT ''",
                "example_translation": "TEXT NOT NULL DEFAULT ''",
                "pos": "TEXT NOT NULL DEFAULT ''",
                "morph_label": "TEXT NOT NULL DEFAULT ''",
                "example_source_text": "TEXT NOT NULL DEFAULT ''",
                "example_translation_text": "TEXT NOT NULL DEFAULT ''",
                "box": "INTEGER NOT NULL DEFAULT 0",
                "due_at": "TEXT",
                "desktop_card_id": "TEXT",
                "sync_updated_at": "TEXT NOT NULL DEFAULT ''",
                "progress_score": "INTEGER NOT NULL DEFAULT 0",
                "review_count": "INTEGER NOT NULL DEFAULT 0",
                "last_reviewed_at": "TEXT NOT NULL DEFAULT ''",
            },
        )
        self._ensure_table_columns(
            conn,
            "tts_jobs",
            {
                "level_id": "INTEGER NOT NULL DEFAULT 1",
                "level_name": "TEXT NOT NULL DEFAULT 'Normal'",
                "target_wpm": "INTEGER NOT NULL DEFAULT 150",
                "audio_variant": "TEXT NOT NULL DEFAULT 'base'",
                "native_rate": "REAL NOT NULL DEFAULT 1.0",
                "rate": "REAL NOT NULL DEFAULT 1.0",
                "pause_scale": "REAL NOT NULL DEFAULT 1.0",
                "total_segments": "INTEGER NOT NULL DEFAULT 0",
                "ready_segments": "INTEGER NOT NULL DEFAULT 0",
                "error_message": "TEXT",
            },
        )
        self._ensure_table_columns(
            conn,
            "tts_segments",
            {
                "audio_variant": "TEXT NOT NULL DEFAULT 'base'",
                "synthesis_text": "TEXT",
                "pause_after_ms": "INTEGER NOT NULL DEFAULT 0",
                "timings_path": "TEXT NOT NULL DEFAULT ''",
            },
        )

    def _ensure_table_columns(self, conn: sqlite3.Connection, table: str, columns: dict[str, str]) -> None:
        existing = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
        for name, definition in columns.items():
            if name not in existing:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")

    def import_book(self, source_path: str, source_lang: str = "en", target_lang: str = "ru") -> dict:
        path = self._normalize_import_source_path(source_path)
        return self._import_book_text(
            title=path.stem,
            source_text=path.read_text(encoding="utf-8"),
            source_name=path.name,
            source_lang=source_lang,
            target_lang=target_lang,
        )

    def import_book_text(
        self,
        title: str,
        source_text: str,
        source_lang: str = "en",
        target_lang: str = "ru",
        stable_book_key: str | None = None,
    ) -> dict:
        return self._import_book_text(
            title=title,
            source_text=source_text,
            source_name=f"{self._normalize_title(title)}.txt",
            source_lang=source_lang,
            target_lang=target_lang,
            stable_book_key=stable_book_key,
        )

    def _import_book_text(
        self,
        *,
        title: str,
        source_text: str,
        source_name: str,
        source_lang: str,
        target_lang: str,
        stable_book_key: str | None = None,
    ) -> dict:
        normalized = normalize_text(source_text)
        paragraphs = self._split_paragraphs(normalized)
        if not paragraphs:
            raise ValueError("TXT file does not contain readable paragraphs")
        content_hash = self._compute_content_hash(normalized)
        book_id = self._book_id_for_import(
            stable_book_key=stable_book_key,
            target_lang=target_lang,
            normalized_text=normalized,
        )
        created_at = datetime.now(timezone.utc).isoformat()
        book_source_path = self._book_source_path(book_id)
        book_source_path.parent.mkdir(parents=True, exist_ok=True)
        book_source_path.write_text("\n\n".join(paragraphs), encoding="utf-8")
        payloads, model_name = self._build_source_only_payloads(
            book_id,
            paragraphs,
            source_lang=source_lang,
            target_lang=target_lang,
        )
        with self._connect() as conn:
            existing = conn.execute(
                "SELECT content_hash FROM books WHERE id = ?",
                (book_id,),
            ).fetchone()
            preserve_audio = (
                existing is not None
                and str(existing["content_hash"] or "") == content_hash
            )
            conn.execute(
                """
                INSERT INTO books(
                    id, title, source_name, source_lang, target_lang, status, model_name,
                    error_message, created_at, current_paragraph_index, source_path,
                    last_opened_at, content_hash
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, 0, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    source_name = excluded.source_name,
                    source_lang = excluded.source_lang,
                    target_lang = excluded.target_lang,
                    status = excluded.status,
                    model_name = excluded.model_name,
                    error_message = NULL,
                    source_path = excluded.source_path,
                    last_opened_at = excluded.last_opened_at,
                    content_hash = excluded.content_hash
                """,
                (
                    book_id,
                    self._normalize_title(title),
                    source_name,
                    source_lang,
                    target_lang,
                    BOOK_STATUS_READY,
                    model_name,
                    created_at,
                    str(book_source_path),
                    created_at,
                    content_hash,
                ),
            )
            self._replace_book_content(
                conn,
                book_id,
                payloads,
                preserve_audio=preserve_audio,
            )
            conn.execute(
                """
                INSERT INTO app_state(key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                (ACTIVE_BOOK_STATE_KEY, book_id),
            )
        return self.get_book_status(book_id)

    def _build_source_only_payloads(
        self,
        book_id: str,
        paragraphs: list[str],
        *,
        source_lang: str,
        target_lang: str,
    ) -> tuple[list[dict], str]:
        payloads: list[dict] = []
        translator = self._resolve_translation_provider(source_lang=source_lang, target_lang=target_lang)
        model_name = translator.provider_name if translator is not None else "source-only"
        rerank_mode = segment_rerank_mode()
        use_segment_qa = (
            segment_qa_rerank_enabled()
            and rerank_mode != "off"
            and translator is not None
            and hasattr(translator, "translate_segment_candidates")
        )
        candidate_count = segment_qa_candidate_count()
        dictionary_cache: dict[tuple[str, str], tuple[str, ...]] = {}
        for paragraph_index, paragraph_text in enumerate(paragraphs):
            paragraph_id = str(uuid.uuid4())
            segments = self._split_segments(paragraph_text)
            translated_segments = (
                []
                if use_segment_qa
                else translator.translate_segments(segments) if translator is not None else ["" for _ in segments]
            )
            paragraph_words: list[dict] = []
            paragraph_word_index = 0
            segment_payloads: list[dict] = []
            for segment_index, segment_text in enumerate(segments):
                segment_id = str(uuid.uuid4())
                segment_words = list(WORD_RE.finditer(segment_text))
                word_analyses = self.source_pos_lemma.analyze_words(
                    segment_text,
                    [match.group(0) for match in segment_words],
                )
                translated_text = (
                    self._rerank_segment_translation(
                        translator=translator,
                        target_lang=target_lang,
                        segment_text=segment_text,
                        segment_words=[match.group(0) for match in segment_words],
                        word_analyses=word_analyses,
                        dictionary_cache=dictionary_cache,
                        candidate_count=candidate_count,
                        rerank_mode=rerank_mode,
                    )
                    if use_segment_qa
                    else translated_segments[segment_index] if segment_index < len(translated_segments) else ""
                )
                segment_meta_json = "{}"
                candidate_count_used = 1 if translated_text else 0
                analysis_version = "provider_sentence_v1" if translated_text else "source_only_v1"
                if isinstance(translated_text, tuple):
                    translated_text, segment_meta_json, candidate_count_used = translated_text
                    analysis_version = f"provider_sentence_{rerank_mode}_rerank_v1" if translated_text else "source_only_v1"
                for local_index, match in enumerate(segment_words):
                    text = match.group(0)
                    normalized = text.lower()
                    analysis = word_analyses[local_index]
                    paragraph_words.append(
                        {
                            "id": f"{paragraph_id}_w_{paragraph_word_index}",
                            "book_id": book_id,
                            "paragraph_id": paragraph_id,
                            "segment_id": segment_id,
                            "order_index_in_paragraph": paragraph_word_index,
                            "order_index_in_segment": local_index,
                            "surface_text": text,
                            "normalized_text": normalized,
                            "lemma": analysis.lemma or normalized,
                            "pos": analysis.pos,
                            "lexical_unit_type": "LEXICAL",
                            "target_start_index": None,
                            "target_end_index": None,
                        }
                    )
                    paragraph_word_index += 1
                segment_payloads.append(
                    {
                        "id": segment_id,
                        "book_id": book_id,
                        "paragraph_id": paragraph_id,
                        "order_index": segment_index,
                        "source_text": segment_text,
                        "target_text": translated_text,
                        "segment_type": "source_segment",
                        "segment_meta_json": segment_meta_json,
                        "translation_kind": "provider" if translated_text else "none",
                        "provider_used": translator.provider_name if translator is not None and translated_text else "",
                        "analysis_version": analysis_version,
                        "candidate_count": candidate_count_used,
                        "source_analysis_json": "{}",
                        "source_lookup_json": "{}",
                        "source_coverage_json": "{}",
                    }
                )
            payloads.append(
                {
                    "id": paragraph_id,
                    "book_id": book_id,
                    "order_index": paragraph_index,
                    "source_text": paragraph_text,
                    "target_text": " ".join(item["target_text"] for item in segment_payloads if item["target_text"]),
                    "segments": segment_payloads,
                    "words": paragraph_words,
                }
            )
        return payloads, model_name

    def _rerank_segment_translation(
        self,
        *,
        translator: object,
        target_lang: str,
        segment_text: str,
        segment_words: list[str],
        word_analyses: list[object],
        dictionary_cache: dict[tuple[str, str], tuple[str, ...]],
        candidate_count: int,
        rerank_mode: str,
    ) -> tuple[str, str, int]:
        candidates_method = getattr(translator, "translate_segment_candidates", None)
        if not callable(candidates_method):
            return "", "{}", 0
        candidates = candidates_method(segment_text, max_candidates=candidate_count)
        if not candidates and hasattr(translator, "translate_segments"):
            translated = translator.translate_segments([segment_text])
            candidates = [item for item in translated if item]
        if not candidates:
            return "", "{}", 0
        mode = rerank_mode if rerank_mode in {"dictionary", "structural", "semantic", "hybrid"} else "hybrid"
        result = self._select_segment_rerank_result(
            mode=mode,
            translator=translator,
            target_lang=target_lang,
            segment_text=segment_text,
            segment_words=segment_words,
            word_analyses=word_analyses,
            dictionary_cache=dictionary_cache,
            candidates=candidates,
        )
        selected = result.selected or candidates[0]
        meta = {
            "translation_rerank": f"segment_{mode}_v1",
            "target_lang": target_lang,
            "candidate_count": len(candidates),
            "rerank_result": result.explanation,
        }
        return selected, json.dumps(meta, ensure_ascii=False), len(candidates)

    def _select_segment_rerank_result(
        self,
        *,
        mode: str,
        translator: object,
        target_lang: str,
        segment_text: str,
        segment_words: list[str],
        word_analyses: list[object],
        dictionary_cache: dict[tuple[str, str], tuple[str, ...]],
        candidates: list[str],
    ) -> object:
        if mode == "structural":
            return self.structural_translation_reranker.select(segment_text, target_lang, candidates)
        if mode == "semantic":
            return self.semantic_translation_reranker.select(segment_text, candidates)
        if mode == "hybrid":
            return self.hybrid_translation_reranker.select(segment_text, target_lang, candidates)
        qa_words = self._segment_qa_words(
            translator=translator,
            target_lang=target_lang,
            segment_words=segment_words,
            word_analyses=word_analyses,
            dictionary_cache=dictionary_cache,
        )
        return self.segment_translation_qa.select(segment_text, qa_words, candidates)

    def _segment_qa_words(
        self,
        *,
        translator: object,
        target_lang: str,
        segment_words: list[str],
        word_analyses: list[object],
        dictionary_cache: dict[tuple[str, str], tuple[str, ...]],
    ) -> list[SegmentQaWord]:
        alternatives_method = getattr(translator, "translate_alternatives", None)
        qa_words: list[SegmentQaWord] = []
        for index, surface in enumerate(segment_words):
            analysis = word_analyses[index] if index < len(word_analyses) else None
            lemma = str(getattr(analysis, "lemma", "") or surface).strip().lower()
            pos = str(getattr(analysis, "pos", "") or "").strip()
            translations: tuple[str, ...] = ()
            if (
                pos.upper() not in ZERO_WEIGHT_POS
                and callable(alternatives_method)
            ):
                cache_key = (lemma, pos.upper())
                translations = dictionary_cache.get(cache_key, ())
                if not translations:
                    found = alternatives_method(lemma, max_alternatives=10)
                    if not found and surface.lower() != lemma:
                        found = alternatives_method(surface, max_alternatives=10)
                    translations = tuple(found or ())
                    dictionary_cache[cache_key] = translations
            qa_words.append(
                SegmentQaWord(
                    surface=surface,
                    lemma=lemma,
                    pos=pos,
                    translations=translations,
                )
            )
        return qa_words

    def _resolve_translation_provider(self, *, source_lang: str, target_lang: str) -> object | None:
        if source_lang != "en":
            return None
        translator = self.book_translation_providers.get(target_lang)
        if translator is not None and translator.is_available:
            return translator
        return None

    def _replace_book_content(
        self,
        conn: sqlite3.Connection,
        book_id: str,
        paragraph_payloads: list[dict],
        *,
        preserve_audio: bool = False,
    ) -> None:
        self._clear_book_dictionary_cache(book_id)
        if not preserve_audio:
            conn.execute("DELETE FROM tts_segments WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM tts_jobs WHERE book_id = ?", (book_id,))
            package_rows = conn.execute(
                "SELECT id FROM tts_package_jobs WHERE book_id = ?",
                (book_id,),
            ).fetchall()
            for package in package_rows:
                conn.execute(
                    "DELETE FROM tts_package_stages WHERE package_job_id = ?",
                    (str(package["id"]),),
                )
            conn.execute("DELETE FROM tts_package_jobs WHERE book_id = ?", (book_id,))
        conn.execute("DELETE FROM segment_resolved_alignments WHERE segment_id IN (SELECT id FROM segments WHERE book_id = ?)", (book_id,))
        conn.execute("DELETE FROM segment_alignments WHERE book_id = ?", (book_id,))
        conn.execute("DELETE FROM target_tokens WHERE book_id = ?", (book_id,))
        conn.execute("DELETE FROM book_dictionary_entries WHERE book_id = ?", (book_id,))
        conn.execute("DELETE FROM source_words WHERE book_id = ?", (book_id,))
        conn.execute("DELETE FROM segments WHERE book_id = ?", (book_id,))
        conn.execute("DELETE FROM paragraphs WHERE book_id = ?", (book_id,))
        conn.executemany(
            """
            INSERT INTO paragraphs(id, book_id, order_index, source_text, target_text)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                (item["id"], book_id, item["order_index"], item["source_text"], item["target_text"])
                for item in paragraph_payloads
            ],
        )
        segment_rows = []
        for paragraph in paragraph_payloads:
            for segment in paragraph["segments"]:
                segment_rows.append(
                    (
                        segment["id"],
                        book_id,
                        paragraph["id"],
                        segment["order_index"],
                        segment["source_text"],
                        segment["target_text"],
                        "source_segment",
                        segment.get("segment_meta_json", "{}"),
                        segment["translation_kind"],
                        100,
                        "pass",
                        "[]",
                        1 if segment["target_text"] else 0,
                        segment.get("provider_used", ""),
                        0.0,
                        0.0,
                        "",
                        "[]",
                        "[]",
                        0.0,
                        "[]",
                        "{}",
                        "{}",
                        0.0,
                        "[]",
                        0.0,
                        "[]",
                        "[]",
                        "accept",
                        "provider_sentence" if segment["target_text"] else "source_only",
                        segment.get("candidate_count", 0),
                        "{}",
                        "{}",
                        0.0,
                        "[]",
                        segment["analysis_version"],
                        "{}",
                        "{}",
                        "{}",
                    )
                )
        conn.executemany(
            """
            INSERT INTO segments(
                id, book_id, paragraph_id, order_index, source_text, target_text, segment_type,
                segment_meta_json, translation_kind, quality_score, quality_status, quality_flags,
                translation_attempt_count, provider_used, alignment_confidence, semantic_score,
                back_translation, source_entities_json, back_entities_json, entity_preservation_score,
                entity_flags, source_frame_json, back_frame_json, frame_preservation_score,
                frame_flags, ru_quality_score, ru_quality_flags, retry_reason_flags, decision_status,
                winner_reason, candidate_count, source_verb_frame_json, back_verb_frame_json,
                verb_score, verb_flags, analysis_version, source_analysis_json, source_lookup_json,
                source_coverage_json
            )
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            segment_rows,
        )
        word_rows = [
            (
                word["id"],
                book_id,
                paragraph["id"],
                word["segment_id"],
                word["order_index_in_paragraph"],
                word["order_index_in_segment"],
                word["surface_text"],
                word["normalized_text"],
                word["lemma"],
                word["pos"],
                word["lexical_unit_type"],
                None,
                None,
            )
            for paragraph in paragraph_payloads
            for word in paragraph["words"]
        ]
        conn.executemany(
            """
            INSERT INTO source_words(
                id, book_id, paragraph_id, segment_id, order_index_in_paragraph,
                order_index_in_segment, surface_text, normalized_text, lemma, pos,
                lexical_unit_type, target_start_index, target_end_index
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            word_rows,
        )
        self._rebuild_book_dictionary_entries(conn, book_id)
        shutil.rmtree(self.tts_dir / book_id, ignore_errors=True)

    def rebuild_book_library_dictionary(self, book_id: str | None = None, target_lang: str = "ru") -> dict:
        resolved = self._resolve_required_book_id(book_id)
        normalized_lang = str(target_lang or "ru").strip().lower() or "ru"
        if normalized_lang not in {"ru", "uk"}:
            raise ValueError("Library dictionary prototype supports only ru/uk")
        payload = self._build_book_layer_payload(resolved, normalized_lang)
        layer_path = self.library_dictionary_store.write_book_layer(payload, normalized_lang)
        merge_result = self.library_dictionary_store.merge_book_layer(payload)
        self._clear_book_dictionary_cache(resolved)
        with self._connect() as conn:
            dictionary_entry_count = self._rebuild_book_dictionary_entries(conn, resolved)
        return {
            "ok": True,
            "book_id": resolved,
            "target_lang": normalized_lang,
            "book_layer_path": str(layer_path),
            "word_count": len(payload.get("words") or []),
            "phrase_count": len(payload.get("phrases") or []),
            "parallel_count": len(payload.get("parallel") or []),
            "dictionary_entry_count": dictionary_entry_count,
            **merge_result,
        }

    def _build_book_layer_payload(self, book_id: str, target_lang: str) -> dict:
        with self._connect() as conn:
            book = conn.execute("SELECT * FROM books WHERE id = ?", (book_id,)).fetchone()
            if book is None:
                raise ValueError(f"No such book: {book_id}")
            book_target_lang = str(book["target_lang"] or "").strip().lower()
            segments = conn.execute(
                """
                SELECT source_text, target_text
                FROM segments
                WHERE book_id = ?
                ORDER BY paragraph_id, order_index
                """,
                (book_id,),
            ).fetchall()
            word_rows = conn.execute(
                """
                SELECT normalized_text, surface_text, lemma, pos
                FROM source_words
                WHERE book_id = ?
                ORDER BY order_index_in_paragraph
                """,
                (book_id,),
            ).fetchall()

        parallel = []
        if book_target_lang == target_lang:
            for row in segments:
                source = str(row["source_text"] or "").strip()
                translation = str(row["target_text"] or "").strip()
                if source or translation:
                    parallel.append({"source": source, "translation": translation})

        words_by_key: dict[str, dict] = {}
        for row in word_rows:
            surface = str(row["surface_text"] or row["normalized_text"] or "").strip()
            normalized = str(row["normalized_text"] or surface).strip().lower()
            lemma = str(row["lemma"] or normalized).strip().lower()
            pos = str(row["pos"] or "").strip().upper()
            if not lemma:
                continue
            key = self._dictionary_key(lemma, pos)
            if key in words_by_key:
                continue
            translation = self._book_word_translation(
                book_id=book_id,
                lemma=lemma,
                pos=pos,
                target_lang=target_lang,
            )
            if not translation:
                continue
            words_by_key[key] = {
                "word": surface or normalized,
                "lemma": lemma,
                "pos": pos,
                "translation": translation,
                "translations": self._contextual_translation_forms(
                    surface=surface or normalized,
                    lemma=lemma,
                    translation=translation,
                    parallel=parallel,
                ),
            }

        return {
            "version": 1,
            "book_id": book_id,
            "title": str(book["title"] or ""),
            "source_lang": str(book["source_lang"] or "en"),
            "target_lang": target_lang,
            "parallel": parallel,
            "phrases": self._book_phrase_seed(book_id, target_lang),
            "words": list(words_by_key.values()),
        }

    def _contextual_translation_forms(
        self,
        *,
        surface: str,
        lemma: str,
        translation: str,
        parallel: list[dict],
    ) -> list[str]:
        result = [str(translation or "").strip()]
        base_tokens = re.findall(r"[^\W_]+", result[0], flags=re.UNICODE)
        if len(base_tokens) != 1:
            return [value for value in result if value]
        base = base_tokens[0].lower()
        source_surface = str(surface or "").strip().lower()
        source_lemma = str(lemma or source_surface).strip().lower()
        for segment in parallel:
            if not isinstance(segment, dict):
                continue
            source_tokens = [
                token.lower()
                for token in re.findall(
                    r"[^\W_]+", str(segment.get("source") or ""), flags=re.UNICODE
                )
            ]
            if not any(
                token in {source_surface, source_lemma}
                or (
                    source_lemma
                    and token.startswith(source_lemma)
                    and token[len(source_lemma):] in {"s", "es", "ed", "ing"}
                )
                for token in source_tokens
            ):
                continue
            target_tokens = re.findall(
                r"[^\W_]+", str(segment.get("translation") or ""), flags=re.UNICODE
            )
            scored: list[tuple[float, str]] = []
            for token in target_tokens:
                candidate = token.lower()
                shortest = min(len(base), len(candidate))
                common = 0
                while common < shortest and base[common] == candidate[common]:
                    common += 1
                if common < 3 or common / shortest < 0.6:
                    continue
                score = common / shortest - abs(len(base) - len(candidate)) * 0.01
                scored.append((score, token))
            if not scored:
                continue
            contextual = max(scored)[1]
            if contextual.lower() not in {value.lower() for value in result}:
                result.append(contextual)
        return [value for value in result if value]
    def _book_word_translation(self, *, book_id: str, lemma: str, pos: str, target_lang: str) -> str:
        clean_book_id = str(book_id or "").strip()
        key = self._dictionary_key(str(lemma or "").strip().lower(), str(pos or "").strip().upper())
        return self._book_word_translation_seed(clean_book_id, target_lang).get(key, "")

    def _book_word_translation_seed(self, book_id: str, target_lang: str) -> dict[str, str]:
        target_lang = str(target_lang or "ru").strip().lower()
        seed_path = self.library_dictionary_store.book_layer_path(book_id, target_lang).parent / f"seed_words_{target_lang}.json"
        if seed_path.exists():
            try:
                payload = json.loads(seed_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                payload = {}
            if isinstance(payload, dict):
                result: dict[str, str] = {}
                for key, value in payload.items():
                    clean_key = str(key or "").strip()
                    if not clean_key:
                        continue
                    if isinstance(value, dict):
                        translations = value.get("translations")
                        if isinstance(translations, list) and translations:
                            text = str(translations[0] or "").strip()
                        else:
                            text = str(value.get("translation") or "").strip()
                    else:
                        text = str(value or "").strip()
                    if text:
                        result[clean_key] = text
                if result:
                    return result
        return {}


    def _book_phrase_seed(self, book_id: str, target_lang: str) -> list[dict]:
        target_lang = str(target_lang or "ru").strip().lower()
        seed_path = self.library_dictionary_store.book_layer_path(book_id, target_lang).parent / f"seed_phrases_{target_lang}.json"
        if not seed_path.exists():
            return []
        try:
            payload = json.loads(seed_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []

        records: list[dict] = []
        if isinstance(payload, dict):
            for source, value in payload.items():
                if isinstance(value, dict):
                    translations = value.get("translations")
                    if isinstance(translations, list) and translations:
                        translation = str(translations[0] or "").strip()
                    else:
                        translation = str(value.get("translation") or "").strip()
                    components = value.get("components")
                else:
                    translation = str(value or "").strip()
                    components = None
                records.append(
                    {
                        "source": str(source or "").strip(),
                        "translation": translation,
                        "components": components,
                    }
                )
        elif isinstance(payload, list):
            for item in payload:
                if not isinstance(item, dict):
                    continue
                source = str(item.get("source") or item.get("phrase") or "").strip()
                translations = item.get("translations")
                if isinstance(translations, list) and translations:
                    translation = str(translations[0] or "").strip()
                else:
                    translation = str(item.get("translation") or "").strip()
                records.append(
                    {
                        "source": source,
                        "translation": translation,
                        "components": item.get("components"),
                    }
                )

        phrases: list[dict] = []
        seen: set[str] = set()
        for record in records:
            source = str(record.get("source") or "").strip()
            translation = str(record.get("translation") or "").strip()
            key = source.lower()
            if not key or not translation or key in seen:
                continue
            phrase = {"source": source, "translation": translation}
            components = record.get("components")
            if isinstance(components, list) and components:
                phrase["components"] = components
            phrases.append(phrase)
            seen.add(key)
        return phrases

    def rebuild_book_quality(self, book_id: str | None = None) -> dict:
        resolved = self._resolve_required_book_id(book_id)
        return {"ok": True, "book_id": resolved, "mode": "source_only", "segment_count": self._segment_count(resolved)}

    def rebuild_book_source_first(self, book_id: str | None = None) -> dict:
        resolved = self._resolve_required_book_id(book_id)
        return {"ok": True, "book_id": resolved, "mode": "removed", "segment_count": self._segment_count(resolved)}

    def rebuild_book_simalign(self, book_id: str | None = None) -> dict:
        resolved = self._resolve_required_book_id(book_id)
        return {"ok": True, "book_id": resolved, "mode": "removed", "segment_count": self._segment_count(resolved)}

    def rebuild_book_resolved_alignment(self, book_id: str | None = None) -> dict:
        resolved = self._resolve_required_book_id(book_id)
        return {"ok": True, "book_id": resolved, "mode": "removed", "segment_count": self._segment_count(resolved)}

    def rebuild_book_dictionary_manifest(self, book_id: str | None = None) -> dict:
        resolved = self._resolve_required_book_id(book_id)
        with self._connect() as conn:
            count = self._rebuild_book_dictionary_entries(conn, resolved)
        return {"ok": True, "book_id": resolved, "dictionary_entry_count": count}

    def get_paragraphs(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved_book_id = self._resolve_book_id(conn, book_id)
            if resolved_book_id is None:
                return {
                    "book_id": None,
                    "title": None,
                    "status": "empty",
                    "source_lang": None,
                    "target_lang": None,
                    "current_paragraph_index": 0,
                    "paragraphs": [],
                }
            book = conn.execute("SELECT * FROM books WHERE id = ?", (resolved_book_id,)).fetchone()
            paragraphs = conn.execute(
                "SELECT * FROM paragraphs WHERE book_id = ? ORDER BY order_index",
                (resolved_book_id,),
            ).fetchall()
            segments = conn.execute(
                "SELECT * FROM segments WHERE book_id = ? ORDER BY paragraph_id, order_index",
                (resolved_book_id,),
            ).fetchall()
            words = conn.execute(
                "SELECT * FROM source_words WHERE book_id = ? ORDER BY paragraph_id, order_index_in_paragraph",
                (resolved_book_id,),
            ).fetchall()
        segments_by_paragraph: dict[str, list[sqlite3.Row]] = {}
        for row in segments:
            segments_by_paragraph.setdefault(str(row["paragraph_id"]), []).append(row)
        words_by_paragraph: dict[str, list[sqlite3.Row]] = {}
        for row in words:
            words_by_paragraph.setdefault(str(row["paragraph_id"]), []).append(row)
        return {
            "book_id": resolved_book_id,
            "title": str(book["title"] or "") if book else "",
            "status": str(book["status"] or BOOK_STATUS_READY) if book else BOOK_STATUS_READY,
            "source_lang": str(book["source_lang"] or "en") if book else "en",
            "target_lang": str(book["target_lang"] or "ru") if book else "ru",
            "current_paragraph_index": int(book["current_paragraph_index"] or 0) if book else 0,
            "paragraphs": [
                self._reader_paragraph_payload(row, segments_by_paragraph.get(str(row["id"]), []), words_by_paragraph.get(str(row["id"]), []))
                for row in paragraphs
            ],
        }

    def _reader_paragraph_payload(self, paragraph: sqlite3.Row, segments: list[sqlite3.Row], words: list[sqlite3.Row]) -> dict:
        segments_by_id = {str(row["id"]): row for row in segments}
        word_payloads = [self._reader_word_payload(row, segments_by_id.get(str(row["segment_id"]))) for row in words]
        return {
            "index": int(paragraph["order_index"]),
            "source_text": str(paragraph["source_text"] or ""),
            "target_text": str(paragraph["target_text"] or ""),
            "segments_v2": [self._reader_segment_payload(row) for row in segments],
            "tokens": self._build_reader_tokens(str(paragraph["source_text"] or ""), word_payloads),
            "words": word_payloads,
        }

    def _reader_segment_payload(self, row: sqlite3.Row) -> dict:
        return {
            "id": str(row["id"]),
            "order_index": int(row["order_index"]),
            "source_text": str(row["source_text"] or ""),
            "target_text": str(row["target_text"] or ""),
            "segment_type": "source_segment",
            "translation_kind": str(row["translation_kind"] or "none"),
            "analysis_version": str(row["analysis_version"] or "source_only_v1"),
            "segment_meta": {},
            "source_analysis": {},
            "source_lookup": {},
            "source_coverage": {},
            "source_effective": {},
            "segment_alignment": {},
        }

    def _reader_word_payload(self, row: sqlite3.Row, segment: sqlite3.Row | None = None) -> dict:
        text = str(row["surface_text"] or "")
        word_id = str(row["id"])
        segment_source_text = str(segment["source_text"] or "") if segment is not None else ""
        segment_target_text = str(segment["target_text"] or "") if segment is not None else ""
        return {
            "id": word_id,
            "text": text,
            "order_index": int(row["order_index_in_paragraph"]),
            "order_index_in_segment": int(row["order_index_in_segment"]),
            "target_start_index": -1,
            "target_end_index": -1,
            "segment_id": str(row["segment_id"]),
            "anchor_word_id": word_id,
            "tap_unit_id": word_id,
            "source_unit_text": text,
            "translation_span_text": "",
            "translation_left_text": "",
            "translation_focus_text": "",
            "translation_right_text": "",
            "unit_translation_span_text": segment_target_text,
            "unit_translation_left_text": "",
            "unit_translation_focus_text": segment_target_text,
            "unit_translation_right_text": "",
            "segment_source_text": segment_source_text,
            "segment_target_text": segment_target_text,
            "lemma": str(row["lemma"] or row["normalized_text"] or "").lower(),
            "pos": str(row["pos"] or ""),
            "morph": "",
            "lexical_unit_id": word_id,
            "lexical_unit_type": "LEXICAL",
            "grammar_hint": "",
            "morph_label": "",
            "source_first_unit_id": "",
            "source_first_unit_text": "",
            "source_first_left_text": "",
            "source_first_focus_text": "",
            "source_first_right_text": "",
            "source_first_coverage_status": "",
            "source_first_effective_source": "",
            "effective_translation_text": segment_target_text,
            "effective_left_text": "",
            "effective_focus_text": segment_target_text,
            "effective_right_text": "",
            "effective_matched_by": "segment_translation" if segment_target_text else "",
            "effective_alignment_kind": "segment",
            "effective_coverage_status": "segment" if segment_target_text else "",
        }

    def _build_reader_tokens(self, source_text: str, words: list[dict]) -> list[dict]:
        tokens: list[dict] = []
        words_by_text: dict[str, list[dict]] = {}
        for word in words:
            words_by_text.setdefault(str(word["text"]), []).append(word)
        used_indexes: dict[str, int] = {}
        order_index = 0
        cursor = 0
        for match in TOKEN_RE.finditer(source_text):
            if match.start() > cursor:
                gap_text = source_text[cursor:match.start()]
                tokens.append(
                    {
                        "id": f"tok_{order_index}",
                        "text": gap_text,
                        "kind": "punctuation",
                        "order_index": order_index,
                        "tap_unit_id": None,
                        "word_id": None,
                    }
                )
                order_index += 1
            text = match.group(0)
            word = None
            if WORD_RE.fullmatch(text):
                index = used_indexes.get(text, 0)
                candidates = words_by_text.get(text, [])
                if index < len(candidates):
                    word = candidates[index]
                    used_indexes[text] = index + 1
            tokens.append(
                {
                    "id": f"tok_{order_index}",
                    "text": text,
                    "kind": "word" if word is not None else "punctuation",
                    "order_index": order_index,
                    "tap_unit_id": str(word["tap_unit_id"]) if word else None,
                    "word_id": str(word["id"]) if word else None,
                }
            )
            order_index += 1
            cursor = match.end()
        if cursor < len(source_text):
            tokens.append(
                {
                    "id": f"tok_{order_index}",
                    "text": source_text[cursor:],
                    "kind": "punctuation",
                    "order_index": order_index,
                    "tap_unit_id": None,
                    "word_id": None,
                }
            )
        return tokens

    def _dictionary_key(self, lemma: str, pos: str) -> str:
        return f"{str(lemma or '').strip().lower()}|{str(pos or '').strip().upper()}"

    def _rebuild_book_dictionary_entries(self, conn: sqlite3.Connection, book_id: str) -> int:
        rows = conn.execute(
            """
            SELECT normalized_text, lemma, pos
            FROM source_words
            WHERE book_id = ?
            ORDER BY lemma, pos
            """,
            (book_id,),
        ).fetchall()
        entries_by_key: dict[str, tuple[str, str, str]] = {}
        for row in rows:
            surface = str(row["normalized_text"] or "").strip().lower()
            lemma = str(row["lemma"] or surface).strip().lower()
            pos = str(row["pos"] or "").strip()
            if not lemma:
                continue
            key = self._dictionary_key(lemma, pos)
            entries_by_key.setdefault(key, (surface or lemma, lemma, pos))

        conn.execute("DELETE FROM book_dictionary_entries WHERE book_id = ?", (book_id,))
        created_at = datetime.now(timezone.utc).isoformat()
        entry_rows = []
        for key, (surface, lemma, pos) in entries_by_key.items():
            entry = self.dictionary_lookup.lookup_word(surface, lemma=lemma, pos=pos, target_lang="ru")
            entry["dictionary_key"] = key
            entry["offline_manifest"] = True
            entry_rows.append(
                (
                    book_id,
                    key,
                    lemma,
                    pos,
                    json.dumps(entry, ensure_ascii=False),
                    created_at,
                )
            )
        if entry_rows:
            conn.executemany(
                """
                INSERT INTO book_dictionary_entries(book_id, dictionary_key, lemma, pos, entry_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                entry_rows,
            )
        return len(entry_rows)

    def _get_book_dictionary_entry(self, conn: sqlite3.Connection, book_id: str, lemma: str, pos: str) -> dict | None:
        dictionary_key = self._dictionary_key(lemma, pos)
        row = conn.execute(
            """
            SELECT entry_json
            FROM book_dictionary_entries
            WHERE book_id = ? AND dictionary_key = ?
            """,
            (book_id, dictionary_key),
        ).fetchone()
        if row is None:
            return None
        payload = self._json_object(row["entry_json"])
        return payload if isinstance(payload, dict) else None

    def _book_dictionary_source_items(self, conn: sqlite3.Connection, book_id: str) -> dict[str, tuple[str, str, str]]:
        rows = conn.execute(
            """
            SELECT normalized_text, lemma, pos
            FROM source_words
            WHERE book_id = ?
            ORDER BY lemma, pos
            """,
            (book_id,),
        ).fetchall()
        entries_by_key: dict[str, tuple[str, str, str]] = {}
        for row in rows:
            surface = str(row["normalized_text"] or "").strip().lower()
            lemma = str(row["lemma"] or surface).strip().lower()
            pos = str(row["pos"] or "").strip()
            if not lemma:
                continue
            key = self._dictionary_key(lemma, pos)
            entries_by_key.setdefault(key, (surface or lemma, lemma, pos))
        return entries_by_key

    def _book_context_dictionary_source_items(
        self,
        conn: sqlite3.Connection,
        book_id: str,
        target_lang: str,
    ) -> dict[str, tuple[str, str, str, str, str]]:
        rows = conn.execute(
            """
            SELECT source_words.normalized_text, source_words.lemma, source_words.pos,
                   segments.source_text AS segment_source_text,
                   segments.target_text AS segment_target_text,
                   books.target_lang AS book_target_lang
            FROM source_words
            JOIN segments ON segments.id = source_words.segment_id
            JOIN books ON books.id = source_words.book_id
            WHERE source_words.book_id = ?
            ORDER BY source_words.lemma, source_words.pos
            """,
            (book_id,),
        ).fetchall()
        entries_by_key: dict[str, tuple[str, str, str, str, str]] = {}
        for row in rows:
            surface = str(row["normalized_text"] or "").strip().lower()
            lemma = str(row["lemma"] or surface).strip().lower()
            pos = str(row["pos"] or "").strip()
            if not lemma:
                continue
            segment_source = str(row["segment_source_text"] or "")
            segment_target = (
                str(row["segment_target_text"] or "")
                if str(row["book_target_lang"] or "").strip().lower() == target_lang
                else ""
            )
            key = self._dictionary_key(lemma, pos)
            entries_by_key.setdefault(key, (surface or lemma, lemma, pos, segment_source, segment_target))
        return entries_by_key

    def _context_dictionary_entry(
        self,
        surface: str,
        lemma: str,
        pos: str,
        source_segment: str,
        target_segment: str,
        target_lang: str,
    ) -> dict:
        return self.context_dictionary_resolver.build_entry(
            surface=surface,
            lemma=lemma,
            pos=pos,
            source_segment=source_segment,
            target_segment=target_segment,
            target_lang=target_lang,
        )

    def _book_dictionary_manifest(self, book_id: str, target_lang: str = "ru") -> dict:
        target_lang = str(target_lang or "ru").strip().lower()
        cache_key = (str(book_id), target_lang)
        cached = self._dictionary_manifest_cache.get(cache_key)
        if cached is not None:
            return cached
        with self._connect() as conn:
            source_items = self._book_context_dictionary_source_items(conn, book_id, target_lang)
        entries = {}
        for key, (surface, lemma, pos, source_segment, target_segment) in source_items.items():
            entries[key] = self._context_dictionary_entry(
                surface,
                lemma,
                pos,
                source_segment,
                target_segment,
                target_lang,
            )
        phrases = (
            self.library_dictionary_store.phrase_records(target_lang)
            if target_lang in {"ru", "uk"}
            else {}
        )
        manifest = {
            "book_id": book_id,
            "target_lang": target_lang,
            "source": library_dictionary_source(target_lang) if target_lang in {"ru", "uk"} and self.library_dictionary_store.has_global_words(target_lang) else CONTEXT_DICTIONARY_SOURCE,
            "entry_count": len(entries),
            "entries": entries,
            "phrase_count": len(phrases),
            "phrases": phrases,
        }
        self._dictionary_manifest_cache[cache_key] = manifest
        return manifest

    def _clear_book_dictionary_cache(self, book_id: str) -> None:
        prefix = str(book_id)
        for key in list(self._dictionary_manifest_cache):
            if key[0] == prefix:
                self._dictionary_manifest_cache.pop(key, None)

    def _json_object(self, raw: object) -> dict:
        try:
            payload = json.loads(str(raw or "{}"))
        except Exception:
            return {}
        return payload if isinstance(payload, dict) else {}

    def get_detail_sheet(self, book_id: str, word_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM source_words WHERE id = ? AND book_id = ?", (word_id, book_id)).fetchone()
            segment = None
            if row is not None:
                segment = conn.execute("SELECT source_text, target_text FROM segments WHERE id = ?", (row["segment_id"],)).fetchone()
                dictionary_entry = self._get_book_dictionary_entry(
                    conn,
                    book_id,
                    str(row["lemma"] or row["normalized_text"] or ""),
                    str(row["pos"] or ""),
                )
        if row is None:
            raise ValueError("Word not found")
        text = str(row["surface_text"] or "")
        lookup_query = str(row["normalized_text"] or text)
        lookup_lemma = str(row["lemma"] or lookup_query)
        lookup_pos = str(row["pos"] or "")
        segment_text = str(segment["source_text"] or "") if segment is not None else text
        segment_translation = str(segment["target_text"] or "") if segment is not None else ""
        if dictionary_entry is None:
            dictionary_entry = self.dictionary_lookup.lookup_word(
                lookup_query,
                lemma=lookup_lemma,
                pos=lookup_pos,
                target_lang="ru",
            )
        return {
            "book_id": book_id,
            "word_id": word_id,
            "tap_unit_id": word_id,
            "source_text": text,
            "translation_text": "",
            "sheet_source_text": text,
            "sheet_translation_text": "",
            "example_source_text": segment_text,
            "example_translation_text": segment_translation,
            "source_first": None,
            "dictionary_entry": dictionary_entry,
            "units": [
                {
                    "unit_id": word_id,
                    "source_text": text,
                    "translation": "",
                    "grammar_hint": "",
                    "morph_label": "",
                    "is_primary": True,
                    "is_grammar": False,
                }
            ],
        }

    def build_mobile_book_package(self, book_id: str) -> dict:
        reader_payload = self.get_paragraphs(book_id)
        book_status = self.get_book_status(book_id)
        target_lang = str(book_status.get("target_lang") or "ru").strip().lower()
        dictionary_manifests = {
            "ru": self._book_dictionary_manifest(book_id, "ru"),
            "uk": self._book_dictionary_manifest(book_id, "uk"),
        }
        if target_lang and target_lang not in {"ru", "uk"}:
            dictionary_manifests[target_lang] = self._book_dictionary_manifest(book_id, target_lang)

        return {
            "meta": {
                "local_book_id": str(book_status.get("id") or ""),
                "desktop_book_id": str(book_status.get("id") or ""),
                "title": str(book_status.get("title") or ""),
            },
            "book": book_status,
            "reader": reader_payload,
            "reader_payload": reader_payload,
            "detail_manifest": {},
            "dictionary_manifest": dictionary_manifests.get(target_lang) or dictionary_manifests["ru"],
            "dictionary_manifests": dictionary_manifests,
            "tts_manifest": self._build_mobile_tts_manifest(book_id),
            "word_audio_manifest": self._build_mobile_word_audio_manifest(book_id),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }

    def build_mobile_book_reader_package(self, book_id: str) -> dict:
        reader_payload = self.get_paragraphs(book_id)
        book_status = self.get_book_status(book_id)
        return {
            "meta": {
                "local_book_id": str(book_status.get("id") or ""),
                "desktop_book_id": str(book_status.get("id") or ""),
                "title": str(book_status.get("title") or ""),
                "source_lang": str(book_status.get("source_lang") or "en"),
                "target_lang": str(book_status.get("target_lang") or "ru"),
                "status": str(book_status.get("status") or BOOK_STATUS_READY),
                "current_paragraph_index": int(book_status.get("current_paragraph_index") or 0),
            },
            "book": book_status,
            "reader": reader_payload,
            "reader_payload": reader_payload,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }

    def build_mobile_book_package_manifest(self, book_id: str) -> dict:
        package = self.build_mobile_book_package(book_id)
        parts = self._build_mobile_book_package_parts(package)
        return {
            "meta": package["meta"],
            "book": package["book"],
            "generated_at": package["generated_at"],
            "parts": [
                {
                    "part_id": item["part_id"],
                    "kind": item["kind"],
                    "bytes": len(json.dumps(item["payload"], ensure_ascii=False).encode("utf-8")),
                }
                for item in parts
            ],
        }

    def build_mobile_book_package_part(self, book_id: str, part_id: str) -> dict:
        package = self.build_mobile_book_package(book_id)
        for item in self._build_mobile_book_package_parts(package):
            if item["part_id"] == part_id:
                return {
                    "part_id": item["part_id"],
                    "kind": item["kind"],
                    "payload": item["payload"],
                }
        raise ValueError(f"Unknown package part: {part_id}")

    def _build_mobile_book_package_parts(self, package: dict) -> list[dict]:
        reader_payload = dict(package.get("reader") or {})
        paragraphs = list(reader_payload.get("paragraphs") or [])
        base_reader = {
            "book_id": reader_payload.get("book_id"),
            "title": reader_payload.get("title"),
            "status": reader_payload.get("status"),
            "source_lang": reader_payload.get("source_lang"),
            "target_lang": reader_payload.get("target_lang"),
            "current_paragraph_index": reader_payload.get("current_paragraph_index", 0),
        }
        parts = [
            {"part_id": "book", "kind": "book", "payload": package.get("book") or {}},
            {"part_id": "reader_meta", "kind": "reader_meta", "payload": base_reader},
        ]
        current_chunk: list[dict] = []
        current_size = 0
        chunk_index = 0
        for paragraph in paragraphs:
            paragraph_size = len(json.dumps(paragraph, ensure_ascii=False).encode("utf-8"))
            if current_chunk and current_size + paragraph_size > MOBILE_PACKAGE_MAX_PART_BYTES:
                parts.append(
                    {
                        "part_id": f"reader_paragraphs_{chunk_index}",
                        "kind": "reader_paragraphs",
                        "payload": {"paragraphs": current_chunk},
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
                    "payload": {"paragraphs": current_chunk},
                }
            )
        parts.append({"part_id": "dictionary_manifest", "kind": "dictionary_manifest", "payload": package.get("dictionary_manifest") or {}})
        parts.append({"part_id": "dictionary_manifests", "kind": "dictionary_manifests", "payload": package.get("dictionary_manifests") or {}})
        parts.append({"part_id": "detail_manifest", "kind": "detail_manifest", "payload": package.get("detail_manifest") or {}})
        parts.append({"part_id": "tts_manifest", "kind": "tts_manifest", "payload": package.get("tts_manifest") or {}})
        parts.append({"part_id": "word_audio_manifest", "kind": "word_audio_manifest", "payload": package.get("word_audio_manifest") or {}})
        return parts

    def get_tts_audio_path(self, book_id: str, job_id: str, segment_index: int) -> Path:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT audio_path FROM tts_segments WHERE book_id = ? AND job_id = ? AND segment_index = ?",
                (book_id, job_id, segment_index),
            ).fetchone()
        if row is None:
            raise ValueError("TTS segment not found")
        path = Path(str(row["audio_path"] or ""))
        if not path.exists():
            raise FileNotFoundError(f"TTS audio file not found: {path}")
        return path

    def get_tts_timings(self, book_id: str, job_id: str, segment_index: int) -> list[dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT timings_path FROM tts_segments WHERE book_id = ? AND job_id = ? AND segment_index = ?",
                (book_id, job_id, segment_index),
            ).fetchone()
        if row is None:
            raise ValueError("TTS segment not found")
        timings_path = Path(str(row["timings_path"] or ""))
        if not timings_path.exists():
            return []
        return json.loads(timings_path.read_text(encoding="utf-8"))

    def get_word_audio_path(self, word: str, voice_id: str | None = None) -> Path:
        return self._ensure_word_audio_path(word, voice_id=voice_id)

    def list_books(self) -> dict:
        with self._connect() as conn:
            active_id = self._get_active_book_id(conn)
            rows = conn.execute(
                """
                SELECT books.*, COUNT(paragraphs.id) AS paragraph_count
                FROM books
                LEFT JOIN paragraphs ON paragraphs.book_id = books.id
                GROUP BY books.id
                ORDER BY COALESCE(books.last_opened_at, books.created_at) DESC
                """
            ).fetchall()
        return {
            "active_book_id": active_id,
            "items": [
                {
                    **self._book_row_to_status(row, int(row["paragraph_count"] or 0)),
                    "is_active": str(row["id"]) == active_id,
                    "desktop_book_id": str(row["id"]),
                    "content_hash": str(row["content_hash"] or ""),
                }
                for row in rows
            ],
        }

    def set_active_book(self, book_id: str) -> dict:
        timestamp = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            row = conn.execute("SELECT id FROM books WHERE id = ?", (book_id,)).fetchone()
            if row is None:
                raise ValueError(f"No such book: {book_id}")
            conn.execute(
                "INSERT INTO app_state(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (ACTIVE_BOOK_STATE_KEY, book_id),
            )
            conn.execute("UPDATE books SET last_opened_at = ? WHERE id = ?", (timestamp, book_id))
        return self.get_book_status(book_id)

    def delete_book(self, book_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute("SELECT id FROM books WHERE id = ?", (book_id,)).fetchone()
            if row is None:
                raise ValueError(f"No such book: {book_id}")
            self._clear_book_dictionary_cache(book_id)
            conn.execute("DELETE FROM tts_segments WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM tts_jobs WHERE book_id = ?", (book_id,))
            package_rows = conn.execute("SELECT id FROM tts_package_jobs WHERE book_id = ?", (book_id,)).fetchall()
            for package in package_rows:
                conn.execute("DELETE FROM tts_package_stages WHERE package_job_id = ?", (str(package["id"]),))
            conn.execute("DELETE FROM tts_package_jobs WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM target_tokens WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM segment_resolved_alignments WHERE segment_id IN (SELECT id FROM segments WHERE book_id = ?)", (book_id,))
            conn.execute("DELETE FROM segment_alignments WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM source_words WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM segments WHERE book_id = ?", (book_id,))
            conn.execute("DELETE FROM paragraphs WHERE book_id = ?", (book_id,))
            conn.execute("UPDATE saved_cards SET source_book_id = NULL WHERE source_book_id = ?", (book_id,))
            conn.execute("DELETE FROM books WHERE id = ?", (book_id,))
            conn.execute("DELETE FROM app_state WHERE key = ? AND value = ?", (ACTIVE_BOOK_STATE_KEY, book_id))
        shutil.rmtree(self.books_dir / book_id, ignore_errors=True)
        shutil.rmtree(self.tts_dir / book_id, ignore_errors=True)
        return self.list_books()

    def clean_book_artifacts(self, book_id: str | None, voice_ids: list[str] | tuple[str, ...] | None = None) -> dict:
        normalized_book_id = self._resolve_required_book_id(book_id)
        normalized_voice_ids = sorted(
            {
                str(voice_id or "").strip()
                for voice_id in (voice_ids or [])
                if str(voice_id or "").strip()
            }
        )
        deleted_jobs = 0
        deleted_segments = 0
        deleted_package_jobs = 0
        deleted_files = 0
        if not normalized_voice_ids:
            return {
                "ok": True,
                "book_id": normalized_book_id,
                "voice_ids": [],
                "deleted_jobs": 0,
                "deleted_segments": 0,
                "deleted_package_jobs": 0,
                "deleted_files": 0,
            }
        with self._connect() as conn:
            for voice_id in normalized_voice_ids:
                audio_rows = conn.execute(
                    """
                    SELECT audio_path, timings_path
                    FROM tts_segments
                    WHERE book_id = ? AND voice_id = ?
                    """,
                    (normalized_book_id, voice_id),
                ).fetchall()
                for audio_row in audio_rows:
                    for path_key in ("audio_path", "timings_path"):
                        raw_path = str(audio_row[path_key] or "")
                        if not raw_path:
                            continue
                        path = Path(raw_path)
                        if path.exists() and path.is_file():
                            path.unlink(missing_ok=True)
                            deleted_files += 1
                segment_row = conn.execute(
                    "SELECT COUNT(*) AS count FROM tts_segments WHERE book_id = ? AND voice_id = ?",
                    (normalized_book_id, voice_id),
                ).fetchone()
                deleted_segments += int(segment_row["count"] or 0)
                conn.execute(
                    "DELETE FROM tts_segments WHERE book_id = ? AND voice_id = ?",
                    (normalized_book_id, voice_id),
                )
                job_row = conn.execute(
                    "SELECT COUNT(*) AS count FROM tts_jobs WHERE book_id = ? AND voice_id = ?",
                    (normalized_book_id, voice_id),
                ).fetchone()
                deleted_jobs += int(job_row["count"] or 0)
                conn.execute(
                    "DELETE FROM tts_jobs WHERE book_id = ? AND voice_id = ?",
                    (normalized_book_id, voice_id),
                )
                package_rows = conn.execute(
                    "SELECT id FROM tts_package_jobs WHERE book_id = ? AND voice_id = ?",
                    (normalized_book_id, voice_id),
                ).fetchall()
                for package in package_rows:
                    conn.execute(
                        "DELETE FROM tts_package_stages WHERE package_job_id = ?",
                        (str(package["id"]),),
                    )
                deleted_package_jobs += len(package_rows)
                conn.execute(
                    "DELETE FROM tts_package_jobs WHERE book_id = ? AND voice_id = ?",
                    (normalized_book_id, voice_id),
                )
                voice_dir = self.tts_dir / normalized_book_id / self.tts_provider.engine_id / voice_id
                if voice_dir.exists() and voice_dir.is_dir():
                    shutil.rmtree(voice_dir, ignore_errors=True)
        return {
            "ok": True,
            "book_id": normalized_book_id,
            "voice_ids": normalized_voice_ids,
            "deleted_jobs": deleted_jobs,
            "deleted_segments": deleted_segments,
            "deleted_package_jobs": deleted_package_jobs,
            "deleted_files": deleted_files,
        }
    def get_book_status(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved = self._resolve_book_id(conn, book_id)
            if resolved is None:
                return {"has_book": False, "status": "empty", "paragraph_count": 0, "current_paragraph_index": 0}
            row = conn.execute("SELECT * FROM books WHERE id = ?", (resolved,)).fetchone()
            paragraph_count = conn.execute("SELECT COUNT(*) AS count FROM paragraphs WHERE book_id = ?", (resolved,)).fetchone()["count"]
        return self._book_row_to_status(row, int(paragraph_count or 0))

    def get_segment_quality_report(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved = self._resolve_book_id(conn, book_id)
            if resolved is None:
                return {"book_id": None, "status": "empty", "summary": {}, "segments": []}
            rows = conn.execute(
                """
                SELECT paragraphs.order_index AS paragraph_index, segments.order_index AS segment_index,
                       segments.id, segments.source_text, segments.target_text, segments.segment_type
                FROM segments
                JOIN paragraphs ON paragraphs.id = segments.paragraph_id
                WHERE segments.book_id = ?
                ORDER BY paragraphs.order_index, segments.order_index
                """,
                (resolved,),
            ).fetchall()
        segments = [
            {
                "paragraph_index": int(row["paragraph_index"]),
                "segment_index": int(row["segment_index"]),
                "id": str(row["id"]),
                "source_text": str(row["source_text"] or ""),
                "target_text": str(row["target_text"] or ""),
                "segment_type": str(row["segment_type"] or "source_segment"),
                "translation_kind": str(row["translation_kind"] or "none"),
                "quality_score": 100,
                "quality_status": "pass",
                "decision_status": "accept",
                "quality_flags": [],
                "retry_reason_flags": [],
                "winner_reason": "argos_sentence" if str(row["target_text"] or "") else "source_only",
                "candidate_count": 1 if str(row["target_text"] or "") else 0,
            }
            for row in rows
        ]
        return {
            "book_id": resolved,
            "status": "source_only",
            "summary": {"segment_count": len(segments), "fail_count": 0, "retry_count": 0},
            "segments": segments,
        }

    def save_reader_position(self, book_id: str, paragraph_index: int) -> dict:
        with self._connect() as conn:
            conn.execute(
                "UPDATE books SET current_paragraph_index = ?, last_opened_at = ? WHERE id = ?",
                (paragraph_index, datetime.now(timezone.utc).isoformat(), book_id),
            )
        return {"ok": True, "book_id": book_id, "paragraph_index": paragraph_index}

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
        overwrite: bool = False,
    ) -> dict:
        return self.tts_service.generate_jobs(
            book_id=book_id,
            voice_id=voice_id,
            level_ids=level_ids,
            mode=mode,
            overwrite=overwrite,
        )

    def start_tts_job(self, book_id: str, job_id: str) -> dict:
        return self.tts_service.start_playback(book_id=book_id, job_id=job_id)

    def control_tts(self, book_id: str, job_id: str, action: str) -> dict:
        return self.tts_service.control(book_id=book_id, job_id=job_id, action=action)

    def get_tts_state(self, book_id: str | None = None) -> dict:
        with self._connect() as conn:
            resolved = self._resolve_book_id(conn, book_id)
        if resolved is None:
            return {"jobs": [], "active_job": None, "active_segments": []}
        return self.tts_service.get_state(book_id=resolved)

    def generate_tts_package(
        self,
        book_id: str,
        voice_id: str,
        overwrite: bool = False,
        overwrite_word_audio: bool = False,
    ) -> dict:
        return self.start_tts_package_generation(book_id, voice_id, overwrite, overwrite_word_audio)

    def get_tts_package(self, book_id: str, voice_id: str) -> dict:
        return self.get_tts_package_state(book_id, voice_id)

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
            resolved = self._resolve_book_id(conn, book_id)
            if resolved is None:
                raise ValueError(f"Book not found: {book_id}")
            existing = conn.execute(
                """
                SELECT id FROM tts_package_jobs
                WHERE book_id = ? AND voice_id = ? AND status IN ('queued', 'running')
                LIMIT 1
                """,
                (resolved, voice_id),
            ).fetchone()
            if existing is not None:
                raise ValueError("TTS package generation is already in progress for this voice")
            conn.execute(
                """
                INSERT INTO tts_package_jobs(id, book_id, voice_id, status, created_at, updated_at, error_message)
                VALUES (?, ?, ?, ?, ?, ?, NULL)
                """,
                (package_job_id, resolved, voice_id, "queued", timestamp, timestamp),
            )
            for stage_key, label in self._PACKAGE_STAGE_LABELS.items():
                conn.execute(
                    """
                    INSERT INTO tts_package_stages(
                        id, package_job_id, stage_key, label, status, done_count,
                        total_count, error_message, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, 'pending', 0, 0, NULL, ?, ?)
                    """,
                    (f"{package_job_id}_{stage_key}", package_job_id, stage_key, label, timestamp, timestamp),
                )
        self._start_tts_package_worker(package_job_id, overwrite, overwrite_word_audio)
        return self.get_tts_package_state(book_id, voice_id)

    def get_tts_package_state(self, book_id: str, voice_id: str) -> dict:
        with self._connect() as conn:
            resolved = self._resolve_book_id(conn, book_id)
            if resolved is None:
                return {"book_id": book_id, "voice_id": voice_id, "status": "idle", "package_job_id": "", "stages": []}
            job = conn.execute(
                """
                SELECT * FROM tts_package_jobs
                WHERE book_id = ? AND voice_id = ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (resolved, voice_id),
            ).fetchone()
            if job is None:
                return {"book_id": resolved, "voice_id": voice_id, "status": "idle", "package_job_id": "", "stages": []}
            stages = conn.execute(
                """
                SELECT stage_key, label, status, done_count, total_count, error_message
                FROM tts_package_stages
                WHERE package_job_id = ?
                ORDER BY CASE stage_key WHEN 'base_audio' THEN 1 WHEN 'slow_audio' THEN 2 WHEN 'word_audio' THEN 3 ELSE 99 END
                """,
                (job["id"],),
            ).fetchall()
        return {
            "book_id": resolved,
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
                for row in stages
            ],
        }

    def _start_tts_package_worker(self, package_job_id: str, overwrite: bool, overwrite_word_audio: bool) -> None:
        worker = threading.Thread(
            target=self._run_tts_package_job,
            args=(package_job_id, overwrite, overwrite_word_audio),
            daemon=True,
        )
        with self._package_lock:
            self._package_workers[package_job_id] = worker
        worker.start()

    def _run_tts_package_job(self, package_job_id: str, overwrite: bool, overwrite_word_audio: bool) -> None:
        try:
            with self._connect() as conn:
                job = conn.execute("SELECT book_id, voice_id FROM tts_package_jobs WHERE id = ?", (package_job_id,)).fetchone()
            if job is None:
                return
            book_id = str(job["book_id"])
            voice_id = str(job["voice_id"])
            self._update_package_job_status(package_job_id, "running")
            self._run_package_audio_stage(package_job_id, "base_audio", book_id, voice_id, "base", overwrite)
            self._run_package_audio_stage(package_job_id, "slow_audio", book_id, voice_id, "slow_native", overwrite)
            self._run_package_word_stage(package_job_id, book_id, voice_id, overwrite_word_audio)
            self._update_package_job_status(package_job_id, "done")
        except Exception as exc:
            self._update_package_job_status(package_job_id, "error", str(exc))
        finally:
            with self._package_lock:
                self._package_workers.pop(package_job_id, None)

    def _run_package_audio_stage(
        self,
        package_job_id: str,
        stage_key: str,
        book_id: str,
        voice_id: str,
        audio_variant: str,
        overwrite: bool,
    ) -> None:
        self._update_package_stage(package_job_id, stage_key, status="running", error_message="")
        level_id = self._resolve_level_id_for_variant(audio_variant)
        existing = self._find_tts_job_for_variant(book_id=book_id, voice_id=voice_id, audio_variant=audio_variant)
        if not overwrite and existing is not None and existing["status"] == "ready":
            self._update_package_stage(
                package_job_id,
                stage_key,
                status="done",
                done_count=int(existing["ready_segments"] or 0),
                total_count=int(existing["total_segments"] or 0),
                error_message="",
            )
            return
        self.tts_service.generate_jobs(book_id=book_id, voice_id=voice_id, level_ids=[level_id], overwrite=overwrite)
        self._poll_package_audio_stage(package_job_id, stage_key, book_id, voice_id, audio_variant)

    def _poll_package_audio_stage(self, package_job_id: str, stage_key: str, book_id: str, voice_id: str, audio_variant: str) -> None:
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
                self._update_package_stage(package_job_id, stage_key, status="done", done_count=ready, total_count=total, error_message="")
                return
            if status == "error":
                raise RuntimeError(str(job.get("error_message") or f"{audio_variant} generation failed"))
            time.sleep(0.35)

    def _run_package_word_stage(self, package_job_id: str, book_id: str, voice_id: str, overwrite_word_audio: bool) -> None:
        self._update_package_stage(package_job_id, "word_audio", status="running", error_message="")
        entries = self._collect_book_word_audio_entries(book_id)
        self._update_package_stage(package_job_id, "word_audio", status="running", total_count=len(entries))
        for index, entry in enumerate(entries, start=1):
            self._ensure_word_audio_path(entry, voice_id=voice_id, overwrite=overwrite_word_audio)
            self._update_package_stage(package_job_id, "word_audio", status="running", done_count=index, total_count=len(entries), error_message="")
        self._update_package_stage(package_job_id, "word_audio", status="done", done_count=len(entries), total_count=len(entries), error_message="")

    def _collect_book_word_audio_entries(self, book_id: str) -> list[str]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT lemma, normalized_text FROM source_words WHERE book_id = ? ORDER BY order_index_in_paragraph",
                (book_id,),
            ).fetchall()
        entries: list[str] = []
        seen: set[str] = set()
        for row in rows:
            candidate = str(row["lemma"] or row["normalized_text"] or "").strip().lower()
            if not candidate or candidate in seen or not re.search(r"[a-z]", candidate):
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
        self.tts_provider.synthesize(normalized, selected_voice_id, audio_path, rate=0.89)
        if not audio_path.exists() or not audio_path.is_file():
            raise FileNotFoundError(f"Word audio file not found: {audio_path}")
        return audio_path

    def _find_tts_job_for_variant(self, *, book_id: str, voice_id: str, audio_variant: str) -> sqlite3.Row | None:
        with self._connect() as conn:
            return conn.execute(
                """
                SELECT * FROM tts_jobs
                WHERE book_id = ? AND voice_id = ? AND audio_variant = ?
                ORDER BY created_at DESC
                LIMIT 1
                """,
                (book_id, voice_id, audio_variant),
            ).fetchone()

    def _resolve_level_id_for_variant(self, audio_variant: str) -> int:
        for item in self.tts_service.get_levels().get("items", []):
            if str(item.get("audio_variant") or "base") == audio_variant:
                return int(item["id"])
        raise ValueError(f"No TTS level configured for audio variant '{audio_variant}'")

    def _update_package_job_status(self, package_job_id: str, status: str, error_message: str | None = None) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE tts_package_jobs SET status = ?, error_message = ?, updated_at = ? WHERE id = ?",
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

    def list_saved_cards(self, status: str | None = None) -> dict:
        with self._connect() as conn:
            if status:
                rows = conn.execute("SELECT * FROM saved_cards WHERE status = ? AND deleted_at IS NULL ORDER BY updated_at DESC", (status,)).fetchall()
            else:
                rows = conn.execute("SELECT * FROM saved_cards WHERE deleted_at IS NULL ORDER BY updated_at DESC").fetchall()
        items = [self._saved_card_to_payload(row) for row in rows]
        return {"items": items, "summary": self._build_cards_summary(items)}

    def get_review_cards(self) -> dict:
        return self.list_saved_cards("new")

    def save_detail_unit(self, book_id: str, word_id: str, unit_id: str) -> dict:
        with self._connect() as conn:
            word = conn.execute("SELECT * FROM source_words WHERE id = ? AND book_id = ?", (word_id, book_id)).fetchone()
            if word is None:
                raise ValueError("Word not found")
            now = datetime.now(timezone.utc).isoformat()
            card_id = f"card_{uuid.uuid4().hex[:16]}"
            conn.execute(
                """
                INSERT INTO saved_cards(
                    id, head_text, translation, grammar_label, example_source_text,
                    example_translation_text, source_word_id, source_unit_id,
                    source_paragraph_id, source_segment_id, source_book_id, status,
                    box, due_at, created_at, updated_at, deleted_at, desktop_card_id,
                    device_id, sync_updated_at
                )
                VALUES (?, ?, '', '', ?, '', ?, ?, ?, ?, ?, 'new', 0, NULL, ?, ?, NULL, ?, 'desktop', ?)
                """,
                (
                    card_id,
                    str(word["surface_text"] or ""),
                    str(word["surface_text"] or ""),
                    word_id,
                    unit_id,
                    str(word["paragraph_id"]),
                    str(word["segment_id"]),
                    book_id,
                    now,
                    now,
                    card_id,
                    now,
                ),
            )
        return self._saved_card_payload_by_id(card_id)

    def save_dictionary_card(self, book_id: str, word_id: str, translations: list[str]) -> dict:
        selected = self._dedupe_texts(translations)
        if not selected:
            raise ValueError("At least one translation is required")
        translation_text = "; ".join(selected)
        with self._connect() as conn:
            word = conn.execute("SELECT * FROM source_words WHERE id = ? AND book_id = ?", (word_id, book_id)).fetchone()
            if word is None:
                raise ValueError("Word not found")
            existing = conn.execute(
                """
                SELECT id
                FROM saved_cards
                WHERE source_book_id = ?
                  AND source_word_id = ?
                  AND translation = ?
                  AND deleted_at IS NULL
                LIMIT 1
                """,
                (book_id, word_id, translation_text),
            ).fetchone()
            if existing is not None:
                return self._saved_card_payload_by_id(str(existing["id"]))
            segment = conn.execute("SELECT source_text FROM segments WHERE id = ?", (word["segment_id"],)).fetchone()
            now = datetime.now(timezone.utc).isoformat()
            card_id = f"card_{uuid.uuid4().hex[:16]}"
            surface = str(word["surface_text"] or "")
            lemma = str(word["lemma"] or word["normalized_text"] or surface).strip().lower()
            pos = str(word["pos"] or "")
            example_source = str(segment["source_text"] or surface) if segment is not None else surface
            conn.execute(
                """
                INSERT INTO saved_cards(
                    id, card_type, head_text, surface_text, lemma, translation, grammar_label,
                    example_text, example_translation, example_source_text,
                    example_translation_text, pos, morph_label, source_word_id,
                    source_unit_id, source_paragraph_id, source_segment_id,
                    source_book_id, status, box, due_at, created_at, updated_at,
                    deleted_at, desktop_card_id, device_id, sync_updated_at
                )
                VALUES (?, 'lexical', ?, ?, ?, ?, '', ?, '', ?, '', ?, '', ?, ?, ?, ?, ?, 'new', 0, NULL, ?, ?, NULL, ?, 'desktop', ?)
                """,
                (
                    card_id,
                    lemma or surface,
                    surface,
                    lemma,
                    translation_text,
                    example_source,
                    example_source,
                    pos,
                    word_id,
                    word_id,
                    str(word["paragraph_id"]),
                    str(word["segment_id"]),
                    book_id,
                    now,
                    now,
                    card_id,
                    now,
                ),
            )
        return self._saved_card_payload_by_id(card_id)

    def save_raw_word(self, word: str) -> dict:
        normalized = str(word or "").strip()
        if not normalized:
            raise ValueError("Word is required")
        now = datetime.now(timezone.utc).isoformat()
        card_id = f"raw_{uuid.uuid4().hex[:16]}"
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO saved_cards(
                    id, head_text, translation, grammar_label, example_source_text,
                    example_translation_text, status, box, created_at, updated_at,
                    desktop_card_id, device_id, sync_updated_at
                )
                VALUES (?, ?, '', '', ?, '', 'new', 0, ?, ?, ?, 'desktop', ?)
                """,
                (card_id, normalized, normalized, now, now, card_id, now),
            )
        return self._saved_card_payload_by_id(card_id)

    def _dedupe_texts(self, items: list[str]) -> list[str]:
        result = []
        seen = set()
        for item in items:
            text = str(item or "").strip()
            key = text.lower()
            if not text or key in seen:
                continue
            seen.add(key)
            result.append(text)
        return result

    def list_saved_words(self) -> dict:
        return self.list_saved_cards()

    def apply_review_result(self, card_id: str, direction: str) -> dict:
        now = datetime.now(timezone.utc).isoformat()
        status = "learning" if direction == "again" else "known"
        with self._connect() as conn:
            conn.execute(
                "UPDATE saved_cards SET status = ?, updated_at = ?, sync_updated_at = ? WHERE id = ?",
                (status, now, now, card_id),
            )
        return self._saved_card_payload_by_id(card_id)

    def delete_saved_card(self, card_id: str) -> dict:
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute("UPDATE saved_cards SET deleted_at = ?, updated_at = ?, sync_updated_at = ? WHERE id = ?", (now, now, now, card_id))
        return {"ok": True, "card_id": card_id}

    def sync_mobile_cards_full(self, device_id: str, cards_delta: list[dict], last_sync_at: str | None = None) -> dict:
        return {
            "ok": True,
            "device_id": device_id,
            "merged_cards_count": 0,
            "server_time": datetime.now(timezone.utc).isoformat(),
            "cards_delta": [],
            "last_sync_at": last_sync_at,
        }

    def _saved_card_payload_by_id(self, card_id: str) -> dict:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM saved_cards WHERE id = ?", (card_id,)).fetchone()
        if row is None:
            raise ValueError("Card not found")
        return self._saved_card_to_payload(row)

    def _saved_card_to_payload(self, row: sqlite3.Row) -> dict:
        example_text = str(row["example_text"] or row["example_source_text"] or "")
        example_translation = str(row["example_translation"] or row["example_translation_text"] or "")
        return {
            "id": str(row["id"]),
            "card_type": str(row["card_type"] or "lexical"),
            "head_text": str(row["head_text"] or ""),
            "surface_text": str(row["surface_text"] or row["head_text"] or ""),
            "lemma": str(row["lemma"] or row["head_text"] or ""),
            "translation": str(row["translation"] or ""),
            "pos": str(row["pos"] or ""),
            "grammar_label": str(row["grammar_label"] or ""),
            "morph_label": str(row["morph_label"] or ""),
            "example_text": example_text,
            "example_translation": example_translation,
            "example_source_text": example_text,
            "example_translation_text": example_translation,
            "source_word_id": str(row["source_word_id"] or ""),
            "source_unit_id": str(row["source_unit_id"] or ""),
            "source_book_id": str(row["source_book_id"] or ""),
            "status": str(row["status"] or "new"),
            "box": int(row["box"] or 0),
            "due_at": row["due_at"],
            "progress_score": int(row["progress_score"] or 0),
            "review_count": int(row["review_count"] or 0),
            "last_reviewed_at": str(row["last_reviewed_at"] or ""),
            "created_at": str(row["created_at"] or ""),
            "updated_at": str(row["updated_at"] or ""),
            "deleted_at": row["deleted_at"],
            "desktop_card_id": str(row["desktop_card_id"] or row["id"]),
            "device_id": str(row["device_id"] or "desktop"),
            "sync_updated_at": str(row["sync_updated_at"] or row["updated_at"] or ""),
        }

    def _build_cards_summary(self, items: list[dict]) -> dict:
        return {
            "total": len(items),
            "new": sum(1 for item in items if item.get("status") == "new"),
            "learning": sum(1 for item in items if item.get("status") == "learning"),
            "known": sum(1 for item in items if item.get("status") == "known"),
        }

    def _build_mobile_tts_manifest(self, book_id: str) -> dict:
        with self._connect() as conn:
            job_rows = conn.execute(
                """
                SELECT * FROM tts_jobs
                WHERE book_id = ?
                ORDER BY created_at DESC
                """,
                (book_id,),
            ).fetchall()
            segment_rows = conn.execute(
                """
                SELECT job_id, segment_index, paragraph_index, source_text, timings_path,
                       audio_path, duration_ms, status
                FROM tts_segments
                WHERE book_id = ?
                ORDER BY job_id, segment_index
                """,
                (book_id,),
            ).fetchall()
        segments_by_job: dict[str, list[dict]] = {}
        for row in segment_rows:
            segments_by_job.setdefault(str(row["job_id"]), []).append(
                {
                    "segment_index": int(row["segment_index"]),
                    "paragraph_index": int(row["paragraph_index"]),
                    "source_text": str(row["source_text"] or ""),
                    "audio_path": str(row["audio_path"] or ""),
                    "duration_ms": int(row["duration_ms"] or 0),
                    "status": str(row["status"] or "pending"),
                    "audio_url": f"/mobile/books/audio?book_id={book_id}&job_id={row['job_id']}&segment_index={int(row['segment_index'])}",
                    "timings_url": f"/mobile/books/audio-timings?book_id={book_id}&job_id={row['job_id']}&segment_index={int(row['segment_index'])}",
                }
            )
        jobs = []
        for row in job_rows:
            payload = self.tts_service._job_payload(dict(row))
            payload["segments"] = segments_by_job.get(str(row["id"]), [])
            jobs.append(payload)
        return {
            "profiles": self.get_tts_profiles()["items"],
            "levels": self.get_tts_levels()["items"],
            "jobs": jobs,
        }

    def _build_mobile_word_audio_manifest(self, book_id: str) -> dict:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT voice_id FROM tts_package_jobs
                WHERE book_id = ? AND status = 'done'
                GROUP BY voice_id
                ORDER BY voice_id
                """,
                (book_id,),
            ).fetchall()
        voice_ids = sorted({str(row["voice_id"] or "").strip() for row in rows if str(row["voice_id"] or "").strip()})
        if not voice_ids:
            return {"book_id": book_id, "voice_id": "", "items": [], "voices": {}}
        items = self._collect_book_word_audio_entries(book_id)
        voices = {voice_id: {"items": items} for voice_id in voice_ids}
        return {
            "book_id": book_id,
            "voice_id": voice_ids[0],
            "items": items,
            "voices": voices,
        }

    def _split_paragraphs(self, text: str) -> list[str]:
        return [item.strip() for item in re.split(r"\n\s*\n+", text) if item.strip()]

    def _split_segments(self, paragraph: str) -> list[str]:
        segments: list[str] = []
        for line in str(paragraph or "").splitlines():
            line = line.strip()
            if not line:
                continue
            sentences = [match.group(0).strip() for match in SENTENCE_RE.finditer(line) if match.group(0).strip()]
            segments.extend(sentences or [line])
        return segments or ([paragraph.strip()] if paragraph.strip() else [])

    def _segment_count(self, book_id: str) -> int:
        with self._connect() as conn:
            return int(conn.execute("SELECT COUNT(*) AS count FROM segments WHERE book_id = ?", (book_id,)).fetchone()["count"] or 0)

    def _resolve_required_book_id(self, book_id: str | None) -> str:
        with self._connect() as conn:
            resolved = self._resolve_book_id(conn, book_id)
        if resolved is None:
            raise ValueError("No active book")
        return resolved

    def _book_row_to_status(self, row: sqlite3.Row, paragraph_count: int) -> dict:
        return {
            "id": str(row["id"]),
            "has_book": True,
            "title": str(row["title"] or ""),
            "source_name": str(row["source_name"] or ""),
            "source_lang": str(row["source_lang"] or "en"),
            "target_lang": str(row["target_lang"] or "ru"),
            "status": str(row["status"] or BOOK_STATUS_READY),
            "model_name": str(row["model_name"] or "source-only"),
            "error_message": row["error_message"],
            "paragraph_count": paragraph_count,
            "current_paragraph_index": int(row["current_paragraph_index"] or 0),
        }

    def _book_source_path(self, book_id: str) -> Path:
        return self.books_dir / book_id / "source.txt"

    def _normalize_import_source_path(self, source_path: str) -> Path:
        path = Path(source_path).expanduser()
        if not path.is_absolute():
            path = (self.root / path).resolve()
        if not path.exists() or not path.is_file():
            raise FileNotFoundError(f"Source file not found: {path}")
        return path

    def _compute_content_hash(self, source_text: str) -> str:
        return hashlib.sha256(source_text.encode("utf-8")).hexdigest()

    def _book_id_for_import(
        self,
        *,
        stable_book_key: str | None,
        target_lang: str,
        normalized_text: str,
    ) -> str:
        key = (stable_book_key or "").strip()
        if key:
            return f"book_{self._compute_content_hash(f'stable\n{key}')[:12]}"
        return f"book_{self._compute_content_hash(f'{target_lang}\n{normalized_text}')[:12]}"

    def _normalize_title(self, title: str) -> str:
        return title.strip() or "Untitled"

    def _resolve_book_id(self, conn: sqlite3.Connection, explicit_book_id: str | None) -> str | None:
        if explicit_book_id:
            row = conn.execute("SELECT id FROM books WHERE id = ?", (explicit_book_id,)).fetchone()
            return str(row["id"]) if row is not None else None
        active = self._get_active_book_id(conn)
        if active:
            return active
        row = conn.execute("SELECT id FROM books ORDER BY COALESCE(last_opened_at, created_at) DESC LIMIT 1").fetchone()
        return str(row["id"]) if row is not None else None

    def _get_active_book_id(self, conn: sqlite3.Connection) -> str | None:
        row = conn.execute("SELECT value FROM app_state WHERE key = ?", (ACTIVE_BOOK_STATE_KEY,)).fetchone()
        if row is None:
            return None
        book_id = str(row["value"] or "")
        exists = conn.execute("SELECT id FROM books WHERE id = ?", (book_id,)).fetchone()
        return book_id if exists is not None else None








