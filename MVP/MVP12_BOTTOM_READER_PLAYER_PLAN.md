# MVP12 — Bottom Reader Player Plan

## 1. Цель этапа

Перевести управление воспроизведением TTS из технической боковой панели в отдельный reader-first player, встроенный в нижнюю часть экрана.

Итог этапа:

- playback controls больше не живут в `TtsPanel`
- в reader появляется нижний полупрозрачный player bar
- player bar можно свернуть и развернуть
- текст книги не перекрывается сверху
- `Generate` и `Overwrite` остаются отдельно как generation controls

## 2. Главный принцип

Не делать:

- playback controls внутри технической TTS-панели
- плавающий блок поверх текста книги
- отдельные разрозненные кнопки `Start`, `Pause`, `Resume`, `Stop` в настройках и боковых панелях

Делать:

`Generation Controls` отдельно

и

`Bottom Reader Player` отдельно

То есть:

- генерация и перегенерация живут в настройках / generation panel
- воспроизведение живёт внизу reader как отдельный player layer

## 3. Новая продуктовая модель

### 3.1 Generation layer

Должен содержать:

- выбор голоса
- выбор playback speed preset
- `Generate`
- `Overwrite`

Generation layer отвечает только за:

- подготовку аудио
- перегенерацию
- выбор playback speed preset как пользовательской настройки

### 3.2 Playback layer

Должен содержать:

- `Stop`
- `Prev segment`
- `Play / Pause`
- `Next segment`

Playback layer отвечает только за:

- запуск готового audio
- паузу
- остановку
- переходы между сегментами

## 4. Новая нижняя панель player

### 4.1 Расположение

Панель должна жить:

- внизу экрана reader
- поверх нижней кромки экрана
- не над текстом книги

Важно:

- текст reader не должен перекрываться верхним overlay
- player должен восприниматься как отдельный bottom control bar

### 4.2 Внешний вид

Панель должна быть:

- узкой
- полупрозрачной
- визуально лёгкой
- примерно по ширине reader area, а не обязательно на весь экран

Поведение:

- desktop: центрированная нижняя панель
- mobile: нижняя панель во всю удобную ширину safe area

## 5. Кнопки player

### 5.1 Состав

Слева направо:

- `Stop`
- `Prev`
- крупная центральная `Play / Pause`
- `Next`

### 5.2 Что убирается из старой UI-модели

Из reader-facing playback UI нужно убрать:

- отдельную кнопку `Start`
- отдельные `Pause` и `Resume`
- playback-кнопки из `TtsPanel`
- playback-кнопки из mobile settings player section

### 5.3 Новая логика центральной кнопки

Центральная кнопка работает так:

- если playback ещё не запущен, но есть готовый job:
  - запускает воспроизведение
- если playback идёт:
  - ставит на паузу
- если playback на паузе:
  - продолжает

То есть:

- `Play / Pause` становится одной основной кнопкой

## 6. Stop

Кнопка `Stop` должна:

- остановить player
- сбросить playback state job в `idle`
- сбросить текущий segment index в начало

## 7. Prev / Next

Кнопки `Prev / Next` должны:

- переключать сегменты внутри текущего активного job
- работать только если есть текущий playable job

## 8. Collapse / Expand

### 8.1 Состояния

Player bar должен иметь два состояния:

- `expanded`
- `collapsed`

### 8.2 Expanded

В expanded состоянии видны:

- все playback controls

### 8.3 Collapsed

В collapsed состоянии остаётся:

- только тонкая нижняя ручка / полоска
- едва заметная стрелка

### 8.4 Индикатор

Нужен минимальный индикатор:

- если панель развёрнута:
  - стрелка вниз
- если панель свёрнута:
  - стрелка вверх

Задача индикатора:

- не бросаться в глаза
- но показывать, что player можно раскрывать и скрывать

## 9. Поведение player bar

### 9.1 Если генерации нет

Если нет готового playable job:

- `Play / Pause` disabled
- `Prev` disabled
- `Next` disabled
- `Stop` disabled

### 9.2 Если job генерируется

Если generation ещё идёт:

- playback controls disabled

### 9.3 Если job готов

Если есть готовый job:

- `Play` активен
- `Prev/Next` активны по контексту
- `Stop` активен после старта playback

## 10. Источник playable job

Нужна единая логика выбора playable job.

Playable job должен определяться через:

- выбранный голос
- текущую книгу

Playback speed preset не должен создавать новый job.

## 11. Что должно остаться в TTS panel / settings

После этапа в generation UI должны остаться только:

- voice selector
- speed preset selector
- `Generate`
- `Overwrite`

Не должно остаться:

- `Start`
- `Stop`
- `Pause`
- `Resume`
- `Prev`
- `Next`

## 12. Desktop

На desktop нужно:

- убрать playback buttons из боковой TTS-панели
- встроить bottom player в `ReaderScreen`
- оставить generation controls в боковой панели

## 13. Mobile

На mobile нужно:

- убрать playback buttons из `MobileSettingsScreen`
- встроить bottom player прямо в `MobileReaderScreen`
- generation controls оставить в settings / generation section

## 14. Техническая стратегия

Нужен новый widget, например:

- `ReaderPlaybackBar`

Он должен быть переиспользуемым:

- desktop
- mobile

Минимальные входы:

- `expanded/collapsed`
- `hasPlayableJob`
- `isPlaying`
- `isPaused`
- callbacks:
  - `onToggleExpand`
  - `onPlayPause`
  - `onStop`
  - `onPrev`
  - `onNext`

## 15. Что не входит в MVP12

На этом этапе не нужно делать:

- waveform
- timeline scrubbing
- drag seek
- advanced chapter navigation
- volume control
- progress scrubber
- отдельный mini-player outside reader

## 16. Порядок реализации

### Этап 1. Зафиксировать новую UI-границу

- generation controls отдельно
- playback controls отдельно

### Этап 2. Создать `ReaderPlaybackBar`

- expanded/collapsed states
- базовая разметка кнопок

### Этап 3. Подключить desktop reader

- убрать playback controls из `TtsPanel`
- вставить bottom bar в `ReaderScreen`

### Этап 4. Подключить mobile reader

- убрать playback controls из mobile settings TTS section
- вставить bottom bar в `MobileReaderScreen`

### Этап 5. Свести логику `Play/Pause`

- единая центральная кнопка вместо `Start + Pause + Resume`

### Этап 6. Проверить collapse / expand UX

- desktop
- mobile

## 17. Критерии готовности

Этап считается завершённым, если:

- playback controls больше не находятся в `TtsPanel`
- playback controls больше не находятся в mobile settings TTS section
- в reader есть bottom player bar
- panel можно свернуть и развернуть
- `Play / Pause` работает как одна центральная кнопка
- `Stop`, `Prev`, `Next` работают из нижней панели
- генерация и playback визуально и логически разделены
- текст книги не перекрывается верхними playback controls

## 18. Главный ожидаемый результат

После `MVP12` reader в LEXO должен ощущаться как:

- экран чтения
- с нормальным нижним player

а не как технический TTS-экран с набором служебных кнопок.
