from __future__ import annotations

import re


SPACE_BEFORE_PUNCT_RE = re.compile(r"\s+([,.;:!?])")


def assemble_paragraph(segments: list[str]) -> str:
    combined = " ".join(segment.strip() for segment in segments if segment.strip()).strip()
    return SPACE_BEFORE_PUNCT_RE.sub(r"\1", combined)
