# MVP8 — Unified Product Plan

## 1. Цель этапа

Перевести LEXO из набора отдельных desktop-решений в единый продуктовый каркас, где:

- логика приложения общая
- набор функций общий
- состояние общее
- `Desktop UI` и `Mobile UI` — это две разные presentation-оболочки одного продукта
- `Android Emulator` используется как рабочий mobile preview на Windows
- после этого тот же `Mobile UI` идёт в iPhone pipeline

Итог этапа:

- можно нормально видеть и тестировать mobile-интерфейс
- можно продолжать развивать desktop и mobile без расхождения по логике
- появляется основа для будущей iPhone-сборки

## 2. Главный принцип

Не делать:

- отдельное приложение под Windows
- отдельное приложение под iPhone
- отдельное приложение под Android

Делать:

`Core + Shared Features + Desktop UI + Mobile UI + Platform Adapters`

То есть продукт один.
Меняются presentation и platform adapters.

## 3. Что должен дать MVP8

После завершения этапа должны существовать:

- общий слой `Core / Feature State / Actions`
- отдельный `Desktop UI`
- отдельный `Mobile UI`
- рабочий `Mobile Reader`
- рабочий `Mobile Library`
- общая логика `Reader / Translation / TTS / Saved Words / Library`
- возможность запускать mobile-flow в `Android Emulator`
- готовность проекта к следующему этапу: iPhone build pipeline

## 4. Что не входит в MVP8

На этом этапе не нужно делать:

- финальный polished iOS-продукт
- отдельный Android-specific продукт
- web
- sync/cloud accounts
- production-grade parser для английского языка
- полную дизайн-систему для всех экранов
- идеальную адаптацию под все form factors

## 5. Продуктовая формула

### Одинаково на всех платформах

- книги
- библиотека
- reader state
- reading position
- tap units
- translation context
- TTS jobs
- saved words
- feature state
- API contract

### Разное на разных платформах

- layout
- расположение control surfaces
- навигационная оболочка
- размеры и плотность элементов
- жесты
- platform APIs

## 6. Источник истины

Для следующего этапа источником истины считаются:

- код проекта
- `MVP/MVP8_UNIFIED_PRODUCT_PLAN.md`
- существующие утверждённые MVP-документы как история развития

Новые крупные функции должны сначала встраиваться в логику этого документа.

## 7. Правило синхрона desktop/mobile

Любая новая функция добавляется в таком порядке:

1. `feature name`
2. `shared state`
3. `shared actions`
4. `desktop presentation`
5. `mobile presentation`

Запрещено:

- добавлять фичу только в desktop UI без shared-слоя
- добавлять фичу только в mobile UI как отдельную логику
- хранить критичное состояние только в конкретном screen/widget

## 8. Общий слой продукта

Нужен общий слой, который не зависит от платформенного layout.

### Общие сущности состояния

- `AppShellState`
- `LibraryState`
- `ReaderState`
- `SelectionState`
- `TranslationState`
- `TtsState`
- `SavedWordsState`
- `SettingsState`

### Общие действия

- `importBook`
- `openBook`
- `deleteBook`
- `setActiveBook`
- `setBooksViewMode`
- `selectTapUnit`
- `clearSelection`
- `saveReaderPosition`
- `saveWord`
- `removeSavedWord`
- `generateTts`
- `startTts`
- `pauseTts`
- `resumeTts`
- `prevTtsSegment`
- `nextTtsSegment`
- `stopTts`
- `setTtsVoice`
- `setTtsLevel`

## 9. Shared feature map

### 9.1 Library feature

Должна быть общей для desktop/mobile.

Содержит:

- список книг
- active book
- import book
- delete book
- open book
- режим отображения списка книг
- текущий статус книги

### 9.2 Reader feature

Должна быть общей для desktop/mobile.

Содержит:

- paragraphs
- current paragraph index
- tap unit selection
- translation context data
- highlight state
- reading position save

### 9.3 Translation feature

Содержит:

- selected source unit
- target context text
- left/focus/right parts
- selection metadata

### 9.4 TTS feature

Содержит:

- profiles
- levels
- jobs
- active job
- playback state
- generation state

### 9.5 Saved Words feature

Содержит:

- список сохранённых слов
- поиск
- сортировки и фильтры
- открытие карточки/деталей

## 10. UI families

## 10.1 Desktop UI

Desktop UI должен использовать:

- широкий layout
- параллельные панели
- side panel для TTS
- больше постоянных control surfaces

Desktop не является источником истины.
Это только одна presentation-family.

### Базовые desktop-экраны

- `DesktopLibraryScreen`
- `DesktopReaderScreen`
- `DesktopSavedWordsScreen`

### Базовые desktop-widgets

- `DesktopLibraryToolbar`
- `DesktopReaderLayout`
- `DesktopTtsPanel`
- `TranslationContextBar`

## 10.2 Mobile UI

Mobile UI должен быть отдельным UX, а не “сжатым desktop”.

Принципы:

- один главный экран за раз
- вертикальный layout
- крупные тач-зоны
- bottom sheets / compact surfaces
- меньше постоянных панелей

### Базовые mobile-экраны

- `MobileLibraryScreen`
- `MobileReaderScreen`
- `MobileSavedWordsScreen`

### Базовые mobile surfaces

- `MobileTopBar`
- `MobileBottomActionBar`
- `MobileTranslationSheet` или compact translation zone
- `MobileTtsSheet`
- `MobileLibraryOptionsSheet`

## 11. Reader как центральный shared feature

Reader должен быть одним по логике и двумя по presentation.

### Общая логика reader

- рендер текста по абзацам
- tap unit selection
- continuous highlight state
- translation payload
- paragraph position save
- TTS entry points

### Desktop presentation

- translation bar сверху
- TTS panel сбоку
- широкий поток текста

### Mobile presentation

- translation zone сверху или компактная pinned area
- основной фокус на тексте
- действия через нижнюю панель или sheet
- TTS без постоянной боковой панели

## 12. Library как второй ключевой shared feature

### Общая логика library

- получение списка книг
- активная книга
- импорт
- удаление
- выбор режима отображения

### Desktop presentation

- toolbar
- list/grid/table-like layouts

### Mobile presentation

- compact list/cards
- фильтры и режимы через sheet/menu

## 13. Platform adapters

Нужно отделить platform-specific вещи от UI.

### Windows adapter

- file picker
- desktop paths
- audio/session особенности
- local process launch

### iOS adapter

- file picker
- permissions
- audio session
- safe area/platform hooks

### Android adapter

- file picker
- permissions
- audio session
- android-specific behavior

Важно:

- `ios/` и `android/` папки Flutter не являются местом для двух разных UI
- `Mobile UI` остаётся общим

## 14. Целевая структура Flutter-части

Целевое направление структуры:

```text
app/lib/src/
  core/
  features/
    app_shell/
    library/
    reader/
    translation/
    tts/
    saved_words/
    settings/
  ui/
    desktop/
      screens/
      widgets/
    mobile/
      screens/
      widgets/
  platform/
    windows/
    ios/
    android/
  api/
```

Это не требование “переписать всё сразу”.
Это целевая карта рефактора.

## 15. Этапы реализации MVP8

## Этап 1. Зафиксировать shared feature contracts

Нужно:

- определить состояния
- определить действия
- определить ownership логики

Критерий готовности:

- понятно, какие части логики считаются shared

## Этап 2. Выделить shared reader logic

Нужно:

- вынести из текущего `ReaderScreen` всё, что не зависит от desktop-layout
- оставить desktop-screen только как оболочку

Критерий готовности:

- desktop reader использует shared reader-state/actions

## Этап 3. Выделить shared library logic

Нужно:

- перестать держать library state в desktop-only представлении
- подготовить тот же feature для mobile

## Этап 4. Разделить UI по семействам

Нужно:

- выделить `ui/desktop`
- выделить `ui/mobile`
- перестать складывать оба семейства в одну плоскую папку `screens/widgets`

## Этап 5. Собрать mobile library

Минимум:

- список книг
- import
- open
- delete
- базовый режим списка

## Этап 6. Собрать mobile reader

Минимум:

- top zone
- reading area
- tap selection
- translation display
- открытие TTS controls

## Этап 7. Подключить mobile TTS presentation

Нужно:

- не переписывать TTS pipeline
- только сделать mobile presentation

## Этап 8. Прогон Android Emulator

Нужно проверить:

- влезает ли layout
- удобно ли нажимать
- не ломается ли scroll
- не разваливаются ли sheets
- работает ли reader flow

## Этап 9. Desktop/mobile parity check

Нужно проверить:

- одинаковые ли действия доступны
- одинаковая ли логика состояний
- не потеряна ли функция на одной из платформ

## 16. Android Emulator как часть MVP8

Android Emulator в этом этапе используется не как отдельный продуктовый канал, а как:

- mobile preview
- быстрый способ увидеть телефонный интерфейс на Windows
- фильтр до iPhone pipeline

### Что должно быть возможно на этом этапе

- запуск `Mobile UI`
- открытие library
- открытие reader
- тап по слову
- базовые TTS controls
- базовая навигация

### Что не нужно ожидать от Android Emulator

- iPhone-specific поведение 1:1
- финальную iOS визуальную полировку

## 17. Связь с будущей iPhone-сборкой

MVP8 должен подготовить проект к следующему этапу:

- mobile UI уже существует
- shared logic уже существует
- platform adapters не смешаны с UI
- можно подключать iOS build pipeline без переизобретения интерфейса

## 18. Минимальные критерии готовности MVP8

Этап считается завершённым, если:

- существует отдельный `Mobile UI` слой
- существует отдельный `Desktop UI` слой
- shared reader logic реально общая
- shared library logic реально общая
- новые функции можно подключать в обе presentation-family через shared state/actions
- mobile flow запускается в Android Emulator
- desktop flow не сломан
- проект стал структурно готов к iPhone pipeline

## 19. Главный продуктовый результат

После MVP8 LEXO должен перестать быть “desktop-прототипом с мечтой о mobile”.

Он должен стать:

- одним продуктом
- с одной логикой
- с двумя UI-семействами
- и с понятным путём к iPhone app
