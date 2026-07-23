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
  "blocks": [],
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
- Keep a function word with no independent Russian equivalent, but use `translation: ""`, `translations: []`, and `empty_reason`. Record the same absorption in its block component.
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

## Block record

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

Allowed block types:

- `phrasal_verb`
- `fixed_expression`
- `collocation`
- `grammar_construction`
- `prepositional_group`
- `name_group`
- `reordered_block`

Every block requires a concise target-language `explanation` that describes the reusable construction rather than the surrounding sentence. The source must be the shortest contiguous span that retains the exceptional meaning. An empty component translation requires `empty_reason` explaining structural absorption. Block records and `seed_blocks_ru.json` must not contain complete segment copies or audit prose. Necessity evidence belongs only to Pass 4 and references `parallel[]` through zero-based `segment_indexes[]`.

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
        "block_sources": ["walk into"],
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
      "block_decisions": [
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

Every `parallel[]` pair must have a corresponding `reviewed_segments[]` entry. Pass 3 must contain exactly one decision for every word key. Allowed ownership values are `word`, `absorbed`, `mixed`, and `noncontextual`. Use `noncontextual` only when no occurrence has an independently owned target value and the word record contains one skill fallback instead. Each decision requires occurrence evidence. Completion requires both passes to have `status: passed` and empty `unresolved[]` lists.

An `absorbed` decision requires empty word translations and membership in `absorbed_word_keys`. A `word` decision requires non-empty translations and must not be absorbed. Use `mixed` only when the same key has independently translated and structurally absorbed occurrences; its `translations[]` contains only independently owned target spans.

Block-component translations and word records must agree. A non-empty component translation must occur in the matching word record. An absorbed component must be empty and explain which block, construction, or Russian morphological relation owns its meaning. The translation of a whole construction must never be copied to one of its grammatical components; for example, `there are → находятся` does not establish `be → находятся`.

Pass 4 requires exactly one `accepted` decision for every retained block. Rejected candidates remain in audit metadata so a later rebuild does not recreate compositional groups.

## Reproducible seeds

`seed_words_ru.json` and `seed_blocks_ru.json` are editable evidence sources used to regenerate the layer. Globals and package artifacts are derived outputs. Never make a global dictionary the only location of new book evidence.

## Teaching fallback

Contextual ownership and a teaching definition are separate fields. When the
approved translation contains no independent target span for a word, keep
`translation: ""` and `translations: []`. A concise value produced by the skill
may be stored only as:

```json
{
  "dictionary_translation": "значение",
  "dictionary_translation_source": "skill_fallback"
}
```

The fallback is normally one target-language word. A short multiword fallback is
allowed only when the occurrence is explicitly listed in an alignment group's
`group_only_word_ids[]`, has no contextual target span, and the complete fallback
passes the isolation test by itself. It is never occurrence evidence, never claims
target indexes, and never replaces `empty_reason`. Rules must describe structural
categories and POS/ownership conditions; they must not contain a closed list of
particular English words.

## Verification word-to-word

`word_to_word_ru.json` is owned by this skill. It proves the seeds and layer
against every source occurrence but is not a Workbench, package, or ZIP artifact.

```json
{
  "version": 1,
  "book_id": "book_id",
  "source_lang": "en",
  "target_lang": "ru",
  "entries": [
    {
      "word_id": "stable_occurrence_id",
      "segment_index": 0,
      "source_order": 0,
      "surface": "word",
      "lemma": "word",
      "pos": "NOUN",
      "contextual_translation": "слово",
      "dictionary_translation": "",
      "status": "independent_translation",
      "owner_unit_id": "word:stable_occurrence_id",
      "tap_unit_id": "word:stable_occurrence_id",
      "target_start_index": 0,
      "target_end_index": 0,
      "empty_reason": ""
    }
  ],
  "block_occurrences": [
    {
      "unit_id": "block:0:0",
      "tap_unit_id": "block:0:0",
      "block_source": "canonical block",
      "source_form": "attested source form",
      "translation": "перевод всей конструкции",
      "segment_index": 0,
      "word_ids": ["first_word_id", "second_word_id"]
    }
  ]
}
```

### Occurrence-local alignment groups

Use `alignment_groups[]` only when at least one word fails the isolation test,
no minimal reusable semantic Block exists, and one minimal contiguous source
span corresponds honestly to one contiguous target span:

```json
{
  "alignment_groups": [
    {
      "unit_id": "alignment_group:1:0",
      "kind": "structural_recast",
      "segment_index": 1,
      "source_word_ids": ["in_id", "the_id", "wrong_id", "room_id"],
      "group_only_word_ids": ["the_id", "wrong_id"],
      "source_text": "in the wrong room",
      "target_start_index": 1,
      "target_end_index": 4,
      "target_text": "не в той комнате",
      "reason": "Перестроенный перевод не допускает честной отдельной связи для каждого слова."
    }
  ]
}
```

`source_word_ids[]` must be ordered, contiguous occurrences from one segment.
`group_only_word_ids[]` is the subset with no honest independent target span;
those entries keep no contextual target indexes and may retain only an honest
dictionary fallback or zero-correspondence status. A dictionary fallback may be
multiword here only when the whole value is an independently meaningful card;
a grammatical remnant from the target span remains invalid. Other group members
may keep independent exact spans. The group covers its complete target span for
parallel display, including structural target additions not represented by one
source word.

An alignment group is not a Block. Its source must not appear as a book Block or
Block source form; never copy the group to seeds, `book_layer.blocks`,
`block_occurrences`, Globals, function-word records, or learner-facing meanings.
The validator permits overlap only between the group and exact spans owned by
its own source members. Overlap with another group, target coverage, or an
unrelated word is invalid.

Allowed entry statuses:

- `independent_translation`;
- `block_component`;
- `grammar_component`;
- `zero_correspondence`;
- `dictionary_fallback`;
- `source_translation_omission`;
- `unresolved`.

`entries[]` must reconstruct the token sequence of every `parallel[]` source in
segment and source order. Every `word_id` is unique. An independent translation
requires a contextual value and a target span. A fallback requires exactly one
`dictionary_translation` and no contextual target span. Empty contextual values
require `empty_reason`.

Every block or grammar component requires `owner_unit_id` and `tap_unit_id`.
All `word_ids` in a block block use that block's unit and tap ids. A whole-block
translation must not be copied into a component unless that component owns the
same target span independently.

Every retained block occurrence attested by `source_forms[]` must have exactly
one block block. Missing words, duplicate ids, unclassified entries,
unmaterialized blocks, duplicated independent target spans, and `unresolved`
statuses are blocking errors.

An `insertion` is learner-visible and therefore requires an honest
`display_anchor_word_id`. The anchor must be an independently translated occurrence,
and the display highlight must contain both its exact target span and the insertion.
The insertion must not be copied into the anchor's contextual translation.

A `restructure` without an honest one-word anchor is coverage-only. It requires every
contributing `source_word_ids` value and must omit `display_anchor_word_id` and both
highlight fields. Its target span must not be promoted into word translations, seeds,
fallbacks, blocks, Globals, or learner-facing dictionary cards.

### Target-side coverage and display highlighting

Every target-language token must be covered either by an independent word span or
by one explicit `target_coverage[]` record. This layer represents structural target
additions and sentence restructures without falsifying dictionary translations:

```json
{
  "segment_index": 2,
  "target_start_index": 7,
  "target_end_index": 7,
  "target_text": "добавочный элемент",
  "ownership": "insertion",
  "source_word_ids": ["source_word_1", "source_word_2"],
  "display_anchor_word_id": "source_word_2",
  "highlight_target_start_index": 7,
  "highlight_target_end_index": 8,
  "reason": "Структурный элемент целевой конструкции; не самостоятельный перевод исходного слова."
}
```

Allowed ownership values are `block`, `insertion`, and `restructure`. The display
anchor is optional and must belong to `source_word_ids[]`. Its highlight span is a
presentation span only: the anchored word retains its exact contextual translation,
dictionary key, and semantic target span. Materializers and validators must remain
lexeme-agnostic; semantic decisions come from the exhaustive book audit, not from a
closed list of words or nearest-token guessing.

## Scope boundary

The skill stops after writing and validating the two seeds, book layer, and
verification word-to-word file. It does not rebuild globals, Workbench data,
application assets, CloudLibrary files, packages, or ZIP files.
