from __future__ import annotations

import re
import sys
from collections import Counter
from functools import lru_cache
from pathlib import Path

import spacy


ROOT = Path(__file__).resolve().parent
CHAPTER_RE = re.compile(r"^\d{2}_.+\.md$")
BOOK_RE = re.compile(
    r"^## Book (?P<number>\d+): (?P<title>[^\n]+)\n\n"
    r"Target: (?P<target>[^\n]+)\n"
    r"(?:Recycle: (?P<recycle>[^\n]+)\n)?\n"
    r"(?P<body>.*?)(?=^## Book |\Z)",
    re.MULTILINE | re.DOTALL,
)
LEDGER_RE = re.compile(
    r"^### (?P<chapter>\d+)\. .+?\n\n"
    r"- Introduce: (?P<terms>.*?)(?=\n- Functions:)",
    re.MULTILINE | re.DOTALL,
)
WORD_RE = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)?")
SOFT_LINE_BREAK_RE = re.compile(r"(?<!\n)\n(?!\n)")
PHONE_NUMBER_RE = re.compile(r"(?<!\w)\+?\d(?:[\d ()-]*\d){6,}(?!\w)")
MIN_WORDS = 250
MAX_WORDS = 500
MIN_TARGETS = 8
MAX_TARGETS = 14
NLP = spacy.load(
    "en_core_web_sm",
    disable=["parser", "ner", "textcat"],
)


def split_terms(value: str) -> list[str]:
    return [
        item.strip().rstrip(".")
        for item in value.replace("\n  ", " ").split(",")
        if item.strip()
    ]


def has_non_phone_digits(text: str) -> bool:
    return bool(re.search(r"\d", PHONE_NUMBER_RE.sub("", text)))


@lru_cache(maxsize=None)
def phrase_words(value: str) -> tuple[str, ...]:
    return tuple(match.group().lower() for match in WORD_RE.finditer(value))


@lru_cache(maxsize=None)
def phrase_lemmas(value: str) -> tuple[str, ...]:
    return tuple(
        token.lemma_.lower()
        for token in NLP(value.replace("’", "'"))
        if token.is_alpha
    )


def count_sequence(values: list[str], phrase: tuple[str, ...]) -> int:
    if not phrase:
        return 0
    width = len(phrase)
    return sum(
        tuple(values[index : index + width]) == phrase
        for index in range(len(values) - width + 1)
    )


def count_unit(words: list[str], lemmas: list[str], unit: str) -> int:
    return max(
        count_sequence(words, phrase_words(unit)),
        count_sequence(lemmas, phrase_lemmas(unit)),
    )


def read_ledger() -> list[tuple[int, str]]:
    text = (ROOT / "WORD_LEDGER.md").read_text(encoding="utf-8")
    terms: list[tuple[int, str]] = []
    for match in LEDGER_RE.finditer(text):
        chapter = int(match.group("chapter"))
        for term in split_terms(match.group("terms")):
            if not term.startswith("planned") and not term.startswith(
                "no required"
            ):
                terms.append((chapter, term.lower()))
    return terms


def main() -> int:
    chapter_files = sorted(
        path for path in ROOT.glob("*.md") if CHAPTER_RE.match(path.name)
    )
    errors: list[str] = []
    quality_debt: list[str] = []
    titles: list[str] = []
    chapter_books: dict[int, list[tuple[list[str], list[str]]]] = {}
    word_counts: list[int] = []

    if not chapter_files:
        errors.append("no A2 chapter files found")
    if len(chapter_files) > 12:
        errors.append(f"expected at most 12 chapters, found {len(chapter_files)}")

    expected_numbers = list(range(1, len(chapter_files) + 1))
    actual_numbers = [int(path.name[:2]) for path in chapter_files]
    if actual_numbers != expected_numbers:
        errors.append(
            f"chapter sequence is not continuous: {actual_numbers}"
        )

    for path in chapter_files:
        chapter = int(path.name[:2])
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        matches = list(BOOK_RE.finditer(text))
        if len(matches) != 5:
            errors.append(f"{path.name}: expected 5 books, found {len(matches)}")

        chapter_books[chapter] = []
        for expected_number, match in enumerate(matches, start=1):
            number = int(match.group("number"))
            title = match.group("title").strip()
            targets = split_terms(match.group("target"))
            body = match.group("body").strip()
            words = [
                token.group().lower() for token in WORD_RE.finditer(body)
            ]
            lemmas = [
                token.lemma_.lower()
                for token in NLP(body.replace("’", "'"))
                if token.is_alpha
            ]
            titles.append(title)
            word_counts.append(len(words))
            chapter_books[chapter].append((words, lemmas))

            if SOFT_LINE_BREAK_RE.search(body):
                errors.append(
                    f"{path.name} / {title}: line break inside paragraph"
                )
            if has_non_phone_digits(body):
                errors.append(
                    f"{path.name} / {title}: digit outside phone number"
                )

            if number != expected_number:
                errors.append(
                    f"{path.name}: expected Book {expected_number}, found {number}"
                )
            if not MIN_WORDS <= len(words) <= MAX_WORDS:
                errors.append(
                    f"{path.name} / {title}: {len(words)} words, "
                    f"expected {MIN_WORDS}-{MAX_WORDS}"
                )
            if not MIN_TARGETS <= len(targets) <= MAX_TARGETS:
                errors.append(
                    f"{path.name} / {title}: {len(targets)} targets, "
                    f"expected {MIN_TARGETS}-{MAX_TARGETS}"
                )
            for target in targets:
                if count_unit(words, lemmas, target) == 0:
                    errors.append(
                        f"{path.name} / {title}: missing target '{target}'"
                    )

    for title, count in Counter(titles).items():
        if count > 1:
            errors.append(f"duplicate title: {title} ({count})")

    for chapter, term in read_ledger():
        books = chapter_books.get(chapter)
        if books is None:
            continue
        book_count = sum(
            count_unit(words, lemmas, term) > 0 for words, lemmas in books
        )
        total_count = sum(
            count_unit(words, lemmas, term) for words, lemmas in books
        )
        if total_count == 0:
            errors.append(f"chapter {chapter}: missing core unit '{term}'")
        elif book_count < 2:
            quality_debt.append(
                f"chapter {chapter}: core unit '{term}' appears in "
                f"{book_count} book"
            )

    print(
        f"chapters={len(chapter_files)} books={len(titles)} "
        f"unique_titles={len(set(titles))} "
        f"word_range={min(word_counts, default=0)}-"
        f"{max(word_counts, default=0)}"
    )
    print(f"errors={len(errors)} quality_debt={len(quality_debt)}")
    for error in errors:
        print(f"ERROR: {error}")
    for item in quality_debt:
        print(f"DEBT: {item}")

    if errors:
        print("A2 corpus audit failed.")
        return 1
    if quality_debt:
        print("A2 corpus audit passed hard checks with quality debt.")
        return 0

    print("A2 corpus audit passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
