from __future__ import annotations

import re


WORD_PATTERN = re.compile(r"[A-Za-zА-Яа-яЁё0-9]+(?:[-'][A-Za-zА-Яа-яЁё0-9]+)*")
ARTICLE_WORDS = {"the", "a", "an"}
COPULA_WORDS = {"is", "am", "are", "was", "were"}
POSSESSIVE_WORDS = {"my", "your", "his", "her", "our", "their"}
TARGET_FUNCTION_WORDS = {
    "в",
    "во",
    "на",
    "к",
    "ко",
    "с",
    "со",
    "из",
    "от",
    "до",
    "у",
    "по",
    "под",
    "над",
    "при",
    "для",
    "без",
    "через",
    "после",
    "перед",
    "и",
    "а",
    "но",
    "или",
    "не",
    "же",
    "ли",
    "о",
    "об",
    "обо",
}
TARGET_POSSESSIVE_WORDS = {
    "свой",
    "своя",
    "своё",
    "свои",
    "свою",
    "своего",
    "своей",
    "своих",
    "его",
    "ее",
    "её",
    "их",
    "мой",
    "моя",
    "мою",
    "твой",
    "твоя",
    "наш",
    "наша",
    "ваш",
    "ваша",
    "моих",
    "твоих",
    "наших",
}
PRONOUN_WORDS = {"i", "you", "he", "she", "it", "we", "they"}
PREPOSITION_WORDS = {
    "at",
    "in",
    "on",
    "to",
    "from",
    "with",
    "for",
    "of",
    "by",
    "into",
    "onto",
    "over",
    "under",
    "near",
    "around",
    "through",
    "after",
    "before",
    "out",
}
CONJUNCTION_WORDS = {"and", "or", "but"}
COMMON_ADJECTIVE_WORDS = {
    "sunny",
    "new",
    "beautiful",
    "blue",
    "white",
    "red",
    "green",
    "brown",
    "small",
    "big",
    "little",
    "good",
    "happy",
    "tired",
    "energetic",
    "funny",
    "fresh",
    "cold",
    "long",
    "tall",
    "yellow",
    "flat",
    "clear",
    "relaxed",
    "warm",
    "quiet",
    "hot",
    "friendly",
    "grey",
    "gray",
    "orange",
    "pink",
    "whole",
    "ready",
    "great",
    "beautiful",
}
COMMON_VERB_WORDS = {
    "say",
    "says",
    "think",
    "thinks",
    "wake",
    "wakes",
    "go",
    "goes",
    "make",
    "makes",
    "drink",
    "drinks",
    "eat",
    "eats",
    "look",
    "looks",
    "see",
    "sees",
    "wear",
    "wears",
    "play",
    "plays",
    "walk",
    "walks",
    "sit",
    "sits",
    "run",
    "runs",
    "start",
    "starts",
    "arrive",
    "arrives",
    "find",
    "finds",
    "call",
    "calls",
    "come",
    "comes",
    "reply",
    "replies",
    "answer",
    "answers",
}
PHRASAL_VERB_PAIRS = {
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
    ("take", "off"),
    ("takes", "off"),
    ("took", "off"),
    ("taken", "off"),
}
ANCHOR_TRANSLATIONS = {
    "chapter": {"глава"},
    "am": {"утра"},
    "pm": {"дня", "вечера"},
    "tom": {"том"},
    "luna": {"луна", "луну"},
    "anna": {"анна", "анну"},
}
REPORTING_VERB_TRANSLATIONS = {
    "say": {"говорит", "сказал", "сказала", "ответил", "ответила", "отвечает"},
    "says": {"говорит", "сказал", "сказала", "ответил", "ответила", "отвечает"},
    "think": {"думает", "подумал", "подумала"},
    "thinks": {"думает", "подумал", "подумала"},
    "ask": {"спрашивает", "спросил", "спросила"},
    "asks": {"спрашивает", "спросил", "спросила"},
    "whisper": {"шепчет", "прошептал", "прошептала"},
    "whispers": {"шепчет", "прошептал", "прошептала"},
    "reply": {"отвечает", "ответил", "ответила"},
    "replies": {"отвечает", "ответил", "ответила"},
    "answer": {"отвечает", "ответил", "ответила"},
    "answers": {"отвечает", "ответил", "ответила"},
}


def tokenize_words(text: str) -> list[dict]:
    return [
        {
            "text": match.group(0),
            "normalized": match.group(0).lower(),
        }
        for match in WORD_PATTERN.finditer(text)
    ]


def build_word_mappings(
    source_text: str,
    target_text: str,
    paragraph_start_index: int,
) -> tuple[list[dict], list[dict]]:
    source_tokens = tokenize_words(source_text)
    target_tokens = tokenize_words(target_text)
    if not source_tokens:
        return [], []

    target_by_source_index: dict[int, int | None] = {}
    target_span_by_source_index: dict[int, tuple[int, int]] = {}
    anchor_pairs = _match_anchor_pairs(source_tokens, target_tokens)
    _assign_window_targets(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        anchor_pairs=anchor_pairs,
        target_by_source_index=target_by_source_index,
    )

    content_indices = [
        index
        for index, token in enumerate(source_tokens)
        if not _is_inheriting_function_word(token)
    ]
    if not content_indices:
        content_indices = list(range(len(source_tokens)))

    for source_index, token in enumerate(source_tokens):
        if _is_inheriting_function_word(token):
            target_by_source_index[source_index] = _resolve_function_target(
                source_tokens=source_tokens,
                source_index=source_index,
                content_indices=content_indices,
                target_tokens=target_tokens,
                target_by_source_index=target_by_source_index,
            )
    _rescue_reporting_verb_targets(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        target_by_source_index=target_by_source_index,
    )
    _apply_special_phrase_overrides(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )
    _repair_possessive_targets(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        target_by_source_index=target_by_source_index,
    )
    _cleanup_grammar_targets(
        source_tokens=source_tokens,
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )

    words: list[dict] = []
    alignments: list[dict] = []
    for order_index, token in enumerate(source_tokens):
        word_id = f"w_{paragraph_start_index + order_index}"
        target_index = target_by_source_index.get(order_index)
        target_span = target_span_by_source_index.get(order_index)
        anchor_source_index = _resolve_anchor_source_index(
            source_tokens=source_tokens,
            source_index=order_index,
            content_indices=content_indices,
        )
        words.append(
            {
                "id": word_id,
                "order_index_in_paragraph": paragraph_start_index + order_index,
                "order_index_in_segment": order_index,
                "surface_text": token["text"],
                "normalized_text": token["normalized"],
                "is_function_word": int(_is_inheriting_function_word(token)),
                "anchor_order_index_in_segment": anchor_source_index,
            }
        )
        if target_index is None:
            alignments.append(
                {
                    "source_word_id": word_id,
                    "target_start_index": -1,
                    "target_end_index": -1,
                    "target_text": "",
                    "confidence": 0.0,
                }
            )
            continue
        target_start_index = target_index
        target_end_index = target_index
        target_text_value = target_tokens[target_index]["text"]
        if target_span is not None:
            target_start_index, target_end_index = target_span
            target_text_value = " ".join(
                token["text"]
                for token in target_tokens[target_start_index : target_end_index + 1]
            ).strip()
        alignments.append(
            {
                "source_word_id": word_id,
                "target_start_index": target_start_index,
                "target_end_index": target_end_index,
                "target_text": target_text_value,
                "confidence": 0.95 if token["normalized"] not in ARTICLE_WORDS else 0.75,
            }
        )
    return words, alignments


def build_context_window(
    target_text: str,
    target_start_index: int,
    target_end_index: int,
) -> tuple[str, str, str]:
    target_tokens = tokenize_words(target_text)
    if not target_tokens:
        return "", "", ""
    if target_start_index < 0 or target_end_index < 0:
        return "", "", ""

    clamped_start = max(0, min(target_start_index, len(target_tokens) - 1))
    clamped_end = max(clamped_start, min(target_end_index, len(target_tokens) - 1))
    left = " ".join(token["text"] for token in target_tokens[max(0, clamped_start - 3) : clamped_start])
    focus = " ".join(token["text"] for token in target_tokens[clamped_start : clamped_end + 1])
    right = " ".join(token["text"] for token in target_tokens[clamped_end + 1 : clamped_end + 4])
    return left, focus, right


def build_tap_word_payloads(
    segment_target_text: str,
    words: list[dict],
) -> list[dict]:
    if not words:
        return []

    units = _build_tap_units(words)
    payload_by_word_id: dict[str, dict] = {}
    for unit in units:
        left_text, focus_text, right_text = build_context_window(
            target_text=segment_target_text,
            target_start_index=unit["target_start_index"],
            target_end_index=unit["target_end_index"],
        )
        effective_span_text = focus_text or unit["translation_span_text"]
        for word in unit["words"]:
            payload = {
                "id": word["id"],
                "text": word["text"],
                "order_index": word["order_index"],
                "anchor_word_id": word["anchor_word_id"],
                "tap_unit_id": unit["id"],
                "source_unit_text": unit["source_text"],
                "translation_span_text": effective_span_text,
                "translation_left_text": left_text,
                "translation_focus_text": effective_span_text,
                "translation_right_text": right_text,
            }
            for optional_key in (
                "normalized_text",
                "segment_id",
                "segment_source_text",
                "segment_target_text",
                "segment_type",
                "segment_translation_kind",
                "lemma",
                "pos",
                "morph",
                "lexical_unit_id",
                "lexical_unit_type",
                "grammar_hint",
                "morph_label",
            ):
                if optional_key in word:
                    payload[optional_key] = word[optional_key]
            payload_by_word_id[word["id"]] = payload
    return [payload_by_word_id[word["id"]] for word in words]


def _assign_content_targets(content_count: int, target_count: int) -> list[int | None]:
    if content_count <= 0:
        return []
    if target_count <= 0:
        return [None] * content_count
    if content_count == 1:
        return [0]
    return [round(position * (target_count - 1) / (content_count - 1)) for position in range(content_count)]


def _resolve_function_target(
    source_tokens: list[dict],
    source_index: int,
    content_indices: list[int],
    target_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
) -> int | None:
    anchor_index = _resolve_anchor_source_index(
        source_tokens=source_tokens,
        source_index=source_index,
        content_indices=content_indices,
    )
    anchor_target_index = target_by_source_index.get(anchor_index)
    if anchor_target_index is None:
        return None

    token = source_tokens[source_index]
    if token["normalized"] in ARTICLE_WORDS and source_index < anchor_index and anchor_target_index > 0:
        previous_target_index = anchor_target_index - 1
        if _is_target_function_word(target_tokens[previous_target_index]):
            return previous_target_index
        return None
    if token["normalized"] in COPULA_WORDS:
        if anchor_target_index > 0 and _is_target_function_word(target_tokens[anchor_target_index - 1]):
            return anchor_target_index - 1
        return None
    return anchor_target_index


def _resolve_anchor_source_index(
    source_tokens: list[dict],
    source_index: int,
    content_indices: list[int],
) -> int:
    if not _is_inheriting_function_word(source_tokens[source_index]):
        return source_index

    for candidate_index in range(source_index + 1, len(source_tokens)):
        if not _is_inheriting_function_word(source_tokens[candidate_index]):
            return candidate_index
    for candidate_index in range(source_index - 1, -1, -1):
        if not _is_inheriting_function_word(source_tokens[candidate_index]):
            return candidate_index
    return content_indices[0] if content_indices else source_index


def _assign_window_targets(
    source_tokens: list[dict],
    target_tokens: list[dict],
    anchor_pairs: list[tuple[int, int]],
    target_by_source_index: dict[int, int | None],
) -> None:
    sorted_pairs = sorted(anchor_pairs)
    source_cursor = 0
    target_cursor = 0

    for source_anchor_index, target_anchor_index in sorted_pairs:
        _assign_window_range(
            source_tokens=source_tokens,
            target_tokens=target_tokens,
            source_start=source_cursor,
            source_end=source_anchor_index - 1,
            target_start=target_cursor,
            target_end=target_anchor_index - 1,
            target_by_source_index=target_by_source_index,
        )
        target_by_source_index[source_anchor_index] = target_anchor_index
        source_cursor = source_anchor_index + 1
        target_cursor = target_anchor_index + 1

    _assign_window_range(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        source_start=source_cursor,
        source_end=len(source_tokens) - 1,
        target_start=target_cursor,
        target_end=len(target_tokens) - 1,
        target_by_source_index=target_by_source_index,
    )


def _assign_window_range(
    source_tokens: list[dict],
    target_tokens: list[dict],
    source_start: int,
    source_end: int,
    target_start: int,
    target_end: int,
    target_by_source_index: dict[int, int | None],
) -> None:
    if source_start > source_end:
        return

    source_content_indices = [
        index
        for index in range(source_start, source_end + 1)
        if not _is_inheriting_function_word(source_tokens[index])
    ]
    if not source_content_indices:
        return

    if target_start > target_end or not target_tokens:
        for source_index in source_content_indices:
            target_by_source_index[source_index] = None
        return

    target_indices = list(range(target_start, target_end + 1))
    if _should_skip_leading_target_function_tokens(
        source_tokens=source_tokens,
        source_start=source_start,
        source_content_indices=source_content_indices,
        target_tokens=target_tokens,
        target_indices=target_indices,
    ):
        trimmed_target_indices = list(target_indices)
        while (
            len(trimmed_target_indices) > len(source_content_indices)
            and trimmed_target_indices
            and _is_target_function_word(target_tokens[trimmed_target_indices[0]])
        ):
            trimmed_target_indices.pop(0)
        if len(trimmed_target_indices) >= len(source_content_indices):
            target_indices = trimmed_target_indices

    relative_targets = _assign_content_targets(len(source_content_indices), len(target_indices))
    for position, source_index in enumerate(source_content_indices):
        relative_index = relative_targets[position]
        target_by_source_index[source_index] = (
            None if relative_index is None else target_indices[relative_index]
        )


def _match_anchor_pairs(
    source_tokens: list[dict],
    target_tokens: list[dict],
) -> list[tuple[int, int]]:
    matches: list[tuple[int, int]] = []
    next_target_index = 0

    for source_index, token in enumerate(source_tokens):
        if not _is_hard_anchor(token):
            continue
        candidates = _anchor_candidates(token)
        if not candidates:
            continue
        matched_index = _find_target_anchor_index(target_tokens, candidates, next_target_index)
        if matched_index is None:
            continue
        matches.append((source_index, matched_index))
        next_target_index = matched_index + 1
    return matches


def _is_hard_anchor(token: dict) -> bool:
    text = token["text"]
    normalized = token["normalized"]
    if normalized in {"chapter", "am", "pm"}:
        return True
    if text.isdigit():
        return True
    return normalized in {"tom", "luna", "anna"}


def _anchor_candidates(token: dict) -> set[str]:
    text = token["text"]
    normalized = token["normalized"]
    candidates = {normalized}
    if normalized in ANCHOR_TRANSLATIONS:
        candidates.update(ANCHOR_TRANSLATIONS[normalized])
    if text.isdigit():
        candidates.add(text)
    return {item.lower() for item in candidates}


def _find_target_anchor_index(
    target_tokens: list[dict],
    candidates: set[str],
    start_index: int,
) -> int | None:
    for index in range(start_index, len(target_tokens)):
        if target_tokens[index]["normalized"] in candidates:
            return index
    return None


def _is_target_function_word(token: dict) -> bool:
    return token["normalized"] in TARGET_FUNCTION_WORDS


def _apply_special_phrase_overrides(
    source_tokens: list[dict],
    target_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
    target_span_by_source_index: dict[int, tuple[int, int]],
) -> None:
    if not source_tokens or not target_tokens:
        return

    _apply_pronoun_be_adjective_overrides(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )
    _apply_exact_phrase_override(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        source_phrase=("how", "are", "you"),
        target_phrase=("как", "дела"),
        apply_mode="all",
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )
    _apply_exact_phrase_override(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        source_phrase=("thank", "you"),
        target_phrase=("спасибо",),
        apply_mode="all",
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )
    _apply_exact_phrase_override(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        source_phrase=("goodnight",),
        target_phrase=("спокойной", "ночи"),
        apply_mode="all",
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )
    _apply_exact_phrase_override(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        source_phrase=("in", "the", "afternoon"),
        target_phrase=("днем",),
        apply_mode="all",
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )
    _apply_it_day_overrides(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        target_by_source_index=target_by_source_index,
        target_span_by_source_index=target_span_by_source_index,
    )


def _apply_pronoun_be_adjective_overrides(
    source_tokens: list[dict],
    target_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
    target_span_by_source_index: dict[int, tuple[int, int]],
) -> None:
    if len(source_tokens) < 3:
        return
    source_words = [token["normalized"] for token in source_tokens]
    pronoun = source_words[0]
    copula = source_words[1]
    predicate = source_words[2]
    if pronoun not in PRONOUN_WORDS - {"it"}:
        return
    if copula not in COPULA_WORDS:
        return

    pronoun_target_candidates = {
        "i": {"я"},
        "you": {"ты", "вы"},
        "he": {"он"},
        "she": {"она"},
        "we": {"мы"},
        "they": {"они"},
    }.get(pronoun, set())
    if pronoun_target_candidates:
        pronoun_target_index = _find_target_token_index(target_tokens, pronoun_target_candidates)
        if pronoun_target_index is not None:
            _set_target_span_override(0, pronoun_target_index, pronoun_target_index, target_by_source_index, target_span_by_source_index)

    if predicate in {"great", "grate"}:
        predicate_span = _find_target_phrase_span(target_tokens, ("в", "порядке"))
        if predicate_span is None:
            return
        target_by_source_index[1] = None
        _set_target_span_override(2, predicate_span[0], predicate_span[1], target_by_source_index, target_span_by_source_index)
        return

    predicate_candidates = {
        "happy": {"счастлив", "счастлива", "счастливы"},
        "tired": {"уставший", "уставшая", "уставшие"},
        "ready": {"готов", "готова", "готовы"},
        "hungry": {"голодный", "голодна", "голодны"},
        "sad": {"грустный", "грустна", "грустны"},
    }.get(predicate, set())
    if not predicate_candidates:
        return
    predicate_index = _find_target_token_index(target_tokens, predicate_candidates)
    if predicate_index is None:
        return
    target_by_source_index[1] = None
    _set_target_span_override(2, predicate_index, predicate_index, target_by_source_index, target_span_by_source_index)


def _apply_exact_phrase_override(
    source_tokens: list[dict],
    target_tokens: list[dict],
    source_phrase: tuple[str, ...],
    target_phrase: tuple[str, ...],
    apply_mode: str,
    target_by_source_index: dict[int, int | None],
    target_span_by_source_index: dict[int, tuple[int, int]],
) -> None:
    source_start = _find_source_phrase_range(source_tokens, source_phrase)
    target_span = _find_target_phrase_span(target_tokens, target_phrase)
    if source_start is None or target_span is None:
        return
    target_start, target_end = target_span
    for offset in range(len(source_phrase)):
        source_index = source_start + offset
        if apply_mode == "all":
            _set_target_span_override(
                source_index=source_index,
                target_start_index=target_start,
                target_end_index=target_end,
                target_by_source_index=target_by_source_index,
                target_span_by_source_index=target_span_by_source_index,
            )


def _apply_it_day_overrides(
    source_tokens: list[dict],
    target_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
    target_span_by_source_index: dict[int, tuple[int, int]],
) -> None:
    source_words = [token["normalized"] for token in source_tokens]
    subject_index = _find_target_token_index(target_tokens, {"сегодня", "это"})
    day_index = _find_target_token_index(target_tokens, {"день"})
    if subject_index is None or day_index is None:
        return

    if source_words[:5] == ["it", "is", "a", "beautiful", "day"]:
        adjective_index = _find_target_token_index(
            target_tokens,
            {"прекрасный", "прекрасная", "прекрасное", "прекрасную", "прекрасного"},
        )
        if adjective_index is None:
            return
        _set_target_span_override(0, subject_index, subject_index, target_by_source_index, target_span_by_source_index)
        target_by_source_index[1] = None
        target_by_source_index[2] = None
        _set_target_span_override(3, adjective_index, adjective_index, target_by_source_index, target_span_by_source_index)
        _set_target_span_override(4, day_index, day_index, target_by_source_index, target_span_by_source_index)
        return

    if source_words[:6] == ["it", "is", "a", "very", "good", "day"]:
        very_index = _find_target_token_index(target_tokens, {"очень"})
        adjective_index = _find_target_token_index(target_tokens, {"хороший", "хорошая", "хорошее"})
        if very_index is None or adjective_index is None:
            return
        _set_target_span_override(0, subject_index, subject_index, target_by_source_index, target_span_by_source_index)
        target_by_source_index[1] = None
        target_by_source_index[2] = None
        _set_target_span_override(3, very_index, very_index, target_by_source_index, target_span_by_source_index)
        _set_target_span_override(4, adjective_index, adjective_index, target_by_source_index, target_span_by_source_index)
        _set_target_span_override(5, day_index, day_index, target_by_source_index, target_span_by_source_index)


def _find_source_phrase_range(source_tokens: list[dict], source_phrase: tuple[str, ...]) -> int | None:
    normalized_tokens = [token["normalized"] for token in source_tokens]
    phrase_length = len(source_phrase)
    for index in range(0, len(normalized_tokens) - phrase_length + 1):
        if tuple(normalized_tokens[index : index + phrase_length]) == source_phrase:
            return index
    return None


def _find_target_phrase_span(
    target_tokens: list[dict],
    target_phrase: tuple[str, ...],
) -> tuple[int, int] | None:
    normalized_tokens = [token["normalized"] for token in target_tokens]
    phrase_length = len(target_phrase)
    for index in range(0, len(normalized_tokens) - phrase_length + 1):
        if tuple(normalized_tokens[index : index + phrase_length]) == target_phrase:
            return index, index + phrase_length - 1
    return None


def _find_target_token_index(target_tokens: list[dict], candidates: set[str]) -> int | None:
    for index, token in enumerate(target_tokens):
        if token["normalized"] in candidates:
            return index
    return None


def _set_target_span_override(
    source_index: int,
    target_start_index: int,
    target_end_index: int,
    target_by_source_index: dict[int, int | None],
    target_span_by_source_index: dict[int, tuple[int, int]],
) -> None:
    target_by_source_index[source_index] = target_start_index
    target_span_by_source_index[source_index] = (target_start_index, target_end_index)


def _rescue_reporting_verb_targets(
    source_tokens: list[dict],
    target_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
) -> None:
    if not source_tokens or not target_tokens:
        return

    used_target_indices = {
        target_index
        for target_index in target_by_source_index.values()
        if target_index is not None and target_index >= 0
    }
    anchor_pairs = _match_anchor_pairs(source_tokens, target_tokens)
    target_anchor_by_source_index = {source_index: target_index for source_index, target_index in anchor_pairs}

    for source_index, token in enumerate(source_tokens):
        normalized = token["normalized"]
        if normalized not in REPORTING_VERB_TRANSLATIONS:
            continue

        current_target_index = target_by_source_index.get(source_index)
        if current_target_index is not None and current_target_index >= 0:
            current_target_token = target_tokens[current_target_index]
            if current_target_token["normalized"] in REPORTING_VERB_TRANSLATIONS[normalized]:
                continue

        rescued_target_index = _find_reporting_verb_target_index(
            source_tokens=source_tokens,
            source_index=source_index,
            target_tokens=target_tokens,
            used_target_indices=used_target_indices,
            target_anchor_by_source_index=target_anchor_by_source_index,
        )
        if rescued_target_index is None:
            continue
        target_by_source_index[source_index] = rescued_target_index
        used_target_indices.add(rescued_target_index)


def _find_reporting_verb_target_index(
    source_tokens: list[dict],
    source_index: int,
    target_tokens: list[dict],
    used_target_indices: set[int],
    target_anchor_by_source_index: dict[int, int],
) -> int | None:
    normalized = source_tokens[source_index]["normalized"]
    candidates = REPORTING_VERB_TRANSLATIONS.get(normalized) or set()
    if not candidates:
        return None

    candidate_indices = [
        index
        for index, token in enumerate(target_tokens)
        if token["normalized"] in candidates
    ]
    if not candidate_indices:
        return None

    preferred_anchor_indices: list[int] = []
    if source_index > 0 and _is_hard_anchor(source_tokens[source_index - 1]):
        anchor_target_index = target_anchor_by_source_index.get(source_index - 1)
        if anchor_target_index is not None:
            preferred_anchor_indices.append(anchor_target_index)
    if source_index + 1 < len(source_tokens) and _is_hard_anchor(source_tokens[source_index + 1]):
        anchor_target_index = target_anchor_by_source_index.get(source_index + 1)
        if anchor_target_index is not None:
            preferred_anchor_indices.append(anchor_target_index)

    def score(index: int) -> tuple[int, int, int]:
        is_used = 1 if index in used_target_indices else 0
        anchor_distance = min((abs(index - anchor_index) for anchor_index in preferred_anchor_indices), default=0)
        source_distance = abs(index - source_index)
        return (is_used, anchor_distance, source_distance)

    candidate_indices.sort(key=score)
    return candidate_indices[0]


def _repair_possessive_targets(
    source_tokens: list[dict],
    target_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
) -> None:
    for source_index, token in enumerate(source_tokens):
        if token["normalized"] not in POSSESSIVE_WORDS:
            continue
        target_index = target_by_source_index.get(source_index)
        if target_index is not None and target_index >= 0:
            current_target = target_tokens[target_index]
            if current_target["normalized"] in TARGET_POSSESSIVE_WORDS:
                continue
            if not _is_target_function_word(current_target):
                rescued_index = _find_matching_possessive_target(
                    source_tokens=source_tokens,
                    source_index=source_index,
                    target_tokens=target_tokens,
                )
                if rescued_index is not None:
                    target_by_source_index[source_index] = rescued_index
                continue

        rescued_index = _find_matching_possessive_target(
            source_tokens=source_tokens,
            source_index=source_index,
            target_tokens=target_tokens,
        )
        if rescued_index is None:
            target_by_source_index[source_index] = None
            continue
        target_by_source_index[source_index] = rescued_index


def _find_matching_possessive_target(
    source_tokens: list[dict],
    source_index: int,
    target_tokens: list[dict],
) -> int | None:
    candidates = _target_possessive_candidates_for_source(source_tokens[source_index]["normalized"])
    if not candidates:
        return None

    paired_noun_candidates = _target_noun_candidates_for_possessive_pair(
        source_tokens=source_tokens,
        source_index=source_index,
    )
    if paired_noun_candidates:
        for index, token in enumerate(target_tokens):
            if token["normalized"] not in candidates:
                continue
            if index + 1 < len(target_tokens) and target_tokens[index + 1]["normalized"] in paired_noun_candidates:
                return index

    return _find_target_token_index(target_tokens, candidates)


def _target_possessive_candidates_for_source(normalized_source: str) -> set[str]:
    mapping = {
        "my": {"мой", "моя", "мою", "моих"},
        "your": {"твой", "твоя", "твою", "твоих"},
        "his": {"его"},
        "her": {"ее", "её"},
        "our": {"наш", "наша", "нашу", "наших"},
        "their": {"их"},
    }
    return mapping.get(normalized_source, set())


def _target_noun_candidates_for_possessive_pair(
    source_tokens: list[dict],
    source_index: int,
) -> set[str]:
    if source_index + 1 >= len(source_tokens):
        return set()
    next_word = source_tokens[source_index + 1]["normalized"]
    mapping = {
        "legs": {"ногах", "ноги", "ног"},
        "feet": {"ступнях", "ступни", "ногах"},
        "hands": {"руках", "руки", "рук"},
        "friend": {"друга", "друг", "подругу", "подруга"},
        "cat": {"кота", "кот", "кошку", "кошка"},
        "dog": {"собаку", "собака", "пса", "пес"},
        "book": {"книгу", "книга"},
    }
    return mapping.get(next_word, set())


def _cleanup_grammar_targets(
    source_tokens: list[dict],
    target_by_source_index: dict[int, int | None],
    target_span_by_source_index: dict[int, tuple[int, int]],
) -> None:
    for source_index, token in enumerate(source_tokens):
        normalized = token["normalized"]
        if source_index in target_span_by_source_index:
            continue
        if normalized in ARTICLE_WORDS:
            target_by_source_index[source_index] = None
            continue
        if normalized in COPULA_WORDS:
            target_by_source_index[source_index] = None


def _should_skip_leading_target_function_tokens(
    source_tokens: list[dict],
    source_start: int,
    source_content_indices: list[int],
    target_tokens: list[dict],
    target_indices: list[int],
) -> bool:
    if not target_indices or not source_content_indices:
        return False
    if _word_normalized(source_tokens[source_start]) not in ARTICLE_WORDS:
        return False
    if len(source_content_indices) < 2:
        return False
    first_target_index = target_indices[0]
    if not _is_target_function_word(target_tokens[first_target_index]):
        return False
    return True


def _is_inheriting_function_word(token: dict) -> bool:
    normalized = token["normalized"]
    text = token["text"]
    if normalized in ARTICLE_WORDS:
        return True
    if normalized in COPULA_WORDS and not text.isupper():
        return True
    return False


def _build_tap_units(words: list[dict]) -> list[dict]:
    units: list[dict] = []
    index = 0
    while index < len(words):
        unit = (
            _match_fixed_phrase_unit(words, index)
            or _match_it_be_unit(words, index)
            or
            _match_time_unit(words, index)
            or _match_chapter_unit(words, index)
            or _match_pronoun_be_unit(words, index)
            or _match_article_noun_phrase_unit(words, index)
            or _match_article_noun_unit(words, index)
            or _match_be_predicate_unit(words, index)
            or _match_phrasal_verb_unit(words, index)
        )
        if unit is None:
            unit = _build_unit(words, index, index, "single")
        units.append(unit)
        index = unit["end_index"] + 1
    return units


def _match_fixed_phrase_unit(words: list[dict], index: int) -> dict | None:
    patterns = (
        (("good", "morning"), "phrase"),
        (("how", "are", "you"), "phrase"),
        (("thank", "you"), "phrase"),
        (("goodnight",), "phrase"),
        (("in", "the", "afternoon"), "phrase"),
    )
    for pattern, unit_type in patterns:
        end_index = index + len(pattern)
        if end_index > len(words):
            continue
        if tuple(_word_normalized(word) for word in words[index:end_index]) == pattern:
            return _build_unit(words, index, end_index - 1, unit_type)
    return None


def _match_it_be_unit(words: list[dict], index: int) -> dict | None:
    if index + 1 >= len(words):
        return None
    if _word_normalized(words[index]) == "it" and _word_normalized(words[index + 1]) in COPULA_WORDS:
        return _build_unit(words, index, index + 1, "pronoun_be")
    return None


def _match_time_unit(words: list[dict], index: int) -> dict | None:
    current = words[index]
    if not current["text"].isdigit():
        return None
    if index + 2 < len(words) and words[index + 1]["text"].isdigit() and words[index + 2]["text"].upper() in {"AM", "PM"}:
        return _build_unit(words, index, index + 2, "time")
    if index + 1 < len(words) and words[index + 1]["text"].upper() in {"AM", "PM"}:
        return _build_unit(words, index, index + 1, "time")
    return None


def _match_chapter_unit(words: list[dict], index: int) -> dict | None:
    if _word_normalized(words[index]) != "chapter":
        return None
    if index + 1 < len(words) and words[index + 1]["text"].isdigit():
        return _build_unit(words, index, index + 1, "chapter")
    return None


def _match_pronoun_be_unit(words: list[dict], index: int) -> dict | None:
    if _word_normalized(words[index]) not in (PRONOUN_WORDS - {"it"}):
        return None
    if index + 1 >= len(words):
        return None
    next_word = words[index + 1]
    if _word_normalized(next_word) in COPULA_WORDS and not next_word["text"].isupper():
        return _build_unit(words, index, index + 1, "pronoun_be")
    return None


def _match_article_noun_phrase_unit(words: list[dict], index: int) -> dict | None:
    if _word_normalized(words[index]) not in ARTICLE_WORDS or index + 1 >= len(words):
        return None
    scan_index = index + 1
    adjective_count = 0
    while scan_index < len(words) and _is_adjective_like(words[scan_index]):
        adjective_count += 1
        scan_index += 1
    if scan_index >= len(words):
        return None
    head_word = words[scan_index]
    if not _is_noun_like(head_word):
        return None
    next_index = scan_index + 1
    if next_index < len(words) and not _is_phrase_boundary(words[next_index]):
        return None
    if adjective_count <= 0:
        return None
    return _build_unit(words, index, scan_index, "article_noun_phrase")


def _match_article_adjective_unit(words: list[dict], index: int) -> dict | None:
    if _word_normalized(words[index]) not in ARTICLE_WORDS or index + 2 >= len(words):
        return None
    adjective_word = words[index + 1]
    noun_word = words[index + 2]
    if not _is_adjective_like(adjective_word):
        return None
    if not _is_noun_like(noun_word):
        return None
    next_index = index + 3
    if next_index >= len(words):
        return None
    if _is_phrase_boundary(words[next_index]):
        return None
    return _build_unit(words, index, index + 1, "article_adjective")


def _match_article_noun_unit(words: list[dict], index: int) -> dict | None:
    if _word_normalized(words[index]) not in ARTICLE_WORDS or index + 1 >= len(words):
        return None
    next_word = words[index + 1]
    next_normalized = _word_normalized(next_word)
    if next_normalized in ARTICLE_WORDS or next_normalized in COPULA_WORDS:
        return None
    if next_normalized in CONJUNCTION_WORDS:
        return None
    if not _is_noun_like(next_word):
        return None
    return _build_unit(words, index, index + 1, "article_noun")


def _match_phrasal_verb_unit(words: list[dict], index: int) -> dict | None:
    if index + 1 >= len(words):
        return None
    pair = (_word_normalized(words[index]), _word_normalized(words[index + 1]))
    if pair in PHRASAL_VERB_PAIRS:
        return _build_unit(words, index, index + 1, "phrasal_verb")
    return None


def _match_be_predicate_unit(words: list[dict], index: int) -> dict | None:
    if index + 1 >= len(words):
        return None
    current = words[index]
    next_word = words[index + 1]
    current_normalized = _word_normalized(current)
    next_normalized = _word_normalized(next_word)
    if current_normalized not in COPULA_WORDS or current["text"].isupper():
        return None
    if next_normalized in ARTICLE_WORDS or next_normalized in COPULA_WORDS:
        return None
    if next_normalized in CONJUNCTION_WORDS:
        return None
    if index > 0 and _word_normalized(words[index - 1]) in PRONOUN_WORDS:
        return None
    return _build_unit(words, index, index + 1, "be_predicate")


def _build_unit(words: list[dict], start_index: int, end_index: int, unit_type: str) -> dict:
    unit_words = words[start_index : end_index + 1]
    target_start_index, target_end_index, translation_span_text = _resolve_unit_target(unit_words, unit_type)
    return {
        "id": unit_words[0]["id"],
        "type": unit_type,
        "start_index": start_index,
        "end_index": end_index,
        "words": unit_words,
        "source_text": " ".join(word["text"] for word in unit_words),
        "target_start_index": target_start_index,
        "target_end_index": target_end_index,
        "translation_span_text": translation_span_text,
    }


def _resolve_unit_target(unit_words: list[dict], unit_type: str) -> tuple[int, int, str]:
    if unit_type == "pronoun_be":
        return _single_word_target(unit_words[0])
    if unit_type == "article_noun":
        return _single_word_target(unit_words[-1])
    if unit_type == "article_adjective":
        return _aggregate_target(unit_words)
    if unit_type == "article_noun_phrase":
        return _aggregate_target(unit_words[1:])
    return _aggregate_target(unit_words)


def _single_word_target(word: dict) -> tuple[int, int, str]:
    start_index = word["target_start_index"]
    end_index = word["target_end_index"]
    if start_index is None or end_index is None or start_index < 0 or end_index < 0:
        return -1, -1, ""
    return int(start_index), int(end_index), str(word["translation_span_text"] or "")


def _aggregate_target(unit_words: list[dict]) -> tuple[int, int, str]:
    valid_words = [
        word
        for word in unit_words
        if word["target_start_index"] is not None
        and word["target_end_index"] is not None
        and int(word["target_start_index"]) >= 0
        and int(word["target_end_index"]) >= 0
    ]
    if not valid_words:
        return -1, -1, ""
    start_index = min(int(word["target_start_index"]) for word in valid_words)
    end_index = max(int(word["target_end_index"]) for word in valid_words)
    span_text = " ".join(
        word["translation_span_text"]
        for word in valid_words
        if str(word["translation_span_text"] or "").strip()
    ).strip()
    return start_index, end_index, span_text


def _word_normalized(word: dict) -> str:
    return str(word.get("normalized_text") or word.get("normalized") or word.get("text") or "").lower()


def _is_phrase_boundary(word: dict) -> bool:
    normalized = _word_normalized(word)
    if normalized in ARTICLE_WORDS or normalized in COPULA_WORDS:
        return True
    if normalized in PREPOSITION_WORDS or normalized in CONJUNCTION_WORDS:
        return True
    if _is_verb_like(word):
        return True
    return False


def _is_adjective_like(word: dict) -> bool:
    normalized = _word_normalized(word)
    if normalized in COMMON_ADJECTIVE_WORDS:
        return True
    return normalized.endswith(("ful", "ous", "ive", "al", "able", "ible", "ic", "ary"))


def _is_verb_like(word: dict) -> bool:
    normalized = _word_normalized(word)
    if normalized in COMMON_VERB_WORDS:
        return True
    if normalized in COPULA_WORDS:
        return True
    if normalized.endswith(("ed", "ing")):
        return True
    if normalized.endswith("s") and len(normalized) > 3 and normalized not in COMMON_ADJECTIVE_WORDS:
        return True
    return False


def _is_noun_like(word: dict) -> bool:
    normalized = _word_normalized(word)
    if normalized in ARTICLE_WORDS or normalized in COPULA_WORDS:
        return False
    if normalized in PREPOSITION_WORDS or normalized in CONJUNCTION_WORDS:
        return False
    if _is_adjective_like(word):
        return False
    return True
