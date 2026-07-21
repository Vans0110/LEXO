from __future__ import annotations

import re
from typing import Any

from .tokenization import WORD_RE


def mt_dictionary_translations(
    translator: Any,
    inputs: list[str],
    *,
    limit: int = 3,
) -> list[str]:
    if translator is None or not hasattr(translator, "translate_alternatives"):
        return []
    candidates = []
    for text in inputs:
        if not text:
            continue
        candidates.extend(
            translator.translate_alternatives(text, max_alternatives=10)
        )
        cleaned = _unique_candidates(candidates)
        if len(cleaned) >= limit:
            return cleaned[:limit]
    return _unique_candidates(candidates)[:limit]


def _unique_candidates(candidates: list[str]) -> list[str]:
    result = []
    seen = set()
    for candidate in candidates:
        cleaned = re.sub(r"\s+", " ", str(candidate or "")).strip()
        cleaned = cleaned.strip(" \t\r\n.,;:!?-–—()[]{}\"'")
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        if not cleaned or re.search(r"[A-Za-z]", cleaned):
            continue
        tokens = [_norm(token) for token in WORD_RE.findall(cleaned)]
        if any(left == right for left, right in zip(tokens, tokens[1:])):
            continue
        key = _norm(cleaned).strip(" \t\r\n.,;:!?-–—")
        if not key or key in seen:
            continue
        seen.add(key)
        result.append(cleaned)
    return result


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip().lower().replace("ё", "е")
