import tempfile
import unittest
from pathlib import Path

from engine.storage import LexoStorage


class _Translator:
    def __init__(self, target_lang: str) -> None:
        self.target_lang = target_lang
        self.provider_name = f"test:{target_lang}"
        self.is_available = True

    def translate_segments(self, segments):
        return [f"{self.target_lang}:{segment}" for segment in segments]


class MultilingualSourceGraphTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.addCleanup(self.temp_dir.cleanup)
        self.storage = LexoStorage(Path(self.temp_dir.name))
        self.storage.book_translation_providers = {
            "ru": _Translator("ru"),
            "uk": _Translator("uk"),
        }

    def test_languages_share_one_canonical_source_graph(self) -> None:
        source = "There are twelve students in the room.\n\nSara opens the door."
        ru = self.storage.import_book_text(
            "The Wrong Classroom",
            source,
            target_lang="ru",
            stable_book_key="a1/chapter-1/the-wrong-classroom",
        )
        ru_reader = self.storage.get_paragraphs(ru["id"], "ru")

        uk = self.storage.import_book_text(
            "The Wrong Classroom",
            source,
            target_lang="uk",
            stable_book_key="a1/chapter-1/the-wrong-classroom",
        )
        uk_reader = self.storage.get_paragraphs(uk["id"], "uk")
        ru_reader_after = self.storage.get_paragraphs(ru["id"], "ru")

        self.assertEqual(ru["id"], uk["id"])
        self.assertEqual(
            self._word_ids(ru_reader),
            self._word_ids(uk_reader),
        )
        self.assertEqual(
            self._segment_ids(ru_reader),
            self._segment_ids(uk_reader),
        )
        self.assertEqual(
            [item["target_text"] for item in ru_reader_after["paragraphs"]],
            [item["target_text"] for item in ru_reader["paragraphs"]],
        )
        self.assertNotEqual(
            [item["target_text"] for item in ru_reader["paragraphs"]],
            [item["target_text"] for item in uk_reader["paragraphs"]],
        )

    def test_reimport_does_not_change_source_ids(self) -> None:
        source = "A student opens a book."
        first = self.storage.import_book_text(
            "Stable",
            source,
            target_lang="ru",
            stable_book_key="stable-book",
        )
        first_reader = self.storage.get_paragraphs(first["id"], "ru")
        self.storage.import_book_text(
            "Stable",
            source,
            target_lang="ru",
            stable_book_key="stable-book",
        )
        second_reader = self.storage.get_paragraphs(first["id"], "ru")
        self.assertEqual(self._word_ids(first_reader), self._word_ids(second_reader))
        self.assertEqual(
            self._segment_ids(first_reader), self._segment_ids(second_reader)
        )

    @staticmethod
    def _word_ids(reader):
        return [
            word["id"]
            for paragraph in reader["paragraphs"]
            for word in paragraph["words"]
        ]

    @staticmethod
    def _segment_ids(reader):
        return [
            segment["id"]
            for paragraph in reader["paragraphs"]
            for segment in paragraph["segments_v2"]
        ]


if __name__ == "__main__":
    unittest.main()
