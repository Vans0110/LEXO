# История LEXO

Этот файл хранит только оглавление истории по датам.

## Записи

### 2026-06-16
- Добавлен ручной `Virgil Core Dictionary`: строгая структура `word|POS`, инструкция построения,
  JSON-schema; все 5 книг A1 Chapter 1 внесены в единый общий словарь.
- Runtime-словарь переподключён только на `Virgil Core Dictionary`; внешние Wiktionary/FreeDict/2Books lookup
  и словарный NLLB/MT fallback отключены, Core дозаполнен до 349 entries по 8 готовым output-книгам с обложками.
- Workbench Book Library переведён на один `Start` с отдельными галочками text RU/UK, dictionary RU/UK
  и Kokoro voices; Google usage поднят наверх и показывает cap 5000 отдельно от месячных 500000.
- Добавлен локальный счётчик Google Translation API с JSONL-журналом,
  endpoint-ом месячного usage и отображением в Workbench; рассчитан расход двух
  тестовых книг: 1500 подтверждённых символов, до 3000 при RU+UK.
- Рабочий лимит Google Translation снижен до 5000 символов; Workbench требует
  подтверждение перед расходом, backend блокирует превышение лимита.
- Файл: [2026-06-16.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-16.md)

### 2026-06-15
- Workbench получил независимую перезапись выбранных TTS-голосов без чтения,
  импорта или повторного перевода текста; reader и словари сохраняются.
- Добавлен приоритетный проверенный словарь Virgil для полной замены ошибочных
  внешних переводов по ключу `язык + lemma + POS`; `math|NOUN` исправлен для RU/UK.
- Перевод segment-ов книги временно вынесен в Google Cloud Translation API:
  вход очищается до букв, цифр, пробелов и `. , ! ?`, десять вариантов и
  rerank обходятся; NLLB сохранён для словарного fallback.
- Добавлен тестовый аудит совпадений словарных переводов с переводом
  собственного segment-а по точной форме и RU/UK-лемме.
- Для `The Wrong Classroom` выполнена полная сверка 81 словарной записи с
  одним первым вариантом локального NLLB для RU и UK.
- Файл: [2026-06-15.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-15.md)

### 2026-06-12
- Упрощён Workbench: удалён нижний ручной редактор книги, а `Clean selected`
  и `Sync to R2` перенесены в верхнюю панель Book Library.
- Фильтры Workbench получили кнопку `Apply` и сохраняют применённое состояние
  во время обработки и обновления списка книг.
- Экран книг главы получил адаптивную сетку из двух или трёх колонок без
  изменения размера карточек: обложки выровнены сверху, последняя строка слева.
- Числовые данные во всех текущих A1/A2 текстах преобразованы в английские
  слова; правило и аудит применены ко всем уровням A1-C1, кроме будущего
  отдельного типа телефонных номеров.
- Исправлен формат учебных текстов: убраны ручные переносы внутри абзацев
  A1/A2, переэкспортированы TXT, добавлены общее правило A1-C1 и проверки.
- Добавлен каскадный MT fallback для отсутствующих RU/UK словарных переводов: до трёх
  уникальных вариантов, приоритет исходной формы над ошибочной леммой; source повышен до `v3`.
- Исправлен dictionary fallback при ошибочной POS/lemma-разметке: lookup
  повторяется без POS и по исходной форме; добавлены regression-тесты,
  версии RU/UK source повышены до `v2`, пакет `The Wrong Classroom`
  пересобран с русским переводом `downstairs`.
- Sync to R2 теперь оставляет публикацию только при наличии TXT и полной сборки
  `workbench_output`; старый ZIP не считается подтверждением готовности. Лишние
  ZIP/обложки удаляются локально и из R2; `New Student` и `Late for Class`
  удалены из опубликованной библиотеки.
- Исправлена регрессия Sync to R2: один выбранный готовый голос теперь достаточен,
  пустой результат загрузчика не запускает очистку; пять книг Chapter 1
  восстановлены и повторно опубликованы.
- Исправлена совместимость фильтров Workbench с Flutter `3.32.8`, используемым
  iOS CI: устранена compile-ошибка неизвестного параметра `initialValue`.
- Исправлено Flutter-падение Workbench после удаления книги: карточки и
  элементы прокрутки получили стабильные ключи, устранён вложенный `setState`.
- Для Chapter 4 `Food & Drinks` созданы пять финальных обложек A1; проверены
  заголовки, сцены и технический формат 1024 x 1536 RGB.
- Для Chapter 5 `Work & Study` созданы пять финальных обложек A1 с акцентом
  mustard yellow; проверены сцены, отсутствие брендов и формат 1024 x 1536 RGB.
- Файл: [2026-06-12.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-12.md)

### 2026-06-11
- Выполнен редакторско-педагогический проход корпуса A1: устранены
  неестественные словарные вставки, исправлены грамматика и сюжетная
  связность, глубоко переработаны главы 18 и 20; 100 текстов проходят
  структурный аудит, жёстких лексических ошибок нет, позднее повторяются
  90% единиц Active Core.
- В рабочий каталог A1 экспортировано 68 текстов: по пять книг для глав 1-12
  и по одной для глав 13-20; обложки и изображения не изменялись.
- Зафиксирован единый расширяемый стиль книжных обложек A1 и подготовлены
  сюжетные брифы для всех 68 фактически размещённых книг без генерации PNG.
- Удалены прежние книжные обложки и создана новая единая серия из пяти
  обложек A1.1 размером 1024 x 1536; изображения глав сохранены.
- Для A1.2 создано ещё пять обложек с усиленной фиксацией общей палитры,
  фактуры, света и композиции; в каталоге теперь 10 книжных PNG.
- Для A1.3 создано пять обложек в закреплённом стиле с терракотовым акцентом;
  первые три главы теперь имеют 15 книжных PNG.
- Исправлена общая backend-токенизация апострофов: прямой и фигурный
  апостроф сохраняются внутри одного tappable-слова во всех основных
  контурах; добавлены regression-тесты.
- Workbench получил выпадающие фильтры по уровню, главе и готовности книги,
  выбор только видимых карточек и отдельную обработку выбранных книг.
- Начато производство A2 по новому chapter-first процессу: созданы контракт,
  грамматический маршрут, словарный реестр, паспорта и пять текстов эталонной
  главы A2.1; новый аудит проходит без ошибок и словарного долга.
- Завершён полный плановый реестр A2 для 12 глав: 371 обязательная новая
  активная/тематическая единица и 63 Recognition; добавлены CSV-экспорт,
  маршруты повторения и отдельный аудит без ошибок и предупреждений.
- Файл: [2026-06-11.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-11.md)

### 2026-06-10
- Завершена лексическая переработка A1: 20 глав и 100 текстов проходят
  структурный и строгий словарный аудит без пропусков и долгов повторения.
- Созданы система иллюстраций A1, архитектура библиотеки A1–C1 и полный
  черновой корпус A1: 20 глав, 100 уникальных текстов, словарный реестр и
  автоматический структурно-лексический аудит; добавлены фактический
  инвентарь, строгий лексический QA и первый проход исправления текстов
- Файл: [2026-06-10.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-10.md)

### 2026-06-09
- Подготовка Virgil к Google Play и финальная группировка workspace в `Virgil`, `Studio`, `Release`, `Private`, `Archive`, `Docs`; upload signing и автоматическая упаковка AAB по версии
- Файл: [2026-06-09.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-09.md)

### 2026-06-05
- Сессия: два этапа полного аудита и безопасной очистки workspace; удалены отсоединённые модели, старые окружения/ML-кэши, MVP, logs, backup/build/tmp, сырые словарные дампы, 2Books/IPA и дубли Workbench ZIP; рабочие NLLB CT2, Kokoro, E5, Stanza, словари и актуальные книги сохранены
- Production mobile переименован в Virgil; удалены пользовательские кнопки обновления, обновлены Android/iOS IDs, Workbench, launch scripts, workflow и облачный путь
- Workbench получил выбор книг чекбоксами, общий `All` и безопасный пакетный `Clean` с подтверждением и очисткой строго по артефактам каждой книги
- Контур обновления книг усилен проверкой SHA-256 перед распаковкой, обновляемым облачным индексом, рабочим `Update` и трёхфазной публикацией R2 с индексом строго после файлов
- Карточки глав мобильной библиотеки выровнены по высоте: единые зоны изображения/заголовка/счётчика и номер для глав без иллюстрации; ширина и карусель сохранены
- Реализован полный локальный каталог: `Downloaded Books`, офлайн-избранное, восстановление активной книги и потоковая атомарная установка ZIP
- Версии книг переведены на SHA-256 ZIP в `content_hash`; сопоставление и избранное используют стабильный `book_id`
- Файл: [2026-06-05.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-05.md)

### 2026-06-03
- Сессия: Nove mobile UX fixes — Open сразу после Load, увеличенная drag-зона reader detail sheet, copy word/segment, упрощённый dictionary UI и удаление карточек только свайпом; добавлен UK Wiktionary dictionary layer без NLLB fallback; chapter cards сжаты по нижнему пустому полю; в Settings добавлена feedback-форма через email; word audio переведён на multi-voice формат пакета и Workbench status; import stable-книг больше не сносит готовый segment audio при неизменном тексте
- Файл: [2026-06-03.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-03.md)

### 2026-06-02
- Сессия: Workbench получил подсветку обработанных книг, карточки с секциями TXT/Dictionary/Voice, диагностику player voices/missing voices, refresh одной книги и refresh dictionaries по книге; запуск верстака теперь автостартует backend; из library data удалён устаревший mock TTS profile; backend import получил стабильный book_id для Nove Workbench; удалены старые zip-архивы и output-пакеты книг; RU dictionary manifest переключён на context resolver Wiktionary+FreeDict
- Файл: [2026-06-02.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-02.md)

### 2026-05-26
- Сессия: Smoke-test segment-local dictionary QA rerank на коротких RU/UK cases и in-memory прогон `New Student`; structural target rerank без словаря через Stanza RU/UK; перенос Stanza resources на `D:`; semantic E5 rerank и hybrid experiment; required POS bucket counts; интеграция rerank modes в backend build и перенос HF cache на `D:`
- Файл: [2026-05-26.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-26.md)

### 2026-05-25
- Сессия: Замена iOS AppIcon для Nove; ускорение mobile Library; POS-aware apostrophe/cleanup translation input; display names; UI tweaks; диагностика NLLB 3.3B EN-UK; switch Marian -> NLLB 3.3B; Workbench skip `chapter_images`; Clean button; NLLB speed/package cache fixes; chapter cards 1.5x; Kokoro voice ready-check; segment-local dictionary QA rerank
- Файл: [2026-05-25.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-25.md)

### 2026-05-24
- Сессия: Тест американских Kokoro voices на первом абзаце `New Student`; обновление доступных голосов LEXO/Nove до `af_heart`, `af_bella`, `af_sarah`, `am_adam`, `am_michael`
- Файл: [2026-05-24.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-24.md)

### 2026-05-22
- Сессия: Перенос `Books/Icon.png` из UI-заглушки в Android launcher icon для Nove
- Файл: [2026-05-22.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-22.md)

### 2026-05-21
- Сессия: Тестовый украинский dictionary layer через Marian EN-UK и выбор словаря по языку книги/mobile settings
- Файл: [2026-05-21.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-21.md)

### 2026-05-20
- Сессия: Добавление Marian EN-UK, multi-language Workbench export (`reader_ru/reader_uk`) и мобильной настройки языка перевода книг
- Файл: [2026-05-20.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-20.md)

### 2026-05-19
- Сессия: Старт отдельного production mobile приложения `Nove`, mobile-only shell без Host Sync и Reader-каталог `Избранное / Главы / Книги`
- Файл: [2026-05-19.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-19.md)

### 2026-05-18
- Сессия: Подключение Argos Translate EN-RU для sentence-level segment translations без возврата word alignment
- Файл: [2026-05-18.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-18.md)

### 2026-05-15
- Сессия: Fast-fix mobile sync chunked package contract для `local_book_id`; native loop + 5s silence для mobile `repeatBook`; этапы 1-4 background audio service; analyzer/widget test, Android compile fixes, active queue rebuild/wrap-around/current-segment preserve/silence для `playLibraryOnce`, mobile word-audio manifest, диагностика silence item, bottom padding под player, белая active repeat icon/splash, footer spacer, уменьшение mobile reader bottom spacer, iOS fallback для silence item
- Файл: [2026-05-15.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-15.md)

### 2026-05-14
- Сессия: POS/lemma перед словарём, offline dictionary manifest, сохранение словарных карточек, ремонт Kokoro venv, word audio в detail sheet, режимы повтора reader-плеера
- Файл: [2026-05-14.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-14.md)

### 2026-05-13
- Сессия: Восстановление Windows UI запуска, диагностика SimAlign, исправление segment-scoped `tap_unit_id`, план и реализация MVP23.10 для разделения word tap / owner semantics
- Файл: [2026-05-13.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-13.md)

### 2026-05-12
- Сессия: Диагностика UI-подсветки/tap-unit, подтверждение `word = word`, восстановление `.venv_backend` и фиксация отсутствующего Flutter SDK
- Файл: [2026-05-12.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-12.md)

### 2026-05-08
- Сессия: Доводка lifecycle `resolved alignment`, новый rebuild route и автопересчёт после import / quality / simalign
- Файл: [2026-05-08.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-08.md)

### 2026-05-07
- Сессия: Возврат legacy runtime alignment без `LLM`, отключение автозапуска `LLM alignment` и переключение reader/detail обратно на `SimAlign -> legacy fallback`
- Файл: [2026-05-07.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-07.md)

### 2026-05-06
- Сессия: Починка Windows `.venv`, launcher-ы `Aya` / `Qwen2.5-14B GGUF`, внедрение нового `LLM alignment` контура под `A1-A2`, отключение старого runtime alignment path и выделение чистой `.venv_backend` для рабочего `Marian`
- Файл: [2026-05-06.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-06.md)

### 2026-03-28
- Сессия: Инициализация MVP-каркаса проекта
- Файл: [2026-03-28.md](/mnt/d/Programs/LEXO/Docs/History/2026-03-28.md)

### 2026-03-30
- Сессия: Фикс bat-запуска MVP без зависимости от PATH
- Файл: [2026-03-30.md](/mnt/d/Programs/LEXO/Docs/History/2026-03-30.md)

### 2026-03-31
- Сессия: План реализации MVP2 и перехода к bilingual pipeline
- Файл: [2026-03-31.md](/mnt/d/Programs/LEXO/Docs/History/2026-03-31.md)

### 2026-04-01
- Сессия: План и реализация MVP5 для multi-level TTS generation
- Файл: [2026-04-01.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-01.md)

### 2026-04-02
- Сессия: Привязка `word_id` к target span и фикc смещения перевода на артиклях
- Файл: [2026-04-02.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-02.md)

### 2026-04-03
- Сессия: План MVP9 для mobile book package, локальной mobile library, разделения LAN host / Windows UI launcher, новый MVP11 для single-base TTS, MVP12 для bottom reader player и MVP13 для stable source render
- Файл: [2026-04-03.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-03.md)

### 2026-04-06
- Сессия: Формализация и реализация MVP14 detail sheet, desktop shell унификация и реализация основы MVP15 для cards list / swipe review
- Файл: [2026-04-06.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-06.md)

### 2026-04-07
- Сессия: Реализация MVP16 для локальных mobile cards, ручного sync с desktop host и переработки mobile Settings под Host + Sync
- Файл: [2026-04-07.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-07.md)

### 2026-04-08
- Сессия: Mobile reader переведён на strict offline runtime, host оставлен только для sync
- Файл: [2026-04-08.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-08.md)

### 2026-04-09
- Сессия: Добавлен literal word-by-word path для study segments и начата очередь 1 по quality contract из ТЗ-1
- Файл: [2026-04-09.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-09.md)

### 2026-04-10
- Сессия: Формализация отдельного V2 core как unit-first source-driven контура
- Файл: [2026-04-10.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-10.md)

### 2026-04-13
- Сессия: Точечный фикс reporting-verb alignment и cleanup явных ошибок EN->RU перевода
- Файл: [2026-04-13.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-13.md)

### 2026-04-14
- Сессия: Slow TTS blocks переведены на `..` per-block
- Файл: [2026-04-14.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-14.md)

### 2026-04-15
- Сессия: Из translation pipeline убраны book-specific фразы и post-edit подмены после provider
- Файл: [2026-04-15.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-15.md)

### 2026-04-16
- Сессия: Анализ деградации `The Sunny Morning` на `nllb33`, подключение MarianMT и фиксация причины desktop-фриза `Load TXT`
- Файл: [2026-04-16.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-16.md)

### 2026-04-17
- Сессия: Реализация segment QA, rebuild-пути и формализация отдельного MVP20 для стабильного translation QA без хрупких словарей
- Файл: [2026-04-17.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-17.md)

### 2026-04-20
- Сессия: Подключение Marian `ru -> en`, top-5/merge retry и детальный разбор alignment-проблем `The Sunny Morning`
- Файл: [2026-04-20.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-20.md)

### 2026-04-21
- Сессия: Ремонт alignment/unit pipeline, fail-closed alignment QA, починка reader tap-area по `tap_unit_id` и фиксация остаточного runtime словарного слоя
- Файл: [2026-04-21.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-21.md)

### 2026-04-22
- Сессия: Формализация MVP21 для source-first сегментации и coverage без словарей как primary logic
- Файл: [2026-04-22.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-22.md)

### 2026-04-23
- Сессия: Доводка MVP21 до консистентного source-first runtime path, пересборка persisted contour для `The Sunny Morning`
- Файл: [2026-04-23.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-23.md)

### 2026-04-24
- Сессия: Подготовка runtime payload к миграции с legacy alignment на source-first
- Файл: [2026-04-24.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-24.md)

### 2026-04-27
- Сессия: План поэтапной замены legacy word alignment на SimAlign sidecar-контур
- Файл: [2026-04-27.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-27.md)

### 2026-04-28
- Сессия: Унификация time-token токенизации и strict runtime-режим только для однозначных SimAlign совпадений
- Файл: [2026-04-28.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-28.md)

### 2026-04-29
- Сессия: Fail-closed запрет symbol-only target token в source-first coverage, UI trace desktop freeze, замена `Load TXT` на Windows-native file picker, MVP semantic QA, stage-2 role-aware semantic matching и переход к content-core QA (`missing / extra / substituted / duplicate`)
- Файл: [2026-04-29.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-29.md)

### 2026-04-30
- Сессия: Анализ живых translation ошибок на 3 книгах, фиксация рассинхрона persisted QA и ужесточение final selection contract для blocking semantic defects
- Файл: [2026-04-30.md](/mnt/d/Programs/LEXO/Docs/History/2026-04-30.md)

### 2026-05-01
- Сессия: Fail-closed финализация книги при unresolved QA-blocking сегментах, strict-equivalence для `everyone/everybody`, полный word-only режим без block/group inheritance и временное отключение 2-го salvage-pass
- Файл: [2026-05-01.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-01.md)

### 2026-05-02
- Сессия: Глубокий reverse-analysis `2Books`, извлечение живого `tap #1` runtime-контракта, page payload формата, alignment-priors и локального staging/build-path через live monitoring эмулятора
- Файл: [2026-05-02.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-02.md)

### 2026-05-04
- Сессия: Доказана двухстадийная сборка `2Books` page payload: ранний source skeleton и поздний bilingual enrichment для `tap #1`
- Файл: [2026-05-04.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-04.md)

### 2026-05-05
- Сессия: Удалена локальная модель `mistral-small-3.1-24b-instruct-2503` из `data/models`
- Файл: [2026-05-05.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-05.md)

### 2026-05-13
- Сессия: Backend снесён до source-only reader каркаса; translation/alignment/QA pipeline удалён, TTS оставлен; подключён read-only словарь на тап по `source_words`; dictionary output переведён на чистый список статей без выбора "лучшего" перевода
- Файл: [2026-05-13.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-13.md)

### 2026-05-19
- Сессия: Создано отдельное production mobile приложение Nove, Workbench для zip-книг и автономная Library с bundled zip import, обложками, деталями книги и ручным избранным
- Файл: [2026-05-19.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-19.md)

### 2026-05-21
- Сессия: Подготовлена облачная библиотека Nove через Cloudflare R2: Workbench sync-кнопка, генерация `library_index.json`, mobile cloud catalog fallback
- Файл: [2026-05-21.md](/mnt/d/Programs/LEXO/Docs/History/2026-05-21.md)
