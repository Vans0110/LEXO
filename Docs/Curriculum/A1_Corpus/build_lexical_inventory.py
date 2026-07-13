from __future__ import annotations

import csv
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import spacy

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "Lexical_Inventory"
CHAPTER_RE = re.compile(r"^\d{2}_.+\.md$")
BOOK_RE = re.compile(
    r"^## Book (?P<number>\d+): (?P<title>[^\n]+)\n\n"
    r"Target: (?P<target>[^\n]+)\n"
    r"(?:Recycle: (?P<recycle>[^\n]+)\n)?\n"
    r"(?P<body>.*?)(?=^## Book |\Z)",
    re.MULTILINE | re.DOTALL,
)
LEDGER_SECTION_RE = re.compile(
    r"^### (?P<chapter>\d+)\. .+?\n\n"
    r"- Introduce: (?P<terms>.*?)(?=\n- Functions:)",
    re.MULTILINE | re.DOTALL,
)
WORD_RE = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)?")
SPLITS = {
    "A_D.csv": set("abcd"),
    "E_H.csv": set("efgh"),
    "I_M.csv": set("ijklm"),
    "N_R.csv": set("nopqr"),
    "S_Z.csv": set("stuvwxyz"),
}
NLP = spacy.load(
    "en_core_web_sm",
    disable=["parser", "ner", "textcat"],
)
@dataclass
class Book:
    chapter: int
    title: str
    targets: list[str]
    recycle: list[str]
    body: str
    words: list[str]
    lemmas: list[str]


def split_terms(value: str) -> list[str]:
    return [
        item.strip().rstrip(".")
        for item in value.replace("\n  ", " ").split(",")
        if item.strip()
    ]


@lru_cache(maxsize=None)
def phrase_lemmas(value: str) -> tuple[str, ...]:
    return tuple(
        token.lemma_.lower()
        for token in NLP(value.replace("’", "'"))
        if token.is_alpha
    )


@lru_cache(maxsize=None)
def phrase_words(value: str) -> tuple[str, ...]:
    return tuple(
        match.group().lower()
        for match in WORD_RE.finditer(value.replace("’", "'"))
    )


def count_sequence(values: list[str], phrase: tuple[str, ...]) -> int:
    if not phrase:
        return 0
    width = len(phrase)
    return sum(
        tuple(values[index : index + width]) == phrase
        for index in range(len(values) - width + 1)
    )


def count_unit(book: Book, value: str) -> int:
    exact_count = count_sequence(book.words, phrase_words(value))
    lemma_count = count_sequence(book.lemmas, phrase_lemmas(value))
    return max(exact_count, lemma_count)


def read_books() -> list[Book]:
    raw_books: list[tuple[int, re.Match[str]]] = []
    for path in sorted(ROOT.glob("*.md")):
        if not CHAPTER_RE.match(path.name):
            continue
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        chapter = int(path.name[:2])
        raw_books.extend((chapter, match) for match in BOOK_RE.finditer(text))

    docs = list(
        NLP.pipe(
            match.group("body").strip().replace("’", "'")
            for _, match in raw_books
        )
    )
    books: list[Book] = []
    for (chapter, match), doc in zip(raw_books, docs):
        books.append(
            Book(
                chapter=chapter,
                title=match.group("title").strip(),
                targets=split_terms(match.group("target")),
                recycle=split_terms(match.group("recycle") or ""),
                body=match.group("body").strip(),
                words=[
                    match.group().lower()
                    for match in WORD_RE.finditer(
                        match.group("body").replace("’", "'")
                    )
                ],
                lemmas=[
                    token.lemma_.lower()
                    for token in doc
                    if token.is_alpha
                ],
            )
        )
    return books


def read_ledger() -> list[tuple[int, str]]:
    text = (ROOT / "WORD_LEDGER.md").read_text(encoding="utf-8")
    terms: list[tuple[int, str]] = []
    for match in LEDGER_SECTION_RE.finditer(text):
        chapter = int(match.group("chapter"))
        for term in split_terms(match.group("terms")):
            if not term.startswith("no required"):
                terms.append((chapter, term.lower()))
    return terms


def token_inventory(books: list[Book]) -> list[dict[str, str | int]]:
    counts: Counter[str] = Counter()
    forms: defaultdict[str, Counter[str]] = defaultdict(Counter)
    parts: defaultdict[str, Counter[str]] = defaultdict(Counter)
    chapters: defaultdict[str, set[int]] = defaultdict(set)
    book_titles: defaultdict[str, set[str]] = defaultdict(set)

    for book, doc in zip(
        books,
        NLP.pipe(book.body.replace("’", "'") for book in books),
    ):
        seen: set[str] = set()
        for token in doc:
            if not token.is_alpha:
                continue
            lemma = token.lemma_.lower()
            counts[lemma] += 1
            forms[lemma][token.text.lower()] += 1
            parts[lemma][token.pos_] += 1
            chapters[lemma].add(book.chapter)
            if lemma not in seen:
                book_titles[lemma].add(f"{book.chapter}:{book.title}")
                seen.add(lemma)

    ledger_tokens: defaultdict[str, set[int]] = defaultdict(set)
    for chapter, term in read_ledger():
        for lemma in phrase_lemmas(term):
            ledger_tokens[lemma].add(chapter)

    target_tokens: defaultdict[str, set[int]] = defaultdict(set)
    for book in books:
        for target in book.targets:
            if target.lower() == "review only":
                continue
            for lemma in phrase_lemmas(target):
                target_tokens[lemma].add(book.chapter)

    rows: list[dict[str, str | int]] = []
    for lemma in sorted(counts):
        first_chapter = min(chapters[lemma])
        ledger_chapters = sorted(ledger_tokens[lemma])
        target_chapters = sorted(target_tokens[lemma])
        rows.append(
            {
                "lemma": lemma,
                "forms": "|".join(sorted(forms[lemma])),
                "pos": "|".join(sorted(parts[lemma])),
                "occurrences": counts[lemma],
                "book_count": len(book_titles[lemma]),
                "first_chapter": first_chapter,
                "chapters": "|".join(map(str, sorted(chapters[lemma]))),
                "ledger_chapters": "|".join(map(str, ledger_chapters)),
                "target_chapters": "|".join(map(str, target_chapters)),
                "status": (
                    "core"
                    if ledger_chapters
                    else "target_extra"
                    if target_chapters
                    else "unclassified"
                ),
            }
        )
    return rows


def curriculum_units(books: list[Book]) -> list[dict[str, str | int]]:
    units: dict[tuple[int, str], dict[str, str | int]] = {}

    for chapter, term in read_ledger():
        units[(chapter, term)] = {
            "chapter": chapter,
            "unit": term,
            "source": "ledger",
        }

    for book in books:
        for target in book.targets:
            term = target.lower()
            if term == "review only":
                continue
            key = (book.chapter, term)
            if key not in units:
                units[key] = {
                    "chapter": book.chapter,
                    "unit": term,
                    "source": "target_extra",
                }

    rows: list[dict[str, str | int]] = []
    for (chapter, term), row in sorted(units.items()):
        own_books = [
            book
            for book in books
            if book.chapter == chapter
            and count_unit(book, term) > 0
        ]
        later_books = [
            book
            for book in books
            if book.chapter > chapter
            and count_unit(book, term) > 0
        ]
        all_books = [
            book for book in books if count_unit(book, term) > 0
        ]
        occurrences = sum(count_unit(book, term) for book in books)
        rows.append(
            {
                **row,
                "occurrences": occurrences,
                "book_count": len(all_books),
                "own_chapter_books": len(own_books),
                "later_books": len(later_books),
                "first_book": (
                    f"{all_books[0].chapter}:{all_books[0].title}"
                    if all_books
                    else ""
                ),
                "result": (
                    "missing"
                    if occurrences == 0
                    else "single"
                    if occurrences == 1
                    else "pass"
                    if row["source"] == "target_extra"
                    else "no_late_recycle"
                    if chapter < 20 and not later_books
                    else "pass"
                ),
            }
        )
    return rows


def write_csv(path: Path, rows: list[dict[str, str | int]]) -> None:
    if not rows:
        return
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_summary(
    token_rows: list[dict[str, str | int]],
    unit_rows: list[dict[str, str | int]],
) -> None:
    statuses = Counter(str(row["status"]) for row in token_rows)
    results = Counter(str(row["result"]) for row in unit_rows)
    unclassified_once = [
        str(row["lemma"])
        for row in token_rows
        if row["status"] == "unclassified" and row["occurrences"] == 1
    ]
    missing = [
        f'{row["chapter"]}:{row["unit"]}'
        for row in unit_rows
        if row["result"] == "missing"
    ]
    single = [
        f'{row["chapter"]}:{row["unit"]}'
        for row in unit_rows
        if row["result"] == "single"
    ]
    no_late = [
        f'{row["chapter"]}:{row["unit"]}'
        for row in unit_rows
        if row["result"] == "no_late_recycle"
    ]
    content = f"""# A1 Lexical Inventory

Автоматически построенный снимок фактической лексики 100 историй.

## Сводка

- Уникальных лемм в текстах: {len(token_rows)}.
- Лемм, связанных с ядром: {statuses["core"]}.
- Дополнительных target-лемм: {statuses["target_extra"]}.
- Неклассифицированных лемм: {statuses["unclassified"]}.
- Учебных единиц в реестре и Target: {len(unit_rows)}.
- Полностью отсутствуют: {results["missing"]}.
- Встречаются один раз: {results["single"]}.
- Не возвращаются после главы: {results["no_late_recycle"]}.
- Проходят базовый маршрут повторения: {results["pass"]}.

## Отсутствующие единицы

{", ".join(missing) or "Нет."}

## Одноразовые учебные единицы

{", ".join(single) or "Нет."}

## Без позднего повторения

{", ".join(no_late) or "Нет."}

## Одноразовая неклассифицированная лексика

{", ".join(unclassified_once) or "Нет."}

## Файлы

- `Curriculum_01_05.csv` ... `Curriculum_16_20.csv` — слова и фразы из
  реестра и Target.
- `Revision_Backlog.csv` — только отсутствующие, одноразовые и не
  возвращающиеся единицы.
- `A_D.csv` ... `S_Z.csv` — полный токенный инвентарь.

## Ограничение

Статус `core` означает присутствие леммы в реестре, но ещё не утверждённую
частотность или официальный уровень CEFR. Классификация сложных значений
требует педагогической проверки.
"""
    (OUTPUT / "SUMMARY.md").write_text(content, encoding="utf-8")


def main() -> None:
    books = read_books()
    token_rows = token_inventory(books)
    unit_rows = curriculum_units(books)
    OUTPUT.mkdir(exist_ok=True)

    for filename, initials in SPLITS.items():
        rows = [
            row
            for row in token_rows
            if str(row["lemma"])[0].lower() in initials
        ]
        write_csv(OUTPUT / filename, rows)

    for start in range(1, 21, 5):
        end = start + 4
        rows = [
            row
            for row in unit_rows
            if start <= int(row["chapter"]) <= end
        ]
        write_csv(
            OUTPUT / f"Curriculum_{start:02d}_{end:02d}.csv",
            rows,
        )
    write_csv(
        OUTPUT / "Revision_Backlog.csv",
        [row for row in unit_rows if row["result"] != "pass"],
    )

    old_path = OUTPUT / "Curriculum_Units.csv"
    if old_path.exists():
        old_path.unlink()
    write_summary(token_rows, unit_rows)
    print(
        f"books={len(books)} lemmas={len(token_rows)} "
        f"units={len(unit_rows)} output={OUTPUT}"
    )


if __name__ == "__main__":
    main()
