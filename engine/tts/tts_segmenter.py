from __future__ import annotations

import re

from ..segmenter import split_sentences
from .tts_models import SpeechProfile
from .tts_models import TtsChunk


MIN_SPLIT_WORDS = 6
PHRASE_PAUSE_MS = 120
SENTENCE_PAUSE_MS = 250
PARAGRAPH_PAUSE_MS = 400
WEAK_ENDINGS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "by",
    "for",
    "from",
    "in",
    "of",
    "on",
    "or",
    "the",
    "to",
    "with",
}
WEAK_STARTS = {
    "and",
    "because",
    "but",
    "or",
    "so",
    "then",
}
MIN_TAIL_WORDS = 4
MIN_TAIL_CHARS = 24
HEADING_PREFIX_RE = re.compile(
    r"^(chapter|part|section|book|prologue|epilogue)\b",
    flags=re.IGNORECASE,
)


def build_tts_chunks(
    paragraphs: list[dict],
    start_paragraph_index: int = 0,
    profile: SpeechProfile | None = None,
) -> list[TtsChunk]:
    policy = _resolve_policy(profile.target_wpm if profile is not None else 145)
    pause_scale = profile.pause_scale if profile is not None else 1.0
    chunks: list[TtsChunk] = []
    order_index = 0
    visible_paragraphs = [item for item in paragraphs if int(item["index"]) >= start_paragraph_index]
    paragraph_units = [_paragraph_units(item, pause_scale, policy) for item in visible_paragraphs]
    total_units = sum(len(units) for _, units in paragraph_units)
    emitted_units = 0
    target_chunk_chars = int(policy["target_chunk_chars"])
    soft_max_chunk_chars = int(policy["soft_max_chunk_chars"])
    hard_max_chunk_chars = int(policy["hard_max_chunk_chars"])

    for paragraph_index, units in paragraph_units:
        current_parts: list[str] = []
        current_last_pause_ms = PARAGRAPH_PAUSE_MS
        for unit in units:
            emitted_units += 1
            unit_text = unit["text"]
            unit_pause_ms = int(unit["pause_after_ms"])
            force_break_before = bool(unit.get("force_break_before"))
            force_break_after = bool(unit.get("force_break_after"))
            if force_break_before and current_parts:
                pause_after_ms = current_last_pause_ms
                chunks.append(
                    TtsChunk(
                        order_index=order_index,
                        paragraph_index=paragraph_index,
                        source_text=_join_parts(current_parts),
                        synthesis_text=_join_parts(current_parts),
                        pause_after_ms=pause_after_ms,
                    )
                )
                order_index += 1
                current_parts = []
            candidate = _join_parts(current_parts + [unit_text])
            if not current_parts:
                current_parts = [unit_text]
                current_last_pause_ms = unit_pause_ms
                if force_break_after:
                    pause_after_ms = 0 if emitted_units == total_units else current_last_pause_ms
                    chunks.append(
                        TtsChunk(
                            order_index=order_index,
                            paragraph_index=paragraph_index,
                            source_text=_join_parts(current_parts),
                            synthesis_text=_join_parts(current_parts),
                            pause_after_ms=pause_after_ms,
                        )
                    )
                    order_index += 1
                    current_parts = []
                continue
            if len(candidate) <= target_chunk_chars:
                current_parts.append(unit_text)
                current_last_pause_ms = unit_pause_ms
                if force_break_after:
                    pause_after_ms = 0 if emitted_units == total_units else current_last_pause_ms
                    chunks.append(
                        TtsChunk(
                            order_index=order_index,
                            paragraph_index=paragraph_index,
                            source_text=_join_parts(current_parts),
                            synthesis_text=_join_parts(current_parts),
                            pause_after_ms=pause_after_ms,
                        )
                    )
                    order_index += 1
                    current_parts = []
                continue
            current_text = _join_parts(current_parts)
            if len(candidate) <= hard_max_chunk_chars and _should_avoid_break(current_text, unit_text, policy):
                current_parts.append(unit_text)
                current_last_pause_ms = unit_pause_ms
                if force_break_after:
                    pause_after_ms = 0 if emitted_units == total_units else current_last_pause_ms
                    chunks.append(
                        TtsChunk(
                            order_index=order_index,
                            paragraph_index=paragraph_index,
                            source_text=_join_parts(current_parts),
                            synthesis_text=_join_parts(current_parts),
                            pause_after_ms=pause_after_ms,
                        )
                    )
                    order_index += 1
                    current_parts = []
                continue
            if len(candidate) <= soft_max_chunk_chars and not _is_preferred_break(unit_text, policy):
                current_parts.append(unit_text)
                current_last_pause_ms = unit_pause_ms
                if force_break_after:
                    pause_after_ms = 0 if emitted_units == total_units else current_last_pause_ms
                    chunks.append(
                        TtsChunk(
                            order_index=order_index,
                            paragraph_index=paragraph_index,
                            source_text=_join_parts(current_parts),
                            synthesis_text=_join_parts(current_parts),
                            pause_after_ms=pause_after_ms,
                        )
                    )
                    order_index += 1
                    current_parts = []
                continue

            pause_after_ms = 0 if emitted_units == total_units else current_last_pause_ms
            chunks.append(
                TtsChunk(
                    order_index=order_index,
                    paragraph_index=paragraph_index,
                    source_text=_join_parts(current_parts),
                    synthesis_text=_join_parts(current_parts),
                    pause_after_ms=pause_after_ms,
                )
            )
            order_index += 1
            current_parts = [unit_text]
            current_last_pause_ms = unit_pause_ms

        if current_parts:
            pause_after_ms = 0 if emitted_units == total_units else current_last_pause_ms
            chunks.append(
                TtsChunk(
                    order_index=order_index,
                    paragraph_index=paragraph_index,
                    source_text=_join_parts(current_parts),
                    synthesis_text=_join_parts(current_parts),
                    pause_after_ms=pause_after_ms,
                )
            )
            order_index += 1

    return chunks


def _paragraph_units(
    paragraph: dict,
    pause_scale: float,
    policy: dict[str, int | str],
) -> tuple[int, list[dict]]:
    paragraph_index = int(paragraph["index"])
    units: list[dict] = []
    lines = _normalized_lines(str(paragraph["source_text"]))
    for line_index, line in enumerate(lines):
        is_heading = _is_heading_line(line)
        is_last_line = line_index == len(lines) - 1
        if is_heading:
            units.append(
                {
                    "text": _normalize_heading(line),
                    "pause_after_ms": int(PARAGRAPH_PAUSE_MS * pause_scale),
                    "force_break_before": True,
                    "force_break_after": True,
                }
            )
            continue

        sentences = split_sentences(line)
        for sentence_index, sentence in enumerate(sentences):
            phrases = _split_phrases(sentence)
            for phrase_index, phrase in enumerate(phrases):
                fragments = _split_long_phrase(phrase, policy)
                for fragment_index, fragment in enumerate(fragments):
                    is_last_fragment = fragment_index == len(fragments) - 1
                    is_last_phrase = phrase_index == len(phrases) - 1
                    is_last_sentence = sentence_index == len(sentences) - 1
                    pause_ms = _resolve_pause_ms(
                        is_last_fragment_in_phrase=is_last_fragment,
                        is_last_phrase_in_sentence=is_last_phrase,
                        is_last_sentence_in_paragraph=is_last_sentence,
                    )
                    if is_last_sentence and is_last_phrase and is_last_fragment and not is_last_line:
                        pause_ms = PARAGRAPH_PAUSE_MS
                    units.append(
                        {
                            "text": fragment,
                            "pause_after_ms": int(pause_ms * pause_scale),
                            "force_break_before": False,
                            "force_break_after": False,
                        }
                    )
    return paragraph_index, units


def _normalized_lines(text: str) -> list[str]:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    lines = [line.strip() for line in normalized.split("\n") if line.strip()]
    return lines


def _split_phrases(text: str) -> list[str]:
    parts = re.split(r"(?<=[,;:])\s+", text)
    return [item.strip() for item in parts if item.strip()]


def _split_long_phrase(text: str, policy: dict[str, int | str]) -> list[str]:
    normalized = text.strip()
    hard_max_chunk_chars = int(policy["hard_max_chunk_chars"])
    if len(normalized) <= hard_max_chunk_chars:
        return [normalized]

    chunks: list[str] = []
    remaining = normalized
    while len(remaining) > hard_max_chunk_chars:
        split_at = _best_split_index(remaining, policy)
        head = remaining[:split_at].strip()
        tail = remaining[split_at:].strip()
        if not head or not tail:
            break
        chunks.append(head)
        remaining = tail
    if remaining:
        chunks.append(remaining)
    return chunks


def _best_split_index(text: str, policy: dict[str, int | str]) -> int:
    punctuation_candidates = [", ", "; ", ": ", " - "]
    search_limit = min(int(policy["soft_max_chunk_chars"]), len(text))
    candidates: list[int] = []
    for marker in punctuation_candidates:
        idx = text.rfind(marker, MIN_SPLIT_WORDS * 4, search_limit)
        if idx > 0:
            candidates.append(idx + len(marker) - 1)

    words = text.split()
    if len(words) <= MIN_SPLIT_WORDS:
        return min(int(policy["hard_max_chunk_chars"]), len(text))
    for split_words in range(MIN_SPLIT_WORDS, len(words) - MIN_TAIL_WORDS + 1):
        prefix = " ".join(words[:split_words])
        if len(prefix) > int(policy["hard_max_chunk_chars"]):
            break
        if len(prefix) >= MIN_SPLIT_WORDS * 4:
            candidates.append(len(prefix))

    ranked = sorted(
        ((_score_split_candidate(text, idx, policy), idx) for idx in set(candidates)),
        key=lambda item: item[0],
        reverse=True,
    )
    if ranked:
        return ranked[0][1]

    midpoint = max(MIN_SPLIT_WORDS, min(len(words) - MIN_TAIL_WORDS, len(words) // 2))
    prefix = " ".join(words[:midpoint])
    return len(prefix)


def _is_preferred_break(next_text: str, policy: dict[str, int | str]) -> bool:
    if len(next_text) > int(policy["target_chunk_chars"]):
        return True
    first_word = _normalize_word(next_text.split()[0]) if next_text.split() else ""
    if first_word in {"however", "but", "then", "suddenly", "meanwhile"}:
        return True
    return str(policy["boundary_strictness"]) in {"high", "max"} and first_word in {"and", "but", "so"}


def _resolve_pause_ms(
    *,
    is_last_fragment_in_phrase: bool,
    is_last_phrase_in_sentence: bool,
    is_last_sentence_in_paragraph: bool,
) -> int:
    if not is_last_fragment_in_phrase:
        return PHRASE_PAUSE_MS
    if not is_last_phrase_in_sentence:
        return PHRASE_PAUSE_MS
    if not is_last_sentence_in_paragraph:
        return SENTENCE_PAUSE_MS
    return PARAGRAPH_PAUSE_MS


def _join_parts(parts: list[str]) -> str:
    return " ".join(part.strip() for part in parts if part.strip()).strip()


def _normalize_word(word: str) -> str:
    return re.sub(r"^[^\w]+|[^\w]+$", "", word).lower()


def _is_heading_line(line: str) -> bool:
    if not line or len(line) > 80:
        return False
    return bool(HEADING_PREFIX_RE.match(line))


def _normalize_heading(line: str) -> str:
    heading = line.strip()
    heading = re.sub(r":\s+", ". ", heading)
    if heading and heading[-1] not in ".!?":
        heading = f"{heading}."
    return heading


def _should_avoid_break(left_text: str, right_text: str, policy: dict[str, int | str]) -> bool:
    left_last = _last_word(left_text)
    right_first = _first_word(right_text)
    if left_last in WEAK_ENDINGS:
        return True
    if right_first in WEAK_STARTS:
        return True
    if _is_short_tail(right_text):
        return True
    strictness = str(policy["boundary_strictness"])
    return strictness == "max" and len(right_text) < int(policy["target_chunk_chars"]) // 2


def _score_split_candidate(text: str, split_at: int, policy: dict[str, int | str]) -> tuple[int, int, int, int]:
    left = text[:split_at].strip()
    right = text[split_at:].strip()
    left_last = _last_word(left)
    right_first = _first_word(right)
    score = 0
    if left_last and left_last not in WEAK_ENDINGS:
        score += 5
    if right_first and right_first not in WEAK_STARTS:
        score += 4
    if not _is_short_tail(right):
        score += 4
    if re.search(r"[.!?][\"')\]]?$", left):
        score += 5
    elif re.search(r"[;:][\"')\]]?$", left):
        score += 4
    elif re.search(r",[\")\]]?$", left):
        score += 3
    target = int(policy["target_chunk_chars"])
    closeness = -abs(len(left) - target)
    return score, closeness, len(left), -len(right)


def _is_short_tail(text: str) -> bool:
    words = text.split()
    return len(words) < MIN_TAIL_WORDS or len(text) < MIN_TAIL_CHARS


def _last_word(text: str) -> str:
    parts = text.split()
    return _normalize_word(parts[-1]) if parts else ""


def _first_word(text: str) -> str:
    parts = text.split()
    return _normalize_word(parts[0]) if parts else ""


def _resolve_policy(target_wpm: int) -> dict[str, int | str]:
    if target_wpm <= 90:
        return {
            "target_chunk_chars": 90,
            "soft_max_chunk_chars": 120,
            "hard_max_chunk_chars": 150,
            "boundary_strictness": "max",
        }
    if target_wpm <= 120:
        return {
            "target_chunk_chars": 125,
            "soft_max_chunk_chars": 160,
            "hard_max_chunk_chars": 210,
            "boundary_strictness": "high",
        }
    if target_wpm <= 145:
        return {
            "target_chunk_chars": 160,
            "soft_max_chunk_chars": 220,
            "hard_max_chunk_chars": 280,
            "boundary_strictness": "medium",
        }
    return {
        "target_chunk_chars": 200,
        "soft_max_chunk_chars": 280,
        "hard_max_chunk_chars": 360,
        "boundary_strictness": "moderate",
    }

