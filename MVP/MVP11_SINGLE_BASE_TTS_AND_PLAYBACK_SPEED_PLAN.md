# MVP11 — Single Base TTS And Playback Speed Plan

## 1. Цель этапа

Упростить и стабилизировать TTS-контур LEXO, убрав multi-generation по speech speed и разделив:

- `качество синтеза`
- `скорость прослушивания`

Итог этапа:

- TTS генерируется в одном стабильном базовом режиме
- speed presets больше не меняют `rate`, `pause_scale` и segmentation policy
- slow/normal/fast становятся отдельным playback-layer
- качество базовой речи перестаёт зависеть от low-speed hacks
- TTS pipeline становится дешевле, проще и предсказуемее

## 2. Главный принцип

Не делать:

- отдельную генерацию аудио под каждый speed preset
- `target_wpm -> rate + pause_scale + segmentation`
- специальный low-speed native режим через `rate = 0.60`
- попытку "додавить" slow listening через паузы `x3`
- разный chunk policy в зависимости от speech speed

Делать:

`Normalized Text -> Stable Segmentation -> Stable TTS Generation -> Playback Speed Layer`

То есть:

- TTS отвечает только за чистую базовую речь
- speed presets отвечают только за темп прослушивания

## 3. Почему нужен этап

Текущее состояние после `MVP5/MVP6` смешивает в одном speech preset сразу несколько осей:

- `rate`
- `pause_scale`
- segmentation policy
- cache split по profile

Из-за этого:

- low-speed режимы деградируют по качеству
- генерация становится дороже по времени и storage
- архитектура усложняется без гарантии лучшего результата
- TTS jobs по сути моделируют не "голос", а смесь синтеза и player behavior

Новая модель должна вернуть правильную границу ответственности:

- `TTS` генерирует качественную базу
- `Player/Post-process` управляет скоростью восприятия

## 4. Новый продуктовый принцип

### Было

- `Start 90`
- `Transition 120`
- `Podcast 145`
- `Hardcore 200`

Каждый preset управлял:

- `target_wpm`
- `rate`
- `pause_scale`
- `chunk policy`
- отдельным audio cache

### Стало

Есть одна базовая генерация:

- один `voice`
- один `generation profile`
- один `rate`
- один `pause profile`
- одна `segmentation policy`

И есть отдельные режимы прослушивания:

- `Slow`
- `Normal`
- `Fast`

Они управляют только playback speed.

## 5. Новый TTS pipeline

Новый pipeline должен быть таким:

1. raw text
2. text normalization
3. stable segmentation
4. TTS generation with fixed base rate
5. ready audio segments
6. playback speed layer
7. playback in reader

Главная идея:

- генерировать один раз
- слушать в разных скоростях

## 6. Базовая генерация

### 6.1 Базовый rate

На первом безопасном проходе базовый режим принимается как:

- `rate = 1.0`

Это не означает, что `1.0` навсегда лучший вариант.
Это означает:

- нужен один инженерно чистый baseline
- baseline должен быть понятным
- baseline должен быть легко отлаживаемым

Если позже тесты покажут, что глобально лучший clean baseline это `0.95` или `0.90`, это можно будет изменить отдельным решением.

Но после первого runtime-прогона этап допускает калибровку clean baseline.

Текущий рабочий baseline для проекта:

- `fixed_rate = 0.89`

### 6.2 Базовые паузы

Паузы должны определяться только структурой текста:

- phrase pause
- sentence pause
- paragraph pause
- heading pause

Запрещено:

- умножать паузы от speed preset
- раздувать pause profile ради slow listening

### 6.3 Базовая segmentation policy

Segmentation должна оставаться структурной:

- `paragraph -> sentence -> phrase -> chunk`

Но policy должна быть одной и стабильной.

Нельзя:

- иметь отдельный chunk policy для `90`, `120`, `145`, `200`

Нужно:

- выбрать один хороший baseline policy для clean speech

## 7. Text normalization

Перед TTS нужен отдельный нормализующий слой.

### 7.1 Что должно нормализоваться

- время:
  - `7:00 AM` -> speech-friendly form
- номера глав:
  - `Chapter 1` -> speech-friendly form
- мусорные переносы
- лишние разрывы строк
- нестабильные кавычки
- нестабильные тире
- двоеточия и другие знаки в проблемных позициях
- артефакты исходного книжного текста

### 7.2 Что не должно происходить

- нормализация не должна ломать визуальный reader text
- нормализация не должна переписывать книгу для UI

Нужно разделение:

- `reader/source text`
- `tts synthesis text`

## 8. Playback speed layer

### 8.1 Новый смысл speed preset

Speed preset больше не является speech generation profile.

Теперь это:

- playback behavior preset

### 8.2 Базовые пресеты

На первом проходе:

- `Slow`
- `Normal`
- `Fast`

Пример разумных скоростей:

- `Slow = 0.85x`
- `Normal = 1.00x`
- `Fast = 1.15x`

Это стартовые продуктовые значения, не окончательная физика.

### 8.3 Ограничения

На этапе `MVP11` не нужно:

- уходить в экстремальные slow values
- имитировать `90 WPM native speech`
- строить сложную математику пересчёта "реального WPM"

Цель этапа:

- дать комфортный темп прослушивания
- не ломая качество синтеза

## 9. Что нужно убрать из текущей модели

### 9.1 Из speech profiles

Нужно отказаться от:

- `BASE_WPM`
- `RATE_MIN`
- `RATE_MAX`
- `target_wpm -> raw_rate`
- special case для `<=95`
- `pause_scale` как функции WPM

### 9.2 Из segmentation policy

Нужно убрать:

- per-speed chunk policy
- зависимость segmentation от speech speed

### 9.3 Из storage/job модели

TTS job больше не должен описывать speed generation preset.

Он должен описывать:

- книгу
- голос
- generation profile version
- статус генерации
- сегменты

Playback speed не должен требовать нового generation job.

## 10. Что должно остаться

Нужно сохранить:

- разделение `Generate` и `Start`
- background generation
- прогресс генерации
- segment-based playback
- кэширование audio
- overwrite-сценарий перегенерации
- reader integration
- mobile audio download flow

То есть `MVP11` не отменяет существующий TTS-контур целиком.
Он упрощает только ось speed generation.

## 11. Новая модель данных

### 11.1 Generation profile

Нужен один стабильный generation profile.

Минимально он должен хранить:

- `profile_id`
- `label`
- `tts_rate`
- `segmentation_version`
- `normalization_version`
- `pause_profile_version`

На первом проходе допускается даже более простая модель:

- один implicit default profile

### 11.2 Playback speed preset

Отдельная модель для UI/player:

- `id`
- `label`
- `speed`

Например:

- `slow`
- `normal`
- `fast`

### 11.3 Job identity

Если generation у нас одна, то job identity должна определяться не speed preset, а:

- `book_id`
- `voice_id`
- `generation_profile`

То есть:

- одно сгенерированное основание на голос
- несколько вариантов воспроизведения без новой генерации

## 12. UI модель после MVP11

### 12.1 Что должен видеть пользователь

Вместо старого выбора WPM-профиля пользователь видит:

- выбор голоса
- `Generate`
- `Overwrite`
- `Start`
- `Stop`
- выбор playback speed:
  - `Slow`
  - `Normal`
  - `Fast`

### 12.2 Что больше не должен видеть пользователь

Не нужно показывать:

- `90`
- `120`
- `145`
- `200`
- `target_wpm`
- технические distinctions generation profiles

### 12.3 UX правило

Speed selector не должен создавать новый generation job.

Он должен:

- мгновенно менять playback mode
- не инвалидировать TTS cache

## 13. Mobile и desktop

Новая модель должна быть одинаковой для desktop и mobile.

Одинаково:

- одна базовая генерация на host
- одинаковый generation contract
- одинаковые speed presets

Различаться может только presentation:

- desktop side panel
- mobile settings / sheet / compact controls

## 14. API contract после MVP11

### 14.1 Generate API

Генерация больше не принимает speed preset как generation-level параметр.

Нужен контракт вида:

- `book_id`
- `voice_id`
- optional overwrite flag

На первом этапе допустимо временно оставить старое поле `level_ids` для обратной совместимости, но новая логика должна его игнорировать или свести к одному default profile.

### 14.2 Playback API / state

Нужен отдельный playback-speed state:

- текущий `speed preset`
- возможно численное значение speed

Этот state не должен влиять на job generation identity.

## 15. Порядок реализации

### Этап 1. Зафиксировать новый продуктовый контракт

- утвердить single-base generation model
- утвердить fixed rate
- утвердить speed presets

### Этап 2. Упростить backend speech profile logic

- убрать WPM-derived generation logic
- зафиксировать base rate
- убрать low-speed pause hacks

### Этап 3. Зафиксировать stable segmentation

- выбрать один chunk policy
- отвязать segmentation от speed preset

### Этап 4. Ввести text normalization layer

- отдельный preprocessing для TTS synthesis text

### Этап 5. Перестроить job/cache identity

- убрать split по old speed generation presets
- оставить generation cache на голос + базовый профиль

### Этап 6. Перестроить UI

- убрать WPM presets из UI
- добавить `Slow / Normal / Fast`

### Этап 7. Подключить playback speed layer

- desktop
- mobile

### Этап 8. Перепроверить overwrite и mobile audio

- overwrite должен перегенерировать базу
- playback speed не должен ломать локальный mobile audio flow

## 16. Что не входит в MVP11

На этом этапе не нужно делать:

- сложный DSP research по нескольким алгоритмам time-stretch
- production-grade studio audio mastering
- вычисление "реального WPM" по итоговому аудио
- десятки speed presets
- отдельную voice cloning логику
- новую TTS модель

## 17. Критерии готовности

Этап считается завершённым, если:

- TTS генерируется в одном базовом режиме
- `rate` больше не зависит от speech preset
- `pause_scale` больше не зависит от speech preset
- segmentation больше не зависит от speech preset
- UI больше не показывает `90/120/145/200`
- UI показывает `Slow/Normal/Fast`
- смена speed preset не создаёт новый generation job
- overwrite работает для базовой генерации
- mobile и desktop используют один и тот же generation contract

## 18. Главный ожидаемый результат

После `MVP11` TTS в LEXO должен стать:

- проще
- дешевле
- стабильнее
- чище по качеству
- легче для поддержки

А speed presets должны превратиться из unstable speech-generation hacks в нормальный playback layer.
