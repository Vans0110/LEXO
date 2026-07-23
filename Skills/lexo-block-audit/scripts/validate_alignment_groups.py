from __future__ import annotations

from collections import defaultdict
from typing import Any, Callable


def group_only_word_ids(
    groups: list[dict[str, Any]],
    clean: Callable[[object], str],
) -> set[str]:
    return {
        clean(word_id)
        for group in groups
        for word_id in group.get("group_only_word_ids") or []
        if clean(word_id)
    }


def multiword_fallback_keys(
    proof: dict[str, Any],
    clean: Callable[[object], str],
) -> set[str]:
    groups = [
        group for group in proof.get("alignment_groups") or [] if isinstance(group, dict)
    ]
    allowed_ids = group_only_word_ids(groups, clean)
    entries = {
        clean(entry.get("word_id")): entry
        for entry in proof.get("entries") or []
        if isinstance(entry, dict) and clean(entry.get("word_id"))
    }
    return {
        f"{clean(entries[word_id].get('lemma')).casefold()}|"
        f"{clean(entries[word_id].get('pos')).upper()}"
        for word_id in allowed_ids
        if word_id in entries
    }


def validate_alignment_groups(
    layer: dict[str, Any],
    parallel: list[dict[str, Any]],
    groups: list[dict[str, Any]],
    entries_by_id: dict[str, dict[str, Any]],
    token_owners: defaultdict[tuple[int, int], list[str]],
    clean: Callable[[object], str],
    tokens: Callable[[object], list[str]],
) -> tuple[list[str], dict[str, set[str]], set[str]]:
    errors: list[str] = []
    members_by_owner: dict[str, set[str]] = {}
    unit_ids: set[str] = set()
    block_forms = {
        tuple(tokens(value))
        for block in layer.get("blocks") or []
        if isinstance(block, dict)
        for value in [block.get("source"), *(block.get("source_forms") or [])]
        if tokens(value)
    }
    for index, group in enumerate(groups):
        label = f"alignment_groups[{index}]"
        owner_label = f"alignment_group:{index}"
        unit_id = clean(group.get("unit_id"))
        segment_index = group.get("segment_index")
        start = group.get("target_start_index")
        end = group.get("target_end_index")
        source_word_ids = group.get("source_word_ids")
        group_only_word_ids = group.get("group_only_word_ids") or []
        if not unit_id or unit_id in unit_ids:
            errors.append(f"{label}.unit_id is missing or duplicated")
        else:
            unit_ids.add(unit_id)
        if clean(group.get("kind")) != "structural_recast":
            errors.append(f"{label}.kind must be 'structural_recast'")
        if not isinstance(segment_index, int) or not 0 <= segment_index < len(parallel):
            errors.append(f"{label}.segment_index is invalid")
            continue
        if not isinstance(source_word_ids, list) or len(source_word_ids) < 2:
            errors.append(f"{label}.source_word_ids requires at least two entries")
            source_word_ids = []
        normalized_ids = [clean(word_id) for word_id in source_word_ids]
        if len(set(normalized_ids)) != len(normalized_ids):
            errors.append(f"{label}.source_word_ids contains duplicates")
        members: list[dict[str, Any]] = []
        for word_id in normalized_ids:
            entry = entries_by_id.get(word_id)
            if entry is None:
                errors.append(f"{label} references unknown word_id {word_id!r}")
            elif entry.get("segment_index") != segment_index:
                errors.append(f"{label} references a word from another segment")
            else:
                members.append(entry)
        orders = [entry.get("source_order") for entry in members]
        if orders and (
            not all(isinstance(order, int) for order in orders)
            or orders != sorted(orders)
            or orders != list(range(min(orders), max(orders) + 1))
        ):
            errors.append(f"{label}.source_word_ids must form one ordered contiguous span")
        source_tokens = [
            token for entry in members for token in tokens(entry.get("surface"))
        ]
        if tokens(group.get("source_text")) != source_tokens:
            errors.append(f"{label}.source_text disagrees with source_word_ids")
        if tuple(source_tokens) in block_forms:
            errors.append(f"{label} must not duplicate a book block or block source form")
        if not isinstance(group_only_word_ids, list):
            errors.append(f"{label}.group_only_word_ids must be a list")
            group_only_word_ids = []
        group_only = {clean(word_id) for word_id in group_only_word_ids}
        if not group_only.issubset(set(normalized_ids)):
            errors.append(f"{label}.group_only_word_ids must belong to source_word_ids")
        for word_id in group_only:
            entry = entries_by_id.get(word_id)
            if entry is None:
                continue
            if clean(entry.get("contextual_translation")):
                errors.append(f"{label} group-only word {word_id} claims contextual translation")
            if isinstance(entry.get("target_start_index"), int) or isinstance(
                entry.get("target_end_index"), int
            ):
                errors.append(f"{label} group-only word {word_id} must not claim target span")
            if clean(entry.get("status")) not in {
                "dictionary_fallback",
                "zero_correspondence",
                "source_translation_omission",
            }:
                errors.append(f"{label} group-only word {word_id} has invalid status")
        target_tokens = tokens(parallel[segment_index].get("translation"))
        if (
            not isinstance(start, int)
            or not isinstance(end, int)
            or start < 0
            or end < start
            or end >= len(target_tokens)
        ):
            errors.append(f"{label} has invalid target span")
            continue
        if tokens(group.get("target_text")) != target_tokens[start : end + 1]:
            errors.append(f"{label}.target_text disagrees with target span")
        if not clean(group.get("reason")):
            errors.append(f"{label}.reason is required")
        independently_owned = {
            target_index
            for target_index in range(start, end + 1)
            if token_owners.get((segment_index, target_index))
        }
        if not group_only and len(independently_owned) == end - start + 1:
            errors.append(f"{label} is unnecessary: words already own the complete target span")
        members_by_owner[owner_label] = set(normalized_ids)
        for target_index in range(start, end + 1):
            token_owners[(segment_index, target_index)].append(owner_label)
    return errors, members_by_owner, unit_ids
