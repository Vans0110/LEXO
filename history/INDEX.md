# История LEXO

Этот файл хранит только оглавление истории по датам.

## Записи

### 2026-05-25
- Сессия: Замена iOS AppIcon для Nove; ускорение mobile Library; POS-aware apostrophe/cleanup translation input; display names; UI tweaks; диагностика NLLB 3.3B EN-UK; switch Marian -> NLLB 3.3B; Workbench skip `chapter_images`; Clean button; NLLB speed/package cache fixes
- Файл: [2026-05-25.md](/mnt/d/Programs/LEXO/history/2026-05-25.md)

### 2026-05-24
- Сессия: Тест американских Kokoro voices на первом абзаце `New Student`; обновление доступных голосов LEXO/Nove до `af_heart`, `af_bella`, `af_sarah`, `am_adam`, `am_michael`
- Файл: [2026-05-24.md](/mnt/d/Programs/LEXO/history/2026-05-24.md)

### 2026-05-22
- Сессия: Перенос `Books/Icon.png` из UI-заглушки в Android launcher icon для Nove
- Файл: [2026-05-22.md](/mnt/d/Programs/LEXO/history/2026-05-22.md)

### 2026-05-21
- Сессия: Тестовый украинский dictionary layer через Marian EN-UK и выбор словаря по языку книги/mobile settings
- Файл: [2026-05-21.md](/mnt/d/Programs/LEXO/history/2026-05-21.md)

### 2026-05-20
- Сессия: Добавление Marian EN-UK, multi-language Workbench export (`reader_ru/reader_uk`) и мобильной настройки языка перевода книг
- Файл: [2026-05-20.md](/mnt/d/Programs/LEXO/history/2026-05-20.md)

### 2026-05-19
- Сессия: Старт отдельного production mobile приложения `Nove`, mobile-only shell без Host Sync и Reader-каталог `Избранное / Главы / Книги`
- Файл: [2026-05-19.md](/mnt/d/Programs/LEXO/history/2026-05-19.md)

### 2026-05-18
- Сессия: Подключение Argos Translate EN-RU для sentence-level segment translations без возврата word alignment
- Файл: [2026-05-18.md](/mnt/d/Programs/LEXO/history/2026-05-18.md)

### 2026-05-15
- Сессия: Fast-fix mobile sync chunked package contract для `local_book_id`; native loop + 5s silence для mobile `repeatBook`; этапы 1-4 background audio service; analyzer/widget test, Android compile fixes, active queue rebuild/wrap-around/current-segment preserve/silence для `playLibraryOnce`, mobile word-audio manifest, диагностика silence item, bottom padding под player, белая active repeat icon/splash, footer spacer, уменьшение mobile reader bottom spacer, iOS fallback для silence item
- Файл: [2026-05-15.md](/mnt/d/Programs/LEXO/history/2026-05-15.md)

### 2026-05-14
- Сессия: POS/lemma перед словарём, offline dictionary manifest, сохранение словарных карточек, ремонт Kokoro venv, word audio в detail sheet, режимы повтора reader-плеера
- Файл: [2026-05-14.md](/mnt/d/Programs/LEXO/history/2026-05-14.md)

### 2026-05-13
- Сессия: Восстановление Windows UI запуска, диагностика SimAlign, исправление segment-scoped `tap_unit_id`, план и реализация MVP23.10 для разделения word tap / owner semantics
- Файл: [2026-05-13.md](/mnt/d/Programs/LEXO/history/2026-05-13.md)

### 2026-05-12
- Сессия: Диагностика UI-подсветки/tap-unit, подтверждение `word = word`, восстановление `.venv_backend` и фиксация отсутствующего Flutter SDK
- Файл: [2026-05-12.md](/mnt/d/Programs/LEXO/history/2026-05-12.md)

### 2026-05-08
- Сессия: Доводка lifecycle `resolved alignment`, новый rebuild route и автопересчёт после import / quality / simalign
- Файл: [2026-05-08.md](/mnt/d/Programs/LEXO/history/2026-05-08.md)

### 2026-05-07
- Сессия: Возврат legacy runtime alignment без `LLM`, отключение автозапуска `LLM alignment` и переключение reader/detail обратно на `SimAlign -> legacy fallback`
- Файл: [2026-05-07.md](/mnt/d/Programs/LEXO/history/2026-05-07.md)

### 2026-05-06
- Сессия: Починка Windows `.venv`, launcher-ы `Aya` / `Qwen2.5-14B GGUF`, внедрение нового `LLM alignment` контура под `A1-A2`, отключение старого runtime alignment path и выделение чистой `.venv_backend` для рабочего `Marian`
- Файл: [2026-05-06.md](/mnt/d/Programs/LEXO/history/2026-05-06.md)

### 2026-03-28
- Сессия: Инициализация MVP-каркаса проекта
- Файл: [2026-03-28.md](/mnt/d/Programs/LEXO/history/2026-03-28.md)

### 2026-03-30
- Сессия: Фикс bat-запуска MVP без зависимости от PATH
- Файл: [2026-03-30.md](/mnt/d/Programs/LEXO/history/2026-03-30.md)

### 2026-03-31
- Сессия: План реализации MVP2 и перехода к bilingual pipeline
- Файл: [2026-03-31.md](/mnt/d/Programs/LEXO/history/2026-03-31.md)

### 2026-04-01
- Сессия: План и реализация MVP5 для multi-level TTS generation
- Файл: [2026-04-01.md](/mnt/d/Programs/LEXO/history/2026-04-01.md)

### 2026-04-02
- Сессия: Привязка `word_id` к target span и фикc смещения перевода на артиклях
- Файл: [2026-04-02.md](/mnt/d/Programs/LEXO/history/2026-04-02.md)

### 2026-04-03
- Сессия: План MVP9 для mobile book package, локальной mobile library, разделения LAN host / Windows UI launcher, новый MVP11 для single-base TTS, MVP12 для bottom reader player и MVP13 для stable source render
- Файл: [2026-04-03.md](/mnt/d/Programs/LEXO/history/2026-04-03.md)

### 2026-04-06
- Сессия: Формализация и реализация MVP14 detail sheet, desktop shell унификация и реализация основы MVP15 для cards list / swipe review
- Файл: [2026-04-06.md](/mnt/d/Programs/LEXO/history/2026-04-06.md)

### 2026-04-07
- Сессия: Реализация MVP16 для локальных mobile cards, ручного sync с desktop host и переработки mobile Settings под Host + Sync
- Файл: [2026-04-07.md](/mnt/d/Programs/LEXO/history/2026-04-07.md)

### 2026-04-08
- Сессия: Mobile reader переведён на strict offline runtime, host оставлен только для sync
- Файл: [2026-04-08.md](/mnt/d/Programs/LEXO/history/2026-04-08.md)

### 2026-04-09
- Сессия: Добавлен literal word-by-word path для study segments и начата очередь 1 по quality contract из ТЗ-1
- Файл: [2026-04-09.md](/mnt/d/Programs/LEXO/history/2026-04-09.md)

### 2026-04-10
- Сессия: Формализация отдельного V2 core как unit-first source-driven контура
- Файл: [2026-04-10.md](/mnt/d/Programs/LEXO/history/2026-04-10.md)

### 2026-04-13
- Сессия: Точечный фикс reporting-verb alignment и cleanup явных ошибок EN->RU перевода
- Файл: [2026-04-13.md](/mnt/d/Programs/LEXO/history/2026-04-13.md)

### 2026-04-14
- Сессия: Slow TTS blocks переведены на `..` per-block
- Файл: [2026-04-14.md](/mnt/d/Programs/LEXO/history/2026-04-14.md)

### 2026-04-15
- Сессия: Из translation pipeline убраны book-specific фразы и post-edit подмены после provider
- Файл: [2026-04-15.md](/mnt/d/Programs/LEXO/history/2026-04-15.md)

### 2026-04-16
- Сессия: Анализ деградации `The Sunny Morning` на `nllb33`, подключение MarianMT и фиксация причины desktop-фриза `Load TXT`
- Файл: [2026-04-16.md](/mnt/d/Programs/LEXO/history/2026-04-16.md)

### 2026-04-17
- Сессия: Реализация segment QA, rebuild-пути и формализация отдельного MVP20 для стабильного translation QA без хрупких словарей
- Файл: [2026-04-17.md](/mnt/d/Programs/LEXO/history/2026-04-17.md)

### 2026-04-20
- Сессия: Подключение Marian `ru -> en`, top-5/merge retry и детальный разбор alignment-проблем `The Sunny Morning`
- Файл: [2026-04-20.md](/mnt/d/Programs/LEXO/history/2026-04-20.md)

### 2026-04-21
- Сессия: Ремонт alignment/unit pipeline, fail-closed alignment QA, починка reader tap-area по `tap_unit_id` и фиксация остаточного runtime словарного слоя
- Файл: [2026-04-21.md](/mnt/d/Programs/LEXO/history/2026-04-21.md)

### 2026-04-22
- Сессия: Формализация MVP21 для source-first сегментации и coverage без словарей как primary logic
- Файл: [2026-04-22.md](/mnt/d/Programs/LEXO/history/2026-04-22.md)

### 2026-04-23
- Сессия: Доводка MVP21 до консистентного source-first runtime path, пересборка persisted contour для `The Sunny Morning`
- Файл: [2026-04-23.md](/mnt/d/Programs/LEXO/history/2026-04-23.md)

### 2026-04-24
- Сессия: Подготовка runtime payload к миграции с legacy alignment на source-first
- Файл: [2026-04-24.md](/mnt/d/Programs/LEXO/history/2026-04-24.md)

### 2026-04-27
- Сессия: План поэтапной замены legacy word alignment на SimAlign sidecar-контур
- Файл: [2026-04-27.md](/mnt/d/Programs/LEXO/history/2026-04-27.md)

### 2026-04-28
- Сессия: Унификация time-token токенизации и strict runtime-режим только для однозначных SimAlign совпадений
- Файл: [2026-04-28.md](/mnt/d/Programs/LEXO/history/2026-04-28.md)

### 2026-04-29
- Сессия: Fail-closed запрет symbol-only target token в source-first coverage, UI trace desktop freeze, замена `Load TXT` на Windows-native file picker, MVP semantic QA, stage-2 role-aware semantic matching и переход к content-core QA (`missing / extra / substituted / duplicate`)
- Файл: [2026-04-29.md](/mnt/d/Programs/LEXO/history/2026-04-29.md)

### 2026-04-30
- Сессия: Анализ живых translation ошибок на 3 книгах, фиксация рассинхрона persisted QA и ужесточение final selection contract для blocking semantic defects
- Файл: [2026-04-30.md](/mnt/d/Programs/LEXO/history/2026-04-30.md)

### 2026-05-01
- Сессия: Fail-closed финализация книги при unresolved QA-blocking сегментах, strict-equivalence для `everyone/everybody`, полный word-only режим без block/group inheritance и временное отключение 2-го salvage-pass
- Файл: [2026-05-01.md](/mnt/d/Programs/LEXO/history/2026-05-01.md)

### 2026-05-02
- Сессия: Глубокий reverse-analysis `2Books`, извлечение живого `tap #1` runtime-контракта, page payload формата, alignment-priors и локального staging/build-path через live monitoring эмулятора
- Файл: [2026-05-02.md](/mnt/d/Programs/LEXO/history/2026-05-02.md)

### 2026-05-04
- Сессия: Доказана двухстадийная сборка `2Books` page payload: ранний source skeleton и поздний bilingual enrichment для `tap #1`
- Файл: [2026-05-04.md](/mnt/d/Programs/LEXO/history/2026-05-04.md)

### 2026-05-05
- Сессия: Удалена локальная модель `mistral-small-3.1-24b-instruct-2503` из `data/models`
- Файл: [2026-05-05.md](/mnt/d/Programs/LEXO/history/2026-05-05.md)

### 2026-05-13
- Сессия: Backend снесён до source-only reader каркаса; translation/alignment/QA pipeline удалён, TTS оставлен; подключён read-only словарь на тап по `source_words`; dictionary output переведён на чистый список статей без выбора "лучшего" перевода
- Файл: [2026-05-13.md](/mnt/d/Programs/LEXO/history/2026-05-13.md)

### 2026-05-19
- Сессия: Создано отдельное production mobile приложение Nove, Workbench для zip-книг и автономная Library с bundled zip import, обложками, деталями книги и ручным избранным
- Файл: [2026-05-19.md](/mnt/d/Programs/LEXO/history/2026-05-19.md)

### 2026-05-21
- Сессия: Подготовлена облачная библиотека Nove через Cloudflare R2: Workbench sync-кнопка, генерация `library_index.json`, mobile cloud catalog fallback
- Файл: [2026-05-21.md](/mnt/d/Programs/LEXO/history/2026-05-21.md)
