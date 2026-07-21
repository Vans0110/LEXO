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
            {"source": "They sit down.", "translation": "Вони сідають."},
        ],
        "words": [
            {
                "word": "They",
                "lemma": "they",
                "pos": "PRON",
                "translation": "вони",
                "translations": ["вони"],
            },
            {
                "word": "sit",
                "lemma": "sit",
                "pos": "VERB",
                "translation": "сідають",
                "translations": ["сідають"],
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
                "translation": "сідають",
                "source_forms": ["sit down"],
            }
        ],
    }
    proof = {
        "version": 1,
        "book_id": "book_test",
        "source_lang": "en",
        "target_lang": "uk",
        "entries": [
            {
                "word_id": "w0",
                "segment_index": 0,
                "source_order": 0,
                "surface": "They",
                "lemma": "they",
                "pos": "PRON",
                "contextual_translation": "Вони",
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
                "contextual_translation": "сідають",
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
                "dictionary_translation": "униз",
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
                "translation": "сідають",
                "segment_index": 0,
                "word_ids": ["w1", "w2"],
            }
        ],
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


if __name__ == "__main__":
    unittest.main()

