from __future__ import annotations

import unittest

from engine.source_pos_lemma import SourcePosLemmaAnalyzer
from engine.storage import LexoStorage
from engine.tokenization import TOKEN_RE, WORD_RE
from engine.tts.tts_text_normalizer import build_slow_synthesis_text


class ApostropheTokenizationTest(unittest.TestCase):
    def test_ascii_and_curly_apostrophes_stay_inside_words(self) -> None:
        cases = {
            "Grandma's Dinner": ["Grandma's", "Dinner"],
            "Grandma’s Dinner": ["Grandma’s", "Dinner"],
            "Emma's book": ["Emma's", "book"],
            "Emma’s book": ["Emma’s", "book"],
            "don't stop": ["don't", "stop"],
            "I’m ready": ["I’m", "ready"],
            "seven o’clock": ["seven", "o’clock"],
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(WORD_RE.findall(text), expected)
                self.assertEqual(TOKEN_RE.findall(text), expected)

    def test_possessive_uses_base_name_for_lemma(self) -> None:
        analyzer = SourcePosLemmaAnalyzer()
        if not analyzer.is_available:
            self.skipTest("spaCy English model is not available")

        for surface in ("Emma's", "Emma’s"):
            with self.subTest(surface=surface):
                analysis = analyzer.analyze_words(
                    f"{surface} book is here.",
                    [surface, "book", "is", "here"],
                )
                self.assertEqual(analysis[0].surface_text, surface)
                self.assertEqual(analysis[0].lemma, "emma")
                self.assertEqual(analysis[0].pos, "PROPN")

    def test_reader_keeps_possessive_as_one_tappable_token(self) -> None:
        storage = LexoStorage.__new__(LexoStorage)
        words = [
            {
                "id": "word_1",
                "text": "Grandma’s",
                "tap_unit_id": "word_1",
            },
            {
                "id": "word_2",
                "text": "Dinner",
                "tap_unit_id": "word_2",
            },
        ]

        tokens = storage._build_reader_tokens("Grandma’s Dinner", words)

        self.assertEqual(
            [(token["text"], token["kind"]) for token in tokens],
            [
                ("Grandma’s", "word"),
                (" ", "punctuation"),
                ("Dinner", "word"),
            ],
        )
        self.assertEqual(tokens[0]["tap_unit_id"], "word_1")

    def test_tts_keeps_apostrophe_word_together(self) -> None:
        self.assertEqual(
            build_slow_synthesis_text("Emma’s book", dot_count=2),
            "Emma's.. book..",
        )


if __name__ == "__main__":
    unittest.main()
