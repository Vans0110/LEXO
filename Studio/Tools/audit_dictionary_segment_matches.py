from __future__ import annotations

import argparse
import json
import re
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any


BACKEND_ROOT = Path(__file__).resolve().parents[1] / "Backend"
sys.path.insert(0, str(BACKEND_ROOT))

from engine.config import STANZA_RESOURCES_DIR


WORD_RE = re.compile(r"[^\W_]+(?:['’][^\W_]+)*", re.UNICODE)


def normalized_tokens(text: str) -> list[str]:
    return [token.lower() for token in WORD_RE.findall(str(text or ""))]


def contains_sequence(haystack: list[str], needle: list[str]) -> bool:
    if not needle or len(needle) > len(haystack):
        return False
    width = len(needle)
    return any(haystack[index : index + width] == needle for index in range(len(haystack) - width + 1))


@lru_cache(maxsize=2)
def load_pipeline(lang: str) -> Any:
    import stanza

    return stanza.Pipeline(
        lang=lang,
        processors="tokenize,pos,lemma",
        dir=str(STANZA_RESOURCES_DIR),
        use_gpu=False,
        verbose=False,
    )


@lru_cache(maxsize=4096)
def lemma_tokens(lang: str, text: str) -> tuple[str, ...]:
    doc = load_pipeline(lang)(str(text or ""))
    return tuple(
        str(word.lemma or word.text or "").strip().lower()
        for sentence in doc.sentences
        for word in sentence.words
        if str(word.upos or "") != "PUNCT" and str(word.lemma or word.text or "").strip()
    )


def audit_language(dictionary_path: Path, lang: str) -> dict:
    payload = json.loads(dictionary_path.read_text(encoding="utf-8"))
    results = []
    counts = {"exact": 0, "lemma": 0, "no_match": 0, "no_segment": 0}
    for dictionary_key, entry in payload.get("entries", {}).items():
        segment = str(entry.get("target_segment") or "").strip()
        translations = [
            str(item or "").strip()
            for item in entry.get("translations", [])
            if str(item or "").strip()
        ]
        segment_tokens = normalized_tokens(segment)
        segment_lemmas = list(lemma_tokens(lang, segment)) if segment else []
        matches = []
        for translation in translations:
            translation_tokens = normalized_tokens(translation)
            if contains_sequence(segment_tokens, translation_tokens):
                matches.append(
                    {
                        "translation": translation,
                        "match": "exact",
                        "translation_tokens": translation_tokens,
                    }
                )
                continue
            translation_lemmas = list(lemma_tokens(lang, translation))
            if contains_sequence(segment_lemmas, translation_lemmas):
                matches.append(
                    {
                        "translation": translation,
                        "match": "lemma",
                        "translation_lemmas": translation_lemmas,
                    }
                )
        if not segment:
            status = "no_segment"
        elif matches:
            status = "exact" if any(item["match"] == "exact" for item in matches) else "lemma"
        else:
            status = "no_match"
        counts[status] += 1
        results.append(
            {
                "dictionary_key": dictionary_key,
                "query": entry.get("query", ""),
                "lemma": entry.get("lemma", ""),
                "pos": entry.get("part_of_speech", ""),
                "source_segment": entry.get("source_segment", ""),
                "target_segment": segment,
                "translations": translations,
                "matches": matches,
                "status": status,
                "mt_generated": bool(entry.get("mt_generated")),
            }
        )
    return {
        "language": lang,
        "dictionary": str(dictionary_path),
        "source": payload.get("source", ""),
        "summary": {"entries": len(results), **counts},
        "results": results,
    }


def print_report(report: dict, show: str) -> None:
    summary = report["summary"]
    print(
        f"{report['language'].upper()}: entries={summary['entries']} "
        f"exact={summary['exact']} lemma={summary['lemma']} "
        f"no_match={summary['no_match']} no_segment={summary['no_segment']}"
    )
    allowed = {"exact", "lemma"} if show == "matches" else {show}
    for item in report["results"]:
        if item["status"] not in allowed:
            continue
        matched = ", ".join(
            f"{match['translation']} [{match['match']}]"
            for match in item["matches"]
        )
        print(
            f"- {item['dictionary_key']}: {matched or 'NO MATCH'}\n"
            f"  dictionary: {', '.join(item['translations'])}\n"
            f"  segment: {item['target_segment']}"
        )


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(
        description="Compare dictionary translations with their translated segments."
    )
    parser.add_argument("book_dir", type=Path)
    parser.add_argument("--langs", nargs="+", default=["ru", "uk"], choices=["ru", "uk"])
    parser.add_argument(
        "--show",
        default="matches",
        choices=["matches", "exact", "lemma", "no_match", "no_segment"],
    )
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    reports = []
    for lang in args.langs:
        dictionary_path = args.book_dir / f"dictionary_{lang}.json"
        if not dictionary_path.exists():
            raise FileNotFoundError(dictionary_path)
        report = audit_language(dictionary_path, lang)
        reports.append(report)
        print_report(report, args.show)

    if args.json_output is not None:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(
            json.dumps(reports, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
