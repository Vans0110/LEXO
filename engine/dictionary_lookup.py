from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path


class DictionaryLookup:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.wiktionary_path = root / "data" / "dictionaries" / "wiktionary_en_ru.sqlite"
        self.freedict_path = root / "data" / "dictionary_cache" / "freedict_eng_rus.sqlite"
        self.twobooks_path = root / "data" / "dictionary_cache" / "2books_dictionary.db"

    def lookup_word(self, word: str, lemma: str | None = None, pos: str | None = None) -> dict:
        query = self._normalize(word)
        if not query:
            return self._empty(query, "Empty dictionary query.")
        lookup_lemma = self._normalize(lemma) or query
        requested_pos = str(pos or "").strip()
        twobooks = self._lookup_2books(lookup_lemma)
        lemmas = [lookup_lemma]
        entries = [
            *self._lookup_wiktionary_entries(lemmas),
            *self._lookup_freedict_entries(lemmas),
        ]
        entries, pos_filter_applied = self._filter_entries_by_pos(entries, requested_pos)
        verb_forms = twobooks.get("verb_forms") or {}
        phrasals = twobooks.get("phrasals") or []
        has_content = bool(entries or verb_forms or phrasals or twobooks.get("word_found"))
        return {
            "query": query,
            "lemma": lookup_lemma,
            "detected_part_of_speech": requested_pos,
            "transcript": str(twobooks.get("transcript") or ""),
            "word_found": bool(has_content),
            "word_entry": twobooks.get("word_entry") or {},
            "translations": [],
            "part_of_speech": requested_pos,
            "pos_filter_applied": pos_filter_applied,
            "definitions": [],
            "inflected_forms": [],
            "verb_forms": verb_forms,
            "phrasals": phrasals,
            "entries": entries,
            "has_content": bool(has_content),
            "note": "" if has_content else "Dictionary entry was not found.",
        }

    def _candidate_lemmas(self, query: str) -> list[str]:
        candidates = [query]
        if self.wiktionary_path.exists():
            with sqlite3.connect(self.wiktionary_path) as conn:
                conn.row_factory = sqlite3.Row
                rows = conn.execute(
                    "SELECT lemma FROM forms WHERE form = ? ORDER BY rowid LIMIT 12",
                    (query,),
                ).fetchall()
                candidates.extend(str(row["lemma"] or "").lower() for row in rows)
        if self.twobooks_path.exists():
            with sqlite3.connect(self.twobooks_path) as conn:
                conn.row_factory = sqlite3.Row
                rows = conn.execute(
                    "SELECT word FROM forms WHERE form = ? LIMIT 8",
                    (query,),
                ).fetchall()
                candidates.extend(str(row["word"] or "").lower() for row in rows)
        return self._dedupe([item for item in candidates if item])

    def _lookup_wiktionary_entries(self, lemmas: list[str]) -> list[dict]:
        if not self.wiktionary_path.exists():
            return []
        entries = []
        with sqlite3.connect(self.wiktionary_path) as conn:
            conn.row_factory = sqlite3.Row
            for lemma in lemmas:
                rows = conn.execute(
                    """
                    SELECT id, lemma, pos, transcript
                    FROM entries
                    WHERE lemma = ? AND entry_type = 'word'
                    ORDER BY id
                    """,
                    (lemma,),
                ).fetchall()
                for row in rows:
                    entry_id = int(row["id"])
                    translations = [
                        str(item["translation"] or "")
                        for item in conn.execute(
                            """
                            SELECT translation
                            FROM translations
                            WHERE entry_id = ?
                            ORDER BY priority, sense_index
                            LIMIT 24
                            """,
                            (entry_id,),
                        ).fetchall()
                    ]
                    definitions = [
                        str(item["definition"] or "")
                        for item in conn.execute(
                            """
                            SELECT definition
                            FROM definitions
                            WHERE entry_id = ?
                            ORDER BY sense_index
                            LIMIT 8
                            """,
                            (entry_id,),
                        ).fetchall()
                    ]
                    entries.append(
                        {
                            "source": "wiktionary",
                            "lemma": str(row["lemma"] or ""),
                            "part_of_speech": str(row["pos"] or ""),
                            "transcript": str(row["transcript"] or ""),
                            "translations": self._dedupe(translations),
                            "definitions": self._dedupe(definitions),
                        }
                    )
        return entries

    def _lookup_freedict_entries(self, lemmas: list[str]) -> list[dict]:
        if not self.freedict_path.exists():
            return []
        entries = []
        with sqlite3.connect(self.freedict_path) as conn:
            conn.row_factory = sqlite3.Row
            for lemma in lemmas:
                rows = conn.execute(
                    """
                    SELECT word, pos, transcript, translations_json, definitions_json
                    FROM entries
                    WHERE word = ?
                    ORDER BY rowid
                    """,
                    (lemma,),
                ).fetchall()
                for row in rows:
                    entries.append(
                        {
                            "source": "freedict",
                            "lemma": str(row["word"] or ""),
                            "part_of_speech": str(row["pos"] or ""),
                            "transcript": str(row["transcript"] or ""),
                            "translations": self._dedupe(self._json_list(row["translations_json"])),
                            "definitions": self._dedupe(self._json_list(row["definitions_json"])),
                        }
                    )
        return entries

    def _filter_entries_by_pos(self, entries: list[dict], pos: str) -> tuple[list[dict], bool]:
        if not pos:
            return entries, False
        matched = []
        for entry in entries:
            if self._entry_pos_matches(str(entry.get("part_of_speech") or ""), pos):
                matched.append(entry)
        if not matched:
            return entries, False
        return matched, True

    def _entry_pos_matches(self, entry_pos: str, requested_pos: str) -> bool:
        entry_key = entry_pos.strip().lower()
        requested_key = requested_pos.strip().lower()
        if not entry_key or not requested_key:
            return False
        aliases = {
            "adj": {"adj", "adjective", "a"},
            "adjective": {"adj", "adjective", "a"},
            "adv": {"adv", "adverb", "r"},
            "adverb": {"adv", "adverb", "r"},
            "noun": {"noun", "n", "subst"},
            "propn": {"noun", "proper noun", "proper_noun", "n", "subst"},
            "verb": {"verb", "v"},
            "aux": {"verb", "v", "aux", "auxiliary"},
            "pron": {"pron", "pronoun"},
            "det": {"det", "determiner", "article"},
            "adp": {"adp", "preposition", "postposition", "prep"},
            "num": {"num", "number", "numeral"},
            "conj": {"conj", "conjunction"},
            "cconj": {"conj", "conjunction"},
            "sconj": {"conj", "conjunction"},
        }
        accepted = aliases.get(requested_key, {requested_key})
        return entry_key in accepted or any(item in entry_key for item in accepted if len(item) > 2)

    def _lookup_2books(self, query: str) -> dict:
        if not self.twobooks_path.exists():
            return {}
        with sqlite3.connect(self.twobooks_path) as conn:
            conn.row_factory = sqlite3.Row
            lookup_word = query
            form_row = conn.execute("SELECT word FROM forms WHERE form = ? LIMIT 1", (query,)).fetchone()
            if form_row is not None:
                lookup_word = str(form_row["word"] or query).lower()
            row = conn.execute(
                """
                SELECT word, stem, normal, transcript, ngsl_rank, ngsl_rank_ref, en_translate, similar
                FROM words
                WHERE word = ? OR normal = ?
                LIMIT 1
                """,
                (lookup_word, lookup_word),
            ).fetchone()
            verb_row = conn.execute(
                """
                SELECT vf.verb, vf.form1, vf.form2, vf.form3
                FROM verb_forms vf
                JOIN verbs v ON v.form_id = vf.id
                WHERE v.verb = ?
                LIMIT 1
                """,
                (lookup_word,),
            ).fetchone()
            phrasals = []
            for phrasal in conn.execute(
                "SELECT data FROM phrasals WHERE word LIKE ? ORDER BY word LIMIT 8",
                (f"{lookup_word} %",),
            ).fetchall():
                payload = self._json_object(phrasal["data"])
                if payload:
                    phrasals.append(self._phrasal_payload(payload))
        word_entry = {}
        if row is not None:
            word_entry = {
                "word": str(row["word"] or ""),
                "stem": str(row["stem"] or ""),
                "normal": str(row["normal"] or ""),
                "transcript": str(row["transcript"] or ""),
                "ngsl_rank": int(row["ngsl_rank"] or 0),
                "ngsl_rank_ref": str(row["ngsl_rank_ref"] or ""),
                "en_translate": bool(row["en_translate"]),
                "similar": self._json_list(row["similar"]),
            }
        verb_forms = {}
        if verb_row is not None:
            verb_forms = {
                "verb": str(verb_row["verb"] or ""),
                "present": str(verb_row["form1"] or ""),
                "past": str(verb_row["form2"] or ""),
                "participle": str(verb_row["form3"] or ""),
            }
        return {
            "lemma": lookup_word,
            "word_found": row is not None,
            "word_entry": word_entry,
            "transcript": str(word_entry.get("transcript") or ""),
            "verb_forms": verb_forms,
            "phrasals": phrasals,
        }

    def _phrasal_payload(self, payload: dict) -> dict:
        definitions = []
        for definition in payload.get("def") or []:
            for translation in definition.get("tr") or []:
                text = str(translation.get("text") or "").strip()
                if text:
                    definitions.append(text)
        return {
            "word": str(payload.get("word") or ""),
            "transcript": str(payload.get("ts") or ""),
            "translation": str(payload.get("tr") or ""),
            "definitions": self._dedupe(definitions)[:6],
            "link_words": [str(item) for item in payload.get("link") or []],
        }

    def _empty(self, query: str, note: str) -> dict:
        return {
            "query": query,
            "lemma": query,
            "transcript": "",
            "word_found": False,
            "word_entry": {},
            "translations": [],
            "part_of_speech": "",
            "definitions": [],
            "inflected_forms": [],
            "verb_forms": {},
            "phrasals": [],
            "entries": [],
            "has_content": False,
            "note": note,
        }

    def _normalize(self, text: str) -> str:
        return str(text or "").strip().lower()

    def _json_list(self, raw: object) -> list[str]:
        payload = self._json_object(raw)
        if isinstance(payload, list):
            return [str(item) for item in payload if str(item).strip()]
        return []

    def _json_object(self, raw: object):
        try:
            return json.loads(str(raw or ""))
        except Exception:
            return [] if isinstance(raw, str) and raw.strip().startswith("[") else {}

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
        text = re.sub(r"\[\[([^|\]]+)\|([^\]]+)\]\]", r"\2", text)
        text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
        return text
