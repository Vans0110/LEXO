from __future__ import annotations

import re


def normalize_text(raw_text: str) -> str:
    text = raw_text.replace("\r\n", "\n").replace("\r", "\n")
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.split("\n")]

    normalized_lines: list[str] = []
    previous_blank = False
    for line in lines:
        if not line:
            if previous_blank:
                continue
            normalized_lines.append("")
            previous_blank = True
            continue
        normalized_lines.append(line)
        previous_blank = False

    return "\n".join(normalized_lines).strip()
