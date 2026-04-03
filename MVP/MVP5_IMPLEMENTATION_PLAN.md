# MVP5 — Multi-Level TTS Generation

## Цель

Сделать TTS-контур, в котором генерация аудио отделена от воспроизведения, поддерживает несколько speech-level профилей на одну книгу и показывает реальный прогресс по каждому профилю.

## Что должно измениться

- кнопка `Play` заменяется на `Start`
- `Start` запускает только готовую генерацию
- появляется отдельная кнопка `Generate voice`
- пользователь может выбрать один или несколько speech levels
- для каждого выбранного level создаётся отдельный TTS job
- у каждого job есть отдельный прогресс генерации
- скорость речи вычисляется через `target_wpm -> rate`
- на низких скоростях применяется компенсация через `pause_scale`

## Константы

```json
{
  "base_wpm": 164,
  "rate_min": 0.75,
  "rate_max": 1.25
}
```

## Уровни

```json
{
  "levels": [
    { "id": 1, "name": "Start",        "target_wpm": 90  },
    { "id": 3, "name": "Transition",   "target_wpm": 120 },
    { "id": 4, "name": "Podcast",      "target_wpm": 145 },
    { "id": 6, "name": "Hardcore",     "target_wpm": 200 }
  ]
}
```

## Speech profile

- `raw_rate = target_wpm / base_wpm`
- `rate = clamp(raw_rate, rate_min, rate_max)`
- если `raw_rate < 0.75`, использовать:
  - `rate = 0.75`
  - `pause_scale = map_low_speed(target_wpm)`

### map_low_speed

- `<= 95 -> 1.4`
- `<= 110 -> 1.25`
- `<= 125 -> 1.1`
- иначе `1.0`

## Паузы

- `phrase_pause = 120 ms`
- `sentence_pause = 250 ms`
- `paragraph_pause = 400 ms`
- итоговая пауза:
  - `final_pause = base_pause * pause_scale`

## Сегментация

Pipeline:

`Paragraph -> Sentence -> Phrase -> Chunk`

Правила:

- sentence split по `.`, `!`, `?`
- phrase split по `,`, `;`, `:`
- длинные куски режутся до `12-16` слов
- запрещён сценарий `один длинный paragraph -> один TTS вызов`

## Backend

- TTS jobs больше не должны удалять друг друга внутри одной книги
- job должен хранить:
  - `level_id`
  - `level_name`
  - `target_wpm`
  - `rate`
  - `pause_scale`
  - `total_segments`
  - `ready_segments`
  - `error_message`
- генерация должна идти в фоне по сегментам
- `/tts/state` должен возвращать список jobs для книги
- нужен отдельный endpoint генерации, а не старый `play -> generate + start`
- кэш должен учитывать speech profile, чтобы разные уровни не перетирали один и тот же audio cache

## UI

- reader показывает:
  - выбор голоса
  - выбор одного или нескольких levels
  - `Generate voice`
  - список генераций
- каждая генерация показывает:
  - level
  - скорость
  - статус
  - `ready/total`
  - отдельную шкалу прогресса
  - `Start`
- UI опрашивает backend, пока есть jobs в `queued` или `generating`

## Минимальный MVP5 scope

- один provider `kokoro`
- несколько speech levels
- отдельная генерация
- отдельный `Start`
- реальный прогресс по каждому уровню
- playback остаётся сегментным

## Критерии готовности

- `Start` не запускает генерацию
- `Generate voice` создаёт job в фоне
- можно выбрать несколько levels сразу
- у каждого level свой прогресс
- `rate` реально передаётся в Kokoro
- low-speed уровни используют `pause_scale`
- кэш не конфликтует между разными levels
