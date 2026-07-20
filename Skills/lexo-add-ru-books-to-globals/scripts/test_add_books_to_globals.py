from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from add_books_to_globals import apply_books, audit_book, duplicates


def write(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def seed(root: Path, book_id: str, translation: str) -> None:
    directory = (
        root
        / "Studio"
        / "Backend"
        / "data"
        / "dictionaries"
        / "library_ru"
        / "books"
        / book_id
    )
    write(
        directory / "seed_words_ru.json",
        {"rest|NOUN": {"translation": translation, "translations": [translation]}},
    )
    write(
        directory / "seed_blocks_ru.json",
        [
            {
                "source": "at rest",
                "translation": f"в {translation}",
                "type": "fixed_expression",
                "explanation": "Describes a state without movement or activity.",
                "source_forms": ["at rest"],
                "components": [],
            }
        ],
    )


class AddBooksToGlobalsTest(unittest.TestCase):
    def test_incremental_add_skip_and_new_translation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed(root, "book_a", "покое")
            seed(root, "book_b", "остаток")
            words, blocks, report, errors = apply_books(
                root, ["book_a"], {}, {}
            )
            self.assertEqual([], errors)
            self.assertEqual(2, report["totals"]["added"])
            self.assertEqual([], duplicates(words, "word"))
            self.assertEqual([], duplicates(blocks, "block"))
            present, expected, missing = audit_book(
                root, "book_a", words, blocks
            )
            self.assertEqual((expected, []), (present, missing))

            same_words, same_blocks, same_report, errors = apply_books(
                root, ["book_a"], words, blocks
            )
            self.assertEqual([], errors)
            self.assertEqual(words, same_words)
            self.assertEqual(blocks, same_blocks)
            self.assertEqual(2, same_report["totals"]["skipped_existing"])

            next_words, next_blocks, next_report, errors = apply_books(
                root, ["book_b"], words, blocks
            )
            self.assertEqual([], errors)
            self.assertEqual(2, next_report["totals"]["new_translation"])
            self.assertEqual(2, len(next_words["rest|NOUN"]["translations"]))
            self.assertEqual(2, len(next_blocks["at rest"]["translations"]))

            seed(root, "book_c", "покое")
            _, _, provenance_report, errors = apply_books(
                root, ["book_c"], words, blocks
            )
            self.assertEqual([], errors)
            self.assertEqual(
                2, provenance_report["totals"]["provenance_supplemented"]
            )

    def test_reports_unapplied_book(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed(root, "book_a", "покое")
            present, expected, missing = audit_book(root, "book_a", {}, {})
            self.assertEqual(0, present)
            self.assertEqual(2, expected)
            self.assertEqual(2, len(missing))


if __name__ == "__main__":
    unittest.main()
