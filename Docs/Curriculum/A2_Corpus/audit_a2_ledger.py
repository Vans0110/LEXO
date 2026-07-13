from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
A1_LEDGER = ROOT.parent / "A1_Corpus" / "WORD_LEDGER.md"
A2_LEDGER = ROOT / "WORD_LEDGER.md"
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
A1_INTRODUCE_RE = re.compile(
    r"^- Introduce: (?P<value>.*?)(?=\n- Functions:)",
    re.MULTILINE | re.DOTALL,
)
PLACEHOLDERS = {
    "planned with chapter passports",
    "todo",
    "tbd",
}
REVIEW_VALUES = {
    "no required new lexical group",
    "no planned new recognition group",
}
EXPECTED_CHAPTERS = 12
ACTIVE_RANGE = range(180, 211)
TOPIC_RANGE = range(160, 201)
RECOGNITION_RANGE = range(40, 81)


def split_units(value: str) -> list[str]:
    return [
        item.strip().rstrip(".")
        for item in value.replace("\n  ", " ").split(",")
        if item.strip()
    ]


def parse_a1_units() -> set[str]:
    text = A1_LEDGER.read_text(encoding="utf-8")
    units: set[str] = set()
    for match in A1_INTRODUCE_RE.finditer(text):
        units.update(unit.lower() for unit in split_units(match.group("value")))
    return units


def main() -> int:
    text = A2_LEDGER.read_text(encoding="utf-8")
    sections = list(SECTION_RE.finditer(text))
    errors: list[str] = []
    warnings: list[str] = []
    by_category: dict[str, list[tuple[int, str]]] = defaultdict(list)
    chapter_fields: dict[int, dict[str, list[str]]] = {}

    chapters = [int(match.group("chapter")) for match in sections]
    if chapters != list(range(1, EXPECTED_CHAPTERS + 1)):
        errors.append(f"expected chapters 1-12, found {chapters}")

    for section in sections:
        chapter = int(section.group("chapter"))
        fields: dict[str, list[str]] = {}
        for field in FIELD_RE.finditer(section.group("body")):
            category = field.group("name")
            units = split_units(field.group("value"))
            fields[category] = units
            by_category[category].extend((chapter, unit) for unit in units)

        chapter_fields[chapter] = fields
        for required in (
            "Active Core",
            "Topic Vocabulary",
            "Recognition",
            "A1 Recycle",
        ):
            if required not in fields:
                errors.append(f"chapter {chapter}: missing field '{required}'")

        for category, units in fields.items():
            for unit in units:
                if unit.lower() in PLACEHOLDERS:
                    errors.append(
                        f"chapter {chapter} {category}: placeholder '{unit}'"
                    )

        if chapter < 12:
            if not fields.get("Active Core"):
                errors.append(f"chapter {chapter}: empty Active Core")
            if not fields.get("Topic Vocabulary"):
                errors.append(f"chapter {chapter}: empty Topic Vocabulary")
        else:
            active_review = fields.get("Active Core", [])
            topic_review = fields.get("Topic Vocabulary", [])
            if (
                not active_review
                or active_review[0] != "no required new lexical group"
            ):
                errors.append("chapter 12: unexpected Active Core")
            if (
                not topic_review
                or topic_review[0] != "no required new lexical group"
            ):
                errors.append("chapter 12: unexpected Topic Vocabulary")

    active = [
        (chapter, unit)
        for chapter, unit in by_category["Active Core"]
        if unit.lower() not in REVIEW_VALUES
    ]
    topic = [
        (chapter, unit)
        for chapter, unit in by_category["Topic Vocabulary"]
        if unit.lower() not in REVIEW_VALUES
    ]
    recognition = [
        (chapter, unit)
        for chapter, unit in by_category["Recognition"]
        if unit.lower() not in REVIEW_VALUES
    ]

    active_counts = Counter(unit.lower() for _, unit in active)
    topic_counts = Counter(unit.lower() for _, unit in topic)
    recognition_counts = Counter(unit.lower() for _, unit in recognition)

    for category, counts in (
        ("Active Core", active_counts),
        ("Topic Vocabulary", topic_counts),
        ("Recognition", recognition_counts),
    ):
        for unit, count in sorted(counts.items()):
            if count > 1:
                errors.append(f"duplicate {category}: '{unit}' ({count})")

    active_set = set(active_counts)
    topic_set = set(topic_counts)
    recognition_set = set(recognition_counts)
    for left_name, left, right_name, right in (
        ("Active Core", active_set, "Topic Vocabulary", topic_set),
        ("Active Core", active_set, "Recognition", recognition_set),
        ("Topic Vocabulary", topic_set, "Recognition", recognition_set),
    ):
        for unit in sorted(left & right):
            errors.append(
                f"category overlap: '{unit}' in {left_name} and {right_name}"
            )

    if len(active) not in ACTIVE_RANGE:
        errors.append(
            f"Active Core count {len(active)} outside "
            f"{ACTIVE_RANGE.start}-{ACTIVE_RANGE.stop - 1}"
        )
    if len(topic) not in TOPIC_RANGE:
        errors.append(
            f"Topic Vocabulary count {len(topic)} outside "
            f"{TOPIC_RANGE.start}-{TOPIC_RANGE.stop - 1}"
        )
    if len(recognition) not in RECOGNITION_RANGE:
        errors.append(
            f"Recognition count {len(recognition)} outside "
            f"{RECOGNITION_RANGE.start}-{RECOGNITION_RANGE.stop - 1}"
        )

    a1_units = parse_a1_units()
    allowed_new_meaning_markers = {
        "change",
        "experience",
        "event",
        "decision",
        "opportunity",
    }
    for chapter, unit in active + topic:
        normalized = unit.lower()
        if normalized in a1_units and normalized not in allowed_new_meaning_markers:
            warnings.append(
                f"chapter {chapter}: exact A1 unit reused as new '{unit}'"
            )

    for chapter in range(1, 12):
        fields = chapter_fields.get(chapter, {})
        active_count = len(fields.get("Active Core", []))
        topic_count = len(fields.get("Topic Vocabulary", []))
        if not 7 <= active_count <= 20:
            warnings.append(
                f"chapter {chapter}: Active Core count is {active_count}"
            )
        if not 12 <= topic_count <= 22:
            warnings.append(
                f"chapter {chapter}: Topic Vocabulary count is {topic_count}"
            )

    print(
        f"chapters={len(sections)} active={len(active)} topic={len(topic)} "
        f"recognition={len(recognition)} planned={len(active) + len(topic)}"
    )
    print(f"errors={len(errors)} warnings={len(warnings)}")
    for error in errors:
        print(f"ERROR: {error}")
    for warning in warnings:
        print(f"WARNING: {warning}")

    if errors:
        print("A2 ledger audit failed.")
        return 1

    print("A2 ledger audit passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
