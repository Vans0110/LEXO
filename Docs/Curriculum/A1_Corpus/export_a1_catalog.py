from __future__ import annotations

import re
from pathlib import Path


CORPUS_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = CORPUS_ROOT.parents[2]
CATALOG_ROOT = PROJECT_ROOT / "Studio" / "Workbench" / "Books" / "A1"

BOOK_RE = re.compile(
    r"^## Book (?P<number>\d+): (?P<title>[^\n]+)\n\n"
    r"Target: [^\n]+\n"
    r"(?:Recycle: [^\n]+\n)?\n"
    r"(?P<body>.*?)(?=^## Book |\Z)",
    re.MULTILINE | re.DOTALL,
)
INVALID_FILENAME_RE = re.compile(r'[<>:"/\\|?*]')

CHAPTERS = (
    ("01_INTRODUCTION.md", "Глава 1 - Introduction"),
    ("02_FAMILY_AND_PEOPLE.md", "Глава 2 - Family"),
    ("03_HOME_AND_FURNITURE.md", "Глава 3 - Home & Furniture"),
    ("04_FOOD_AND_DRINKS.md", "Глава 4 - Food & Drinks"),
    ("05_WORK_AND_STUDY.md", "Глава 5 - Work & Study"),
    ("06_DAILY_ROUTINE_AND_TIME.md", "Глава 6 - Daily Routine & Time"),
    ("07_CLOTHES_AND_SHOPPING.md", "Глава 7 - Clothes & Shopping"),
    ("08_CITY_AND_TRANSPORT.md", "Глава 8 - City & Transport"),
    ("09_WEATHER_AND_NATURE.md", "Глава 9 - Weather & Nature"),
    ("10_NUMBERS_AND_MONEY.md", "Глава 10 - Numbers & Money"),
    ("11_HEALTH_AND_BODY.md", "Глава 11 - Health & Body"),
    ("12_TRAVEL_AND_PLANS.md", "Глава 12 - Travel & Plans"),
    ("13_HOBBIES_AND_FREE_TIME.md", "Глава 13 - Hobbies & Free Time"),
    (
        "14_TECHNOLOGY_AND_COMMUNICATION.md",
        "Глава 14 - Technology & Communication",
    ),
    ("15_FRIENDS_AND_EMOTIONS.md", "Глава 15 - Friends & Emotions"),
    (
        "16_HOLIDAYS_AND_SPECIAL_DAYS.md",
        "Глава 16 - Holidays & Special Days",
    ),
    ("17_ANIMALS_AND_PETS.md", "Глава 17 - Animals & Pets"),
    (
        "18_PROBLEMS_AND_SMALL_ADVENTURES.md",
        "Глава 18 - Problems & Small Adventures",
    ),
    ("19_DREAMS_AND_FUTURE.md", "Глава 19 - Dreams & Future"),
    ("20_REVIEW_WORLD.md", "Глава 20 - Review World"),
)


def safe_filename(title: str) -> str:
    cleaned = INVALID_FILENAME_RE.sub("", title).rstrip(". ")
    if not cleaned:
        raise ValueError(f"Book title cannot be used as a filename: {title!r}")
    return cleaned


def normalize_story_body(body: str) -> str:
    paragraphs = re.split(r"\n\s*\n", body.strip())
    return "\n\n".join(
        re.sub(r"\s*\n\s*", " ", paragraph).strip()
        for paragraph in paragraphs
        if paragraph.strip()
    )


def load_books(source_path: Path) -> list[tuple[int, str, str]]:
    source = source_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    books = [
        (
            int(match.group("number")),
            match.group("title").strip(),
            normalize_story_body(match.group("body")),
        )
        for match in BOOK_RE.finditer(source)
    ]
    if len(books) != 5:
        raise ValueError(f"{source_path.name}: expected 5 books, found {len(books)}")
    return books


def main() -> None:
    expected_files: set[Path] = set()
    exported = 0

    for chapter_number, (source_name, folder_name) in enumerate(CHAPTERS, 1):
        chapter_dir = CATALOG_ROOT / folder_name
        chapter_dir.mkdir(parents=True, exist_ok=True)
        books = load_books(CORPUS_ROOT / source_name)
        selected_books = books if chapter_number <= 12 else books[:1]

        for _, title, body in selected_books:
            output_path = chapter_dir / f"{safe_filename(title)}.txt"
            output_path.write_text(
                f"{title}\n\n{body}\n",
                encoding="utf-8",
                newline="\n",
            )
            expected_files.add(output_path)
            exported += 1

    for chapter_dir in CATALOG_ROOT.glob("Глава *"):
        if not chapter_dir.is_dir():
            continue
        for text_path in chapter_dir.glob("*.txt"):
            if text_path not in expected_files:
                text_path.unlink()

    if exported != 68:
        raise RuntimeError(f"Expected 68 exported books, wrote {exported}")

    print(f"Exported {exported} A1 books to {CATALOG_ROOT}")


if __name__ == "__main__":
    main()
