from __future__ import annotations

import json
import shutil
import sqlite3
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "Studio" / "Backend"
BOOK_ID = "book_07a16679df53"
BOOK_DIR = (
    ROOT
    / "Studio"
    / "Runtime"
    / "workbench_output"
    / "a1"
    / "chapters"
    / "book_07a16679df53_a_voice_from_online"
)
OLD_TEXT = '"W-A-L-K-E-R," Ben says.'
NEW_TEXT = '"WALKER," Ben says.'
OLD_WORD = "w-a-l-k-e-r"
NEW_WORD = "walker"
VOICE_ID = "af_heart"
SEGMENT_INDEX = 9


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: object) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def replace_source_text(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if OLD_TEXT in text:
        path.write_text(text.replace(OLD_TEXT, NEW_TEXT, 1), encoding="utf-8")
    elif NEW_TEXT not in text:
        raise RuntimeError(f"Expected source text not found: {path}")


def replace_core_entry(path: Path) -> None:
    payload = load_json(path)
    entries = payload.get("entries") if isinstance(payload.get("entries"), dict) else payload
    old_key = f"{OLD_WORD}|PROPN"
    new_key = f"{NEW_WORD}|PROPN"
    if old_key in entries:
        entries.pop(old_key)
    elif new_key not in entries:
        raise RuntimeError(f"Expected dictionary key not found: {path}")
    entries[new_key] = {
        "pos": "PROPN",
        "translations": {"ru": ["Уокер"], "uk": ["Вокер"]},
        "word": NEW_WORD,
    }
    if entries is payload:
        payload = dict(sorted(payload.items()))
    else:
        payload["entries"] = dict(sorted(entries.items()))
        payload["entry_count"] = len(entries)
    write_json(path, payload)


def replace_derived_values(value: object) -> object:
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            new_key = key.replace(OLD_WORD, NEW_WORD).replace("W-A-L-K-E-R", "WALKER")
            result[new_key] = replace_derived_values(item)
        return result
    if isinstance(value, list):
        return [replace_derived_values(item) for item in value]
    if isinstance(value, str):
        return value.replace(OLD_TEXT, NEW_TEXT).replace("W-A-L-K-E-R", "WALKER").replace(OLD_WORD, NEW_WORD)
    return value


def update_database() -> None:
    db_path = BACKEND / "data" / "lexo.db"
    with sqlite3.connect(db_path) as conn:
        paragraph = conn.execute(
            "SELECT id FROM paragraphs WHERE book_id = ? AND order_index = ? AND source_text IN (?, ?)",
            (BOOK_ID, SEGMENT_INDEX, OLD_TEXT, NEW_TEXT),
        ).fetchone()
        if paragraph is None:
            raise RuntimeError("Expected paragraph was not found")
        paragraph_id = str(paragraph[0])
        conn.execute("UPDATE paragraphs SET source_text = ? WHERE id = ?", (NEW_TEXT, paragraph_id))
        conn.execute(
            "UPDATE segments SET source_text = ? WHERE book_id = ? AND paragraph_id = ?",
            (NEW_TEXT, BOOK_ID, paragraph_id),
        )
        changed = conn.execute(
            """
            UPDATE source_words
            SET surface_text = 'WALKER', normalized_text = ?, lemma = ?
            WHERE book_id = ? AND paragraph_id = ? AND normalized_text IN (?, ?)
            """,
            (NEW_WORD, NEW_WORD, BOOK_ID, paragraph_id, OLD_WORD, NEW_WORD),
        ).rowcount
        if changed != 1:
            raise RuntimeError(f"Expected one source word, changed {changed}")
        conn.execute(
            "UPDATE tts_segments SET source_text = ?, synthesis_text = ? WHERE book_id = ? AND segment_index = ?",
            (NEW_TEXT, NEW_TEXT, BOOK_ID, SEGMENT_INDEX),
        )


def regenerate_voice_segments() -> list[tuple[str, str, Path]]:
    import sys

    sys.path.insert(0, str(BACKEND))
    from engine.storage import LexoStorage
    from engine.tts.tts_models import SpeechProfile
    from engine.tts.tts_provider import KokoroProvider
    from engine.tts.tts_queue import generate_tts_segment

    storage = LexoStorage(BACKEND, tts_provider=KokoroProvider())
    updated: list[tuple[str, str, Path]] = []
    with storage._connect() as conn:
        rows = conn.execute(
            """
            SELECT s.id, s.job_id, s.paragraph_index, s.pause_after_ms,
                   j.level_id, j.level_name, j.target_wpm, j.audio_variant,
                   j.native_rate, j.rate, j.pause_scale
            FROM tts_segments s
            JOIN tts_jobs j ON j.id = s.job_id
            WHERE s.book_id = ? AND s.voice_id = ? AND s.segment_index = ?
              AND j.audio_variant IN ('base', 'slow_native')
            ORDER BY j.audio_variant
            """,
            (BOOK_ID, VOICE_ID, SEGMENT_INDEX),
        ).fetchall()
    if len(rows) != 2:
        raise RuntimeError(f"Expected two speed variants for {VOICE_ID}, found {len(rows)}")
    for row in rows:
        variant = str(row["audio_variant"])
        profile = SpeechProfile(
            level_id=int(row["level_id"]),
            level_name=str(row["level_name"]),
            target_wpm=int(row["target_wpm"] or 0),
            audio_variant=variant,
            native_rate=float(row["native_rate"] or row["rate"] or 0.89),
            word_gap_ms=300 if variant == "slow_native" else 0,
            expand_word_gaps=False,
            playback_speed=1.0,
            rate=float(row["rate"] or 0.89),
            pause_scale=float(row["pause_scale"] or 1.0),
        )
        cache_dir = storage.tts_dir / BOOK_ID / storage.tts_provider.engine_id / VOICE_ID / variant
        result = generate_tts_segment(
            provider=storage.tts_provider,
            cache_dir=cache_dir,
            book_id=BOOK_ID,
            voice_id=VOICE_ID,
            chunk=SimpleNamespace(
                order_index=SEGMENT_INDEX,
                paragraph_index=int(row["paragraph_index"]),
                source_text=NEW_TEXT,
                synthesis_text=NEW_TEXT,
                pause_after_ms=int(row["pause_after_ms"] or 0),
            ),
            profile=profile,
        )
        with storage._connect() as conn:
            conn.execute(
                """
                UPDATE tts_segments
                SET source_text = ?, synthesis_text = ?, audio_path = ?, timings_path = ?,
                    duration_ms = ?, status = 'ready', hash = ?
                WHERE id = ?
                """,
                (
                    NEW_TEXT,
                    NEW_TEXT,
                    result["audio_path"],
                    result["timings_path"],
                    result["duration_ms"],
                    result["hash"],
                    row["id"],
                ),
            )
        output_audio = BOOK_DIR / "audio" / "segments" / f"{row['job_id']}_{SEGMENT_INDEX}.mp3"
        shutil.copyfile(result["audio_path"], output_audio)
        updated.append((str(row["job_id"]), variant, Path(result["audio_path"])))
    return updated


def rebuild_outputs() -> None:
    import sys

    sys.path.insert(0, str(BACKEND))
    from engine.storage import LexoStorage
    from engine.tts.tts_provider import KokoroProvider

    storage = LexoStorage(BACKEND, tts_provider=KokoroProvider())
    storage.rebuild_book_dictionary_manifest(BOOK_ID)
    package = storage.build_mobile_book_package(BOOK_ID)
    write_json(BOOK_DIR / "reader.json", package["reader"])
    write_json(BOOK_DIR / "reader_ru.json", package["reader"])
    write_json(BOOK_DIR / "dictionary_ru.json", package["dictionary_manifests"]["ru"])
    write_json(BOOK_DIR / "dictionary_uk.json", package["dictionary_manifests"]["uk"])
    write_json(BOOK_DIR / "tts_manifest.json", package["tts_manifest"])
    write_json(BOOK_DIR / "word_audio_manifest.json", package["word_audio_manifest"])
    for name in ("reader_uk.json", "word_to_word.json", "word_to_word_ru.json", "word_to_word_uk.json"):
        path = BOOK_DIR / name
        write_json(path, replace_derived_values(load_json(path)))


def main() -> None:
    replace_source_text(ROOT / "Docs" / "Curriculum" / "A1_Corpus" / "01_INTRODUCTION.md")
    replace_source_text(ROOT / "Studio" / "Workbench" / "Books" / "A1" / "Глава 1 - Introduction" / "A Voice from Online.txt")
    replace_source_text(BACKEND / "data" / "books" / BOOK_ID / "source.txt")
    replace_core_entry(BACKEND / "data" / "dictionaries" / "virgil_core" / "virgil_core_dictionary.json")
    replace_core_entry(BACKEND / "data" / "dictionaries" / "virgil_core" / "book_seeds" / "book_07a16679df53_a_voice_from_online.json")
    update_database()
    updated_audio = regenerate_voice_segments()
    rebuild_outputs()
    print(f"Updated {NEW_TEXT}; TTS: {[(job, variant) for job, variant, _ in updated_audio]}")


if __name__ == "__main__":
    main()
