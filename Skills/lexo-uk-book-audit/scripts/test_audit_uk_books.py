from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audit_uk_books import audit_root


class AuditUkBooksTest(unittest.TestCase):
    def test_incomplete_book_is_not_created(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            book = root / "Studio/Backend/data/dictionaries/library_uk/books/book_a"
            book.mkdir(parents=True)
            (book / "seed_words_uk.json").write_text("{}", encoding="utf-8")
            result = audit_root(root)
            self.assertEqual({"not_created": 1}, result["counts"])
            self.assertIn("word_to_word_uk.json", result["books"]["book_a"]["missing_files"])


if __name__ == "__main__":
    unittest.main()
