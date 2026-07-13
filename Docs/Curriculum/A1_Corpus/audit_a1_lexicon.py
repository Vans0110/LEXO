from __future__ import annotations

import sys
from collections import Counter

from build_lexical_inventory import (
    count_unit,
    read_books,
    read_ledger,
)


MIN_WORDS = 120
MAX_WORDS = 220
MAX_REPORTED_ITEMS = 80


def print_group(title: str, items: list[str]) -> None:
    print(f"{title}: {len(items)}")
    for item in items[:MAX_REPORTED_ITEMS]:
        print(f"  - {item}")
    if len(items) > MAX_REPORTED_ITEMS:
        print(f"  ... and {len(items) - MAX_REPORTED_ITEMS} more")


def main() -> int:
    books = read_books()
    hard_errors: list[str] = []
    missing_targets: list[str] = []
    missing_core: list[str] = []
    single_core: list[str] = []
    no_late_recycle: list[str] = []
    no_own_chapter_use: list[str] = []
    weak_own_chapter_use: list[str] = []

    chapter_counts = Counter(book.chapter for book in books)
    if len(chapter_counts) != 20:
        hard_errors.append(
            f"expected 20 chapters, found {len(chapter_counts)}"
        )
    if len(books) != 100:
        hard_errors.append(f"expected 100 books, found {len(books)}")
    for chapter in range(1, 21):
        if chapter_counts[chapter] != 5:
            hard_errors.append(
                f"chapter {chapter}: expected 5 books, "
                f"found {chapter_counts[chapter]}"
            )

    titles = Counter(book.title for book in books)
    for title, count in titles.items():
        if count > 1:
            hard_errors.append(f"duplicate title: {title} ({count})")

    for book in books:
        word_count = len(book.lemmas)
        if not MIN_WORDS <= word_count <= MAX_WORDS:
            hard_errors.append(
                f"{book.chapter}:{book.title}: {word_count} words"
            )
        for target in book.targets:
            if target.lower() == "review only":
                continue
            if count_unit(book, target) == 0:
                missing_targets.append(
                    f"{book.chapter}:{book.title} -> {target}"
                )

    for chapter, term in read_ledger():
        own_count = sum(
            count_unit(book, term)
            for book in books
            if book.chapter == chapter
        )
        total_count = sum(count_unit(book, term) for book in books)
        later_count = sum(
            count_unit(book, term)
            for book in books
            if book.chapter > chapter
        )
        key = f"{chapter}:{term}"
        if total_count == 0:
            missing_core.append(key)
        elif total_count == 1:
            single_core.append(key)
        if own_count == 0:
            no_own_chapter_use.append(key)
        own_book_count = sum(
            count_unit(book, term) > 0
            for book in books
            if book.chapter == chapter
        )
        if own_book_count < 2:
            weak_own_chapter_use.append(
                f"{key} ({own_book_count} books)"
            )
        if chapter < 20 and later_count == 0:
            no_late_recycle.append(key)

    hard_errors.extend(
        f"target missing from assigned book: {item}"
        for item in missing_targets
    )
    hard_errors.extend(
        f"core unit absent from corpus: {item}" for item in missing_core
    )

    print(
        f"chapters={len(chapter_counts)} books={len(books)} "
        f"unique_titles={len(titles)}"
    )
    print_group("HARD ERRORS", hard_errors)
    print_group("CORE USED ONCE", single_core)
    print_group("CORE ABSENT FROM OWN CHAPTER", no_own_chapter_use)
    print_group("CORE IN FEWER THAN TWO OWN BOOKS", weak_own_chapter_use)
    print_group("CORE WITHOUT LATER RECYCLE", no_late_recycle)

    if hard_errors:
        print("A1 lexical audit failed.")
        return 1

    if (
        single_core
        or no_own_chapter_use
        or weak_own_chapter_use
        or no_late_recycle
    ):
        print("A1 lexical audit passed hard checks with quality debt.")
        return 0

    print("A1 lexical audit passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
