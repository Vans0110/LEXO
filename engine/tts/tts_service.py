from __future__ import annotations

import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from .speech_profiles import build_profile, list_levels
from .tts_models import SpeechProfile
from .tts_queue import generate_tts_segment
from .tts_segmenter import build_tts_chunks


class LexoTtsService:
    def __init__(self, db_path: Path, tts_dir: Path, provider) -> None:
        self.db_path = db_path
        self.tts_dir = tts_dir
        self.provider = provider
        self._workers: dict[str, threading.Thread] = {}
        self._lock = threading.Lock()

    def seed_profiles(self) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM tts_profiles")
            for item in self.provider.list_profiles():
                conn.execute(
                    """
                    INSERT INTO tts_profiles(id, engine_id, voice_id, display_name, lang, is_enabled)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        engine_id = excluded.engine_id,
                        voice_id = excluded.voice_id,
                        display_name = excluded.display_name,
                        lang = excluded.lang,
                        is_enabled = excluded.is_enabled
                    """,
                    (
                        item["id"],
                        item["engine_id"],
                        item["voice_id"],
                        item["display_name"],
                        item["lang"],
                        item["is_enabled"],
                    ),
                )

    def get_profiles(self) -> dict:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, engine_id, voice_id, display_name, lang, is_enabled
                FROM tts_profiles
                WHERE is_enabled = 1
                ORDER BY display_name
                """
            ).fetchall()
        return {"items": [dict(row) for row in rows]}

    def get_levels(self) -> dict:
        return {"items": list_levels()}

    def generate_jobs(
        self,
        *,
        book_id: str,
        voice_id: str,
        level_ids: list[int],
        mode: str = "play_from_current",
    ) -> dict:
        status = self._book_status(book_id)
        if status is None:
            raise ValueError(f"No such book: {book_id}")
        valid_voice_ids = {item["voice_id"] for item in self.provider.list_profiles()}
        if voice_id not in valid_voice_ids:
            raise ValueError(
                f"Voice '{voice_id}' is not available for provider '{self.provider.engine_id}'"
            )
        if not level_ids:
            raise ValueError("No TTS levels selected")

        paragraphs = self._paragraphs(book_id)
        start_index = int(status["current_paragraph_index"]) if mode == "play_from_current" else 0
        profiles = [build_profile(int(level_id)) for level_id in level_ids]
        jobs_to_start: list[str] = []
        timestamp = datetime.now(timezone.utc).isoformat()

        with self._connect() as conn:
            for profile in profiles:
                chunks = build_tts_chunks(
                    paragraphs,
                    start_paragraph_index=start_index,
                    profile=profile,
                )
                if not chunks:
                    raise ValueError("No text available for TTS")
                existing = conn.execute(
                    "SELECT id FROM tts_jobs WHERE book_id = ? AND voice_id = ? AND level_id = ?",
                    (book_id, voice_id, profile.level_id),
                ).fetchall()
                for row in existing:
                    conn.execute("DELETE FROM tts_segments WHERE job_id = ?", (row["id"],))
                conn.execute(
                    "DELETE FROM tts_jobs WHERE book_id = ? AND voice_id = ? AND level_id = ?",
                    (book_id, voice_id, profile.level_id),
                )
                job_id = str(uuid.uuid4())
                audio_dir = self.tts_dir / book_id / self.provider.engine_id / voice_id / f"level_{profile.level_id}"
                audio_dir.mkdir(parents=True, exist_ok=True)
                conn.execute(
                    """
                    INSERT INTO tts_jobs(
                        id, book_id, engine_id, voice_id, mode, status, playback_state,
                        current_segment_index, created_at, updated_at, level_id, level_name,
                        target_wpm, rate, pause_scale, total_segments, ready_segments, error_message
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        job_id,
                        book_id,
                        self.provider.engine_id,
                        voice_id,
                        mode,
                        "queued",
                        "idle",
                        0,
                        timestamp,
                        timestamp,
                        profile.level_id,
                        profile.level_name,
                        profile.target_wpm,
                        profile.rate,
                        profile.pause_scale,
                        len(chunks),
                        0,
                        None,
                    ),
                )
                conn.executemany(
                    """
                    INSERT INTO tts_segments(
                        id, job_id, book_id, segment_index, paragraph_index, engine_id, voice_id,
                        source_text, synthesis_text, pause_after_ms, audio_path, duration_ms, status, hash, created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        (
                            str(uuid.uuid4()),
                            job_id,
                            book_id,
                            chunk.order_index,
                            chunk.paragraph_index,
                            self.provider.engine_id,
                            voice_id,
                            chunk.source_text,
                            chunk.synthesis_text,
                            chunk.pause_after_ms,
                            str(audio_dir / f"pending_{chunk.order_index}.wav"),
                            0,
                            "pending",
                            "",
                            timestamp,
                        )
                        for chunk in chunks
                    ],
                )
                jobs_to_start.append(job_id)

        for job_id in jobs_to_start:
            self._start_worker(job_id)
        return self.get_state(book_id)

    def start_playback(self, *, book_id: str, job_id: str) -> dict:
        with self._connect() as conn:
            job = conn.execute(
                "SELECT id, status FROM tts_jobs WHERE id = ? AND book_id = ?",
                (job_id, book_id),
            ).fetchone()
            if job is None:
                raise ValueError("TTS job not found")
            if job["status"] != "ready":
                raise ValueError("TTS job is not ready yet")
            timestamp = datetime.now(timezone.utc).isoformat()
            conn.execute(
                "UPDATE tts_jobs SET playback_state = ?, updated_at = ? WHERE book_id = ?",
                ("idle", timestamp, book_id),
            )
            conn.execute(
                "UPDATE tts_jobs SET playback_state = ?, updated_at = ? WHERE id = ?",
                ("playing", timestamp, job_id),
            )
        return self.get_state(book_id)

    def control(self, *, book_id: str, job_id: str, action: str) -> dict:
        with self._connect() as conn:
            job = conn.execute(
                """
                SELECT id, current_segment_index, playback_state
                FROM tts_jobs
                WHERE id = ? AND book_id = ?
                """,
                (job_id, book_id),
            ).fetchone()
            if job is None:
                raise ValueError("TTS job not found")
            count_row = conn.execute(
                "SELECT COUNT(*) AS count FROM tts_segments WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            total_segments = int(count_row["count"]) if count_row is not None else 0
            current = int(job["current_segment_index"])
            last_index = max(0, total_segments - 1)
            playback_state = job["playback_state"]
            if action == "pause":
                playback_state = "paused"
            elif action == "resume":
                playback_state = "playing"
            elif action == "stop":
                current = 0
                playback_state = "idle"
            elif action == "next":
                current = min(last_index, current + 1)
                playback_state = "playing"
            elif action == "prev":
                current = max(0, current - 1)
                playback_state = "playing"
            else:
                raise ValueError(f"Unsupported TTS action: {action}")
            conn.execute(
                """
                UPDATE tts_jobs
                SET playback_state = ?, current_segment_index = ?, updated_at = ?
                WHERE id = ?
                """,
                (playback_state, current, datetime.now(timezone.utc).isoformat(), job_id),
            )
        return self.get_state(book_id)

    def get_state(self, book_id: str) -> dict:
        with self._connect() as conn:
            rows = conn.execute(
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
            active_job = conn.execute(
                """
                SELECT id, book_id, engine_id, voice_id, mode, status, playback_state,
                       current_segment_index, level_id, level_name, target_wpm, rate,
                       pause_scale, total_segments, ready_segments, error_message, created_at, updated_at
                FROM tts_jobs
                WHERE book_id = ? AND playback_state IN ('playing', 'paused')
                ORDER BY updated_at DESC
                LIMIT 1
                """,
                (book_id,),
            ).fetchone()
            active_segments_rows = []
            if active_job is not None:
                active_segments_rows = conn.execute(
                    """
                    SELECT segment_index, paragraph_index, source_text, audio_path, duration_ms, pause_after_ms, status
                    FROM tts_segments
                    WHERE job_id = ?
                    ORDER BY segment_index
                    """,
                    (active_job["id"],),
                ).fetchall()
        jobs = [self._job_payload(dict(row)) for row in rows]
        return {
            "jobs": jobs,
            "active_job": self._job_payload(dict(active_job)) if active_job is not None else None,
            "active_segments": [dict(row) for row in active_segments_rows],
        }

    def _start_worker(self, job_id: str) -> None:
        worker = threading.Thread(target=self._run_job, args=(job_id,), daemon=True)
        with self._lock:
            self._workers[job_id] = worker
        worker.start()

    def _run_job(self, job_id: str) -> None:
        try:
            with self._connect() as conn:
                job = conn.execute(
                    """
                    SELECT id, book_id, voice_id, level_id, level_name, target_wpm, rate, pause_scale
                    FROM tts_jobs WHERE id = ?
                    """,
                    (job_id,),
                ).fetchone()
                if job is None:
                    return
                timestamp = datetime.now(timezone.utc).isoformat()
                conn.execute(
                    "UPDATE tts_jobs SET status = ?, updated_at = ?, error_message = NULL WHERE id = ?",
                    ("generating", timestamp, job_id),
                )
                rows = conn.execute(
                    """
                    SELECT id, segment_index, paragraph_index, source_text, synthesis_text, pause_after_ms
                    FROM tts_segments
                    WHERE job_id = ?
                    ORDER BY segment_index
                    """,
                    (job_id,),
                ).fetchall()
            profile = SpeechProfile(
                level_id=int(job["level_id"]),
                level_name=str(job["level_name"]),
                target_wpm=int(job["target_wpm"]),
                rate=float(job["rate"]),
                pause_scale=float(job["pause_scale"]),
            )
            cache_dir = self.tts_dir / job["book_id"] / self.provider.engine_id / job["voice_id"] / f"level_{profile.level_id}"
            cache_dir.mkdir(parents=True, exist_ok=True)

            for row in rows:
                chunk_payload = generate_tts_segment(
                    provider=self.provider,
                    cache_dir=cache_dir,
                    book_id=str(job["book_id"]),
                    voice_id=str(job["voice_id"]),
                    chunk=SimpleNamespace(
                        order_index=int(row["segment_index"]),
                        paragraph_index=int(row["paragraph_index"]),
                        source_text=str(row["source_text"]),
                        synthesis_text=str(row["synthesis_text"] or row["source_text"]),
                        pause_after_ms=int(row["pause_after_ms"] or 0),
                    ),
                    profile=profile,
                )
                with self._connect() as conn:
                    conn.execute(
                        """
                        UPDATE tts_segments
                        SET audio_path = ?, duration_ms = ?, pause_after_ms = ?, status = ?, hash = ?
                        WHERE id = ?
                        """,
                        (
                            chunk_payload["audio_path"],
                            chunk_payload["duration_ms"],
                            chunk_payload["pause_after_ms"],
                            "ready",
                            chunk_payload["hash"],
                            row["id"],
                        ),
                    )
                    count_row = conn.execute(
                        "SELECT COUNT(*) AS count FROM tts_segments WHERE job_id = ? AND status = 'ready'",
                        (job_id,),
                    ).fetchone()
                    ready_segments = int(count_row["count"]) if count_row is not None else 0
                    conn.execute(
                        """
                        UPDATE tts_jobs
                        SET ready_segments = ?, updated_at = ?, status = ?
                        WHERE id = ?
                        """,
                        (
                            ready_segments,
                            datetime.now(timezone.utc).isoformat(),
                            "ready" if ready_segments >= len(rows) else "generating",
                            job_id,
                        ),
                    )
        except Exception as exc:
            with self._connect() as conn:
                conn.execute(
                    "UPDATE tts_jobs SET status = ?, error_message = ?, updated_at = ? WHERE id = ?",
                    ("error", str(exc), datetime.now(timezone.utc).isoformat(), job_id),
                )
        finally:
            with self._lock:
                self._workers.pop(job_id, None)

    def _job_payload(self, job: dict) -> dict:
        total_segments = int(job.get("total_segments") or 0)
        ready_segments = int(job.get("ready_segments") or 0)
        current_segment_index = int(job.get("current_segment_index") or 0)
        return {
            "id": job["id"],
            "book_id": job["book_id"],
            "engine_id": job["engine_id"],
            "voice_id": job["voice_id"],
            "mode": job["mode"],
            "status": job["status"],
            "playback_state": job["playback_state"],
            "current_segment_index": current_segment_index,
            "level_id": int(job.get("level_id") or 0),
            "level_name": job.get("level_name") or "",
            "target_wpm": int(job.get("target_wpm") or 0),
            "rate": float(job.get("rate") or 1.0),
            "pause_scale": float(job.get("pause_scale") or 1.0),
            "total_segments": total_segments,
            "ready_segments": ready_segments,
            "generation_progress": (ready_segments / total_segments) if total_segments else 0.0,
            "current_segment_number": min(current_segment_index + 1, total_segments) if total_segments else 0,
            "playback_progress": ((current_segment_index + 1) / total_segments) if total_segments else 0.0,
            "error_message": job.get("error_message"),
            "created_at": job.get("created_at"),
            "updated_at": job.get("updated_at"),
        }

    def _book_status(self, book_id: str) -> sqlite3.Row | None:
        with self._connect() as conn:
            return conn.execute(
                "SELECT id, current_paragraph_index FROM books WHERE id = ?",
                (book_id,),
            ).fetchone()

    def _paragraphs(self, book_id: str) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT order_index, source_text FROM paragraphs WHERE book_id = ? ORDER BY order_index",
                (book_id,),
            ).fetchall()
        return [{"index": row["order_index"], "source_text": row["source_text"]} for row in rows]

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection
