# Incremental UK Global schema

## Word identity

Global word key: normalized lowercase `lemma|UPPER_POS`.

```json
{
  "lemma": "lemma",
  "pos": "POS",
  "translations": ["переклад"],
  "variants": [
    {
      "translation": "переклад",
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
  "translations": ["переклад"],
  "type": "grammar_construction",
  "explanation": "Коротке багаторазове пояснення конструкції.",
  "variants": [
    {
      "translation": "переклад",
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

A block can contain several valid meanings. Preserve `dictionary_translation`
as a `dictionary_fallback` variant and each exact book occurrence translation
as a `contextual` variant. For example, `the rest of` may contain both
`решта чогось` and `кінця`; adding the latter must not replace the
former.

`type` and `explanation` are required. The explanation describes the reusable
block rather than the complete sentence. Conflicting non-empty values for the
same normalized source are blocking and must not be silently merged.

## Preservation

An add operation may append a new key, translation, variant, source form, book
id, or component. It must not remove or rewrite unrelated existing content.
Output ordering is deterministic so a repeated add is idempotent.

## Function-word identity

Global function key: normalized lowercase `lemma|UPPER_POS`.

```json
{
  "be|AUX": {
    "label": "Початкова форма be",
    "explanation": "Короткий багаторазовий опис граматичної функції.",
    "match_keys": ["be|VERB"]
  }
}
```

`label` and `explanation` are localized reference text, not translations from
a book. `match_keys` is optional and may only contain normalized keys. Existing
valid descriptions are preserved; an absent functional `lemma|POS` found in a
selected seed must be reviewed and added before the Global merge can pass.

