# MVP18 — Full Offline Audio Package Generation

## 1. Цель

Сделать `Generate voice` единой командой полной офлайн-подготовки аудио для книги:

1. `base` audio для `1.0`
2. `slow_native` audio для `0.85`
3. `word audio` для всех лексических слов книги

Режим `1.15` не требует отдельной генерации:

- использует `base`
- playback остаётся speed-layer поверх `base`

Итог:

- после одного запуска книга готова для офлайн-прослушивания
- slow-режим готов
- любые слова книги можно позже добавить в карточки и проигрывать офлайн без догенерации

---

## 2. Продуктовый результат

После `Generate voice` пользователь получает:

- `Normal` работает от готового `base`
- `Fast` работает от того же `base`
- `Slow` работает от готового `slow_native`
- карточки могут проигрывать слова офлайн
- слово не нужно отдельно догенерировать в момент review/add

Главный принцип:

- одна кнопка
- один orchestration pipeline
- полная офлайн-готовность

---

## 3. Что уже есть в проекте

Уже реализовано:

- `base` и `slow_native` как разные TTS variants
- `word_audio` cache через:
  - [engine/storage.py](/mnt/d/Programs/LEXO/engine/storage.py)
- lazy word-audio generation через:
  - `POST /word/audio`
  - `GET /word/audio`
- playback карточек через:
  - [app/lib/src/screens/cards_list_screen.dart](/mnt/d/Programs/LEXO/app/lib/src/screens/cards_list_screen.dart)

Значит новый этап не требует новой аудио-архитектуры.
Нужен orchestration-слой поверх существующих путей.

---

## 4. Новый пользовательский сценарий

### 4.1 Нажатие `Generate voice`

Кнопка запускает pipeline:

1. `Base audio`
2. `Slow audio`
3. `Word audio`

На первом безопасном этапе pipeline выполняется последовательно.

---

## 5. Что именно генерируется

### 5.1 Book audio

Нужно подготовить:

- `base`
- `slow_native`

### 5.2 Word audio

Нужно подготовить audio не только для сохранённых карточек, а для **всех лексических слов книги**.

Источник:

- `source_words` текущей книги

Дедупликация:

- если есть `lemma`, использовать `lemma`
- иначе использовать `normalized_text`

Исключить:

- punctuation
- пустые значения
- grammar-only слова

---

## 6. Offline-цель word audio

После завершения package generation:

- карточка, добавленная позже из этой книги, должна сразу иметь готовое слово
- `/word/audio` остаётся как fallback
- но основной сценарий должен работать без ленивой догенерации

---

## 7. Новый backend orchestration layer

### 7.1 Отдельная сущность package generation

Нельзя смешивать package generation с текущими `tts_jobs`.

Нужна новая верхнеуровневая сущность:

- `tts_package_job`

Она управляет тремя стадиями:

- `base_audio`
- `slow_audio`
- `word_audio`

---

## 8. Новые таблицы

### 8.1 `tts_package_jobs`

Поля:

- `id`
- `book_id`
- `voice_id`
- `status`
- `created_at`
- `updated_at`
- `error_message`

### 8.2 `tts_package_stages`

Поля:

- `id`
- `package_job_id`
- `stage_key`
- `label`
- `status`
- `done_count`
- `total_count`
- `error_message`

`stage_key`:

- `base_audio`
- `slow_audio`
- `word_audio`

---

## 9. Новые backend endpoints

### 9.1 `POST /tts/generate-package`

Payload:

```json
{
  "book_id": "...",
  "voice_id": "...",
  "overwrite": false,
  "overwrite_word_audio": false
}
```

Ответ:

```json
{
  "ok": true,
  "package_job_id": "...",
  "status": "queued"
}
```

### 9.2 `GET /tts/package-state`

Пример:

`/tts/package-state?book_id=...&voice_id=...`

Ответ:

```json
{
  "book_id": "...",
  "voice_id": "...",
  "status": "running",
  "stages": [
    {
      "id": "base_audio",
      "label": "Base audio",
      "status": "running",
      "done": 42,
      "total": 120
    },
    {
      "id": "slow_audio",
      "label": "Slow audio",
      "status": "pending",
      "done": 0,
      "total": 120
    },
    {
      "id": "word_audio",
      "label": "Word audio",
      "status": "pending",
      "done": 0,
      "total": 1240
    }
  ]
}
```

---

## 10. Порядок backend выполнения

Безопасный порядок:

1. старт package job
2. `base_audio`
3. `slow_audio`
4. собрать lexical word set книги
5. `word_audio`
6. статус `done`

Если падает `base_audio`:

- дальше не идти
- package status = `error`

Если падает `slow_audio`:

- дальше не идти
- package status = `error`

Если падает `word_audio`:

- package status = `error`

На первом этапе допускается простая модель ошибок без partial recovery.

---

## 11. Реализация `base_audio`

Нужно переиспользовать существующий TTS generation path:

- через текущий `tts_service`
- с `level_id`, который даёт `base`

Package layer не должен дублировать сегментную генерацию.
Он только оркестрирует её и отражает progress.

---

## 12. Реализация `slow_audio`

То же самое:

- использовать существующий generation path для `slow_native`
- ждать завершения
- отражать progress в `tts_package_stages`

---

## 13. Сбор lexical words книги

Нужен storage-метод:

- `_collect_book_word_audio_entries(book_id)`

Логика:

1. взять `source_words` книги
2. убрать grammar-only entries
3. взять:
   - `lemma`, если есть
   - иначе `normalized_text`
4. дедуплицировать
5. отсортировать для стабильного порядка

Это и будет source list для `word_audio`

---

## 14. Реализация `word_audio`

Нужен storage-метод:

- `generate_book_word_audio(...)`

Логика:

1. получить lexical entries книги
2. вычислить `total_count`
3. пройтись по entries
4. для каждого:
   - использовать `get_word_audio_path(...)`
   - или lower-level helper с поддержкой overwrite
5. обновлять `done_count`

---

## 15. Overwrite поведение

### 15.1 Book audio

`overwrite=true`:

- перегенерировать `base`
- перегенерировать `slow_native`

### 15.2 Word audio

Нужен отдельный флаг:

- `overwrite_word_audio=false` по умолчанию

Если `false`:

- готовые word wav не пересобирать

Если `true`:

- пересобирать только lexical entries текущей книги
- не чистить весь global `word_audio` cache

---

## 16. UI статус

### 16.1 Где показывать

Показывать в `TTS panel`.

### 16.2 Какие стадии показывать

- `Base audio`
- `Slow audio`
- `Word audio`

Для каждой стадии:

- `pending`
- `running`
- `done`
- `error`

И прогресс:

- `done_count / total_count`

Пример:

- `Base audio 24/120`
- `Slow audio 0/120`
- `Word audio 0/1240`

---

## 17. Что делать с `Fast`

Отдельный stage для `Fast` не нужен.

`Fast` использует `base`.

При желании в UI можно пояснить:

- `Fast uses Base audio`

Но отдельную генерацию не запускать.

---

## 18. Что менять в Flutter

### 18.1 API client

Добавить методы:

- `generateTtsPackage(...)`
- `getTtsPackageState(...)`

### 18.2 Models

Добавить:

- `TtsPackageState`
- `TtsPackageStage`

### 18.3 Reader / polling

Нужно обновлять package state рядом с текущим `tts_state`.

### 18.4 `TTS panel`

Кнопка `Generate voice` должна запускать package generation.

Ниже должен показываться статус стадий.

---

## 19. Что не нужно делать на этом этапе

Не нужно:

- генерировать отдельный `Fast` audio
- пересобирать весь global word cache
- включать в word batch grammar-only слова
- добавлять phrase-audio generation для всех detail units
- ломать lazy `/word/audio`

---

## 20. Важные проверки после реализации

1. `Generate voice` создаёт package job
2. `base_audio` проходит до конца
3. `slow_audio` проходит до конца
4. `word_audio` считает уникальные lexical entries книги
5. карточка воспроизводит слово без ленивой догенерации после package generation
6. повторный запуск без overwrite не тратит время на уже готовый word cache
7. `overwrite_word_audio=true` пересобирает только нужный word set
8. UI показывает stage progress без ощущения зависания

---

## 21. Порядок реализации

1. schema migration для `tts_package_jobs` и `tts_package_stages`
2. storage methods для package job и stage updates
3. orchestration backend path
4. word-audio batch generation
5. package-state endpoint
6. Flutter API client
7. Flutter models
8. `TTS panel` status UI
9. polling / refresh
10. smoke tests

---

## 22. Главный итог

`Generate voice` должен стать не одной TTS-командой, а полной командой:

- `Base audio`
- `Slow audio`
- `Word audio for all lexical words in the book`

То есть:

`Generate voice -> Full Offline Audio Package Build`
