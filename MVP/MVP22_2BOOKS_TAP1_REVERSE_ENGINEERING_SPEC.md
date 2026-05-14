# MVP22 — `2Books` Tap #1 Reverse Engineering Spec

## Цель документа

Этот документ фиксирует максимально подробную реконструкцию того, как у приложения `2Books` устроен контур:

- `sentence alignment`
- `word alignment`
- локальные `frame`
- runtime `tap #1`

Документ основан не на абстрактных гипотезах, а на анализе:

- APK и распакованных Flutter-ресурсов
- живых файлов приложения в Android-эмуляторе
- `page payload`
- внутренних SQLite-баз
- строк и SQL-фрагментов из `libapp.so`

Основная цель:

- выделить реальный data contract `2Books`
- понять, что именно делает `tap #1`
- понять, что именно хранится заранее
- оценить, какие принципы можно использовать как референс для LEXO

## Граница уверенности

В документе различаются 3 уровня утверждений:

- `Подтверждено`:
  - напрямую доказано файлами, БД или payload
- `Сильная реконструкция`:
  - не виден исходный Dart-код, но данные очень сильно указывают на такой механизм
- `Остаётся неизвестным`:
  - по доступным артефактам восстановить точно пока нельзя

## Что было исследовано

### APK и распакованные файлы

- [Other/su.x2books.app.apk](/mnt/d/Programs/LEXO/Other/su.x2books.app.apk)
- [Other/resources/AndroidManifest.xml](/mnt/d/Programs/LEXO/Other/resources/AndroidManifest.xml)
- [Other/resources/lib/arm64-v8a/libapp.so](/mnt/d/Programs/LEXO/Other/resources/lib/arm64-v8a/libapp.so)
- [Other/resources/assets/flutter_assets/assets/translations/en.yaml](/mnt/d/Programs/LEXO/Other/resources/assets/flutter_assets/assets/translations/en.yaml)
- [Other/resources/assets/flutter_assets/assets/dictionary.zip](/mnt/d/Programs/LEXO/Other/resources/assets/flutter_assets/assets/dictionary.zip)
- [Other/resources/assets/flutter_assets/assets/priors.zip](/mnt/d/Programs/LEXO/Other/resources/assets/flutter_assets/assets/priors.zip)

### Живые файлы приложения в эмуляторе

- `/data/data/su.x2books.app/app_flutter/books/...`
- `/data/data/su.x2books.app/app_flutter/parallel/process.db`
- `/data/data/su.x2books.app/databases/user.db`
- `/data/data/su.x2books.app/databases/priors.db`
- `/data/data/su.x2books.app/databases/dictionary.db`
- `/data/data/su.x2books.app/databases/dictionary_cache.db`

## Что подтверждено по продуктовому контракту

Из `translations/en.yaml` подтверждено:

- `Tap on the words to see a parallel translation`
- `The dictionary translation opens when you tap a word again`
- `Alignment of sentences by dictionary`
- `Quick alignment of sentences without dictionary`
- `Word alignment`

Из этого сразу следует:

- `tap #1` не является словарной карточкой
- `tap #1` относится к слою `parallel translation`
- в продукте существует отдельный pipeline:
  - sentence alignment
  - word alignment

## Что подтверждено по типу приложения

Подтверждено:

- это Flutter APK
- Android-обвязка вторична
- главная логика сидит в `libapp.so`

Следствие:

- точный Dart-код напрямую не виден
- поведение приходится восстанавливать по runtime-данным и строкам бинаря

## Runtime-источник истины для `tap #1`

### Подтверждено

У каждой книги в приложении есть:

- `meta.json`
- `toc.json`
- `pages/*.json.gz`

Именно `pages/*.json.gz` являются runtime-источником данных для `tap #1`.

Это главный факт всего анализа.

### Подтверждённый формат страницы

Пример:

```json
{
  "tokens1": [["The",""," ",0,null],["Sunny",""," ",0,100],["Morning","","",1,100]],
  "tokens2": [["Солнечное",""," "],["утро","",""]],
  "sentences": [0],
  "version": 2,
  "translator": "google_mobile",
  "footnotes1": [],
  "footnotes2": []
}
```

Подтверждённая интерпретация:

- `tokens1[i] = [text, left, right, targetIndex, score]`
- `tokens2[j] = [text, left, right]`

Где:

- `text` — токен
- `left` — левый префикс перед токеном
- `right` — правый хвост после токена
- `targetIndex` — индекс target-токена
- `score` — роль source-token внутри локального alignment-frame

### Подтверждённые примеры

- `["Sunny",""," ",0,100] -> tokens2[0] = "Солнечное"`
- `["Morning","","",1,100] -> tokens2[1] = "утро"`
- `["The",""," ",0,null] -> tokens2[0] = "Солнечное"`
- `["wakes",""," ",5,100]`
- `["up",""," ",5,null]`

## Что это значит для `tap #1`

### Подтверждено

`tap #1`:

- не делает alignment в момент клика
- не делает live dictionary lookup как основной механизм
- читает уже сохранённый page payload

Минимальный runtime-контракт:

```text
source token
-> targetIndex из tokens1[i][3]
-> target token / target sentence context
```

### Сильная реконструкция

Reader почти наверняка использует не только один `targetIndex`, но и:

- текущее source sentence
- target sentence span вокруг выбранного токена
- локальный frame вокруг текущего слова

Иначе было бы невозможно стабильно показывать корректный target-фрагмент в случаях, где target содержит слова без source owner.

## Sentence-level контракт

### Подтверждено

Поле `sentences` хранит стартовые индексы source-предложений в `tokens1`.

Примеры:

- `[0, 5, 11, 15, 18, 28, 33, 38]`
- `[0, 3, 6, 11, 15, 20, 25, 36]`

После разрезания по этим индексам получаются реальные source sentences.

### Подтверждено

Для каждого source sentence набор `targetIndex` почти всегда образует локальный target-span.

Примеры:

- `Tom wakes up at 7:00 AM.` -> `Том просыпается в 7:00 утра.`
- `He is happy.` -> `Он счастлив.`
- `Tom makes breakfast.` -> `Том готовит завтрак.`

### Следствие

Верхний runtime-контракт у `2Books` выглядит так:

```text
page
-> source sentences
-> target sentence spans
-> token-level links внутри sentence
```

## Token role model: `100 / 0 / null`

### Подтверждено по данным

Встречаются только три класса:

- `100`
- `0`
- `null`

### Сильная реконструкция

Это не просто confidence.
Это, вероятнее всего, роль source-token внутри локального frame.

#### `100`

`100` выглядит как `head anchor`.

Свойства:

- имеет собственный alignment-link
- обычно несёт главный смысловой узел локальной конструкции
- часто соответствует lexical head или main predicate / main content token

Примеры:

- `wakes -> просыпается`
- `transformed -> изменило`
- `interact -> взаимодействия`
- `technology -> технологиями`
- `future -> будущего`

#### `0`

`0` выглядит как `explicit secondary link`.

Свойства:

- это тоже собственный alignment-link
- но он не является главным anchor внутри локального frame
- часто выражает:
  - структурный элемент
  - предлог
  - зависимый content-piece
  - часть перестроенной конструкции

Примеры:

- `in -> в`
- `on -> в`
- `made -> принимаются`
- `ensure -> обеспечения`
- `sustainable -> устойчивого`
- `advancement -> прогрессом`

#### `null`

`null` выглядит как `attached residue`.

Свойства:

- собственного alignment-link нет
- token просто делит `targetIndex` с соседним source-token
- служит для UI-непрерывности и сохранения поверхностного потока

Примеры:

- `up -> просыпается`
- `the -> Солнце`
- `is -> Он`
- `a -> ест`

### Практический вывод

Их token-role модель очень похожа на:

```text
H = primary aligned head
S = secondary explicit aligned dependent
N = attached non-aligned residue
```

## Local frame model

### Главный вывод

Внутри source sentence у `2Books` явно существуют локальные `frame`.

Frame — это не весь sentence и не один token.
Это компактная локальная конструкция, внутри которой source tokens связаны с компактным target-span.

### Подтверждённые признаки frame

Frame:

- лежит внутри одного sentence
- состоит из подряд идущих source tokens
- их target indices попадают в короткий local span
- допускает небольшой reorder
- несёт внутренние роли `H/S/N`

### Повторяющиеся типы frame

#### 1. Verb + particle / preposition

Примеры:

- `wakes up -> просыпается`
- `get on the bus -> садится в автобус`

Роли:

- `get = H`
- `on = S`
- `the = N`
- `bus = H`

#### 2. Preposition + noun phrase

Примеры:

- `in a big city -> в большом городе`
- `in the workplace -> на рабочем месте`

Роли:

- `in = S`
- `a/the = N`
- прилагательное / существительное = чаще `H`

#### 3. Copula / support residue

Примеры:

- `He is happy -> Он счастлив`
- `Luna is small and grey -> Луна маленькая и серая`

Роли:

- местоимение / content heads = `H`
- `is` = `N`

#### 4. Clause frame / discourse operator

Примеры:

- `As a result -> В результате`
- `At the same time -> В то же время`

Роли:

- часть токенов получает `S`
- один content/head токен получает `H`
- остатки иногда `N`

#### 5. Nominal reorder

Примеры:

- `Bus Driver -> Водитель автобуса`
- `human responsibility -> ответственностью человека`

Свойства:

- оба content token могут быть `H`
- порядок target может быть инвертирован

#### 6. Predicate restructuring

Примеры:

- `made by algorithms -> принимаются алгоритмами`
- `required to ensure a sustainable future -> требуется для обеспечения устойчивого будущего`

Свойства:

- главный предикат обычно `H`
- structural scaffold — `S`
- residue — `N`

## Как frame режется внутри sentence

### Подтверждено

Главный boundary-signal — topology `targetIndex`.

Основные причины разрыва frame:

#### 1. `backward_jump`

Если новый source token указывает в target левее предыдущего,
очень часто начинается новый frame.

Примеры:

- `people -> 15`, `interact -> 14`
- `seemed -> 21`, `like -> 18`
- `find -> 125`, `a -> 120`

#### 2. большой `forward_gap`

Если targetIndex прыгает слишком далеко вперёд,
тоже начинается новый frame.

Наблюдаемые gap:

- `+3`
- `+4`
- `+5`
- `+6`

Примеры:

- `morning -> 32`, `many -> 36`
- `boy -> 50`, `gets -> 53`
- `result -> 58`, `employees -> 61`

### Сильная реконструкция boundary-rule

Frame, вероятно, строится так:

```text
идём слева направо по source sentence
держим текущий local target span

если:
- targetIndex откатывается назад
или
- новый targetIndex слишком далеко расширяет span

то:
- закрываем frame
- открываем новый
```

## Почему одного набора word-links недостаточно

### Подтверждено

Есть target tokens, на которые не указывает ни один source token.

Примеры:

- `рабочем`
- `конечном`
- `все`

### Следствие

Reader не может строить parallel view только как union точечных source-token links.

Нужен ещё как минимум:

- target sentence span
- или target frame span

Именно поэтому sentence/frame уровень обязателен.

## Что видно по `priors.db`

### Подтверждено

В приложении есть отдельная база alignment-priors:

- `en_words`
- `ru_words`
- `en_ru_counts`
- `fert`
- `jump`

Примеры:

- `make -> сдела / дела / застав / приготов`
- `made -> сдела / застав / дела / приготов`
- `jump` имеет ярко выраженное распределение по локальным смещениям

### Очень важный вывод

Это не runtime слой reader-а.
Это statistical prior layer для build-stage alignment.

### Дополнительное наблюдение

Английские ключи часто лежат в stem-подобной форме:

- `peopl`
- `morn`
- `wake`
- `ensur`
- `sustain`
- `signific`

То есть alignment, скорее всего, использует нормализованные формы, а не только surface tokens.

## Что видно по `process.db`

### Подтверждено

Есть staging DB:

- `align(id, links, length, score)`
- `main_book(..., align_id, align_token)`
- `secondary_book(..., align_id, align_token)`

### Следствие

Build-stage включает:

- подготовку source/target предложений
- sentence alignment
- промежуточную сущность `align`
- дополнительный token-level слой `align_token`

### Что остаётся неизвестным

- точное содержимое `links`
- точное содержание `align_token`
- в каком формате sentence alignment переходит в token-level frames

## Что видно по `libapp.so`

Из строк бинаря подтверждены фазы:

- `parallel.align.sentences.batchPrepare`
- `parallel.align.sentences.batchAlign`
- `parallel.align.sentences.uniqueWords`
- `parallel.align.words.prepare`
- `parallel.align.words.align`
- `parallel.align.words.save`
- `parallel.match.quickAlign`
- `parallel.export.quality`

Также подтверждены строки:

- `priors.db`
- `process.db`
- `tokens1`
- `tokens2`
- `align_token`

Это поддерживает reconstruction:

```text
sentence prepare
-> sentence align
-> word align
-> save
-> export page payload
-> reader tap
```

## Итоговая реконструкция пайплайна

### Сильная реконструкция

На текущем уровне данных наиболее правдоподобный pipeline выглядит так:

```text
1. Source/target texts tokenized and split into sentences
2. Sentence alignment is built
3. For each aligned sentence pair:
   - lexical/statistical priors are used
   - token-level links are proposed
4. Sentence pair is split into local frames by target-index topology
   - backward jumps
   - large forward gaps
5. Inside each frame source tokens get roles:
   - H = head anchor = 100
   - S = explicit dependent = 0
   - N = attached residue = null
6. Result is serialized into pages/*.json.gz
7. Reader tap #1 reads this persisted structure
```

## Что уже можно считать установленным

- `tap #1` не является realtime alignment
- `tap #1` работает по persisted page payload
- верхний контейнер — `sentence`
- внутри sentence есть локальные `frame`
- внутри frame source token имеет роль:
  - head
  - secondary
  - attached
- границы frame зависят от topology `targetIndex`
- reader не может работать только по точечным word-links, потому что target содержит unmapped tokens

## Что остаётся неполным

- точная формула выбора `H` против `S`
- точный порог для `forward_gap`
- точный формат `align_token`
- точная схема промежуточных word tables вроде:
  - `main_words`
  - `secondary_words`
  - `counts`
- точный reader-алгоритм сборки визуального target-focus из frame и sentence-span

## Практический смысл для LEXO

Этот reverse-engineering не означает, что LEXO должен копировать `2Books` буквально.
Но он показывает важные принципы:

- sentence-first scaffold обязателен
- token-only `1:1` контракт недостаточен
- нужен local frame уровень
- нужно различать:
  - main anchors
  - explicit dependents
  - attached residue
- target-side view не должен строиться только из source-token matches

## Краткий итог

Самая короткая формула того, что, вероятно, делает `2Books`:

```text
sentence-aligned
-> frame-segmented
-> head-aware token alignment
-> persisted page JSON
-> reader tap over saved structure
```

На данный момент именно эта модель лучше всего объясняет все найденные артефакты:

- `pages/*.json.gz`
- `100 / 0 / null`
- `backward_jump`
- `forward_gap`
- unmapped target tokens
- `priors.db`
- `process.db`
