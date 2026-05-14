# Спецификация `conflict resolution + owner semantics`

Это следующий слой после:
- `resolved_alignment_v2_contract`
- `phrase / compound candidate layer`
- `candidate generation`
- `scoring v2`

Его задача:
- из набора уже оценённых кандидатов выбрать не просто лучший link на unit, а лучший совместимый набор объяснений для всего сегмента
- зафиксировать, как работают:
  - `phrase owner`
  - `compound owner`
  - конкуренция `phrase / compound / word / grammar`
  - поглощение слабых внутренних кандидатов

Главная идея:
- хороший resolver выбирает не “лучший span сам по себе”
- а “наиболее правдоподобное общее объяснение того, как source-сегмент отразился в target”

---

## 1. Зачем нужен этот слой

Даже идеальный scoring не решает всё.

Проблема:
- несколько кандидатов могут иметь высокий score
- но быть несовместимыми друг с другом

Типичные конфликты:
- `bus driver -> водитель автобуса`
- и одновременно:
  - `bus -> автобуса`
  - `driver -> водитель`

Или:
- `wake up -> просыпается`
- и одновременно:
  - `wake -> просыпается`
  - `up -> просыпается`

Если просто брать top-1 per unit, всё ломается:
- дубли
- конкуренция за один и тот же target span
- UI начинает видеть несколько “истин” сразу

Поэтому нужен отдельный слой выбора победителей.

---

## 2. Главный принцип

Resolver должен выбирать:

- не лучший candidate для каждого unit отдельно
- а лучший совместимый набор кандидатов по сегменту

То есть он решает задачу:
- какие кандидаты оставить победителями
- какие понизить
- какие пометить как covered by owner
- какие отправить в `absorbed / rejected / omitted`

---

## 3. Что считается конфликтом

Нужно жёстко определить, какие ситуации считаются конфликтующими.

### A. Source overlap conflict

Два кандидата конфликтуют, если:
- покрывают один и тот же source index
- и при этом не находятся в разрешённом owner-отношении

Пример:
- `bus driver`
- `driver`

### B. Target overlap conflict

Два кандидата конфликтуют, если:
- претендуют на один и тот же target span или на пересекающиеся lexical target tokens
- и это не допустимый shared-owner case

Пример:
- `wake up -> просыпается`
- `wake -> просыпается`

### C. Semantic ownership conflict

Два кандидата конфликтуют, если:
- один объясняет более крупный смысловой блок
- второй пытается независимо присвоить его внутренний target без достаточной силы

Пример:
- `there is`
- `is`

### D. Grammar vs lexical conflict

Конфликт, если:
- слабый grammar/function candidate отъедает span у сильного lexical candidate

Пример:
- `the -> дверь`
- `door -> дверь`

---

## 4. Что такое owner semantics

Это ключевая часть слоя.

`owner` — это candidate/unit, который объясняет более крупный смысловой блок и может:
- побеждать внутренние слабые кандидаты
- поглощать их
- задавать главную интерпретацию target span

### Виды owner

- `phrase_owner`
- `compound_owner`

### Важно

Owner:
- не равен автоматической UI-склейке
- не обязан убирать внутренние слова из source
- он только говорит, что главное alignment-объяснение идёт через более крупную единицу

---

## 5. Phrase owner semantics

Для `phrase` owner правило должно быть жёстким.

### Если phrase candidate победил

Тогда:
- внутренние word-кандидаты не должны независимо получать тот же target span
- внутренние служебные элементы могут стать:
  - `absorbed`
  - `covered_by_owner`
  - `rejected`, если отдельный match не нужен

### Пример

`wake up -> просыпается`

Если phrase-owner победил:
- `wake -> просыпается` как отдельный main winner не нужен
- `up -> просыпается` как отдельный main winner не нужен

Phrase-owner должен считаться основной truth-интерпретацией.

---

## 6. Compound owner semantics

Для `compound` owner правило мягче.

### Если compound candidate победил

Тогда возможны два режима:

**A. Strong owner mode**
- compound считается главным объяснением
- внутренние кандидаты ослабляются
- внутренние слова могут быть:
  - `covered_by_owner`
  - или получить отдельные links только если они действительно сильные и не ломают картину

**B. Soft owner mode**
- compound фиксируется как лучшая high-level интерпретация
- но отдельные word-links допустимы, если:
  - они clean
  - не конфликтуют
  - полезны для UI/detail/debug

### Для LEXO правильнее начать с `soft owner mode`

Потому что:
- `bus driver` полезно видеть как compound explanation
- но `bus -> автобуса` и `driver -> водитель` тоже могут быть педагогически полезны

---

## 7. Иерархия приоритетов

При конфликте должны действовать жёсткие приоритеты.

### Базовая иерархия

1. `phrase owner`
2. `compound owner`
3. сильный `word`
4. слабый `word`
5. `grammar`
6. forced function-span candidates

### Дополнительные tie-breakers

Если тип одинаковый, сильнее тот, у кого:
1. выше `final_score`
2. cleaner span
3. сильнее `dictionary + grammar + context`
4. меньше noise в target span
5. выше structural plausibility

---

## 8. Разрешённые overlap cases

Нельзя запрещать любой overlap без исключений.

### Разрешено

- phrase-owner overlap с внутренними словами, если внутренние слова не становятся main competing winners
- compound-owner overlap с внутренними словами в soft-owner режиме
- grammar absorbed рядом с lexical winner
- function word без собственного span при наличии owner

### Не разрешено

- два независимых lexical winners, которые присваивают один и тот же target lexical span
- слабый internal word winner, который ломает phrase-owner
- grammar/function candidate, который перебивает сильный lexical owner

---

## 9. Winner selection policy

На первом production-проходе не нужно heavy optimization.
Достаточно сделать хороший greedy selection с owner-aware правилами.

### Предлагаемый порядок

1. Отсортировать кандидаты по:
   - `final_score`
   - owner priority
   - type priority
   - span cleanliness
2. Идти сверху вниз
3. Для каждого кандидата проверять:
   - конфликт по source
   - конфликт по target
   - owner-совместимость
   - grammar/lexical safety
4. Если кандидат совместим:
   - принять
5. Если конфликтует:
   - либо отклонить
   - либо пометить как `covered_by_owner`
   - либо оставить только как debug-side candidate

---

## 10. Что делать с внутренними unit-ами после победы owner-а

Это надо определить отдельно, иначе потом всё снова расползётся.

### Для `phrase owner`

Внутренние unit-ы:
- не должны получать тот же main span как независимый winner
- могут стать:
  - `absorbed`
  - `covered_by_owner`
  - `rejected`

### Для `compound owner`

Внутренние unit-ы:
- могут остаться с отдельными links, если они clean
- если отдельные links слабые, owner их поглощает
- если отдельные links сильные и не конфликтуют, можно сохранять обе интерпретации:
  - compound как high-level explanation
  - word links как local detail

---

## 11. Нужен ли отдельный статус `covered_by_owner`

Это отдельная архитектурная точка.

### Вариант A: не вводить новый status

Тогда owner relation хранить только в `meta`:
- `owner_unit_id`
- `owner_mode`

А внутренние unit-ы оставлять как:
- `absorbed`
- `rejected`
- или aligned independently

### Вариант B: ввести `covered_by_owner`

Это чище логически, но расширяет status model.

Для `v2` я бы рекомендовал:
- не вводить пока новый public status
- хранить owner coverage в `meta`
- чтобы не раздувать контракт раньше времени

---

## 12. Когда candidate должен быть отклонён даже при хорошем score

Нужно явно записать hard-ish rejection rules.

Кандидат должен проигрывать, если:
- конфликтует с более сильным phrase-owner
- конфликтует с более сильным compound-owner
- пересекает lexical span более сильного winner без достаточного основания
- grammar candidate отъедает lexical target
- candidate создаёт duplicate explanation без новой пользы

То есть высокий score сам по себе ещё не гарантирует победу.

---

## 13. Что делать с `absorbed` и `omitted`

Эти статусы тоже участвуют в итоговом выборе.

### `absorbed`

Должен побеждать, если:
- отдельный span для unit-а слабый или ложный
- но grammar logic подтверждает, что unit встроен в структуру перевода

### `omitted`

Должен побеждать, если:
- unit не объясняется отдельным span
- не выглядит absorbed
- но отсутствие отдельного выражения в переводе plausibly объяснимо

### `rejected`

Использовать, если:
- resolver не уверен
- лучше не утверждать ничего

---

## 14. Compound vs word competition

Это один из самых важных практических кейсов.

### Пример

`bus driver -> водитель автобуса`

Возможные кандидаты:
- compound owner `[0,1]`
- `bus -> автобуса`
- `driver -> водитель`

### Правило

Если compound owner:
- имеет высокий score
- даёт cleaner total explanation
- лучше согласован по dictionary/context

то он должен считаться главным explanation-кандидатом.

Но для `LEXO` word-links можно оставить как secondary usable detail, если:
- они не шумные
- не contradict compound owner
- полезны для tap UX

---

## 15. Phrase vs word competition

Здесь правило должно быть строже, чем у compound.

### Пример

`wake up -> просыпается`

Если phrase-owner сильный:
- `wake`
- `up`

не должны конкурировать с ним как равноправные winners.

Потому что здесь phrase — это реально более правильная смысловая единица, а не просто optional hypothesis.

---

## 16. Grammar conflict rules

Нужно явно записать:

### Grammar candidate проигрывает, если

- претендует на lexical target span content-word победителя
- не имеет сильной function evidence
- мешает phrase-owner или strong lexical winner

### Grammar candidate выигрывает, если

- идёт в `absorbed`
- либо получает очень чистый function-token span без ущерба lexical structure

---

## 17. Что сохранять в meta после разрешения конфликта

После итогового выбора у победителей и зависимых unit-ов должно сохраняться:

- `owner_unit_id`
- `owner_mode`
- `resolution_role`
- `suppressed_candidates_count`
- `selection_reason`

Примеры:
- `owner_mode = "always_phrase"`
- `owner_mode = "optional_compound"`
- `resolution_role = "primary_owner"`
- `resolution_role = "independent_word"`
- `resolution_role = "absorbed_after_owner_win"`

Это сильно поможет в debug и detail sheet.

---

## 18. Canonical conflict examples

### Example 1

`wake up -> просыпается`

Побеждает:
- `wake up` as phrase owner

Подавляется:
- `wake -> просыпается`
- `up -> просыпается`

### Example 2

`bus driver -> водитель автобуса`

Побеждает:
- compound-owner как high-level explanation

Допустимо сохранить:
- `bus -> автобуса`
- `driver -> водитель`

Только если это soft-owner mode и нет structural noise.

### Example 3

`the door -> дверь`

Побеждает:
- `door -> дверь`
- `the -> absorbed`

Не должно быть:
- `the -> дверь`

### Example 4

`there is -> есть`

Побеждает:
- phrase-owner `there is`

Подавляется:
- отдельный слабый `there`
- отдельный слабый `is`, если они просто дублируют owner

---

## 19. Что должно стать результатом Шага 5

После этой спеки должны быть готовы:

1. Определение конфликтов
2. Owner semantics для `phrase` и `compound`
3. Иерархия приоритетов
4. Разрешённые и запрещённые overlap cases
5. Winner selection policy
6. Правила подавления внутренних кандидатов
7. Meta fields для resolution outcome
8. Canonical conflict examples

---

## 20. Что будет следующим шагом после этой спеки

После этого логично фиксировать:
- `status resolution + final payload semantics spec`
или
- `runtime / UI resolved-layer integration spec`

Потому что после winner-selection уже нужно определить:
- как именно итог превращается в final persisted `units[]`
- что считается `absorbed`, `omitted`, `rejected`
- как runtime это читает без самодельной доинтерпретации

---

## 21. Практический вывод

Шаг 5 должен зафиксировать 6 главных вещей:

- resolver выбирает совместимый набор winners, а не top-1 per unit
- `phrase owner` должен быть жёстким главным объяснением
- `compound owner` должен быть мягче и работать как high-level explanation
- grammar не должен отъедать lexical spans
- overlap разрешается только в owner-aware режимах
- высокий score без compatibility не гарантирует победу
