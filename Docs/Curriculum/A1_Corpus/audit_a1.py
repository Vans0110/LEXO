from __future__ import annotations

import re
import sys
from pathlib import Path

import spacy


ROOT = Path(__file__).resolve().parent
CHAPTER_RE = re.compile(r"^\d{2}_.+\.md$")
BOOK_RE = re.compile(
    r"^## Book (?P<number>\d+): (?P<title>[^\n]+)\n\n"
    r"Target: (?P<target>[^\n]+)\n"
    r"(?:Recycle: [^\n]+\n)?\n"
    r"(?P<body>.*?)(?=^## Book |\Z)",
    re.MULTILINE | re.DOTALL,
)
WORD_RE = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)?")
SOFT_LINE_BREAK_RE = re.compile(r"(?<!\n)\n(?!\n)")
PHONE_NUMBER_RE = re.compile(r"(?<!\w)\+?\d(?:[\d ()-]*\d){6,}(?!\w)")
NLP = spacy.load(
    "en_core_web_sm",
    disable=["parser", "ner", "textcat"],
)


def lemmas(text: str) -> list[str]:
    return [
        token.lemma_.lower()
        for token in NLP(text.replace("’", "'"))
        if token.is_alpha
    ]


def has_non_phone_digits(text: str) -> bool:
    return bool(re.search(r"\d", PHONE_NUMBER_RE.sub("", text)))


def contains_target(
    body_text: str,
    body_lemmas: list[str],
    target: str,
) -> bool:
    body_words = [
        match.group().lower() for match in WORD_RE.finditer(body_text)
    ]
    target_words = [
        match.group().lower() for match in WORD_RE.finditer(target)
    ]
    width = len(target_words)
    if target_words and any(
        body_words[index : index + width] == target_words
        for index in range(len(body_words) - width + 1)
    ):
        return True
    target_lemmas = lemmas(target)
    if not target_lemmas:
        return True
    width = len(target_lemmas)
    return any(
        body_lemmas[index : index + width] == target_lemmas
        for index in range(len(body_lemmas) - width + 1)
    )


def main() -> int:
    chapter_files = sorted(
        path for path in ROOT.glob("*.md") if CHAPTER_RE.match(path.name)
    )
    errors: list[str] = []
    titles: list[str] = []
    book_count = 0
    word_counts: list[int] = []

    if len(chapter_files) != 20:
        errors.append(f"expected 20 chapter files, found {len(chapter_files)}")

    for path in chapter_files:
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        books = list(BOOK_RE.finditer(text))
        chapter_bodies: list[str] = []
        chapter_targets: set[str] = set()
        if len(books) != 5:
            errors.append(f"{path.name}: expected 5 books, found {len(books)}")

        for book in books:
            book_count += 1
            title = book.group("title").strip()
            titles.append(title)
            body = book.group("body").strip()
            chapter_bodies.append(body)
            body_words = WORD_RE.findall(body)
            word_counts.append(len(body_words))

            if SOFT_LINE_BREAK_RE.search(body):
                errors.append(
                    f"{path.name} / {title}: line break inside paragraph"
                )
            if has_non_phone_digits(body):
                errors.append(
                    f"{path.name} / {title}: digit outside phone number"
                )

            if not 120 <= len(body_words) <= 220:
                errors.append(
                    f"{path.name} / {title}: {len(body_words)} words, "
                    "expected 120-220"
                )

            targets = [
                item.strip().rstrip(".")
                for item in book.group("target").split(",")
            ]
            for target in targets:
                if target.lower() == "review only":
                    continue
                chapter_targets.add(target)

        chapter_body = "\n".join(chapter_bodies)
        chapter_lemmas = lemmas(chapter_body)
        for target in sorted(chapter_targets):
            if not contains_target(chapter_body, chapter_lemmas, target):
                errors.append(
                    f"{path.name}: chapter target not found: {target}"
                )

    duplicate_titles = sorted(
        title for title in set(titles) if titles.count(title) > 1
    )
    for title in duplicate_titles:
        errors.append(f"duplicate title: {title}")

    if book_count != 100:
        errors.append(f"expected 100 books, found {book_count}")

    print(
        f"chapters={len(chapter_files)} books={book_count} "
        f"unique_titles={len(set(titles))} "
        f"word_range={min(word_counts, default=0)}-"
        f"{max(word_counts, default=0)}"
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print("A1 corpus audit passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
