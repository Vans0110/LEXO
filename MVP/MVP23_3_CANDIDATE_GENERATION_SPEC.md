# Спецификация `candidate generation`

Это следующий слой после:
- `resolved_alignment_v2_contract`
- `phrase / compound candidate layer`

Его задача:
- для каждого source unit / hypothesis построить не один span, а набор разумных `target span candidates`
- чтобы resolver выбирал лучшее объяснение, а не blindly брал raw `SimAlign`

---

## 1. Зачем нужен этот слой

Если candidate generation слабый, дальше уже бесполезно улучшать scoring.

Потому что resolver не может выбрать хороший вариант, если ему его вообще не предложили.

Типичная ошибка плохого aligner-а:
- взять только `raw SimAlign min/max span`
- и пытаться оценить только его

Проблема:
- границы часто грязные
- function tokens размазывают span
- phrase/compound часто требуют span шире или уже raw-сигнала
- dictionary может знать лучший multi-token target, которого нет в raw-boundary

Поэтому нужен отдельный слой генерации гипотез.

---

## 2. Главный принцип

Для каждого source unit нужно строить малый, контролируемый набор target-кандидатов из нескольких источников:

1. `raw_simalign_span`
2. `local_variants`
3. `dictionary_span`
4. `owner_span`
5. `absorbed_candidate`
6. позже опционально `contextual_span`

Это не exhaustive search по всем токенам.
Это именно узкий shortlist.

---

## 3. Что является входом слоя

Candidate generator должен получать:

- `segment_id`
- `source_text`
- `target_text`
- `source_units`
- `target_tokens`
- `raw_links`
- `dictionary_candidates`
- `target_token_classes`
- phrase/compound metadata

Минимум этого достаточно.

---

## 4. Что является выходом слоя

Для каждого source unit должен возвращаться список candidate-объектов.

Пример:

```json
{
  "unit_id": "seg_123:u_4",
  "candidates": [
    {
      "candidate_id": "seg_123:u_4:c_1",
      "target_start": 0,
      "target_end": 1,
      "target_text": "водитель автобуса",
      "candidate_kind": "raw_simalign_span",
      "priority": 100,
      "meta": {}
    },
    {
      "candidate_id": "seg_123:u_4:c_2",
      "target_start": 0,
      "target_end": 0,
      "target_text": "водитель",
      "candidate_kind": "contracted_local_span",
      "priority": 70,
      "meta": {}
    }
  ]
}
```

---

## 5. Основные candidate kinds

Нужно заранее зафиксировать ограниченный список типов кандидатов.

### `raw_simalign_span`

Базовый span по raw links.

### `contracted_local_span`

Локально сжатый span вокруг raw области.

### `expanded_local_span`

Локально расширенный span вокруг raw области.

### `shifted_local_span`

Локально сдвинутый влево или вправо span.

### `dictionary_span`

Span, найденный по dictionary candidate в target tokens.

### `owner_span`

Span, построенный для phrase/compound owner-кандидата.

### `absorbed_candidate`

Специальный кандидат без target span.

### `omitted_candidate`

Позже, если понадобится отдельное различение.

---

## 6. Базовый raw span

Это первый и обязательный кандидат.

### Правило

Если у unit есть raw links:
- собрать все target indexes, связанные с source range unit-а
- взять:
  - `raw_start = min(indexes)`
  - `raw_end = max(indexes)`

Создать candidate:
- `candidate_kind = raw_simalign_span`

### Зачем

Это основной anchor-кандидат.
Но не обязательно финальный победитель.

---

## 7. Local variants

Это вторая обязательная часть.

Raw span редко идеален, поэтому вокруг него надо строить несколько аккуратных вариантов.

### Какие варианты строить

Если есть raw span `[start, end]`:

**Contracted**
- `[start, end-1]`
- `[start+1, end]`
- если span длиной > 1

**Expanded**
- `[start-1, end]`
- `[start, end+1]`
- `[start-1, end+1]`

**Shifted**
- `[start-1, end-1]`
- `[start+1, end+1]`

Все варианты:
- только в границах `target_tokens`
- только если длина не выходит за разумный лимит

### Ограничения

Для обычных `word` unit-ов:
- не строить слишком много
- максимум длина 3

Для `phrase/compound`:
- можно допускать до длины 4 или 5, если сегмент короткий

---

## 8. Dictionary-driven spans

Это очень важный недостающий слой.

Если dictionary layer знает кандидата:
- `водитель автобуса`
- `просыпаться`
- `должен`

то generator должен попытаться найти такой текст в `target_tokens`.

### Как искать

Нужно искать:
- exact contiguous token match
- normalized match
- later optional lemma-aware match

### Пример

Source unit:
- `bus driver`

Dictionary candidates:
- `водитель автобуса`

Target tokens:
- `["Водитель", "автобуса", "открыл", "дверь"]`

Generator должен добавить:
- `[0,1]` как `dictionary_span`

Даже если raw SimAlign дал шумный span.

### Зачем

Так resolver получает шанс выбрать cleaner target span.

---

## 9. Owner spans для phrase/compound

Для `phrase` и `compound` нужно строить специальные owner-кандидаты.

### Когда

Если unit имеет:
- `type=phrase`
- или `type=compound`

### Что делать

Даже если внутренние raw links слов конфликтуют, нужно пытаться строить:
- объединённый owner span
- очищенный contiguous span вокруг связанной target-области

### Пример

`wake up`
Raw links могут дать:
- `wake -> просыпается`
- `up -> просыпается`

Нужен единый owner-кандидат:
- `wake up -> просыпается`

### Пример 2

`bus driver`
Raw links:
- `bus -> автобуса`
- `driver -> водитель`

Owner-кандидат:
- `bus driver -> водитель автобуса`

---

## 10. Special logic для grammar/function units

Для `grammar` unit-ов логика должна быть другой.

### Главное правило

Для grammar/function unit:
- primary candidate часто должен быть не span, а `absorbed_candidate`

### Почему

Потому что forcing span для:
- `the`
- `to`
- `is`

часто порождает ложь.

### Что можно допустить

Только как secondary candidate:
- маленький чистый function-word span
- если он действительно очень хорошо подтверждён

### Пример

`the`
Обычно:
- `absorbed_candidate` priority выше
- маленький span-кандидат только как слабая альтернатива

---

## 11. Candidate limits

Это важный технический момент.

Нельзя генерировать слишком много гипотез.
Иначе resolver начнёт шуметь и тормозить.

### Рекомендуемый лимит

Для `word`:
- 1 raw
- 3–5 local
- 0–2 dictionary
- 1 absorbed only if grammar-like edge case

Итого:
- максимум около 6–8 кандидатов

Для `phrase/compound`:
- 1 raw owner
- 4–6 local
- 1–3 dictionary
- 1 owner-specific expanded span

Итого:
- максимум около 8–10 кандидатов

Для `grammar`:
- 1 absorbed
- 0–2 tiny span candidates

---

## 12. Priority policy на этапе generation

Это не финальный score.
Это только initial ordering.

Рекомендуемые базовые priorities:

- `raw_simalign_span` = 100
- `dictionary_span` = 95
- `owner_span` = 92
- `contracted_local_span` = 80
- `expanded_local_span` = 70
- `shifted_local_span` = 65
- `absorbed_candidate` = 90 для `grammar`, 20 для lexical
- `omitted_candidate` позже отдельно

Это не заменяет scoring.
Это просто задаёт правильный порядок shortlist-а.

---

## 13. Нормализация target_text

Для каждого candidate надо сразу сохранять:
- `target_start`
- `target_end`
- `target_text`

### Правила

Если candidate span реальный:
- `target_text` собирается как contiguous join по `target_tokens[start:end+1]`

Если это `absorbed_candidate`:
- `target_text = null`
- `target_start = -1`
- `target_end = -1`

---

## 14. Что нельзя делать

Нужно прямо зафиксировать запреты.

### Нельзя

- генерировать все возможные spans предложения
- строить длинные spans без raw/dictionary основания
- делать dictionary-only hallucinations без target evidence
- насильно давать span каждому grammar word
- склеивать compound только потому, что слова соседние

---

## 15. Инварианты candidate generation

- у каждого unit всегда есть хотя бы 1 кандидат
- если есть raw links, должен быть `raw_simalign_span`
- у `grammar` unit почти всегда должен быть `absorbed_candidate`
- `phrase` и `compound` могут иметь owner-кандидаты
- generator не должен создавать дубли одинакового `[start,end,candidate_kind]`
- все span-кандидаты должны быть contiguous

---

## 16. Canonical examples

### Example 1

`opened -> открыл`

Raw:
- `[2,2]`

Candidates:
- raw `[2,2]`
- expanded `[1,2]`
- expanded `[2,3]`
- shifted `[1,1]` only if valid

### Example 2

`bus driver -> водитель автобуса`

Raw links imply:
- target indexes `{0,1}`

Candidates:
- raw owner `[0,1]`
- contracted `[0,0]`
- contracted `[1,1]`
- dictionary `[0,1]`

### Example 3

`the`

Candidates:
- absorbed
- optional tiny span only if strong function evidence exists

### Example 4

`wake up -> просыпается`

Candidates:
- raw owner `[1,1]`
- expanded `[0,1]` if needed
- dictionary-based verbal span if available

---

## 17. Что должно стать результатом Шага 3

После этой подспеки должны быть готовы:

1. Список `candidate_kind`
2. Правила raw span extraction
3. Правила local variants
4. Правила dictionary span search
5. Правила owner span generation
6. Правила grammar absorbed-first generation
7. Candidate limits
8. Priority policy
9. Canonical examples

---

## 18. Что будет следующим шагом после этой спеки

После этого уже логично фиксировать:
- `scoring v2 spec`

Потому что теперь уже будет понятно:
- какие кандидаты существуют
- какие сигналы нужно считать для их сравнения

---

## 19. Практический вывод

Шаг 3 должен зафиксировать 5 главных вещей:

- resolver сравнивает не один raw span, а shortlist гипотез
- raw `SimAlign` — это anchor, но не истина
- dictionary должен уметь вбрасывать свои contiguous span-кандидаты
- `phrase/compound` должны иметь owner span logic
- `grammar` units должны быть `absorbed-first`, а не `force-span-first`
