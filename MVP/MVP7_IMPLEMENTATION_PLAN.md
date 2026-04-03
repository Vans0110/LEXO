# MVP7 Implementation Plan

## Цель

Переделать `ReaderScreen` из paragraph-card view в reader-first view:

- основной контент справа — поток английского текста
- постоянный русский перевод из потока убрать
- сверху добавить фиксированный `TranslationContextBar`
- по нажатию на английское слово обновлять верхний блок перевода
- текущую TTS-панель не ломать
- текущий backend и `paragraph_index` не менять

## Что меняется

### Reader layout

- убрать `Card`-рендеринг параграфов
- убрать `§ N`
- убрать `SRC/TGT`
- убрать постоянный `targetText` из основного потока
- оставить справа reader layout:
  - сверху `TranslationContextBar`
  - снизу поток английских абзацев

### Interaction

- сделать интерактивный рендер английского текста по словам
- при нажатии на слово:
  - сохранить `paragraph_index`
  - подсветить выбранное слово
  - обновить верхний translation bar

### State

В `ReaderScreen` хранить:

- `selectedParagraphIndex`
- `selectedWordIndex`
- `selectedWord`
- `translationFocusText`
- `translationContextText`

## Новые файлы

- `app/lib/src/widgets/translation_context_bar.dart`
- `app/lib/src/widgets/interactive_paragraph_text.dart`
- `app/lib/src/reader/translation_context_builder.dart`

## Архитектура

- `ReaderScreen` управляет state и layout
- `InteractiveParagraphText` рендерит английский абзац и отдаёт событие выбора слова наверх
- `TranslationContextBar` показывает translation context
- `translation_context_builder.dart` содержит эвристику сборки верхней строки перевода

## Эвристика перевода для MVP7

- backend не менять
- использовать `targetText` текущего абзаца
- разбивать `targetText` на слова
- выбирать опорное слово пропорционально `wordIndex` внутри source paragraph
- собирать короткий контекст вокруг опорного слова

## Критерии готовности

- paragraph cards исчезли
- основной reader area показывает только английский текст
- верхний fixed translation bar есть
- по нажатию на слово верхний блок обновляется
- выбранное слово визуально подсвечивается
- TTS-панель работает как раньше
- `saveReaderPosition(paragraph_index)` не сломан

