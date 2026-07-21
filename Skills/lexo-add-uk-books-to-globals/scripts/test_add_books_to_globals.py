from __future__ import annotations

import argparse
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from add_books_to_globals import apply_books, audit_book, command_add, duplicates
from function_word_audit import audit_functions, function_errors
from verified_book_gate import require_verified_book


def write(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def seed(
    root: Path,
    book_id: str,
    translation: str,
    *,
    block_dictionary_translation: str = "",
) -> None:
    directory = (
        root
        / "Studio"
        / "Backend"
        / "data"
        / "dictionaries"
        / "library_uk"
        / "books"
        / book_id
    )
    write(
        directory / "seed_words_uk.json",
        {"rest|NOUN": {"translation": translation, "translations": [translation]}},
    )
    write(
        directory / "seed_blocks_uk.json",
        [
            {
                "source": "at rest",
                "translation": f"в {translation}",
                "dictionary_translation": block_dictionary_translation,
                "type": "fixed_expression",
                "explanation": "Describes a state without movement or activity.",
                "source_forms": ["at rest"],
                "components": [],
            }
        ],
    )
    write(
        directory / "book_layer_uk.json",
        {
            "book_id": book_id,
            "target_lang": "uk",
            "blocks": [{}],
            "book_layer_audit": {
                "second_pass": {"status": "passed", "unresolved": []},
                "third_pass": {"status": "passed", "unresolved": []},
                "fourth_pass": {"status": "passed", "unresolved": []},
            },
        },
    )
    write(
        directory / "word_to_word_uk.json",
        {"book_id": book_id, "target_lang": "uk", "entries": [], "block_occurrences": []},
    )


class AddBooksToGlobalsTest(unittest.TestCase):
    def test_full_write_and_repeat_preview_use_only_uk_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed(root, "book_a", "спокої")
            library = root / "Studio/Backend/data/dictionaries/library_uk"
            write(library / "global_words_uk.json", {})
            write(library / "global_blocks_uk.json", {})
            write(library / "global_function_words_uk.json", {})
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = command_add(argparse.Namespace(root=root, book_id=["book_a"], write=True))
            self.assertEqual(0, code)
            self.assertTrue(json.loads((library / "global_words_uk.json").read_text(encoding="utf-8")))
            self.assertFalse((root / "Studio/Backend/data/dictionaries/library_ru").exists())
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = command_add(argparse.Namespace(root=root, book_id=["book_a"], write=False))
            repeat = json.loads(output.getvalue())
            self.assertEqual(0, code)
            self.assertEqual(2, repeat["totals"]["skipped_existing"])

    def test_rejects_legacy_book_without_four_file_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "book_legacy"
            directory.mkdir()
            write(directory / "seed_words_uk.json", {})
            with self.assertRaisesRegex(ValueError, "incomplete UK four-file contract"):
                require_verified_book(directory, "book_legacy")

    def test_function_word_audit_uses_pos_and_requires_descriptions(self) -> None:
        seeds = {
            "be|AUX": {"translation": ""},
            "to|PART": {"translation": ""},
            "book|NOUN": {"translation": "книжка"},
        }
        functions = {
            "be|AUX": {
                "label": "Форма-зв’язка",
                "explanation": "Пов’язує учасника з ознакою або станом.",
            }
        }
        present, missing = audit_functions(seeds, functions)
        self.assertEqual(["be|AUX"], present)
        self.assertEqual(["to|PART"], missing)
        self.assertEqual([], function_errors(functions))
        self.assertTrue(
            function_errors({"to|PART": {"label": "", "explanation": ""}})
        )

    def test_function_word_match_key_covers_candidate(self) -> None:
        present, missing = audit_functions(
            {"be|AUX": {}},
            {
                "copula|AUX": {
                    "label": "Форма-зв’язка",
                    "explanation": "Пов’язує учасника з ознакою.",
                    "match_keys": ["be|AUX"],
                },
            },
        )
        self.assertEqual(["be|AUX"], present)
        self.assertEqual([], missing)

    def test_block_keeps_dictionary_and_contextual_translations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed(
                root,
                "book_a",
                "спокої",
                block_dictionary_translation="стан спокою",
            )
            _, blocks, report, errors = apply_books(root, ["book_a"], {}, {})
            self.assertEqual([], errors)
            self.assertEqual(2, report["totals"]["added"])
            self.assertEqual(1, report["totals"]["new_translation"])
            record = blocks["at rest"]
            self.assertEqual(
                ["стан спокою", "в спокої"],
                record["translations"],
            )
            self.assertEqual(
                ["dictionary_fallback", "contextual"],
                [item["translation_kind"] for item in record["variants"]],
            )

    def test_incremental_add_skip_and_new_translation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed(root, "book_a", "спокої")
            seed(root, "book_b", "решта")
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

            seed(root, "book_c", "спокої")
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
            seed(root, "book_a", "спокої")
            present, expected, missing = audit_book(root, "book_a", {}, {})
            self.assertEqual(0, present)
            self.assertEqual(2, expected)
            self.assertEqual(2, len(missing))


if __name__ == "__main__":
    unittest.main()

