from __future__ import annotations

import re


WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")
PAST_WORDS = {"was", "were", "went", "said", "looked", "asked", "whispered", "walked", "slept", "read", "made", "cooked", "drove", "returned"}
FUTURE_WORDS = {"will", "shall"}
VERB_STOPWORDS = {"the", "a", "an", "to", "and", "but", "very", "little", "goodnight", "good", "morning"}
VERB_FAMILIES = {
    "say": "speech_plain",
    "says": "speech_plain",
    "said": "speech_plain",
    "tell": "speech_report",
    "tells": "speech_report",
    "told": "speech_report",
    "ask": "speech_question",
    "asks": "speech_question",
    "asked": "speech_question",
    "answer": "speech_answer",
    "answers": "speech_answer",
    "answered": "speech_answer",
    "whisper": "speech_quiet",
    "whispers": "speech_quiet",
    "whispered": "speech_quiet",
    "go": "motion_base",
    "goes": "motion_base",
    "went": "motion_base",
    "come": "motion_base",
    "comes": "motion_base",
    "came": "motion_base",
    "return": "motion_return",
    "returns": "motion_return",
    "returned": "motion_return",
    "drive": "motion_drive",
    "drives": "motion_drive",
    "drove": "motion_drive",
    "make": "prepare_general",
    "makes": "prepare_general",
    "made": "prepare_general",
    "prepare": "prepare_general",
    "prepares": "prepare_general",
    "prepared": "prepare_general",
    "cook": "prepare_cook",
    "cooks": "prepare_cook",
    "cooked": "prepare_cook",
}
NEAR_VERB_PAIRS = {
    ("go", "return"),
    ("goes", "returns"),
    ("went", "returned"),
    ("return", "go"),
    ("returns", "goes"),
    ("returned", "went"),
}
NARROWING_VERB_PAIRS = {
    ("make", "cook"),
    ("makes", "cooks"),
    ("made", "cooked"),
    ("prepare", "cook"),
    ("prepares", "cooks"),
    ("prepared", "cooked"),
    ("say", "whisper"),
    ("says", "whispers"),
    ("said", "whispered"),
}
WRONG_VERB_PAIRS = {
    ("go", "drive"),
    ("goes", "drives"),
    ("went", "drove"),
}


def extract_verb_frame(text: str, segment_type: str) -> dict:
    tokens = [token.lower() for token in WORD_RE.findall(text)]
    verb = next((token for token in tokens if token in VERB_FAMILIES), "")
    object_head = _extract_object_head(tokens, verb)
    direction = "home" if "home" in tokens else ""
    return {
        "verb_surface": verb,
        "verb_lemma": verb,
        "verb_class": VERB_FAMILIES.get(verb, ""),
        "object_head": object_head,
        "direction": direction,
        "polarity": "negative" if "not" in tokens else "positive",
        "aspect_hint": "future" if any(token in FUTURE_WORDS for token in tokens) else ("past" if any(token in PAST_WORDS for token in tokens) else "present"),
    }


def compare_verb_frames(source_frame: dict, back_frame: dict, segment_type: str, strictness: str = "strict") -> dict:
    source_verb = str(source_frame.get("verb_lemma") or "")
    back_verb = str(back_frame.get("verb_lemma") or "")
    source_object = str(source_frame.get("object_head") or "")
    back_object = str(back_frame.get("object_head") or "")
    flags: list[str] = []
    score = 1.0

    if not source_verb or not back_verb:
        return {
            "verb_score": score,
            "verb_flags": flags,
            "source_verb_frame": source_frame,
            "back_verb_frame": back_frame,
        }

    if source_verb == back_verb:
        relation = "exact"
    elif (source_verb, back_verb) in NEAR_VERB_PAIRS:
        relation = "near"
    elif (source_verb, back_verb) in NARROWING_VERB_PAIRS:
        relation = "narrowing"
    elif (source_verb, back_verb) in WRONG_VERB_PAIRS:
        relation = "wrong"
    else:
        source_class = str(source_frame.get("verb_class") or "")
        back_class = str(back_frame.get("verb_class") or "")
        relation = "same_class" if source_class and source_class == back_class else "wrong"

    if relation == "wrong":
        flags.append("verb_lemma_drift")
        score -= 0.45
    elif relation == "narrowing":
        flags.append("verb_meaning_narrowing")
        score -= 0.30 if strictness == "strict" else 0.15
    elif relation == "near":
        score -= 0.05 if strictness == "strict" else 0.0

    if source_object and back_object and source_object != back_object:
        flags.append("verb_argument_drift")
        score -= 0.25

    return {
        "verb_score": max(0.0, round(score, 4)),
        "verb_flags": sorted(set(flags)),
        "source_verb_frame": source_frame,
        "back_verb_frame": back_frame,
    }


def _extract_object_head(tokens: list[str], verb: str) -> str:
    if not verb:
        return ""
    try:
        verb_index = tokens.index(verb)
    except ValueError:
        return ""
    for token in tokens[verb_index + 1 :]:
        if token in VERB_STOPWORDS:
            continue
        return token
    return ""
