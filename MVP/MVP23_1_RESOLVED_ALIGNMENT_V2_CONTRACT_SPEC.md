# Спецификация `resolved_alignment_v2_contract`

Этот документ фиксирует `source of truth` для нового `resolved alignment`-контракта перед дальнейшими правками resolver-контура.

---

## 1. Зачем нужен этот контракт

Он фиксирует:

- что именно resolver считает `unit`
- чем `type` отличается от `status`
- что считается валидным aligned-result
- что такое `owner`
- что runtime/UI имеют право ожидать от persisted JSON

Без этого дальше нельзя нормально трогать:
- `engine/alignment_contract.py`
- `engine/alignment_units.py`
- `engine/alignment_resolver.py`
- `engine/runtime_simalign_clean.py`

---

## 2. Главный принцип

`type` и `status` должны быть независимы.

Примеры:
- `type=word`, `status=aligned`
- `type=grammar`, `status=absorbed`
- `type=compound`, `status=aligned`
- `type=phrase`, `status=rejected`

Нельзя больше смешивать:
- `phrase` как тип unit-а
- `absorbed` как будто это тоже тип
- `rejected` как будто это тоже тип

---

## 3. Что такое unit в этом контракте

`unit` — это source-side сущность, которую resolver пытается объяснить через target.

Unit может быть:
- отдельным словом
- grammar-словом
- обязательной phrase-единицей
- optional compound-гипотезой

То есть unit — это не обязательно UI-склейка.
Это прежде всего объект alignment-решения.

---

## 4. Целевые `type`

Нужно зафиксировать ровно 4 базовых типа.

### `word`

- обычное лексическое слово
- primary case для content words

Примеры:
- `opened`
- `door`
- `happy`

### `grammar`

- служебное или грамматическое слово/блок
- не обязано иметь собственный target span

Примеры:
- `the`
- `to`
- `is`

### `phrase`

- неделимый смысловой или грамматический блок
- его нельзя честно разбирать как независимые отдельные links без потери смысла

Примеры:
- `wake up`
- `look out`
- `there is`
- `have to`
- `good morning`
- `of course`

### `compound`

- составной кандидат для alignment
- может помогать resolver-у выбрать лучшее объяснение
- не обязан автоматически становиться единым tap-unit в UI

Примеры:
- `bus driver`
- `school bus`
- `front door`

---

## 5. Целевые `status`

Нужно зафиксировать 4 базовых статуса.

### `aligned`

- найден валидный target span
- resolver считает match достаточно надёжным

### `absorbed`

- у unit нет собственного target span
- смысл unit-а встроен в morphology, grammar, owner-span или структуру target

Типичные случаи:
- `the`
- часть grammar phrase
- function word, поглощённый падежом/видом/структурой RU

### `omitted`

- source unit в целевом переводе реально не выражен отдельным смысловым элементом
- это не то же самое, что `absorbed`

Разница:
- `absorbed` = смысл встроен
- `omitted` = смысл/элемент в переводе не реализован явно

### `rejected`

- resolver не нашёл достаточно надёжного объяснения
- лучше честно не дать link, чем дать ложный

---

## 6. Обязательные поля unit-а

Для каждого unit в persisted JSON фиксируется обязательный минимум:

```json
{
  "unit_id": "seg_123:u_4",
  "source_text": "bus driver",
  "source_start": 1,
  "source_end": 2,
  "target_text": "водитель автобуса",
  "target_start": 0,
  "target_end": 1,
  "type": "compound",
  "status": "aligned",
  "confidence": 0.94,
  "signals": {
    "simalign": 0.81,
    "dictionary": 0.92,
    "position": 0.88,
    "grammar": 1.0,
    "phrase": 1.0,
    "context": 0.84
  },
  "meta": {}
}
```

Обязательные поля:
- `unit_id`
- `source_text`
- `source_start`
- `source_end`
- `target_text`
- `target_start`
- `target_end`
- `type`
- `status`
- `confidence`
- `signals`
- `meta`

---

## 7. Правила по target-полям

Если `status=aligned`:
- `target_text` должен быть не `null`
- `target_start >= 0`
- `target_end >= target_start`

Если `status=absorbed | omitted | rejected`:
- `target_text = null`
- `target_start = -1`
- `target_end = -1`

Это избавляет runtime от неоднозначности.

---

## 8. Что должно быть в `signals`

Минимально допустимые ключи:

- `simalign`
- `dictionary`
- `position`
- `grammar`
- `phrase`
- `context`

Правила:
- значения от `0.0` до `1.0`
- отсутствие сигнала допустимо
- runtime не должен зависеть от полного набора сигналов
- `signals` — debug/inspection layer, а не источник UI-логики

---

## 9. Что должно быть в `meta`

`meta` нужен для explainability и owner-логики.

Минимально полезные поля:
- `pattern`
- `owner_mode`
- `owner_unit_id`
- `candidate_source`
- `resolution_notes`

Примеры:
- `pattern: "verb_part"`
- `owner_mode: "always_phrase"`
- `owner_mode: "optional_compound"`
- `candidate_source: "raw_simalign_span"`
- `candidate_source: "dictionary_span"`
- `owner_unit_id: "seg_123:u_4"`

---

## 10. Что такое owner

`owner` — это unit, который объясняет более крупный смысловой блок и может поглощать более слабые внутренние кандидаты.

Примеры:
- `wake up` может быть owner для `wake` и `up`
- `bus driver` может быть compound-owner для пары `bus` + `driver`

Важно:
- owner не равен UI-склейке
- owner — это прежде всего resolver-semantic relation

---

## 11. Разница между `phrase` и `compound`

### `phrase`

- unit обязателен как единый смысловой блок
- разбиение обычно ухудшает качество и смысл
- resolver должен давать ему высокий приоритет

### `compound`

- unit является полезной составной гипотезой
- отдельные слова всё ещё могут жить самостоятельно
- resolver выбирает между:
  - compound explanation
  - отдельными word-links
  - смешанным вариантом

Это ключевая договорённость для случаев вроде `bus driver`.

---

## 12. Совместимость со старым `v1`

Старый формат сейчас фактически использует:
- `type = word | phrase | absorbed | rejected`
- `status = aligned | absorbed | rejected`

Во `v2` нужно:
- перестать писать `absorbed/rejected` в `type`
- но при чтении старых payload-ов runtime/loader должен уметь их мягко нормализовать

Рекомендуемая нормализация:
- если `type=absorbed`, читать как:
  - `type=grammar`
  - `status=absorbed`
- если `type=rejected`, читать как:
  - `type=word`
  - `status=rejected`

Это migration policy, а не новая истина.

---

## 13. Что должен гарантировать resolver

Инварианты:

- один unit имеет ровно один итоговый `status`
- `aligned` unit имеет ровно один итоговый target span
- `type` не зависит от того, найден ли target span
- `status` не определяет semantic type unit-а
- unresolved cases должны быть честно представлены как `absorbed`, `omitted` или `rejected`
- runtime не должен выдумывать target span там, где resolver его не утвердил

---

## 14. Что должен ожидать runtime/UI

Runtime может:
- читать `type`
- читать `status`
- читать `target_*`
- читать `confidence`
- читать `signals`
- использовать `meta.owner_unit_id` для debug/detail

Runtime не должен:
- заново придумывать новый alignment поверх resolved-unit
- склеивать unit-ы только потому, что у них общий span
- подставлять фейковый span для `absorbed/omitted/rejected`

---

## 15. Что должно стать результатом Шага 1

После этого шага должны быть готовы:

1. Новый MVP/spec файл с `resolved_alignment_v2_contract`
2. Зафиксированные таблицы:
   - `types`
   - `statuses`
   - обязательные поля
   - инварианты
3. Несколько canonical JSON examples:
   - lexical aligned
   - grammar absorbed
   - phrase aligned
   - compound aligned
   - rejected
   - omitted
4. Migration notes для `v1 -> v2`

---

## 16. Что будет следующим шагом после этого

Сразу после утверждения контракта уже имеет смысл идти в код и делать:

- переработку `engine/alignment_contract.py`
- затем новый `phrase/compound candidate layer` в `engine/alignment_units.py`
- затем обновление resolver-а под новый `type/status/meta`

---

## 17. Практический вывод

Шаг 1 фиксирует 5 вещей:

- `phrase` и `compound` — это разные типы
- `type` и `status` независимы
- `aligned / absorbed / omitted / rejected` — это целевая статусная модель
- owner — это resolver-отношение, а не автоматическая UI-склейка
- runtime читает resolved-слой как истину и не выдумывает новый alignment
