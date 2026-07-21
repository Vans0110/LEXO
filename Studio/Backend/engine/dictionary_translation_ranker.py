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
    for target in target_tokens:
        if token == target:
            return True
        shortest = min(len(token), len(target))
        common = 0
        while common < shortest and token[common] == target[common]:
            common += 1
        if common >= 5 and common / shortest >= 0.6:
            return True
    return False


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
