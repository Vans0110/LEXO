from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

from engine.library_dictionary import LibraryDictionaryStore

TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)
SOURCE_SUFFIXES = ("s", "es", "ed", "ing")


def _tokens(text: object) -> list[str]:
    return [match.group(0) for match in TOKEN_RE.finditer(str(text or ""))]


def _source_matches(token: str, surface: str, lemma: str) -> bool:
    token = token.lower()
    surface = surface.lower()
    lemma = lemma.lower()
    if token in {surface, lemma}:
        return True
    if lemma and token.startswith(lemma):
        return token[len(lemma) :] in SOURCE_SUFFIXES
    return False


def _context_score(base: str, candidate: str) -> float:
    left = base.lower()
    right = candidate.lower()
    shortest = min(len(left), len(right))
    common = 0
    while common < shortest and left[common] == right[common]:
        common += 1
    if common < 3 or common / shortest < 0.6:
        return 0.0
    length_penalty = abs(len(left) - len(right)) * 0.01
    return common / shortest - length_penalty


def _append_unique(values: list[str], value: str) -> bool:
    clean = re.sub(r"\s+", " ", value).strip()
    if not clean or clean.lower() in {item.lower() for item in values}:
        return False
    values.append(clean)
    return True


def _atomic_write(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def enrich(root: Path, languages: list[str], *, check: bool) -> dict:
    store = LibraryDictionaryStore(root)
    summary: dict[str, dict] = {}
    for lang in languages:
        books_changed = 0
        forms_added = 0
        layers = sorted(store.books_dir(lang).glob(f"*/book_layer_{lang}.json"))
        for layer_path in layers:
            payload = json.loads(layer_path.read_text(encoding="utf-8"))
            parallel = payload.get("parallel") if isinstance(payload, dict) else []
            words = payload.get("words") if isinstance(payload, dict) else []
            if not isinstance(parallel, list) or not isinstance(words, list):
                continue
            changed = False
            for word in words:
                if not isinstance(word, dict):
                    continue
                surface = str(word.get("word") or "").strip()
                lemma = str(word.get("lemma") or surface).strip()
                primary = str(word.get("translation") or "").strip()
                translations = word.get("translations")
                if not isinstance(translations, list):
                    translations = []
                normalized = []
                for value in [primary, *translations]:
                    if isinstance(value, str):
                        _append_unique(normalized, value)
                bases = [value for value in normalized if len(_tokens(value)) == 1]
                if not bases:
                    continue
                for segment in parallel:
                    if not isinstance(segment, dict):
                        continue
                    source_tokens = _tokens(segment.get("source"))
                    if not any(
                        _source_matches(token, surface, lemma)
                        for token in source_tokens
                    ):
                        continue
                    target_tokens = _tokens(segment.get("translation"))
                    for base in bases:
                        scored = [
                            (_context_score(base, target_token), target_token)
                            for target_token in target_tokens
                        ]
                        score, contextual = max(scored, default=(0.0, ""))
                        if score > 0.0 and _append_unique(normalized, contextual):
                            forms_added += 1
                            changed = True
                if normalized != translations:
                    word["translations"] = normalized
                    changed = True
            if changed:
                books_changed += 1
                if not check:
                    _atomic_write(layer_path, payload)
        summary[lang] = {
            "books": len(layers),
            "books_changed": books_changed,
            "context_forms_added": forms_added,
        }
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--languages", nargs="+", default=["ru", "uk"])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = enrich(args.root.resolve(), args.languages, check=args.check)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()