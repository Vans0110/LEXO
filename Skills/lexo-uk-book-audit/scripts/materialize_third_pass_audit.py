from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def tokens(value: object) -> set[str]:
    return {match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or ""))}


def write(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Materialize reviewed third-pass word decisions")
    parser.add_argument("book_layer", type=Path)
    parser.add_argument("--mixed", action="append", default=[], help="lemma|POS key with mixed ownership")
    parser.add_argument("--correction", action="append", default=[])
    args = parser.parse_args()

    path = args.book_layer.resolve()
    layer = json.loads(path.read_text(encoding="utf-8"))
    parallel = [item for item in layer.get("parallel") or [] if isinstance(item, dict)]
    absorbed = {clean(key).lower() for key in layer.get("book_layer_audit", {}).get("absorbed_word_keys") or []}
    mixed = {clean(key).lower() for key in args.mixed}
    decisions = []
    for word in layer.get("words") or []:
        lemma = clean(word.get("lemma")).lower()
        pos = clean(word.get("pos")).upper()
        key = f"{lemma}|{pos}"
        forms = tokens(word.get("word")) or tokens(lemma)
        evidence = [
            f"{clean(pair.get('source'))} → {clean(pair.get('translation'))}"
            for pair in parallel
            if forms <= tokens(pair.get("source"))
        ]
        if not evidence:
            raise ValueError(f"No source occurrence evidence for {key}")
        values = [clean(value) for value in word.get("translations") or [] if clean(value)]
        normalized = key.lower()
        if normalized in mixed:
            ownership = "mixed"
        elif normalized in absorbed:
            ownership = "absorbed"
        else:
            ownership = "word"
        decisions.append(
            {
                "key": key,
                "ownership": ownership,
                "translations": values,
                "evidence": evidence,
            }
        )

    audit = layer.setdefault("book_layer_audit", {})
    audit["version"] = 2
    audit["method"] = "codex_independent_three_pass"
    audit["third_pass"] = {
        "status": "passed",
        "word_decisions": decisions,
        "corrections": args.correction,
        "unresolved": [],
    }
    write(path, layer)
    print(json.dumps({"word_decisions": len(decisions), "mixed": sorted(mixed)}, ensure_ascii=False))


if __name__ == "__main__":
    main()

