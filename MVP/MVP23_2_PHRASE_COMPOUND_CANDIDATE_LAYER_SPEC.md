# Спецификация `phrase / compound candidate layer`

Это следующий обязательный слой после `resolved_alignment_v2_contract`.
Его задача: определить, какие source-блоки resolver вообще имеет право рассматривать как составные кандидаты, и как отличать:

- обязательный `phrase`
- опциональный `compound`
- обычные одиночные `word`
- случаи, которые вообще нельзя склеивать

---

## 1. Зачем нужен этот слой

Если resolver получает только одиночные слова, он системно проигрывает в случаях:

- `wake up`
- `look out`
- `have to`
- `there is`
- `bus driver`
- `front door`

Если же склеивать всё подряд, он начинает врать и ломать UI.

Поэтому нужен отдельный слой, который строит controlled candidate hypotheses:
- не всё сливать
- не всё дробить
- давать resolver-у только осмысленные составные варианты

---

## 2. Главный принцип

Нужно разделить 3 класса source-кандидатов:

### `always_phrase`

Это неделимый смысловой или грамматический блок.
Если такой паттерн найден, resolver обязан рассматривать его как сильный составной unit.

### `optional_compound`

Это составная гипотеза, полезная для alignment.
Но она не обязана побеждать и не обязана становиться единым UI-unit.

### `never_merge`

Это соседние слова, которые нельзя объединять только потому, что они стоят рядом.

---

## 3. Что является результатом слоя

На выходе builder должен давать два уровня сущностей:

### A. Канонические source unit-ы

То, что реально существует как source-side объекты для resolver-а.

Сюда входят:
- `word`
- `grammar`
- `phrase`
- при необходимости `compound`

### B. Alignment hypotheses

Дополнительные составные кандидаты, которые resolver может использовать при выборе лучшего объяснения.

То есть важно:
- не каждый compound должен сразу стать каноническим unit-ом
- часть compound-ов может существовать только как hypothesis

---

## 4. Классы кандидатов

## 4.1. `always_phrase`

Это то, что почти всегда должно жить как единый смысловой блок.

### A. Phrasal verbs

Примеры:
- `wake up`
- `pick up`
- `look out`
- `sit down`
- `stand up`
- `go out`
- `come back`

Правило:
- если первый токен `verbish`
- второй токен particle/adverb/preposition из разрешённого набора
- строим `phrase`-candidate с высоким приоритетом

### B. Grammar phrases

Примеры:
- `there is`
- `there are`
- `have to`
- `has to`
- `going to`
- `used to`
- `do not`
- `does not`
- `did not`

Правило:
- это не просто соседние слова
- это устойчивый grammar pattern
- по умолчанию это `phrase`, а не два независимых `word`

### C. Fixed expressions

Примеры:
- `of course`
- `good morning`
- `thank you`
- `excuse me`
- `all right`

Правило:
- если выражение есть в curated phrase-list или pattern-list
- строим `phrase`
- resolver должен считать его сильнее раздельного разбора

## 4.2. `optional_compound`

Это не “обязательная фраза”, а полезная составная гипотеза.

### A. `noun + noun`

Примеры:
- `bus driver`
- `school bus`
- `coffee cup`
- `kitchen window`

Почему нужно:
- в RU порядок часто переворачивается
- как compound это часто объясняется лучше, чем два независимых слова

Правило:
- если два соседних content-word
- первый `nounish`
- второй `nounish`
- строим `compound`-hypothesis

### B. `adj + noun`

Примеры:
- `front door`
- `blue sky`
- `little girl`

Важно:
- не всякий `adj+noun` нужно насильно склеивать
- это именно optional hypothesis

Правило:
- если первый `adjish`
- второй `nounish`
- можно строить compound-кандидат
- но его приоритет ниже, чем у настоящих `phrase`

### C. Ограниченные `name/title-like` compounds

Примеры:
- `Mr Brown`
- `Doctor Smith`

Это опционально, позже.
На первом проходе можно не включать, если нет уверенности.

## 4.3. `never_merge`

Сюда относятся случаи, которые нельзя объединять без сильного основания.

Примеры:
- случайные `noun + verb`
- случайные `adj + adj`
- function word + content word без grammar pattern
- длинные последовательности, где нет устойчивого шаблона

Правило:
- соседство само по себе не является причиной строить compound
- нужен pattern, POS logic или curated phrase signal

---

## 5. Приоритеты между классами

Это надо зафиксировать жёстко.

Приоритет hypotheses:

1. `always_phrase`
2. `optional_compound`
3. `single_word`

То есть:
- phrase сильнее compound
- compound сильнее случайного одиночного разбора только если реально лучше объясняет target
- word остаётся базовой fallback-сущностью

---

## 6. Что builder должен использовать как вход

Builder должен опираться на:
- `surface_text`
- `normalized_text`
- `lemma`
- `pos`
- `lexical_unit_type`
- `order_index_in_segment`

Опционально позже:
- dependency info
- simple grammar tags
- curated phrase dictionary

На первом проходе dependency parsing не обязателен.

---

## 7. Какие правила нужны в `v1.1`

Чтобы не раздувать слой сразу, достаточно ограниченного набора правил.

### Для `always_phrase`

- `verb + particle`
- `there + be`
- `have + to`
- `be + going + to`
- curated fixed expressions

### Для `optional_compound`

- `noun + noun`
- `adj + noun`

Этого хватит, чтобы резко улучшить качество без giant engine.

---

## 8. Что builder должен возвращать

Нужно зафиксировать отдельную структуру кандидата.

Пример:

```json
{
  "candidate_id": "seg_123:c_2",
  "source_start": 1,
  "source_end": 2,
  "source_text": "bus driver",
  "candidate_type": "compound",
  "pattern": "noun_noun",
  "priority": 70,
  "is_canonical": false,
  "meta": {
    "owner_mode": "optional_compound"
  }
}
```

Для phrase:

```json
{
  "candidate_id": "seg_123:c_1",
  "source_start": 3,
  "source_end": 4,
  "source_text": "wake up",
  "candidate_type": "phrase",
  "pattern": "verb_part",
  "priority": 100,
  "is_canonical": true,
  "meta": {
    "owner_mode": "always_phrase"
  }
}
```

---

## 9. Правило `is_canonical`

Это ключевая вещь.

### `is_canonical = true`

Использовать для:
- `always_phrase`
- базовых single-word unit-ов
- grammar unit-ов

### `is_canonical = false`

Использовать для:
- `optional_compound` hypotheses

Это нужно, чтобы не превращать каждый compound автоматически в продуктовую сущность.

---

## 10. Как это связано с runtime/UI

Нужно заранее записать:

- `phrase` может стать primary pedagogical object
- `compound` не обязан становиться единым tap-unit
- runtime/UI не должен автоматически склеивать compound только потому, что resolver его увидел

То есть:
- resolver может выбрать `bus driver -> водитель автобуса`
- UI может всё равно оставить `bus` и `driver` отдельными tap-словами
- но detail/debug должен знать, что compound-hypothesis существовала

---

## 11. Какие инварианты должны соблюдаться

- каждый source word всегда существует как минимум как single-word unit
- `always_phrase` может перекрывать несколько single-word unit-ов
- `optional_compound` не удаляет внутренние single-word unit-ы
- builder не должен создавать шумовые составные кандидаты без pattern-based основания
- один и тот же span не должен порождать дубли одного и того же candidate type

---

## 12. Что пока сознательно не включать

На этом этапе не нужно:
- длинные 3-4 word phrase chains без уверенного pattern
- dependency-heavy syntax compounds
- full idiom engine
- statistical phrase mining
- LLM phrase detection

Сначала нужен компактный, контролируемый слой.

---

## 13. Что должно стать результатом Шага 2

После этого шага должны быть готовы:

1. Список `always_phrase` patterns
2. Список `optional_compound` patterns
3. Правила `never_merge`
4. Формат candidate object
5. Правила `priority`
6. Правила `is_canonical`
7. Несколько canonical examples

---

## 14. Примеры canonical examples

### Example 1

`Tom wakes up early.`

Должно строиться:
- `Tom` as `word`
- `wakes` as `word`
- `up` as `word/grammar`
- `wake up` as `phrase`, `is_canonical=true`

### Example 2

`The bus driver opened the door.`

Должно строиться:
- `The`
- `bus`
- `driver`
- `opened`
- `the`
- `door`
- `bus driver` as `compound`, `is_canonical=false`

### Example 3

`There is a cat in the room.`

Должно строиться:
- `there is` as `phrase`, `is_canonical=true`
- `a` as `grammar`
- `cat` as `word`
- `in` as `grammar`
- `the` as `grammar`
- `room` as `word`

---

## 15. Что будет следующим шагом после этой спеки

После утверждения этой подспеки уже логично делать следующую:
- `candidate generation spec`

Потому что как только мы поняли, какие unit/candidate типы существуют, можно определять:
- какие target span hypotheses для них строить
- как строить owner spans
- как строить absorbed-first candidates для grammar words

---

## 16. Практический вывод

Шаг 2 должен зафиксировать 4 главные вещи:

- `always_phrase` и `optional_compound` — это разные классы
- compound — это hypothesis, а не обязательная UI-склейка
- phrase — это сильный canonical unit
- builder должен быть узким, pattern-based и контролируемым, а не “склеиваем всё подряд”
