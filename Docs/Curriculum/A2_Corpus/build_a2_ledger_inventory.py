from __future__ import annotations

import csv
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "WORD_LEDGER.md"
OUTPUT = ROOT / "Lexical_Registry"
SECTION_RE = re.compile(
    r"^## (?P<chapter>\d+)\. (?P<title>[^\n]+)\n\n"
    r"(?P<body>.*?)(?=^## |\Z)",
    re.MULTILINE | re.DOTALL,
)
FIELD_RE = re.compile(
    r"^- (?P<name>Active Core|Topic Vocabulary|Recognition|A1 Recycle): "
    r"(?P<value>.*?)(?=\n- [A-Z]|\n\n|\Z)",
    re.MULTILINE | re.DOTALL,
)
RECYCLE_RE = re.compile(
    r"^- Recycle in: (?P<value>.*?)(?=\n\n|\Z)",
    re.MULTILINE | re.DOTALL,
)
REVIEW_VALUES = {
    "no required new lexical group",
    "no planned new recognition group",
}


def split_units(value: str) -> list[str]:
    return [
        item.strip().rstrip(".")
        for item in value.replace("\n  ", " ").split(",")
        if item.strip()
    ]


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    rows: list[dict[str, str | int]] = []

    for section in SECTION_RE.finditer(text):
        chapter = int(section.group("chapter"))
        title = section.group("title").strip()
        body = section.group("body")
        recycle_match = RECYCLE_RE.search(body)
        recycle_route = (
            " ".join(recycle_match.group("value").split())
            if recycle_match
            else ""
        )

        for field in FIELD_RE.finditer(body):
            category = field.group("name")
            if category == "A1 Recycle":
                continue
            for unit in split_units(field.group("value")):
                if unit.lower() in REVIEW_VALUES:
                    continue
                rows.append(
                    {
                        "level": "A2",
                        "chapter": chapter,
                        "chapter_title": title,
                        "category": category,
                        "unit": unit,
                        "status": "planned",
                        "recycle_route": recycle_route,
                    }
                )

    OUTPUT.mkdir(exist_ok=True)
    path = OUTPUT / "A2_Lexicon.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "level",
                "chapter",
                "chapter_title",
                "category",
                "unit",
                "status",
                "recycle_route",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    category_counts = Counter(str(row["category"]) for row in rows)
    summary_lines = [
        "# A2 Lexical Registry",
        "",
        "Автоматически построенная сводка планового словаря A2.",
        "",
        "## Общий объём",
        "",
        f"- Active Core: {category_counts['Active Core']}.",
        f"- Topic Vocabulary: {category_counts['Topic Vocabulary']}.",
        f"- Recognition: {category_counts['Recognition']}.",
        "- Обязательных Active Core + Topic Vocabulary: "
        f"{category_counts['Active Core'] + category_counts['Topic Vocabulary']}.",
        f"- Всего строк реестра: {len(rows)}.",
        "",
        "## По главам",
        "",
        "| Глава | Active | Topic | Recognition |",
        "|---:|---:|---:|---:|",
    ]
    for chapter in range(1, 13):
        chapter_rows = [
            row for row in rows if int(row["chapter"]) == chapter
        ]
        counts = Counter(str(row["category"]) for row in chapter_rows)
        summary_lines.append(
            f"| {chapter} | {counts['Active Core']} | "
            f"{counts['Topic Vocabulary']} | {counts['Recognition']} |"
        )
    summary_lines.extend(
        [
            "",
            "## Статус",
            "",
            "- Все единицы имеют статус `planned`.",
            "- Фактические частоты появятся после написания соответствующих книг.",
            "- Recognition — разрешённый максимум, а не обязательный список.",
            "",
        ]
    )
    summary_path = OUTPUT / "SUMMARY.md"
    summary_path.write_text("\n".join(summary_lines), encoding="utf-8")

    print(f"rows={len(rows)} output={path} summary={summary_path}")


if __name__ == "__main__":
    main()
