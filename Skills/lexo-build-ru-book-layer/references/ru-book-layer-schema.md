# RU book-layer schema

## Primary layer

```json
{
  "version": 1,
  "book_id": "book_id",
  "title": "Book title",
  "source_lang": "en",
  "target_lang": "ru",
  "parallel": [],
  "words": [],
  "phrases": [],
  "book_layer_audit": {}
}
```

`parallel[]` is the only semantic evidence source:

```json
{
  "source": "The exact English segment.",
  "translation": "Точный утверждённый русский сегмент."
}
```

Every input pair must appear exactly once and in reading order.

## Word record

```json
{
  "word": "walks",
  "lemma": "walk",
  "pos": "VERB",
  "translation": "входит",
  "translations": ["входит", "идёт"]
}
```

- `word` preserves an attested source form.
- `lemma` and `pos` use the current project analyzer.
- `translation` is the primary contextual value supported by this book.
- Every item in `translations[]` needs evidence in at least one `parallel[]` pair.
- Keep contextually different confirmed values; do not add generic dictionary senses absent from the book.
- `seed_words_ru.json` and `words[]` contain every source word, including function words.
- Keep a function word with no independent Russian equivalent, but use `translation: ""`, `translations: []`, and `empty_reason`. Record the same absorption in its phrase component.
- Never give an article or other function word the translation of an adjacent lexical word. Invalid examples include `the → комната`, `a → студент`, `down → садится`, and `there → находятся` when those target spans belong to `room`, `student`, `sit`, and `be` respectively.

```json
{
  "word": "The",
  "lemma": "the",
  "pos": "DET",
  "translation": "",
  "translations": [],
  "empty_reason": "article has no independent Russian target"
}
```

## Phrase record

```json
{
  "source": "walk into",
  "translation": "входит в",
  "type": "phrasal_verb",
  "components": [
    {
      "source": "walk",
      "lemma": "walk",
      "pos": "VERB",
      "translation": "входит"
    },
    {
      "source": "into",
      "lemma": "into",
      "pos": "ADP",
      "translation": "в"
    }
  ],
  "source_forms": ["walks into"]
}
```

Allowed phrase types:

- `phrasal_verb`
- `fixed_expression`
- `collocation`
- `grammar_construction`
- `prepositional_group`
- `name_group`
- `reordered_block`

An empty component translation requires `empty_reason` explaining structural absorption. Phrase records and `seed_phrases_ru.json` must not contain complete segment copies or audit prose. Necessity evidence belongs only to Pass 4 and references `parallel[]` through zero-based `segment_indexes[]`.

## Three-pass audit

```json
{
  "book_layer_audit": {
    "version": 1,
    "method": "codex_independent_two_pass",
    "reviewed_segments": [
      {
        "source_text": "She walks into the room.",
        "target_text": "Она входит в комнату.",
        "status": "covered",
        "word_keys": ["walk|VERB", "room|NOUN"],
        "phrase_sources": ["walk into"],
        "notes": ""
      }
    ],
    "second_pass": {
      "status": "passed",
      "corrections": [],
      "unresolved": []
    },
    "third_pass": {
      "status": "passed",
      "word_decisions": [
        {
          "key": "walk|VERB",
          "ownership": "word",
          "translations": ["входит"],
          "evidence": ["She walks into the room. → Она входит в комнату."]
        }
      ],
      "corrections": [],
      "unresolved": []
    },
    "fourth_pass": {
      "status": "passed",
      "phrase_decisions": [
        {
          "source": "sit down",
          "decision": "accepted",
          "word_by_word_result": "сидит + вниз",
          "reason": "the combination means to take a seat",
          "segment_indexes": [17]
        },
        {
          "source": "first floor",
          "decision": "rejected",
          "word_by_word_result": "первый этаж",
          "reason": "independent words preserve the complete meaning",
          "segment_indexes": [13]
        }
      ],
      "unresolved": []
    }
  }
}
```

Every `parallel[]` pair must have a corresponding `reviewed_segments[]` entry. Pass 3 must contain exactly one decision for every word key. Allowed ownership values are `word`, `absorbed`, and `mixed`. Each decision requires occurrence evidence. Completion requires both passes to have `status: passed` and empty `unresolved[]` lists.

An `absorbed` decision requires empty word translations and membership in `absorbed_word_keys`. A `word` decision requires non-empty translations and must not be absorbed. Use `mixed` only when the same key has independently translated and structurally absorbed occurrences; its `translations[]` contains only independently owned target spans.

Phrase-component translations and word records must agree. A non-empty component translation must occur in the matching word record. An absorbed component must be empty and explain which phrase, construction, or Russian morphological relation owns its meaning. The translation of a whole construction must never be copied to one of its grammatical components; for example, `there are → находятся` does not establish `be → находятся`.

Pass 4 requires exactly one `accepted` decision for every retained phrase. Rejected candidates remain in audit metadata so a later rebuild does not recreate compositional groups.

## Reproducible seeds

`seed_words_ru.json` and `seed_phrases_ru.json` are editable evidence sources used to regenerate the layer. Globals and package artifacts are derived outputs. Never make a global dictionary the only location of new book evidence.
