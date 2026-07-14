# Phrase layer schema

## Book phrase

```json
{
  "source": "there are",
  "translation": "находятся",
  "type": "grammar_construction",
  "components": [
    {
      "source": "there",
      "lemma": "there",
      "pos": "PRON",
      "translation": "",
      "empty_reason": "existential marker is absorbed by the construction"
    },
    {
      "source": "are",
      "lemma": "be",
      "pos": "AUX",
      "translation": "",
      "empty_reason": "the Russian predicate belongs to the existential construction"
    }
  ],
  "source_forms": ["There are"]
}
```

Allowed `type` values:

- `phrasal_verb`
- `fixed_expression`
- `collocation`
- `grammar_construction`
- `prepositional_group`
- `name_group`
- `reordered_block`

A phrase may have several forms. Keep one canonical lowercase source key and compact `source_forms[]`. Never copy complete source/target segments into phrase records or seeds.

## Audit metadata

```json
{
  "phrase_audit": {
    "version": 1,
    "method": "codex_two_pass",
    "reviewed_segments": [
      {
        "source_text": "There are books.",
        "target_text": "Есть книги.",
        "status": "covered",
        "phrase_sources": ["there are"],
        "notes": ""
      }
    ],
    "second_pass": {
      "status": "passed",
      "unresolved_omissions": []
    },
    "necessity_pass": {
      "status": "passed",
      "phrase_decisions": [
        {
          "source": "there are",
          "decision": "accepted",
          "word_by_word_result": "there + be",
          "reason": "separate words do not express existence",
          "segment_indexes": [0]
        }
      ],
      "unresolved": []
    }
  }
}
```

Every `parallel[]` object must have a corresponding reviewed-segment entry. Use `status: no_phrase_required` when independent words fully represent the segment. Every retained phrase requires an accepted necessity decision. Reordering, inflection, proper-name grouping, and ordinary compositional translation are rejection reasons, not phrase evidence.

## Global phrase

The merge adds provenance without removing book evidence:

```json
{
  "translations": ["находятся"],
  "variants": [
    {
      "translation": "находятся",
      "book_ids": ["book_id"],
      "source_forms": ["there are"]
    }
  ],
  "components": [
    {
      "source": "are",
      "lemma": "be",
      "pos": "AUX",
      "translation": "находятся",
      "book_ids": ["book_id"]
    }
  ]
}
```

Global data is derived. The book layer and seeds remain the editable evidence source.
