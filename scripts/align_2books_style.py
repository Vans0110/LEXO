#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


WORD_RE = re.compile(r"[A-Za-zА-Яа-яЁё0-9]+(?:[':-][A-Za-zА-Яа-яЁё0-9]+)*")
SENTENCE_BREAK_RE = re.compile(r"[.!?](?:[\"'”»)]*)\s*$")

EN_FUNCTION_WORDS = {
    "a",
    "an",
    "the",
    "and",
    "or",
    "but",
    "if",
    "to",
    "of",
    "in",
    "on",
    "at",
    "for",
    "from",
    "with",
    "by",
    "into",
    "onto",
    "up",
    "down",
    "over",
    "under",
    "through",
    "is",
    "am",
    "are",
    "was",
    "were",
    "be",
    "been",
    "being",
    "do",
    "does",
    "did",
    "have",
    "has",
    "had",
    "he",
    "she",
    "it",
    "they",
    "we",
    "you",
    "i",
    "his",
    "her",
    "their",
    "our",
    "my",
    "your",
    "this",
    "that",
    "these",
    "those",
    "some",
    "many",
    "every",
}

# Небольшой встроенный словарь только для демонстрации на `The Bus Driver`.
BUILTIN_LEXICON = {
    "bus": ["автобус", "автобуса"],
    "driver": ["водитель"],
    "nick": ["ник"],
    "work": ["работает"],
    "works": ["работает"],
    "city": ["город"],
    "big": ["больш"],
    "every": ["каждый"],
    "day": ["день"],
    "wake": ["просып"],
    "wakes": ["просып"],
    "up": ["просып"],
    "at": ["в"],
    "six": ["шесть"],
    "o'clock": ["час"],
    "drink": ["пь"],
    "drinks": ["пь"],
    "tea": ["чай"],
    "eat": ["ест"],
    "eats": ["ест"],
    "apple": ["яблок"],
    "like": ["люб"],
    "likes": ["люб"],
    "job": ["работ"],
    "drive": ["вод"],
    "drives": ["вод"],
    "yellow": ["желт"],
    "morning": ["утр"],
    "people": ["люд"],
    "get": ["сад", "заход"],
    "on": ["на", "в"],
    "tired": ["устав"],
    "happy": ["счаст"],
    "say": ["говор"],
    "says": ["говор"],
    "good": ["добр"],
}

DEMO_SOURCE = (
    "The Bus Driver\n\n"
    "Nick is a bus driver. "
    "He works in a big city. "
    "Every day, he wakes up at six o'clock. "
    "He drinks tea and eats an apple."
)

DEMO_TARGET = (
    "Водитель автобуса\n\n"
    "Ник — водитель автобуса. "
    "Он работает в большом городе. "
    "Каждый день он просыпается в шесть часов. "
    "Он пьет чай и ест яблоко."
)


@dataclass
class SurfaceToken:
    text: str
    left: str
    right: str


@dataclass
class AlignedToken:
    text: str
    left: str
    right: str
    target_index: int | None
    score: int | None
    reason: str
    lexical_score: float


@dataclass
class SentenceAlignment:
    source_start: int
    source_end: int
    target_start: int
    target_end: int


@dataclass
class TargetIndexDecision:
    target_index: int
    lexical_score: float
    reason: str
    projected_index: int


@dataclass
class Frame:
    sentence_local_index: int
    source_indexes: list[int]
    target_min: int
    target_max: int


@dataclass
class SentenceWorkItem:
    source_tokens: list[SurfaceToken]
    target_tokens: list[SurfaceToken]
    aligned_tokens: list[AlignedToken]
    frames: list[Frame]
    frame_debug: list[dict[str, Any]]


def normalize_en(text: str) -> str:
    value = text.lower()
    value = re.sub(r"[^a-z0-9']+", "", value)
    for suffix in ("'s", "ing", "ed", "es", "s"):
        if len(value) > len(suffix) + 2 and value.endswith(suffix):
            value = value[: -len(suffix)]
            break
    return value


def normalize_ru(text: str) -> str:
    value = text.lower().replace("ё", "е")
    return re.sub(r"[^а-я0-9]+", "", value)


def tokenize_surface(text: str) -> list[SurfaceToken]:
    matches = list(WORD_RE.finditer(text))
    tokens: list[SurfaceToken] = []
    for idx, match in enumerate(matches):
        left = text[matches[idx - 1].end() : match.start()] if idx > 0 else text[: match.start()]
        right = text[match.end() : matches[idx + 1].start()] if idx + 1 < len(matches) else text[match.end() :]
        if idx > 0:
            left = ""
        tokens.append(SurfaceToken(text=match.group(0), left=left, right=right))
    return tokens


def sentence_starts(tokens: list[SurfaceToken]) -> list[int]:
    if not tokens:
        return []
    starts = [0]
    for idx, token in enumerate(tokens[:-1]):
        if SENTENCE_BREAK_RE.search(token.right):
            starts.append(idx + 1)
    return starts


def split_sentence_ranges(starts: list[int], token_count: int) -> list[tuple[int, int]]:
    if not starts:
        return []
    ranges: list[tuple[int, int]] = []
    for idx, start in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else token_count
        ranges.append((start, end))
    return ranges


def load_lexicon(path: Path | None) -> dict[str, list[str]]:
    merged = {key: list(value) for key, value in BUILTIN_LEXICON.items()}
    if path is None:
        return merged
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("lexicon json must be an object: {source_key: [target_prefixes...]}")
    for key, value in payload.items():
        if isinstance(value, str):
            merged[normalize_en(key)] = [normalize_ru(value)]
        else:
            merged[normalize_en(key)] = [normalize_ru(str(item)) for item in value]
    return merged


def lexical_candidates(
    source_token: str,
    target_tokens: list[SurfaceToken],
    lexicon: dict[str, list[str]],
) -> list[tuple[int, float]]:
    source_key = normalize_en(source_token)
    hints = lexicon.get(source_key) or []
    if not hints:
        return []
    matches: list[tuple[int, float]] = []
    for idx, token in enumerate(target_tokens):
        target_key = normalize_ru(token.text)
        best = 0.0
        for hint in hints:
            if not hint:
                continue
            if target_key == hint:
                best = max(best, 1.0)
            elif target_key.startswith(hint) or hint.startswith(target_key):
                best = max(best, 0.8)
        if best > 0.0:
            matches.append((idx, best))
    return matches


def choose_target_index(
    source_token: str,
    local_source_idx: int,
    source_len: int,
    target_tokens: list[SurfaceToken],
    prev_target_idx: int | None,
    lexicon: dict[str, list[str]],
) -> TargetIndexDecision:
    projected = 0 if not target_tokens else round((local_source_idx / max(1, source_len - 1)) * (len(target_tokens) - 1))
    candidates = lexical_candidates(source_token, target_tokens, lexicon)
    best_idx = projected
    best_score = 0.05
    best_reason = "positional_fallback"
    for idx, lexical_score in candidates:
        distance_penalty = abs(idx - projected) / max(1, len(target_tokens))
        monotonic_penalty = 0.0
        if prev_target_idx is not None and idx < prev_target_idx - 2:
            monotonic_penalty = 0.35
        score = lexical_score - distance_penalty - monotonic_penalty
        if score > best_score:
            best_score = score
            best_idx = idx
            best_reason = "lexical_prior"
    if prev_target_idx is not None and best_idx < prev_target_idx - 3 and best_reason == "positional_fallback":
        best_idx = prev_target_idx
        best_reason = "monotonic_fallback"
    return TargetIndexDecision(
        target_index=best_idx,
        lexical_score=best_score,
        reason=best_reason,
        projected_index=projected,
    )


def frame_break(prev_idx: int, current_idx: int, frame_min: int, frame_max: int) -> bool:
    if current_idx < prev_idx - 1:
        return True
    span = frame_max - frame_min
    if current_idx > frame_max + max(2, span + 1):
        return True
    return False


def classify_frame(
    items: list[AlignedToken],
    frame: Frame,
) -> dict[str, Any]:
    frame_token_indexes = frame.source_indexes
    by_target: dict[int, list[int]] = defaultdict(list)
    for idx in frame_token_indexes:
        target_idx = items[idx].target_index
        if target_idx is not None:
            by_target[target_idx].append(idx)

    frame_debug = {
        "sentence_local_index": frame.sentence_local_index,
        "source_indexes": list(frame.source_indexes),
        "target_span": [frame.target_min, frame.target_max],
        "target_groups": [],
    }

    for target_idx, source_indexes in by_target.items():
        content = [
            idx
            for idx in source_indexes
            if normalize_en(items[idx].text) not in EN_FUNCTION_WORDS
        ]
        if content:
            head_idx = max(content, key=lambda idx: (items[idx].lexical_score, -idx))
        else:
            head_idx = max(source_indexes, key=lambda idx: items[idx].lexical_score)

        group_debug = {
            "target_index": target_idx,
            "source_indexes": list(source_indexes),
            "source_tokens": [items[idx].text for idx in source_indexes],
            "head_index": head_idx,
            "head_token": items[head_idx].text,
        }
        for idx in source_indexes:
            token = items[idx]
            if idx == head_idx:
                if normalize_en(token.text) in EN_FUNCTION_WORDS and any(
                    normalize_en(items[other].text) not in EN_FUNCTION_WORDS for other in frame_token_indexes if other != idx
                ):
                    if token.lexical_score >= 0.75 and len(frame_token_indexes) <= 2:
                        token.score = 100
                        token.reason = "frame_head_function_strong"
                    else:
                        token.score = 0
                        token.reason = "frame_secondary_function"
                else:
                    token.score = 100
                    token.reason = "frame_head"
                continue

            if token.target_index == items[head_idx].target_index:
                token.score = None
                token.reason = "attached_residue_shared_target"
            elif normalize_en(token.text) in EN_FUNCTION_WORDS:
                token.score = 0
                token.reason = "explicit_secondary_function"
            else:
                token.score = 100
                token.reason = "additional_content_head"
        frame_debug["target_groups"].append(group_debug)
    return frame_debug


def build_target_indices(
    source_tokens: list[SurfaceToken],
    target_tokens: list[SurfaceToken],
    lexicon: dict[str, list[str]],
) -> list[AlignedToken]:
    aligned: list[AlignedToken] = []
    prev_target_idx: int | None = None
    for idx, token in enumerate(source_tokens):
        decision = choose_target_index(
            source_token=token.text,
            local_source_idx=idx,
            source_len=len(source_tokens),
            target_tokens=target_tokens,
            prev_target_idx=prev_target_idx,
            lexicon=lexicon,
        )
        aligned.append(
            AlignedToken(
                text=token.text,
                left=token.left,
                right=token.right,
                target_index=decision.target_index,
                score=None,
                reason=decision.reason,
                lexical_score=decision.lexical_score,
            )
        )
        prev_target_idx = decision.target_index
    return aligned


def split_frames(aligned: list[AlignedToken]) -> list[Frame]:
    frames: list[Frame] = []
    current_frame: list[int] = []
    frame_min = 0
    frame_max = 0
    sentence_local_index = 0
    for idx, token in enumerate(aligned):
        if token.target_index is None:
            continue
        if not current_frame:
            current_frame = [idx]
            frame_min = token.target_index
            frame_max = token.target_index
            continue
        prev_idx = aligned[current_frame[-1]].target_index
        assert prev_idx is not None
        assert token.target_index is not None
        if frame_break(prev_idx, token.target_index, frame_min, frame_max):
            frames.append(
                Frame(
                    sentence_local_index=sentence_local_index,
                    source_indexes=list(current_frame),
                    target_min=frame_min,
                    target_max=frame_max,
                )
            )
            sentence_local_index += 1
            current_frame = [idx]
            frame_min = token.target_index
            frame_max = token.target_index
            continue
        current_frame.append(idx)
        frame_min = min(frame_min, token.target_index)
        frame_max = max(frame_max, token.target_index)
    if current_frame:
        frames.append(
            Frame(
                sentence_local_index=sentence_local_index,
                source_indexes=list(current_frame),
                target_min=frame_min,
                target_max=frame_max,
            )
        )
    return frames


def classify_roles(aligned: list[AlignedToken], frames: list[Frame]) -> list[dict[str, Any]]:
    frame_debug: list[dict[str, Any]] = []
    for frame in frames:
        frame_debug.append(classify_frame(aligned, frame))
    return frame_debug


def align_sentence_pair(
    source_tokens: list[SurfaceToken],
    target_tokens: list[SurfaceToken],
    lexicon: dict[str, list[str]],
) -> SentenceWorkItem:
    aligned = build_target_indices(source_tokens, target_tokens, lexicon)
    frames = split_frames(aligned)
    frame_debug = classify_roles(aligned, frames)
    return SentenceWorkItem(
        source_tokens=source_tokens,
        target_tokens=target_tokens,
        aligned_tokens=aligned,
        frames=frames,
        frame_debug=frame_debug,
    )


def align_texts(source_text: str, target_text: str, lexicon: dict[str, list[str]]) -> dict[str, Any]:
    source_tokens = tokenize_surface(source_text)
    target_tokens = tokenize_surface(target_text)
    source_starts = sentence_starts(source_tokens)
    target_starts = sentence_starts(target_tokens)
    source_ranges = split_sentence_ranges(source_starts, len(source_tokens))
    target_ranges = split_sentence_ranges(target_starts, len(target_tokens))

    sentence_pairs: list[SentenceAlignment] = []
    for idx, (src_start, src_end) in enumerate(source_ranges):
        if idx < len(target_ranges):
            tgt_start, tgt_end = target_ranges[idx]
        elif target_ranges:
            tgt_start, tgt_end = target_ranges[-1]
        else:
            tgt_start, tgt_end = 0, len(target_tokens)
        sentence_pairs.append(
            SentenceAlignment(
                source_start=src_start,
                source_end=src_end,
                target_start=tgt_start,
                target_end=tgt_end,
            )
        )

    aligned_tokens: list[AlignedToken] = []
    diagnostics: list[dict[str, Any]] = []
    for pair in sentence_pairs:
        local_source = source_tokens[pair.source_start : pair.source_end]
        local_target = target_tokens[pair.target_start : pair.target_end]
        work_item = align_sentence_pair(local_source, local_target, lexicon)
        local_aligned = work_item.aligned_tokens
        for token in local_aligned:
            if token.target_index is not None:
                token.target_index += pair.target_start
        aligned_tokens.extend(local_aligned)
        adjusted_frames = [
            {
                "sentence_local_index": frame.sentence_local_index,
                "source_indexes": [pair.source_start + idx for idx in frame.source_indexes],
                "source_tokens": [local_aligned[idx].text for idx in frame.source_indexes],
                "target_span": [pair.target_start + frame.target_min, pair.target_start + frame.target_max],
                "local_target_span": [frame.target_min, frame.target_max],
            }
            for frame in work_item.frames
        ]
        diagnostics.append(
            {
                "source_range": [pair.source_start, pair.source_end],
                "target_range": [pair.target_start, pair.target_end],
                "source_text": "".join(token.left + token.text + token.right for token in local_source).strip(),
                "target_text": "".join(token.left + token.text + token.right for token in local_target).strip(),
                "target_indices": [token.target_index for token in local_aligned],
                "scores": [token.score for token in local_aligned],
                "frames": adjusted_frames,
                "role_debug": [
                    {
                        "sentence_local_index": frame["sentence_local_index"],
                        "target_span": [
                            pair.target_start + frame["target_span"][0],
                            pair.target_start + frame["target_span"][1],
                        ],
                        "target_groups": [
                            {
                                "target_index": pair.target_start + group["target_index"],
                                "source_indexes": [pair.source_start + idx for idx in group["source_indexes"]],
                                "source_tokens": list(group["source_tokens"]),
                                "head_index": pair.source_start + group["head_index"],
                                "head_token": group["head_token"],
                            }
                            for group in frame["target_groups"]
                        ],
                    }
                    for frame in work_item.frame_debug
                ],
            }
        )

    payload = {
        "version": 2,
        "translator": "standalone_2books_rebuild",
        "sentences": source_starts,
        "tokens1": [
            [token.text, token.left, token.right, token.target_index, token.score]
            for token in aligned_tokens
        ],
        "tokens2": [[token.text, token.left, token.right] for token in target_tokens],
        "footnotes1": [],
        "footnotes2": [],
        "diagnostics": diagnostics,
    }
    return payload


def compare_with_page(payload: dict[str, Any], compare_path: Path) -> dict[str, Any]:
    with gzip.open(compare_path, "rt", encoding="utf-8") as handle:
        ground_truth = json.load(handle)

    predicted_tokens = payload.get("tokens1") or []
    actual_tokens = ground_truth.get("tokens1") or []
    overlap = min(len(predicted_tokens), len(actual_tokens))
    mismatch_items: list[dict[str, Any]] = []
    same_target = 0
    same_score = 0
    for idx in range(overlap):
        pred = predicted_tokens[idx]
        actual = actual_tokens[idx]
        if pred[3] == actual[3]:
            same_target += 1
        if pred[4] == actual[4]:
            same_score += 1
        if pred[3] != actual[3] or pred[4] != actual[4]:
            mismatch_items.append(
                {
                    "index": idx,
                    "token": pred[0],
                    "pred_target": pred[3],
                    "actual_target": actual[3],
                    "pred_score": pred[4],
                    "actual_score": actual[4],
                }
            )
    return {
        "compare_path": str(compare_path),
        "predicted_token_count": len(predicted_tokens),
        "actual_token_count": len(actual_tokens),
        "target_index_match_rate": round(same_target / max(1, overlap), 4),
        "score_match_rate": round(same_score / max(1, overlap), 4),
        "first_mismatches": mismatch_items[:20],
    }


def aggregate_batch_comparisons(items: list[dict[str, Any]]) -> dict[str, Any]:
    target_rates = [float(item.get("target_index_match_rate") or 0.0) for item in items]
    score_rates = [float(item.get("score_match_rate") or 0.0) for item in items]
    token_counter: Counter[str] = Counter()
    token_score_pairs: Counter[str] = Counter()
    for item in items:
        for mismatch in item.get("first_mismatches") or []:
            token = str(mismatch.get("token") or "")
            token_counter[token] += 1
            token_score_pairs[
                f"{token}: pred={mismatch.get('pred_score')} actual={mismatch.get('actual_score')}"
            ] += 1
    return {
        "cases": len(items),
        "avg_target_index_match_rate": round(sum(target_rates) / max(1, len(target_rates)), 4),
        "avg_score_match_rate": round(sum(score_rates) / max(1, len(score_rates)), 4),
        "min_target_index_match_rate": round(min(target_rates or [0.0]), 4),
        "min_score_match_rate": round(min(score_rates or [0.0]), 4),
        "top_mismatch_tokens": [
            {"token": token, "count": count}
            for token, count in token_counter.most_common(10)
        ],
        "top_score_mismatch_pairs": [
            {"pattern": key, "count": count}
            for key, count in token_score_pairs.most_common(10)
        ],
    }


def summarize(payload: dict[str, Any]) -> dict[str, Any]:
    tokens1 = payload.get("tokens1") or []
    score_counts = Counter(item[4] for item in tokens1)
    return {
        "tokens1": len(tokens1),
        "tokens2": len(payload.get("tokens2") or []),
        "sentences": payload.get("sentences") or [],
        "score_counts": {
            "100": score_counts.get(100, 0),
            "0": score_counts.get(0, 0),
            "null": score_counts.get(None, 0),
        },
    }


def read_text_arg(text: str | None, path: Path | None) -> str:
    if text:
        return text
    if path:
        return path.read_text(encoding="utf-8")
    raise ValueError("provide either text or file input")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Standalone experimental 2Books-style late bilingual enrichment builder.",
    )
    parser.add_argument("--source-text")
    parser.add_argument("--target-text")
    parser.add_argument("--source-file", type=Path)
    parser.add_argument("--target-file", type=Path)
    parser.add_argument("--lexicon-json", type=Path)
    parser.add_argument("--compare-page", type=Path)
    parser.add_argument("--compare-pages", nargs="+", type=Path)
    parser.add_argument("--compare-glob")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    parser.add_argument("--demo-bus-driver", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    lexicon = load_lexicon(args.lexicon_json)

    if args.demo_bus_driver:
        source_text = DEMO_SOURCE
        target_text = DEMO_TARGET
    else:
        source_text = read_text_arg(args.source_text, args.source_file)
        target_text = read_text_arg(args.target_text, args.target_file)

    payload = align_texts(source_text, target_text, lexicon)
    result: dict[str, Any] = {
        "summary": summarize(payload),
        "payload": payload,
    }
    compare_paths: list[Path] = []
    if args.compare_page:
        compare_paths.append(args.compare_page)
    if args.compare_pages:
        compare_paths.extend(args.compare_pages)
    if args.compare_glob:
        compare_paths.extend(sorted(Path(".").glob(args.compare_glob)))
    if compare_paths:
        deduped_paths: list[Path] = []
        seen: set[str] = set()
        for path in compare_paths:
            key = str(path)
            if key in seen:
                continue
            seen.add(key)
            deduped_paths.append(path)
        comparisons = [compare_with_page(payload, path) for path in deduped_paths]
        if len(comparisons) == 1:
            result["comparison"] = comparisons[0]
        else:
            result["comparisons"] = comparisons
            result["batch_summary"] = aggregate_batch_comparisons(comparisons)

    text = json.dumps(result, ensure_ascii=False, indent=2 if args.pretty or True else None)
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
