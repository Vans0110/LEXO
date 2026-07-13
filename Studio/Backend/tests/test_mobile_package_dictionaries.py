import unittest

from engine.storage import LexoStorage


class MobilePackageDictionaryManifestTests(unittest.TestCase):
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
