from __future__ import annotations

import re
from functools import lru_cache


WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")
RU_WORD_RE = re.compile(r"[А-Яа-яЁё][А-Яа-яЁё-]*")
MOTION_WORDS = {"go", "goes", "went", "come", "comes", "came", "walk", "walks", "walked", "return", "returns", "returned", "drive", "drives", "drove"}
SPEECH_WORDS = {"say", "says", "said", "ask", "asks", "asked", "whisper", "whispers", "whispered", "answer", "answers", "answered", "tell", "tells", "told"}
STATE_WORDS = {"be", "is", "are", "am", "was", "were", "seem", "seems", "seemed", "feel", "feels", "felt"}
PERCEPTION_WORDS = {"see", "sees", "saw", "seen", "look", "looks", "looked", "hear", "hears", "heard", "think", "thinks", "thought", "read", "reads"}
CONSUMPTION_WORDS = {"eat", "eats", "ate", "drink", "drinks", "drank", "make", "makes", "made", "cook", "cooks", "cooked"}
SLEEP_REST_WORDS = {"sleep", "sleeps", "slept", "rest", "rests", "rested"}
PAST_WORDS = {"was", "were", "went", "said", "looked", "asked", "whispered", "walked", "slept", "read"}
FUTURE_WORDS = {"will", "shall"}
HABITUAL_HINTS = {"usually", "often", "always", "every"}
TRANSPORT_HINTS = {"drive", "drives", "drove", "car", "bus"}
DIRECTION_HINTS = {"home", "school", "park", "house", "room", "kitchen", "garden"}
PREPOSITION_HINTS = {"to", "into", "at", "in", "on", "toward", "towards"}


def extract_semantic_frame(text: str, segment_type: str) -> dict:
    nlp = _load_spacy_model()
    if nlp is not None:
        frame = _extract_spacy_frame(text, segment_type, nlp)
        if frame.get("predicate_lemma"):
            return frame
    return _extract_heuristic_frame(text, segment_type)


def compare_semantic_frames(source_frame: dict, back_frame: dict, segment_type: str) -> dict:
    flags: list[str] = []
    score = 1.0

    source_class = str(source_frame.get("predicate_class") or "")
    back_class = str(back_frame.get("predicate_class") or "")
    if source_class and back_class and source_class != back_class:
        flags.append("predicate_class_drift")
        score -= 0.4

    source_subject = str(source_frame.get("subject") or "")
    back_subject = str(back_frame.get("subject") or "")
    if source_subject and back_subject and _normalize(source_subject) != _normalize(back_subject):
        flags.append("subject_role_drift")
        score -= 0.3

    source_direction = str(source_frame.get("direction") or "")
    back_direction = str(back_frame.get("direction") or "")
    if source_direction and not back_direction:
        flags.append("direction_lost")
        score -= 0.25

    source_possessive = str(source_frame.get("possessive_owner") or "")
    back_possessive = str(back_frame.get("possessive_owner") or "")
    if source_possessive and source_possessive != back_possessive:
        flags.append("possessive_relation_lost")
        score -= 0.3

    if source_class == "motion" and _is_habitual(source_frame) != _is_habitual(back_frame):
        flags.append("habitual_vs_event_drift")
        score -= 0.25
    if source_class == "motion" and _is_transport(back_frame) and not _is_transport(source_frame):
        flags.append("predicate_class_drift")
        score -= 0.2
    if _tense(source_frame) and _tense(back_frame) and _tense(source_frame) != _tense(back_frame):
        flags.append("tense_shift_structural")
        score -= 0.15

    if segment_type in {"heading_title", "heading_chapter"} and back_frame.get("predicate_lemma"):
        flags.append("bad_short_segment")
        score -= 0.2

    return {
        "frame_preservation_score": max(0.0, round(score, 4)),
        "frame_flags": sorted(set(flags)),
        "source_frame": source_frame,
        "back_frame": back_frame,
    }


def compare_frame_to_target(
    source_frame: dict,
    target_text: str,
    segment_type: str,
) -> dict:
    flags: list[str] = []
    score = 1.0
    target_tokens = [token.lower() for token in RU_WORD_RE.findall(target_text)]
    source_class = str(source_frame.get("predicate_class") or "")
    source_direction = str(source_frame.get("direction") or "").lower()

    if source_class == "motion":
        if any(token.startswith("езд") for token in target_tokens):
            flags.append("target_motion_transport_drift")
            score -= 0.45
        if any(token.startswith("ход") for token in target_tokens):
            flags.append("target_habitual_motion_drift")
            score -= 0.25
        if source_direction == "home" and "домой" not in target_tokens and "дом" not in target_tokens:
            flags.append("target_direction_lost")
            score -= 0.25
    if source_class == "speech" and not any(
        token.startswith(prefix)
        for token in target_tokens
        for prefix in ("говор", "сказ", "спрос", "шепч", "отвеч")
    ):
        flags.append("target_speech_act_lost")
        score -= 0.3
    if source_class == "state" and any(token.startswith(prefix) for token in target_tokens for prefix in ("ид", "пош", "ход", "езд")):
        flags.append("target_state_to_event_drift")
        score -= 0.3
    if segment_type in {"heading_title", "heading_chapter"} and any(token in {"домой", "сюда", "туда"} for token in target_tokens):
        flags.append("target_directional_title")
        score -= 0.5
    return {
        "frame_preservation_score": max(0.0, round(score, 4)),
        "frame_flags": sorted(set(flags)),
        "target_frame": {
            "target_tokens": target_tokens,
        },
    }


def _extract_spacy_frame(text: str, segment_type: str, nlp) -> dict:
    doc = nlp(text)
    predicate = next((token for token in doc if token.pos_ in {"VERB", "AUX"}), None)
    if predicate is None:
        return _extract_heuristic_frame(text, segment_type)
    subject = next((token for token in predicate.children if token.dep_ in {"nsubj", "nsubjpass"}), None)
    obj = next((token for token in predicate.children if token.dep_ in {"dobj", "attr", "oprd", "pobj"}), None)
    direction = next((token for token in predicate.children if token.dep_ in {"prep", "advmod"} and token.text.lower() in {"home", "to", "into", "toward", "towards"}), None)
    if direction is not None and direction.text.lower() == "to":
        pobj = next((token for token in direction.children if token.dep_ == "pobj"), None)
        direction_text = pobj.text if pobj is not None else direction.text
    else:
        direction_text = direction.text if direction is not None else ""
    return {
        "predicate": predicate.text,
        "predicate_lemma": predicate.lemma_.lower(),
        "predicate_class": _predicate_class(predicate.lemma_.lower()),
        "subject": subject.text if subject is not None else "",
        "object": obj.text if obj is not None else "",
        "direction": direction_text,
        "location": "",
        "tense": _normalize_tense_spacy(predicate),
        "aspect_hint": "habitual" if predicate.tag_ in {"VBZ", "VBP"} else "event",
        "polarity": "negative" if any(token.dep_ == "neg" for token in predicate.children) else "positive",
        "modality": "",
        "possessive_owner": _possessive_owner(doc),
    }


def _extract_heuristic_frame(text: str, segment_type: str) -> dict:
    tokens = [token.lower() for token in WORD_RE.findall(text)]
    predicate = next((token for token in tokens if _predicate_class(token) != "other"), "")
    predicate_class = _predicate_class(predicate)
    subject = _heuristic_subject(text) if predicate else ""
    direction = _heuristic_direction(tokens)
    return {
        "predicate": predicate,
        "predicate_lemma": predicate,
        "predicate_class": predicate_class,
        "subject": subject,
        "object": "",
        "direction": direction,
        "location": direction if direction and direction != "home" else "",
        "tense": _heuristic_tense(tokens) if predicate else "",
        "aspect_hint": "habitual" if any(token in HABITUAL_HINTS for token in tokens) else "event",
        "polarity": "negative" if "not" in tokens else "positive",
        "modality": "future" if any(token in FUTURE_WORDS for token in tokens) else "",
        "possessive_owner": _heuristic_possessive(tokens),
    }


def _predicate_class(token: str) -> str:
    if token in MOTION_WORDS:
        return "motion"
    if token in SPEECH_WORDS:
        return "speech"
    if token in STATE_WORDS:
        return "state"
    if token in PERCEPTION_WORDS:
        return "perception"
    if token in CONSUMPTION_WORDS:
        return "consumption"
    if token in SLEEP_REST_WORDS:
        return "sleep_rest"
    return "other"


def _heuristic_subject(text: str) -> str:
    words = WORD_RE.findall(text)
    if not words:
        return ""
    first = words[0]
    if first.lower() in {"he", "she", "they", "it", "we", "i", "you"}:
        return first
    if first[:1].isupper():
        return first
    return ""


def _heuristic_direction(tokens: list[str]) -> str:
    for index, token in enumerate(tokens):
        if token == "home":
            return "home"
        if token in PREPOSITION_HINTS and index + 1 < len(tokens):
            next_token = tokens[index + 1]
            if next_token in DIRECTION_HINTS:
                return next_token
    for token in tokens:
        if token in DIRECTION_HINTS:
            return token
    return ""


def _heuristic_tense(tokens: list[str]) -> str:
    if any(token in FUTURE_WORDS for token in tokens):
        return "future"
    if any(token in PAST_WORDS for token in tokens):
        return "past"
    return "present" if tokens else ""


def _heuristic_possessive(tokens: list[str]) -> str:
    for token in tokens:
        if token in {"his", "her", "their", "my", "your", "our"}:
            return token
    return ""


def _possessive_owner(doc) -> str:
    for token in doc:
        if token.dep_ == "poss" or token.tag_ in {"PRP$", "POS"}:
            return token.text.lower()
    return ""


def _normalize_tense_spacy(token) -> str:
    morph = token.morph.to_dict()
    if morph.get("Tense") == "Past":
        return "past"
    if token.text.lower() in FUTURE_WORDS:
        return "future"
    return "present"


def _is_habitual(frame: dict) -> bool:
    return str(frame.get("aspect_hint") or "") == "habitual"


def _is_transport(frame: dict) -> bool:
    predicate = str(frame.get("predicate_lemma") or "")
    return predicate in TRANSPORT_HINTS


def _tense(frame: dict) -> str:
    return str(frame.get("tense") or "")


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


@lru_cache(maxsize=1)
def _load_spacy_model():
    try:
        import spacy
    except ImportError:
        return None
    try:
        return spacy.load("en_core_web_sm", disable=["ner", "textcat"])
    except OSError:
        return None
