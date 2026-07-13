from __future__ import annotations

from pathlib import Path
from typing import Any

from .library_dictionary import LibraryDictionaryStore
from .virgil_core_dictionary import (
    VIRGIL_CORE_DICTIONARY_SOURCE,
    VirgilCoreDictionary,
)


RU_CONTEXT_DICTIONARY_SOURCE = VIRGIL_CORE_DICTIONARY_SOURCE
UK_CONTEXT_DICTIONARY_SOURCE = VIRGIL_CORE_DICTIONARY_SOURCE
CONTEXT_DICTIONARY_SOURCE = VIRGIL_CORE_DICTIONARY_SOURCE
VIRGIL_DICTIONARY_SOURCE = VIRGIL_CORE_DICTIONARY_SOURCE


class ContextDictionaryResolver:
    def __init__(
        self,
        root: Path,
        mt_translators: dict[str, Any] | None = None,
    ) -> None:
        self.library_dictionary = LibraryDictionaryStore(root)
        self.core_dictionary = VirgilCoreDictionary(root)
        self.mt_translators = mt_translators or {}

    def build_entry(
        self,
        *,
        surface: str,
        lemma: str,
        pos: str,
        source_segment: str = "",
        target_segment: str = "",
        target_lang: str = "ru",
    ) -> dict:
        library_entry = self.library_dictionary.lookup_word(
            surface=surface,
            lemma=lemma,
            pos=pos,
            target_lang=target_lang,
        )
        if library_entry.get("has_content"):
            library_entry["source_segment"] = source_segment
            library_entry["target_segment"] = target_segment
            return library_entry
        if target_lang in {"ru", "uk"} and self.library_dictionary.has_global_words(target_lang):
            library_entry["source_segment"] = source_segment
            library_entry["target_segment"] = target_segment
            return library_entry
        return self.core_dictionary.lookup(
            surface=surface,
            lemma=lemma,
            pos=pos,
            source_segment=source_segment,
            target_segment=target_segment,
            target_lang=target_lang,
        )


