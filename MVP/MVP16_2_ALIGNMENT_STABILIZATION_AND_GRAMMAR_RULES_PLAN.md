# MVP16.2 — Alignment Stabilization And Grammar Rules Plan

## 1. Назначение этапа

`MVP16` уже дал первый рабочий слой `reorder-aware` alignment, но ещё не довёл engine до стабильного состояния.

Этот follow-up этап нужен, чтобы не потерять нить и зафиксировать всё, что обязательно должно быть доделано после первого среза:

- grammar / phrase units
- reporting verbs family
- metadata layer для grammar rules
- rebuild path для уже импортированных книг
- разделение translation bugs и alignment bugs

## 2. Что после MVP16 уже работает

- основной path переключён на `build_word_mappings_v2(...)`
- старый path сохранён как `build_word_mappings_v1(...)`
- lexical words уже могут брать target candidate слева или справа внутри `segment`
- runtime-проверки уже показывают улучшения:
  - `It is -> Сегодня`
  - `a beautiful -> прекрасный`
  - `day -> день`
  - `thinks -> думает`
  - `says -> говорит`

## 3. Что остаётся нестабильным

### 3.1 Обязательные недостающие blocks

Нужно добавить устойчивые unit-patterns для:

- `how are you`
- `in the afternoon`
- `goodnight`

Ожидаемые результаты:

- `How are you -> Как дела`
- `In the afternoon -> Днем`
- `Goodnight -> Доброй ночи`

### 3.2 Недостающие reporting verbs

Нужно добить:

- `ask/asks`
- `whisper/whispers`
- `reply/replies`
- `answer/answers`

Ожидаемые результаты:

- `asks -> спросил`
- `whispers -> шепчет`
- `replies -> отвечает`
- `answers -> отвечает`

### 3.3 Grammar metadata layer

Нужно расширить unit payload минимум полями:

- `rule_id`
- `rule_type`
- `explanation_id`

Примеры:

- `it_be`
- `how_are_you`
- `in_the_afternoon`
- `article_adjective`
- `goodnight_greeting`

### 3.4 Rebuild уже импортированных книг

Сейчас новые алгоритмы не пересчитывают старые `word_alignments` в `data/lexo.db`.

Нужен отдельный путь:

- rebuild word alignments для существующей книги

Без полного повторного импорта.

### 3.5 Явное разделение translation bugs и alignment bugs

Нужно различать:

- `TRANSLATION_QUALITY_PROBLEM`
- `ALIGNMENT_MISSING`
- `ALIGNMENT_SHIFT`
- `RULE_MISSING`

Чтобы по логам было видно, где проблема в самом переводе, а где в выравнивании.

## 4. Порядок внедрения

### Шаг 1

Добавить:

- `how_are_you`
- `in_the_afternoon`
- `goodnight`
- `ask/whisper/reply/answer`

### Шаг 2

Добавить в engine payload:

- `rule_id`
- `rule_type`
- `explanation_id`

### Шаг 3

Прокинуть эти поля в Flutter:

- `ParagraphWordItem`
- desktop reader
- mobile reader

### Шаг 4

Добавить rebuild path для старых книг.

### Шаг 5

Разделить в логах:

- translation bug
- alignment bug
- rule missing

## 5. Критерии готовности

Этап считается завершённым, если:

- `how are you` работает как единый block
- `in the afternoon` работает как единый block
- `goodnight` работает как single-token -> multiword target span
- `asks` и `whispers` больше не дают `ALIGNMENT_MISSING`
- reader payload несёт `rule_id/rule_type/explanation_id`
- старые книги можно пересчитать rebuild-командой
- лог явно различает translation bug и alignment bug

## 6. Главный ожидаемый результат

После `MVP16.2`:

- alignment engine станет стабильнее на реальных reader-кейсах
- grammar blocks станут отдельными сущностями
- UI получит базу для объясняющих grammar cards
- уже импортированные книги можно будет подтянуть под новый alignment без ручного полного reimport
