from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PRODUCTION_FILES = (
    ROOT / "Studio/Backend/engine/storage.py",
    ROOT / "Studio/Backend/engine/virgil_core_dictionary.py",
    ROOT / "Studio/Backend/engine/segment_translation_qa.py",
    ROOT / "Studio/Backend/engine/structural_translation_rerank.py",
    ROOT / "Studio/Backend/engine/dictionary_translation_ranker.py",
    ROOT / "Studio/Backend/engine/tts/tts_text_normalizer.py",
    ROOT / "Studio/Backend/engine/tts/tts_segmenter.py",
    ROOT / "Virgil/App/lib/src/workbench/virgil_workbench_builder.dart",
)

FORBIDDEN_MARKERS = (
    "TITLE_PROPN_ALIASES",
    "ZERO_WEIGHT_SOURCE_WORDS",
    "EXTRA_INTENSIFIERS",
    "EXTRA_PHASE_WORDS",
    "NEGATION_LEMMAS",
    "_ARTICLE_WORDS",
    "_PRONOUN_WORDS",
    "_ADJECTIVE_LIKE_WORDS",
    "_NOUN_LIKE_WORDS",
    "_NUMBER_WORDS",
    "WEAK_ENDINGS",
    "WEAK_STARTS",
    "book_919621151055",
    "book_cad03a8f1779",
    '"иями", "ями", "ами"',
)


class NoHardcodedDictionaryDataTest(unittest.TestCase):
    def test_production_contour_has_no_known_embedded_lexical_tables(self) -> None:
        violations: list[str] = []
        for path in PRODUCTION_FILES:
            content = path.read_text(encoding="utf-8")
            for marker in FORBIDDEN_MARKERS:
                if marker in content:
                    violations.append(f"{path.relative_to(ROOT)}: {marker}")
        self.assertEqual(violations, [])


if __name__ == "__main__":
    unittest.main()
