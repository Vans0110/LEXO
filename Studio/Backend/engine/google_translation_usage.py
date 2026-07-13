from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MONTHLY_FREE_CHARACTERS = 500_000
MONTHLY_BLOCK_CHARACTERS = 495_000
DEFAULT_WARNING_THRESHOLD = 5_000


class GoogleTranslationUsageTracker:
    def __init__(self, root: Path) -> None:
        self.path = root / "data" / "google_translate_usage.jsonl"

    def record(
        self,
        *,
        target_lang: str,
        character_count: int,
        segment_count: int,
    ) -> None:
        if character_count <= 0 or segment_count <= 0:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "created_at": datetime.now(timezone.utc).isoformat(),
            "provider": "google-cloud-translation-v2",
            "target_lang": str(target_lang or "").strip().lower(),
            "character_count": int(character_count),
            "segment_count": int(segment_count),
        }
        with self.path.open("a", encoding="utf-8") as file:
            file.write(json.dumps(payload, ensure_ascii=False) + "\n")

    def assert_can_spend(
        self,
        *,
        additional_characters: int,
        month: str | None = None,
    ) -> None:
        if additional_characters <= 0:
            return
        summary = self.summary(month)
        current = int(summary["character_count"])
        limit = int(summary["block_character_limit"])
        if current + additional_characters > limit:
            raise RuntimeError(
                "Google Translation monthly block limit exceeded: "
                f"{current} + {additional_characters} > {limit} characters."
            )

    def summary(self, month: str | None = None) -> dict[str, Any]:
        month_key = _month_key(month)
        month_entries = [
            entry
            for entry in self._read_entries()
            if str(entry.get("created_at") or "").startswith(month_key)
        ]
        by_lang: dict[str, int] = {}
        segments_by_lang: dict[str, int] = {}
        for entry in month_entries:
            lang = str(entry.get("target_lang") or "").strip().lower() or "unknown"
            chars = int(entry.get("character_count") or 0)
            segments = int(entry.get("segment_count") or 0)
            by_lang[lang] = by_lang.get(lang, 0) + chars
            segments_by_lang[lang] = segments_by_lang.get(lang, 0) + segments
        total = sum(by_lang.values())
        return {
            "month": month_key,
            "character_count": total,
            "free_character_limit": MONTHLY_FREE_CHARACTERS,
            "block_character_limit": MONTHLY_BLOCK_CHARACTERS,
            "safety_limit": DEFAULT_WARNING_THRESHOLD,
            "warning_threshold": DEFAULT_WARNING_THRESHOLD,
            "remaining_free_characters": max(0, MONTHLY_FREE_CHARACTERS - total),
            "remaining_before_safety_limit": max(
                0,
                DEFAULT_WARNING_THRESHOLD - total,
            ),
            "remaining_before_warning_threshold": max(
                0,
                DEFAULT_WARNING_THRESHOLD - total,
            ),
            "by_lang": by_lang,
            "segments_by_lang": segments_by_lang,
            "entry_count": len(month_entries),
            "usage_path": str(self.path),
        }

    def _read_entries(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        entries: list[dict[str, Any]] = []
        for line in self.path.read_text(encoding="utf-8").splitlines():
            try:
                payload = json.loads(line)
            except ValueError:
                continue
            if isinstance(payload, dict):
                entries.append(payload)
        return entries


def _month_key(month: str | None = None) -> str:
    value = str(month or "").strip()
    if value:
        return value[:7]
    return datetime.now(timezone.utc).strftime("%Y-%m")
