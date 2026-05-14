# Полный план реализации resolver-контура alignment для LEXO

Ниже полный план реализации того resolver-контура, к которому мы пришли, с разделением на: что уже есть, что осталось доделать, в каком порядке это делать и какой должен быть конечный результат.

**Главная цель**
Сделать в LEXO стабильный `pedagogical alignment`-контур, где:

- `Marian` отвечает только за перевод сегмента
- `SimAlign` даёт сырой alignment signal
- resolver строит итоговое `unit -> meaning span`
- runtime/UI читают уже resolved-слой, а не пытаются сами додумывать mapping из raw links

Это не “идеальный академический aligner”, а production-пайплайн под tap UX:
- объяснимый
- дебажимый
- phrase-aware
- fail-closed
- без вранья в ambiguous кейсах

---

**1. Что уже сделано**

**1.1. Базовый каркас**
Уже есть:
- persisted resolved contract
- отдельные модули:
  - `alignment_contract`
  - `alignment_units`
  - `alignment_features`
  - `alignment_resolver`
- таблица `segment_resolved_alignments`
- rebuild-path
- `resolved-first` runtime с fallback на raw `SimAlign`

То есть инфраструктурно новый слой уже существует.

**1.2. Базовый scoring**
Уже есть сигналы:
- `simalign_score`
- `dictionary_score`
- `position_score`
- `grammar_score`
- `phrase_score`

И уже есть итоговая формула с понятными весами.

**1.3. Базовая статусная логика**
Уже есть:
- `aligned`
- `absorbed`
- `rejected`

Но это ещё не полный целевой контракт.

---

**2. Что осталось закончить по сути**

Осталось не “сделать resolver с нуля”, а довести текущий `v1` до полноценного `v2-ready resolver`.

Нужно закрыть 7 больших блоков:

1. Нормализовать входной контракт resolver-а  
2. Усилить `unit building` и phrase-candidate слой  
3. Расширить candidate generation  
4. Расширить scoring  
5. Усилить conflict resolution  
6. Довести status model и persisted JSON  
7. Перевести runtime/UI на настоящий unit-native resolved layer

---

**3. Целевой конечный контракт**

Resolver на выходе должен стабильно сохранять примерно такой тип результата:

```json
{
  "segment_id": "seg_123",
  "resolver_version": "v2",
  "units": [
    {
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
      "meta": {
        "pattern": "noun_noun",
        "owner_mode": "optional_compound"
      }
    },
    {
      "source_text": "the",
      "source_start": 0,
      "source_end": 0,
      "target_text": null,
      "target_start": -1,
      "target_end": -1,
      "type": "grammar",
      "status": "absorbed",
      "confidence": 0.93,
      "signals": {
        "grammar": 1.0
      }
    }
  ]
}
```

Важно:
- `type` и `status` не должны смешиваться
- compound/phrase/grammar/word — это тип unit-а
- `aligned/absorbed/omitted/rejected/...` — это статус результата

---

**4. Полный план реализации**

## Этап A. Зафиксировать целевую модель данных

**Что сделать**
Прежде чем усиливать логику, нужно один раз жёстко утвердить data contract.

Нужно определить:

**Типы unit-ов**
- `word`
- `grammar`
- `phrase`
- `compound`
- опционально позже `meta`

Рекомендуемое правило:
- `phrase` — неделимые смысловые или грамматические блоки
- `compound` — составной кандидат, который может жить как owner-кандидат, но не обязан склеивать UI
- `word` — обычное лексическое слово
- `grammar` — служебное/грамматическое слово или grammar-unit

**Статусы**
- `aligned`
- `absorbed`
- `omitted`
- `rejected`
- опционально позже `fuzzy`

**Дополнительные поля**
- `signals`
- `confidence`
- `meta`
- `resolver_version`

**Что это даст**
После этого весь backend будет двигаться в одном контракте, без путаницы:
- что такое phrase
- что такое compound
- что такое status
- что такое UI-owner

**Результат этапа**
Чёткая спецификация `resolved_alignment_v2_contract`.

---

## Этап B. Нормализовать вход resolver-а

Сейчас resolver получает слишком бедный набор данных. Его нужно привести к нормальной структуре входа.

**Что resolver должен получать на вход**
- `segment_id`
- `source_text`
- `target_text`
- `source_words[]`
- `target_tokens[]`
- `raw_simalign_links[]`
- `source_pos/lemma`
- `target_pos/lemma/classes`
- `dictionary_candidates`
- `phrase_candidates`
- `resolver_context`

**Что реально нужно добавить**
1. `target token classes`
Сейчас RU grammar определяется грубо внутри feature scorer. Это нужно вынести в отдельный подготовительный слой:
- `function`
- `pronoun`
- `nounish`
- `verbish`
- `adjish`
- `number`
- `punct`

2. `phrase_candidates`
Нужен отдельный builder, а не только встроенные 2-word эвристики.

3. `resolver_context`
Минимум:
- длина сегмента
- относительные позиции
- соседние source unit-ы
- соседние target токены
- target coverage around candidate

**Что это даст**
Resolver начнёт работать не как “голая функция над raw links”, а как нормальный decision layer.

---

## Этап C. Переписать unit-building в 2 уровня

Это один из самых важных этапов.

Нужно разделить:
- канонические source unit-ы
- дополнительные compound/phrase hypotheses для alignment

### C1. Канонические source unit-ы

Это то, что живёт в source как учебная сущность.

Нужно строить:
- single lexical words
- grammar words
- always-phrase units
- optional-compound units

### C2. Классификация unit-типов

**Always phrase**
Сюда включать:
- phrasal verbs
  - `wake up`
  - `pick up`
  - `look out`
- grammar phrases
  - `there is`
  - `have to`
  - `going to`
- fixed expressions
  - `of course`
  - `good morning`

Для них правило:
- по умолчанию это единый unit-кандидат
- resolver должен считать их приоритетными

**Optional compound candidate**
Сюда включать:
- `bus driver`
- `school bus`
- `front door`
- `coffee cup`
- `kitchen window`

Для них правило:
- отдельные слова сохраняются
- плюс строится compound-hypothesis
- resolver сам выбирает, нужна compound-интерпретация или достаточно отдельных links

**Never merge**
Сюда не строить compound unit-ы:
- случайные соседние content words без паттерна
- любые пары только по позиции без морфологического основания

### C3. Что именно надо реализовать

Нужен отдельный builder:
- `build_source_alignment_units(...)`
- `build_phrase_candidates(...)`
- `build_compound_candidates(...)`

С хорошей классификацией по:
- POS
- lemma
- pattern
- stopword/function filters

**Что это даст**
Мы перестанем путать:
- phrase как обязательный смысловой блок
- compound как полезную гипотезу для alignment

И это ровно то, к чему мы пришли в обсуждении.

---

## Этап D. Сделать нормальный candidate generation

Сейчас candidate spans строятся слишком узко и грубо. Это нужно усилить.

**Для каждого source unit нужно строить набор target span-кандидатов из нескольких источников**

### D1. Raw SimAlign span
Базовый кандидат:
- span по минимальному/максимальному target index из raw links

### D2. Expanded local spans
Вокруг raw span строить несколько локальных вариантов:
- same span
- left-shifted
- right-shifted
- contracted
- expanded by 1 token
- expanded by 2 tokens только если это phrase/compound

### D3. Dictionary-driven spans
Если dictionary candidates знают явный multi-token RU вариант:
- искать его как span в `target_tokens`
- добавлять как candidate даже если raw `SimAlign` не дал идеальную границу

### D4. Phrase-owner spans
Если unit — `phrase` или `compound`, строить owner span-кандидаты даже если внутренние слова конфликтуют по raw links.

### D5. Grammar-specific candidates
Для grammar/function unit-ов:
- отдельные target spans не навязывать
- primary candidate часто должен быть именно `absorbed`
- secondary кандидат — minimal function-word span, только если он очень чистый

**Что это даст**
Resolver начнёт реально выбирать между гипотезами, а не только “чуть подвигать raw SimAlign”.

---

## Этап E. Расширить scoring до полноценного рабочего набора

Сейчас scoring хороший как `v1`, но до целевого состояния нужно добавить ещё сигналы.

### E1. Оставить текущие сигналы
Оставляем:
- `simalign_score`
- `dictionary_score`
- `position_score`
- `grammar_score`
- `phrase_score`

### E2. Добавить `context_score`
Это один из главных недостающих сигналов.

Он должен учитывать:
- поддерживают ли соседние пары этот match
- не делает ли кандидат сегмент структурно странным
- не ломает ли owner-link локальное распределение смысла

Пример:
- если `breakfast -> завтрак` уже сильный
- тогда `made -> приготовил` усиливается

### E3. Добавить `span_shape_score`
Это важный технический сигнал:
- короткий чистый span лучше длинного шумного
- span без лишних function words лучше грязного span-а
- exact boundary лучше размазанного диапазона

Его можно либо хранить отдельно, либо включить в `context/phrase` блок.

### E4. Усилить `dictionary_score`
Сейчас словарь используется довольно плоско. Нужно различать:
- exact phrase match
- exact lemma match
- token-subset match
- weak partial match
- phrasal dictionary support
- no support

### E5. Усилить `grammar_score`
Нужно:
- явное сравнение source class ↔ target class
- отдельные правила для:
  - verbish
  - nounish
  - adjish
  - function
  - pronoun
  - number

### E6. Опционально добавить `frequency_score`
Не обязательно сразу.
Но позже полезно:
- частые переводы сильнее редких
- например `make -> делать` обычно сильнее экзотических вариантов

**Итоговая рекомендуемая формула**
Для `v2`:

```text
final =
  0.30 * simalign_score +
  0.23 * dictionary_score +
  0.12 * position_score +
  0.15 * grammar_score +
  0.10 * phrase_score +
  0.10 * context_score
```

Потом уже можно подвинуть после тестов.

**Что это даст**
Система станет не просто “поддержанной SimAlign”, а реально multi-signal resolver-ом.

---

## Этап F. Усилить conflict resolution

Сейчас greedy подходит для `v1`, но для более идеального результата нужно сделать его умнее.

### F1. Явный ranking policy
При конфликте должны действовать такие приоритеты:

1. `phrase` сильнее `compound`
2. `compound` сильнее `word`
3. `word` сильнее `grammar`
4. lexical сильнее function
5. короткий clean span сильнее длинного noisy span
6. высокий `dictionary + grammar + simalign + context` сильнее голого `simalign`
7. owner-unit может поглощать слабые внутренние unit-кандидаты

### F2. Owner logic
Нужно ввести логику owner-кандидатов:
- phrase owner
- compound owner

Это не обязательно значит склейку UI.
Это значит:
- resolver может выбрать составное объяснение
- внутренние слова получают либо свои links, либо special status/meta, что они покрыты owner-ом

### F3. Совместимость набора
Resolver должен выбирать не просто лучший candidate per unit, а лучший совместимый набор:
- без конфликта target span-ов, если это не разрешено явно
- без нелепой конкуренции function word vs content word
- без дублей одного и того же смыслового span-а у нескольких слабых unit-ов

### F4. Не переходить пока на heavy optimization
Пока не нужно:
- Hungarian
- CRF
- optimal transport

Правильный путь:
- сначала сделать хороший greedy + owner policy + compatibility rules
- только потом смотреть, остались ли системные провалы

**Что это даст**
Именно тут резко вырастет стабильность на реальных книгах.

---

## Этап G. Довести status model

Это обязательный этап.

Нужно перестать использовать слишком грубую схему.

**Целевые статусы**
- `aligned`
- `absorbed`
- `omitted`
- `rejected`
- позже опционально `fuzzy`

### G1. Что они значат

**aligned**
- найден валидный target span

**absorbed**
- unit не имеет собственного target span
- но его смысл встроен в грамматику / owner / morphology

**omitted**
- source unit по смыслу отсутствует в target
- это не обязательно ошибка runtime, это может быть реальный переводческий пропуск или compression

**rejected**
- candidate matching не прошёл
- resolver не готов утверждать ложную связь

**fuzzy**
- только если позже захотите мягкий UI-режим

### G2. Type и status должны быть независимы
Например:
- `type=compound`, `status=aligned`
- `type=grammar`, `status=absorbed`
- `type=word`, `status=rejected`

Это принципиально.

**Что это даст**
UI и debug начнут понимать не только “есть перевод или нет”, а что именно случилось.

---

## Этап H. Расширить persisted JSON

После смены логики нужно немного расширить persisted payload.

### H1. Добавить `meta`
Например:
- `pattern`
- `owner_mode`
- `owner_unit_id`
- `candidate_source`
- `resolution_notes`

### H2. Сохранять полный `signals`
Это уже частично есть. Нужно сохранить как основу дебага.

### H3. Сохранять `resolver_version`
Обязательно при каждом значимом изменении логики:
- `v1`
- `v1.1`
- `v1.2`
- `v2`

### H4. Не ломать совместимость
Новые поля добавлять мягко:
- старые payload-ы продолжают читаться
- runtime умеет работать и с более старым resolved JSON

**Что это даст**
Можно будет сравнивать качество resolver-а между версиями на одних и тех же книгах.

---

## Этап I. Сделать нормальный evaluation loop

Без этого всё остальное легко уйдёт в иллюзию качества.

### I1. Собрать golden sample
Нужен небольшой эталонный набор сегментов из 3 книг:
- хорошие простые предложения
- phrasal verbs
- noun compounds
- grammar words
- reorder cases
- absorbed cases
- hard ambiguous cases

### I2. Сравнивать по версиям resolver-а
Для каждого сегмента проверять:
- какие unit-ы получили `aligned`
- где появились ложные span-ы
- где phrase/compound owner помог
- где function words начали врать
- где `rejected` стал лучше честного ложного match-а

### I3. Метрики
Нужны хотя бы продуктовые:
- `% meaningful aligned lexical units`
- `% false positive alignments`
- `% phrase/compound improvements`
- `% absorbed correctness`
- `% rejected but acceptable`
- `% regressions vs previous resolver_version`

### I4. Сравнение не только “больше переводов”
Важно смотреть не:
- сколько слов получили span вообще

А:
- сколько слов получили правильный pedagogical result

**Что это даст**
Resolver перестанет эволюционировать вслепую.

---

## Этап J. Перевести runtime/UI на unit-native модель

Это последний большой продуктовый этап.

Сейчас runtime ещё заметно word-oriented. Это нужно постепенно менять.

### J1. Runtime должен читать resolved units как primary objects
Не “слово получило span”, а:
- unit есть
- у unit есть статус
- у unit есть target coverage
- у unit есть owner/meta

### J2. UI не должен требовать перевода для каждого слова
Если unit:
- `absorbed`
- `omitted`
- `rejected`

UI должен отрабатывать это честно:
- не подсовывать фальшивый span
- не склеивать лишнего
- не ломать tap payload

### J3. Compound-owner logic
Для optional compounds:
- UI может оставить отдельные tap-слова
- но detail sheet должен уметь показать, что есть compound-owner interpretation

То есть:
- `bus`
- `driver`

могут жить отдельно визуально,
но detail/debug должен уметь объяснить, что resolver также видит `bus driver -> водитель автобуса`.

### J4. Phrase-owner logic
Для always-phrase:
- если это реально единый блок, UI может использовать owner как primary pedagogical object

Но это уже продуктовая настройка, а не обязательное поведение на первом этапе.

**Что это даст**
Новый resolver станет реальным источником истины для tap UX.

---

**5. Рекомендуемый порядок внедрения**

Правильный порядок такой:

### Фаза 1. Контракт и unit logic
1. Зафиксировать `type/status/meta` contract
2. Разделить `always phrase` и `optional compound`
3. Вынести phrase/compound candidate building в отдельный слой

### Фаза 2. Resolver quality
4. Расширить candidate generation
5. Добавить `context_score`
6. Усилить `dictionary_score`
7. Усилить `grammar_score`
8. Добавить owner/conflict policy

### Фаза 3. Persist + debug
9. Расширить persisted JSON
10. Версионировать resolver
11. Собрать golden sample и evaluation loop

### Фаза 4. Runtime/UI
12. Перевести runtime на unit-native semantics
13. Довести tap/detail-sheet под statuses и owner logic
14. Оставить raw `SimAlign` только как fallback/debug

---

**6. Что даст максимальный прирост качества в первую очередь**

Если делать не всё сразу, а по наибольшему эффекту, то приоритет такой:

1. `phrase / compound candidate layer`
2. `context-aware scoring`
3. `better conflict resolution`
4. `full status model`
5. `unit-native runtime`

Именно это даст максимальный прирост качества tap UX.

---

**7. Что не нужно делать**

Не нужно:
- делать `LLM alignment`
- заменять `SimAlign`
- строить giant linguistic engine
- сразу внедрять тяжёлую глобальную оптимизацию
- смешивать runtime с raw `SimAlign` как с продуктовой истиной
- жёстко склеивать все noun compounds в один UI-unit

---

**8. Что именно осталось закончить коротко**

Если сжать всё в одну практическую формулировку, то осталось:

- доделать сильный `phrase/compound hypothesis layer`
- расширить scoring до `context-aware resolver`
- добавить owner/conflict semantics
- довести полный `type/status` contract
- сделать resolved слой действительно первичным для runtime/UI
- собрать нормальный цикл сравнения версий resolver-а на живых книгах

---

**9. Итог**

Инфраструктура уже сделана. Остался не “каркас”, а качество логики.

То есть проект уже на этапе:
- не “нужно изобрести resolver”
- а “нужно довести существующий resolver до production-grade pedagogical quality”

Если хотите, следующим сообщением я могу превратить этот план в ещё более прикладной инженерный roadmap по шагам вида:

- `Шаг 1`
- `Файлы`
- `Что меняем`
- `Как проверяем`
- `Риск`
- `Критерий готовности`

То есть уже как прямой implementation-plan для работы по задачам.
