from __future__ import annotations

import json
import re
from pathlib import Path


VIRGIL_CORE_DICTIONARY_SOURCE = "virgil_core_dictionary"

class VirgilCoreDictionary:
    def __init__(self, root: Path) -> None:
        self.path = (
            Path(root)
            / "data"
            / "dictionaries"
            / "virgil_core"
            / "virgil_core_dictionary.json"
        )
        self.entries = self._load_entries()

    def lookup(
        self,
        *,
        surface: str,
        lemma: str,
        pos: str,
        target_lang: str = "ru",
        source_segment: str = "",
        target_segment: str = "",
    ) -> dict:
        target_lang = self._target_lang(target_lang)
        query = self._clean_text(surface).lower()
        lookup_lemma = self._clean_text(lemma).lower() or query
        requested_pos = str(pos or "").strip()
        dictionary_key = self._dictionary_key(lookup_lemma, requested_pos)
        record = self.entries.get(dictionary_key)
        translations = self._translations(record, target_lang)
        if not translations:
            return self._empty_entry(
                query=query,
                lemma=lookup_lemma,
                pos=requested_pos,
                target_lang=target_lang,
                source_segment=source_segment,
                target_segment=target_segment,
                dictionary_key=dictionary_key,
            )
        entry = {
            "source": VIRGIL_CORE_DICTIONARY_SOURCE,
            "lemma": lookup_lemma,
            "part_of_speech": requested_pos,
            "transcript": "",
            "translations": translations,
            "definitions": [],
            "mt_generated": False,
        }
        return {
            "query": query,
            "lemma": lookup_lemma,
            "detected_part_of_speech": requested_pos,
            "transcript": "",
            "word_found": True,
            "word_entry": {},
            "translations": translations,
            "part_of_speech": requested_pos,
            "pos_filter_applied": bool(requested_pos),
            "definitions": [],
            "inflected_forms": [],
            "verb_forms": {},
            "phrasals": [],
            "entries": [entry],
            "has_content": True,
            "mt_generated": False,
            "note": "",
            "dictionary_key": dictionary_key,
            "offline_manifest": True,
            "target_lang": target_lang,
            "source_segment": source_segment,
            "target_segment": target_segment,
        }

    def _empty_entry(
        self,
        *,
        query: str,
        lemma: str,
        pos: str,
        target_lang: str,
        source_segment: str,
        target_segment: str,
        dictionary_key: str,
    ) -> dict:
        return {
            "query": query,
            "lemma": lemma,
            "detected_part_of_speech": pos,
            "transcript": "",
            "word_found": False,
            "word_entry": {},
            "translations": [],
            "part_of_speech": pos,
            "pos_filter_applied": bool(pos),
            "definitions": [],
            "inflected_forms": [],
            "verb_forms": {},
            "phrasals": [],
            "entries": [],
            "has_content": False,
            "mt_generated": False,
            "note": "Virgil Core dictionary entry was not found.",
            "dictionary_key": dictionary_key,
            "offline_manifest": True,
            "target_lang": target_lang,
            "source_segment": source_segment,
            "target_segment": target_segment,
        }

    def _load_entries(self) -> dict:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def _translations(self, record: object, target_lang: str) -> list[str]:
        if not isinstance(record, dict):
            return []
        translations_by_lang = record.get("translations")
        if not isinstance(translations_by_lang, dict):
            return []
        values = translations_by_lang.get(target_lang)
        if not isinstance(values, list):
            return []
        return self._dedupe([str(item) for item in values])

    def _target_lang(self, target_lang: str) -> str:
        return str(target_lang or "ru").strip().lower() or "ru"

    def _dictionary_key(self, lemma: str, pos: str) -> str:
        return f"{lemma.strip().lower()}|{pos.strip().upper()}"

    def _dedupe(self, items: list[str]) -> list[str]:
        result = []
        seen = set()
        for item in items:
            normalized = self._clean_text(str(item or "")).strip()
            key = normalized.lower()
            if not normalized or key in seen:
                continue
            seen.add(key)
            result.append(normalized)
        return result

    def _clean_text(self, text: str) -> str:
        text = re.sub(r"\[\[([^|\]]+)\|([^\]]+)\]\]", r"\2", str(text or ""))
        text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
        text = text.replace("\u0301", "")
        return re.sub(r"\s+", " ", text).strip()
