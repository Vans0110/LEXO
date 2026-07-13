from __future__ import annotations

import re

from .tokenization import WORD_RE


def rank_dictionary_translations(
    articles: list[dict],
    *,
    target_segment: str,
) -> list[str]:
    translations = _dedupe(
        [
            translation
            for article in articles
            for translation in article.get("translations", [])
        ]
    )
    target_tokens = _tokens(target_segment)
    if not target_tokens:
        return translations[:12]
    scored = [
        (_target_match_score(translation, target_tokens), -index, translation)
        for index, translation in enumerate(translations)
    ]
    if not any(score > 0 for score, _, _ in scored):
        return translations[:12]
    scored.sort(reverse=True)
    matched = [translation for score, _, translation in scored if score > 0]
    matched_set = set(matched)
    return [*matched, *(item for item in translations if item not in matched_set)][:12]


def _target_match_score(translation: str, target_tokens: list[str]) -> float:
    translation_tokens = _tokens(translation)
    if not translation_tokens:
        return 0.0
    matched = sum(
        _token_matches_any(token, target_tokens)
        for token in translation_tokens
    )
    return matched / len(translation_tokens)


def _token_matches_any(token: str, target_tokens: list[str]) -> bool:
    token_variants = _token_variants(token)
    for target in target_tokens:
        if token_variants & _token_variants(target):
            return True
        if len(token) >= 5 and len(target) >= 5:
            if token[:5] == target[:5] or token.startswith(target[:5]) or target.startswith(token[:5]):
                return True
    return False


def _token_variants(token: str) -> set[str]:
    normalized = _norm(token)
    variants = {normalized}
    if len(normalized) >= 4:
        variants.add(normalized[:5])
    for suffix in (
        "иями", "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими",
        "ая", "яя", "ое", "ее", "ый", "ий", "ой", "ую", "юю", "ом",
        "ем", "ах", "ях", "ов", "ев", "ей", "ью", "ия", "ья", "а", "я",
        "ы", "и", "е", "у", "ю", "ь",
    ):
        if normalized.endswith(suffix) and len(normalized) > len(suffix) + 2:
            variants.add(normalized[:-len(suffix)])
    if normalized.endswith("ец") and len(normalized) > 4:
        variants.add(normalized[:-2])
    return {variant for variant in variants if variant}


def _tokens(text: str) -> list[str]:
    return WORD_RE.findall(_norm(text))


def _dedupe(items: list[str]) -> list[str]:
    result = []
    seen = set()
    for item in items:
        cleaned = re.sub(r"\s+", " ", str(item or "")).strip()
        key = _norm(cleaned)
        if cleaned and key not in seen:
            seen.add(key)
            result.append(cleaned)
    return result


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip().lower().replace("ё", "е")
