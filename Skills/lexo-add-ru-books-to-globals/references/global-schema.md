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

## Phrase identity

Global phrase key: normalized lowercase source phrase.

```json
{
  "translations": ["перевод"],
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

`normalized source + case-insensitive translation` is unique. Phrase components
are merged by normalized `source + lemma + POS + translation`; book provenance
is supplemented without duplicate component records.

## Preservation

An add operation may append a new key, translation, variant, source form, book
id, or component. It must not remove or rewrite unrelated existing content.
Output ordering is deterministic so a repeated add is idempotent.
