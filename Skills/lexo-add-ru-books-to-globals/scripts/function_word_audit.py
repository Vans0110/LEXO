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


def function_occurrence_candidates(
    words: dict[str, Any], entries: list[dict[str, Any]]
) -> dict[str, dict[str, str]]:
    functional_lemmas = {
        key.rsplit("|", 1)[0]
        for key in function_candidates(words)
    }
    candidates: dict[str, dict[str, str]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        surface = clean(entry.get("surface")).casefold()
        lemma = clean(entry.get("lemma")).casefold()
        pos = clean(entry.get("pos")).upper()
        if not surface or not lemma or not pos:
            continue
        if surface == lemma:
            continue
        if pos not in FUNCTION_POS and lemma not in functional_lemmas:
            continue
        key = normalize_key(f"{surface}|{pos}")
        if key:
            candidates[key] = {
                "surface": surface,
                "base_form": lemma,
                "pos": pos,
            }
    return candidates


def _record_for_surface(
    key: str, functions: dict[str, Any]
) -> tuple[str, dict[str, Any] | None]:
    if isinstance(functions.get(key), dict):
        return key, functions[key]
    for record_key, record in functions.items():
        if not isinstance(record, dict):
            continue
        aliases = {normalize_key(item) for item in record.get("match_keys") or []}
        if key in aliases:
            return record_key, record
    return "", None


def audit_function_forms(
    candidates: dict[str, dict[str, str]], functions: dict[str, Any]
) -> tuple[list[str], list[str], list[str]]:
    present: list[str] = []
    missing: list[str] = []
    invalid: list[str] = []
    for key, candidate in sorted(candidates.items()):
        record_key, record = _record_for_surface(key, functions)
        if record is None:
            missing.append(key)
            continue
        present.append(key)
        surface = clean(record.get("surface")).casefold()
        base_form = clean(record.get("base_form")).casefold()
        if surface != candidate["surface"]:
            invalid.append(f"{record_key}: surface must be {candidate['surface']!r}")
        if base_form != candidate["base_form"]:
            invalid.append(
                f"{record_key}: base_form must be {candidate['base_form']!r}"
            )
        if not clean(record.get("translation")):
            invalid.append(f"{record_key}: translation is required for surface form")
        if not clean(record.get("usage")):
            invalid.append(f"{record_key}: usage is required for surface form")
        examples = record.get("examples")
        if not isinstance(examples, list) or not examples:
            invalid.append(f"{record_key}: examples[] is required for surface form")
        else:
            for index, example in enumerate(examples):
                if not isinstance(example, dict) or not clean(
                    example.get("source")
                ) or not clean(example.get("translation")):
                    invalid.append(
                        f"{record_key}: examples[{index}] requires source and translation"
                    )
    return present, missing, invalid


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
