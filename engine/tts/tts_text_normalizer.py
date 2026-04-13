from __future__ import annotations

import re


_MULTISPACE_RE = re.compile(r"\s+")
_TIME_RE = re.compile(r"\b(\d{1,2}):(\d{2})\s*([AaPp][Mm])\b")
_CHAPTER_RE = re.compile(r"\b(Chapter)\s+(\d+)\b")
_WORD_RE = re.compile(r"[A-Za-zА-Яа-яЁё0-9]+(?:[-'][A-Za-zА-Яа-яЁё0-9]+)*")

_ARTICLE_WORDS = {"a", "an", "the"}
_COPULA_WORDS = {"am", "are", "is", "was", "were"}
_PRONOUN_WORDS = {"i", "you", "he", "she", "we", "they", "it"}
_ADJECTIVE_LIKE_WORDS = {
    "beautiful",
    "big",
    "blue",
    "bright",
    "brown",
    "good",
    "happy",
    "little",
    "new",
    "red",
    "small",
    "sunny",
    "tired",
    "very",
    "white",
}
_NOUN_LIKE_WORDS = {
    "afternoon",
    "book",
    "breakfast",
    "cat",
    "chapter",
    "day",
    "dog",
    "flowers",
    "friend",
    "garden",
    "home",
    "kitchen",
    "legs",
    "luna",
    "morning",
    "park",
    "shoes",
    "sofa",
    "sun",
    "t-shirt",
    "time",
    "trees",
    "window",
}

_NUMBER_WORDS = {
    0: "zero",
    1: "one",
    2: "two",
    3: "three",
    4: "four",
    5: "five",
    6: "six",
    7: "seven",
    8: "eight",
    9: "nine",
    10: "ten",
    11: "eleven",
    12: "twelve",
    13: "thirteen",
    14: "fourteen",
    15: "fifteen",
    16: "sixteen",
    17: "seventeen",
    18: "eighteen",
    19: "nineteen",
    20: "twenty",
}


def normalize_text_for_tts(text: str) -> str:
    normalized = (text or "").replace("\r\n", "\n").replace("\r", "\n")
    normalized = normalized.replace("“", '"').replace("”", '"').replace("’", "'")
    normalized = normalized.replace("—", ", ").replace("–", ", ")
    normalized = normalized.replace("\n", " ")
    normalized = _TIME_RE.sub(_expand_time, normalized)
    normalized = _CHAPTER_RE.sub(_expand_chapter, normalized)
    normalized = _MULTISPACE_RE.sub(" ", normalized).strip()
    return normalized


def build_slow_synthesis_text(text: str, dot_count: int = 10) -> str:
    normalized = normalize_text_for_tts(text)
    words = [match.group(0) for match in _WORD_RE.finditer(normalized)]
    if not words:
        return normalized
    blocks = _build_slow_blocks(words)
    dots = "." * max(1, dot_count)
    return " ".join(f"{block}{dots}" for block in blocks)


def _build_slow_blocks(words: list[str]) -> list[str]:
    blocks: list[str] = []
    index = 0
    while index < len(words):
        end_index = (
            _match_fixed_phrase(words, index)
            or _match_pronoun_be(words, index)
            or _match_article_phrase(words, index)
            or index
        )
        blocks.append(" ".join(words[index : end_index + 1]))
        index = end_index + 1
    return blocks


def _match_fixed_phrase(words: list[str], index: int) -> int | None:
    patterns = (
        ("good", "morning"),
        ("how", "are", "you"),
        ("thank", "you"),
        ("in", "the", "afternoon"),
    )
    normalized = [word.lower() for word in words]
    for pattern in patterns:
        end_index = index + len(pattern)
        if end_index > len(words):
            continue
        if tuple(normalized[index:end_index]) == pattern:
            return end_index - 1
    return None


def _match_pronoun_be(words: list[str], index: int) -> int | None:
    if index + 1 >= len(words):
        return None
    first = words[index].lower()
    second = words[index + 1].lower()
    if first in _PRONOUN_WORDS and second in _COPULA_WORDS:
        return index + 1
    return None


def _match_article_phrase(words: list[str], index: int) -> int | None:
    if index + 1 >= len(words):
        return None
    if words[index].lower() not in _ARTICLE_WORDS:
        return None
    scan = index + 1
    while scan < len(words) and not _is_noun_like(words[scan]) and _is_adjective_like(words[scan]):
        scan += 1
    if scan < len(words) and _is_noun_like(words[scan]):
        return scan
    return None


def _is_adjective_like(word: str) -> bool:
    normalized = word.lower()
    if normalized in _ADJECTIVE_LIKE_WORDS:
        return True
    return normalized.endswith(("y", "ful", "ous", "ive"))


def _is_noun_like(word: str) -> bool:
    normalized = word.lower()
    if normalized in _NOUN_LIKE_WORDS:
        return True
    if normalized.endswith(("tion", "ment", "ness", "ship", "ity")):
        return True
    if normalized.endswith("s") and len(normalized) > 3:
        return True
    return False


def _expand_time(match: re.Match[str]) -> str:
    hour = int(match.group(1))
    minute = match.group(2)
    suffix_raw = match.group(3).lower()
    suffix = "a.m." if suffix_raw == "am" else "p.m."
    hour_text = _number_to_words(hour)
    if minute == "00":
        return f"{hour_text} {suffix}"
    minute_value = int(minute)
    minute_text = _number_to_words(minute_value)
    return f"{hour_text} {minute_text} {suffix}"


def _expand_chapter(match: re.Match[str]) -> str:
    label = match.group(1)
    number = int(match.group(2))
    return f"{label} {_number_to_words(number)}"


def _number_to_words(value: int) -> str:
    if value in _NUMBER_WORDS:
        return _NUMBER_WORDS[value]
    if 20 < value < 100:
        tens = value // 10 * 10
        units = value % 10
        tens_word = {
            20: "twenty",
            30: "thirty",
            40: "forty",
            50: "fifty",
            60: "sixty",
            70: "seventy",
            80: "eighty",
            90: "ninety",
        }.get(tens, str(value))
        if units == 0:
            return tens_word
        return f"{tens_word}-{_NUMBER_WORDS.get(units, str(units))}"
    return str(value)
