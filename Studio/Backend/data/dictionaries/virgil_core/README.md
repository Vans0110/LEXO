# Virgil Core Dictionary

Virgil Core Dictionary is the project's hand-curated learning dictionary.
It is not a dump of Wiktionary, FreeDict, MT, or Google output. It stores only
checked translations that Virgil should trust before external dictionaries.

## Files

- `virgil_core_dictionary.json` - the one main shared dictionary. All reviewed
  words from future books are merged here.
- `schema.json` - structural contract for dictionary files.
- `book_seeds/` - optional book-level trace files. They are only import/audit
  sources. The runtime dictionary is the single shared core file.

## Entry Shape

The dictionary is keyed by:

```text
lowercase_english_word|UPPERCASE_POS
```

Example:

```json
{
  "right|ADJ": {
    "word": "right",
    "pos": "ADJ",
    "translations": {
      "ru": ["правильный", "верный", "правый"],
      "uk": ["правильний", "вірний", "правий"]
    }
  }
}
```

## Build Rules

1. Take the source text.
2. Split it into source words.
3. Determine lemma and POS for every word.
4. Build the dictionary key as `lemma|POS`.
5. If the key does not exist, create a new entry in the shared core dictionary.
6. If the key exists, do not create a duplicate.
7. If the key exists but the target language is missing, add that language to
   the existing shared entry.
8. If the key exists and the target language already exists, do not append
   translations automatically. Existing reviewed language data is authoritative.
9. The first translation is the primary card translation.
10. Keep translations short: usually 3-5 items.
11. Do not paste every external dictionary meaning. Store only useful learning
    meanings for Virgil books.
12. Service words are allowed, but they must be educational:
    `a|DET`, `the|DET`, `to|PART`, `do|AUX`, `can|AUX`.
13. Proper names use `PROPN` and should usually preserve the name:
    `ben|PROPN -> Бен / Бен`.

## Segment-Derived Enrichment

After a future book has reviewed RU and UK reader files, enrich Core from the
book only where the source word can be safely matched to the translated
segment:

1. Use `reader_ru.json` and `reader_uk.json` for the same book.
2. Compare each English source segment with its RU and UK target segments.
3. Add a translation to `virgil_core_dictionary.json` only when the word-level
   match is obvious from the segment, for example names, numbers, common nouns,
   simple verbs, and stable classroom blocks.
4. Do not add target text when the source word is an article, auxiliary, or
   other service word that disappears into the sentence.
5. Do not add a whole sentence or block as a single-word translation unless
   the block is a normal learner dictionary block, such as `phone number`,
   `email address`, or `bus stop`.
6. Keep each language list short, preferably 3-5 useful learning meanings.
   Replace noisy external meanings with book-confirmed meanings when needed.
7. If the match is ambiguous, leave the entry unchanged and review manually.

## Runtime Priority

Runtime lookup order is intentionally strict:

```text
1. Virgil Core Dictionary
2. Empty entry when the word/language is missing
```

External dictionaries and local MT fallback must not be used for word-card
dictionary translations. Missing words should be added to this shared Core file
through manual review or a controlled import script.
