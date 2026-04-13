from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from engine.assembler import assemble_paragraph
from engine.config import DATA_DIR
from engine.lexical_enrichment import grammar_hint_for_word, morph_label_for_word
from engine.word_alignment import build_tap_word_payloads


DB_PATH = DATA_DIR / "lexo.db"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Печатает отчёт по paragraph/segment translation для анализа качества перевода."
    )
    selector = parser.add_mutually_exclusive_group()
    selector.add_argument("--book-id", help="Идентификатор книги из SQLite.")
    selector.add_argument(
        "--active",
        action="store_true",
        help="Взять активную книгу. Если не указан ни один флаг выбора, используется активная книга.",
    )
    parser.add_argument(
        "--paragraph",
        type=int,
        action="append",
        dest="paragraph_indexes",
        help="Ограничить отчёт конкретным paragraph order_index. Можно указывать несколько раз.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Формат отчёта.",
    )
    parser.add_argument(
        "--show-context",
        action="store_true",
        help="Показывать соседние segment-ы как контекст для текущего segment.",
    )
    parser.add_argument(
        "--show-words",
        dest="show_words",
        action="store_true",
        default=True,
        help="Показывать word-level alignment внутри каждого segment. По умолчанию включено.",
    )
    parser.add_argument(
        "--hide-words",
        dest="show_words",
        action="store_false",
        help="Скрыть word-level alignment и секцию WORD_SEGMENTS.",
    )
    return parser.parse_args()


def connect_db() -> sqlite3.Connection:
    if not DB_PATH.exists():
        raise SystemExit(f"SQLite база не найдена: {DB_PATH}")
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def resolve_book_id(connection: sqlite3.Connection, requested_book_id: str | None) -> str:
    if requested_book_id:
        row = connection.execute(
            "SELECT id, title FROM books WHERE id = ?",
            (requested_book_id,),
        ).fetchone()
        if row is None:
            raise SystemExit(f"Книга не найдена: {requested_book_id}")
        return str(row["id"])

    active_row = connection.execute(
        "SELECT value FROM app_state WHERE key = 'active_book_id'"
    ).fetchone()
    if active_row is None or not str(active_row["value"] or "").strip():
        raise SystemExit("Активная книга не найдена. Укажи --book-id.")
    return str(active_row["value"])


def load_book_report(
    connection: sqlite3.Connection,
    book_id: str,
    paragraph_indexes: set[int] | None,
) -> dict:
    book_row = connection.execute(
        """
        SELECT id, title, source_name, source_lang, target_lang, model_name, status
        FROM books
        WHERE id = ?
        """,
        (book_id,),
    ).fetchone()
    if book_row is None:
        raise SystemExit(f"Книга не найдена: {book_id}")

    paragraph_rows = connection.execute(
        """
        SELECT id, order_index, source_text, target_text
        FROM paragraphs
        WHERE book_id = ?
        ORDER BY order_index
        """,
        (book_id,),
    ).fetchall()

    segments_by_paragraph: dict[str, list[dict]] = {}
    segment_rows = connection.execute(
        """
        SELECT id, paragraph_id, order_index, source_text, target_text
        FROM segments
        WHERE book_id = ?
        ORDER BY paragraph_id, order_index
        """,
        (book_id,),
    ).fetchall()
    for row in segment_rows:
        paragraph_id = str(row["paragraph_id"])
        segments_by_paragraph.setdefault(paragraph_id, []).append(
            {
                "id": str(row["id"]),
                "order_index": int(row["order_index"]),
                "source_text": str(row["source_text"] or ""),
                "target_text": str(row["target_text"] or ""),
            }
        )

    word_rows = connection.execute(
        """
        SELECT sw.id, sw.paragraph_id, sw.segment_id, sw.order_index_in_paragraph, sw.order_index_in_segment,
               sw.surface_text, sw.normalized_text, sw.anchor_source_word_id, sw.lemma, sw.pos, sw.morph,
               sw.lexical_unit_id, sw.lexical_unit_type,
               segments.source_text AS segment_source_text,
               segments.target_text AS segment_target_text,
               wa.target_start_index, wa.target_end_index, wa.target_text
        FROM source_words sw
        JOIN segments ON segments.id = sw.segment_id
        LEFT JOIN word_alignments wa ON wa.source_word_id = sw.id
        WHERE sw.book_id = ?
        ORDER BY sw.paragraph_id, sw.segment_id, sw.order_index_in_segment
        """,
        (book_id,),
    ).fetchall()
    words_by_segment: dict[tuple[str, str], list[dict]] = {}
    for row in word_rows:
        key = (str(row["paragraph_id"]), str(row["segment_id"]))
        words_by_segment.setdefault(key, []).append(
            {
                "id": str(row["id"]),
                "text": str(row["surface_text"] or ""),
                "normalized_text": str(row["normalized_text"] or ""),
                "order_index": int(row["order_index_in_paragraph"]),
                "order_index_in_segment": int(row["order_index_in_segment"]),
                "anchor_word_id": str(row["anchor_source_word_id"] or ""),
                "target_start_index": int(row["target_start_index"]) if row["target_start_index"] is not None else -1,
                "target_end_index": int(row["target_end_index"]) if row["target_end_index"] is not None else -1,
                "translation_span_text": str(row["target_text"] or ""),
                "segment_id": str(row["segment_id"]),
                "segment_source_text": str(row["segment_source_text"] or ""),
                "segment_target_text": str(row["segment_target_text"] or ""),
                "lemma": str(row["lemma"] or ""),
                "pos": str(row["pos"] or ""),
                "morph": str(row["morph"] or ""),
                "lexical_unit_id": str(row["lexical_unit_id"] or ""),
                "lexical_unit_type": str(row["lexical_unit_type"] or ""),
                "grammar_hint": grammar_hint_for_word(row),
                "morph_label": morph_label_for_word(row),
            }
        )

    paragraphs: list[dict] = []
    for row in paragraph_rows:
        paragraph_index = int(row["order_index"])
        if paragraph_indexes is not None and paragraph_index not in paragraph_indexes:
            continue
        paragraph_id = str(row["id"])
        segments = segments_by_paragraph.get(paragraph_id, [])
        enriched_segments: list[dict] = []
        for segment in segments:
            segment_words = words_by_segment.get((paragraph_id, str(segment.get("id") or "")), [])
            segment_words.sort(key=lambda item: int(item["order_index_in_segment"]))
            tap_words = build_tap_word_payloads(
                segment_target_text=segment["target_text"],
                words=segment_words,
            )
            enriched_segments.append(
                {
                    **segment,
                    "source_length": len(segment["source_text"]),
                    "target_length": len(segment["target_text"]),
                    "words": [
                        {
                            "text": str(word.get("text") or ""),
                            "lemma": str(word.get("lemma") or ""),
                            "translation_span_text": str(word.get("translation_span_text") or ""),
                            "translation_left_text": str(word.get("translation_left_text") or ""),
                            "translation_focus_text": str(word.get("translation_focus_text") or ""),
                            "translation_right_text": str(word.get("translation_right_text") or ""),
                            "lexical_unit_type": str(word.get("lexical_unit_type") or ""),
                            "morph_label": str(word.get("morph_label") or ""),
                        }
                        for word in tap_words
                    ],
                }
            )
        reassembled_target = assemble_paragraph([item["target_text"] for item in segments])
        paragraphs.append(
            {
                "paragraph_id": paragraph_id,
                "order_index": paragraph_index,
                "source_text": str(row["source_text"] or ""),
                "target_text": str(row["target_text"] or ""),
                "segment_count": len(segments),
                "source_length": len(str(row["source_text"] or "")),
                "target_length": len(str(row["target_text"] or "")),
                "reassembled_target_text": reassembled_target,
                "paragraph_target_matches_reassembled": str(row["target_text"] or "") == reassembled_target,
                "segments": enriched_segments,
            }
        )

    return {
        "book": {
            "id": str(book_row["id"]),
            "title": str(book_row["title"] or ""),
            "source_name": str(book_row["source_name"] or ""),
            "source_lang": str(book_row["source_lang"] or ""),
            "target_lang": str(book_row["target_lang"] or ""),
            "model_name": str(book_row["model_name"] or ""),
            "status": str(book_row["status"] or ""),
            "paragraph_count": len(paragraphs),
        },
        "paragraphs": paragraphs,
    }


def format_text_report(report: dict, show_context: bool, show_words: bool) -> str:
    book = report["book"]
    lines = [
        f'BOOK: {book["title"]} ({book["id"]})',
        f'SOURCE: {book["source_lang"]} -> TARGET: {book["target_lang"]}',
        f'MODEL: {book["model_name"]}',
        f'STATUS: {book["status"]}',
        f'PARAGRAPHS: {book["paragraph_count"]}',
    ]

    for paragraph in report["paragraphs"]:
        lines.extend(
            [
                "",
                "=" * 100,
                f'PARAGRAPH #{paragraph["order_index"]} | segments={paragraph["segment_count"]} '
                f'| source_len={paragraph["source_length"]} | target_len={paragraph["target_length"]}',
                "SOURCE_PARAGRAPH:",
                paragraph["source_text"],
                "TARGET_PARAGRAPH:",
                paragraph["target_text"],
                "REASSEMBLED_TARGET:",
                paragraph["reassembled_target_text"],
                "PARAGRAPH_TARGET_MATCHES_REASSEMBLED: "
                + ("yes" if paragraph["paragraph_target_matches_reassembled"] else "no"),
            ]
        )

        segments = paragraph["segments"]
        for index, segment in enumerate(segments):
            lines.extend(
                [
                    "",
                    f'  SEGMENT #{segment["order_index"]} | source_len={segment["source_length"]} '
                    f'| target_len={segment["target_length"]}',
                    f'  EN: {segment["source_text"]}',
                    f'  RU: {segment["target_text"]}',
                ]
            )
            if show_context:
                prev_segment = segments[index - 1] if index > 0 else None
                next_segment = segments[index + 1] if index + 1 < len(segments) else None
                lines.append(
                    "  CONTEXT_PREV_EN: "
                    + (prev_segment["source_text"] if prev_segment is not None else "")
                )
                lines.append(
                    "  CONTEXT_PREV_RU: "
                    + (prev_segment["target_text"] if prev_segment is not None else "")
                )
                lines.append(
                    "  CONTEXT_NEXT_EN: "
                    + (next_segment["source_text"] if next_segment is not None else "")
                )
                lines.append(
                    "  CONTEXT_NEXT_RU: "
                    + (next_segment["target_text"] if next_segment is not None else "")
                )
            if show_words:
                for word in segment["words"]:
                    lines.append(
                        "    WORD: "
                        f'{word["text"]} -> {word["translation_span_text"]}'
                    )
                    if show_context:
                        lines.append(
                            "      CTX: "
                            f'{word["translation_left_text"]} | {word["translation_focus_text"]} | {word["translation_right_text"]}'
                        )
                    extra_bits = []
                    if word["lemma"]:
                        extra_bits.append(f'lemma={word["lemma"]}')
                    if word["lexical_unit_type"]:
                        extra_bits.append(f'unit={word["lexical_unit_type"]}')
                    if word["morph_label"]:
                        extra_bits.append(f'morph={word["morph_label"]}')
                    if extra_bits:
                        lines.append("      META: " + " ".join(extra_bits))

        if show_words:
            lines.extend(
                [
                    "",
                    "  WORD_SEGMENTS:",
                ]
            )
            for segment in segments:
                for word in segment["words"]:
                    lines.append(
                        "    "
                        f'S{segment["order_index"]}: {word["text"]} -> {word["translation_span_text"]}'
                    )
                    if show_context:
                        lines.append(
                            "      "
                            f'CTX: {word["translation_left_text"]} | {word["translation_focus_text"]} | {word["translation_right_text"]}'
                        )
                    extra_bits = []
                    if word["lemma"]:
                        extra_bits.append(f'lemma={word["lemma"]}')
                    if word["lexical_unit_type"]:
                        extra_bits.append(f'unit={word["lexical_unit_type"]}')
                    if word["morph_label"]:
                        extra_bits.append(f'morph={word["morph_label"]}')
                    if extra_bits:
                        lines.append("      META: " + " ".join(extra_bits))

    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    requested_book_id = args.book_id
    if not requested_book_id and not args.active:
        args.active = True

    paragraph_indexes = set(args.paragraph_indexes) if args.paragraph_indexes else None

    with connect_db() as connection:
        book_id = resolve_book_id(connection, requested_book_id)
        report = load_book_report(connection, book_id, paragraph_indexes)

    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(format_text_report(report, show_context=args.show_context, show_words=args.show_words))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
