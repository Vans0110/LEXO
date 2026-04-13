# MVP16.4 — Typed Study Segmenter Plan

## 1. Цель этапа

Перестроить сегментацию в LEXO так, чтобы сегмент перестал быть просто предложением и стал минимальной обучаемой единицей.

Главная идея:

- `sentence != segment`
- `segment = minimal teachable unit`

Этот этап нужен, чтобы уменьшить:

- свободный пересказ в NLLB
- смысловые добавки вроде `справляюсь`
- смещение alignment на смешанных сегментах
- распад формул, greeting-фраз и reporting clauses

## 2. Проблема текущего состояния

Сейчас базовая сегментация в проекте слишком близка к модели:

- `sentence = segment`

Это слишком грубо для учебного пайплайна.

Когда в один сегмент попадают одновременно:

- формула
- реплика
- кто сказал
- время
- два действия
- copula + длинное окружение

модель перевода начинает не переводить, а интерпретировать.

Типичные последствия:

- `I am great, thank you! Anna says.` -> свободный пересказ вместо учебного перевода
- `How are you? Tom asks.` -> формула и reporting clause смешиваются
- `Goodnight, Luna, Tom whispers.` -> greeting / name / reporting живут в одном сегменте

## 3. Новый принцип сегментации

Нужен typed segmenter.

Он должен резать не по грамматическим предложениям, а по учебным паттернам.

Первичные типы сегментов:

- `formula_phrase`
- `greeting_phrase`
- `reporting_clause`
- `time_phrase`
- `copula_subject`
- `copula_predicate`
- `simple_action`
- `prepositional_phrase`
- `fallback_sentence`

Опционально позже:

- `noun_phrase`
- `phrasal_verb_phrase`
- `conjoined_predicate`

## 4. Что обязательно выносить в отдельные сегменты

### 4.1 Формулы

- `how are you`
- `thank you`
- `good morning`
- `goodnight`
- `hello`

### 4.2 Reporting clauses

- `Tom says`
- `Anna asks`
- `he whispers`
- `the cat says`

### 4.3 Time phrases

- `at 7:00 AM`
- `in the afternoon`
- `at 10:00 AM`

### 4.4 Copula patterns

Минимум:

- `It is`
- `He is happy`
- `The sun is bright`

Важный целевой паттерн:

- `X is Y -> [X] [is Y]`

### 4.5 Реплики

Нельзя держать вместе:

- greeting + name + reporting
- formula + reporting

Примеры:

- `"Good morning, Luna!" Tom says.`
  - `[Good morning]`
  - `[Luna]`
  - `[Tom says]`

- `"I am great, thank you!" Anna says.`
  - `[I am great]`
  - `[thank you]`
  - `[Anna says]`

## 5. Что нельзя держать в одном сегменте

### 5.1 Речь + кто сказал

Плохо:

- `"Good morning, Luna!" Tom says.`

### 5.2 Формула + reporting

Плохо:

- `How are you? Tom asks.`

### 5.3 Время + действие

Плохо:

- `At 10:00 AM, Tom goes to the park.`

### 5.4 Два независимых действия

Плохо:

- `He goes to the kitchen and sees his cat.`

### 5.5 Широкий copula-block

Плохо:

- `It is a very good day.`

## 6. Что нельзя дробить слишком мелко

Этот этап не должен превращать текст в бессмысленные огрызки.

Запрещённые результаты:

- `[and toast]`
- `[Tom looks]` если потерян `looks out`
- любой кусок, который перестаёт быть устойчивой переводимой единицей

Главное правило:

если после разреза кусок перестаёт быть самостоятельной переводимой учебной единицей, такой split не допускается.

## 7. Правила приоритета

Порядок работы нового segmenter-а:

1. `formula_phrase`
2. `greeting_phrase`
3. `reporting_clause`
4. `time_phrase`
5. `copula split`
6. `coordination split`
7. `fallback_sentence`

То есть сначала устойчивые учебные блоки, потом общая нарезка.

## 8. Что нужно изменить в коде

### 8.1 `engine/segmenter.py`

Добавить новый путь:

- `split_study_segments(text: str) -> list[dict]`

Каждый segment item должен содержать минимум:

- `text`
- `type`
- `source_start`
- `source_end`
- `meta`

Нужны отдельные matcher-ы для:

- formulas
- greetings
- reporting clauses
- time phrases
- `X is Y`
- контролируемого split по `and / but`

### 8.2 `engine/storage.py`

Новый typed segmenter должен быть встроен в import pipeline.

Нужно:

- перестать сохранять только sentence-level segments
- сохранять `segment_type`
- желательно сохранять `segment_meta_json`

Это позволит дальше использовать тип сегмента:

- в translator
- в word alignment
- в reader/debug payload

### 8.3 `engine/translator.py`

Перевод должен стать type-aware.

Нужен путь вроде:

- `translate_study_segment(segment)`

Поведение по типам:

- `formula_phrase`
  - phrase-first translation
  - fallback в NLLB только если правила не сработали
- `greeting_phrase`
  - phrase-first
- `reporting_clause`
  - constrained translation
- `time_phrase`
  - rule-first
- `copula_predicate`
  - более структурно близкий перевод
- `fallback_sentence`
  - обычный MT path

### 8.4 `engine/word_alignment.py`

Alignment должен получать знание о типе сегмента.

Минимум:

- `segment_type`
- `segment_meta`

Это нужно, чтобы alignment не угадывал post factum, что перед ним:

- formula
- greeting
- reporting
- copula block

## 9. Порядок внедрения

### Шаг 1

Добавить typed segmenter в `engine/segmenter.py`

### Шаг 2

Подключить typed segments в `engine/storage.py`

### Шаг 3

Начать сохранять:

- `segment_type`
- `segment_meta_json`

### Шаг 4

Добавить type-aware translation path в `engine/translator.py`

### Шаг 5

Подключить `segment_type` в `engine/word_alignment.py`

## 10. Первый обязательный scope

Не надо пытаться закрыть весь английский язык сразу.

Первый обязательный набор:

- `formula_phrase`
- `greeting_phrase`
- `reporting_clause`
- `time_phrase`
- `it_be`
- `X is Y`

Этого достаточно, чтобы улучшить:

- `How are you? Tom asks.`
- `I am great, thank you! Anna says.`
- `Goodnight, Luna, Tom whispers.`
- `In the afternoon, Tom goes home.`
- `It is a beautiful day.`

## 11. Что не входит в этот этап

- пост-обработка перевода как главный механизм
- новый UI для grammar explanation
- rebuild старых книг
- полная синтаксическая parser-system
- агрессивное дробление каждой координатной конструкции

## 12. Критерии готовности

Этап считается успешным, если:

- formulas больше не смешиваются с reporting clauses
- time phrases стабильно отделяются
- `I am great` перестаёт рождать лишние смысловые добавки из-за широкого сегмента
- `How are you` стабильно живёт как formula block
- `Goodnight` и `Good morning` не смешиваются с авторской ремаркой
- alignment на этих кейсах становится проще и стабильнее

## 13. Главный ожидаемый результат

После `MVP16.4`:

- перевод перестанет ломаться уже на стадии сегментации
- NLLB будет получать более чистые и учебно-подходящие сегменты
- `word_alignment` будет работать поверх более здорового translation input
- часть нынешних translation/alignment проблем исчезнет без новых латок в поздних стадиях
