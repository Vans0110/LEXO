import unittest
from contextlib import nullcontext

from engine.storage import LexoStorage


class MobilePackageDictionaryManifestTests(unittest.TestCase):
    def test_workbench_dictionary_rebuild_reads_globals_without_writing_layers(self) -> None:
        storage = LexoStorage.__new__(LexoStorage)
        storage._resolve_required_book_id = lambda book_id: str(book_id)
        storage._clear_book_dictionary_cache = lambda book_id: None
        storage._connect = lambda: nullcontext(object())
        storage._rebuild_book_dictionary_entries = (
            lambda conn, book_id, target_lang="ru": 3
        )
        storage._book_dictionary_manifest = lambda book_id, lang="ru": {
            "source": f"library_dictionary_{lang}",
            "entries": {
                "room|NOUN": {"translations": ["комната"]},
                "sit|VERB": {"translations": ["садиться"]},
                "missing|ADJ": {"translations": []},
            },
            "phrase_count": 2,
        }
        storage._build_book_layer_payload = lambda *args, **kwargs: self.fail(
            "Workbench rebuild must not read seed/book-layer payloads"
        )
        storage.library_dictionary_store = type(
            "ForbiddenDictionaryWrites",
            (),
            {
                "write_book_layer": lambda *args, **kwargs: self.fail(
                    "Workbench rebuild must not write book layers"
                ),
                "merge_book_layer": lambda *args, **kwargs: self.fail(
                    "Workbench rebuild must not write Globals"
                ),
            },
        )()

        result = storage.rebuild_book_library_dictionary("book-test", "ru")

        self.assertEqual(3, result["word_count"])
        self.assertEqual(2, result["translated_word_count"])
        self.assertEqual(1, result["missing_word_count"])
        self.assertEqual(2, result["phrase_count"])
        self.assertNotIn("book_layer_path", result)
        self.assertNotIn("global_words_path", result)

    def test_package_includes_ru_and_uk_dictionary_manifests_for_ru_book(self) -> None:
        storage = LexoStorage.__new__(LexoStorage)

        storage.get_paragraphs = lambda book_id: {"book_id": book_id, "paragraphs": []}
        storage.get_book_status = lambda book_id: {
            "id": book_id,
            "title": "A Voice from Online",
            "target_lang": "ru",
        }
        storage._book_dictionary_manifest = lambda book_id, lang="ru": {
            "book_id": book_id,
            "target_lang": lang,
            "entries": {},
        }
        storage._build_mobile_tts_manifest = lambda book_id: {}
        storage._build_mobile_word_audio_manifest = lambda book_id: {}

        package = storage.build_mobile_book_package("book_07a16679df53")

        self.assertEqual(package["dictionary_manifest"]["target_lang"], "ru")
        self.assertEqual(
            sorted(package["dictionary_manifests"].keys()),
            ["ru", "uk"],
        )
        self.assertEqual(package["dictionary_manifests"]["uk"]["target_lang"], "uk")


if __name__ == "__main__":
    unittest.main()
