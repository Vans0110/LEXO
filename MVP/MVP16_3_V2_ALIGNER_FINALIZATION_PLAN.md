# MVP16.3 — V2 Aligner Finalization Plan

## 1. Цель этапа

Довести `build_word_mappings_v2(...)` в `engine/word_alignment.py` до состояния, где он является не просто безопасной надстройкой над `v1`, а основным локальным `reorder-aware` aligner внутри одного `segment`.

Этот этап не про новые UI-элементы и не про новые логи. Он про стабилизацию самого ядра выравнивания:

- candidate spans вместо single-index candidates
- устойчивое разрешение конфликтов между соседними lexical words
- меньше зависимости от старого positional fallback
- лучшее поведение на reorder и multiword target spans

## 2. Что уже есть после MVP16 / MVP16.2

- `build_word_mappings_v2(...)` уже включён как основной path
- lexical words уже могут переезжать в target слева или справа внутри `segment`
- добавлены unit-rules:
  - `it_be`
  - `how_are_you`
  - `in_the_afternoon`
  - `goodnight`
- добит ряд reporting verbs:
  - `say/says`
  - `think/thinks`
  - `ask/asks`
  - `whisper/whispers`
  - `reply/replies`
  - `answer/answers`
- reader payload и UI уже знают про:
  - `rule_id`
  - `rule_type`
  - `explanation_id`

## 3. Что остаётся недоведённым в v2

### 3.1 Single-token bias

Сейчас `v2` всё ещё мыслит в основном через один target index на source word.

Нужно перейти на candidate spans:

- `start_index`
- `end_index`
- `span_text`

Это критично для:

- `доброй ночи`
- `как дела`
- `смотрит в`
- других коротких multiword target spans

### 3.2 Слабый conflict resolution

Сейчас соседние lexical words всё ещё могут заезжать друг на друга или уводить последний content word в соседний смысловой кусок.

Нужен жадный conflict resolver:

- учитывать уже занятые target indices
- разрешать overlap только если нет лучшего варианта
- предпочитать span меньшего конфликта и лучшей lexical quality

### 3.3 Слишком сильная зависимость от v1 current index

Сейчас `v2` ещё слишком охотно доверяет тому, что назначил `v1`.

Нужно:

- сравнивать current span с candidate spans
- разрешать `v2` переигрывать `v1`, если candidate span явно лучше

### 3.4 Multiword direct-meaning candidates

Сейчас `direct_meaning_for_word(...)` используется в основном как набор токенов, а не как набор candidate phrases.

Нужно:

- выделять короткие candidate sequences из direct meaning
- искать их в target токенах как spans

## 4. Что конкретно сделать в коде

### Шаг 1

Добавить в `engine/word_alignment.py` candidate span model:

- `_candidate_target_spans(...)`
- `_pick_best_candidate_span(...)`
- helper для multiword sequences из direct meanings

### Шаг 2

Переделать `build_word_mappings_v2(...)` так, чтобы:

- lexical words оценивались через candidate spans
- занятые target indices учитывались как покрытие span-ов
- hard anchors и хорошие lexical matches проходили раньше слабых кандидатов

### Шаг 3

Сделать greedy span assignment:

- hard anchors first
- затем lexical words
- затем оставить старую inheritance-логику function words

### Шаг 4

Проверить контрольные кейсы:

- `Tom thinks -> думает Том`
- `Anna says -> говорит Анна`
- `How are you -> Как дела`
- `Goodnight -> Доброй ночи`
- `looks out -> смотрит в`
- `It is a beautiful day`

## 5. Что не входит в этот этап

- новые grammar screens / explanation pages
- rebuild старых книг
- отдельная система лог-классов ошибок
- массовое добавление новых phrase rules

## 6. Критерии готовности

Этап считается выполненным, если:

- `v2` выбирает candidate spans, а не только один target index
- lexical words могут получать короткие multiword spans там, где это оправдано
- reorder-кейсы стабильнее без новых ad-hoc патчей
- конфликт соседних lexical words уменьшается
- `v2` меньше зависит от старого positional `v1`

