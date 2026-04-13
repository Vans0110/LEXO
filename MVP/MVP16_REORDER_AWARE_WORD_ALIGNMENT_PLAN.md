# MVP16 — Reorder-Aware Word Alignment Plan

## 1. Цель этапа

Перестроить текущий `word alignment` внутри одного `segment` так, чтобы он устойчиво работал не только на почти прямом порядке слов, но и на локальной перестановке слов в переводе.

Итог этапа:

- `word -> translation span` перестаёт быть почти чисто позиционным
- внутри одного `segment` source word может получать target span и слева, и справа
- `tap unit` больше не строится поверх уже сломанного word alignment
- reader начинает устойчивее обрабатывать:
  - инверсию порядка слов
  - служебные grammar blocks
  - adjective/noun reorder
  - reporting verbs после реплики

Ключевая продуктовая цель:

`segment translation` должен оставаться естественным, а `word/tap alignment` должен объяснять его без системного смещения соседних слов.

## 2. Проблема текущей архитектуры

Сейчас `engine/word_alignment.py` работает так:

1. source segment токенизируется
2. target segment токенизируется
3. ищутся hard anchor-и
4. segment разбивается на окна
5. content words раздаются по target почти позиционно
6. function words наследуют target от соседнего content word
7. уже после этого поверх готовых word spans строятся `tap units`

Это даёт системные ошибки в таких случаях:

- `Tom thinks -> думает Том`
- `It is -> Сегодня`
- `a beautiful day -> прекрасный день`
- `Anna says -> говорит Анна`
- локальная перестановка adjective / noun / verb вокруг имени или цитаты

Ключевой дефект:

- текущий aligner в основном предполагает монотонный порядок слов
- `tap unit` создаётся слишком поздно и не исправляет сломанный word-level mapping

## 3. Что не надо делать

Этап не должен:

- переписывать весь переводчик
- вводить внешнюю alignment model
- тянуть attention/embeddings/новую ML модель
- ломать существующий `reader payload` API
- строить глобальное выравнивание между абзацами

Этап должен остаться:

- локальным
- внутри одного `segment`
- детерминированным
- объяснимым по логам

## 4. Главный принцип нового этапа

Нужно перейти от:

`position-first alignment`

к:

`candidate-first local alignment`

То есть для слова мы сначала ищем возможные target candidates, а уже потом выбираем лучший span внутри текущего `segment`.

Не правило:

- "следующее source слово должно почти обязательно мапиться в следующий target token"

А правило:

- "source word или source unit должны получить лучший совместимый target span внутри этого segment, даже если он стоит левее или правее ожидаемой позиции"

## 5. Основная новая модель

### 5.1 Segment остаётся базовой единицей

Все решения принимаются внутри одного `segment`.

Новый aligner не прыгает:

- в соседний `segment`
- в соседний абзац

### 5.2 Candidate spans

Для каждого source word или source unit нужно строить набор target-кандидатов:

- exact normalized match
- anchor dictionary match
- direct meaning match
- simple lemma hints
- phrase-rule match
- n-gram candidates внутри target text

### 5.3 Reorder-aware выбор

Кандидат может лежать:

- слева
- справа
- на той же позиции

в пределах текущего `segment`.

То есть инверсия:

- `Tom thinks -> думает Том`

должна быть допустимым и нормальным сценарием.

### 5.4 Unit-aware alignment

`tap units` нужно учитывать не после сломанного aligner-а, а во время выравнивания.

То есть:

- некоторые конструкции сначала распознаются как локальный unit
- unit сам предлагает target span
- потом его span распределяется на UI payload

## 6. Что именно нужно изменить в коде

## 6.1 Новый internal path

Вместо немедленной переписи старой логики нужно ввести новый внутренний путь:

- `build_word_mappings_v2(...)`

Старый путь:

- `build_word_mappings(...)`

временно остаётся для сравнения и rollback.

## 6.2 Новый pipeline внутри `word_alignment.py`

Новый pipeline должен быть разбит на явные стадии:

1. tokenize source / target
2. detect source units
3. collect candidate target spans
4. resolve strong anchors
5. resolve lexical words
6. resolve function words
7. build final spans
8. build tap payloads

Это нужно вместо текущей скрытой смеси:

- anchor matching
- positional assignment
- function inheritance
- post-hoc unit building

## 6.3 Strong / soft / function разделение

Source items должны делиться минимум на 3 класса:

- `strong anchors`
- `lexical words`
- `function words`

### Strong anchors

Примеры:

- имена
- числа
- `chapter`
- слова с точным curated translation candidate

### Lexical words

Примеры:

- `beautiful`
- `day`
- `garden`
- `thinks`

### Function words

Примеры:

- `the`
- `a`
- `is`
- `to`
- `and`

Порядок разрешения должен быть:

1. strong anchors
2. lexical words
3. function words

## 6.4 Candidate scoring

Для каждого candidate span нужен score.

Минимальные факторы score:

- точное lexical совпадение
- hit по `ANCHOR_TRANSLATIONS`
- hit по `DIRECT_MEANINGS`
- phrase-rule hit
- близость к уже зафиксированным сильным словам
- штраф за слишком далёкое смещение
- штраф за пересечение с уже занятым strong anchor
- штраф за function-token span у lexical слова

## 6.5 Span вместо single-token мышления

Новый aligner должен нормально поддерживать:

- одиночный target token
- многословный target span
- unit span
- grammar/context span

То есть модель должна быть не:

- `source word -> один target token`

а:

- `source word or unit -> target span [start:end]`

## 6.6 Unit detection до финального payload

Нужно распознавать локальные source units раньше, чем строится финальный tap payload.

Критичные unit-типы для этапа:

- `it + be`
- `article + adjective`
- `article + noun`
- `article + adjective + noun`
- `phrasal verb`
- `chapter + number`
- `time`
- `name + reporting verb`

Важно:

unit не обязан стать одним огромным блоком для UI.

Например:

- `It is a beautiful day`

в reader может распадаться на:

- `It is -> Сегодня`
- `a beautiful -> прекрасный`
- `day -> день`

То есть unit detection нужен не ради giant-block, а ради правильного поиска target span.

## 6.7 Conflict resolution

Если два source item претендуют на один target span:

- strong anchor имеет приоритет
- phrase/unit может занимать объединённый span
- function word может наследовать span unit-а
- слабый lexical candidate должен отступать

## 6.8 UI payload должен остаться совместимым

На выходе reader по-прежнему должен получить те же поля:

- `translation_span_text`
- `translation_left_text`
- `translation_focus_text`
- `translation_right_text`
- `source_unit_text`
- `tap_unit_id`

То есть этап меняет внутреннюю alignment-логику, но не контракт reader payload.

## 7. Этапы внедрения

## 7.1 Этап A — v2 skeleton

Сделать новый internal path:

- `build_word_mappings_v2(...)`

Пока без полного переключения storage.

Нужно:

- вынести старые helper-ы
- сделать новую структуру пайплайна
- добавить compare/debug возможность

## 7.2 Этап B — candidate engine

Добавить:

- candidate collection
- scoring
- left/right reorder support

Без полного удаления старого positional fallback.

## 7.3 Этап C — unit-aware alignment

Добавить ранний unit detection для:

- `it + be`
- `article + adjective`
- `article + adjective + noun`
- `name + says/thinks`

## 7.4 Этап D — switch storage/runtime to v2

После проверки:

- новый путь становится основным
- старый остаётся только как fallback/debug path

## 7.5 Этап E — cleanup

После стабилизации:

- удалить временные compare-helper-ы
- упростить устаревшие positional workaround-ветки

## 8. Контрольные шаблоны, которые реально нужны в коде

Это именно pattern classes, а не просто примеры текста:

- `pronoun + be`
- `it + be`
- `article + adjective`
- `article + noun`
- `article + adjective + noun`
- `name + reporting_verb`
- `phrasal_verb`
- `chapter + number`
- `time`

## 9. Контрольные примеры для проверки

Это не шаблоны кода, а тестовые фразы.

Минимальный контрольный набор:

- `It is a beautiful day, Tom thinks.`
- `Tom thinks.`
- `Anna says hello.`
- `He is happy.`
- `The sun is bright.`
- `He looks out the window.`
- `Chapter 2`
- `7:00 AM`
- `a big garden`
- `red flowers and green trees`

Плюс обязательные ожидаемые раскладки для проблемных кейсов:

### 9.1 It is a beautiful day

Ожидаемо:

- `It is -> Сегодня`
- `a beautiful -> прекрасный`
- `day -> день`

Не должно получаться:

- `beautiful -> день`
- `day -> думает`

### 9.2 Tom thinks

Ожидаемо:

- `Tom -> Том`
- `thinks -> думает`

Даже если перевод переставляет порядок:

- `думает Том`

### 9.3 Anna says hello

Ожидаемо:

- `Anna -> Анна`
- `says -> говорит`
- `hello -> привет`

## 10. Что не считается успехом этапа

Не считается успехом:

- ещё 5-10 новых узких hardcoded patch-правил без общей модели
- giant phrase units вместо нормальных смысловых блоков
- исправление только `thinks/says`
- исправление только `it is`
- отсутствие explainable logs

## 11. Критерии готовности

Этап считается завершённым, если:

- внутри одного `segment` aligner устойчиво переживает локальный reorder
- `word -> target span` больше не полагается только на позицию
- проблемные кейсы не ломают соседние lexical words
- `tap unit` и `word span` больше не расходятся системно
- reader logs показывают предсказуемую и объяснимую alignment-картину

## 12. Главный ожидаемый результат

После `MVP16` reader должен перейти от:

- "примерно угадали соседний target token"

к:

- "нашли осмысленный local target span даже при перестановке слов"

Это нужно не ради одной фразы `It is a beautiful day`, а ради устойчивого поведения всей reader alignment architecture.
