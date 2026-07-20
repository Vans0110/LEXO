from __future__ import annotations

from typing import Any


FUNCTION_POS = {"ADP", "AUX", "CCONJ", "DET", "EXPL", "PART", "SCONJ"}


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def normalize_key(value: object) -> str:
    lemma, separator, pos = clean(value).partition("|")
    return f"{lemma.casefold()}|{pos.upper()}" if separator and lemma and pos else ""


def function_candidates(words: dict[str, Any]) -> list[str]:
    candidates = []
    for raw_key in words:
        key = normalize_key(raw_key)
        if key and key.rsplit("|", 1)[1] in FUNCTION_POS:
            candidates.append(key)
    return sorted(set(candidates))


def function_errors(functions: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    normalized: set[str] = set()
    for raw_key, record in functions.items():
        key = normalize_key(raw_key)
        if not key or key != raw_key:
            errors.append(f"function {raw_key!r}: key must be normalized lemma|POS")
        if key in normalized:
            errors.append(f"function {raw_key!r}: duplicate normalized key")
        normalized.add(key)
        if not isinstance(record, dict):
            errors.append(f"function {raw_key!r}: record must be an object")
            continue
        if not clean(record.get("label")) or not clean(record.get("explanation")):
            errors.append(f"function {raw_key!r}: label and explanation are required")
        match_keys = [normalize_key(item) for item in record.get("match_keys") or []]
        if any(not item for item in match_keys) or len(match_keys) != len(set(match_keys)):
            errors.append(f"function {raw_key!r}: invalid or duplicate match_keys")
    return errors


def audit_functions(words: dict[str, Any], functions: dict[str, Any]) -> tuple[list[str], list[str]]:
    candidates = function_candidates(words)
    aliases = {
        alias
        for record in functions.values()
        if isinstance(record, dict)
        for alias in (normalize_key(item) for item in record.get("match_keys") or [])
        if alias
    }
    present = [key for key in candidates if key in functions or key in aliases]
    missing = [key for key in candidates if key not in functions and key not in aliases]
    return present, missing

