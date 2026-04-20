from __future__ import annotations

import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from engine.storage import LexoStorage
from engine.translator import MockProvider, TranslationProvider


def _assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def _assert_true(value: bool, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value")


def _import_payload(
    text: str,
    *,
    translator: TranslationProvider | None = None,
    storage_cls: type[LexoStorage] = LexoStorage,
) -> tuple[LexoStorage, str, dict]:
    temp_dir = tempfile.TemporaryDirectory()
    storage = storage_cls(Path(temp_dir.name), translator=translator or MockProvider())
    status = storage.import_book_text(title="regression", source_text=text)
    payload = storage.get_paragraphs(status["id"])
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]
    return storage, status["id"], payload


def _segments(storage: LexoStorage, book_id: str) -> list[dict]:
    with storage._connect() as conn:
        rows = conn.execute(
            """
            SELECT source_text, target_text, segment_type, translation_kind,
                   quality_score, semantic_score, ru_quality_score, quality_status, decision_status,
                   quality_flags, ru_quality_flags, retry_reason_flags, winner_reason, candidate_count, back_translation,
                   source_entities_json, back_entities_json, entity_preservation_score, entity_flags,
                   source_frame_json, back_frame_json, frame_preservation_score, frame_flags,
                   source_verb_frame_json, back_verb_frame_json, verb_score, verb_flags,
                   translation_attempt_count, provider_used, alignment_confidence
            FROM segments
            WHERE book_id = ?
            ORDER BY rowid
            """,
            (book_id,),
        ).fetchall()
    return [dict(row) for row in rows]


def _alignment_count(storage: LexoStorage, book_id: str) -> int:
    with storage._connect() as conn:
        row = conn.execute(
            """
            SELECT COUNT(*) AS count
            FROM word_alignments
            WHERE source_word_id IN (
                SELECT id FROM source_words WHERE book_id = ?
            )
            """,
            (book_id,),
        ).fetchone()
    return int(row["count"]) if row is not None else 0


class _StaticProvider(TranslationProvider):
    model_name = "static-provider"

    def __init__(self, mapping: dict[str, str]) -> None:
        self._mapping = mapping

    def translate_segments(
        self,
        segments: list[str],
        source_lang: str,
        target_lang: str,
    ) -> list[str]:
        return [self._mapping.get(segment, f"[{target_lang}] {segment}") for segment in segments]


class _StorageWithQaFallback(LexoStorage):
    def __init__(
        self,
        *args,
        qa_fallback_providers: list[TranslationProvider] | None = None,
        back_translation_provider: TranslationProvider | None = None,
        **kwargs,
    ) -> None:
        super().__init__(*args, **kwargs)
        self._qa_fallback_providers_override = qa_fallback_providers or []
        self._back_translation_provider_override = back_translation_provider

    def _iter_qa_fallback_providers(self):
        yield from self._qa_fallback_providers_override

    def _get_back_translation_provider(self, *, source_lang: str, target_lang: str):
        if self._back_translation_provider_override is not None:
            return self._back_translation_provider_override
        return super()._get_back_translation_provider(source_lang=source_lang, target_lang=target_lang)


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
    storage, book_id, _payload = _import_payload(
        "The Sunny Morning",
        translator=_StaticProvider({"The Sunny Morning": "Солнечное утро"}),
    )
    items = _segments(storage, book_id)
    _assert_equal(len(items), 1, "heading_title segment count")
    _assert_equal(items[0]["segment_type"], "heading_title", "heading_title type")
    _assert_equal(items[0]["target_text"], "Солнечное утро", "heading_title translation")
    _assert_equal(items[0]["translation_kind"], "provider_fallback", "heading_title translation_kind")


def _check_paragraph_split_preserves_heading_boundaries() -> None:
    text = (
        "The Sunny Morning\n"
        "Chapter 1: The New Day\n"
        "Tom wakes up at 7:00 AM. The sun is bright.\n\n"
        "Chapter 2: Breakfast\n"
        "Tom makes breakfast."
    )
    storage, _book_id, payload = _import_payload(
        text,
        translator=_StaticProvider(
            {
                "The Sunny Morning": "Солнечное утро",
                "The New Day": "Новый день",
                "Breakfast": "Завтрак",
                "Tom wakes up at 7:00 AM.": "Том просыпается в 7:00 утра.",
                "The sun is bright.": "Солнце яркое.",
                "Tom makes breakfast.": "Том готовит завтрак.",
            }
        ),
    )
    paragraphs = payload["paragraphs"]
    _assert_equal(len(paragraphs), 5, "heading boundary paragraph count")
    _assert_equal(paragraphs[0]["source_text"], "The Sunny Morning", "heading boundary title source")
    _assert_equal(paragraphs[0]["target_text"], "Солнечное утро", "heading boundary title target")
    _assert_equal(paragraphs[1]["source_text"], "Chapter 1: The New Day", "heading boundary chapter source")
    _assert_equal(paragraphs[1]["target_text"], "Глава 1: Новый день", "heading boundary chapter target")
    _assert_equal(
        paragraphs[2]["target_text"],
        "Том просыпается в 7:00 утра. Солнце яркое.",
        "heading boundary body target",
    )
    _assert_equal(paragraphs[3]["target_text"], "Глава 2: Завтрак", "heading boundary second chapter target")
    _assert_equal(paragraphs[4]["target_text"], "Том готовит завтрак.", "heading boundary second body target")


def _check_heading_chapter_word_number() -> None:
    storage, book_id, _payload = _import_payload(
        "Chapter one.",
        translator=_StaticProvider({"Chapter one.": "Глава 1"}),
    )
    items = _segments(storage, book_id)
    _assert_equal(len(items), 1, "heading_chapter word-number segment count")
    _assert_equal(items[0]["segment_type"], "heading_chapter", "heading_chapter word-number type")
    _assert_equal(items[0]["target_text"], "Глава 1", "heading_chapter word-number translation")
    _assert_equal(items[0]["translation_kind"], "rule_exact", "heading_chapter word-number translation_kind")


def _check_chapter_inline_time_split() -> None:
    storage, book_id, _payload = _import_payload(
        "Chapter 3: The Park At 10:00 AM, Tom goes to the park",
        translator=_StaticProvider(
            {
                "The Park": "Парк",
                "Tom goes to the park": "Том идет в парк",
            }
        ),
    )
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
    storage, book_id, _payload = _import_payload(
        "In the afternoon, Tom goes home.",
        translator=_StaticProvider({"Tom goes home.": "Том идет домой."}),
    )
    items = _segments(storage, book_id)
    _assert_equal(items[0]["segment_type"], "time_phrase", "afternoon time segment type")
    _assert_equal(items[0]["target_text"], "Днем", "afternoon time translation")
    _assert_equal(items[0]["translation_kind"], "rule_exact", "afternoon time translation_kind")


def _check_good_morning_detail_phrase() -> None:
    storage, book_id, payload = _import_payload('"Good morning, Luna!" Tom says.')
    word = _find_word(payload, "Good")
    detail = storage.get_detail_sheet(book_id, word["id"])
    _assert_equal(detail["sheet_source_text"], "Good", "good morning detail source text")
    _assert_equal(detail["quality_state"], "aligned", "good morning detail quality_state")
    _assert_equal(len(detail["units"]), 1, "good morning detail unit count")
    _assert_equal(detail["units"][0]["type"], "LEXICAL", "good morning detail unit type")
    _assert_equal(detail["units"][0]["surface_text"], "Good", "good morning detail unit surface_text")


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
    _assert_equal(detail["units"][1]["type"], "GRAMMAR", "it_be second unit type")


def _check_untranslated_eggs() -> None:
    storage, book_id, payload = _import_payload("He eats eggs and toast.")
    word = _find_word(payload, "eggs")
    _assert_equal(word["translation_kind"], "provider_fallback", "eggs translation_kind")
    _assert_equal(word["quality_state"], "aligned", "eggs quality_state")
    _assert_equal(int(word["is_untranslated"]), 0, "eggs untranslated flag")
    detail = storage.get_detail_sheet(book_id, word["id"])
    _assert_equal(detail["quality_state"], "aligned", "eggs detail quality_state")
    _assert_equal(detail["units"][0]["translation"], "", "eggs detail translation")


def _check_untranslated_flowers_trees() -> None:
    storage, book_id, payload = _import_payload("He sees a big garden with red flowers and green trees.")
    flowers = _find_word(payload, "flowers")
    trees = _find_word(payload, "trees")
    _assert_equal(flowers["quality_state"], "aligned", "flowers quality_state")
    _assert_equal(trees["quality_state"], "aligned", "trees quality_state")
    _assert_equal(int(flowers["is_untranslated"]), 0, "flowers untranslated flag")
    _assert_equal(int(trees["is_untranslated"]), 0, "trees untranslated flag")


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
    storage, book_id, _payload = _import_payload(
        "Chapter 3: The Park At 10:00 AM, Tom goes to the park",
        translator=_StaticProvider(
            {
                "The Park": "Парк",
                "Tom goes to the park": "Том идет в парк",
            }
        ),
    )
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
    _assert_equal(first_payload["quality_state"], "aligned", "mobile detail_manifest quality_state")
    _assert_equal(len(first_payload["units"]), 1, "mobile detail_manifest units count")
    _assert_equal(first_payload["units"][0]["type"], "LEXICAL", "mobile detail_manifest unit type")


def _check_segment_quality_fields_persisted() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tiny title": "Короткий заголовок"}),
        back_translation_provider=_StaticProvider({"Короткий заголовок": "Short title"}),
    )
    status = storage.import_book_text(title="regression", source_text="Tiny title")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["quality_status"], "pass", "segment quality_status")
    _assert_equal(int(items[0]["quality_score"]) >= 80, True, "segment quality_score")
    _assert_equal(float(items[0]["semantic_score"]) > 0.0, True, "segment semantic_score")
    _assert_equal(float(items[0]["ru_quality_score"]) > 0.0, True, "segment ru_quality_score")
    _assert_equal(items[0]["quality_flags"], "[]", "segment quality_flags")
    _assert_equal(items[0]["ru_quality_flags"], "[]", "segment ru_quality_flags")
    _assert_equal(items[0]["retry_reason_flags"], "[]", "segment retry_reason_flags")
    _assert_equal(items[0]["decision_status"], "accept", "segment decision_status")
    _assert_equal(items[0]["winner_reason"], "accepted_base_candidate", "segment winner_reason")
    _assert_equal(int(items[0]["candidate_count"]), 1, "segment candidate_count")
    _assert_equal(items[0]["back_translation"], "Short title", "segment back_translation")
    _assert_equal(float(items[0]["entity_preservation_score"]) > 0.0, True, "segment entity_preservation_score")
    _assert_equal(items[0]["entity_flags"], "[]", "segment entity_flags")
    _assert_equal(float(items[0]["frame_preservation_score"]) > 0.0, True, "segment frame_preservation_score")
    _assert_equal(items[0]["frame_flags"], "[]", "segment frame_flags")
    _assert_equal(float(items[0]["verb_score"]) > 0.0, True, "segment verb_score")
    _assert_equal(items[0]["verb_flags"], "[]", "segment verb_flags")
    _assert_equal(int(items[0]["translation_attempt_count"]), 1, "segment translation_attempt_count")
    _assert_equal(items[0]["provider_used"], "static-provider", "segment provider_used")
    _assert_equal(float(items[0]["alignment_confidence"]), 1.0, "segment alignment_confidence")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_segment_quality_fallback_selects_better_translation() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tiny title": "Tiny title Tiny title Tiny title Tiny title"}),
        qa_fallback_providers=[_StaticProvider({"Tiny title": "Короткий заголовок"})],
        back_translation_provider=_StaticProvider(
            {
                "Tiny title Tiny title Tiny title Tiny title": "tiny title tiny title tiny title tiny title",
                "Короткий заголовок": "Short title",
            }
        ),
    )
    status = storage.import_book_text(title="regression", source_text="Tiny title")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Короткий заголовок", "qa fallback target_text")
    _assert_equal(items[0]["quality_status"], "pass", "qa fallback quality_status")
    _assert_equal(int(items[0]["translation_attempt_count"]), 2, "qa fallback translation_attempt_count")
    _assert_equal(items[0]["winner_reason"], "fallback_candidate_won", "qa fallback winner_reason")
    _assert_equal(int(items[0]["candidate_count"]), 2, "qa fallback candidate_count")
    _assert_equal(items[0]["provider_used"], "static-provider", "qa fallback provider_used")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_failed_segment_skips_alignment() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tiny title": "Tiny title Tiny title Tiny title Tiny title"}),
        qa_fallback_providers=[],
        back_translation_provider=_StaticProvider({"Tiny title Tiny title Tiny title Tiny title": "Wrong repeated title"}),
    )
    status = storage.import_book_text(title="regression", source_text="Tiny title")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["quality_status"], "fail", "qa failed quality_status")
    _assert_equal(_alignment_count(storage, status["id"]), 0, "qa failed alignment count")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_semantic_drift_flagged_by_back_translation() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom goes home.": "Том едет домой."}),
        qa_fallback_providers=[],
        back_translation_provider=_StaticProvider({"Том едет домой.": "Tom drives to school."}),
    )
    status = storage.import_book_text(title="regression", source_text="Tom goes home.")
    items = _segments(storage, status["id"])
    _assert_true("semantic_drift" in str(items[0]["quality_flags"]), "semantic drift flag present")
    _assert_equal(items[0]["back_translation"], "Tom drives to school.", "semantic drift back_translation")
    _assert_equal(float(items[0]["semantic_score"]) < 0.45, True, "semantic drift semantic_score")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_suspicious_verb_choice_flagged() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom says hello.": "Том машет привет."}),
        qa_fallback_providers=[],
        back_translation_provider=_StaticProvider({"Том машет привет.": "Tom waves hello."}),
    )
    status = storage.import_book_text(title="regression", source_text="Tom says hello.")
    items = _segments(storage, status["id"])
    _assert_true("suspicious_verb_choice" in str(items[0]["quality_flags"]), "suspicious verb choice flag present")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_bad_short_segment_flagged() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tiny Title": "Это title chapter phrase text для странного заголовка"}),
        qa_fallback_providers=[],
        back_translation_provider=_StaticProvider(
            {"Это title chapter phrase text для странного заголовка": "This is some strange chapter title phrase text"}
        ),
    )
    status = storage.import_book_text(title="regression", source_text="Tiny Title")
    items = _segments(storage, status["id"])
    _assert_true("bad_short_segment" in str(items[0]["quality_flags"]), "bad short segment flag present")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_entity_demoted_to_common_noun_flagged() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Luna is small and grey.": "Луна маленькая и серая."}),
        back_translation_provider=_StaticProvider({"Луна маленькая и серая.": "The moon is small and gray."}),
    )
    status = storage.import_book_text(title="regression", source_text="Luna is small and grey.")
    items = _segments(storage, status["id"])
    _assert_true("entity_demoted_to_common_noun" in str(items[0]["quality_flags"]), "entity demotion in quality_flags")
    _assert_true("entity_demoted_to_common_noun" in str(items[0]["entity_flags"]), "entity demotion in entity_flags")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_frame_habitual_vs_event_drift_flagged() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom goes to the park.": "Том ходит в парк."}),
        back_translation_provider=_StaticProvider({"Том ходит в парк.": "Tom usually goes to the park."}),
    )
    status = storage.import_book_text(title="regression", source_text="Tom goes to the park.")
    items = _segments(storage, status["id"])
    _assert_true("habitual_vs_event_drift" in str(items[0]["quality_flags"]), "habitual drift in quality_flags")
    _assert_true("habitual_vs_event_drift" in str(items[0]["frame_flags"]), "habitual drift in frame_flags")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_frame_possessive_relation_lost_flagged() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Luna sleeps on his legs.": "Луна спит на ногах."}),
        back_translation_provider=_StaticProvider({"Луна спит на ногах.": "Luna sleeps on legs."}),
    )
    status = storage.import_book_text(title="regression", source_text="Luna sleeps on his legs.")
    items = _segments(storage, status["id"])
    _assert_true("possessive_relation_lost" in str(items[0]["quality_flags"]), "possessive loss in quality_flags")
    _assert_true("possessive_relation_lost" in str(items[0]["frame_flags"]), "possessive loss in frame_flags")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_segment_quality_report_and_log() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tiny Title": "Короткий заголовок"}),
        back_translation_provider=_StaticProvider({"Короткий заголовок": "Short title"}),
    )
    status = storage.import_book_text(title="regression", source_text="Tiny Title")
    report = storage.get_segment_quality_report(status["id"])
    _assert_equal(report["book_id"], status["id"], "segment quality report book_id")
    _assert_equal(int(report["summary"]["segment_count"]), 1, "segment quality report segment_count")
    _assert_equal(int(report["summary"]["decision_counts"]["accept"]), 1, "segment quality report decision accept")
    _assert_equal(int(report["summary"]["retry_required_count"]), 0, "segment quality report retry count")
    _assert_equal(report["segments"][0]["back_translation"], "Short title", "segment quality report back_translation")
    _assert_equal(report["segments"][0]["decision_status"], "accept", "segment quality report decision_status")
    _assert_equal(report["segments"][0]["winner_reason"], "accepted_base_candidate", "segment quality report winner_reason")
    _assert_equal(float(report["segments"][0]["ru_quality_score"]) > 0.0, True, "segment quality report ru score")
    _assert_equal(float(report["segments"][0]["entity_preservation_score"]) > 0.0, True, "segment quality report entity score")
    _assert_equal(float(report["segments"][0]["frame_preservation_score"]) > 0.0, True, "segment quality report frame score")
    _assert_equal(float(report["segments"][0]["verb_score"]) > 0.0, True, "segment quality report verb score")
    log_path = Path(str(report["qa_log_path"]))
    _assert_equal(log_path.exists(), True, "segment quality log exists")
    log_lines = [line for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    _assert_equal(len(log_lines), 1, "segment quality log line count")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_ru_spelling_error_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"He eats eggs and toast.": "Он едит яйца и тосты."}),
        qa_fallback_providers=[_StaticProvider({"He eats eggs and toast.": "Он ест яйца и тосты."})],
        back_translation_provider=_StaticProvider({
            "Он едит яйца и тосты.": "He eats eggs and toast.",
            "Он ест яйца и тосты.": "He eats eggs and toast.",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="He eats eggs and toast.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Он ест яйца и тосты.", "ru spelling retry target_text")
    _assert_equal(items[0]["retry_reason_flags"], "[]", "ru spelling retry cleared")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_ru_spelling_error_without_hardcoded_word() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"He eats soup.": "Он кушаит суп."}),
        qa_fallback_providers=[_StaticProvider({"He eats soup.": "Он кушает суп."})],
        back_translation_provider=_StaticProvider({
            "Он кушаит суп.": "He eats soup.",
            "Он кушает суп.": "He eats soup.",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="He eats soup.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Он кушает суп.", "ru spelling retry no hardcoded word")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_ru_gender_mismatch_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({'"I am great, thank you!" Anna says.': '"Я замечательный, спасибо!" - говорит Анна.'}),
        qa_fallback_providers=[_StaticProvider({'"I am great, thank you!" Anna says.': '"Я замечательная, спасибо!" - говорит Анна.'})],
        back_translation_provider=_StaticProvider({
            '"Я замечательный, спасибо!" - говорит Анна.': '"I am great, thank you!" says Anna.',
            '"Я замечательная, спасибо!" - говорит Анна.': '"I am great, thank you!" says Anna.',
        }),
    )
    status = storage.import_book_text(title="regression", source_text='"I am great, thank you!" Anna says.')
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], '"Я замечательная, спасибо!" - говорит Анна.', "ru gender retry target_text")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_ru_gender_mismatch_without_hardcoded_source_name() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({'"I am great, thank you!" Nora says.': '"Я замечательный, спасибо!" - говорит Нора.'}),
        qa_fallback_providers=[_StaticProvider({'"I am great, thank you!" Nora says.': '"Я замечательная, спасибо!" - говорит Нора.'})],
        back_translation_provider=_StaticProvider({
            '"Я замечательный, спасибо!" - говорит Нора.': '"I am great, thank you!" says Nora.',
            '"Я замечательная, спасибо!" - говорит Нора.': '"I am great, thank you!" says Nora.',
        }),
    )
    status = storage.import_book_text(title="regression", source_text='"I am great, thank you!" Nora says.')
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], '"Я замечательная, спасибо!" - говорит Нора.', "ru gender retry no hardcoded name")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_target_directional_title_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Home": "Домой"}),
        qa_fallback_providers=[_StaticProvider({"Home": "Дом"})],
        back_translation_provider=_StaticProvider({
            "Глава 4: Домой": "Chapter 4: Home is where the heart is.",
            "Глава 4: Дом": "Chapter 4: Home",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="Chapter 4: Home")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Глава 4: Дом", "directional title retry target_text")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_target_possessive_relation_lost_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Luna sleeps on his legs.": "Луна спит на ногах."}),
        qa_fallback_providers=[_StaticProvider({"Luna sleeps on his legs.": "Луна спит у него на ногах."})],
        back_translation_provider=_StaticProvider({
            "Луна спит на ногах.": "Luna sleeps on legs.",
            "Луна спит у него на ногах.": "Luna sleeps on his legs.",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="Luna sleeps on his legs.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Луна спит у него на ногах.", "possessive retry target_text")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_social_relation_possessive_not_flagged() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"In the park, he sees his friend, Anna.": "В парке он видит свою подругу Анну."}),
        back_translation_provider=_StaticProvider({"В парке он видит свою подругу Анну.": "In the park, he sees his friend, Anna."}),
    )
    status = storage.import_book_text(title="regression", source_text="In the park, he sees his friend, Anna.")
    items = _segments(storage, status["id"])
    _assert_true("target_possessive_relation_lost" not in str(items[0]["quality_flags"]), "social relation possessive not in quality_flags")
    _assert_equal(items[0]["quality_status"], "pass", "social relation possessive quality_status")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_rebuild_book_quality_reapplies_current_qa() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"He eats eggs and toast.": "Он ест яйца и тосты."}),
        qa_fallback_providers=[_StaticProvider({"He eats eggs and toast.": "Он ест яйца и тосты."})],
        back_translation_provider=_StaticProvider({"Он ест яйца и тосты.": "He eats eggs and toast."}),
    )
    status = storage.import_book_text(title="regression", source_text="He eats eggs and toast.")
    with storage._connect() as conn:
        conn.execute(
            """
            UPDATE books
            SET current_paragraph_index = ?
            WHERE id = ?
            """,
            (3, status["id"]),
        )
        conn.execute(
            """
            UPDATE paragraphs
            SET target_text = ?
            WHERE book_id = ?
            """,
            ("Он едит яйца и тосты.", status["id"]),
        )
        conn.execute(
            """
            UPDATE segments
            SET target_text = ?, quality_score = ?, semantic_score = ?, ru_quality_score = ?,
                quality_status = ?, quality_flags = ?, ru_quality_flags = ?, retry_reason_flags = ?,
                back_translation = ?
            WHERE book_id = ?
            """,
            (
                "Он едит яйца и тосты.",
                100,
                1.0,
                1.0,
                "pass",
                "[]",
                "[]",
                "[]",
                "He eats eggs and toast.",
                status["id"],
            ),
        )
    rebuilt = storage.rebuild_book_quality(status["id"])
    items = _segments(storage, status["id"])
    _assert_equal(rebuilt["current_paragraph_index"], 3, "rebuild preserves reader position")
    _assert_equal(items[0]["target_text"], "Он ест яйца и тосты.", "rebuild restores current qa translation")
    _assert_equal(items[0]["quality_status"], "pass", "rebuild stores refreshed quality status")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_verb_meaning_narrowing_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom makes breakfast.": "Том готовит завтрак."}),
        qa_fallback_providers=[_StaticProvider({"Tom makes breakfast.": "Том делает завтрак."})],
        back_translation_provider=_StaticProvider({
            "Том готовит завтрак.": "Tom cooks breakfast.",
            "Том делает завтрак.": "Tom makes breakfast.",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="Tom makes breakfast.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Том делает завтрак.", "verb narrowing retry target_text")
    _assert_true("verb_meaning_narrowing" not in str(items[0]["quality_flags"]), "verb narrowing cleared")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_verb_drift_drive_home_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom goes home.": "Том едет домой."}),
        qa_fallback_providers=[_StaticProvider({"Tom goes home.": "Том идет домой."})],
        back_translation_provider=_StaticProvider({
            "Том едет домой.": "Tom drives home.",
            "Том идет домой.": "Tom goes home.",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="Tom goes home.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Том идет домой.", "verb drive retry target_text")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_verb_near_return_home_allowed() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom goes home.": "Том возвращается домой."}),
        back_translation_provider=_StaticProvider({"Том возвращается домой.": "Tom returns home."}),
    )
    status = storage.import_book_text(title="regression", source_text="Tom goes home.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["quality_status"], "pass", "verb near quality_status")
    _assert_true("verb_lemma_drift" not in str(items[0]["quality_flags"]), "verb near no hard drift")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_verb_speech_whisper_triggers_retry() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"Tom says hello.": "Том шепчет привет."}),
        qa_fallback_providers=[_StaticProvider({"Tom says hello.": "Том говорит привет."})],
        back_translation_provider=_StaticProvider({
            "Том шепчет привет.": "Tom whispers hello.",
            "Том говорит привет.": "Tom says hello.",
        }),
    )
    status = storage.import_book_text(title="regression", source_text="Tom says hello.")
    items = _segments(storage, status["id"])
    _assert_equal(items[0]["target_text"], "Том говорит привет.", "verb speech retry target_text")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def _check_single_model_retry_attempts_reach_three() -> None:
    temp_dir = tempfile.TemporaryDirectory()
    storage = _StorageWithQaFallback(
        Path(temp_dir.name),
        translator=_StaticProvider({"He eats eggs and toast.": "Он едит яйца и тосты."}),
        qa_fallback_providers=[],
        back_translation_provider=_StaticProvider({"Он едит яйца и тосты.": "He eats eggs and toast."}),
    )
    status = storage.import_book_text(title="regression", source_text="He eats eggs and toast.")
    items = _segments(storage, status["id"])
    _assert_equal(int(items[0]["candidate_count"]), 3, "single model candidate_count")
    _assert_equal(int(items[0]["translation_attempt_count"]), 3, "single model translation_attempt_count")
    storage._temp_dir = temp_dir  # type: ignore[attr-defined]


def main() -> None:
    checks = [
        ("heading_title", _check_heading_title),
        ("paragraph_split_preserves_heading_boundaries", _check_paragraph_split_preserves_heading_boundaries),
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
        ("segment_quality_fields_persisted", _check_segment_quality_fields_persisted),
        ("segment_quality_fallback_selects_better_translation", _check_segment_quality_fallback_selects_better_translation),
        ("failed_segment_skips_alignment", _check_failed_segment_skips_alignment),
        ("semantic_drift_flagged_by_back_translation", _check_semantic_drift_flagged_by_back_translation),
        ("suspicious_verb_choice_flagged", _check_suspicious_verb_choice_flagged),
        ("bad_short_segment_flagged", _check_bad_short_segment_flagged),
        ("entity_demoted_to_common_noun_flagged", _check_entity_demoted_to_common_noun_flagged),
        ("frame_habitual_vs_event_drift_flagged", _check_frame_habitual_vs_event_drift_flagged),
        ("frame_possessive_relation_lost_flagged", _check_frame_possessive_relation_lost_flagged),
        ("segment_quality_report_and_log", _check_segment_quality_report_and_log),
        ("ru_spelling_error_triggers_retry", _check_ru_spelling_error_triggers_retry),
        ("ru_spelling_error_without_hardcoded_word", _check_ru_spelling_error_without_hardcoded_word),
        ("ru_gender_mismatch_triggers_retry", _check_ru_gender_mismatch_triggers_retry),
        ("ru_gender_mismatch_without_hardcoded_source_name", _check_ru_gender_mismatch_without_hardcoded_source_name),
        ("target_directional_title_triggers_retry", _check_target_directional_title_triggers_retry),
        ("target_possessive_relation_lost_triggers_retry", _check_target_possessive_relation_lost_triggers_retry),
        ("social_relation_possessive_not_flagged", _check_social_relation_possessive_not_flagged),
        ("rebuild_book_quality_reapplies_current_qa", _check_rebuild_book_quality_reapplies_current_qa),
        ("verb_meaning_narrowing_triggers_retry", _check_verb_meaning_narrowing_triggers_retry),
        ("verb_drift_drive_home_triggers_retry", _check_verb_drift_drive_home_triggers_retry),
        ("verb_near_return_home_allowed", _check_verb_near_return_home_allowed),
        ("verb_speech_whisper_triggers_retry", _check_verb_speech_whisper_triggers_retry),
        ("single_model_retry_attempts_reach_three", _check_single_model_retry_attempts_reach_three),
    ]

    for name, check in checks:
        check()
        print(f"PASS {name}")


if __name__ == "__main__":
    main()
