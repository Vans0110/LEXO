from __future__ import annotations

import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from validate_verification_word_to_word import validate


def fixture() -> tuple[dict, dict]:
    layer = {
        "book_id": "book_test",
        "parallel": [
            {"source": "They sit down.", "translation": "Они садятся."},
        ],
        "words": [
            {
                "word": "They",
                "lemma": "they",
                "pos": "PRON",
                "translation": "они",
                "translations": ["они"],
            },
            {
                "word": "sit",
                "lemma": "sit",
                "pos": "VERB",
                "translation": "садятся",
                "translations": ["садятся"],
            },
            {
                "word": "down",
                "lemma": "down",
                "pos": "PART",
                "translation": "",
                "translations": [],
                "empty_reason": "owned by the construction",
            },
        ],
        "blocks": [
            {
                "source": "sit down",
                "translation": "садятся",
                "source_forms": ["sit down"],
            }
        ],
    }
    proof = {
        "version": 1,
        "book_id": "book_test",
        "source_lang": "en",
        "target_lang": "ru",
        "entries": [
            {
                "word_id": "w0",
                "segment_index": 0,
                "source_order": 0,
                "surface": "They",
                "lemma": "they",
                "pos": "PRON",
                "contextual_translation": "Они",
                "dictionary_translation": "",
                "status": "independent_translation",
                "owner_unit_id": "word:w0",
                "tap_unit_id": "word:w0",
                "target_start_index": 0,
                "target_end_index": 0,
                "empty_reason": "",
            },
            {
                "word_id": "w1",
                "segment_index": 0,
                "source_order": 1,
                "surface": "sit",
                "lemma": "sit",
                "pos": "VERB",
                "contextual_translation": "садятся",
                "dictionary_translation": "",
                "status": "block_component",
                "owner_unit_id": "block:0:1",
                "tap_unit_id": "block:0:1",
                "target_start_index": 1,
                "target_end_index": 1,
                "empty_reason": "",
            },
            {
                "word_id": "w2",
                "segment_index": 0,
                "source_order": 2,
                "surface": "down",
                "lemma": "down",
                "pos": "PART",
                "contextual_translation": "",
                "dictionary_translation": "вниз",
                "status": "block_component",
                "owner_unit_id": "block:0:1",
                "tap_unit_id": "block:0:1",
                "empty_reason": "meaning is owned by the construction",
            },
        ],
        "block_occurrences": [
            {
                "unit_id": "block:0:1",
                "tap_unit_id": "block:0:1",
                "block_source": "sit down",
                "source_form": "sit down",
                "translation": "садятся",
                "segment_index": 0,
                "word_ids": ["w1", "w2"],
            }
        ],
    }
    return layer, proof


def alignment_group_fixture() -> tuple[dict, dict]:
    layer = {
        "book_id": "book_group",
        "parallel": [
            {
                "source": "in the wrong room",
                "translation": "не в той комнате",
            }
        ],
        "words": [
            {"word": "in", "lemma": "in", "pos": "ADP", "translation": "в", "translations": ["в"]},
            {"word": "the", "lemma": "the", "pos": "DET", "translation": "", "translations": [], "empty_reason": "article has no independent target"},
            {"word": "wrong", "lemma": "wrong", "pos": "ADJ", "translation": "", "translations": [], "empty_reason": "meaning is structurally recast", "dictionary_translation": "не той"},
            {"word": "room", "lemma": "room", "pos": "NOUN", "translation": "комнате", "translations": ["комнате"]},
        ],
        "blocks": [],
    }
    proof = {
        "version": 2,
        "book_id": "book_group",
        "source_lang": "en",
        "target_lang": "ru",
        "entries": [
            {"word_id": "w0", "segment_index": 0, "source_order": 0, "surface": "in", "lemma": "in", "pos": "ADP", "contextual_translation": "в", "dictionary_translation": "", "status": "independent_translation", "owner_unit_id": "word:w0", "tap_unit_id": "word:w0", "target_start_index": 1, "target_end_index": 1, "empty_reason": ""},
            {"word_id": "w1", "segment_index": 0, "source_order": 1, "surface": "the", "lemma": "the", "pos": "DET", "contextual_translation": "", "dictionary_translation": "", "status": "zero_correspondence", "owner_unit_id": "word:w1", "tap_unit_id": "word:w1", "empty_reason": "article has no independent target"},
            {"word_id": "w2", "segment_index": 0, "source_order": 2, "surface": "wrong", "lemma": "wrong", "pos": "ADJ", "contextual_translation": "", "dictionary_translation": "не той", "status": "dictionary_fallback", "owner_unit_id": "word:w2", "tap_unit_id": "word:w2", "empty_reason": "meaning is realized by the alignment group"},
            {"word_id": "w3", "segment_index": 0, "source_order": 3, "surface": "room", "lemma": "room", "pos": "NOUN", "contextual_translation": "комнате", "dictionary_translation": "", "status": "independent_translation", "owner_unit_id": "word:w3", "tap_unit_id": "word:w3", "target_start_index": 3, "target_end_index": 3, "empty_reason": ""},
        ],
        "alignment_groups": [
            {
                "unit_id": "alignment_group:0:0",
                "kind": "structural_recast",
                "segment_index": 0,
                "source_word_ids": ["w0", "w1", "w2", "w3"],
                "group_only_word_ids": ["w1", "w2"],
                "source_text": "in the wrong room",
                "target_start_index": 0,
                "target_end_index": 3,
                "target_text": "не в той комнате",
                "reason": "The target expresses the construction only as a whole.",
            }
        ],
        "block_occurrences": [],
        "target_coverage": [],
    }
    return layer, proof


def number_group_fixture() -> tuple[dict, dict]:
    layer = {
        "book_id": "book_number",
        "parallel": [{"source": "Room fourteen", "translation": "комнате номер четырнадцать"}],
        "words": [
            {"word": "Room", "lemma": "room", "pos": "PROPN", "translation": "комнате", "translations": ["комнате"]},
            {"word": "fourteen", "lemma": "fourteen", "pos": "NUM", "translation": "четырнадцать", "translations": ["четырнадцать"]},
        ],
        "blocks": [],
    }
    proof = {
        "version": 2,
        "book_id": "book_number",
        "source_lang": "en",
        "target_lang": "ru",
        "entries": [
            {"word_id": "n0", "segment_index": 0, "source_order": 0, "surface": "Room", "lemma": "room", "pos": "PROPN", "contextual_translation": "комнате", "dictionary_translation": "", "status": "independent_translation", "owner_unit_id": "word:n0", "tap_unit_id": "word:n0", "target_start_index": 0, "target_end_index": 0, "empty_reason": ""},
            {"word_id": "n1", "segment_index": 0, "source_order": 1, "surface": "fourteen", "lemma": "fourteen", "pos": "NUM", "contextual_translation": "четырнадцать", "dictionary_translation": "", "status": "independent_translation", "owner_unit_id": "word:n1", "tap_unit_id": "word:n1", "target_start_index": 2, "target_end_index": 2, "empty_reason": ""},
        ],
        "alignment_groups": [
            {"unit_id": "alignment_group:0:0", "kind": "structural_recast", "segment_index": 0, "source_word_ids": ["n0", "n1"], "group_only_word_ids": [], "source_text": "Room fourteen", "target_start_index": 0, "target_end_index": 2, "target_text": "комнате номер четырнадцать", "reason": "The target inserts a structural classifier."}
        ],
        "block_occurrences": [],
        "target_coverage": [],
    }
    return layer, proof


class VerificationWordToWordTest(unittest.TestCase):
    def test_accepts_complete_block(self) -> None:
        layer, proof = fixture()
        errors, counts = validate(layer, proof)
        self.assertEqual([], errors)
        self.assertEqual(3, counts["entries"])
        self.assertEqual(1, counts["block_occurrences"])

    def test_rejects_split_block_tap_units(self) -> None:
        layer, proof = fixture()
        proof["entries"][2]["tap_unit_id"] = "word:w2"
        errors, _ = validate(layer, proof)
        self.assertTrue(any("another tap unit" in error for error in errors))

    def test_rejects_missing_occurrence(self) -> None:
        layer, proof = fixture()
        proof["entries"].pop()
        errors, _ = validate(layer, proof)
        self.assertTrue(any("occurrence tokens disagree" in error for error in errors))

    def test_rejects_unresolved(self) -> None:
        layer, proof = fixture()
        proof["entries"][0]["status"] = "unresolved"
        errors, _ = validate(layer, proof)
        self.assertTrue(any("is unresolved" in error for error in errors))

    def test_accepts_structural_alignment_group(self) -> None:
        layer, proof = alignment_group_fixture()
        errors, counts = validate(layer, proof)
        self.assertEqual([], errors)
        self.assertEqual(1, counts["alignment_groups"])

    def test_rejects_false_word_translation_inside_group(self) -> None:
        layer, proof = alignment_group_fixture()
        wrong = proof["entries"][2]
        wrong.update(
            {
                "contextual_translation": "той",
                "dictionary_translation": "",
                "status": "independent_translation",
                "target_start_index": 2,
                "target_end_index": 2,
                "empty_reason": "",
            }
        )
        errors, _ = validate(layer, proof)
        self.assertTrue(any("group-only word w2 claims contextual translation" in error for error in errors))

    def test_rejects_multiword_fallback_outside_group(self) -> None:
        layer, proof = alignment_group_fixture()
        proof["alignment_groups"] = []
        errors, _ = validate(layer, proof)
        self.assertTrue(
            any("multiword dictionary fallback requires group_only_word_ids" in error for error in errors)
        )

    def test_group_covers_structural_number_token(self) -> None:
        layer, proof = number_group_fixture()
        errors, _ = validate(layer, proof)
        self.assertEqual([], errors)

    def test_rejects_alignment_group_as_block(self) -> None:
        layer, proof = alignment_group_fixture()
        layer["blocks"] = [
            {
                "source": "in the wrong room",
                "translation": "не в той комнате",
                "source_forms": ["in the wrong room"],
            }
        ]
        errors, _ = validate(layer, proof)
        self.assertTrue(any("must not duplicate a book block" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
