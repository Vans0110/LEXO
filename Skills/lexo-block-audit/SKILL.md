---
name: lexo-block-audit
description: Create and audit the complete RU dictionary files for one LEXO book from parallel EN/RU segments. Build verified word seeds, minimal reusable semantic blocks, the RU book layer, and occurrence-level verification; reject compositional or oversized groups and prove every occurrence. Use for new RU book dictionaries, missing/excessive block audits, RU book dictionary rebuilds, or `$lexo-block-audit` for RU books.
---

# LEXO Block Audit

Work on one requested RU book at a time. Treat current code, `Docs/History/INDEX.md`, and the book's `book_layer_ru.json` as sources of truth. Read `references/block-schema.md` and `references/ru-book-layer-schema.md` before analyzing or writing book files.

## Respect project authorization

Follow the repository `AGENTS.md`. Start with read-only analysis. Present the audit report and concrete edit plan, then wait for `ОК, правь` unless that authorization has already been given after the plan.

## Locate the book

1. Read `Docs/History/INDEX.md`.
2. Find the requested `book_layer_ru.json` under `Studio/Backend/data/dictionaries/library_ru/books/`.
3. Confirm `book_id`, title, language, parallel count, word count, and block count.
4. Read the current global words/blocks and the matching Workbench output only after identifying the exact book.

## Pass 1: exhaustive extraction

Analyze every object in `parallel[]`; never use a hardcoded block list as the source of truth.

For each source/translation pair:

1. Identify multiword candidates, but do not accept them from category alone.
2. Translate their components independently. Reject the candidate when those word translations preserve the complete target meaning.
3. Do not treat a collocation, name, prepositional group, reordered block, case change, agreement, or natural target order as a block unless separate words lose or change meaning.
4. Accept only semantic exceptions: idioms, non-compositional phrasal verbs, existential/grammar constructions, and other groups whose meaning cannot be reconstructed word by word.
5. Minimize every accepted block. Remove a leading or trailing word whenever the remaining block still carries the same non-compositional meaning. A full contextual expression must not replace its reusable inner construction.
6. Write one concise Russian `explanation` describing what the construction means or does. Make it reusable across books; do not explain the surrounding sentence.
   Keep `type` as the schema's technical enum, but never use that English enum as user-facing text. The application must render its approved Russian label: `phrasal_verb → фразовый глагол`, `fixed_expression → устойчивое выражение`, `collocation → словосочетание`, `grammar_construction → грамматическая конструкция`, `prepositional_group → предложная группа`, `name_group → группа имени собственного`, `reordered_block → блок с изменённым порядком слов`. Do not invent a new English display label.
7. Record every accepted block using the compact schema in `references/block-schema.md`; keep necessity proof only in audit metadata.
8. Decompose the block into `components[]`. Give each component only its independently owned target value. An empty component translation requires `empty_reason`.
9. Preserve only attested `source_forms[]` in the block. Store evidence as `segment_indexes[]` in the audit; never duplicate complete source/target segments inside block records or seeds.
10. Set the book block `translation` to the exact contiguous target span owned by the minimal source block in its attested occurrence. It must occur verbatim after token normalization in every evidence segment. Do not put a dictionary gloss, paraphrase, teaching definition, or translation owned by an excluded wrapper word into this field.
11. When the reusable dictionary meaning differs from the attested occurrence span, preserve it separately as `dictionary_translation`. Never replace or delete one valid meaning with another: the Global Block merge must retain the dictionary meaning and add every distinct contextual `translation` as a variant.

Do not infer a translation that is absent from the book target. Do not assign the same target span to unrelated source components.
Keep the reusable semantic description only in `explanation`. Example: in `for the rest of the day → до конца дня`, the minimal block `the rest of` owns `конца`; `for` independently owns `до`, and `day` owns `дня`.
For that block, keep `dictionary_translation: "оставшаяся часть чего-либо"` and occurrence `translation: "конца"`; they are complementary values, not alternatives to overwrite.

## Pass 2: independent omission audit

Re-read every `parallel[]` pair without relying on the Pass 1 list as the checklist.

For each segment, ask:

- Is any multiword meaning represented non-literally?
- Did target order move a source construction?
- Does any function word belong to a lexical head or block?
- Is a target span still unowned even though it translates a source construction?
- Is any source construction covered only by an incorrect whole-sentence fallback?
- Are components missing, duplicated, or assigned to another occurrence?

Record every segment in `block_audit.reviewed_segments[]`, including segments with no blocks. Resolve omissions, then repeat the audit until `unresolved_omissions` is empty. Never claim completion from block count alone.

Preserve every attested surface form in occurrence verification. An inflected
function form keeps both `surface` and `lemma`; learner-facing data must not
replace the encountered form with its lemma. Function-reference completeness
is checked later by `$lexo-add-ru-books-to-globals`, which requires separate
surface records and permits POS aliases only for the same surface.

## Pass 3: independent necessity audit

Start again without using the accepted block list as truth. For every retained block and every rejected multiword candidate:

- construct the best word-by-word result from independent dictionary meanings;
- reject the block if that result preserves the full meaning;
- ignore mere reordering, inflection, case, agreement, names, and ordinary collocations;
- retain the block only when word-by-word translation loses or changes meaning;
- record the decision and reason in `block_audit.necessity_pass.block_decisions[]`;
- reject an accepted candidate when a shorter contiguous block preserves the same exceptional meaning.

Reject outputs containing corruption runs such as `???` or `�`.

Require one accepted decision per retained block, keep rejected decisions as evidence against reintroduction, and finish only with `unresolved=[]`.

## Validate before merge

## Pass 5: complete target coverage

After word and block ownership is stable, tokenize every Russian `parallel[].translation`
and subtract all independently owned word spans. Classify every remaining target span
semantically from the complete EN/RU segment as exactly one of:

- `block`: owned by an already verified semantic block;
- `insertion`: a target-language structural addition that is not the translation of
  one source word;
- `restructure`: a target span produced by a wider source construction or sentence
  recast without inventing a word translation.

Write the decisions to `word_to_word_ru.json.target_coverage[]` with exact target
indexes, all participating `source_word_ids[]`, and a concise Russian `reason`.
Use `display_anchor_word_id` plus `highlight_target_start_index` /
`highlight_target_end_index` only when a single tapped source word can honestly keep
its dictionary card while the reader highlights the wider target realization. POS and
distance are candidate filters, never semantic proof. Never hardcode source or target
lexemes in the materializer. If ownership is ambiguous, record the audit item as
unresolved and do not publish the book. Completion requires every target token to be
owned by a word span or `target_coverage[]`.

Run:

```powershell
python Skills/lexo-block-audit/scripts/validate_block_layer.py <book_layer_path>
python Skills/lexo-block-audit/scripts/validate_ru_book_layer.py <book_layer_path>
```

The second command also requires and validates the sibling RU seeds and
skill-owned verification `word_to_word_ru.json`. Treat any validator error
as blocking. Review warnings manually. Also compare the block list against
every parallel segment yourself; deterministic validators cannot judge
semantics.

## Write and verify book word files

After approval and a clean audit:

1. Update the book word/block seeds so regeneration preserves the result.
2. Update `book_layer_ru.json` atomically.
3. Build a skill-owned occurrence-level `word_to_word_ru.json` directly
   from verified book tokens, word seeds, block seeds, and ownership decisions.
   Use `scripts/materialize_verified_word_files.py` when materializing from the
   verified reader, alignment, and review inputs.
4. Require one classified entry per `word_id`, one shared `tap_unit_id` for all
   components of a retained block, one exact shared target span for that block,
   and one materialized block for every attested block occurrence. Reject an
   occurrence when its block translation cannot be found in the target segment.
5. Require complete target-side coverage. Preserve exact word translation spans and
   keep display highlight spans separate; never widen a word's semantic span merely
   to absorb a neighboring Russian token.
5. Run `scripts/validate_block_layer.py`, `scripts/validate_ru_book_layer.py`,
   Python compile, and `scripts/test_verification_word_to_word.py`.
6. Update the current daily history and the concise INDEX entry.

Never rebuild or edit globals, Workbench data, application assets,
CloudLibrary files, production packages, or ZIP files. Never change Flutter.
Those are outside this skill.

## Report

Report:

- reviewed segment count;
- blocks added, changed, and removed;
- component translations added to book words;
- unresolved omissions (must be zero for completion);
- validator/test results;
- verification word-to-word occurrence and block-occurrence counts;
- any judgment calls requiring user review.

Never report the block layer as complete when only a hardcoded seed list was checked.
