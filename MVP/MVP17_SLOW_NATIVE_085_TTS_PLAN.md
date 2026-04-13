# MVP17 — Native Slow TTS 0.85 Without Breaking Base Playback Path

## 1. Цель

Добавить отдельную медленную генерацию TTS только для режима `Slow`, при этом:

- `Slow` должен использовать отдельный backend-generated audio path
- этот путь должен синтезироваться `Kokoro` на скорости `0.85`
- `Normal` должен остаться как сейчас:
  - базовая генерация `rate=0.89`
  - playback `1.00x`
- `Fast` должен остаться как сейчас:
  - та же базовая генерация `rate=0.89`
  - playback `1.15x`

Главное ограничение этапа:

- не трогать translation/runtime контур
- не ломать текущий single-base pipeline для `Normal/Fast`
- не возвращать широкие TTS-эксперименты, которые уже давали побочные регрессии

## 2. Что сейчас реально в коде

### Backend

- [engine/tts/speech_profiles.py](/mnt/d/Programs/LEXO/engine/tts/speech_profiles.py) хранит:
  - один generation profile:
    - `tts_rate = 0.89`
  - три playback preset:
    - `Slow = 0.85`
    - `Normal = 1.0`
    - `Fast = 1.15`
- `build_profile(level_id)` сейчас игнорирует `level_id` и всегда возвращает один и тот же `SpeechProfile`
- [engine/tts/tts_service.py](/mnt/d/Programs/LEXO/engine/tts/tts_service.py) сейчас:
  - игнорирует переданные `level_ids`
  - всегда создаёт ровно один `base` job
  - пишет audio в:
    - `data/tts/<book>/<engine>/<voice>/base`
- [engine/tts/tts_queue.py](/mnt/d/Programs/LEXO/engine/tts/tts_queue.py) строит cache key по:
  - `book_id`
  - `engine_id`
  - `voice_id`
  - `text`
  - `profile.cache_key`
- [engine/tts/tts_provider.py](/mnt/d/Programs/LEXO/engine/tts/tts_provider.py) умеет передавать `rate` в `KokoroProvider.synthesize(...)`
- [engine/tts/kokoro_runner.py](/mnt/d/Programs/LEXO/engine/tts/kokoro_runner.py) уже принимает `--speed`

### UI

- [app/lib/src/screens/reader_screen.dart](/mnt/d/Programs/LEXO/app/lib/src/screens/reader_screen.dart) и [app/lib/src/ui/mobile/screens/mobile_reader_screen.dart](/mnt/d/Programs/LEXO/app/lib/src/ui/mobile/screens/mobile_reader_screen.dart):
  - выбирают `selectedLevel`
  - всегда применяют `player.setRate(selectedLevel.playbackSpeed)`
- `_selectedJob()` в desktop/mobile ищет job только по `voice_id`
- [app/lib/src/widgets/tts_panel.dart](/mnt/d/Programs/LEXO/app/lib/src/widgets/tts_panel.dart) показывает level selector, но факт наличия генерации тоже определяет только по `voice_id`

### Вывод по текущему состоянию

Сейчас `Slow/Normal/Fast` это только playback layer.

Отдельной native slow generation в коде нет.

## 3. Что именно нужно получить

Нужна не новая универсальная TTS-система, а узкое инженерное расширение:

1. Для `Slow` backend должен генерировать отдельный audio variant:
   - `audio_variant = slow_native`
   - `generation_rate = 0.85`
2. Для `Normal` и `Fast` backend должен оставаться на текущем base-варианте:
   - `audio_variant = base`
   - `generation_rate = 0.89`
3. `Fast` не должен создавать отдельный audio cache
4. `Normal` и `Fast` должны использовать один и тот же base job
5. При выборе `Slow` player не должен повторно замедлять уже медленно сгенерированное аудио

Главная продуктовая семантика:

- `Slow` = отдельная native audio generation
- `Normal/Fast` = прежний base audio + playback speed

## 4. Главный риск, который уже был подтверждён историей

По [history/2026-04-13.md](/mnt/d/Programs/LEXO/history/2026-04-13.md) предыдущая попытка вернуть separate slow path уже ломала runtime, потому что изменения были слишком широкими:

- мутация provider внутри service
- broad level-sensitive logic по всему UI
- лишние зависимости в import chain
- weak isolation между generated audio variant и playback preset

Значит новый этап должен быть реализован узко и изолированно:

- без mutation provider
- без waveform post-process
- без новых тяжёлых импортов на старте backend
- без вмешательства в translation/storage path вне TTS таблиц и TTS manifest

## 5. Принцип безопасной реализации

Нужно разделить два понятия:

### 5.1 Playback preset

То, что выбирает пользователь в UI:

- `Slow`
- `Normal`
- `Fast`

### 5.2 Generated audio variant

То, что реально лежит в TTS cache:

- `base`
- `slow_native`

Это не одно и то же.

Связь должна быть такой:

- `Slow` -> требует `slow_native`
- `Normal` -> требует `base`
- `Fast` -> требует `base`

## 6. Минимально необходимая модель данных

### 6.1 Новые поля job/segment

В `tts_jobs` нужно добавить:

- `audio_variant TEXT NOT NULL DEFAULT 'base'`
- `native_rate REAL NOT NULL DEFAULT 0.89`

В `tts_segments` нужно добавить:

- `audio_variant TEXT NOT NULL DEFAULT 'base'`

### 6.2 Почему этого достаточно

Этого хватает, чтобы:

- хранить рядом `base` и `slow_native`
- не путать их по одному `voice_id`
- не дублировать `Fast`
- безопасно отдавать mobile manifest

### 6.3 Что не нужно добавлять на этом этапе

Не нужно:

- timestamps
- post-processed gap variants
- word-level audio metadata
- отдельные таблицы под derived audio

Это другой этап.

## 7. Изменения по backend

### 7.1 `engine/tts/tts_models.py`

Расширить `SpeechProfile`:

- `audio_variant: str`
- `native_rate: float`
- `playback_speed: float`

`cache_key` должен включать:

- `audio_variant`
- `native_rate`

Важно:

- `playback_speed` не должен участвовать в cache key для `base`
- иначе `Normal` и `Fast` снова разъедутся в разные cache entries

### 7.2 `engine/tts/speech_profiles.py`

Перестать считать `level` чисто playback-пресетом.

Нужен явный mapping:

- `Slow`
  - `audio_variant='slow_native'`
  - `native_rate=0.85`
  - `playback_speed=1.0`
- `Normal`
  - `audio_variant='base'`
  - `native_rate=0.89`
  - `playback_speed=1.0`
- `Fast`
  - `audio_variant='base'`
  - `native_rate=0.89`
  - `playback_speed=1.15`

Ключевой момент:

- UI label может продолжать показывать `Slow 0.85`
- но player не должен делать `setRate(0.85)` для native slow job
- иначе получится двойное замедление

### 7.3 `engine/tts/tts_service.py`

Нужны точечные изменения:

1. `generate_jobs(...)` должен реально учитывать выбранный `level_id`
2. Но generation identity должна строиться не по `level_id`, а по `audio_variant`
3. Нельзя удалять все jobs по `voice_id`
4. `overwrite` должен удалять только target variant:
   - `base` или `slow_native`
5. `audio_dir` должен зависеть от variant:
   - `.../<voice>/base`
   - `.../<voice>/slow_native`

Безопасный алгоритм:

- если выбран `Slow`:
  - создаём или перегенерируем `slow_native`
- если выбран `Normal` или `Fast`:
  - создаём или переиспользуем `base`

### 7.4 `engine/tts/tts_queue.py`

Никакой сложной логики не нужно.

Достаточно:

- использовать `profile.native_rate` при `provider.synthesize(...)`
- cache key строить с новым `profile.cache_key`

### 7.5 `engine/storage.py`

Нужны только additive migration и manifest update:

- миграция новых колонок в `tts_jobs`
- миграция `audio_variant` в `tts_segments`
- `_build_mobile_tts_manifest(...)` должен отдавать `audio_variant` и `native_rate`

Важно:

- не трогать translation schema
- не трогать reader payload вне TTS manifest

### 7.6 `engine/tts/tts_provider.py` и `engine/tts/kokoro_runner.py`

Архитектурно больших изменений не нужно.

Они уже поддерживают передачу speed/rate.

На этом этапе не нужно:

- менять runner output contract
- добавлять timestamps
- менять voice fallback logic

## 8. Изменения по UI

### 8.1 Основная проблема текущего UI

Сейчас job выбирается только по `voice_id`.

Это сломает новый контур, потому что у одного голоса появятся два job-варианта:

- `base`
- `slow_native`

### 8.2 Что нужно изменить

В desktop и mobile reader:

- `_selectedJob()` должен искать не просто по `voice_id`, а по:
  - `voice_id`
  - `required audio_variant`

Mapping:

- `Slow` -> `slow_native`
- `Normal/Fast` -> `base`

### 8.3 Playback logic

Player должен применять не `selectedLevel.playbackSpeed` напрямую, а эффективную playback speed:

- для `slow_native`: `1.0`
- для `base + Normal`: `1.0`
- для `base + Fast`: `1.15`

То есть правило должно зависеть от сочетания:

- выбранного level
- активного/generated audio variant

### 8.4 `tts_panel.dart`

Панель должна:

- показывать статус генерации именно для нужного variant
- `Overwrite` должен перегенерировать именно этот variant

Иначе пользователь выберет `Slow`, а UI покажет статус `base` job.

## 9. Порядок работ

### Этап 1. Backend model split

Изменить:

- `engine/tts/tts_models.py`
- `engine/tts/speech_profiles.py`

Результат:

- `SpeechProfile` умеет описывать `base` и `slow_native`

### Этап 2. Storage migrations

Изменить:

- `engine/storage.py`

Результат:

- schema знает `audio_variant`
- mobile manifest знает `audio_variant`

### Этап 3. Job generation isolation

Изменить:

- `engine/tts/tts_service.py`
- `engine/tts/tts_queue.py`

Результат:

- `Slow` создаёт `slow_native`
- `Normal/Fast` используют `base`
- overwrite не трогает соседний variant

### Этап 4. UI selection fix

Изменить:

- `app/lib/src/widgets/tts_panel.dart`
- `app/lib/src/screens/reader_screen.dart`
- `app/lib/src/ui/mobile/screens/mobile_reader_screen.dart`
- при необходимости `app/lib/src/models.dart`

Результат:

- UI выбирает правильный job
- `Slow` не уходит в double-slow
- `Fast` продолжает работать как раньше

### Этап 5. Проверка mobile package

Проверить:

- `tts_manifest` в desktop API
- локальный mobile package parsing
- локальный mobile playback выбор нужного variant

## 10. Что нельзя делать в этой реализации

Нельзя:

- снова добавлять waveform post-processing
- снова завязывать identity job на `level_id`
- снова мутировать provider внутри `tts_service`
- снова делать broad overwrite всего voice cache
- снова выбирать job только по `voice_id`
- снова применять `0.85` через player поверх `slow_native`

Это и есть основные точки, где можно повторно сломать проект.

## 11. Обязательные проверки

### Backend

1. `Slow` создаёт job с:
   - `audio_variant='slow_native'`
   - `native_rate=0.85`
2. `Normal` создаёт job с:
   - `audio_variant='base'`
   - `native_rate=0.89`
3. `Fast` не создаёт отдельный audio variant
4. `Normal` и `Fast` используют один и тот же `base` cache
5. `Overwrite Slow` не удаляет `base`
6. `Overwrite Normal/Fast` не удаляет `slow_native`

### UI

1. При выбранном `Slow` запускается `slow_native`
2. При выбранном `Normal` запускается `base`
3. При выбранном `Fast` запускается `base`
4. `Fast` продолжает играть через player-rate `1.15`
5. `Slow` не проигрывается повторно на `0.85x`

### Mobile

1. В package приходят оба variant при их наличии
2. local playback выбирает правильный variant
3. старые package без `audio_variant` не падают

## 12. Ожидаемый результат этапа

После реализации:

- `Slow` станет отдельной native-generated озвучкой `0.85`
- `Normal` и `Fast` останутся на текущем стабильном base path
- storage не будет раздут лишними дублями для `Fast`
- UI не будет путать `base` и `slow_native`
- общий runtime не будет снова затронут широкой TTS-перетряской

## 13. Следующий этап, но не сейчас

Отдельно позже можно делать более правильный slow-learning path через:

- `Kokoro timestamps`
- `wav + timings`
- backend post-process межсловных gap

Но это не часть данного этапа.

Текущий этап только про одно:

- добавить безопасный отдельный native slow generation path на `0.85`
- не ломая прежний base playback path для `1.0/1.15`
