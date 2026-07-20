---
name: lexo-uk-book-audit
description: Create and audit all UK dictionary files for one LEXO book from approved parallel EN/UK segments, using the verified RU book only as a structural coverage reference. Build Ukrainian word seeds, minimal semantic blocks, the UK book layer, and occurrence-level verification. Use for new Ukrainian book dictionaries, UK word selection, missing or excessive block audits, rebuilds, and checks of previously created UK books.
---

# LEXO UK Book Audit

Work on one requested UK book at a time. Read `Docs/History/INDEX.md`,
`references/block-schema.md`, and `references/uk-book-layer-schema.md` before
writing. Follow repository authorization rules.

## Fix the evidence boundary

Use the approved English source and Ukrainian translation as the only semantic
evidence. Locate the verified RU book by stable `book_id`, or by exact title
when historical language IDs differ. Use RU only as a structural checklist:

- compare English source coverage, word keys, candidate constructions, and
  occurrence counts;
- investigate every RU block and absorbed occurrence, but decide it again from
  EN/UK;
- never translate RU values, explanations, blocks, spans, or `empty_reason`
  fields into Ukrainian;
- never require a UK block merely because RU has one, or omit a UK-specific
  block merely because RU lacks one.

Reject stale UK layer content as evidence when it disagrees with the approved
EN/UK segments. Confirm `book_id`, title, `target_lang: uk`, parallel count,
word count, block count, and the four expected output paths.

## Pass 1: select every word

Review every English occurrence in every `parallel[]` pair. Create one
`lemma|POS` seed entry for every source word, including function words.

For each key:

1. Keep only Ukrainian values supported by the book.
2. Separate independent contextual ownership from teaching fallback.
3. Never assign a neighbouring lexical word's Ukrainian span to an article,
   auxiliary, particle, or preposition.
4. When no independent Ukrainian span exists, keep empty `translation` and
   `translations`, add a precise Ukrainian `empty_reason`, and classify every
   occurrence.
5. Use `mixed` only when the same key has both independent and structurally
   absorbed occurrences.
6. Use a one-word `dictionary_translation` only as `skill_fallback`; it is not
   occurrence evidence.

## Pass 2: select minimal semantic blocks

Analyze every EN/UK pair without using RU blocks as answers.

- Accept only idioms, non-compositional phrasal verbs, existential or grammar
  constructions, and other spans whose full meaning cannot be reconstructed
  from independently owned words.
- Reject ordinary collocations, names, Ukrainian case or agreement, natural
  reordering, and ordinary prepositional groups when separate words preserve
  the meaning.
- Minimize every retained source span.
- Store the exact contiguous Ukrainian occurrence span in `translation`.
- Store a reusable Ukrainian dictionary meaning separately in
  `dictionary_translation` when it differs.
- Write concise reusable Ukrainian `explanation` text.
- Give each component only its independently owned Ukrainian value; require
  Ukrainian `empty_reason` for empty components.

## Pass 3: independent omission and ownership audits

Re-read all pairs without treating the current word or block lists as truth.
Record every segment, including `no_block_required`. Check unowned target
spans, omitted source meanings, duplicate ownership, function-word absorption,
and blocks hidden by whole-sentence fallbacks.

Create exactly one ownership decision for every `lemma|POS`. Require every
non-empty component value in its word record. Require empty absorbed components
to identify the owning construction or Ukrainian morphological relation.
Finish only with empty `unresolved[]` lists.

## Pass 4: independent necessity audit

For every retained and rejected candidate, construct the best word-by-word
Ukrainian result. Retain a block only when that result loses or changes meaning.
Require one accepted decision per retained block, retain rejected decisions as
evidence, require zero unresolved decisions, and reject encoding corruption.

## Write exactly four book artifacts

After approval and clean semantic review, write atomically:

- `seed_words_uk.json`;
- `seed_blocks_uk.json`;
- `book_layer_uk.json`;
- skill-owned `word_to_word_uk.json`.

Require one classified verification entry per `word_id`, exact source token
order, one shared tap unit for all block components, exact Ukrainian target
spans, and one block occurrence for every attested retained block occurrence.

Run:

```powershell
python Skills/lexo-uk-book-audit/scripts/validate_block_layer.py <book_layer_path>
python Skills/lexo-uk-book-audit/scripts/validate_uk_book_layer.py <book_layer_path>
python Skills/lexo-uk-book-audit/scripts/audit_uk_books.py --root <repo-root>
```

Treat every validator error as blocking and review semantic warnings manually.
Also run Python compile and `scripts/test_verification_word_to_word.py`.

## Recheck earlier UK books

After creating the requested book, run the contour audit for all UK book
directories. Report each as:

- `valid`: all four artifacts pass and verified RU structural coverage agrees;
- `stale`: all four pass locally but verified RU English coverage differs;
- `invalid`: all four exist but deterministic validation fails;
- `not_created`: one or more required artifacts are absent.

Do not silently edit earlier books. Report them and wait for their explicit
selection before rebuilding.

## Scope

Never modify UK Globals, RU artifacts, Workbench data, application assets,
CloudLibrary files, production packages, ZIP files, or Flutter. Update project
history after a substantial confirmed book or skill change.

Report reviewed segments, selected word keys, blocks added/changed/removed,
occurrence and block-occurrence counts, RU-reference discrepancies,
unresolved items, validator results, and the all-book contour status.
