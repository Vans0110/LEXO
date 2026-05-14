# Спецификация `status resolution + final payload semantics`

Это следующий слой после:
- `resolved_alignment_v2_contract`
- `phrase / compound candidate layer`
- `candidate generation`
- `scoring v2`
- `conflict resolution + owner semantics`

Его задача:
- взять результат winner-selection
- преобразовать его в окончательный persisted `units[]` payload
- зафиксировать, какие `status`, `type`, `target_*`, `meta`, `signals`, `confidence` реально попадают в финальный JSON

Главная идея:
- resolver должен не только выбрать правильных победителей
- он должен ещё и последовательно упаковать итог так, чтобы runtime/UI не додумывали логику сами

---

## 1. Зачем нужен этот слой

После conflict resolution у нас есть:
- winners
- подавленные кандидаты
- owner-relations
- unresolved cases

Но этого ещё недостаточно для persisted result.

Потому что нужно ответить:
- какие unit-ы вообще писать в финальный `units[]`
- что писать для непобедивших внутренних слов
- где ставить `aligned`, а где `absorbed`
- когда писать `rejected`
- когда писать `omitted`
- какие `meta` сохранять
- какие `signals` сохранять
- какие поля обязаны быть `null/-1`

Если это не зафиксировать, runtime опять начнёт “чинить” backend своим локальным кодом.

---

## 2. Главный принцип

Финальный payload должен быть:
- минимально двусмысленным
- полностью самодостаточным
- пригодным для runtime без дополнительной интерпретации

То есть:
- status должен уже говорить, что произошло
- target fields должны уже быть консистентны
- owner/meta должны уже быть заполнены
- runtime не должен заново решать, как понимать unit

---

## 3. Что является входом этого слоя

Status resolution должен получать:
- canonical source units
- winner candidates
- owner relations
- suppressed internal units
- rejected candidate info
- raw signals/final scores выбранных winners

Этого достаточно, чтобы собрать финальный resolved payload.

---

## 4. Что является выходом

Итогом должен быть список `ResolvedAlignmentUnit` v2.

Каждый unit в финальном payload:
- соответствует source-side unit
- имеет ровно один итоговый status
- имеет консистентные target-поля
- имеет explainability поля

---

## 5. Какие unit-ы должны попадать в final payload

Это важно зафиксировать.

### Должны попадать

- все canonical source unit-ы
- phrase unit-ы, если они canonical
- grammar unit-ы
- optional compound unit-ы только если они реально выбраны как итоговое explanation-решение

### Не обязаны попадать

- все candidate hypotheses подряд
- все подавленные промежуточные spans
- служебные shortlist-объекты candidate generation

То есть:
- final payload хранит результат решения
- а не полный trace всего поиска

---

## 6. Правило “один unit = один итоговый результат”

Для каждого unit в final payload должно быть:
- ровно одно итоговое состояние
- ровно один итоговый `status`
- ровно один итоговый `type`
- либо один итоговый target span
- либо отсутствие target span по правилу статуса

Это главный инвариант финального JSON.

---

## 7. Как мапить winner в final `status`

### Если unit выиграл real target span

Тогда:
- `status = aligned`

### Если unit не получил собственного span, но объяснён через grammar/owner absorption

Тогда:
- `status = absorbed`

### Если unit plausibly отсутствует в переводе как отдельный выраженный элемент

Тогда:
- `status = omitted`

### Если resolver не готов честно утверждать ничего

Тогда:
- `status = rejected`

---

## 8. Как мапить owner-covered случаи

Это один из самых важных вопросов.

### Phrase owner win

Если phrase-owner победил:
- сам phrase unit получает:
  - `status = aligned`
- внутренние слабые unit-ы:
  - не должны дублировать owner span
  - обычно получают:
    - `absorbed`, если они функционально встроены
    - либо `rejected`, если отдельный unit-result не нужен
  - owner relation пишется в `meta`

### Compound owner win

Если compound-owner победил:
- compound unit получает:
  - `status = aligned`
- внутренние слова:
  - могут остаться `aligned`, если у них clean independent links
  - иначе:
    - `absorbed`
    - или `rejected`
  - owner relation пишется в `meta`

### Рекомендуемое правило для `v2`

- phrase owner: более жёсткий
- compound owner: более мягкий

---

## 9. Когда писать `absorbed`

`absorbed` нужно писать только тогда, когда это реально объяснимое отсутствие отдельного span.

### Типичные случаи

- артикли
- служебные предлоги
- grammar helper words
- слова, встроенные в grammar owner
- internal function pieces phrase-owner блока

### Не надо писать `absorbed`, если

- unit просто не удалось надёжно сопоставить
- unit content-heavy, но evidence нет
- match слишком слабый и непонятный

В таких случаях лучше:
- `rejected`
- или иногда `omitted`

---

## 10. Когда писать `omitted`

`omitted` — это не мусорный статус.
Он нужен для реального случая, когда source unit не выражен в переводе отдельным смысловым элементом.

### Примеры

- source содержит слабый discourse marker
- в переводе этот элемент сознательно не передан
- compression translation
- часть content unit ушла в более свободную перестройку без отдельного recoverable span

### Когда не писать `omitted`

- для обычного unresolved grammar слова, которое очевидно absorbed
- для всех непонятных случаев подряд
- если resolver просто не уверен

Тогда лучше `rejected`.

---

## 11. Когда писать `rejected`

Это честный fail-closed статус.

Нужно писать `rejected`, если:
- unit не объяснён надёжным target span
- не выглядит как absorbed
- не выглядит как omitted
- owner не даёт достаточного основания
- кандидатная борьба ничего не утвердила уверенно

Это важно, потому что `rejected` лучше ложного aligned.

---

## 12. Как заполнять `target_*` поля

Правила должны быть жёсткие.

### Для `aligned`

- `target_text` обязателен
- `target_start >= 0`
- `target_end >= target_start`

### Для `absorbed`

- `target_text = null`
- `target_start = -1`
- `target_end = -1`

### Для `omitted`

- `target_text = null`
- `target_start = -1`
- `target_end = -1`

### Для `rejected`

- `target_text = null`
- `target_start = -1`
- `target_end = -1`

Runtime должен уметь опираться на это без дополнительных догадок.

---

## 13. Как заполнять `confidence`

### Для `aligned`

- `confidence = final_score` победившего candidate
- либо post-normalized equivalent, если позже появится calibration

### Для `absorbed`

- confidence не должен быть нулём
- если absorbed подтверждён grammar/owner logic:
  - нормальный высокий confidence допустим
  - например `0.85 .. 0.98`

### Для `omitted`

- confidence отражает уверенность именно в omitted-решении
- не “нет данных”, а “resolver считает omission plausibly correct”

### Для `rejected`

- обычно низкий confidence
- например `0.0 .. 0.3`
- либо можно оставить `0.0`, если хотим максимально жёсткую трактовку

---

## 14. Как заполнять `signals`

### Для `aligned`

Сохранять полный набор победившего candidate:
- `simalign`
- `dictionary`
- `position`
- `grammar`
- `phrase`
- `context`

### Для `absorbed`

Сохранять только релевантные сигналы:
- `grammar`
- возможно `context`
- возможно `phrase`, если absorption вызван owner-отношением

### Для `omitted`

Сигналы могут быть сокращёнными:
- `context`
- `grammar`
- опционально `phrase`

### Для `rejected`

Можно сохранять:
- либо пустой `signals`
- либо частичный diagnostic snapshot, если это полезно для дебага

Для `v2` лучше не перегружать rejected units большим мусором.

---

## 15. Как заполнять `meta`

`meta` должен хранить explainability, а не повторять основные поля.

Минимально полезные поля:
- `owner_unit_id`
- `owner_mode`
- `resolution_role`
- `selection_reason`
- `pattern`
- `candidate_source`

### Примеры

- `resolution_role = primary_owner`
- `resolution_role = independent_word`
- `resolution_role = absorbed_after_phrase_owner`
- `resolution_role = absorbed_after_compound_owner`
- `selection_reason = best_scored_compatible_candidate`
- `selection_reason = grammar_absorption`
- `selection_reason = unresolved_after_conflict_filter`

---

## 16. Нужно ли сохранять подавленные кандидаты

В final public payload — нет.

Final `units[]` не должен превращаться в debug dump.

Если позже нужен trace:
- делать отдельный debug payload
- отдельную таблицу
- отдельный resolver debug mode

Но основной persisted alignment должен хранить:
- только итоговые unit-results

---

## 17. Порядок unit-ов в final payload

Нужно зафиксировать стабильный порядок.

Рекомендуемое правило:
- сортировка по `source_start`
- при равном `source_start`:
  - сначала более широкий canonical owner
  - потом внутренние smaller unit-ы
  - либо наоборот, но строго одинаково во всех местах

Для `v2` удобнее:
- сначала более широкий unit
- потом внутренние

Потому что так payload естественно читается как high-level-first.

---

## 18. Что делать с optional compound в final payload

Это важный отдельный вопрос.

### Если compound не победил

- не писать его в финальный `units[]`

### Если compound победил как meaningful explanation

- писать его как отдельный final unit

### Если compound победил, но внутренние слова тоже полезны

- писать compound unit
- и при необходимости сохранять внутренние canonical word units тоже
- но без дублирования одной и той же роли без причины

Для `LEXO` это даёт гибкий вариант:
- compound есть как high-level explanation
- слова остаются доступными как локальные элементы

---

## 19. Canonical final payload examples

### Example 1

`door -> дверь`

```json
{
  "unit_id": "u1",
  "source_text": "door",
  "source_start": 4,
  "source_end": 4,
  "target_text": "дверь",
  "target_start": 2,
  "target_end": 2,
  "type": "word",
  "status": "aligned",
  "confidence": 0.95,
  "signals": {
    "simalign": 1.0,
    "dictionary": 0.95,
    "position": 0.9,
    "grammar": 1.0,
    "phrase": 0.0,
    "context": 0.8
  },
  "meta": {
    "resolution_role": "independent_word",
    "selection_reason": "best_scored_compatible_candidate"
  }
}
```

### Example 2

`the`

```json
{
  "unit_id": "u2",
  "source_text": "the",
  "source_start": 3,
  "source_end": 3,
  "target_text": null,
  "target_start": -1,
  "target_end": -1,
  "type": "grammar",
  "status": "absorbed",
  "confidence": 0.93,
  "signals": {
    "grammar": 1.0
  },
  "meta": {
    "resolution_role": "grammar_absorbed",
    "selection_reason": "grammar_absorption"
  }
}
```

### Example 3

`wake up`

```json
{
  "unit_id": "u3",
  "source_text": "wake up",
  "source_start": 1,
  "source_end": 2,
  "target_text": "просыпается",
  "target_start": 1,
  "target_end": 1,
  "type": "phrase",
  "status": "aligned",
  "confidence": 0.91,
  "signals": {
    "simalign": 0.88,
    "dictionary": 0.8,
    "position": 0.9,
    "grammar": 1.0,
    "phrase": 1.0,
    "context": 0.9
  },
  "meta": {
    "owner_mode": "always_phrase",
    "resolution_role": "primary_owner"
  }
}
```

### Example 4

`bus driver`

```json
{
  "unit_id": "u4",
  "source_text": "bus driver",
  "source_start": 1,
  "source_end": 2,
  "target_text": "водитель автобуса",
  "target_start": 0,
  "target_end": 1,
  "type": "compound",
  "status": "aligned",
  "confidence": 0.89,
  "signals": {
    "simalign": 0.8,
    "dictionary": 1.0,
    "position": 0.85,
    "grammar": 1.0,
    "phrase": 0.9,
    "context": 0.85
  },
  "meta": {
    "owner_mode": "optional_compound",
    "resolution_role": "primary_owner"
  }
}
```

---

## 20. Что должно стать результатом Шага 6

После этой спеки должны быть готовы:

1. Правила маппинга winner-selection -> final status
2. Правила заполнения `target_*`
3. Правила заполнения `confidence`
4. Правила заполнения `signals`
5. Правила заполнения `meta`
6. Правила включения/невключения unit-ов в final payload
7. Порядок unit-ов в `units[]`
8. Canonical final JSON examples

---

## 21. Что будет следующим шагом после этой спеки

После этого уже логично делать:
- `runtime / UI resolved-layer integration spec`

Потому что теперь final payload уже формально определён, и можно отдельно зафиксировать:
- как runtime его читает
- как строится word/tap payload
- как показывать phrase/compound owner cases
- как вести себя с `absorbed / omitted / rejected`

---

## 22. Практический вывод

Шаг 6 должен зафиксировать 6 главных вещей:

- winner-selection ещё не равен финальному payload
- каждый unit должен получить ровно один итоговый status
- `aligned / absorbed / omitted / rejected` должны мапиться в жёсткие target-field rules
- owner semantics должны доходить до persisted `meta`
- final payload должен быть компактным и самодостаточным
- runtime не должен додумывать backend-логику поверх него
