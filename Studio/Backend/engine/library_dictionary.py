from __future__ import annotations

import json
import re
from pathlib import Path


LIBRARY_DICTIONARY_SOURCE = "library_ru_global_words_v2"
SUPPORTED_LIBRARY_DICTIONARY_LANGS = {"ru", "uk"}

def library_dictionary_source(target_lang: str = "ru") -> str:
    lang = str(target_lang or "ru").strip().lower() or "ru"
    return f"library_{lang}_global_words_v2"


class LibraryDictionaryStore:
    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.default_lang = "ru"

    def base_dir(self, target_lang: str = "ru") -> Path:
        lang = self._normalize_lang(target_lang)
        return self.root / "data" / "dictionaries" / f"library_{lang}"

    def books_dir(self, target_lang: str = "ru") -> Path:
        return self.base_dir(target_lang) / "books"

    @property
    def global_words_path(self) -> Path:
        return self.global_words_path_for("ru")

    @property
    def global_blocks_path(self) -> Path:
        return self.global_blocks_path_for("ru")

    def global_words_path_for(self, target_lang: str = "ru") -> Path:
        lang = self._normalize_lang(target_lang)
        return self.base_dir(lang) / f"global_words_{lang}.json"

    def global_blocks_path_for(self, target_lang: str = "ru") -> Path:
        lang = self._normalize_lang(target_lang)
        return self.base_dir(lang) / f"global_blocks_{lang}.json"

    def global_function_words_path_for(self, target_lang: str = "ru") -> Path:
        lang = self._normalize_lang(target_lang)
        return self.base_dir(lang) / f"global_function_words_{lang}.json"

    def has_global_words(self, target_lang: str = "ru") -> bool:
        return self.global_words_path_for(target_lang).exists()

    def book_layer_path(self, book_id: str, target_lang: str = "ru") -> Path:
        lang = self._normalize_lang(target_lang)
        return self.books_dir(lang) / str(book_id) / f"book_layer_{lang}.json"

    def write_book_layer(self, payload: dict, target_lang: str = "ru") -> Path:
        book_id = str(payload.get("book_id") or "").strip()
        if not book_id:
            raise ValueError("book_id is required")
        path = self.book_layer_path(book_id, target_lang)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return path

    def merge_book_layer(self, payload: dict) -> dict:
        target_lang = self._normalize_lang(payload.get("target_lang") or "ru")
        book_id = self._clean_text(payload.get("book_id") or "")
        words_added = self._merge_words(payload.get("words") or [], target_lang, book_id)
        blocks_added = self._merge_blocks(payload.get("blocks") or [], target_lang, book_id)
        return {
            "words_added": words_added,
            "blocks_added": blocks_added,
            "global_words_path": str(self.global_words_path_for(target_lang)),
            "global_blocks_path": str(self.global_blocks_path_for(target_lang)),
        }

    def lookup_word(self, *, surface: str, lemma: str, pos: str, target_lang: str = "ru") -> dict:
        target_lang = str(target_lang or "ru").strip().lower() or "ru"
        lookup_lemma = self._clean_text(lemma or surface).lower()
        lookup_pos = str(pos or "").strip().upper()
        dictionary_key = self.word_key(lookup_lemma, lookup_pos)
        translations: list[str] = []
        if target_lang in SUPPORTED_LIBRARY_DICTIONARY_LANGS:
            record = self._load_json_object(self.global_words_path_for(target_lang)).get(dictionary_key)
            if isinstance(record, dict):
                values = record.get("translations")
                if isinstance(values, list):
                    translations = self._dedupe([str(item) for item in values])
        if not translations:
            return self._empty_entry(
                query=self._clean_text(surface).lower(),
                lemma=lookup_lemma,
                pos=lookup_pos,
                target_lang=target_lang,
                dictionary_key=dictionary_key,
            )
        entry = {
            "source": library_dictionary_source(target_lang),
            "lemma": lookup_lemma,
            "part_of_speech": lookup_pos,
            "transcript": "",
            "translations": translations,
            "definitions": [],
            "mt_generated": False,
        }
        return {
            "query": self._clean_text(surface).lower(),
            "lemma": lookup_lemma,
            "detected_part_of_speech": lookup_pos,
            "transcript": "",
            "word_found": True,
            "word_entry": {},
            "translations": translations,
            "part_of_speech": lookup_pos,
            "pos_filter_applied": bool(lookup_pos),
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
            "source_segment": "",
            "target_segment": "",
        }

    def block_records(self, target_lang: str = "ru") -> dict[str, dict]:
        target_lang = str(target_lang or "ru").strip().lower() or "ru"
        if target_lang not in SUPPORTED_LIBRARY_DICTIONARY_LANGS:
            return {}
        payload = self._load_json_object(self.global_blocks_path_for(target_lang))
        result: dict[str, dict] = {}
        for source, record in payload.items():
            normalized_source = self._normalize_block(source)
            if not normalized_source or not isinstance(record, dict):
                continue
            translations = record.get("translations")
            if not isinstance(translations, list):
                continue
            clean_translations = self._dedupe([str(item) for item in translations])
            if clean_translations:
                source_forms = [normalized_source]
                variants = record.get("variants")
                if isinstance(variants, list):
                    for variant in variants:
                        if not isinstance(variant, dict):
                            continue
                        forms = variant.get("source_forms")
                        if isinstance(forms, list):
                            source_forms.extend(self._normalize_block(item) for item in forms)
                result[normalized_source] = {
                    "translations": clean_translations,
                    "source_forms": self._dedupe([item for item in source_forms if item]),
                    "type": self._clean_text(record.get("type") or ""),
                    "explanation": self._clean_text(record.get("explanation") or ""),
                }
        return result

    def function_word_records(self, target_lang: str = "ru") -> dict[str, dict]:
        path = self.global_function_words_path_for(target_lang)
        return self._load_json_object(path) if path.exists() else {}

    def _merge_words(self, words: object, target_lang: str = "ru", book_id: str = "") -> int:
        if not isinstance(words, list):
            return 0
        path = self.global_words_path_for(target_lang)
        payload = self._load_json_object(path)
        added = 0
        for item in words:
            if not isinstance(item, dict):
                continue
            source_form = self._clean_text(item.get("word") or item.get("surface") or "")
            lemma = self._clean_text(item.get("lemma") or source_form).lower()
            pos = str(item.get("pos") or "").strip().upper()
            raw_translations = item.get("translations")
            candidates = raw_translations if isinstance(raw_translations, list) else []
            candidates = [*candidates, item.get("translation")]
            translations_to_merge = self._dedupe(
                [self._clean_text(value) for value in candidates if self._clean_text(value)]
            )
            if not lemma or not translations_to_merge:
                continue
            key = self.word_key(lemma, pos)
            record = payload.get(key)
            if not isinstance(record, dict):
                record = {"lemma": lemma, "pos": pos, "translations": [], "variants": []}
                payload[key] = record
            record["lemma"] = str(record.get("lemma") or lemma)
            record["pos"] = str(record.get("pos") or pos)
            translations = record.get("translations")
            if not isinstance(translations, list):
                translations = []
                record["translations"] = translations
            for translation in translations_to_merge:
                if self._append_unique(translations, translation):
                    added += 1
                canonical_translation = next(
                    str(value)
                    for value in translations
                    if self._clean_text(value).lower() == translation.lower()
                )
                self._merge_variant(
                    record,
                    translation=canonical_translation,
                    book_id=book_id,
                    source_form=source_form,
                )
        self._write_json_object(path, payload)
        return added
    def _merge_blocks(self, blocks: object, target_lang: str = "ru", book_id: str = "") -> int:
        if not isinstance(blocks, list):
            return 0
        path = self.global_blocks_path_for(target_lang)
        payload = self._load_json_object(path)
        added = 0
        for item in blocks:
            if not isinstance(item, dict):
                continue
            source = self._normalize_block(item.get("source") or item.get("block") or "")
            translation = self._clean_text(item.get("translation") or "")
            block_type = self._clean_text(item.get("type") or "")
            explanation = self._clean_text(item.get("explanation") or "")
            if not source or not translation or not block_type or not explanation:
                continue
            record = payload.get(source)
            if not isinstance(record, dict):
                record = {"translations": [], "variants": []}
                payload[source] = record
            existing_type = self._clean_text(record.get("type") or "")
            existing_explanation = self._clean_text(record.get("explanation") or "")
            if existing_type and existing_type != block_type:
                raise ValueError(f"Conflicting block type: {source}")
            if existing_explanation and existing_explanation != explanation:
                raise ValueError(f"Conflicting block explanation: {source}")
            record["type"] = block_type
            record["explanation"] = explanation
            translations = record.get("translations")
            if not isinstance(translations, list):
                translations = []
                record["translations"] = translations
            if self._append_unique(translations, translation):
                added += 1
            canonical_translation = next(
                str(value)
                for value in translations
                if self._clean_text(value).lower() == translation.lower()
            )
            self._merge_variant(
                record,
                translation=canonical_translation,
                book_id=book_id,
                source_form=source,
            )
            self._merge_block_components(record, item.get("components"), book_id)
        self._write_json_object(path, payload)
        return added

    def _merge_block_components(
        self, record: dict, components: object, book_id: str
    ) -> None:
        if not isinstance(components, list):
            return
        merged = record.get("components")
        if not isinstance(merged, list):
            merged = []
            record["components"] = merged
        for item in components:
            if not isinstance(item, dict):
                continue
            source = self._clean_text(item.get("source") or item.get("word") or "")
            lemma = self._clean_text(item.get("lemma") or source).lower()
            pos = self._clean_text(item.get("pos") or "").upper()
            translation = self._clean_text(item.get("translation") or "")
            if not source or not translation:
                continue
            existing = next(
                (
                    value
                    for value in merged
                    if isinstance(value, dict)
                    and self._clean_text(value.get("source") or "").lower()
                    == source.lower()
                    and self._clean_text(value.get("translation") or "").lower()
                    == translation.lower()
                ),
                None,
            )
            if not isinstance(existing, dict):
                existing = {
                    "source": source,
                    "lemma": lemma,
                    "pos": pos,
                    "translation": translation,
                    "book_ids": [],
                }
                merged.append(existing)
            book_ids = existing.get("book_ids")
            if not isinstance(book_ids, list):
                book_ids = []
                existing["book_ids"] = book_ids
            if book_id:
                self._append_unique(book_ids, book_id)
    def _merge_variant(
        self,
        record: dict,
        *,
        translation: str,
        book_id: str,
        source_form: str,
    ) -> None:
        variants = record.get("variants")
        if not isinstance(variants, list):
            variants = []
            record["variants"] = variants
        variant = next(
            (
                item
                for item in variants
                if isinstance(item, dict)
                and self._clean_text(item.get("translation") or "") == translation
            ),
            None,
        )
        if not isinstance(variant, dict):
            variant = {"translation": translation, "book_ids": [], "source_forms": []}
            variants.append(variant)
        book_ids = variant.get("book_ids")
        if not isinstance(book_ids, list):
            book_ids = []
            variant["book_ids"] = book_ids
        source_forms = variant.get("source_forms")
        if not isinstance(source_forms, list):
            source_forms = []
            variant["source_forms"] = source_forms
        if book_id:
            self._append_unique(book_ids, book_id)
        if source_form:
            self._append_unique(source_forms, source_form)
    def _empty_entry(
        self,
        *,
        query: str,
        lemma: str,
        pos: str,
        target_lang: str,
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
            "note": "Library dictionary entry was not found.",
            "dictionary_key": dictionary_key,
            "offline_manifest": True,
            "target_lang": target_lang,
            "source_segment": "",
            "target_segment": "",
        }

    def _load_json_object(self, path: Path) -> dict:
        if not path.exists():
            return {}
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def _write_json_object(self, path: Path, payload: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def _append_unique(self, values: list, value: str) -> bool:
        normalized = self._clean_text(value)
        if not normalized:
            return False
        seen = {self._clean_text(str(item)).lower() for item in values}
        if normalized.lower() in seen:
            return False
        values.append(normalized)
        return True

    def _dedupe(self, items: list[str]) -> list[str]:
        result: list[str] = []
        for item in items:
            self._append_unique(result, item)
        return result

    def _normalize_block(self, value: object) -> str:
        return self._clean_text(value).lower()

    def _clean_text(self, value: object) -> str:
        return re.sub(r"\s+", " ", str(value or "")).strip()

    def word_key(self, lemma: str, pos: str) -> str:
        return f"{str(lemma or '').strip().lower()}|{str(pos or '').strip().upper()}"

    def _normalize_lang(self, target_lang: object) -> str:
        lang = str(target_lang or "ru").strip().lower() or "ru"
        if lang not in SUPPORTED_LIBRARY_DICTIONARY_LANGS:
            raise ValueError(f"Unsupported library dictionary language: {lang}")
        return lang
