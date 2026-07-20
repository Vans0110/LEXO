from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def write(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Materialize reviewed block-necessity decisions")
    parser.add_argument("book_layer", type=Path)
    args = parser.parse_args()
    path = args.book_layer.resolve()
    layer = json.loads(path.read_text(encoding="utf-8"))
    review = json.load(sys.stdin)
    if not isinstance(review, list):
        raise ValueError("stdin must contain a JSON decision list")

    decisions: dict[str, dict[str, Any]] = {}
    for item in review:
        if not isinstance(item, dict):
            raise ValueError("every decision must be an object")
        source = clean(item.get("source")).casefold()
        decision = clean(item.get("decision")).lower()
        if not source or decision not in {"accepted", "rejected"}:
            raise ValueError("every decision requires source and accepted/rejected")
        if source in decisions:
            raise ValueError(f"duplicate decision for {source}")
        if not clean(item.get("word_by_word_result")) or not clean(item.get("reason")):
            raise ValueError(f"decision for {source} requires word_by_word_result and reason")
        if any("???" in clean(value) or "�" in clean(value) for value in item.values()):
            raise ValueError(f"encoding corruption in decision for {source}")
        decisions[source] = item

    blocks = [item for item in layer.get("blocks") or [] if isinstance(item, dict)]
    block_sources = {clean(item.get("source")).casefold() for item in blocks}
    accepted_review_sources = {
        source for source, item in decisions.items() if item.get("decision") == "accepted"
    }
    if accepted_review_sources != block_sources:
        raise ValueError(
            f"accepted decisions disagree with blocks: missing={sorted(block_sources-accepted_review_sources)}, "
            f"extra={sorted(accepted_review_sources-block_sources)}"
        )
    accepted = []
    parallel = [item for item in layer.get("parallel") or [] if isinstance(item, dict)]
    for block in blocks:
        source = clean(block.get("source")).casefold()
        decision = decisions[source]
        occurrences = [item for item in block.pop("occurrences", []) if isinstance(item, dict)]
        block.pop("necessity", None)
        source_forms = [clean(item.get("source_form")) for item in occurrences if clean(item.get("source_form"))]
        if not source_forms:
            source_forms = [clean(item) for item in block.get("source_forms") or [] if clean(item)]
        block["source_forms"] = list(dict.fromkeys(source_forms or [clean(block.get("source"))]))
        indexes = []
        for occurrence in occurrences:
            pair = (clean(occurrence.get("source_text")), clean(occurrence.get("target_text")))
            for index, segment in enumerate(parallel):
                if pair == (clean(segment.get("source")), clean(segment.get("translation"))):
                    indexes.append(index)
        if not indexes:
            forms = {item.casefold() for item in block["source_forms"]}
            indexes = [
                index for index, segment in enumerate(parallel)
                if any(form in clean(segment.get("source")).casefold() for form in forms)
            ]
        supplied_indexes = decision.get("segment_indexes")
        if isinstance(supplied_indexes, list):
            indexes.extend(item for item in supplied_indexes if isinstance(item, int))
        decision["segment_indexes"] = sorted(set(indexes))
        if not decision["segment_indexes"]:
            raise ValueError(f"No segment evidence for {source}")
        if decision["decision"] != "accepted":
            continue
        accepted.append(block)

    accepted_sources = {clean(item.get("source")).casefold() for item in accepted}
    for source, decision in decisions.items():
        indexes = decision.get("segment_indexes")
        if not isinstance(indexes, list) or not indexes:
            raise ValueError(f"No segment evidence for {source}")
    audit = layer.setdefault("book_layer_audit", {})
    for segment in audit.get("reviewed_segments") or []:
        sources = [
            source for source in segment.get("block_sources") or []
            if clean(source).casefold() in accepted_sources
        ]
        segment["block_sources"] = sources
        segment["status"] = "covered" if sources else "no_block_required"
    audit["version"] = max(int(audit.get("version") or 0), 3)
    audit["fourth_pass"] = {
        "status": "passed",
        "block_decisions": review,
        "unresolved": [],
    }
    layer["blocks"] = accepted
    write(path, layer)
    write(path.with_name("seed_blocks_uk.json"), accepted)
    print(json.dumps({"candidates": len(blocks), "accepted": len(accepted), "rejected": len(blocks)-len(accepted)}, ensure_ascii=False))


if __name__ == "__main__":
    main()

