---
name: lexo-add-uk-books-to-globals
description: Incrementally add words and blocks from explicitly selected, fully verified UK book dictionary files into LEXO UK Global dictionaries, audit the Ukrainian function-word reference layer, add carefully written missing Ukrainian function descriptions, and report book coverage. Use when the user asks to add selected Ukrainian books to UK Globals or audit UK Global coverage by book.
---

# LEXO Add UK Books to Globals

Operate only on explicitly selected `book_id` values. Never rebuild all books
implicitly and never clear Globals. Manual clearing is outside this skill.

## Scope

Read only:

- `seed_words_uk.json`;
- `seed_blocks_uk.json`, when present;
- an explicitly empty `book_layer_uk.json.blocks[]` only to prove that a
  missing block seed means zero blocks.
- `word_to_word_uk.json` and the audit statuses in `book_layer_uk.json`, only
  to prove the book passed the four-file `$lexo-uk-book-audit` contract.

Write only:

- `global_words_uk.json`;
- `global_blocks_uk.json`.
- `global_function_words_uk.json`, only for reviewed missing function records.

Never modify book seeds, book layers, Workbench, word-to-word files, Globals for
another language, packages, or ZIP files.

Reject legacy or incomplete UK books before reading their contributions. Require
all four UK artifacts, `target_lang: uk`, matching `book_id`, passed second,
third, and fourth audits with no unresolved items, and a UK verification proof.

Read `references/global-schema.md` before interpreting results.

## Add selected books

1. Confirm the exact selected `book_id` list.
2. Run a preview without `--write`:

```powershell
python Skills/lexo-add-uk-books-to-globals/scripts/add_books_to_globals.py add `
  --root <repo-root> --book-id <book_id> [--book-id <book_id> ...]
```

3. Treat seed/schema errors and audit errors as blocking.
4. Review every reported `function_missing` key. For each genuinely functional
   `lemma|POS`, write a concise Ukrainian `label` and reusable Ukrainian
   `explanation` to `global_function_words_uk.json`, then repeat preview.
   Derive candidates from functional POS categories and the selected seeds;
   never use a hardcoded English word list. Do not invent a contextual
   translation in this layer.
5. Review the per-book `added`, `new_translation`,
   `provenance_supplemented`, `skipped_existing`, and `skipped_empty` report.
6. Run the same command with `--write` only after the preview is clean.
7. Require the post-write second audit to report `errors: 0`.
8. Run the preview once more. It must add nothing and report all identical
   contributions as `skipped_existing`.

For words, identity is normalized `lemma|POS + translation`. For blocks,
identity is normalized `source + translation`. An existing key with a different
translation receives a new variant. An identical value is not duplicated; only
missing `book_ids` and `source_forms` are supplemented.

Transfer contextual seed translations as contextual variants. Transfer
`dictionary_translation` as a distinct `dictionary_fallback` variant even when
the same block also has contextual translations. A Global Block may hold one
reusable dictionary meaning and several book-context meanings. Never overwrite
or delete an existing valid meaning when adding another one, and never invent a
translation.

## Function-word layer

The function layer is a localized grammar reference, not another translation
dictionary. Each normalized `lemma|POS` record requires `label` and
`explanation`; optional `match_keys` cover parser POS aliases. A function word
may also remain in Global Words when it has an independent translation.

Audit `ADP`, `AUX`, `CCONJ`, `DET`, `EXPL`, `PART`, and `SCONJ` seed keys.
Treat different POS values independently (`to|ADP` is not `to|PART`). Preserve
all existing valid records byte-for-byte in meaning: never silently rewrite an
approved explanation. Missing descriptions block the Global add until the
skill reviews and adds them. After selected books pass, use `report` to verify
all earlier seed books as well.

Write every new functional `label` and `explanation` in Ukrainian. Do not copy
the Russian Function Words text; it may be consulted only as a coverage
checklist for English `lemma|POS` keys.

## Report unapplied books

Run:

```powershell
python Skills/lexo-add-uk-books-to-globals/scripts/add_books_to_globals.py report `
  --root <repo-root>
```

Classify every UK seed book from actual word, block, and function-description coverage:

- `fully_applied`: every non-empty seed contribution and provenance is present;
- `partially_applied`: at least one, but not all, contributions are present;
- `not_applied`: no contribution from the book is present;
- `invalid`: seeds cannot be audited safely.

Do not use a separate processed flag.

## Completion

Report selected books, word and block counts by action, function descriptions
added/existing/missing/invalid, every skip reason, errors, and post-write audit
results. Never claim completion when an expected seed contribution or function
description is missing, duplicated, or attached to the wrong key.

