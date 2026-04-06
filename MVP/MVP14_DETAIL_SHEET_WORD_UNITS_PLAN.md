# MVP14 — Detail Sheet Word Units Plan

## 1. Цель этапа

Добавить в reader режим детального разбора выделенного блока через `long press`, не ломая текущий быстрый tap-flow.

Итог этапа:

- обычный `tap` остаётся как быстрый перевод текущего `tap unit`
- `long press` открывает нижнюю `Detail Sheet`
- `Detail Sheet` показывает не веер отдельных карточек, а одну составную панель
- внутри панели отображаются `unit rows`:
  - phrase
  - lexical
  - grammar
- для построения панели используются уже существующие reader-данные и новый слой lexical enrichment
- frontend не вычисляет grammar/lemma/phrase сам

## 2. Главный принцип

Не делать:

- отдельный экран поверх reader
- россыпь из 3-4 независимых карточек
- словарную статью
- длинные объяснения
- отдельную новую модель перевода

Делать:

- один `Detail Sheet` на текущий выделенный блок
- краткий разбор внутренних смысловых единиц
- минимальные grammar hints
- показ формы слова через связь `surface -> lemma + label`

Ключевая формула этапа:

`Tap Unit -> Detail Sheet -> Unit Rows`

## 3. Почему нужен отдельный этап

В текущем проекте уже есть:

- word-level storage
- heuristic alignment
- `tap units`
- стабильный reader payload
- backend `tokens` для рендера source text

Это означает, что базовая интерактивность reader уже существует.

Новый этап не должен переписывать:

- `word_alignment.py`
- текущий быстрый tap translation flow
- reader token rendering
- mobile book package как источник reader payload

Этап должен добавить только второй уровень взаимодействия:

- быстрый tap для мгновенного понимания
- long press для короткого разбора структуры блока

## 4. Продуктовая модель этапа

### 4.1 Tap layer

Остаётся без изменения.

Пользователь:

- читает текст
- делает обычный `tap`
- получает быстрый перевод текущего `tap unit`

Пример:

- `the sun`
- tap -> `солнце`

### 4.2 Detail layer

Появляется новый `long press` на том же reader token / tap unit.

Пользователь:

- удерживает слово или блок
- открывает `Detail Sheet`
- видит перевод всей группы
- ниже видит короткий разбор внутренних единиц

### 4.3 Unit rows

`Detail Sheet` не показывает отдельные плавающие карточки.

Он показывает список строк внутри одной панели.

Типы строк:

- `PHRASE`
- `LEXICAL`
- `GRAMMAR`

## 5. Термины этапа

### 5.1 Tap Unit

Сущность текущего reader interaction layer.

Это то, что:

- выделяется при tap
- уже имеет быстрый translation context
- уже приходит в payload через `tap_unit_id`

Примеры:

- `the sun`
- `He is`
- `in front of`

### 5.2 Detail Sheet

Одна нижняя шторка, открывающаяся по `long press`.

Она относится к одному выбранному `tap unit`.

### 5.3 Unit Row

Одна строка внутри `Detail Sheet`.

Это не reader unit и не render token.

Это отдельная detail-level сущность для объяснения содержимого выбранного блока.

### 5.4 Phrase Unit

Смысловая единица, которую нельзя полезно делить на отдельные слова в MVP.

Примеры:

- `in front of`
- `take off`

### 5.5 Lexical Unit

Обычное смысловое слово.

Примеры:

- `sun`
- `run`
- `house`

### 5.6 Grammar Unit

Служебное слово с краткой функцией.

Примеры:

- `the`
- `a`
- `of`
- `will`

## 6. Пользовательский результат

### 6.1 Сценарий: `the sun`

Обычный tap:

- `солнце`

Long press:

```text
the sun
солнце

the
грамматика: указывает на конкретный объект

sun
солнце
основное слово

Пример:
The sun is hot.
```

### 6.2 Сценарий: `He ran home`

Tap по `ran` или по текущему unit:

- `бежал` / `побежал`

Long press:

```text
ran
бежал

run
бежать

ran -> прошедшее

Пример:
He ran home.
```

### 6.3 Сценарий: `in front of the house`

Long press:

```text
in front of the house
перед домом

in front of
перед

the
грамматика: делает предмет конкретным

house
дом
основное слово
```

### 6.4 Сценарий: `He took off his jacket`

Long press:

```text
took off
снял

take off
снять

took -> прошедшее

Пример:
He took off his jacket.
```

## 7. Что должно происходить в UI

## 7.1 Trigger

`Detail Sheet` открывается по `long press` на reader token.

Trigger должен быть доступен:

- desktop
- mobile

## 7.2 Layout

`Detail Sheet` открывается снизу и не уводит пользователя на новый экран.

Структура:

- header
- optional example block
- list of `unit rows`
- optional action area

## 7.3 Header

Верхний блок должен содержать:

- исходный text текущего `tap unit`
- быстрый перевод всей группы

Если текущий перевод уже есть в reader state, он должен переиспользоваться.

## 7.4 Unit rows rendering

### Phrase row

Показывает:

- phrase text
- перевод
- при наличии короткую строку-пояснение

Пример:

- `in front of — перед`

### Lexical row

Показывает:

- surface или lemma в зависимости от сценария
- основной перевод
- если форма отличается от lemma, короткую форму связи

Пример:

- `run — бежать`
- `ran -> прошедшее`

### Grammar row

Показывает:

- слово
- краткую функцию в одну строку

Пример:

- `the — указывает на конкретный объект`

## 7.5 Save behavior

В рамках MVP сохранять в study/saved words только:

- `PHRASE`
- `LEXICAL`

Массовое сохранение `GRAMMAR` не делать.

Допустимая MVP-логика:

- grammar rows показываются для понимания
- по умолчанию не попадают в список изучаемого

## 8. Порядок логики внутри detail sheet

Логика классификации должна идти строго сверху вниз.

### Шаг 1. Найти phrase units

Если внутри выбранного блока есть MWE / phrase match:

- сначала формируется phrase unit
- слова внутри phrase unit отдельно не разваливаются

Пример:

- `take off` должно стать одним `PHRASE`
- `in front of` должно стать одним `PHRASE`

### Шаг 2. Выделить grammar words

Для оставшихся одиночных слов определить grammar-like units.

### Шаг 3. Остальное считать lexical

Если слово не попало в phrase и не классифицировано как grammar, оно становится lexical fallback.

Это важное правило, чтобы система не теряла смысловые слова из-за слишком узких POS-правил.

## 9. Источник данных

Новый этап должен использовать существующие backend-данные:

- `source_words`
- `word_alignments`
- текущие `tap units`
- текущий `translation span` / `translation context`

Новый слой должен добавлять:

- `lemma`
- `pos`
- `morph`
- detail-level unit grouping

Нельзя переносить business logic в Flutter.

Frontend должен получать уже готовую detail-модель от backend.

## 10. Новая backend-модель

### 10.1 Новый слой

После текущего `word_mapping` добавить новый этап:

`lexical_enrichment`

Упрощённый pipeline:

`text -> normalize -> segments -> translate -> word_mapping -> lexical_enrichment -> DB`

### 10.2 Задача слоя

Для каждого source word получить:

- `lemma`
- `pos`
- `morph`

Для некоторых последовательностей слов получить:

- detail-level phrase grouping

### 10.3 Граница слоя

Новый слой не должен менять:

- target translation
- существующий `tap unit` selection contract
- reader render tokens

Его задача:

- обогатить `source_words`
- подготовить данные для `Detail Sheet`

## 11. Изменения в БД

Текущая точка расширения:

- таблица `source_words`

### 11.1 Добавляемые поля

- `lemma TEXT`
- `pos TEXT`
- `morph TEXT`
- `lexical_unit_id TEXT NULL`
- `lexical_unit_type TEXT NULL`

### 11.2 Назначение полей

`lemma`

- базовая форма слова

`pos`

- coarse POS для MVP

`morph`

- сериализованная morphology строкой или JSON

`lexical_unit_id`

- id detail-level unit, к которому относится слово
- нужен для объединения слов в phrase row

`lexical_unit_type`

- один из:
  - `PHRASE`
  - `LEXICAL`
  - `GRAMMAR`

### 11.3 Почему не использовать только `tap_unit_id`

Потому что:

- `tap unit` нужен для reader selection
- `lexical unit` нужен для detail sheet decomposition

Пример:

- `the sun` может быть одним `tap unit`
- но в detail sheet это две строки:
  - `the`
  - `sun`

Следовательно:

- `tap unit` и `lexical unit` нельзя смешивать

## 12. Правила классификации для MVP

### 12.1 Phrase first

Сначала искать phrase units.

Для MVP достаточно ограниченного набора:

- phrasal verbs из whitelist
- несколько устойчивых preposition phrases

Примеры:

- `take off`
- `wake up`
- `in front of`

### 12.2 Grammar rules

Если слово не попало в phrase, тогда grammar определяется по простым правилам.

Базовый набор POS для `GRAMMAR`:

- `DET`
- `ADP`
- `PART`
- `AUX`

Допустимо добавить ручной whitelist для спорных коротких слов, если это потребуется для стабильности MVP.

### 12.3 Lexical fallback

Если слово:

- не является phrase
- не является grammar

то оно считается `LEXICAL`.

Это правило обязательно для MVP, чтобы поведение было предсказуемым.

## 13. Morph labels для MVP

Нужно не объяснять теорию, а показывать живую связь формы с базой.

### 13.1 Что показывать

Минимальный набор labels:

- `прошедшее`
- `сейчас длится`
- `базовая форма`

### 13.2 Примеры

- `ran -> прошедшее`
- `running -> сейчас длится`

### 13.3 Что не показывать

Не писать:

- `irregular verb`
- `second form`
- `third form`
- длинные grammar descriptions

## 14. Детальная payload-модель

Нужен отдельный backend payload для открытия detail sheet.

Рабочий контракт MVP:

- `sheet_source_text`
- `sheet_translation_text`
- `example_source_text`
- `example_translation_text`
- `units[]`

Каждый `unit` должен содержать:

- `id`
- `type`
- `text`
- `lemma`
- `translation`
- `grammar_hint`
- `morph_label`
- `is_primary`

### 14.1 Принцип payload

Backend должен возвращать уже собранный список `units`.

Frontend не должен:

- вычислять `phrase`
- вычислять `lemma`
- вычислять `grammar_hint`
- склеивать строки сам

## 15. API-граница этапа

Есть два допустимых варианта MVP.

### Вариант A. Отдельный endpoint detail sheet

Например:

- `GET /reader/detail-sheet?book_id=...&word_id=...`

Плюсы:

- не раздувает основной reader payload
- detail данные грузятся только по запросу

Минусы:

- дополнительный API round-trip

### Вариант B. Встраивание detail payload в основной reader payload

Плюсы:

- sheet открывается мгновенно

Минусы:

- package и reader payload сильно разрастаются

Для MVP предпочтителен:

- `Вариант A`

Причина:

- detail sheet не нужен на каждый tap
- enrichment хранится в БД
- собрать sheet по `word_id` на backend проще и чище

## 16. Изменения в mobile package

Так как mobile reader работает через package snapshot, detail sheet должен быть совместим и с mobile-моделью.

Если выбран `Вариант A` и mobile читает локальный package без host:

- нужно решить, может ли mobile строить detail sheet полностью локально

Для MVP проще и чище сделать так:

- detail data включается в package только в минимальном виде, достаточном для локального sheet

Минимально в package должны попасть:

- новые поля `source_words`
- либо уже готовая compact detail-model по словам

Итоговое правило этапа:

- detail sheet должен работать одинаково на desktop и mobile

## 17. Backend-изменения по файлам

### 17.1 Новый модуль

Добавить новый модуль:

- `engine/lexical_enrichment.py`

Задачи модуля:

- обогащение word rows
- phrase detection для MVP
- morphology labels mapping
- detail unit grouping

### 17.2 Storage layer

Расширить:

- `engine/storage.py`

Задачи:

- миграции новых колонок `source_words`
- вызов `lexical_enrichment` при импорте
- сборка detail payload
- при необходимости упаковка detail data в mobile package

### 17.3 API layer

Расширить:

- `engine/api.py`

Задачи:

- новый endpoint под `Detail Sheet`, если выбран `Вариант A`

### 17.4 UI models

Расширить:

- `app/lib/src/models.dart`

Задачи:

- новая модель `DetailSheetPayload`
- новая модель `DetailSheetUnitItem`

### 17.5 Reader UI

Расширить reader widgets/screens:

- desktop reader
- mobile reader

Задачи:

- обработка `long press`
- открытие bottom sheet
- рендер unit rows

## 18. Порядок реализации

### Шаг 1

Добавить DB-миграции под новые поля `source_words`.

### Шаг 2

Добавить `lexical_enrichment` в backend pipeline импорта.

### Шаг 3

Добавить backend builder для `Detail Sheet`.

### Шаг 4

Добавить API contract для открытия `Detail Sheet`.

### Шаг 5

Добавить Flutter models под новый payload.

### Шаг 6

Добавить `long press -> bottom sheet` в desktop reader.

### Шаг 7

Добавить ту же механику в mobile reader.

### Шаг 8

Проверить package / local mobile behavior, чтобы sheet не зависел от frontend вычислений.

## 19. Что не входит в этап

- словарь значений
- Oxford-style article
- LLM
- новая translation model
- переписывание текущего alignment
- отдельный screen flow для grammar learning
- spaced repetition
- массовое сохранение grammar words

## 20. Критерии готовности

Этап считается готовым, если:

- обычный `tap` в reader работает как раньше
- `long press` открывает `Detail Sheet`
- `Detail Sheet` собирается backend-логикой, а не фронтовыми эвристиками
- `the sun` показывает один sheet с двумя строками, а не две отдельные карточки
- `ran` показывает `run` и label `прошедшее`
- `take off` и `in front of` не разваливаются на бессмысленные одиночные grammar rows
- mobile и desktop получают один и тот же смысловой результат
- grammar rows не засоряют saved words по умолчанию

## 21. Решения по умолчанию для MVP

Если на этапе реализации возникнут спорные места, по умолчанию принимать такие решения:

- сохранять текущий `tap unit` без изменений
- decomposition делать только в detail sheet
- phrase detection держать узкой и контролируемой
- grammar explanations делать короткими и шаблонными
- не пытаться покрыть все случаи английского языка
- если случай неоднозначный, лучше показать lexical row, чем сломать смысловую phrase

## 22. Итог этапа

После `MVP14` reader должен получить второй слой понимания текста:

- `tap` отвечает за скорость
- `long press` отвечает за структуру

Пользователь в итоге получает:

- быстрый перевод без перегруза
- короткий разбор формы слова
- короткие grammar hints
- понятную структуру фразы внутри одного компактного sheet

Это должно усилить core reading experience, не превращая reader в учебный словарь и не ломая текущую MVP-архитектуру.
