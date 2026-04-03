from __future__ import annotations

import re


SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(\[])")


def split_paragraphs(text: str) -> list[str]:
    chunks = [chunk.strip() for chunk in text.split("\n\n")]
    return [chunk for chunk in chunks if chunk]


def split_sentences(paragraph: str) -> list[str]:
    normalized = re.sub(r"\s+", " ", paragraph).strip()
    if not normalized:
        return []

    parts = [part.strip() for part in SENTENCE_SPLIT_RE.split(normalized) if part.strip()]
    return parts or [normalized]
