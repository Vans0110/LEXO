# Спецификация `scoring v2`

Это следующий слой после:
- `resolved_alignment_v2_contract`
- `phrase / compound candidate layer`
- `candidate generation`

Его задача:
- для каждого `source unit -> target candidate span` посчитать набор стабильных сигналов
- объединить их в понятный `final_score`
- дать resolver-у основу для выбора лучшего объяснения сегмента

Главная идея:
- scoring не должен быть “магией”
- scoring не должен быть black box
- scoring должен быть дебажимым и объяснимым по каждому candidate

---

## 1. Зачем нужен этот слой

Candidate generation даёт shortlist гипотез.

Но без нормального scoring resolver не понимает:
- почему `bus driver -> водитель автобуса` лучше, чем `driver -> водитель`
- почему `the -> null` лучше, чем `the -> водитель`
- почему phrase-owner должен побеждать внутренние слабые word-links
- почему один noisy span надо отрезать, а другой принять

То есть scoring отвечает не за поиск кандидатов, а за ранжирование правдоподобия.

---

## 2. Главный принцип

Итоговый `final_score` должен быть суммой нескольких слабых, но понятных сигналов.

Базовая формула `v2`:

```text
final =
  0.30 * simalign_score +
  0.23 * dictionary_score +
  0.12 * position_score +
  0.15 * grammar_score +
  0.10 * phrase_score +
  0.10 * context_score
```

Это не догма.
Но это хороший рабочий старт:
- сильный вес у `SimAlign`
- сильный вес у словаря
- умеренный вес у grammar
- мягкий вес у position
- явная поддержка phrase/context

---

## 3. Какие сигналы входят в `v2`

Нужно зафиксировать 6 основных сигналов.

### 1. `simalign_score`

Оценивает:
- насколько candidate span согласован с raw `SimAlign`

### 2. `dictionary_score`

Оценивает:
- насколько dictionary layer поддерживает именно этот candidate span

### 3. `position_score`

Оценивает:
- насколько source unit и target candidate находятся в похожей относительной области сегмента

### 4. `grammar_score`

Оценивает:
- насколько source unit type/class совместим с target token classes

### 5. `phrase_score`

Оценивает:
- насколько candidate поддерживает phrase/compound interpretation

### 6. `context_score`

Оценивает:
- насколько candidate хорошо вписывается в окружающий локальный alignment-контекст

---

## 4. Общие правила для сигналов

Для всех сигналов нужно зафиксировать:

- диапазон: `0.0 .. 1.0`
- `1.0` = очень сильная поддержка
- `0.0` = отсутствует поддержка или явное несоответствие
- промежуточные значения допустимы
- отсутствие сигнала не должно ломать scoring

Важно:
- сигнал не равен “истине”
- сигнал равен силе данного признака

---

## 5. `simalign_score`

Это основной alignment-signal.

### Что он должен измерять

Насколько candidate span совпадает с тем, что реально показывают raw links для unit-а.

### Для `word`

Если raw links дают:
- точный single target token

и candidate совпадает с ним:
- `1.0`

Если candidate содержит этот token, но span шире:
- `0.6 .. 0.9`

Если candidate смещён и перекрытие слабое:
- `0.1 .. 0.5`

Если candidate не пересекается с raw evidence:
- `0.0`

### Для `phrase/compound`

Если candidate аккуратно покрывает объединённую target-область внутренних raw links:
- высокий score

Если candidate берёт только кусок phrase-owner span:
- средний

Если candidate ломает owner coverage:
- низкий

### Важно

`simalign_score` — это не embedding similarity в чистом виде.
Это именно:
- согласованность с уже существующим raw alignment evidence

---

## 6. `dictionary_score`

Это второй главный сигнал.

### Что он должен измерять

Насколько словарь поддерживает именно этот span, а не слово вообще.

### Градации поддержки

**1.0**
- exact phrase match
- candidate text совпадает с сильным dictionary candidate целиком

Пример:
- `bus driver -> водитель автобуса`

**0.9 - 0.95**
- exact lexical lemma-level match
- для одиночного `word`

Пример:
- `door -> дверь`

**0.75 - 0.85**
- strong token-subset match
- span содержит правильное ключевое слово, но не идеально

**0.5 - 0.7**
- weak partial support
- словарь знает один из элементов, но не весь span

**0.0**
- словарь не поддерживает candidate

### Важное правило

Если словарь пустой:
- это не должно автоматически убивать candidate
- просто `dictionary_score = 0.0`

---

## 7. `position_score`

Это мягкий structural prior.

### Что он должен измерять

Насколько source unit и target candidate находятся примерно в одной части сегмента.

### Как считать

Берутся относительные центры.

Для source:
- `source_center = (source_start + source_end) / 2`

Для target:
- `target_center = (target_start + target_end) / 2`

Нормализуем:
- `source_center / (source_len - 1)`
- `target_center / (target_len - 1)`

Дальше:
- `distance = abs(norm_source - norm_target)`

Простая формула:
- `position_score = max(0, 1 - distance)`

### Интерпретация

- очень близко по относительной позиции: `0.85 .. 1.0`
- умеренное смещение: `0.5 .. 0.8`
- сильный прыжок по сегменту: `0.0 .. 0.4`

### Важное правило

`position_score` не должен быть жёстким фильтром.
Это бонус, а не закон.

Потому что EN↔RU часто меняют порядок слов.

---

## 8. `grammar_score`

Это фильтр semantic nonsense.

### Что он должен измерять

Насколько source class совместим с target class.

### Source classes

- `verbish`
- `nounish`
- `adjish`
- `function`
- `pronoun`
- `number`

### Target classes

- `verbish`
- `nounish`
- `adjish`
- `function`
- `pronoun`
- `number`
- `unknown`

### Рекомендуемые правила

**Source = function**
- target empty with absorbed path: `1.0`
- target single function/pronoun token: `0.8 .. 1.0`
- target lexical noun/verb span: `0.0 .. 0.2`

**Source = verbish**
- target headed by verbish: `0.9 .. 1.0`
- target mixed verb+function span: `0.7 .. 0.9`
- target nounish span: `0.0 .. 0.3`

**Source = nounish**
- target nounish: `0.9 .. 1.0`
- target adj+noun or pronoun-ish nominal replacement: `0.6 .. 0.85`
- target verbish only: `0.0 .. 0.3`

**Source = adjish**
- target adjish: `0.9 .. 1.0`
- target nounish with adjectival role leakage: `0.4 .. 0.7`
- target verbish: `0.0 .. 0.2`

### Важное правило

`grammar_score` не должен притворяться полной морфологией RU.
В `v2` это ещё грубая, но полезная типовая совместимость.

---

## 9. `phrase_score`

Это сигнал поддержки составного объяснения.

### Что он должен измерять

Насколько candidate оправдан как:
- `phrase`
- `compound`
- owner-span

### Для `phrase`

Если candidate покрывает phrase unit целиком и clean:
- `1.0`

Если candidate дробит phrase и теряет её смысл:
- `0.0 .. 0.4`

### Для `compound`

Если candidate хорошо объясняет compound как единый target span:
- `0.7 .. 0.95`

Если candidate не даёт преимуществ по сравнению с отдельными словами:
- `0.2 .. 0.5`

### Для `word`

По умолчанию:
- `0.0`

### Важное правило

`phrase_score` не должен автоматически заставлять compound побеждать.
Он только даёт составной гипотезе шанс.

---

## 10. `context_score`

Это один из самых важных новых сигналов.

### Что он должен измерять

Насколько candidate хорошо вписывается в локальный alignment-контекст сегмента.

### Что может входить

- согласованность с соседними сильными кандидатами
- отсутствие структурного конфликта
- поддержка owner-отношения
- отсутствие “грязного захвата” чужих слов
- общая plausibility локального решения

### Пример

`He made breakfast.`  
`Он приготовил завтрак.`

Если:
- `breakfast -> завтрак` уже сильный
- тогда `made -> приготовил` усиливается

### Градации

- сильная контекстная поддержка: `0.8 .. 1.0`
- нейтральный контекст: `0.4 .. 0.6`
- контекст против: `0.0 .. 0.3`

### Важно

На первом проходе `context_score` может быть простым:
- без глобальной оптимизации
- только локальные соседние проверки

---

## 11. Что пока не входит в `v2`

Пока сознательно не включать в базовую формулу:

- `frequency_score`
- `alignment_prior` в стиле GIZA
- deep dependency score
- discourse-level score
- sentence-level semantic paraphrase score
- LLM confidence

Это можно добавить позже, но не в первый production-pass.

---

## 12. `confidence` vs `final_score`

Нужно заранее договориться:
- `confidence` и `final_score` могут быть равны в `v2`
- либо `confidence` может быть лёгкой пост-нормализацией `final_score`

Рекомендуемый простой вариант:
- пока `confidence = final_score`

Это упрощает дебаг.

Позже можно отдельно вводить:
- confidence calibration
- thresholds для UI режимов

---

## 13. Threshold policy

Нужно зафиксировать базовые пороги.

### Для `aligned`

Если:
- `final_score >= 0.55`
- candidate может считаться допустимым aligned-кандидатом

### Для strong aligned

Если:
- `final_score >= 0.80`
- это сильный надёжный match

### Для weak/noisy

Если:
- `0.35 <= final_score < 0.55`
- кандидат не должен автоматически становиться aligned
- может использоваться в отладке или как fallback later

### Для reject

Если:
- `final_score < 0.35`
- кандидат слишком слаб

### Для grammar absorbed

У grammar unit absorbed-path может жить по отдельному правилу:
- не требовать высокий lexical threshold
- если grammar logic поддерживает absorption, это валидно и без target span

---

## 14. Penalty rules

Нужно зафиксировать, что score не только растёт, но и штрафуется.

### Штрафовать надо:

- слишком длинный noisy span
- span, захватывающий лишние lexical tokens
- mismatch между source class и target head class
- candidate, который пересекает явный owner чужого phrase
- candidate без raw и без dictionary evidence
- candidate, который выглядит как forced alignment для grammar word

### Мягкий штраф, а не жёсткий запрет

Кроме совсем абсурдных случаев, лучше снижать score, а не сразу убивать candidate.

---

## 15. Type-aware scoring policy

Сигналы должны работать по-разному для разных unit types.

### Для `word`

Основные сигналы:
- `simalign`
- `dictionary`
- `position`
- `grammar`
- `context`

### Для `grammar`

Основные сигналы:
- `grammar`
- `absorbed logic`
- `position` минимально
- `dictionary` почти вторично
- `phrase/context` только если grammar unit часть larger structure

### Для `phrase`

Основные сигналы:
- `simalign`
- `phrase`
- `dictionary`
- `context`

### Для `compound`

Основные сигналы:
- `dictionary`
- `phrase`
- `context`
- `simalign` как aggregated owner evidence
- `position` как secondary bonus

---

## 16. Canonical scoring examples

### Example 1

`door -> дверь`

Пример сигналов:
- `simalign = 1.0`
- `dictionary = 0.95`
- `position = 0.95`
- `grammar = 1.0`
- `phrase = 0.0`
- `context = 0.8`

Итог:
- strong aligned

### Example 2

`the -> null`

Пример:
- lexical span signals не нужны
- grammar absorption supported

Интерпретация:
- valid `absorbed`
- confidence высокий по grammar-path

### Example 3

`bus driver -> водитель автобуса`

Пример:
- `simalign = 0.8`
- `dictionary = 1.0`
- `position = 0.85`
- `grammar = 1.0`
- `phrase = 0.9`
- `context = 0.85`

Итог:
- strong compound aligned

### Example 4

`opened -> собака`

Пример:
- `simalign = 0.2`
- `dictionary = 0.0`
- `position = 0.4`
- `grammar = 0.1`
- `phrase = 0.0`
- `context = 0.1`

Итог:
- reject

---

## 17. Что должно сохраняться в persisted JSON

Для победившего unit-result обязательно сохранять:
- `confidence`
- `signals`

Пример:

```json
"signals": {
  "simalign": 0.81,
  "dictionary": 0.92,
  "position": 0.88,
  "grammar": 1.0,
  "phrase": 1.0,
  "context": 0.84
},
"confidence": 0.89
```

Это важно, потому что без этого потом невозможно дебажить:
- почему победил именно этот span
- почему compound победил word
- почему grammar ушёл в absorbed

---

## 18. Что должно стать результатом Шага 4

После этой спеки должны быть готовы:

1. Список сигналов `v2`
2. Формула `final_score`
3. Правила расчёта каждого сигнала
4. Type-aware scoring policy
5. Threshold policy
6. Penalty rules
7. Canonical examples
8. Правило `confidence = final_score` для `v2`

---

## 19. Что будет следующим шагом после этой спеки

После этого логично фиксировать:
- `conflict resolution + owner semantics spec`

Потому что после scoring уже нужно определять:
- как из ranked candidates выбирать совместимый набор победителей
- как owner побеждает внутренние слабые кандидаты
- как phrase/compound конкурируют с одиночными словами

---

## 20. Практический вывод

Шаг 4 должен зафиксировать 6 главных вещей:

- scoring — это сумма сигналов, а не одно правило
- `SimAlign` важен, но не абсолютен
- словарь должен серьёзно влиять на выбор
- grammar должен фильтровать бессмысленные matches
- phrase/compound должны получать отдельную поддержку
- `context_score` нужен, чтобы resolver перестал быть “локально слепым”
