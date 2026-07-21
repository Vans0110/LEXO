from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from engine.context_dictionary_resolver import (
    VIRGIL_DICTIONARY_SOURCE,
    ContextDictionaryResolver,
)


class FakeTranslator:
    def __init__(self, translations: list[str]) -> None:
        self.translations = translations
        self.calls: list[tuple[str, int]] = []

    def translate_alternatives(
        self,
        text: str,
        max_alternatives: int = 10,
    ) -> list[str]:
        self.calls.append((text, max_alternatives))
        return self.translations[:max_alternatives]


class ContextDictionaryFallbackTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.core_path = (
            self.root
            / "data"
            / "dictionaries"
            / "virgil_core"
            / "virgil_core_dictionary.json"
        )
        self.core_path.parent.mkdir(parents=True)
        self.core_path.write_text(
            json.dumps(
                {
                    "math|NOUN": {
                        "word": "math",
                        "pos": "NOUN",
                        "translations": {
                            "ru": ["математика"],
                            "uk": ["математика"],
                        },
                    },
                    "voice|NOUN": {
                        "word": "voice",
                        "pos": "NOUN",
                        "translations": {
                            "ru": ["голос"],
                        },
                    },
                    "classroom|NOUN": {
                        "word": "classroom",
                        "pos": "NOUN",
                        "translations": {
                            "ru": ["класс", "классная комната"],
                            "uk": ["клас", "класна кімната"],
                        },
                    },
                    "hill|PROPN": {
                        "word": "hill",
                        "pos": "PROPN",
                        "translations": {
                            "ru": ["Хилл"],
                            "uk": ["Гілл"],
                        },
                    },
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        self.resolver = ContextDictionaryResolver(self.root)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_reads_ru_translation_from_virgil_core(self) -> None:
        entry = self.resolver.build_entry(
            surface="Math",
            lemma="math",
            pos="NOUN",
            target_lang="ru",
        )

        self.assertEqual(entry["dictionary_key"], "math|NOUN")
        self.assertEqual(entry["translations"], ["математика"])
        self.assertEqual(entry["entries"][0]["source"], VIRGIL_DICTIONARY_SOURCE)
        self.assertFalse(entry["mt_generated"])

    def test_reads_uk_translation_from_virgil_core(self) -> None:
        entry = self.resolver.build_entry(
            surface="math",
            lemma="math",
            pos="NOUN",
            target_lang="uk",
        )

        self.assertEqual(entry["translations"], ["математика"])
        self.assertEqual(entry["target_lang"], "uk")

    def test_title_propn_does_not_alias_to_lexical_article(self) -> None:
        entry = self.resolver.build_entry(
            surface="Classroom",
            lemma="classroom",
            pos="PROPN",
            target_lang="ru",
        )

        self.assertEqual(entry["dictionary_key"], "classroom|PROPN")
        self.assertEqual(entry["translations"], [])

    def test_real_propn_keeps_proper_name_article(self) -> None:
        entry = self.resolver.build_entry(
            surface="Hill",
            lemma="hill",
            pos="PROPN",
            target_lang="ru",
        )

        self.assertEqual(entry["translations"], ["Хилл"])

    def test_missing_language_returns_empty_entry_without_fallback(self) -> None:
        entry = self.resolver.build_entry(
            surface="voice",
            lemma="voice",
            pos="NOUN",
            target_lang="uk",
        )

        self.assertEqual(entry["dictionary_key"], "voice|NOUN")
        self.assertEqual(entry["translations"], [])
        self.assertEqual(entry["entries"], [])
        self.assertFalse(entry["word_found"])
        self.assertFalse(entry["mt_generated"])

    def test_missing_word_does_not_call_mt(self) -> None:
        translator = FakeTranslator(["машинный перевод"])
        resolver = ContextDictionaryResolver(
            self.root,
            mt_translators={"ru": translator},
        )

        entry = resolver.build_entry(
            surface="missing",
            lemma="missing",
            pos="NOUN",
            target_lang="ru",
        )

        self.assertEqual(entry["translations"], [])
        self.assertEqual(entry["entries"], [])
        self.assertEqual(translator.calls, [])


if __name__ == "__main__":
    unittest.main()
