from __future__ import annotations

import re


SENTENCE_RE = re.compile(r"[^.!?]+[.!?]?|[.!?]+")


def split_paragraphs(text: str) -> list[str]:
    return [item.strip() for item in re.split(r"\n\s*\n+", text) if item.strip()]


def split_sentences(paragraph: str) -> list[str]:
    segments: list[str] = []
    for line in str(paragraph or "").splitlines():
        line = line.strip()
        if not line:
            continue
        sentences = [match.group(0).strip() for match in SENTENCE_RE.finditer(line) if match.group(0).strip()]
        segments.extend(sentences or [line])
    return segments or ([paragraph.strip()] if paragraph.strip() else [])


def split_study_segments(paragraph: str) -> list[dict]:
    return [
        {
            "source_text": sentence,
            "target_text": "",
            "segment_type": "source_segment",
            "segment_meta": {},
            "segment_meta_json": "{}",
            "translation_kind": "none",
            "analysis_version": "source_only_v1",
        }
        for sentence in split_sentences(paragraph)
    ]
