from __future__ import annotations

import re

from .qa_entities import compare_entities, compare_entities_to_target, extract_entities
from .qa_frames import compare_frame_to_target, compare_semantic_frames, extract_semantic_frame
from .qa_relations import evaluate_possessive_relations
from .qa_ru_quality import (
    evaluate_ru_motion_drift,
    evaluate_ru_quality,
    evaluate_ru_speaker_gender,
    evaluate_title_target_shape,
)
from .qa_verbs import compare_verb_frames, extract_verb_frame


CYRILLIC_RE = re.compile(r"[А-Яа-яЁё]")
LATIN_WORD_RE = re.compile(r"[A-Za-z]+")
WORD_RE = re.compile(r"[A-Za-zА-Яа-яЁё0-9]+")
SHORT_SEGMENT_TYPES = {"heading_title", "heading_chapter", "quote_dialogue", "short_phrase"}
RISKY_VERB_GROUPS = {
    "say": {"say", "says", "said", "tell", "tells", "told", "whisper", "whispers", "whispered", "call", "calls", "called", "answer", "answers", "answered"},
    "go_home": {"go", "goes", "went", "come", "comes", "came", "return", "returns", "returned", "home"},
    "sunset": {"sun", "go", "goes", "went", "down", "set", "sets"},
    "tail": {"wag", "wags", "wagged", "tail"},
}
SHORT_TITLE_SUSPECT_WORDS = {
    "title", "chapter", "quote", "dialogue", "phrase", "line", "text",
}


def evaluate_segment_translation(
    *,
    source_text: str,
    target_text: str,
    segment_type: str,
    back_translation: str = "",
) -> dict:
    technical = _evaluate_technical_quality(
        source_text=source_text,
        target_text=target_text,
        segment_type=segment_type,
        back_translation=back_translation,
    )
    ru_quality = _merge_ru_quality_layers(
        [
            evaluate_ru_quality(target_text=target_text, source_text=source_text, segment_type=segment_type),
            evaluate_title_target_shape(target_text=target_text, segment_type=segment_type),
            evaluate_ru_motion_drift(source_text=source_text, target_text=target_text),
            evaluate_ru_speaker_gender(source_text=source_text, target_text=target_text),
        ]
    )
    relation_eval = evaluate_possessive_relations(
        source_text=source_text,
        target_text=target_text,
        segment_type=segment_type,
    )
    source_entities = extract_entities(source_text, segment_type)
    target_entities = compare_entities_to_target(
        source_entities=source_entities,
        target_text=target_text,
        segment_type=segment_type,
    )
    back_entities = extract_entities(back_translation, segment_type)
    entity_back_eval = compare_entities(
        source_entities=source_entities,
        back_entities=back_entities,
        source_text=source_text,
        back_text=back_translation,
        segment_type=segment_type,
    )
    source_frame = extract_semantic_frame(source_text, segment_type)
    frame_target_eval = compare_frame_to_target(
        source_frame=source_frame,
        target_text=target_text,
        segment_type=segment_type,
    )
    back_frame = extract_semantic_frame(back_translation, segment_type)
    frame_back_eval = compare_semantic_frames(
        source_frame=source_frame,
        back_frame=back_frame,
        segment_type=segment_type,
    )
    source_verb_frame = extract_verb_frame(source_text, segment_type)
    back_verb_frame = extract_verb_frame(back_translation, segment_type)
    verb_eval = compare_verb_frames(
        source_frame=source_verb_frame,
        back_frame=back_verb_frame,
        segment_type=segment_type,
        strictness="strict",
    )
    return _merge_quality_layers(
        technical=technical,
        ru_quality=ru_quality,
        relation_eval=relation_eval,
        source_entities=source_entities,
        target_entity_eval=target_entities,
        entity_back_eval=entity_back_eval,
        source_frame=source_frame,
        frame_target_eval=frame_target_eval,
        frame_back_eval=frame_back_eval,
        verb_eval=verb_eval,
        segment_type=segment_type,
        back_translation=back_translation.strip(),
    )


def _evaluate_technical_quality(
    *,
    source_text: str,
    target_text: str,
    segment_type: str,
    back_translation: str,
) -> dict:
    source = source_text.strip()
    target = target_text.strip()
    flags: list[str] = []

    if not target:
        flags.append("empty_target")
        return {"technical_score": 0.0, "semantic_score": 0.0, "technical_flags": flags}

    source_words = WORD_RE.findall(source.lower())
    target_words = WORD_RE.findall(target.lower())
    if not target_words:
        flags.append("empty_target")
        return {"technical_score": 0.0, "semantic_score": 0.0, "technical_flags": flags}

    if _is_copy_of_source(source, target):
        flags.append("copy_source")
    if _has_repetition(target_words):
        flags.append("repetition")
    if _has_english_leftover(source_words, target_words, target):
        flags.append("english_leftover")
    if _has_length_mismatch(source_words, target_words):
        flags.append("length_mismatch")
    semantic_score = _semantic_similarity_score(source, back_translation)
    if back_translation.strip() and semantic_score < 0.45:
        flags.append("semantic_drift")
    if back_translation.strip() and _has_tense_shift_hint(source, back_translation):
        flags.append("tense_shift")
    if back_translation.strip() and _has_suspicious_verb_choice(source, back_translation):
        flags.append("suspicious_verb_choice")
    if _has_bad_short_segment_shape(segment_type, source, target, back_translation):
        flags.append("bad_short_segment")

    score = 1.0
    penalties = {
        "copy_source": 0.60,
        "repetition": 0.45,
        "english_leftover": 0.35,
        "length_mismatch": 0.20,
        "semantic_drift": 0.30,
        "tense_shift": 0.15,
        "suspicious_verb_choice": 0.20,
        "bad_short_segment": 0.20,
    }
    for flag in flags:
        score -= penalties.get(flag, 0.0)
    return {
        "technical_score": max(0.0, round(score, 4)),
        "semantic_score": semantic_score,
        "technical_flags": sorted(set(flags)),
    }


def _merge_quality_layers(
    *,
    technical: dict,
    ru_quality: dict,
    relation_eval: dict,
    source_entities: dict,
    target_entity_eval: dict,
    entity_back_eval: dict,
    source_frame: dict,
    frame_target_eval: dict,
    frame_back_eval: dict,
    verb_eval: dict,
    segment_type: str,
    back_translation: str,
) -> dict:
    entity_flags = sorted(set(list(target_entity_eval.get("entity_flags") or []) + list(entity_back_eval.get("entity_flags") or [])))
    frame_flags = sorted(set(list(frame_target_eval.get("frame_flags") or []) + list(frame_back_eval.get("frame_flags") or [])))
    quality_flags = sorted(
        set(
            list(technical.get("technical_flags") or [])
            + list(ru_quality.get("ru_quality_flags") or [])
            + list(relation_eval.get("relation_flags") or [])
            + entity_flags
            + frame_flags
            + list(verb_eval.get("verb_flags") or [])
        )
    )
    weighted_score = (
        float(technical.get("technical_score") or 0.0) * 0.20
        + float(ru_quality.get("ru_quality_score") or 0.0) * 0.30
        + float(relation_eval.get("relation_score") or 0.0) * 0.10
        + float(target_entity_eval.get("entity_preservation_score") or 0.0) * 0.15
        + float(frame_target_eval.get("frame_preservation_score") or 0.0) * 0.15
        + float(verb_eval.get("verb_score") or 0.0) * 0.10
        + float(entity_back_eval.get("entity_preservation_score") or 0.0) * 0.05
    )
    quality_score = max(0, min(100, round(weighted_score * 100)))
    warn_threshold = 80
    fail_threshold = 50
    if segment_type in SHORT_SEGMENT_TYPES:
        warn_threshold = 85
        fail_threshold = 60
    if {"english_leftover", "semantic_drift"} <= set(quality_flags):
        quality_score = min(quality_score, fail_threshold - 5)
    if {"ru_spelling_error", "ru_gender_mismatch"} & set(quality_flags):
        quality_score = min(quality_score, fail_threshold - 5)
    if {"target_entity_missing", "target_entity_count_mismatch"} & set(quality_flags):
        quality_score = min(quality_score, fail_threshold - 5)
    if {"target_directional_title", "target_motion_transport_drift"} & set(quality_flags):
        quality_score = min(quality_score, fail_threshold - 5)
    if {"target_habitual_motion_drift", "target_possessive_relation_lost"} & set(quality_flags):
        quality_score = min(quality_score, warn_threshold - 5)
    if {"verb_lemma_drift", "verb_argument_drift"} & set(quality_flags):
        quality_score = min(quality_score, fail_threshold - 5)
    if {"verb_meaning_narrowing", "verb_meaning_broadening"} & set(quality_flags):
        quality_score = min(quality_score, warn_threshold - 5)
    retry_reason_flags = sorted(
        set(
            flag
            for flag in quality_flags
            if flag in {
                "ru_spelling_error",
                "ru_agreement_error",
                "ru_gender_mismatch",
                "target_possessive_relation_lost",
                "target_directional_title",
                "target_motion_transport_drift",
                "target_habitual_motion_drift",
                "suspicious_verb_choice",
                "verb_lemma_drift",
                "verb_meaning_narrowing",
                "verb_meaning_broadening",
                "verb_argument_drift",
            }
        )
    )

    if quality_score < fail_threshold:
        quality_status = "fail"
        alignment_confidence = 0.0
    elif quality_score < warn_threshold:
        quality_status = "warn"
        alignment_confidence = 0.55
    else:
        quality_status = "pass"
        alignment_confidence = 1.0
    decision_status = _resolve_decision_status(
        quality_status=quality_status,
        retry_reason_flags=retry_reason_flags,
    )
    return {
        "quality_score": quality_score,
        "semantic_score": float(technical.get("semantic_score") or 0.0),
        "quality_status": quality_status,
        "decision_status": decision_status,
        "quality_flags": quality_flags,
        "ru_quality_score": float(ru_quality.get("ru_quality_score") or 0.0),
        "ru_quality_flags": list(ru_quality.get("ru_quality_flags") or []),
        "retry_reason_flags": retry_reason_flags,
        "alignment_confidence": alignment_confidence,
        "back_translation": back_translation,
        "source_entities": source_entities.get("items") or [],
        "back_entities": entity_back_eval.get("back_entities") or [],
        "entity_preservation_score": float(target_entity_eval.get("entity_preservation_score") or 0.0),
        "entity_flags": entity_flags,
        "source_frame": source_frame,
        "back_frame": frame_back_eval.get("back_frame") or {},
        "frame_preservation_score": float(frame_target_eval.get("frame_preservation_score") or 0.0),
        "frame_flags": frame_flags,
        "verb_score": float(verb_eval.get("verb_score") or 0.0),
        "verb_flags": list(verb_eval.get("verb_flags") or []),
        "source_verb_frame": verb_eval.get("source_verb_frame") or {},
        "back_verb_frame": verb_eval.get("back_verb_frame") or {},
    }


def _resolve_decision_status(*, quality_status: str, retry_reason_flags: list[str]) -> str:
    if retry_reason_flags:
        return "retry_required"
    if quality_status == "fail":
        return "reject"
    if quality_status == "warn":
        return "accept_low_confidence"
    return "accept"


def _merge_ru_quality_layers(layers: list[dict]) -> dict:
    score = 1.0
    flags: list[str] = []
    for layer in layers:
        score = min(score, float(layer.get("ru_quality_score") or 1.0))
        flags.extend([str(flag) for flag in layer.get("ru_quality_flags") or []])
    return {
        "ru_quality_score": max(0.0, round(score, 4)),
        "ru_quality_flags": sorted(set(flags)),
    }


def _is_copy_of_source(source_text: str, target_text: str) -> bool:
    source = _normalize_compare_text(source_text)
    target = _normalize_compare_text(target_text)
    if not source or not target:
        return False
    return source == target


def _has_repetition(words: list[str]) -> bool:
    if len(words) >= 4 and len(set(words)) <= max(1, len(words) // 5):
        return True
    return _has_repeated_ngram(words, size=1, threshold=4) or _has_repeated_ngram(words, size=2, threshold=3)


def _has_repeated_ngram(words: list[str], *, size: int, threshold: int) -> bool:
    if len(words) < size * threshold:
        return False
    count = 1
    previous: tuple[str, ...] | None = None
    for index in range(len(words) - size + 1):
        current = tuple(words[index:index + size])
        if current == previous:
            count += 1
            if count >= threshold:
                return True
        else:
            previous = current
            count = 1
    return False


def _has_english_leftover(source_words: list[str], target_words: list[str], target_text: str) -> bool:
    if not source_words or not target_words:
        return False
    latin_words = [word for word in target_words if LATIN_WORD_RE.search(word)]
    if not latin_words:
        return False
    has_cyrillic = bool(CYRILLIC_RE.search(target_text))
    if not has_cyrillic:
        return True
    return len(latin_words) >= max(2, len(target_words) // 2)


def _has_length_mismatch(source_words: list[str], target_words: list[str]) -> bool:
    if not source_words or not target_words:
        return False
    ratio = len(target_words) / len(source_words)
    return ratio >= 2.8 or ratio <= 0.33


def _normalize_compare_text(text: str) -> str:
    normalized = re.sub(r"\s+", " ", text.strip().lower())
    return re.sub(r"[^\w\s]+", "", normalized)


def _semantic_similarity_score(source_text: str, back_translation: str) -> float:
    source_tokens = _semantic_tokens(source_text)
    back_tokens = _semantic_tokens(back_translation)
    if not back_translation.strip():
        return 1.0
    if not source_tokens or not back_tokens:
        return 0.0
    overlap = len(source_tokens & back_tokens)
    return overlap / max(len(source_tokens), len(back_tokens))


def _semantic_tokens(text: str) -> set[str]:
    stopwords = {
        "a", "an", "the", "is", "are", "am", "was", "were", "be", "been", "being",
        "to", "of", "in", "on", "at", "for", "with", "and", "or", "but", "he",
        "she", "it", "they", "we", "i", "you", "this", "that", "these", "those",
    }
    tokens = {token.lower() for token in WORD_RE.findall(text)}
    return {token for token in tokens if token not in stopwords and len(token) > 1}


def _has_tense_shift_hint(source_text: str, back_translation: str) -> bool:
    source = source_text.lower()
    back = back_translation.lower()
    present_markers = {"is", "are", "goes", "says", "walks", "runs", "looks", "wakes"}
    past_markers = {"was", "were", "went", "said", "walked", "ran", "looked", "woke"}
    future_markers = {"will", "shall"}
    source_present = any(marker in WORD_RE.findall(source) for marker in present_markers)
    source_past = any(marker in WORD_RE.findall(source) for marker in past_markers)
    source_future = any(marker in WORD_RE.findall(source) for marker in future_markers)
    back_present = any(marker in WORD_RE.findall(back) for marker in present_markers)
    back_past = any(marker in WORD_RE.findall(back) for marker in past_markers)
    back_future = any(marker in WORD_RE.findall(back) for marker in future_markers)
    if source_present and (back_past or back_future):
        return True
    if source_past and (back_present or back_future):
        return True
    if source_future and (back_present or back_past):
        return True
    return False


def _has_suspicious_verb_choice(source_text: str, back_translation: str) -> bool:
    source_tokens = _semantic_tokens(source_text)
    back_tokens = _semantic_tokens(back_translation)
    if not source_tokens or not back_tokens:
        return False
    for group_tokens in RISKY_VERB_GROUPS.values():
        source_hits = source_tokens & group_tokens
        if not source_hits:
            continue
        back_hits = back_tokens & group_tokens
        if not back_hits:
            return True
    return False


def _has_bad_short_segment_shape(
    segment_type: str,
    source_text: str,
    target_text: str,
    back_translation: str,
) -> bool:
    if segment_type not in SHORT_SEGMENT_TYPES:
        return False
    source_tokens = WORD_RE.findall(source_text)
    target_tokens = WORD_RE.findall(target_text)
    if len(source_tokens) <= 5 and len(target_tokens) >= max(7, len(source_tokens) * 2 + 1):
        return True
    if segment_type in {"heading_title", "heading_chapter", "short_phrase"}:
        lowered_target = {token.lower() for token in target_tokens}
        if lowered_target & SHORT_TITLE_SUSPECT_WORDS:
            return True
    if back_translation.strip() and _semantic_similarity_score(source_text, back_translation) < 0.6:
        return True
    return False
