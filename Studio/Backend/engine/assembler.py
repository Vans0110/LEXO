from __future__ import annotations

import re


SPACE_BEFORE_PUNCT_RE = re.compile(r"\s+([,.;:!?])")
HEADING_SEGMENT_TYPES = {"heading_title", "heading_chapter"}

def assemble_paragraph(segments: list[dict]) -> str:
    lines: list[str] = []
    current_parts: list[str] = []

    def flush_current() -> None:
        if not current_parts:
            return
        combined = " ".join(part.strip() for part in current_parts if part.strip()).strip()
        if combined:
            lines.append(SPACE_BEFORE_PUNCT_RE.sub(r"\1", combined))
        current_parts.clear()

    for segment in segments:
        text = str(segment.get("target_text") or "").strip()
        if not text:
            continue
        segment_type = str(segment.get("segment_type") or "simple_action")
        if segment_type in HEADING_SEGMENT_TYPES:
            flush_current()
            lines.append(SPACE_BEFORE_PUNCT_RE.sub(r"\1", text))
            continue
        current_parts.append(text)

    flush_current()
    return "\n".join(lines).strip()
