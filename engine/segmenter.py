from __future__ import annotations

import re


SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(\[])")
CHAPTER_INLINE_RE = re.compile(
    r"^\s*(?P<heading>Chapter\s+(?P<number>\d+|one|two|three|four|five|six|seven|eight|nine|ten)(?::\s*[^,.!?]+)?)\s+"
    r"(?P<time>At\s+\d{1,2}:\d{2}\s*(?:AM|PM)|In\s+the\s+(?:morning|afternoon|evening))"
    r"(?P<tail>[, ]+.+)$",
    flags=re.IGNORECASE,
)
CHAPTER_ONLY_RE = re.compile(
    r"^\s*Chapter\s+(?P<number>\d+|one|two|three|four|five|six|seven|eight|nine|ten)\.?\s*$",
    flags=re.IGNORECASE,
)
CHAPTER_TITLE_RE = re.compile(
    r"^\s*Chapter\s+(?P<number>\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s*:\s*(?P<title>.+?)\s*$",
    flags=re.IGNORECASE,
)
TIME_LEADING_RE = re.compile(
    r"^\s*(?P<time>At\s+\d{1,2}:\d{2}\s*(?:AM|PM)|In\s+the\s+(?:morning|afternoon|evening))(?P<tail>[, ]+.+)$",
    flags=re.IGNORECASE,
)

NUMBER_WORDS = {
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9",
    "ten": "10",
}


def split_paragraphs(text: str) -> list[str]:
    chunks = [chunk.strip() for chunk in text.split("\n\n")]
    return [chunk for chunk in chunks if chunk]


def split_sentences(paragraph: str) -> list[str]:
    return [item["source_text"] for item in split_study_segments(paragraph)]


def split_study_segments(paragraph: str) -> list[dict]:
    normalized = re.sub(r"\s+", " ", paragraph).strip()
    if not normalized:
        return []

    raw_lines = [line.strip() for line in paragraph.splitlines() if line.strip()]
    if raw_lines:
        segments: list[dict] = []
        for raw_line in raw_lines:
            segments.extend(_split_line_to_segments(raw_line))
        if segments:
            return segments

    parts = [part.strip() for part in SENTENCE_SPLIT_RE.split(normalized) if part.strip()]
    return [_segment_payload(part, "simple_action") for part in (parts or [normalized])]


def _split_line_to_segments(line: str) -> list[dict]:
    inline_match = CHAPTER_INLINE_RE.match(line)
    if inline_match is not None:
        heading_text = str(inline_match.group("heading") or "").strip()
        time_text = str(inline_match.group("time") or "").strip()
        tail_text = str(inline_match.group("tail") or "").lstrip(" ,")
        return [
            _segment_payload(
                heading_text,
                "heading_chapter",
                target_text=_translate_heading_chapter(heading_text),
                translation_kind="rule_exact",
            ),
            _segment_payload(
                time_text,
                "time_phrase",
                target_text=_translate_time_phrase(time_text),
                translation_kind="rule_exact",
            ),
            *_split_plain_line_to_segments(tail_text),
        ]

    chapter_title = CHAPTER_TITLE_RE.match(line)
    if chapter_title is not None:
        return [
            _segment_payload(
                line.strip(),
                "heading_chapter",
                target_text=_translate_heading_chapter(line.strip()),
                translation_kind="rule_exact",
            )
        ]

    chapter_only = CHAPTER_ONLY_RE.match(line)
    if chapter_only is not None:
        return [
            _segment_payload(
                line.strip(),
                "heading_chapter",
                target_text=_translate_heading_chapter(line.strip()),
                translation_kind="rule_exact",
            )
        ]

    time_match = TIME_LEADING_RE.match(line)
    if time_match is not None:
        time_text = str(time_match.group("time") or "").strip()
        tail_text = str(time_match.group("tail") or "").lstrip(" ,")
        return [
            _segment_payload(
                time_text,
                "time_phrase",
                target_text=_translate_time_phrase(time_text),
                translation_kind="rule_exact",
            ),
            *_split_plain_line_to_segments(tail_text),
        ]

    if _looks_like_title(line):
        return [
            _segment_payload(
                line.strip(),
                "heading_title",
                target_text="Солнечное утро" if _normalize(line) == "the sunny morning" else "",
                translation_kind="rule_exact" if _normalize(line) == "the sunny morning" else "provider_fallback",
            )
        ]

    return _split_plain_line_to_segments(line)


def _segment_payload(
    source_text: str,
    segment_type: str,
    *,
    target_text: str = "",
    translation_kind: str = "provider_fallback",
) -> dict:
    return {
        "source_text": source_text.strip(),
        "segment_type": segment_type,
        "target_text": target_text.strip(),
        "translation_kind": translation_kind,
    }


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip().lower()


def _looks_like_title(line: str) -> bool:
    normalized = _normalize(line)
    if normalized == "the sunny morning":
        return True
    words = [chunk for chunk in re.findall(r"[A-Za-z]+", line) if chunk]
    if not words or len(words) > 5:
        return False
    return all(word[:1].isupper() for word in words)


def _translate_heading_chapter(text: str) -> str:
    match = CHAPTER_TITLE_RE.match(text) or CHAPTER_ONLY_RE.match(text)
    if match is None:
        return text
    number_raw = str(match.group("number") or "").strip().lower()
    number = NUMBER_WORDS.get(number_raw, number_raw)
    title = ""
    if "title" in match.groupdict():
        title = str(match.group("title") or "").strip()
    if not title:
        return f"Глава {number}"
    title_map = {
        "a special saturday": "Особенная суббота",
        "the journey": "Путешествие",
        "the forest": "Лес",
        "the picnic": "Пикник",
        "the top of the hill": "Вершина холма",
        "going home": "Возвращение домой",
        "the park": "Парк",
        "the new day": "Новый день",
        "home": "Дом",
        "breakfast": "Завтрак",
    }
    translated_title = title_map.get(_normalize(title), title)
    return f"Глава {number}: {translated_title}"


def _translate_time_phrase(text: str) -> str:
    normalized = _normalize(text)
    if normalized.startswith("at "):
        time_value = text.strip()[3:].strip()
        translated_suffix = "утра" if time_value.upper().endswith("AM") else "вечера"
        clean_time = re.sub(r"\s*(AM|PM)\s*$", "", time_value, flags=re.IGNORECASE).strip()
        return f"в {clean_time} {translated_suffix}"
    mapping = {
        "in the afternoon": "Днем",
        "in the morning": "Утром",
        "in the evening": "Вечером",
    }
    return mapping.get(normalized, text.strip())


def _split_plain_line_to_segments(line: str) -> list[dict]:
    parts = _split_dialogue_aware_sentences(re.sub(r"\s+", " ", line).strip())
    return [_segment_payload(part, "simple_action") for part in (parts or [line.strip()])]


def _split_dialogue_aware_sentences(text: str) -> list[str]:
    if not text:
        return []
    parts: list[str] = []
    current: list[str] = []
    in_quote = False
    index = 0
    while index < len(text):
        char = text[index]
        current.append(char)
        if char == '"':
            in_quote = not in_quote
        if char in ".!?" and not in_quote:
            lookahead = text[index + 1 :]
            if not lookahead.strip():
                parts.append("".join(current).strip())
                current = []
            else:
                next_non_space = next((item for item in lookahead if not item.isspace()), "")
                if next_non_space in {'"', "(", "["} or next_non_space.isupper():
                    parts.append("".join(current).strip())
                    current = []
                    while index + 1 < len(text) and text[index + 1].isspace():
                        index += 1
        index += 1
    if current:
        parts.append("".join(current).strip())
    return [part for part in parts if part]
