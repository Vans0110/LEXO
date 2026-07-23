from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


CONTENT_POS = {"NOUN", "VERB", "ADJ", "ADV", "PROPN", "NUM", "PRON"}
TOKEN_RE = re.compile(r"[\w]+", re.UNICODE)
APPROVED_OVERRIDES = {
    ("book_cad03a8f1779", 4, "students"): 7,
}


def tokens(text: str) -> list[str]:
    return [match.group(0) for match in TOKEN_RE.finditer(text)]


def prefix_score(left: str, right: str) -> float:
    left = left.casefold()
    right = right.casefold()
    common = 0
    while common < min(len(left), len(right)) and left[common] == right[common]:
        common += 1
    if common < 3:
        return 0.0
    return common / min(len(left), len(right))


def word_records(layer: dict) -> dict[str, dict]:
    return {
        f"{str(item.get('lemma') or '').lower()}|{str(item.get('pos') or '').upper()}": item
        for item in layer.get("words") or []
    }


def repair_book(book_dir: Path, apply: bool) -> dict:
    layer_path = book_dir / "book_layer_uk.json"
    verification_path = book_dir / "word_to_word_uk.json"
    layer = json.loads(layer_path.read_text(encoding="utf-8"))
    verification = json.loads(verification_path.read_text(encoding="utf-8"))
    records = word_records(layer)
    parallel = layer.get("parallel") or []
    entries = verification.get("entries") or []
    book_id = str(layer.get("book_id") or "")
    claimed: dict[int, set[int]] = {}
    for entry in entries:
        start = entry.get("target_start_index")
        end = entry.get("target_end_index")
        if isinstance(start, int) and isinstance(end, int) and 0 <= start <= end:
            claimed.setdefault(int(entry.get("segment_index") or 0), set()).update(
                range(start, end + 1)
            )
    changes = []
    for entry in entries:
        if entry.get("status") != "dictionary_fallback":
            continue
        if str(entry.get("pos") or "").upper() not in CONTENT_POS:
            continue
        segment_index = int(entry.get("segment_index") or 0)
        if segment_index < 0 or segment_index >= len(parallel):
            continue
        key = f"{str(entry.get('lemma') or '').lower()}|{str(entry.get('pos') or '').upper()}"
        record = records.get(key) or {}
        translations = [
            str(value).strip()
            for value in record.get("translations") or []
            if str(value).strip()
        ]
        target_tokens = tokens(str(parallel[segment_index].get("translation") or ""))
        override_index = APPROVED_OVERRIDES.get(
            (book_id, segment_index, str(entry.get("surface") or ""))
        )
        if override_index is not None:
            if override_index >= len(target_tokens):
                raise RuntimeError(
                    f"Invalid approved target index for {book_id}:{segment_index}"
                )
            target_token = target_tokens[override_index]
            entry["contextual_translation"] = target_token
            entry["status"] = "independent_translation"
            entry["target_start_index"] = override_index
            entry["target_end_index"] = override_index
            entry["empty_reason"] = ""
            claimed.setdefault(segment_index, set()).add(override_index)
            changes.append(
                {
                    "segment_index": segment_index,
                    "surface": entry.get("surface"),
                    "lemma": entry.get("lemma"),
                    "dictionary_form": entry.get("dictionary_translation"),
                    "contextual_translation": target_token,
                    "target_index": override_index,
                    "score": "approved_semantic_override",
                }
            )
            continue
        candidates = []
        for target_index, target_token in enumerate(target_tokens):
            if target_index in claimed.setdefault(segment_index, set()):
                continue
            for translation in translations:
                translation_tokens = tokens(translation)
                if len(translation_tokens) != 1:
                    continue
                score = prefix_score(translation_tokens[0], target_token)
                if score >= 0.6:
                    candidates.append((score, target_index, target_token, translation))
        if not candidates:
            continue
        source_order = int(entry.get("source_order") or 0)
        source_count = sum(
            1
            for item in entries
            if int(item.get("segment_index") or 0) == segment_index
        )
        source_position = (source_order + 0.5) / max(source_count, 1)
        candidates.sort(
            key=lambda item: (
                -item[0],
                abs(source_position - (item[1] + 0.5) / max(len(target_tokens), 1)),
                item[1],
            )
        )
        score, target_index, target_token, dictionary_form = candidates[0]
        entry["contextual_translation"] = target_token
        entry["status"] = "independent_translation"
        entry["target_start_index"] = target_index
        entry["target_end_index"] = target_index
        entry["empty_reason"] = ""
        claimed[segment_index].add(target_index)
        changes.append(
            {
                "segment_index": segment_index,
                "surface": entry.get("surface"),
                "lemma": entry.get("lemma"),
                "dictionary_form": dictionary_form,
                "contextual_translation": target_token,
                "target_index": target_index,
                "score": round(score, 3),
            }
        )
    if apply and changes:
        verification_path.write_text(
            json.dumps(verification, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return {"book_id": layer.get("book_id"), "changes": changes}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--books-root", type=Path, required=True)
    parser.add_argument("--book-id", action="append", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    report = [
        repair_book(args.books_root / book_id, args.apply)
        for book_id in args.book_id
    ]
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
