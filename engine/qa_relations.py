from __future__ import annotations

import re


SOURCE_POSSESSIVE_RE = re.compile(r"\b(his|her|my|their|our|your)\s+([A-Za-z][A-Za-z'-]*)\b", flags=re.IGNORECASE)
SOURCE_BODY_PART_HINTS = {"leg", "legs", "hand", "hands", "arm", "arms", "head", "shoulder", "shoulders", "knee", "knees"}
SOURCE_OWNED_OBJECT_HINTS = {
    "book",
    "books",
    "bag",
    "bags",
    "coat",
    "coats",
    "hat",
    "hats",
    "shoe",
    "shoes",
    "cat",
    "dog",
    "food",
    "breakfast",
    "lunch",
    "dinner",
    "tail",
}
TARGET_OWNER_MARKERS = (
    "его",
    "ее",
    "её",
    "их",
    "мой",
    "моя",
    "мое",
    "моё",
    "мои",
    "твой",
    "твоя",
    "твое",
    "твоё",
    "твои",
    "наш",
    "наша",
    "наше",
    "наши",
    "свой",
    "своя",
    "свою",
    "свои",
    "своё",
    "своем",
    "своём",
    "своего",
    "своей",
    "у него",
    "у неё",
    "у нее",
)
TARGET_BODY_PART_HINTS = {
    "нога",
    "ноги",
    "ногах",
    "рука",
    "руки",
    "руках",
    "голова",
    "голове",
    "голову",
    "плечо",
    "плечах",
    "колено",
    "коленях",
}
TARGET_SOCIAL_RELATION_HINTS = {
    "друг",
    "друга",
    "другу",
    "друзья",
    "подруга",
    "подругу",
    "подруги",
    "приятель",
    "приятеля",
    "знакомый",
    "знакомую",
}
TARGET_PET_FOOD_HINTS = {"корм", "корма", "еду", "еда"}


def evaluate_possessive_relations(source_text: str, target_text: str, segment_type: str) -> dict:
    matches = list(SOURCE_POSSESSIVE_RE.finditer(source_text))
    if not matches:
        return {"relation_score": 1.0, "relation_flags": []}

    target_lower = target_text.lower()
    target_tokens = _ru_tokens(target_text)
    has_owner_marker = any(marker in target_lower for marker in TARGET_OWNER_MARKERS)
    flags: list[str] = []
    score = 1.0

    for match in matches:
        possessed = str(match.group(2) or "").strip().lower()
        if has_owner_marker:
            continue
        if _is_social_relation_case(possessed, target_tokens):
            continue
        if _requires_owner_marker(possessed, target_tokens, segment_type):
            flags.append("target_possessive_relation_lost")
            score -= 0.45
            break

    return {
        "relation_score": max(0.0, round(score, 4)),
        "relation_flags": sorted(set(flags)),
    }


def _is_social_relation_case(possessed: str, target_tokens: list[str]) -> bool:
    if possessed not in {"friend", "friends"}:
        return False
    return any(token in TARGET_SOCIAL_RELATION_HINTS for token in target_tokens)


def _requires_owner_marker(possessed: str, target_tokens: list[str], segment_type: str) -> bool:
    if possessed in SOURCE_BODY_PART_HINTS:
        return True
    if possessed in SOURCE_OWNED_OBJECT_HINTS:
        return True
    if any(token in TARGET_BODY_PART_HINTS for token in target_tokens):
        return True
    if possessed == "food" and any(token in TARGET_PET_FOOD_HINTS for token in target_tokens):
        return True
    return segment_type in {"simple_action", "quote_dialogue"} and possessed in {"cat", "dog", "food", "tail"}


def _ru_tokens(text: str) -> list[str]:
    return re.findall(r"[А-Яа-яЁё-]+", text.lower())
