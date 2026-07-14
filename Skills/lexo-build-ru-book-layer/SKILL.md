---
name: lexo-build-ru-book-layer
description: Create a complete Russian LEXO book layer from an English original and its approved Russian translation, including aligned parallel segments, context-specific word translations, phrase translations, component ownership, occurrence evidence, an independent second-pass audit, and a blocking third-pass word-ownership audit. Use when the user asks to create, generate, rebuild from source texts, or fully re-analyze a RU `book_layer_ru.json`, `seed_words_ru.json`, or `seed_phrases_ru.json` for one book.
---

# LEXO Build RU Book Layer

Build one Russian book layer at a time from the English source and the approved Russian translation. This skill creates evidence-backed dictionary data; it does not translate the book itself.

## Respect project authorization

Follow repository `AGENTS.md`. Read `Docs/History/INDEX.md` first. Inspect inputs and report the build plan before editing; wait for `ОК, правь` unless approval has already been given for that plan.

## Read the schema

Read `references/ru-book-layer-schema.md` completely before analyzing or writing a layer. Use the current code and current RU layers only to confirm integration details; never copy their lexical content into another book.

## Confirm inputs

Require one English original and one approved Russian translation for the same book. Locate existing import metadata when available and confirm:

- title and stable `book_id`;
- `source_lang: en` and `target_lang: ru`;
- source and translation segment counts;
- exact segment correspondence;
- output directory under `Studio/Backend/data/dictionaries/library_ru/books/<book_id>/`.

Stop if alignment is ambiguous. Do not invent missing Russian text, silently merge unrelated segments, or use machine translation as evidence.

## Build aligned parallel data

Read both texts completely. Produce `parallel[]` in reading order with exact `source` and `translation` values.

For every pair:

1. Verify that the Russian segment represents the complete English meaning.
2. Record alignment uncertainty instead of guessing.
3. Preserve punctuation and meaningful capitalization from the approved texts.
4. Never source dictionary values from hardcoded Python/Dart tables.

## Pass 1: construct words and phrases

Analyze every aligned pair.

### Words

Create a word record for every lexical occurrence required by the reader dictionary contract:

- preserve the actual English `word` form;
- derive `lemma` and `pos` from the project analyzer;
- choose `translation` from the current Russian segment;
- collect `translations[]` only when each form is supported by an occurrence in this book;
- distinguish repeated words whose context gives different Russian values;
- include every source word in `seed_words_ru.json`/`words[]`, including function words;
- when a function word is structurally absorbed, keep its entry with `translation: ""`, `translations: []`, and `empty_reason`; document the same ownership in phrase components;
- never assign a neighbouring noun, verb, adjective, or whole phrase translation to a function word (`the` must never receive the translation of `room` or `teacher`);
- keep independently translated function words only when an exact contextual target belongs to that word itself;
- never select a global dictionary value merely because it exists.

Treat global RU words as comparison material, not as primary evidence. Add confirmed contextual values; do not erase older confirmed values during later merge.

### Phrases

Create a phrase only when two or more source words form a meaning that cannot be recovered from their independently valid word translations. Phrase storage is a semantic exception layer, not a list of all multiword groups.

Reject a candidate when the target meaning is fully compositional from separate words. A collocation, prepositional group, proper name, reordered block, shared inflection, or natural Russian word order is not sufficient by itself. Examples that normally remain words: `first floor → первый этаж`, `look at → смотреть на` when `look → смотреть` and `at → на`, and `English teacher → учитель английского языка`.

Accept a candidate only when word-by-word translation loses or changes meaning, such as an idiom, phrasal verb with an absorbed particle, existential construction, or grammar construction with target meaning not owned by any component.

For every accepted phrase:

- save canonical English `source` and contextual Russian `translation`;
- assign a valid `type`;
- decompose it into `components[]` with lemma, POS, and contextual ownership;
- require `empty_reason` for an absorbed component without its own Russian span;
- save every confirming occurrence with exact source/target segments, actual source form, and Russian target span;
- prevent unrelated components from claiming the same target span.
- keep phrase records compact: `source`, `translation`, `type`, `components[]`, and attested `source_forms[]` only;
- never copy full source/target segments or audit explanations into `seed_phrases_ru.json` or a phrase record.

Keep ordinary compositional words separate unless grouping changes meaning, ownership, or target order.

## Pass 2: independent full re-analysis

After constructing the draft, start again from the first EN/RU segment. Do not use the Pass 1 word or phrase list as the checklist.

For every segment independently verify:

- every source word is represented or explicitly absorbed;
- no function word has stolen the target span of its lexical head or containing phrase;
- every chosen word translation occurs in or is directly supported by the Russian segment;
- context, inflection, number, gender, tense, and sense are correct;
- no non-literal multiword meaning was missed;
- reordered target spans have correct source ownership;
- function words are attached to the correct lexical head or phrase;
- no target span is duplicated across unrelated words/phrases;
- phrase components and occurrence evidence are complete;
- no translation was imported from another book without evidence here.

Record every segment in `book_layer_audit.reviewed_segments[]`, including clean segments. Put every problem in `second_pass.unresolved[]`, fix the draft, and repeat the second pass until the list is empty. Phrase count or word count alone never proves completion.

## Pass 3: independent word-ownership audit

Discard the Pass 1/2 ownership conclusions and audit every `lemma|POS` key again from its occurrences. This pass is mandatory and blocking.

For every key:

1. List every source occurrence and its complete EN/RU segment.
2. Decide separately for each occurrence whether the Russian meaning belongs to the word itself, a multiword phrase, a grammar construction, Russian morphology, or a zero correspondence.
3. Add a word translation only when a specific Russian span belongs to that word independently. A target conveying the whole construction is not a word translation.
4. Treat copular, auxiliary, and existential forms of `be` as empty when Russian expresses the predicate or construction as a whole. For example, `there are → находятся` does not prove `be → находятся`.
5. Distinguish prepositions that own an explicit target (`look at → смотреть на`, so `at → на`) from prepositions expressed only by case or by the whole construction.
6. Reverse-audit every claimed Russian span: name its single source owner and reject duplicated or shifted ownership.
7. Reconcile the decision with the word record, every phrase component, `absorbed_word_keys`, and both seed files. An absorbed key must not have a translated phrase component; a translated component must occur in the matching word entry.

Record one decision per word key in `book_layer_audit.third_pass.word_decisions[]`, including evidence and the final ownership classification. Put contradictions in `third_pass.unresolved[]`, correct the draft, and repeat Pass 3 until it is empty. Never copy Pass 2 conclusions into Pass 3 without re-evaluating the source pairs.

## Pass 4: phrase-necessity audit

Re-evaluate every retained phrase and every multiword candidate from the parallel segments.

1. Build the best translation obtainable from independently justified word entries, without borrowing the phrase translation back into its components.
2. Compare that result with the approved target meaning.
3. Remove the phrase when the meaning remains complete, even if Russian changes order, case, agreement, or natural phrasing.
4. Retain it only when separate words lose, distort, or fail to express the construction meaning.
5. Record accepted and rejected candidates in `book_layer_audit.fourth_pass.phrase_decisions[]` with `source`, `decision`, `word_by_word_result`, `reason`, and compact `segment_indexes[]` pointing into `parallel[]`.

Require exactly one accepted decision for each phrase in `phrases[]`, preserve rejected decisions as audit evidence, and repeat until `fourth_pass.unresolved[]` is empty.

Reject any artifact containing corruption runs such as `???` or `�`. Never pipe non-ASCII review JSON through a shell unless UTF-8 is proven; prefer UTF-8 files or ASCII audit text.

## Write reproducible outputs

After approval and a clean second pass:

1. Write `seed_words_ru.json` from verified book word evidence.
2. Write `seed_phrases_ru.json` from verified phrase evidence.
3. Write `book_layer_ru.json` with `parallel`, `words`, `phrases`, and audit metadata.
4. Run `scripts/validate_ru_book_layer.py <book_layer_ru.json>`. The validator also compares sibling seed files when they exist.
5. Rebuild RU global words/phrases through the project rebuild script; never hand-edit globals as the primary source.
6. Run global rebuild again in check mode and require `changed=false`.
7. Rebuild `dictionary_ru.json`, occurrence-level `word_to_word_ru.json`, and affected package ZIP.
8. Run relevant backend tests, Flutter regression, Python compile, and Dart analyze.
9. Update the current daily history and concise `Docs/History/INDEX.md` entry.

Treat validator errors and unresolved second-, third-, or fourth-pass findings as blocking.

## Report

Report:

- source and translation inputs;
- aligned/reviewed segment counts;
- unique word records and contextual translations;
- phrases and components created;
- corrections found during Pass 2;
- ownership corrections found during Pass 3;
- unresolved items, which must be zero for completion;
- validator, rebuild, idempotence, package, and test results.

Never claim that the RU book layer is complete unless every segment passed both semantic analyses and every word key passed the independent ownership audit.
