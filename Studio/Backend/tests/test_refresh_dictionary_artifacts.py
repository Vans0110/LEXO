from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from refresh_dictionary_artifacts import _refresh_language


class RefreshDictionaryArtifactsTest(unittest.TestCase):
    def test_absorbed_word_stays_present_without_global_translation(self) -> None:
        reader = {
            "book_id": "book-test",
            "paragraphs": [
                {
                    "words": [
                        {
                            "id": "word-the",
                            "segment_id": "segment-1",
                            "order_index_in_segment": 0,
                            "text": "The",
                            "lemma": "the",
                            "pos": "DET",
                        }
                    ],
                    "segments_v2": [
                        {
                            "id": "segment-1",
                            "source_text": "The room.",
                            "target_text": "Комната.",
                        }
                    ],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            dictionary, alignment = _refresh_language(
                Path(temp_dir),
                lang="ru",
                reader=reader,
                words={"the|DET": {"translations": ["комната"], "variants": []}},
                phrases={},
                absorbed_word_keys={"the|det"},
            )
        self.assertIn("the|DET", dictionary["entries"])
        self.assertEqual([], dictionary["entries"]["the|DET"]["translations"])
        self.assertEqual("", alignment["entries"][0]["translation"])
        self.assertEqual([], alignment["entries"][0]["translations"])

    def test_assigns_each_occurrence_to_unclaimed_contextual_target_span(self) -> None:
        segment_id = "segment-1"
        source_words = [
            ("Her", "her", "PRON"),
            ("English", "english", "ADJ"),
            ("class", "class", "NOUN"),
            ("is", "be", "AUX"),
            ("in", "in", "ADP"),
            ("Room", "room", "PROPN"),
            ("fourteen", "fourteen", "NUM"),
        ]
        reader = {
            "book_id": "book-test",
            "paragraphs": [
                {
                    "words": [
                        {
                            "id": f"word-{index}",
                            "segment_id": segment_id,
                            "order_index_in_segment": index,
                            "text": surface,
                            "lemma": lemma,
                            "pos": pos,
                        }
                        for index, (surface, lemma, pos) in enumerate(source_words)
                    ],
                    "segments_v2": [
                        {
                            "id": segment_id,
                            "source_text": "Her English class is in Room fourteen.",
                            "target_text": (
                                "Её урок английского языка проходит "
                                "в четырнадцатом классе."
                            ),
                        }
                    ],
                }
            ],
        }
        translations = {
            "her|PRON": ["её"],
            "english|ADJ": ["английский", "английского", "английского языка"],
            "class|NOUN": ["класс", "классе", "урок"],
            "be|AUX": ["быть", "проходит"],
            "in|ADP": ["в"],
            "room|PROPN": ["комната", "классе"],
            "fourteen|NUM": ["четырнадцать", "четырнадцатом"],
        }
        words = {
            key: {"translations": values, "variants": []}
            for key, values in translations.items()
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            _, alignment = _refresh_language(
                Path(temp_dir),
                lang="ru",
                reader=reader,
                words=words,
                phrases={},
            )
        selected = {
            entry["surface"]: entry["translation"]
            for entry in alignment["entries"]
        }
        self.assertEqual("английского языка", selected["English"])
        self.assertEqual("урок", selected["class"])
        self.assertEqual("классе", selected["Room"])
        self.assertEqual("четырнадцатом", selected["fourteen"])
        self.assertEqual(7, len(alignment["entries"]))


if __name__ == "__main__":
    unittest.main()
