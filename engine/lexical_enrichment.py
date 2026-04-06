from __future__ import annotations

import json
from functools import lru_cache


GRAMMAR_POS = {"DET", "ADP", "PART", "AUX", "PRON", "CCONJ", "SCONJ"}
GRAMMAR_HINTS = {
    "the": "указывает на конкретный объект",
    "a": "показывает один из возможных объектов",
    "an": "показывает один из возможных объектов",
    "of": "связывает слово с другим словом",
    "in": "показывает положение или место",
    "on": "показывает положение на поверхности",
    "at": "указывает на точку или момент",
    "to": "показывает направление или связь с действием",
    "that": "связывает часть мысли или указывает на объект",
    "for": "показывает цель или назначение",
    "with": "показывает совместность или инструмент",
    "can": "показывает возможность или умение",
    "could": "показывает возможность, вежливость или условность",
    "may": "показывает возможность или разрешение",
    "might": "показывает слабую возможность",
    "must": "показывает необходимость",
    "should": "показывает совет или ожидание",
    "has": "помогает собрать грамматическую форму или показывает обладание",
    "have": "помогает собрать грамматическую форму или показывает обладание",
    "had": "помогает собрать грамматическую форму или показывает прошлое обладание",
    "do": "помогает собрать вопрос, отрицание или усиление",
    "does": "помогает собрать вопрос, отрицание или усиление",
    "did": "помогает собрать вопрос, отрицание или усиление в прошлом",
    "been": "часть составной формы",
    "being": "часть составной формы",
    "his": "показывает принадлежность",
    "her": "показывает принадлежность",
    "their": "показывает принадлежность",
    "my": "показывает принадлежность",
    "your": "показывает принадлежность",
    "will": "показывает будущее действие",
    "would": "показывает условность или мягкое намерение",
    "shall": "показывает намерение или будущее действие",
    "is": "связывает подлежащее с признаком или состоянием",
    "am": "связывает подлежащее с признаком или состоянием",
    "are": "связывает подлежащее с признаком или состоянием",
    "was": "связывает подлежащее с признаком или состоянием",
    "were": "связывает подлежащее с признаком или состоянием",
}
DIRECT_MEANINGS = {
    "i": "я",
    "you": "ты / вы",
    "he": "он",
    "she": "она",
    "it": "это / оно",
    "we": "мы",
    "they": "они",
    "me": "меня / мне",
    "him": "его / ему",
    "her": "её / ей",
    "us": "нас / нам",
    "them": "их / им",
    "my": "мой / моя / моё",
    "your": "твой / ваш",
    "his": "его",
    "their": "их",
    "our": "наш",
    "this": "этот / это",
    "that": "тот / это",
    "these": "эти",
    "those": "те",
    "is": "есть",
    "am": "есть",
    "are": "есть / являются",
    "was": "был / была",
    "were": "были",
    "be": "быть",
    "been": "был / была / было",
    "being": "будучи / находясь",
    "has": "имеет / помогает собрать форму",
    "have": "иметь / помогать собрать форму",
    "had": "имел / имела / помогал собрать форму",
    "can": "мочь",
    "could": "мог / могла / мог бы",
    "may": "мочь / можно",
    "might": "мог бы",
    "must": "должен / нужно",
    "should": "следует / стоит",
    "at": "в",
    "in": "в",
    "on": "на",
    "of": "из / о / принадлежность",
    "to": "к / чтобы",
    "for": "для",
    "with": "с",
    "am_time": "утра",
    "pm_time": "вечера / дня",
}
IRREGULAR_LEMMAS = {
    "ran": "run",
    "went": "go",
    "gone": "go",
    "took": "take",
    "taken": "take",
    "saw": "see",
    "seen": "see",
    "came": "come",
    "woke": "wake",
    "woken": "wake",
    "got": "get",
    "gotten": "get",
    "was": "be",
    "were": "be",
    "is": "be",
    "are": "be",
    "am": "be",
    "been": "be",
    "being": "be",
    "has": "have",
    "had": "have",
    "did": "do",
    "done": "do",
    "could": "can",
}
COMMON_VERB_WORDS = {
    "run",
    "swim",
    "go",
    "take",
    "look",
    "come",
    "get",
    "wake",
    "sit",
    "say",
    "make",
    "know",
    "think",
    "see",
    "want",
    "need",
    "like",
    "work",
    "call",
    "try",
    "ask",
    "play",
    "move",
    "live",
    "turn",
    "start",
    "show",
    "hear",
    "walk",
    "talk",
    "help",
    "seem",
    "feel",
    "leave",
    "put",
    "bring",
    "keep",
    "let",
    "begin",
}
COMMON_NOUN_WORDS = {
    "morning",
    "evening",
    "ceiling",
    "building",
    "king",
    "thing",
}
MODAL_WORDS = {"can", "could", "may", "might", "must", "shall", "should", "will", "would"}
AUXILIARY_WORDS = {
    "am",
    "is",
    "are",
    "was",
    "were",
    "be",
    "been",
    "being",
    "have",
    "has",
    "had",
    "do",
    "does",
    "did",
}
PRONOUN_WORDS = {
    "i",
    "you",
    "he",
    "she",
    "it",
    "we",
    "they",
    "me",
    "him",
    "her",
    "us",
    "them",
    "my",
    "your",
    "his",
    "their",
    "our",
    "this",
    "that",
    "these",
    "those",
}
SUBORDINATOR_WORDS = {"that", "if", "because", "when", "while", "although", "though"}
PHRASE_PATTERNS = [
    ("in", "front", "of"),
    ("take", "off"),
    ("took", "off"),
    ("taken", "off"),
    ("wake", "up"),
    ("wakes", "up"),
    ("woke", "up"),
    ("get", "up"),
    ("gets", "up"),
    ("got", "up"),
    ("sit", "down"),
    ("sits", "down"),
    ("sat", "down"),
    ("come", "back"),
    ("comes", "back"),
    ("came", "back"),
    ("go", "out"),
    ("goes", "out"),
    ("went", "out"),
    ("look", "out"),
    ("looks", "out"),
    ("looked", "out"),
]


@lru_cache(maxsize=1)
def _load_spacy_model():
    try:
        import spacy
    except ImportError:
        return None
    for model_name in ("en_core_web_sm",):
        try:
            return spacy.load(model_name, disable=["ner", "textcat"])
        except OSError:
            continue
    return None


def enrich_words(words: list[dict]) -> list[dict]:
    if not words:
        return words

    annotations = _annotate_with_spacy(words) or [_heuristic_annotation(word) for word in words]
    _apply_context_overrides(words, annotations)
    phrase_groups = _detect_phrase_groups(words)

    for index, word in enumerate(words):
        annotation = annotations[index]
        lexical_unit_type = _resolve_lexical_unit_type(index, word, annotation, phrase_groups)
        lexical_unit_id = phrase_groups.get(index)
        if lexical_unit_id is None:
            lexical_unit_id = f"{word['id']}:lex"
        word["lemma"] = annotation["lemma"]
        word["pos"] = annotation["pos"]
        word["morph"] = json.dumps(annotation["morph"], ensure_ascii=False, sort_keys=True)
        word["lexical_unit_id"] = lexical_unit_id
        word["lexical_unit_type"] = lexical_unit_type
    return words


def grammar_hint_for_word(word: dict) -> str | None:
    normalized = str(_mapping_get(word, "normalized_text") or _mapping_get(word, "text") or _mapping_get(word, "surface_text") or "").lower()
    pos = str(_mapping_get(word, "pos") or "").upper()
    if normalized in {"he", "she", "it", "they", "we", "i", "you", "is", "am", "are", "was", "were"}:
        return None
    if pos in GRAMMAR_POS and normalized in GRAMMAR_HINTS:
        return GRAMMAR_HINTS[normalized]
    if pos == "DET":
        return "делает объект более конкретным"
    if pos == "ADP":
        return "связывает слово с местом, временем или отношением"
    if pos in {"AUX", "PART"}:
        return "помогает собрать грамматическую форму"
    if pos in {"PRON", "CCONJ", "SCONJ"}:
        return "служебное слово для связи или указания"
    return None


def direct_meaning_for_word(word: dict) -> str | None:
    normalized = str(_mapping_get(word, "normalized_text") or _mapping_get(word, "text") or _mapping_get(word, "surface_text") or "").lower()
    text = str(_mapping_get(word, "text") or _mapping_get(word, "surface_text") or "")
    if text.upper() == "AM":
        return DIRECT_MEANINGS["am_time"]
    if text.upper() == "PM":
        return DIRECT_MEANINGS["pm_time"]
    return DIRECT_MEANINGS.get(normalized)


def morph_label_for_word(word: dict) -> str | None:
    raw_morph = str(_mapping_get(word, "morph") or "")
    morph_data = _parse_morph(raw_morph)
    if morph_data.get("Tense") == "Past":
        return "прошедшее"
    if morph_data.get("VerbForm") == "Part":
        return "используется в составной форме"
    if morph_data.get("VerbForm") == "Ger" or raw_morph == "Gerund":
        return "сейчас длится"
    if morph_data.get("VerbForm") == "Inf":
        return "базовая форма"
    return None


def build_unit_surface_text(words: list[dict]) -> str:
    return " ".join(str(_mapping_get(word, "text") or _mapping_get(word, "surface_text") or "").strip() for word in words).strip()


def build_unit_lemma_text(words: list[dict]) -> str:
    return " ".join(str(_mapping_get(word, "lemma") or _mapping_get(word, "normalized_text") or "").strip() for word in words).strip()


def _annotate_with_spacy(words: list[dict]) -> list[dict] | None:
    model = _load_spacy_model()
    if model is None:
        return None
    doc = model(" ".join(str(word["surface_text"]) for word in words))
    tokens = [token for token in doc if not token.is_space]
    if len(tokens) != len(words):
        return None
    return [
        {
            "lemma": token.lemma_.lower() or str(words[index]["normalized_text"]),
            "pos": token.pos_.upper(),
            "morph": _normalize_morph_dict(token.morph.to_dict()),
        }
        for index, token in enumerate(tokens)
    ]


def _heuristic_annotation(word: dict) -> dict:
    text = str(word["surface_text"])
    normalized = str(word["normalized_text"])
    pos = _heuristic_pos(normalized)
    morph: dict[str, str] = {}
    if normalized in COMMON_NOUN_WORDS:
        pass
    elif normalized.endswith("ing"):
        morph["VerbForm"] = "Ger"
    elif normalized in {"taken", "seen", "gone", "been", "done", "woken", "gotten"}:
        morph["VerbForm"] = "Part"
    elif normalized.endswith("ed") or normalized in {"ran", "went", "took", "came", "woke", "got", "was", "were", "did", "had"}:
        morph["Tense"] = "Past"
    elif pos == "VERB":
        morph["VerbForm"] = "Inf"
    return {
        "lemma": _heuristic_lemma(text, normalized),
        "pos": pos,
        "morph": morph,
    }


def _heuristic_pos(normalized: str) -> str:
    if normalized in {"the", "a", "an"}:
        return "DET"
    if normalized in {"in", "on", "of", "to", "for", "with", "at", "from", "by", "before", "after"}:
        return "ADP"
    if normalized in MODAL_WORDS:
        return "AUX"
    if normalized in AUXILIARY_WORDS:
        return "AUX"
    if normalized in {"and", "or", "but"}:
        return "CCONJ"
    if normalized in SUBORDINATOR_WORDS:
        return "SCONJ"
    if normalized in PRONOUN_WORDS:
        return "PRON"
    if normalized in COMMON_NOUN_WORDS:
        return "NOUN"
    if normalized in COMMON_VERB_WORDS or normalized.endswith("ing") or normalized.endswith("ed") or normalized in IRREGULAR_LEMMAS:
        return "VERB"
    return "NOUN"


def _heuristic_lemma(text: str, normalized: str) -> str:
    if normalized in IRREGULAR_LEMMAS:
        return IRREGULAR_LEMMAS[normalized]
    if normalized in COMMON_NOUN_WORDS:
        return normalized
    if normalized.endswith("ing") and len(normalized) > 4:
        base = normalized[:-3]
        if len(base) > 2 and base[-1] == base[-2]:
            return base[:-1]
        return base
    if normalized.endswith("ed") and len(normalized) > 3:
        base = normalized[:-2]
        if len(base) > 2 and base[-1] == base[-2]:
            return base[:-1]
        return base
    if normalized.endswith("s") and len(normalized) > 3 and text[0:1].islower():
        return normalized[:-1]
    return normalized


def _detect_phrase_groups(words: list[dict]) -> dict[int, str]:
    phrase_groups: dict[int, str] = {}
    normalized_words = [str(word["normalized_text"]).lower() for word in words]
    index = 0
    while index < len(words):
        matched = None
        for pattern in PHRASE_PATTERNS:
            end_index = index + len(pattern)
            if tuple(normalized_words[index:end_index]) == pattern:
                matched = pattern
                break
        if matched is None:
            index += 1
            continue
        phrase_id = f"{words[index]['id']}:phrase"
        for offset in range(len(matched)):
            phrase_groups[index + offset] = phrase_id
        index += len(matched)
    return phrase_groups


def _resolve_lexical_unit_type(index: int, word: dict, annotation: dict, phrase_groups: dict[int, str]) -> str:
    if index in phrase_groups:
        return "PHRASE"
    pos = annotation["pos"]
    normalized = str(word["normalized_text"]).lower()
    if int(word.get("is_function_word", 0)) == 1:
        return "GRAMMAR"
    if pos in GRAMMAR_POS:
        return "GRAMMAR"
    return "LEXICAL"


def _apply_context_overrides(words: list[dict], annotations: list[dict]) -> None:
    normalized_words = [str(word["normalized_text"]).lower() for word in words]
    for index, normalized in enumerate(normalized_words):
        previous_word = normalized_words[index - 1] if index > 0 else ""
        next_word = normalized_words[index + 1] if index + 1 < len(normalized_words) else ""
        annotation = annotations[index]

        if normalized == "can" and previous_word in {"a", "an", "the"}:
            annotation["pos"] = "NOUN"
            annotation["morph"] = {}

        if normalized == "that":
            if next_word and annotations[index + 1]["pos"] in {"NOUN", "ADJ"}:
                annotation["pos"] = "DET"
            else:
                annotation["pos"] = "PRON"

        if normalized == "to" and next_word and annotations[index + 1]["pos"] == "VERB":
            annotation["pos"] = "PART"

        if normalized in MODAL_WORDS and next_word and annotations[index + 1]["pos"] != "VERB":
            annotation["pos"] = "NOUN"
            annotation["morph"] = {}

        if normalized in {"has", "have", "had"} and next_word and annotations[index + 1]["pos"] in {"VERB", "AUX"}:
            annotation["pos"] = "AUX"

        if normalized in {"been", "being"}:
            annotation["pos"] = "AUX"

        if normalized == "off" and previous_word in {"take", "takes", "took", "taken", "take"}:
            annotation["pos"] = "PART"


def _normalize_morph_dict(morph: dict[str, object]) -> dict[str, str]:
    normalized: dict[str, str] = {}
    for key, value in morph.items():
        if isinstance(value, (list, tuple)):
            normalized[key] = str(value[0]) if value else ""
        else:
            normalized[key] = str(value)
    return normalized


def _parse_morph(raw_morph: str) -> dict[str, str]:
    if not raw_morph:
        return {}
    try:
        parsed = json.loads(raw_morph)
    except json.JSONDecodeError:
        return {"VerbForm": raw_morph}
    if not isinstance(parsed, dict):
        return {}
    return {str(key): str(value) for key, value in parsed.items()}


def _mapping_get(mapping: object, key: str, default: object | None = None) -> object | None:
    if hasattr(mapping, "get"):
        try:
            return mapping.get(key, default)
        except TypeError:
            pass
    try:
        return mapping[key]  # type: ignore[index]
    except Exception:
        return default
