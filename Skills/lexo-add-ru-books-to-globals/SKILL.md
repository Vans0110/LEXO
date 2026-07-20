---
name: lexo-add-ru-books-to-globals
description: Incrementally add words and blocks from explicitly selected RU book seed files into LEXO Global word and block dictionaries, skip identical values with reasons, add new contextual translations as variants, and report books that are fully, partially, or not applied. Use when the user asks to add selected RU books to Globals or audit Global coverage by book.
---

# LEXO Add RU Books to Globals

Operate only on explicitly selected `book_id` values. Never rebuild all books
implicitly and never clear Globals. Manual clearing is outside this skill.

## Scope

Read only:

- `seed_words_ru.json`;
- `seed_blocks_ru.json`, when present;
- an explicitly empty `book_layer_ru.json.blocks[]` only to prove that a
  missing block seed means zero blocks.

Write only:

- `global_words_ru.json`;
- `global_blocks_ru.json`.

Never modify book seeds, book layers, Workbench, word-to-word files, Globals for
another language, packages, or ZIP files.

Read `references/global-schema.md` before interpreting results.

## Add selected books

1. Confirm the exact selected `book_id` list.
2. Run a preview without `--write`:

```powershell
python Skills/lexo-add-ru-books-to-globals/scripts/add_books_to_globals.py add `
  --root <repo-root> --book-id <book_id> [--book-id <book_id> ...]
```

3. Treat seed/schema errors and audit errors as blocking.
4. Review the per-book `added`, `new_translation`,
   `provenance_supplemented`, `skipped_existing`, and `skipped_empty` report.
5. Run the same command with `--write` only after the preview is clean.
6. Require the post-write second audit to report `errors: 0`.
7. Run the preview once more. It must add nothing and report all identical
   contributions as `skipped_existing`.

For words, identity is normalized `lemma|POS + translation`. For blocks,
identity is normalized `source + translation`. An existing key with a different
translation receives a new variant. An identical value is not duplicated; only
missing `book_ids` and `source_forms` are supplemented.

Transfer contextual seed translations as contextual variants. Transfer
`dictionary_translation` only when the seed has no contextual translations and
mark it `dictionary_fallback`. Never invent a translation.

## Report unapplied books

Run:

```powershell
python Skills/lexo-add-ru-books-to-globals/scripts/add_books_to_globals.py report `
  --root <repo-root>
```

Classify every RU seed book from actual contribution coverage:

- `fully_applied`: every non-empty seed contribution and provenance is present;
- `partially_applied`: at least one, but not all, contributions are present;
- `not_applied`: no contribution from the book is present;
- `invalid`: seeds cannot be audited safely.

Do not use a separate processed flag.

## Completion

Report selected books, word and block counts by action, every skip reason,
errors, and post-write audit results. Never claim completion when an expected
seed contribution is missing, duplicated, or attached to the wrong translation.
