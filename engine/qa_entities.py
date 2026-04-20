from __future__ import annotations

import re
from functools import lru_cache


WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")
RU_WORD_RE = re.compile(r"[А-Яа-яЁё][А-Яа-яЁё-]*")
PROPER_NAME_RE = re.compile(r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b")
COMMON_NOUN_HINTS = {
    "moon",
    "sun",
    "book",
    "dog",
    "cat",
    "home",
    "park",
    "breakfast",
    "morning",
    "day",
}
NAME_STOPWORDS = {"the", "a", "an"}


def extract_entities(text: str, segment_type: str) -> dict:
    items: list[dict] = []
    nlp = _load_spacy_model()
    if nlp is not None:
        doc = nlp(text)
        for ent in doc.ents:
            label = str(ent.label_ or "").strip().lower()
            kind = "person_like" if label == "person" else "proper_name_like"
            items.append(
                {
                    "text": ent.text,
                    "normalized": _normalize(ent.text),
                    "kind": kind,
                    "start": int(ent.start_char),
                    "end": int(ent.end_char),
                    "confidence": 0.9,
                    "is_proper_name_like": True,
                }
            )
    if not items:
        items.extend(_extract_heuristic_entities(text, segment_type))
    return {"items": _dedupe_items(items)}


def compare_entities(
    source_entities: dict,
    back_entities: dict,
    source_text: str,
    back_text: str,
    segment_type: str,
) -> dict:
    source_items = [item for item in source_entities.get("items") or [] if item.get("is_proper_name_like")]
    back_items = back_entities.get("items") or []
    back_by_norm = {str(item.get("normalized") or ""): item for item in back_items}
    flags: list[str] = []
    score = 1.0

    if source_items and len(back_items) < len(source_items):
        flags.append("entity_count_mismatch")
        score -= 0.2

    for item in source_items:
        normalized = str(item.get("normalized") or "")
        matched = back_by_norm.get(normalized)
        if matched is None:
            back_tokens = _token_set(back_text)
            if normalized and normalized in back_tokens:
                flags.append("entity_demoted_to_common_noun")
                score -= 0.55
            elif back_tokens & COMMON_NOUN_HINTS:
                flags.append("entity_demoted_to_common_noun")
                score -= 0.55
            else:
                flags.append("entity_missing")
                score -= 0.45
            continue
        if not matched.get("is_proper_name_like"):
            flags.append("entity_demoted_to_common_noun")
            score -= 0.55

    if segment_type in {"heading_title", "heading_chapter", "short_phrase"} and source_items and not back_items:
        flags.append("entity_missing")
        score -= 0.2

    return {
        "entity_preservation_score": max(0.0, round(score, 4)),
        "entity_flags": sorted(set(flags)),
        "source_entities": source_items,
        "back_entities": back_items,
    }


def compare_entities_to_target(
    source_entities: dict,
    target_text: str,
    segment_type: str,
) -> dict:
    source_items = [item for item in source_entities.get("items") or [] if item.get("is_proper_name_like")]
    if not source_items:
        return {
            "entity_preservation_score": 1.0,
            "entity_flags": [],
            "target_entities": [],
        }
    target_items = _extract_target_named_tokens(target_text)
    flags: list[str] = []
    score = 1.0

    if len(target_items) < len(source_items):
        flags.append("target_entity_count_mismatch")
        score -= 0.2
    if not target_items:
        flags.append("target_entity_missing")
        score -= 0.45

    return {
        "entity_preservation_score": max(0.0, round(score, 4)),
        "entity_flags": sorted(set(flags)),
        "target_entities": target_items,
    }


def _extract_heuristic_entities(text: str, segment_type: str) -> list[dict]:
    items: list[dict] = []
    for match in PROPER_NAME_RE.finditer(text):
        token_text = match.group(0)
        if _should_skip_match(token_text, text, match.start()):
            continue
        items.append(
            {
                "text": token_text,
                "normalized": _normalize(token_text),
                "kind": "proper_name_like",
                "start": match.start(),
                "end": match.end(),
                "confidence": 0.65,
                "is_proper_name_like": True,
            }
        )
    if not items and segment_type in {"heading_title", "heading_chapter"}:
        title_words = [word for word in WORD_RE.findall(text) if word and word[0].isupper()]
        if title_words and len(title_words) <= 4:
            title_text = " ".join(title_words)
            items.append(
                {
                    "text": title_text,
                    "normalized": _normalize(title_text),
                    "kind": "title_like",
                    "start": 0,
                    "end": len(text),
                    "confidence": 0.4,
                    "is_proper_name_like": True,
                }
            )
    return items


def _should_skip_match(token_text: str, text: str, start_index: int) -> bool:
    normalized = _normalize(token_text)
    if not normalized:
        return True
    if normalized in NAME_STOPWORDS:
        return True
    if normalized in COMMON_NOUN_HINTS and start_index == 0:
        return True
    prefix = text[:start_index].rstrip()
    if not prefix:
        suffix_words = WORD_RE.findall(text[token_text.__len__():])
        return len(suffix_words) <= 2
    return prefix.endswith((".", "!", "?", ":"))


def _dedupe_items(items: list[dict]) -> list[dict]:
    seen: set[tuple[str, int, int]] = set()
    unique: list[dict] = []
    for item in items:
        key = (str(item.get("normalized") or ""), int(item.get("start") or 0), int(item.get("end") or 0))
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    return unique


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def _token_set(text: str) -> set[str]:
    return {token.lower() for token in WORD_RE.findall(text)}


def _extract_target_named_tokens(text: str) -> list[dict]:
    items: list[dict] = []
    for match in RU_WORD_RE.finditer(text):
        token = match.group(0)
        if not token[:1].isupper():
            continue
        items.append(
            {
                "text": token,
                "normalized": _normalize(token),
                "kind": "target_name_like",
                "start": match.start(),
                "end": match.end(),
                "confidence": 0.5,
                "is_proper_name_like": True,
            }
        )
    return _dedupe_items(items)


@lru_cache(maxsize=1)
def _load_spacy_model():
    try:
        import spacy
    except ImportError:
        return None
    try:
        return spacy.load("en_core_web_sm", disable=["textcat"])
    except OSError:
        return None
