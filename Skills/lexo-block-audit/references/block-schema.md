# Block layer schema

## Book block

```json
{
  "source": "there are",
  "translation": "находятся",
  "type": "grammar_construction",
  "explanation": "Сообщает, что кто-то или что-то существует либо находится где-то.",
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

A block may have several forms. Keep one canonical lowercase source key and compact `source_forms[]`. Require a concise reusable `explanation` in the target language. Explain the construction, not the whole sentence. Never copy complete source/target segments into block records or seeds.

The source must be the shortest contiguous reusable span that still owns the non-compositional meaning. For example, store `the rest of`, not the contextual wrapper `for the rest of the day`; the wrapper remains occurrence evidence and its full translation remains in the book segment/alignment.

`translation` is occurrence evidence, not a dictionary gloss. Store the exact contiguous target span owned by the minimal source block, and require that span in every target segment referenced by the accepted audit decision. Keep a reusable paraphrase only in `explanation`. For `for the rest of the day → до конца дня`, store `the rest of → конца`; the excluded `for → до` and `day → дня` remain word-owned.

## Audit metadata

```json
{
  "block_audit": {
    "version": 1,
    "method": "codex_two_pass",
    "reviewed_segments": [
      {
        "source_text": "There are books.",
        "target_text": "Есть книги.",
        "status": "covered",
        "block_sources": ["there are"],
        "notes": ""
      }
    ],
    "second_pass": {
      "status": "passed",
      "unresolved_omissions": []
    },
    "necessity_pass": {
      "status": "passed",
      "block_decisions": [
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

Every `parallel[]` object must have a corresponding reviewed-segment entry. Use `status: no_block_required` when independent words fully represent the segment. Every retained block requires an accepted necessity decision. Reordering, inflection, proper-name grouping, ordinary compositional translation, and non-minimal contextual wrappers are rejection reasons, not block evidence.

## Global block

The merge adds provenance without removing book evidence:

```json
{
  "translations": ["находятся"],
  "type": "grammar_construction",
  "explanation": "Сообщает о наличии или местонахождении.",
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

## Scope and occurrence proof

The block audit stops after writing the book word seed, block seed, book layer,
and a skill-owned verification `word_to_word_<lang>.json`. It never rebuilds
globals, Workbench data, packages, or ZIP files.

Every attested retained block occurrence must appear as one verification block
occurrence. All component `word_id` values share that block's `owner_unit_id` and
`tap_unit_id`. A missing block, split tap units, an empty component without a
reason, or a whole translation copied to multiple components is blocking.
