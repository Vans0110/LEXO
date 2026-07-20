from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from engine.context_dictionary_resolver import ContextDictionaryResolver
from engine.library_dictionary import (
    LIBRARY_DICTIONARY_SOURCE,
    LibraryDictionaryStore,
)


class LibraryDictionaryStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.store = LibraryDictionaryStore(self.root)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_writes_book_layer_and_merges_words_and_blocks(self) -> None:
        payload = {
            "version": 1,
            "book_id": "book_demo",
            "target_lang": "ru",
            "parallel": [
                {
                    "source": "Daniel walks into Room twelve.",
                    "translation": "Даниэль входит в кабинет номер двенадцать.",
                }
            ],
            "blocks": [
                {
                    "source": "walks into",
                    "translation": "входит",
                    "type": "phrasal_verb",
                    "explanation": "Describes entering an enclosed place on foot.",
                    "components": [
                        {
                            "source": "walks",
                            "lemma": "walk",
                            "pos": "VERB",
                            "translation": "входит",
                        },
                        {
                            "source": "into",
                            "lemma": "into",
                            "pos": "ADP",
                            "translation": "в",
                        },
                    ],
                },
            ],
            "words": [
                {
                    "word": "walks",
                    "lemma": "walk",
                    "pos": "VERB",
                    "translation": "идти",
                },
                {
                    "word": "Room",
                    "lemma": "room",
                    "pos": "NOUN",
                    "translation": "кабинет",
                },
            ],
        }

        layer_path = self.store.write_book_layer(payload)
        first_merge = self.store.merge_book_layer(payload)
        second_merge = self.store.merge_book_layer(payload)

        self.assertTrue(layer_path.exists())
        self.assertEqual(first_merge["words_added"], 2)
        self.assertEqual(first_merge["blocks_added"], 1)
        self.assertEqual(second_merge["words_added"], 0)
        self.assertEqual(second_merge["blocks_added"], 0)

        words = json.loads(self.store.global_words_path.read_text(encoding="utf-8"))
        blocks = json.loads(self.store.global_blocks_path.read_text(encoding="utf-8"))
        self.assertEqual(words["walk|VERB"]["translations"], ["идти"])
        self.assertEqual(words["room|NOUN"]["translations"], ["кабинет"])
        self.assertEqual(
            words["room|NOUN"]["variants"],
            [
                {
                    "translation": "кабинет",
                    "book_ids": ["book_demo"],
                    "source_forms": ["Room"],
                }
            ],
        )
        self.assertEqual(blocks["walks into"]["translations"], ["входит"])
        self.assertEqual(blocks["walks into"]["variants"][0]["book_ids"], ["book_demo"])
        self.assertEqual(
            [item["translation"] for item in blocks["walks into"]["components"]],
            ["входит", "в"],
        )

    def test_merges_contextual_forms_with_book_provenance(self) -> None:
        self.store.merge_book_layer(
            {
                "book_id": "book_context",
                "target_lang": "ru",
                "words": [
                    {
                        "word": "English",
                        "lemma": "english",
                        "pos": "ADJ",
                        "translation": "английский",
                        "translations": ["английский", "английского"],
                    }
                ],
                "blocks": [],
            }
        )
        record = json.loads(
            self.store.global_words_path.read_text(encoding="utf-8")
        )["english|ADJ"]
        self.assertEqual(record["translations"], ["английский", "английского"])
        self.assertEqual(
            [variant["book_ids"] for variant in record["variants"]],
            [["book_context"], ["book_context"]],
        )
        self.assertTrue(
            all(variant["source_forms"] == ["English"] for variant in record["variants"])
        )
    def test_context_resolver_prefers_library_dictionary_for_ru(self) -> None:
        self.store.merge_book_layer(
            {
                "words": [
                    {
                        "word": "walks",
                        "lemma": "walk",
                        "pos": "VERB",
                        "translation": "идти",
                    }
                ],
                "blocks": [],
            }
        )
        core_path = (
            self.root
            / "data"
            / "dictionaries"
            / "virgil_core"
            / "virgil_core_dictionary.json"
        )
        core_path.parent.mkdir(parents=True)
        core_path.write_text(
            json.dumps(
                {
                    "walk|VERB": {
                        "word": "walk",
                        "pos": "VERB",
                        "translations": {"ru": ["ходить"]},
                    }
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

        entry = ContextDictionaryResolver(self.root).build_entry(
            surface="walks",
            lemma="walk",
            pos="VERB",
            target_lang="ru",
        )

        self.assertEqual(entry["translations"], ["идти"])
        self.assertEqual(entry["entries"][0]["source"], LIBRARY_DICTIONARY_SOURCE)


if __name__ == "__main__":
    unittest.main()
