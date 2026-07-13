from __future__ import annotations

from pathlib import Path

from .library_dictionary import LibraryDictionaryStore
from .virgil_core_dictionary import VirgilCoreDictionary


class DictionaryLookup:
    def __init__(self, root: Path) -> None:
        self.library_dictionary = LibraryDictionaryStore(root)
        self.core_dictionary = VirgilCoreDictionary(root)

    def lookup_word(
        self,
        word: str,
        lemma: str | None = None,
        pos: str | None = None,
        target_lang: str = "ru",
    ) -> dict:
        query = str(word or "").strip().lower()
        lookup_lemma = str(lemma or query).strip().lower()
        lookup_pos = str(pos or "").strip()
        library_entry = self.library_dictionary.lookup_word(
            surface=query,
            lemma=lookup_lemma,
            pos=lookup_pos,
            target_lang=target_lang,
        )
        if library_entry.get("has_content"):
            return library_entry
        if target_lang in {"ru", "uk"} and self.library_dictionary.has_global_words(target_lang):
            return library_entry
        return self.core_dictionary.lookup(
            surface=query,
            lemma=lookup_lemma,
            pos=lookup_pos,
            target_lang=target_lang,
        )




