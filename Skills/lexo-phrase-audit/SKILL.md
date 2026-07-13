---
name: lexo-phrase-audit
description: Perform an exhaustive two-pass semantic audit of phrases and component words in a LEXO book layer, then update verified book/global dictionaries and rebuilt packages. Use when the user asks Codex to find missing phrases, audit phrase coverage, rebuild a book dictionary from parallel source/translation segments, or invokes `$lexo-phrase-audit` for RU or UK books.
---

# LEXO Phrase Audit

Work on one requested book and target language at a time. Treat current code, `Docs/History/INDEX.md`, and the book's `book_layer_{lang}.json` as sources of truth. Read `references/phrase-schema.md` before analyzing phrases.

## Respect project authorization

Follow the repository `AGENTS.md`. Start with read-only analysis. Present the audit report and concrete edit plan, then wait for `ОК, правь` unless that authorization has already been given after the plan.

## Locate the book

1. Read `Docs/History/INDEX.md`.
2. Find the requested `book_layer_{lang}.json` under `Studio/Backend/data/dictionaries/library_{lang}/books/`.
3. Confirm `book_id`, title, language, parallel count, word count, and phrase count.
4. Read the current global words/phrases and the matching Workbench output only after identifying the exact book.

## Pass 1: exhaustive extraction

Analyze every object in `parallel[]`; never use a hardcoded phrase list as the source of truth.

For each source/translation pair:

1. Identify phrasal verbs, fixed expressions, collocations, existential/grammar constructions, prepositional groups, multiword names, and reordered or discontinuous semantic blocks.
2. Keep ordinary compositional words independent unless grouping materially changes meaning, word ownership, or target order.
3. Record every accepted phrase using the schema in `references/phrase-schema.md`.
4. Decompose the phrase into `components[]`. Give each component its contextual target value. An empty component translation requires `empty_reason`.
5. Preserve occurrence evidence: segment source, target, source form, and target span text.
6. Add confirmed contextual component translations to the matching book word entry; never delete an older confirmed translation.

Do not infer a translation that is absent from the book target. Do not assign the same target span to unrelated source components.

## Pass 2: independent omission audit

Re-read every `parallel[]` pair without relying on the Pass 1 list as the checklist.

For each segment, ask:

- Is any multiword meaning represented non-literally?
- Did target order move a source construction?
- Does any function word belong to a lexical head or phrase?
- Is a target span still unowned even though it translates a source construction?
- Is any source construction covered only by an incorrect whole-sentence fallback?
- Are components missing, duplicated, or assigned to another occurrence?

Record every segment in `phrase_audit.reviewed_segments[]`, including segments with no phrases. Resolve omissions, then repeat the audit until `unresolved_omissions` is empty. Never claim completion from phrase count alone.

## Validate before merge

Run:

```powershell
python Skills/lexo-phrase-audit/scripts/validate_phrase_layer.py <book_layer_path>
```

Treat any validator error as blocking. Review warnings manually. Also compare the phrase list against every parallel segment yourself; the deterministic validator cannot judge semantics.

## Update dictionaries

After approval and a clean audit:

1. Update the book word/phrase seeds so regeneration preserves the result.
2. Update `book_layer_{lang}.json` atomically.
3. Rebuild global words and phrases through the project rebuild script; do not edit globals as the primary source.
4. Run the global rebuild again in check mode and require `changed=false`.
5. Rebuild `dictionary_{lang}.json`, occurrence-level `word_to_word_{lang}.json`, and package ZIPs.
6. Confirm phrase headers use global phrases while `Words` uses individual occurrence-level word entries.
7. Run backend tests, Flutter regression tests, Python compile, and Dart analyze relevant to the change.
8. Update the current daily history and the concise INDEX entry.

## Report

Report:

- reviewed segment count;
- phrases added, changed, and removed;
- component translations added to book words;
- unresolved omissions (must be zero for completion);
- validator/test results;
- rebuilt package scope;
- any judgment calls requiring user review.

Never report the phrase layer as complete when only a hardcoded seed list was checked.