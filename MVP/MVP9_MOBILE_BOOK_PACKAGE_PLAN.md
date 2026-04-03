# MVP9 — Mobile Book Package Plan

## 1. Цель этапа

Перевести mobile-ветку LEXO с desktop-зависимой схемы на переносимую модель книги, где:

- `Mobile UI` не зависит от desktop file paths
- iPhone/Android могут импортировать книгу со своей стороны
- desktop engine используется как processing-host
- после обработки mobile получает готовый локальный пакет книги
- tap/translation/highlight/TTS могут работать от локальных данных mobile
- desktop library при желании может экспортироваться и переноситься на mobile как локальная копия

Итог этапа:

- mobile перестаёт быть "тонким клиентом к desktop filesystem"
- mobile становится самостоятельным reader-хранилищем
- desktop остаётся машиной обработки, а не постоянным runtime-зависимым хранилищем

## 2. Главный принцип

Не делать:

- передачу `source_path` с телефона на ПК как главный контракт
- передачу `audio_path` с ПК на телефон как локальный путь
- чтение mobile-книги напрямую из desktop storage
- постоянную runtime-зависимость reader-а от файлов на ПК

Делать:

`Mobile Local Book Package + Desktop Processing Host + Optional Desktop Sync`

То есть:

- mobile выбирает книгу или получает книгу из desktop library
- desktop обрабатывает
- mobile получает переносимый результат
- дальнейшее чтение идёт из локального mobile package

## 3. Что должен дать MVP9

После завершения этапа должны существовать:

- формат `book package` для mobile
- import flow `mobile -> desktop processing -> mobile local save`
- export/sync flow `desktop library -> mobile local library`
- локальное чтение книги на mobile без desktop file paths
- локальное хранение alignment/tap-unit/translation payload на mobile
- локальная привязка TTS metadata на mobile
- отдельная стратегия для TTS:
  - либо локальные audio files на mobile
  - либо явный deferred download/generation flow
- готовность mobile к будущей iPhone runtime-сборке без привязки к desktop filesystem

## 4. Что не входит в MVP9

На этом этапе не нужно делать:

- cloud accounts
- multi-device merge sync
- background sync между desktop и phone
- production-grade conflict resolution
- полный offline TTS generation на самом телефоне
- автоматический iCloud/Google Drive sync
- финальную polished iOS delivery pipeline

## 5. Главная продуктовая модель

### Desktop

Desktop хранит:

- свою библиотеку книг
- исходные `.txt`
- processing pipeline
- translation pipeline
- TTS generation pipeline
- служебные кэши и внутренние storage-таблицы

### Mobile

Mobile хранит:

- свою локальную библиотеку книг
- локальные packaged books
- локальные reader payloads
- локальные tap/alignment данные
- локальные reading positions
- локальные TTS references
- локальные TTS audio files, если они уже были скачаны/перенесены

### Связь между ними

Desktop и mobile связаны не через filesystem path, а через:

- upload/import API
- package download API
- sync/export API

## 6. Новый источник истины для mobile

Для mobile-режима источником истины должен стать не desktop SQLite напрямую, а локальный mobile `book package`.

То есть для mobile reader источником истины становятся:

- локальный packaged source text
- локальный packaged paragraph payload
- локальный packaged words/tap units/alignment
- локальная packaged TTS state snapshot
- локальные audio references

## 7. Новый базовый объект: Book Package

Нужен переносимый формат книги.

### Минимальный состав package

- `book_meta.json`
- `source.txt`
- `paragraphs.json`
- `words.json` или эквивалент внутри paragraph payload
- `tts_manifest.json`
- при необходимости папка `audio/`

### Что хранит `book_meta.json`

- `book_id`
- `title`
- `source_lang`
- `target_lang`
- `model_name`
- `created_at`
- `package_version`
- `content_hash`
- `desktop_origin_id` или `source_book_id`
- `has_local_audio`
- `processing_state`

### Что хранит `paragraphs.json`

- список paragraph payloads
- `source_text`
- `target_text`
- `index`
- нужные данные для reader

### Что хранит `words/tap data`

- `word_id`
- `anchor_word_id`
- `tap_unit_id`
- `source_unit_text`
- `translation_left_text`
- `translation_focus_text`
- `translation_right_text`
- всё, что нужно для верхнего перевода и highlight без обращения к desktop

### Что хранит `tts_manifest.json`

- список voice/jobs
- segment metadata
- `segment_index`
- `paragraph_index`
- `source_text`
- `duration_ms`
- `pause_after_ms`
- локальный audio file name или remote asset id
- статус наличия аудио на mobile

## 8. Два основных сценария импорта

### 8.1 Import from Mobile File

Сценарий:

1. пользователь выбирает `.txt` на iPhone/Android
2. mobile читает содержимое файла у себя
3. mobile отправляет на desktop:
   - текст файла
   - имя книги
   - языки
   - базовые метаданные
4. desktop создаёт книгу во внутреннем storage
5. desktop выполняет segmentation/translation/alignment
6. desktop собирает `book package`
7. mobile скачивает package
8. mobile сохраняет package локально
9. книга появляется в локальной mobile library

Главный принцип:
в API передаётся не `source_path`, а содержимое книги или бинарный upload.

### 8.2 Import from Desktop Library

Сценарий:

1. на desktop уже есть книга в библиотеке
2. пользователь на mobile открывает экран sync/import
3. mobile запрашивает список desktop-книг
4. пользователь выбирает книгу
5. desktop собирает export package для выбранной книги
6. mobile скачивает package
7. mobile сохраняет package локально
8. книга появляется как локальная mobile-книга

Главный принцип:
desktop library становится источником экспортируемых package, а не runtime-файловых путей.

## 9. Новый API contract

### 9.1 Book import API

Нужен endpoint вида:

- `POST /mobile/books/import-text`

Принимает:

- `title`
- `source_lang`
- `target_lang`
- `source_text`

Возвращает:

- `job_id` или `book_id`
- статус начала обработки

### 9.2 Book package build/status API

Нужны endpoints вида:

- `GET /mobile/import-jobs/<id>`
- `GET /mobile/books/<id>/package`

Поведение:

- либо polling статуса
- либо прямой package download после готовности

### 9.3 Desktop library sync API

Нужны endpoints вида:

- `GET /mobile/desktop-books`
- `POST /mobile/desktop-books/<id>/export`
- `GET /mobile/exports/<id>/package`

### 9.4 Audio delivery API

Нужен контракт не через `audio_path`, а через:

- package-local audio file
или
- explicit audio download endpoint

Например:

- `GET /mobile/books/<id>/audio/<segment_id>`

## 10. Reader contract после MVP9

Reader на mobile больше не должен читать данные напрямую из desktop API как единственного источника.

Новый порядок:

1. mobile открывает локальную packaged book
2. reader получает paragraphs/words/tap data из local storage
3. тап по слову работает локально
4. верхний перевод берётся из packaged payload
5. reading position сохраняется локально
6. синк с desktop может быть отдельной операцией, но не обязателен для каждого тапа

## 11. TTS contract после MVP9

### Что неправильно сейчас

Сейчас mobile получает `audio_path`, который физически относится к desktop host.

### Что должно быть

Нужны 2 допустимых режима.

#### Режим A. Audio inside package

- desktop генерирует TTS
- audio files входят в package
- mobile сохраняет их локально
- playback полностью локальный

Плюс:

- лучший offline режим

Минус:

- package может быть тяжёлым

#### Режим B. Metadata first, audio on demand

- desktop отправляет package без audio files
- mobile получает только TTS manifest
- при первом запуске нужный audio segment/job скачивается отдельно
- после скачивания сохраняется локально

Плюс:

- легче initial import

Минус:

- нужна дополнительная логика cache/download

Для MVP9 разумнее заложить архитектуру под оба режима, но реализовать сначала один.
Практически первым я бы взял:
`metadata first + optional audio download`,
если размер книг и TTS может быть большим.

## 12. Локальное mobile storage

Нужен отдельный mobile storage-слой.

Он должен хранить:

- список локальных mobile books
- metadata package
- paragraph payloads
- word/tap payloads
- reading position
- TTS manifest
- downloaded audio files
- флаг происхождения:
  - `imported_from_mobile_file`
  - `synced_from_desktop`
  - `local_mobile_copy_of_desktop_book`

## 13. Идентичность книги и связь desktop/mobile

Нужно разделить два id:

- `desktop_book_id`
- `mobile_book_id`

И нужен ещё один стабильный идентификатор содержимого, например:

- `content_hash`
или
- `package_origin_id`

Зачем:

- одна desktop-книга может быть экспортирована на несколько устройств
- на mobile книга должна жить как локальная сущность
- при повторном sync нужно понимать:
  - это новая книга
  - это обновление существующей
  - это тот же контент

## 14. Сценарий обновления книги

Нужен базовый MVP-режим обновления:

1. mobile видит, что на desktop есть более новая версия package
2. пользователь вручную жмёт `Update from Desktop`
3. desktop отдаёт новый package
4. mobile заменяет локальные packaged payloads
5. reading position по возможности сохраняется

На MVP не нужен сложный auto-merge.

## 15. UI изменения в mobile

### Library

Нужно добавить в mobile library/settings:

- `Import TXT`
- `Import from Desktop Library`
- `Update from Desktop`
- индикатор:
  - `Local`
  - `Synced from Desktop`
  - `Update available`

### Reader

Reader не должен знать, откуда пришла книга.
Он должен работать по локальному package.

### Settings / Sync

Нужен отдельный mobile flow:

- подключение к desktop host
- список desktop-книг
- import/export/update actions
- TTS download management

## 16. UI изменения в desktop

Desktop нужен минимальный export/sync control surface:

- список книг, доступных для mobile export
- команда `Prepare mobile package`
- команда `Export with audio` / `Export without audio`
- статус package generation

На MVP можно даже без большого UI, если это идёт через backend API.

## 17. Архитектурные изменения в коде

Нужно отделить 3 слоя:

### Shared feature logic

- library state
- reader state
- selection state
- translation state
- tts state

### Transport/API layer

- desktop processing API
- package download API
- desktop sync API

### Local mobile persistence layer

- mobile package repository
- local reader source
- local audio repository

Запрещено после MVP9:

- mobile reader читает книгу через desktop file path
- mobile TTS открывает audio через desktop host filesystem path
- import книги строится на `source_path` клиента

## 18. Этапы реализации

### Этап 1. Зафиксировать package contract

Сделать:

- структуру `book package`
- `package_version`
- обязательные поля metadata
- схему paragraphs/words/tap data
- схему TTS manifest

Результат:
есть утверждённый формат переносимой mobile-книги

### Этап 2. Вынести desktop processing в import/export API

Сделать:

- import text endpoint
- processing job/status endpoint
- package build endpoint
- desktop library export endpoint

Результат:
desktop умеет не только хранить книгу у себя, но и выдавать mobile package

### Этап 3. Добавить local mobile storage

Сделать:

- хранение packaged books
- индекс локальной mobile library
- локальную загрузку paragraphs/words
- локальное сохранение reading position

Результат:
mobile reader читает уже локальную книгу

### Этап 4. Перевести mobile import на новый контракт

Сделать:

- чтение текста файла на mobile
- отправку текста на desktop
- скачивание готового package
- локальное сохранение package

Результат:
mobile import больше не использует `source_path`

### Этап 5. Перевести mobile TTS на новый контракт

Сделать:

- новый TTS manifest contract
- local audio refs
- audio download or package-audio import
- playback из local mobile storage

Результат:
mobile TTS больше не зависит от `audio_path` desktop-хоста

### Этап 6. Добавить desktop library sync flow

Сделать:

- listing desktop books
- export selected desktop book
- import package into mobile local library
- ручное обновление package

Результат:
существующая desktop library может переноситься на iPhone/Android как локальная библиотека

## 19. Критерии готовности

Этап считается завершённым, если:

- mobile import не использует `source_path`
- mobile reader не зависит от desktop filesystem
- mobile TTS playback не зависит от desktop `audio_path`
- тап по слову и верхний перевод работают из локальных packaged данных
- книга, импортированная на iPhone/Android, становится локальной mobile-книгой
- книга из desktop library может быть перенесена на mobile как локальная копия
- mobile reader может открываться без постоянного чтения книги с ПК
- проект готов к iPhone runtime-модели

## 20. Главный продуктовый результат

После MVP9 LEXO должен перестать быть mobile-preview, который живёт рядом с desktop host.

Он должен стать:

- общим mobile-продуктом
- с локальной mobile library
- с desktop как processing-host
- с переносимыми packaged books
- с правильной основой под iPhone и Android

## 21. Что идёт следующим этапом

После MVP9 уже можно уверенно идти в:

- iPhone build pipeline
- первую реальную установку на iPhone
- проверку реального device-runtime
- шлифовку mobile sync/TTS UX
