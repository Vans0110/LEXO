# MVP13 — Stable Source Render Plan

## 1. Цель этапа

Убрать из frontend повторную токенизацию `sourceText` и перевести reader на рендер исходного текста из backend payload, чтобы снять гарантированный источник смещений между:

- визуально нажатым словом
- выбранной сущностью в UI
- `tapUnitId`
- верхним переводным контекстом

Итог этапа:

- frontend больше не угадывает слова через regex
- reader рендерит исходный текст из стабильной payload-структуры
- тап идёт по backend-данным, а не по `wordIndex`
- текущая unit-level логика выбора сохраняется
- текущий `translationLeft/Focus/Right` сохраняется без переработки alignment на этом этапе

## 2. Почему нужен отдельный этап

По текущему коду проблема состоит из двух слоёв:

### 2.1 Технический слой

Сейчас frontend делает повторную токенизацию строки:

- файл: `app/lib/src/widgets/interactive_paragraph_text.dart`
- функция: `_tokenize`
- затем сопоставляет `sourceText` tokens с `words[]` по порядку через `wordIndex`

Это означает:

- любое расхождение токенизации backend/frontend сдвигает соответствие
- пунктуация и специальные токены легко ломают хвост абзаца
- UI может обработать не тот `ParagraphWordItem`, на который визуально нажал пользователь

### 2.2 Архитектурный слой

Сейчас backend строит interaction pipeline так:

- перевод делается по предложениям
- затем строится heuristic word mapping
- затем source words группируются в `tap units`
- затем UI выглядит как word-level interface, хотя данные по сути unit-level

Этот слой не чинится в `MVP13`.

`MVP13` нужен, чтобы сначала убрать гарантированный frontend-рассинхрон и только потом отдельно разбирать backend alignment.

## 3. Фактическое текущее состояние кода

### 3.1 Backend payload сейчас

Сейчас reader payload содержит:

- `ParagraphItem.sourceText`
- `ParagraphItem.targetText`
- `ParagraphItem.words`

Файл:

- `app/lib/src/models.dart`

`ParagraphWordItem` сейчас содержит:

- `id`
- `text`
- `orderIndex`
- `anchorWordId`
- `tapUnitId`
- `sourceUnitText`
- `translationSpanText`
- `translationLeftText`
- `translationFocusText`
- `translationRightText`

### 3.2 Backend сборка payload сейчас

Reader payload формируется в:

- `engine/storage.py`
- метод `get_paragraphs`

Сейчас backend отдаёт:

- `source_text`
- `target_text`
- `words`

Но не отдаёт отдельную стабильную структуру source-токенов для прямого рендера.

### 3.3 Frontend рендер сейчас

Текущий рендер строится так:

- `InteractiveParagraphText` получает `sourceText`
- вызывает `_tokenize(sourceText)`
- на каждый word-token берёт `words[wordIndex]`
- по tap вызывает `onWordTap(word)`

Файл:

- `app/lib/src/widgets/interactive_paragraph_text.dart`

Это и есть главный технический дефект этапа.

## 4. Что меняем на этапе

На этом этапе меняется только источник рендера исходного текста.

Не меняется:

- backend sentence-level translation pipeline
- heuristic alignment в `engine/word_alignment.py`
- логика `translationLeftText / translationFocusText / translationRightText`
- grouping в `tap units`
- верхняя translation bar

Меняется:

- backend reader payload должен начать отдавать отдельный список source tokens
- frontend должен рендерить только эти tokens
- tap должен идти через token payload, а не через догадку из regex split

## 5. Новая продуктовая модель этапа

Нужно честно разделить три слоя:

### 5.1 Source render layer

Отвечает только за:

- что именно рисуется в абзаце
- в каком порядке
- где слово
- где знак препинания
- где пробел

Источник истины:

- `sourceTokens[]` из backend payload

### 5.2 Selection layer

Отвечает только за:

- что реально считается выбранной сущностью при тапе

На этом этапе выбранной сущностью остаётся:

- `tap unit`

То есть:

- пользователь тапаeт токен
- токен знает `tapUnitId`
- UI выделяет соответствующий unit

### 5.3 Translation context layer

Отвечает только за:

- что показывать сверху

На этом этапе без изменений:

- берём `translationLeftText`
- `translationFocusText`
- `translationRightText`

из уже подготовленного backend payload выбранного unit/word item

## 6. Минимальная новая payload-структура

### 6.1 Что нужно добавить

В `ParagraphItem` нужно добавить отдельную коллекцию source-токенов.

Рабочее имя для этапа:

- `tokens`

### 6.2 Что должен хранить токен

Минимально:

- `id`
- `text`
- `kind`
- `orderIndex`
- `tapUnitId`
- `wordId`

### 6.3 Смысл полей

- `id`
  - стабильный id токена внутри абзаца
- `text`
  - точный текст токена, который нужно рендерить
- `kind`
  - например:
    - `word`
    - `whitespace`
    - `punctuation`
- `orderIndex`
  - порядок в абзаце
- `tapUnitId`
  - к какому unit относится токен
  - для punctuation может быть `null`
- `wordId`
  - если токен соответствует source-word payload
  - нужен для прямого доступа к `ParagraphWordItem`

## 7. Источник этих токенов

На этапе `MVP13` нельзя позволять frontend самому восстанавливать токены.

Токены должны строиться на backend из той же source-структуры, которая уже используется для reader words.

Это нужно для того, чтобы:

- backend и frontend использовали один и тот же source order
- UI не терял синхрон при пунктуации и сложных токенах
- один и тот же `tapUnitId` жил и в рендере, и в выборе

## 8. Границы этапа

### 8.1 Что входит

- анализ текущего backend payload
- добавление source-tokens в reader payload
- добавление frontend models под новые tokens
- замена `InteractiveParagraphText` на рендер по payload tokens
- сохранение текущего tap behavior через `tapUnitId`
- сохранение текущего translation context behavior

### 8.2 Что не входит

- переписывание `word_alignment.py`
- новый alignment engine
- word-level precision fix на backend
- range selection
- drag selection
- новый словарный режим
- новая translation context logic
- переработка paragraph/segment storage model

## 9. Пофайловый план анализа и правок

### 9.1 Backend

- `engine/storage.py`
  - понять, где именно удобнее собирать `tokens`
  - встроить `tokens` в `get_paragraphs`
  - сохранить обратную совместимость с текущим `words`

- `engine/word_alignment.py`
  - использовать только как источник фактической source token/order информации, если это возможно без нового alignment-переписывания
  - не менять heuristic mapping на этом этапе без отдельного решения

### 9.2 Frontend models

- `app/lib/src/models.dart`
  - добавить модель `ParagraphTokenItem`
  - расширить `ParagraphItem`

### 9.3 Frontend render

- `app/lib/src/widgets/interactive_paragraph_text.dart`
  - убрать `_tokenize(sourceText)`
  - убрать mapping через `wordIndex`
  - перейти на рендер `tokens[]`
  - tap по токену должен находить связанный `ParagraphWordItem` по `wordId`

- `app/lib/src/widgets/reader_text_flow.dart`
  - обновить прокидывание paragraph payload в новый renderer, если потребуется

### 9.4 Screens

- `app/lib/src/screens/reader_screen.dart`
- `app/lib/src/ui/mobile/screens/mobile_reader_screen.dart`

Нужно проверить:

- не зависит ли highlight / selected state от старого поведения renderer

## 10. Ожидаемое улучшение после этапа

После `MVP13` должно улучшиться следующее:

- меньше ложных смещений при тапе
- меньше промахов по словам из-за пунктуации
- меньше случаев, где визуально выбран один кусок, а data payload соответствует другому
- backend alignment можно будет анализировать чище, без примеси фронтовой regex-ошибки

Важно:

`MVP13` не гарантирует, что heuristic translation mapping станет точным.

Он должен убрать именно frontend-рассинхрон.

## 11. Как понять, что этап выполнен

Критерии готовности:

- `InteractiveParagraphText` больше не содержит frontend regex-токенизацию строки абзаца
- рендер текста строится только из backend payload tokens
- нажатие по токену вызывает выбор через связанный `wordId` / `tapUnitId`
- текущая верхняя translation bar продолжает работать без изменений в её логике
- desktop и mobile reader используют один и тот же новый paragraph render contract

## 12. Риск этапа

Главный риск:

- backend может не иметь сейчас готовой source-token структуры, пригодной для прямого рендера

Если это подтвердится по коду, допустимый путь только один:

- добавить минимальный backend token payload

Недопустимый путь:

- снова собирать tokens на frontend из `sourceText`

## 13. Почему это следующий правильный шаг

Сейчас нельзя честно оценить качество backend alignment, пока frontend сам создаёт дополнительный слой ошибок.

Поэтому порядок должен быть такой:

1. убрать фронтовое угадывание слов
2. зафиксировать стабильный render contract
3. повторно проверить реальные остаточные alignment bugs
4. только потом принимать решение по следующему этапу backend mapping
