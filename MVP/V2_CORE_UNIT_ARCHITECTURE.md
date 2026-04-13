# V2 Core Unit Architecture

## Цель

Собрать новый `V2 core` как отдельный контур и законсервировать текущий translation/alignment pipeline как legacy.

`V2 core` должен строиться не вокруг target-span и не вокруг позиционного alignment, а вокруг канонических source unit-ов.

Главная идея:

- пользователь тапает source unit
- система знает тип unit-а
- система знает lookup / explanation для unit-а
- система пытается найти target coverage
- если target coverage ненадёжен, система всё равно показывает правильный lookup и учебный перевод сегмента

Подсветка target нужна как визуальный слой поверх unit-системы, а не как источник смысла.

## Базовый приоритет смысла

В `V2 core` lookup всегда первичен, а target coverage вторичен.

Это жёсткое правило:

- если `coverage_status = exact`, UI показывает lookup + coverage
- если `coverage_status = reordered`, UI показывает lookup + coverage
- если `coverage_status = absorbed`, UI показывает lookup без требования отдельного span
- если `coverage_status = phrase_owned`, UI показывает lookup owner unit-а и coverage owner-а
- если `coverage_status = fuzzy` или `none`, UI всё равно обязан показать корректный lookup и `segment_translation_learning`

Отсутствие надёжного target span не делает tap payload невалидным.

## Статус legacy

Текущий core не удаляется сразу.

Он должен быть:

- извлечён в отдельный legacy-контур
- заморожен как reference implementation
- исключён из дальнейшего проектирования нового ядра

Оболочка приложения, reader UI, offline package, detail sheet framework и cards сохраняются.

## Канонические unit types

В `V2 core` вводятся 5 базовых типов:

### 1. `LEXICAL`

Обычные смысловые слова.

Примеры:

- `Tom`
- `sun`
- `happy`
- `kitchen`
- `flowers`

### 2. `PHRASE`

Устойчивые или составные блоки, которые нельзя честно дробить на отдельные переводы.

Примеры:

- `wake up`
- `good morning`
- `look at`
- `have to`
- `at 7:00 AM` в зависимости от source-правила может быть либо `META/TIME`, либо специальным phrase/pattern unit

### 3. `FUNCTION`

Служебные слова, которые нельзя трактовать как обычный перевод.

Примеры:

- `the`
- `a`
- `an`
- `in`
- `on`
- `to`
- `of`
- `is`
- `are`
- `was`

### 4. `GRAMMAR`

Грамматические конструкции, где смысл возникает из схемы, а не из одного слова.

Примеры:

- `it is`
- `there is`
- `going to`
- `used to`
- `do not`
- некоторые связки могут храниться не как отдельный unit, а как grammar relation к host/predicate блоку

### 5. `META`

Не лексика narrative-текста.

Примеры:

- `Chapter 1`
- `7:00 AM`
- имя главы
- номер
- punctuation marker
- dialogue marker

## Приоритет типов

Порядок source-анализа должен быть жёстким:

1. `META`
2. `PHRASE`
3. `GRAMMAR`
4. `FUNCTION`
5. `LEXICAL`

Это обязательное правило.

Нельзя сначала разметить всё как слова, а потом пытаться задним числом собирать phrases и grammar blocks.

## Канонические сущности данных

### `SourceUnit`

Минимальный контракт:

```text
SourceUnit
unit_id
segment_id
type
source_text
token_start
token_end
head_token_id
attached_to_unit_id nullable
phrase_owner_unit_id nullable
lookup_mode = translate | explain | none
priority
```

Назначение:

- хранит каноническую source-единицу
- является основой tap UX
- не зависит от target matching

### `LookupResult`

Минимальный контракт:

```text
LookupResult
unit_id
status = found | guessed | missing
base_translation
alt_translations
explanation
source = phrase_dict | lemma_dict | function_rules | grammar_rules | mt_fallback | manual_curated | pattern_rule
```

Назначение:

- даёт смысл unit-у
- является первичным ответом на tap
- не зависит от того, удалось ли найти точный target span

### `TargetCoverage`

Минимальный контракт:

```text
TargetCoverage
unit_id
target_text
target_token_start
target_token_end
coverage_status = exact | reordered | absorbed | phrase_owned | fuzzy | none
host_unit_id nullable
owner_unit_id nullable
confidence
```

Назначение:

- описывает только визуальное покрытие unit-а в target
- не определяет смысл unit-а
- может отсутствовать или быть неполным без потери корректности lookup
- статусы `absorbed` и `phrase_owned` считаются нормальными валидными состояниями coverage, а не ошибками matching

### `TapPayload`

Минимальный контракт:

```text
TapPayload
selected_unit_text
selected_unit_type
lookup_title
lookup_body
segment_source
segment_translation_learning
target_coverage_text
coverage_status
host_unit_text nullable
phrase_owner_text nullable
```

Назначение:

- единый payload для reader tap UX
- должен строиться от `SourceUnit + LookupResult + TargetCoverage`
- должен оставаться валидным даже при `coverage_status = fuzzy` или `none`

## Правила анализа source

### Шаг 1. Tokenize source

Source разбирается только по английскому тексту.

Пример:

`Tom wakes up at 7:00 AM`

Токены:

- `Tom`
- `wakes`
- `up`
- `at`
- `7:00`
- `AM`

### Шаг 2. Сначала искать multi-token unit-ы

Это критично.

Сначала искать:

- phrasal verbs
- fixed phrases
- time patterns
- chapter/title patterns
- grammar patterns

Примеры:

- `wakes up` -> `PHRASE`
- `7:00 AM` -> `META`
- `at 7:00 AM` -> в зависимости от source-правила либо `META/TIME`, либо специальный phrase/pattern unit

### Шаг 3. Потом размечать function words

Примеры:

- `at` -> `FUNCTION`
- `the` -> `FUNCTION`
- `is` -> `FUNCTION`, если не поглощён `GRAMMAR`

### Шаг 4. Остаток = lexical

Примеры:

- `Tom` -> `LEXICAL`
- `sun` -> `LEXICAL`

## Правила для `FUNCTION` и `GRAMMAR`

Нужно явно различать:

- одиночное служебное слово
- grammar block, который поглощает несколько токенов

Базовое правило:

- `is` само по себе = `FUNCTION`
- `it is`, `there is`, `do not`, `going to` = `GRAMMAR`
- если токен входит в grammar block, его одиночный unit не должен становиться главным смысловым объектом

## Owner resolution при tap

Если пользователь тапает токен, который принадлежит `PHRASE` или `GRAMMAR`, система не должна строить ложный отдельный word-level смысл.

Правило:

- tap по токену внутри `PHRASE` должен резолвиться в phrase owner
- tap по токену внутри `GRAMMAR` должен резолвиться в grammar owner или grammar relation host
- одиночный token-level payload допустим только если токен действительно живёт как самостоятельный unit

## Правила target coverage

Подсветка не обязана быть всегда точной.

Она должна быть tiered.

### `exact`

Явный target кусок найден.

Пример:

- `happy` -> `счастлив`

### `reordered`

Перевод найден, но в другой позиции.

Пример:

- `Anna says`
- `говорит Анна`

Тогда:

- `Anna` покрывает `Анна`
- `says` покрывает `говорит`
- `coverage_status = reordered`

### `absorbed`

Unit смыслово присутствует, но отдельного русского слова нет.

Примеры:

- `the`
- `is`

Тогда:

- lookup / explanation показывается
- отдельный target highlight не обязателен
- можно привязаться к host unit

### `phrase_owned`

Слово принадлежит phrase unit и отдельно не живёт.

Пример:

- `wake` внутри `wake up`
- `up` внутри `wake up`

Тогда:

- отдельный target span для токена не строится
- показывается coverage phrase owner-а

### `fuzzy`

Есть только слабое приближение.

Используется как запасной статус, но не должен становиться основной логикой.

### `none`

Покрытие не найдено.

Lookup и explanation всё равно остаются валидными.

## Как искать target coverage

Нельзя опираться только на позицию и нельзя считать target span источником истины.

Порядок поиска:

1. exact normalized match
2. dictionary-backed target candidates
3. phrase-level match
4. reordered window search по всему target segment
5. attached coverage для `FUNCTION`

### Exact normalized match

Примеры:

- `Tom` -> `том`
- `happy` -> `счастлив`

### Dictionary-backed candidates

Из lookup брать допустимые target-варианты.

Примеры:

- `flower` -> `цветок`, `цветы`
- `tree` -> `дерево`, `деревья`

### Phrase-level match

Если unit = `wake up`, искать не отдельные токены, а phrase candidate:

- `просыпается`
- `проснуться`

### Reordered window search

Искать по всему target segment, а не возле той же позиции.

### Attached coverage

Для `FUNCTION` не требовать отдельного русского слова, а при необходимости привязывать unit к host unit.

## Канонические проблемные кейсы

### `wake up`

Правильно:

- `wake up` = `PHRASE`
- target = `просыпаться` / `просыпается`
- `wake` и `up` attached к phrase unit
- при тапе на любой токен подсвечивается coverage phrase-блока

Неправильно:

- `wake = просыпаться`
- `up = вверх`

### `The sun is bright`

Разбор:

- `the` -> `FUNCTION`, attached to `sun`
- `sun` -> `LEXICAL`
- `is` -> `FUNCTION` или часть grammar relation
- `bright` -> `LEXICAL`

Подсветка:

- tap `sun` -> `солнце`
- tap `bright` -> `яркое`
- tap `the` -> explanation + optional host highlight
- tap `is` -> explanation + optional predicate coverage

### `Anna says`

Разбор:

- `Anna` -> `LEXICAL`
- `says` -> `LEXICAL`

Target:

- `говорит Анна`

Подсветка:

- `Anna` -> `Анна`
- `says` -> `говорит`
- `coverage_status = reordered`

### `He is happy`

Разбор:

- `He` -> `LEXICAL` или отдельный специальный pronoun subtype
- `is` -> `FUNCTION`
- `happy` -> `LEXICAL`

Target:

- `Он счастлив`

Подсветка:

- `He` -> `Он`
- `happy` -> `счастлив`
- `is` -> `absorbed` или attached к predicate

## Правила UI

### Для `LEXICAL`

Показывать:

- слово
- перевод
- target coverage
- весь учебный перевод сегмента

### Для `PHRASE`

Показывать:

- фразу
- перевод фразы
- source highlight всего phrase unit
- target highlight всего phrase coverage

### Для `FUNCTION`

Показывать:

- слово
- короткое объяснение функции
- host word
- optional host target highlight

Пример:

- `the`
- article
- указывает на конкретный объект
- относится к `sun`

### Для `GRAMMAR`

Показывать:

- блок
- что он делает
- короткий шаблон
- учебное объяснение без требования отдельного target span

### Для `META`

Показывать:

- тип meta-блока
- нормализованное значение или объяснение
- без попытки притворяться обычной лексикой narrative

## Что не делать

Нельзя:

- переводить каждый уровень отдельно и потом "голосовать"
- считать позицию основой истины
- требовать отдельный русский span для `the`, `a`, `is`
- разрешать слову внутри phrase жить своей отдельной ложной жизнью
- делать sentence translation источником истины для word lookup

## Минимальные правила V2 core

### Rule 1

`Source analysis` первичен, `target coverage` вторичен.

### Rule 2

`PHRASE > GRAMMAR > FUNCTION > LEXICAL` внутри обычного текста.

`META` всегда разбирается раньше остальных.

### Rule 3

Sentence translation не является источником истины для слова.

### Rule 4

Function words могут не иметь отдельного target span.

### Rule 5

Подсветка может быть:

- `exact`
- `reordered`
- `absorbed`
- `phrase_owned`
- `fuzzy`
- `none`

### Rule 6

При тапе смысл даёт `unit lookup`, а не `target span`.

## Что делать первым

До переписывания matching нужно ввести минимум:

- `unit_type`
- `attached_to_unit_id`
- `phrase_owner_unit_id`
- `coverage_status`

Без типов unit-ов новый pipeline снова начнёт матчить всё одинаково и повторит ошибки legacy core.

## Порядок реализации V2

### Этап 1. Source Unit Layer

- ввести канонические unit types
- реализовать source tokenizer
- реализовать source-first unit detector
- покрыть ручными примерами все базовые типы

### Этап 2. Lookup Layer

- ввести `LookupResult`
- разделить lookup для `LEXICAL`, `PHRASE`, `FUNCTION`, `GRAMMAR`, `META`
- перестать зависеть от target span как от смыслового источника

### Этап 3. Target Coverage Layer

- ввести `TargetCoverage`
- реализовать `exact`, `reordered`, `absorbed`, `phrase_owned`, `none`
- искать coverage по unit semantics, а не по позиции

### Этап 4. Tap Payload + UI Adapter

- строить `TapPayload` из V2-сущностей
- подключить V2 к reader shell через адаптер
- не ломать legacy UI контур на старте

### Этап 5. Migration

- законсервировать текущий core как legacy
- держать V1 и V2 параллельно
- прогонять оба контура на одном regression-наборе
- переводить reader/detail/cards на V2 только после стабилизации

## Критерий успеха V2

Новый core считается лучше старого, если:

- source-unit можно объяснить простыми правилами
- phrase cases не разваливаются на ложные word-level переводы
- function words не требуют фальшивого target span
- reordered cases работают без позиционных костылей
- tap UX даёт корректный lookup даже при слабом target coverage
- desktop/mobile используют один и тот же смысловой contract
