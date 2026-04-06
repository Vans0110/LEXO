from __future__ import annotations

import re


_MULTISPACE_RE = re.compile(r"\s+")
_TIME_RE = re.compile(r"\b(\d{1,2}):(\d{2})\s*([AaPp][Mm])\b")
_CHAPTER_RE = re.compile(r"\b(Chapter)\s+(\d+)\b")

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
