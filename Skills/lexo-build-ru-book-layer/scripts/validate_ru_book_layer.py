from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


PHRASE_TYPES = {
    "phrasal_verb",
    "fixed_expression",
    "collocation",
    "grammar_construction",
    "prepositional_group",
    "name_group",
    "reordered_block",
}
TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)
FUNCTION_POS = {"DET", "AUX", "ADP", "PART", "CCONJ", "SCONJ"}
OWNERSHIP_TYPES = {"word", "absorbed", "mixed"}


def clean(value: object) -> str:
    return " ".join(str(value or "").split())


def tokens(value: object) -> list[str]:
    return [match.group(0).casefold() for match in TOKEN_RE.finditer(str(value or ""))]


def contains_sequence(text: object, span: object) -> bool:
    haystack = tokens(text)
    wanted = tokens(span)
    return bool(wanted) and any(
        haystack[index : index + len(wanted)] == wanted
        for index in range(len(haystack) - len(wanted) + 1)
    )


def load(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("book layer must be a JSON object")
    return payload


def corruption_paths(value: object, path: str = "$") -> list[str]:
    found: list[str] = []
    if isinstance(value, str) and ("???" in value or "�" in value):
        found.append(path)
    elif isinstance(value, dict):
        for key, item in value.items():
            found.extend(corruption_paths(item, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(corruption_paths(item, f"{path}[{index}]"))
    return found


def normalized_word_map(items: object) -> dict[str, tuple[str, ...]]:
    result: dict[str, tuple[str, ...]] = {}
    if isinstance(items, dict):
        iterable = []
        for key, value in items.items():
            if not isinstance(value, dict) or "|" not in str(key):
                continue
            lemma, pos = str(key).rsplit("|", 1)
            iterable.append({**value, "lemma": lemma, "pos": pos})
    else:
        iterable = items or []
    for item in iterable:
        if not isinstance(item, dict):
            continue
        key = f"{clean(item.get('lemma')).lower()}|{clean(item.get('pos')).upper()}"
        values = tuple(sorted({clean(value).casefold() for value in item.get("translations") or [] if clean(value)}))
        result[key] = values
    return result


def normalized_phrase_map(items: object) -> dict[str, str]:
    return {
        clean(item.get("source")).casefold(): clean(item.get("translation")).casefold()
        for item in items or []
        if isinstance(item, dict) and clean(item.get("source"))
    }


def validate(payload: dict[str, Any]) -> tuple[list[str], dict[str, int]]:
    errors: list[str] = []
    for path in corruption_paths(payload):
        errors.append(f"encoding corruption at {path}")
    for field in ("book_id", "title"):
        if not clean(payload.get(field)):
            errors.append(f"missing {field}")
    if payload.get("source_lang") != "en":
        errors.append("source_lang must be 'en'")
    if payload.get("target_lang") != "ru":
        errors.append("target_lang must be 'ru'")

    parallel = [item for item in payload.get("parallel") or [] if isinstance(item, dict)]
    words = [item for item in payload.get("words") or [] if isinstance(item, dict)]
    phrases = [item for item in payload.get("phrases") or [] if isinstance(item, dict)]
    audit_payload = payload.get("book_layer_audit")
    absorbed_word_keys = {
        clean(item).lower()
        for item in (audit_payload.get("absorbed_word_keys") or [])
        if isinstance(audit_payload, dict) and clean(item)
    }
    pairs = {(clean(item.get("source")), clean(item.get("translation"))) for item in parallel}
    if not parallel:
        errors.append("parallel[] must not be empty")
    for index, item in enumerate(parallel):
        if not clean(item.get("source")) or not clean(item.get("translation")):
            errors.append(f"parallel[{index}] requires source and translation")

    seen_word_keys: set[str] = set()
    word_translations_by_key: dict[str, set[str]] = {}
    for index, word in enumerate(words):
        label = f"words[{index}]"
        lemma = clean(word.get("lemma")).lower()
        pos = clean(word.get("pos")).upper()
        if not clean(word.get("word")) or not lemma or not pos:
            errors.append(f"{label} requires word, lemma, and pos")
        translations = word.get("translations")
        if not isinstance(translations, list):
            errors.append(f"{label}.translations must be a list")
        primary = clean(word.get("translation"))
        if primary and isinstance(translations, list) and primary not in [clean(item) for item in translations]:
            errors.append(f"{label}.translation must occur in translations[]")
        key = f"{lemma}|{pos}"
        is_absorbed = key.lower() in absorbed_word_keys
        if not any(clean(item) for item in translations or []):
            if not is_absorbed or not clean(word.get("empty_reason")):
                errors.append(
                    f"{label} without translations requires absorbed ownership and empty_reason"
                )
        elif is_absorbed:
            errors.append(f"{label} is absorbed but still has translations")
        if key in seen_word_keys:
            errors.append(f"duplicate word key: {key}")
        seen_word_keys.add(key)
        word_translations_by_key[key] = {
            clean(item).casefold() for item in translations or [] if clean(item)
        }

    seen_phrases: set[str] = set()
    component_owners: dict[str, set[str]] = {}
    component_translations_by_key: dict[str, set[str]] = {}
    for index, phrase in enumerate(phrases):
        label = f"phrases[{index}]"
        source = clean(phrase.get("source")).casefold()
        if not source or not clean(phrase.get("translation")):
            errors.append(f"{label} requires source and translation")
        if source in seen_phrases:
            errors.append(f"duplicate phrase source: {source}")
        seen_phrases.add(source)
        if phrase.get("type") not in PHRASE_TYPES:
            errors.append(f"{label} has invalid type")
        for forbidden in ("occurrences", "necessity"):
            if forbidden in phrase:
                errors.append(f"{label}.{forbidden} belongs in audit metadata, not phrase records")
        components = phrase.get("components")
        if not isinstance(components, list) or not components:
            errors.append(f"{label}.components[] is required")
        else:
            for component_index, component in enumerate(components):
                component_label = f"{label}.components[{component_index}]"
                if not isinstance(component, dict):
                    errors.append(f"{component_label} must be an object")
                    continue
                for field in ("source", "lemma", "pos"):
                    if not clean(component.get(field)):
                        errors.append(f"{component_label} missing {field}")
                if not clean(component.get("translation")) and not clean(component.get("empty_reason")):
                    errors.append(f"{component_label} needs translation or empty_reason")
                component_key = (
                    f"{clean(component.get('lemma')).lower()}|"
                    f"{clean(component.get('pos')).upper()}"
                )
                component_translation = clean(component.get("translation")).casefold()
                if component_translation:
                    component_translations_by_key.setdefault(component_key, set()).add(
                        component_translation
                    )
                    if component_key.lower() in absorbed_word_keys:
                        errors.append(
                            f"{component_label} translates absorbed word {component_key}: "
                            f"{component_translation!r}"
                        )
                if component_translation and clean(component.get("pos")).upper() not in FUNCTION_POS:
                    component_owners.setdefault(component_translation, set()).add(component_key)
        source_forms = phrase.get("source_forms")
        if not isinstance(source_forms, list) or not any(clean(item) for item in source_forms):
            errors.append(f"{label}.source_forms[] is required")
        elif not any(
            contains_sequence(pair_source, form) and contains_sequence(pair_target, phrase.get("translation"))
            for pair_source, pair_target in pairs
            for form in source_forms
            if clean(form)
        ):
            errors.append(f"{label} has no supporting parallel segment")

    for key, translations in word_translations_by_key.items():
        missing_component_values = component_translations_by_key.get(key, set()) - translations
        pos = key.rsplit("|", 1)[-1]
        if missing_component_values and (
            pos in FUNCTION_POS or key.lower() in absorbed_word_keys
        ):
            errors.append(
                f"word {key} misses phrase-component translations "
                f"{sorted(missing_component_values)}"
            )
        if pos not in FUNCTION_POS:
            continue
        for translation in translations:
            other_owners = component_owners.get(translation, set()) - {key}
            if other_owners:
                errors.append(
                    f"function word {key} reuses lexical component translation "
                    f"{translation!r} owned by {sorted(other_owners)}"
                )

    audit = audit_payload
    if not isinstance(audit, dict):
        errors.append("book_layer_audit is required")
        reviewed: list[dict] = []
    else:
        reviewed = [item for item in audit.get("reviewed_segments") or [] if isinstance(item, dict)]
        reviewed_pairs = {
            (clean(item.get("source_text")), clean(item.get("target_text"))) for item in reviewed
        }
        missing = pairs - reviewed_pairs
        extra = reviewed_pairs - pairs
        if missing:
            errors.append(f"audit misses {len(missing)} parallel segment(s)")
        if extra:
            errors.append(f"audit contains {len(extra)} unknown segment(s)")
        second = audit.get("second_pass")
        if not isinstance(second, dict):
            errors.append("book_layer_audit.second_pass is required")
        else:
            if second.get("status") != "passed":
                errors.append("second_pass.status must be 'passed'")
            unresolved = second.get("unresolved")
            if not isinstance(unresolved, list):
                errors.append("second_pass.unresolved must be a list")
            elif unresolved:
                errors.append(f"second pass has {len(unresolved)} unresolved item(s)")

        third = audit.get("third_pass")
        if not isinstance(third, dict):
            errors.append("book_layer_audit.third_pass is required")
        else:
            if third.get("status") != "passed":
                errors.append("third_pass.status must be 'passed'")
            unresolved = third.get("unresolved")
            if not isinstance(unresolved, list):
                errors.append("third_pass.unresolved must be a list")
            elif unresolved:
                errors.append(f"third pass has {len(unresolved)} unresolved item(s)")
            decisions = [
                item for item in third.get("word_decisions") or [] if isinstance(item, dict)
            ]
            decisions_by_key: dict[str, dict[str, Any]] = {}
            for index, decision in enumerate(decisions):
                key = clean(decision.get("key"))
                label = f"third_pass.word_decisions[{index}]"
                if not key:
                    errors.append(f"{label}.key is required")
                    continue
                if "|" not in key:
                    errors.append(f"{label}.key must use lemma|POS format")
                    continue
                normalized_key = key.rsplit("|", 1)[0].lower() + "|" + key.rsplit("|", 1)[-1].upper()
                if normalized_key in decisions_by_key:
                    errors.append(f"duplicate third-pass decision: {normalized_key}")
                decisions_by_key[normalized_key] = decision
                ownership = clean(decision.get("ownership")).lower()
                if ownership not in OWNERSHIP_TYPES:
                    errors.append(f"{label} has invalid ownership {ownership!r}")
                evidence = decision.get("evidence")
                if not isinstance(evidence, list) or not any(clean(item) for item in evidence):
                    errors.append(f"{label}.evidence[] is required")
                decision_values = {
                    clean(item).casefold() for item in decision.get("translations") or [] if clean(item)
                }
                word_values = word_translations_by_key.get(normalized_key, set())
                if decision_values != word_values:
                    errors.append(
                        f"{label}.translations disagree with word {normalized_key}"
                    )
                is_absorbed = normalized_key.lower() in absorbed_word_keys
                if ownership == "absorbed" and (word_values or not is_absorbed):
                    errors.append(f"{label} absorbed ownership disagrees with word/audit state")
                if ownership == "word" and (not word_values or is_absorbed):
                    errors.append(f"{label} word ownership disagrees with word/audit state")
                if ownership == "mixed" and (not word_values or is_absorbed):
                    errors.append(f"{label} mixed ownership requires translations and no blanket absorption")
            missing_decisions = seen_word_keys - set(decisions_by_key)
            extra_decisions = set(decisions_by_key) - seen_word_keys
            if missing_decisions:
                errors.append(f"third pass misses word keys {sorted(missing_decisions)}")
            if extra_decisions:
                errors.append(f"third pass has unknown word keys {sorted(extra_decisions)}")

        fourth = audit.get("fourth_pass")
        if not isinstance(fourth, dict):
            errors.append("book_layer_audit.fourth_pass is required")
        else:
            if fourth.get("status") != "passed":
                errors.append("fourth_pass.status must be 'passed'")
            unresolved = fourth.get("unresolved")
            if not isinstance(unresolved, list):
                errors.append("fourth_pass.unresolved must be a list")
            elif unresolved:
                errors.append(f"fourth pass has {len(unresolved)} unresolved item(s)")
            accepted: list[str] = []
            for index, decision in enumerate(fourth.get("phrase_decisions") or []):
                label = f"fourth_pass.phrase_decisions[{index}]"
                if not isinstance(decision, dict):
                    errors.append(f"{label} must be an object")
                    continue
                decision_source = clean(decision.get("source")).casefold()
                decision_value = clean(decision.get("decision")).lower()
                if not decision_source or decision_value not in {"accepted", "rejected"}:
                    errors.append(f"{label} requires source and accepted/rejected decision")
                if not clean(decision.get("word_by_word_result")) or not clean(decision.get("reason")):
                    errors.append(f"{label} requires word_by_word_result and reason")
                segment_indexes = decision.get("segment_indexes")
                if not isinstance(segment_indexes, list) or not segment_indexes or any(
                    not isinstance(item, int) or item < 0 or item >= len(parallel)
                    for item in segment_indexes
                ):
                    errors.append(f"{label}.segment_indexes[] must reference parallel[]")
                if decision_value == "accepted":
                    accepted.append(decision_source)
            if len(accepted) != len(set(accepted)):
                errors.append("fourth pass has duplicate accepted phrase decisions")
            if set(accepted) != seen_phrases:
                errors.append(
                    "fourth-pass accepted phrases disagree with phrases[]: "
                    f"missing={sorted(seen_phrases - set(accepted))}, "
                    f"extra={sorted(set(accepted) - seen_phrases)}"
                )

    return errors, {
        "parallel": len(parallel),
        "words": len(words),
        "phrases": len(phrases),
        "reviewed": len(reviewed),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a four-pass Russian LEXO book layer")
    parser.add_argument("book_layer", type=Path)
    args = parser.parse_args()
    try:
        layer_path = args.book_layer.resolve()
        payload = load(layer_path)
        errors, counts = validate(payload)
        seed_words_path = layer_path.with_name("seed_words_ru.json")
        seed_phrases_path = layer_path.with_name("seed_phrases_ru.json")
        if seed_words_path.exists():
            seed_words = json.loads(seed_words_path.read_text(encoding="utf-8"))
            if normalized_word_map(seed_words) != normalized_word_map(payload.get("words")):
                errors.append("seed_words_ru.json disagrees with book_layer_ru.json words[]")
        if seed_phrases_path.exists():
            seed_phrases = json.loads(seed_phrases_path.read_text(encoding="utf-8"))
            if normalized_phrase_map(seed_phrases) != normalized_phrase_map(payload.get("phrases")):
                errors.append("seed_phrases_ru.json disagrees with book_layer_ru.json phrases[]")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}")
        return 2
    print(json.dumps(counts, ensure_ascii=False))
    for error in errors:
        print(f"ERROR: {error}")
    if errors:
        print(f"FAILED: {len(errors)} error(s)")
        return 1
    print("OK: 0 errors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
