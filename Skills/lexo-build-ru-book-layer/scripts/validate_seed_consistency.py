from __future__ import annotations

from typing import Any

import re


TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def block_components_cover_source(block: dict[str, Any]) -> bool:
    tokenize = lambda value: [
        match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or ""))
    ]
    components = block.get("components") or []
    actual = [
        token
        for component in components
        if isinstance(component, dict)
        for token in tokenize(component.get("source"))
    ]
    return actual == tokenize(block.get("source"))


def normalized_word_map(
    items: object,
) -> dict[str, tuple[tuple[str, ...], str, str, str]]:
    result: dict[str, tuple[tuple[str, ...], str, str, str]] = {}
    if isinstance(items, dict):
        iterable = []
        for key, value in items.items():
            if not isinstance(value, dict) or "|" not in str(key):
                continue
            lemma, pos = str(key).rsplit("|", 1)
            iterable.append({**value, "lemma": lemma, "pos": pos})
    else:
        iterable = items or []
    for item in iterable:
        if not isinstance(item, dict):
            continue
        key = f"{clean(item.get('lemma')).lower()}|{clean(item.get('pos')).upper()}"
        values = tuple(
            sorted(
                {
                    clean(value).casefold()
                    for value in item.get("translations") or []
                    if clean(value)
                }
            )
        )
        result[key] = (
            values,
            clean(item.get("dictionary_translation")).casefold(),
            clean(item.get("dictionary_translation_source")).casefold(),
            clean(item.get("empty_reason")).casefold(),
        )
    return result


def normalized_block_map(items: object) -> dict[str, str]:
    return {
        clean(item.get("source")).casefold(): clean(
            item.get("translation")
        ).casefold()
        for item in items or []
        if isinstance(item, dict) and clean(item.get("source"))
    }
