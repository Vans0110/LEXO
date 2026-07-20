# Incremental RU Global schema

## Word identity

Global word key: normalized lowercase `lemma|UPPER_POS`.

```json
{
  "lemma": "lemma",
  "pos": "POS",
  "translations": ["перевод"],
  "variants": [
    {
      "translation": "перевод",
      "translation_kind": "contextual",
      "book_ids": ["book_id"],
      "source_forms": ["source form"]
    }
  ]
}
```

`lemma|POS + case-insensitive translation` is unique. A different translation
creates another variant. An identical translation supplements provenance only.
Fallback variants use `translation_kind: dictionary_fallback`; a contextual
contribution upgrades the same translation to `contextual`.

## Block identity

Global block key: normalized lowercase source block.

```json
{
  "translations": ["перевод"],
  "type": "grammar_construction",
  "explanation": "Короткое переиспользуемое пояснение конструкции.",
  "variants": [
    {
      "translation": "перевод",
      "translation_kind": "contextual",
      "book_ids": ["book_id"],
      "source_forms": ["attested form"]
    }
  ],
  "components": []
}
```

`normalized source + case-insensitive translation` is unique. Block components
are merged by normalized `source + lemma + POS + translation`; book provenance
is supplemented without duplicate component records.

`type` and `explanation` are required. The explanation describes the reusable
block rather than the complete sentence. Conflicting non-empty values for the
same normalized source are blocking and must not be silently merged.

## Preservation

An add operation may append a new key, translation, variant, source form, book
id, or component. It must not remove or rewrite unrelated existing content.
Output ordering is deterministic so a repeated add is idempotent.
