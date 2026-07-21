from __future__ import annotations

import re


APOSTROPHES = "'’"
WORD_RE = re.compile(
    rf"[^\W_]+(?:[-{APOSTROPHES}][^\W_]+)*",
    re.UNICODE,
)
TOKEN_RE = re.compile(
    rf"[^\W_]+(?:[-{APOSTROPHES}][^\W_]+)*|[^\w\s]",
    re.UNICODE,
)


def normalize_apostrophes(value: str) -> str:
    return str(value or "").replace("’", "'")
