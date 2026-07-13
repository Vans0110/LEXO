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
      "translation": "находятся"
    }
  ],
  "occurrences": [
    {
      "source_text": "There are books, maps, and twelve students in the room.",
      "target_text": "В комнате находятся книги, карты и двенадцать учеников.",
      "source_form": "There are",
      "target_span_text": "находятся"
    }
  ]
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

A phrase may have several occurrences. Keep one canonical lowercase source key while preserving actual `source_form` evidence.

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
    }
  }
}
```

Every `parallel[]` object must have a corresponding reviewed-segment entry. Use `status: no_phrase_required` when independent words fully represent the segment.

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