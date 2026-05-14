# MVP23_7 — Clean Adapter Layer / Resolved JSON -> UI Bridge

## 1. Цель

Сделать так, чтобы:

- backend один раз строил финальный `resolved_alignment JSON`
- этот JSON был единственной истиной
- adapter layer больше не принимал alignment-решений
- adapter layer только перекладывал backend truth в формат, который ждёт UI

Главный принцип:

`backend думает, adapter мапит, UI показывает`

---

## 2. Какая проблема есть сейчас

Сейчас между:

- `segment_resolved_alignments.alignment_json`

и

- UI payload (`paragraphs`, `words`, `translation_span_text`, `target_start_index`, и т.д.)

есть слой адаптации.

Проблема не в самом наличии этого слоя.

Проблема в том, что adapter может:
- применять `resolved`
- потом ещё применять raw `SimAlign`
- потом ещё фильтровать
- потом ещё сам раздавать span-ы словам

То есть он местами ведёт себя не как mapper, а как второй mini-resolver.

Это и надо убрать.

---

## 3. Что должно быть после чистки

Правильная схема:

1. backend собрал финальный `resolved JSON`
2. adapter прочитал этот JSON
3. adapter разложил его в текущий UI-формат
4. UI показал результат

Не должно быть:
- повторного alignment
- повторного выбора winners
- подмешивания raw `SimAlign` поверх resolved
- “если тут пусто, давай сами додумаем”

---

## 4. Что adapter layer должен делать

Оставить только 4 функции.

### A. Читать финальный resolved JSON

Adapter должен брать:
- `segment_resolved_alignments.alignment_json`

как source of truth.

### B. Раскладывать его в UI payload

Нужно формировать:
- `paragraphs`
- `segments_v2`
- `words`
- `translation_span_text`
- `target_start_index`
- `target_end_index`
- `alignment_status`
- `tap_unit_id`
- нужные detail-sheet поля

### C. Привязывать resolved result к текущей word/paragraph структуре

Потому что UI сейчас живёт через:
- paragraph list
- segment list
- word list

Это нормальная функция адаптера.

### D. Давать fallback только если resolved отсутствует

Если у сегмента нет resolved JSON вообще:
- тогда допустим fallback на raw `SimAlign`

Но только как fallback отсутствия данных, а не как вторая правда.

---

## 5. Что adapter layer не должен делать

Это нужно вырезать.

### Нельзя

- заново назначать target span, если resolved уже есть
- применять raw `SimAlign` поверх resolved
- фильтровать/alter `aligned / absorbed / omitted / rejected`
- переигрывать owner semantics
- выдавать слову перевод, которого нет в финальном JSON
- решать, что phrase “слишком неудобен” и лучше раздать span по словам
- принимать новые alignment-решения на UI bridge уровне

Идея:
`adapter не имеет права улучшать backend`

---

## 6. Граница ответственности

### Backend отвечает за:

- segmentation
- translation
- alignment
- candidate generation
- scoring
- conflict resolution
- status resolution
- финальный `resolved JSON`

### Adapter отвечает за:

- чтение backend truth
- mapping в UI format
- сохранение текущей совместимости API payload

### UI отвечает за:

- рендер
- tap interaction
- отображение уже переданной карты

---

## 7. Что нужно сохранить, чтобы не сломать систему

Это нельзя удалять.

### Оставить обязательно

- сборку `paragraphs`
- сборку `words`
- связь слов с paragraph/segment
- текущий API shape для Flutter
- поля, на которые уже завязан UI:
  - `translation_span_text`
  - `target_start_index`
  - `target_end_index`
  - `alignment_status`
  - `tap_unit_id`
  - detail-sheet поля

То есть adapter остаётся как форматный мост.

---

## 8. Что нужно вычистить

Вот это и есть суть MVP.

### Убрать / отключить

- raw `SimAlign` path поверх сегментов, у которых уже есть resolved
- повторную post-filter логику, меняющую backend result
- phrase/compound обходные ветки, которые ломают resolved truth
- word-level span assignment, если он не следует прямо из final JSON
- “спасение” пустых слов через старые raw links, если resolved уже всё решил

---

## 9. Новый жёсткий runtime rule

Нужно зафиксировать правило:

### Rule 1

Если у сегмента есть `resolved_alignment`:
- adapter использует только его

### Rule 2

Если у сегмента нет `resolved_alignment`:
- adapter может использовать fallback path

### Rule 3

Fallback path не имеет права вмешиваться, если resolved уже присутствует

Это главное системное правило.

---

## 10. Как adapter должен работать после чистки

### Для `aligned`

Adapter:
- читает span из final JSON
- переносит его в word payload
- не меняет

### Для `absorbed`

Adapter:
- передаёт пустой span
- выставляет status
- не пытается найти replacement span

### Для `omitted`

Adapter:
- передаёт пустой span
- выставляет status
- не выдумывает coverage

### Для `rejected`

Adapter:
- передаёт пустой span
- выставляет status
- не подмешивает raw match

---

## 11. Что делать с phrase / compound в adapter layer

Это важно зафиксировать.

### Phrase

Если backend решил phrase-owner:
- adapter должен уважать это решение
- не раздавать тот же target span внутренним словам как новую самостоятельную истину

### Compound

Если backend решил compound-owner:
- adapter должен следовать backend truth
- если UI-формат требует word-level payload, то это должна быть именно раскладка backend result, а не новый resolve

То есть:
- phrase/compound semantics задаёт backend
- adapter только отображает их в текущей модели

---

## 12. Fallback policy

Fallback нужен только для переходного режима.

### Допустимый fallback

- `resolved JSON` отсутствует
- тогда можно использовать raw `SimAlign`

### Недопустимый fallback

- `resolved JSON` есть, но adapter решил, что он “недостаточно хороший”
- и сам подмешал raw

Этого быть не должно.

---

## 13. Этапы чистки adapter layer

### Этап A. Аудит

Проверить все места в adapter layer, где:
- применяется resolved
- применяется raw
- применяется повторная фильтрация
- происходит word-level reassignment

### Этап B. Жёсткий gating

Ввести правило:
- `if resolved exists -> no raw override`

### Этап C. Упростить mapping

Оставить только:
- чтение final JSON
- перенос в UI fields

### Этап D. Проверка переходных кейсов

Прогнать:
- `aligned`
- `absorbed`
- `phrase`
- `compound`
- `rejected`

### Этап E. Cleanup legacy branches

Удалить или изолировать старые bridge-ветки, которые больше не нужны.

---

## 14. Что проверять после чистки

Нужно проверить минимум 5 типов кейсов.

### 1. Обычное lexical word

- `door -> дверь`

### 2. Grammar absorbed

- `the -> null`

### 3. Phrase owner

- `wake up -> просыпается`

### 4. Compound owner

- `bus driver -> водитель автобуса`

### 5. Rejected

- слово без надёжного match не получает поддельный span

---

## 15. Критерии готовности

Слой считается готовым, когда выполняются все условия:

- resolved JSON реально стал единственной истиной
- adapter не подмешивает raw `SimAlign`, если resolved уже есть
- adapter не меняет backend statuses
- adapter не создаёт новых spans, которых нет в final JSON
- UI payload полностью следует backend truth
- fallback работает только при отсутствии resolved

---

## 16. Что не нужно делать

Не нужно:
- удалять весь adapter layer целиком
- переписывать Flutter-модели прямо сейчас
- переводить UI на прямое чтение таблицы из БД
- строить новый bridge-DSL
- добавлять новую backend логику в adapter

---

## 17. Итог

Финальная цель этого MVP-слоя:

`adapter layer остаётся, но становится тупым`

То есть:
- не resolver
- не второй alignment engine
- не корректировщик backend
- а только mapper:

`resolved JSON -> UI payload`
