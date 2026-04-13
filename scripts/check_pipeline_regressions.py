from __future__ import annotations

import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from engine.storage import LexoStorage


def _assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def _assert_true(value: bool, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value")


def _import_payload(text: str) -> tuple[LexoStorage, str, dict]:
    temp_dir = tempfile.TemporaryDirectory()
    storage = LexoStorage(Path(temp_dir.name))
    status = storage.import_book_text(title="regression", source_text=text)
    payload = storage.get_paragraphs(status["id"])
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]
    return storage, status["id"], payload


def _segments(storage: LexoStorage, book_id: str) -> list[dict]:
    with storage._connect() as conn:
        rows = conn.execute(
            """
            SELECT source_text, target_text, segment_type, translation_kind
            FROM segments
            WHERE book_id = ?
            ORDER BY rowid
            """,
            (book_id,),
        ).fetchall()
    return [dict(row) for row in rows]


def _find_word(payload: dict, text: str, occurrence: int = 0) -> dict:
    matches = [
        word
        for paragraph in payload["paragraphs"]
        for word in paragraph["words"]
        if str(word.get("text") or "") == text
    ]
    if occurrence >= len(matches):
        raise AssertionError(f'word "{text}" occurrence {occurrence} not found')
    return matches[occurrence]


def _check_heading_title() -> None:
    storage, book_id, _payload = _import_payload("The Sunny Morning")
    items = _segments(storage, book_id)
    _assert_equal(len(items), 1, "heading_title segment count")
    _assert_equal(items[0]["segment_type"], "heading_title", "heading_title type")
    _assert_equal(items[0]["target_text"], "Солнечное утро", "heading_title translation")
    _assert_equal(items[0]["translation_kind"], "rule_exact", "heading_title translation_kind")


def _check_heading_chapter_word_number() -> None:
    storage, book_id, _payload = _import_payload("Chapter one.")
    items = _segments(storage, book_id)
    _assert_equal(len(items), 1, "heading_chapter word-number segment count")
    _assert_equal(items[0]["segment_type"], "heading_chapter", "heading_chapter word-number type")
    _assert_equal(items[0]["target_text"], "Глава 1", "heading_chapter word-number translation")
    _assert_equal(items[0]["translation_kind"], "rule_exact", "heading_chapter word-number translation_kind")


def _check_chapter_inline_time_split() -> None:
    storage, book_id, _payload = _import_payload("Chapter 3: The Park At 10:00 AM, Tom goes to the park")
    items = _segments(storage, book_id)
    _assert_equal(
        [item["segment_type"] for item in items],
        ["heading_chapter", "time_phrase", "simple_action"],
        "chapter inline time segment types",
    )
    _assert_equal(items[0]["target_text"], "Глава 3: Парк", "chapter inline time heading translation")
    _assert_equal(items[1]["target_text"], "в 10:00 утра", "chapter inline time time translation")
    _assert_equal(items[0]["translation_kind"], "rule_exact", "chapter inline time heading translation_kind")
    _assert_equal(items[1]["translation_kind"], "rule_exact", "chapter inline time time translation_kind")


def _check_time_phrase_rule() -> None:
    storage, book_id, _payload = _import_payload("In the afternoon, Tom goes home.")
    items = _segments(storage, book_id)
    _assert_equal(items[0]["segment_type"], "time_phrase", "afternoon time segment type")
    _assert_equal(items[0]["target_text"], "Днем", "afternoon time translation")
    _assert_equal(items[0]["translation_kind"], "rule_exact", "afternoon time translation_kind")


def _check_good_morning_detail_phrase() -> None:
    storage, book_id, payload = _import_payload('"Good morning, Luna!" Tom says.')
    word = _find_word(payload, "Good")
    detail = storage.get_detail_sheet(book_id, word["id"])
    _assert_equal(detail["rule_id"], "good_morning_greeting", "good morning detail rule_id")
    _assert_equal(detail["rule_type"], "phrase", "good morning detail rule_type")
    _assert_equal(int(detail["is_phrase_member"]), 1, "good morning detail phrase flag")
    _assert_equal(len(detail["units"]), 1, "good morning detail unit count")
    _assert_equal(detail["units"][0]["type"], "PHRASE", "good morning detail unit type")
    _assert_equal(detail["units"][0]["translation"], "доброе утро", "good morning detail unit translation")


def _check_article_grammar_detail() -> None:
    storage, book_id, payload = _import_payload("The sun is bright.")
    word = _find_word(payload, "The")
    _assert_equal(word["quality_state"], "grammar_only", "article word quality_state")
    _assert_equal(int(word["is_grammar_only"]), 1, "article word grammar flag")
    detail = storage.get_detail_sheet(book_id, word["id"])
    _assert_equal(detail["quality_state"], "grammar_only", "article detail quality_state")
    _assert_true("конкретный объект" in str(detail["grammar_hint"]), "article detail grammar hint")
    _assert_equal(detail["units"][0]["type"], "GRAMMAR", "article detail first unit type")


def _check_it_be_detail() -> None:
    storage, book_id, payload = _import_payload("It is a beautiful day.")
    word = _find_word(payload, "It")
    _assert_equal(word["rule_id"], "it_be", "it_be word rule_id")
    _assert_equal(word["rule_type"], "grammar", "it_be word rule_type")
    detail = storage.get_detail_sheet(book_id, word["id"])
    _assert_equal(detail["sheet_source_text"], "It is", "it_be detail sheet_source_text")
    _assert_equal(detail["rule_id"], "it_be", "it_be detail rule_id")
    _assert_equal(len(detail["units"]), 2, "it_be detail units count")
    _assert_equal(detail["units"][0]["type"], "GRAMMAR", "it_be first unit type")
    _assert_equal(detail["units"][0]["translation"], "это / оно", "it_be first unit translation")


def _check_untranslated_eggs() -> None:
    storage, book_id, payload = _import_payload("He eats eggs and toast.")
    word = _find_word(payload, "eggs")
    _assert_equal(word["translation_kind"], "literal_partial", "eggs translation_kind")
    _assert_equal(word["quality_state"], "untranslated", "eggs quality_state")
    _assert_equal(int(word["is_untranslated"]), 1, "eggs untranslated flag")
    detail = storage.get_detail_sheet(book_id, word["id"])
    _assert_equal(detail["quality_state"], "untranslated", "eggs detail quality_state")
    _assert_equal(detail["units"][0]["translation"], "eggs", "eggs detail translation")


def _check_untranslated_flowers_trees() -> None:
    storage, book_id, payload = _import_payload("He sees a big garden with red flowers and green trees.")
    flowers = _find_word(payload, "flowers")
    trees = _find_word(payload, "trees")
    _assert_equal(flowers["quality_state"], "untranslated", "flowers quality_state")
    _assert_equal(trees["quality_state"], "untranslated", "trees quality_state")
    _assert_equal(int(flowers["is_untranslated"]), 1, "flowers untranslated flag")
    _assert_equal(int(trees["is_untranslated"]), 1, "trees untranslated flag")


def _check_quality_fields_present() -> None:
    storage, _book_id, payload = _import_payload("The sun is bright. He eats eggs and toast.")
    word = _find_word(payload, "eggs")
    required_fields = {
        "translation_kind",
        "alignment_kind",
        "matched_by",
        "quality_state",
        "is_untranslated",
        "is_inherited",
        "is_grammar_only",
        "is_phrase_member",
        "direct_meaning_text",
    }
    _assert_equal(required_fields.issubset(set(word.keys())), True, "reader payload quality fields present")


def _check_target_tokens_storage() -> None:
    storage, book_id, _payload = _import_payload("Chapter 3: The Park At 10:00 AM, Tom goes to the park")
    with storage._connect() as conn:
        rows = conn.execute(
            """
            SELECT surface_text
            FROM target_tokens
            WHERE book_id = ?
            ORDER BY rowid
            """,
            (book_id,),
        ).fetchall()
    tokens = [str(row["surface_text"]) for row in rows]
    _assert_true("Глава" in tokens, "target_tokens contains heading token")
    _assert_true("10" in tokens or "10:00" in tokens, "target_tokens contains time token")
    _assert_true("парк" in tokens, "target_tokens contains lexical token")


def _check_mobile_detail_manifest() -> None:
    storage, book_id, _payload = _import_payload('"Good morning, Luna!" Tom says.')
    package = storage.build_mobile_book_package(book_id)
    detail_manifest = package.get("detail_manifest") or {}
    _assert_true(bool(detail_manifest), "mobile detail_manifest exists")
    first_payload = next(iter(detail_manifest.values()))
    _assert_equal(first_payload["rule_type"], "phrase", "mobile detail_manifest rule_type")
    _assert_equal(len(first_payload["units"]), 1, "mobile detail_manifest units count")
    _assert_equal(first_payload["units"][0]["type"], "PHRASE", "mobile detail_manifest phrase unit")


def main() -> None:
    checks = [
        ("heading_title", _check_heading_title),
        ("heading_chapter_word_number", _check_heading_chapter_word_number),
        ("chapter_inline_time_split", _check_chapter_inline_time_split),
        ("time_phrase_rule", _check_time_phrase_rule),
        ("good_morning_detail_phrase", _check_good_morning_detail_phrase),
        ("article_grammar_detail", _check_article_grammar_detail),
        ("it_be_detail", _check_it_be_detail),
        ("untranslated_eggs", _check_untranslated_eggs),
        ("untranslated_flowers_trees", _check_untranslated_flowers_trees),
        ("quality_fields_present", _check_quality_fields_present),
        ("target_tokens_storage", _check_target_tokens_storage),
        ("mobile_detail_manifest", _check_mobile_detail_manifest),
    ]

    for name, check in checks:
        check()
        print(f"PASS {name}")


if __name__ == "__main__":
    main()
