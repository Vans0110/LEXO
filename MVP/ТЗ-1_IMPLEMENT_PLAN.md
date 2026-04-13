# ТЗ-1 Implement Plan

## Очередь 1. Quality Contract

Цель: перестать врать в payload, не ломая текущий pipeline.

1. `engine/translator.py`
- Ввести `translation_kind` на уровне segment result.
- Минимальные значения:
  - `rule_exact`
  - `literal_exact`
  - `literal_partial`
  - `provider_fallback`
  - `untranslated`
  - `grammar_only`
- Возвращать не просто `list[str]`, а структуру segment translation result.
- Отдельно помечать unknown token cases.

2. `engine/word_alignment.py`
- Ввести внутренние и выходные поля:
  - `alignment_kind`
  - `matched_by`
  - `is_untranslated`
  - `is_inherited`
  - `is_grammar_only`
  - `is_phrase_member`
- Не считать `the -> к/в/на` и `is -> adjective` lexical match.
- Для function words перевод и alignment разделить.

3. `engine/storage.py`
- Расширить схему `word_alignments` и/или `source_words` под quality fields.
- Прокинуть новые поля в `get_paragraphs()`.
- Расширить `ParagraphWordItem` payload.

4. `app/lib/src/models.dart`
- Добавить в `ParagraphWordItem`:
  - `translationKind`
  - `alignmentKind`
  - `matchedBy`
  - `qualityState`
  - `isUntranslated`
  - `isGrammarOnly`
  - `isPhraseMember`

5. `app/lib/src/screens/reader_screen.dart`
- Убрать логику “непустой `translation_span_text` = успех”.
- Использовать quality fields для debug и UI state.

Regression coverage этой очереди:
- `He eats eggs and toast.`
- `He sees a big garden with red flowers and green trees.`
- `The sun is bright.`
- `He is happy.`

## Очередь 2. Canonical Detail + Segmenter Fix

Цель: выровнять desktop/mobile и исправить грубые source-ошибки.

1. `engine/segmenter.py`
- Добавить типы:
  - `heading_title`
  - `heading_chapter`
  - `meta_time`
- Сначала выделять heading/meta, потом dialogue/time/copula/simple.
- Исправить кейс `Chapter ... At 10:00 AM, ...`.

2. `engine/storage.py`
- Перестроить `_build_paragraph_payloads()` под новые `segment_type`.
- Сделать canonical detail payload builder.
- Backend обязан отдавать полный top-level contract:
  - `rule_id`
  - `rule_type`
  - `explanation_id`
  - `grammar_hint`
  - `quality_state`
- И unit-level contract с quality fields.

3. `app/lib/src/detail_sheet_models.dart`
- Привести модель к реальному backend contract.
- Убрать зависимость от локальной догадки там, где должен отвечать backend.

4. `app/lib/src/screens/reader_screen.dart`
- Desktop fallback оставить только аварийным.
- Основной путь: canonical backend detail payload.

5. `app/lib/src/ui/mobile/screens/mobile_reader_screen.dart`
- Уйти от отдельного локального алгоритма detail builder.
- Лучше сразу перейти на packaged canonical detail data.

Regression coverage этой очереди:
- `The Sunny Morning`
- `Chapter 1: The New Day`
- `At 10:00 AM, Tom goes to the park`
- `"Good morning, Luna!" Tom says.`
- `In the afternoon, Tom goes home.`
- `It is a beautiful day.`

## Очередь 3. Storage Normalization

Цель: убрать строковую хрупкость target-side.

1. `engine/storage.py`
- Добавить таблицу `target_tokens`.
- Сохранять target token sequence для каждого segment.
- Перевести aggregation и detail span recovery на token layer.

2. `engine/word_alignment.py`
- Перевести span-модель с “индексы в строке” на “индексы token layer”.
- Сохранить совместимость с текущим reader payload.

3. `engine/storage.py`
- Пересобрать:
  - `build_context_window()`
  - detail unit translation
  - translation bar inputs
  через `target_tokens`.

Regression coverage этой очереди:
- phrase/detail consistency
- stable context bar
- stable target span reconstruction

## Отдельные обязательные правки

1. `engine/lexical_enrichment.py`
- Ослабить fallback POS.
- Лучше пусто/`UNKNOWN`, чем ложный `VERB`.
- Не ставить `morph_label` на слабой эвристике.

2. `app/test/widget_test.dart`
- Удалить или переписать под текущий shell.

3. Старый UX слой
- Не использовать в основном контуре:
  - [word_card.dart](/mnt/d/Programs/LEXO/app/lib/src/widgets/word_card.dart)
  - [saved_words_screen.dart](/mnt/d/Programs/LEXO/app/lib/src/screens/saved_words_screen.dart)
  - `/word/audio` stub

## Рекомендуемый порядок правок

1. Quality fields в backend/storage/models.
2. Function words + untranslated semantics.
3. Canonical detail payload.
4. Segmenter heading/meta fix.
5. Mobile detail unification.
6. POS/morph cleanup.
7. `target_tokens`.

## Критерий “можно считать улучшением” после первой итерации

- `eggs/toast/flowers/trees` больше не выглядят как нормальный перевод без статуса.
- `the/is` больше не выглядят как точный lexical alignment.
- desktop и mobile перестают расходиться по detail logic.
- heading/time кейсы перестают ломать persisted segments.
