from __future__ import annotations

import re

from ..tokenization import WORD_RE


_MULTISPACE_RE = re.compile(r"\s+")


def normalize_text_for_tts(text: str) -> str:
    normalized = (text or "").replace("\r\n", "\n").replace("\r", "\n")
    normalized = normalized.replace("“", '"').replace("”", '"').replace("’", "'")
    normalized = normalized.replace("—", ", ").replace("–", ", ")
    normalized = normalized.replace("\n", " ")
    normalized = _MULTISPACE_RE.sub(" ", normalized).strip()
    return normalized


def build_slow_synthesis_text(text: str, dot_count: int = 10) -> str:
    normalized = normalize_text_for_tts(text)
    words = [match.group(0) for match in WORD_RE.finditer(normalized)]
    if not words:
        return normalized
    dots = "." * max(1, dot_count)
    return " ".join(f"{word}{dots}" for word in words)
