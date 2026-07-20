# История LEXO

Этот файл хранит только оглавление истории по датам.

## Записи

### 2026-07-20
- Пять проверенных UK-книг главы 1 применены к трём UK Globals: добавлены/дополнены Words и Blocks, создано 32 украинских Function Words описания; повторный preview идемпотентен, все пять книг имеют статус `fully_applied`.
- Завершён UK Book Audit всех пяти книг главы 1: исправлены украинские сегментные переводы, созданы четыре обязательных UK-артефакта на книгу, все 752 occurrences и 24 block-occurrences проверены с `unresolved=0`; пять книг имеют статус `valid` без расхождений с RU-структурным эталоном.
- POS fallback в Mobile Reader теперь ведёт `AUX + ADP/DET/ADJ` до именной вершины и строит параллельный перевод по проверенному расширенному target-span, без hardcoded-слов.
- Подсветка multi-word групп в Mobile Reader стала непрерывной: внутренние пробелы получают общую заливку, а отдельные слова визуально не объединяются.
- Проверенная occurrence ownership теперь доходит из Workbench до Reader без потерь: POS fallback не переопределяет английские tap-блоки, а расширенная подсветка параллельного перевода остаётся независимой.
- Добавлен полный target-side coverage: Workbench переносит проверенные insertion/restructure spans в пакет, Reader отделяет расширенную подсветку от точного значения карточки, а RU audit/validator запрещают бесхозные русские токены и случайное nearest-word угадывание.
- Исправлен миграционный gate: строгий target coverage применяется только к книгам с явно созданным полем `target_coverage`, поэтому старые проверенные книги без Pass 5 снова собираются, а уже мигрированные остаются fail-closed.
- Исправлен Workbench null при refresh старых verified alignments: target-span теперь безопасно инициализирует набор занятых индексов независимо от пути выбора alignment.
- Mobile Reader автоматически перечитывает активную книгу при изменении её `content_hash`, поэтому атомарное обновление пакета больше не оставляет старую версию в памяти.
- RU Function Words переведены на отдельные карточки фактических форм: Global-скилл автоматически находит `am/is/are/does` по проверенным occurrences, требует полное описание каждой формы, а Reader показывает нажатую форму вместо подмены общей леммой `be`.
- Workbench исправлен для безопасной публикации RU-only/UK-only пакетов: новый `reader_lexicon` распознаётся как словарь, отсутствие второго языка не блокирует готовность, а CloudLibrary/R2 cleanup больше не удаляет книгу из-за неполного output.
- Создан `$lexo-add-uk-books-to-globals`: выбранные полностью проверенные UK-книги безопасно добавляются в три UK Globals с идемпотентностью, provenance и украинским Function Words audit.
- Создан `$lexo-uk-book-audit`: UK-книги теперь получают тот же строгий четырёхфайловый и occurrence-level контракт, что RU, но украинские значения создаются заново по EN/UK с RU только как структурным эталоном.
- Mobile Reader привязывает `AUX` через `ADP` к смысловой вершине и показывает пояснение Function Word даже без отдельного перевода.
- RU Global merge расширен проверяемым слоем Function Words: пять книг главы 1 полностью покрыты локализованными грамматическими описаниями, отсутствующие записи теперь блокируют добавление.
- RU Globals обновлены из всех пяти проверенных книг главы 1: четыре новые книги применены инкрементально, повторный preview идемпотентен, все пять имеют статус `fully_applied`.
- Три RU dictionary skills сведены к двум: старый `$lexo-build-ru-book-layer` объединён с автономным `$lexo-block-audit` и удалён; отдельный `$lexo-add-ru-books-to-globals` сохранён для Globals.
- Завершён RU Block Audit всех пяти книг главы 1: для четырёх оставшихся книг созданы проверенные seeds/layers/word-to-word, все книжные валидаторы прошли с `unresolved=0`; Globals и runtime-артефакты не менялись.
- `$lexo-block-audit` ограничен RU-книгами; универсальные языковые пути и имена артефактов заменены на RU-контур.
- Репозиторий подготовлен как полный исходный проект: добавлены актуальный Block-контур, карта Workbench/backend/mobile/Skills, безопасная граница локальных данных и инструкции запуска.
- Phrase-контур заменён на Block-контур: введены три глобальных словаря Words/Blocks/Function Words, создан `$lexo-block-audit`; Global Block хранит общее и несколько контекстных значений, occurrence использует точный target-span (`the rest of → конца`), обновлены backend/reader/mobile и пересобраны 10 RU/UK ZIP.
- Mobile detail sheet оформляет `Blocks` как отдельный контейнер с вложенной карточкой, словарным значением, типом и пояснением; контекстный перевод сохранён отдельно для заголовка и подсветки.
- Файл: [2026-07-20.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-20.md)

### 2026-07-16
- `dictionary_<lang>.json` и `word_to_word_<lang>.json` объединены в нормализованный `reader_lexicon_<lang>.json` v3 без повторения словарных переводов в occurrence-alignments; пересобраны 10 RU/UK ZIP, добавлен legacy read-fallback.
- Файл: [2026-07-16.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-16.md)

### 2026-07-15
- POS grammar-группы переведены на полное occurrence-span покрытие всех значимых компонентов без hardcoded-слов; сохранены индексы word-to-word, `into Room → в комнату` подтверждено live.
- Detail sheet приведён к единому формату `Words`: жёлтый dictionary-блок удалён, слова расположены вертикально и каждое получило собственную кнопку сохранения с выбором переводов.
- GitHub push закреплён через существующий Git Credential Manager без лишнего требования `gh auth`; для mixed worktree обязателен выборочный staging.
- Добавлена актуальная карта Virgil: расширен App README и создан подробный документ архитектуры с mobile/Workbench/R2 и dictionary data flow.
- Detail sheet разделён по источникам: `Words` строится только из книжного dictionary/Globals, а word-to-word используется только для contextual header и параллельной подсветки.
- Reader больше не отключает standalone tap и detail card только по служебному POS: точные `and → и` и `at → на` доступны, long press карточки работает, phrase/grammar ownership сохранён.
- Workbench Dictionary refresh переведён на односторонний контур Globals → книжный dictionary → word-to-word: seed/book layer/Globals не изменяются; The Wrong Classroom проверен 81/81, missing 0, 5 фраз.
- Словарные skills ограничены четырьмя собственными файлами без globals/ZIP; добавлен обязательный occurrence-level `word_to_word_ru.json` с блокирующей проверкой всех слов, ownership и phrase-блоков.
- `The Wrong Classroom` пересобран новым контрактом: 146/146 occurrences, 5 единых phrase-блоков, `unresolved=0`, оба валидатора без ошибок; ZIP и globals не обновлялись.
- RU Globals вручную очищены; создан `$lexo-add-ru-books-to-globals` для инкрементального добавления только выбранных seed-книг с double audit, skip/new-translation логикой и отчётом покрытия.
- `The Wrong Classroom` выборочно добавлен в RU Globals: 81 word key/100 переводов и 5 фраз; повторный прогон 105/105 `skipped_existing`, остальные 9 книг не применены.
- Файл: [2026-07-15.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-15.md)

### 2026-07-14
- Из production-контура словарей, QA, POS и TTS удалены hardcoded-слова, фразы, переводы, книжные ID/исключения и языковые таблицы; добавлен guard-тест, пересобраны 10 RU/UK пакетов, global rebuild идемпотентен.
- Добавлен `$lexo-build-ru-book-layer`: создание контекстного RU book layer и seed-файлов по EN/RU текстам с обязательным независимым вторым проходом и валидатором.
- Skill полностью прогнан на `The Wrong Classroom`: 24 RU-пары, 81 контекстное слово, 25 доказанных фраз, второй проход `unresolved=0`; globals и пакеты пересобраны идемпотентно.
- Исправлен word ownership RU-слоя: 11 phrase-absorbed function keys сохранены во всех seed/layer/package артефактах с пустыми переводами и `empty_reason`; global fallback заблокирован, skill запрещает значения вида `the → комната`, backend 24/24.
- `$lexo-build-ru-book-layer` усилен обязательным третьим word-ownership audit: решения по каждому `lemma|POS`, reverse target ownership и блокирующая сверка seed/phrase/layer; прежние противоречия The Wrong Classroom теперь обнаруживаются валидатором.
- The Wrong Classroom повторно прогнан через Pass 3: 81/81 word decisions, `be|AUX`/`be|VERB` пустые, исправлены ownership `at`/`to`/`for`/`of`; validator 0 errors, backend 24/24, RU rebuild `changed=false`, пакеты пересобраны.
- Фразовые skills переведены на строгий meaning-loss критерий с блокирующим necessity Pass 4; The Wrong Classroom сокращён с 25 до 6 необходимых фраз, 19 композиционных групп отклонены, validators 0 errors, backend 24/24, RU globals 53 phrases и `changed=false`.
- Phrase JSON очищен от полных сегментов и audit prose: evidence хранится ссылками `segment_indexes`, `seed_phrases_ru.json` содержит только компактные словарные поля; исправлены `????????`, добавлен encoding guard, validators 0 errors и backend 24/24.
- Файл: [2026-07-14.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-14.md)

### 2026-07-13
- Mobile grammar blocks получили reorder-aware разбиение: `is a new` → `новая`, `student` → `ученица`, `at Hill` → `Хилл`, `School` → `школы`; добавлен regression-тест обратного порядка target spans.
- Library dictionary обновлён до v2: контекстные словоформы и provenance RU/UK, контекстный word-to-word выбор; пересобраны 10 актуальных двуязычных пакетов.
- Word-to-word стал occurrence-level: каждое `word_id` сопоставляется с незанятым target-span текущего предложения; исправлены `English`/`class`/`Room`/`fourteen` в The Wrong Classroom.
- Phrase/detail контур очищен от legacy Source-first: phrase хранит общий перевод и components, а Words показывает отдельные `word_to_word` (`walk` → `входит`, `into` → `в`).
- Добавлен репозиторный Codex skill `$lexo-phrase-audit`: два прохода по всем parallel-сегментам, строгая phrase/components schema, omission audit, валидатор и восстановимый установщик.
- Файл: [2026-07-13.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-13.md)
### 2026-07-10
- Mobile package/detail flow переключён на новый word_to_word alignment: language-specific alignment сохраняется из ZIP, Refresh dictionaries обновляет word-to-word, detail sheet строится из dictionary alignment и показывает unit-level слова.
- Исправлен multi-language Refresh dictionaries при едином стабильном book_id: языковые слои разделены, пересобраны RU/UK seeds и layers пяти текущих книг Chapter 1.
- Закрыт partial-manifest case Workbench dictionary refresh: неполная языковая карта дополняется единым стабильным book_id.
- Mobile reader сохраняет phrase-блоки, показывает их слова отдельными блоками в карточке, выводит полный переводной сегмент и отключает standalone tap служебных слов.
- Добавлены POS-driven grammar blocks: `DET/AUX/PART` структурно присоединяются к lexical head без hardcoded-слов и ложных отдельных переводов.
- Файл: [2026-07-10.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-10.md)

### 2026-07-09
- Добавлен первый RU-прототип library dictionary: `book_layer_ru.json`, накопительные `global_words_ru.json`/`global_phrases_ru.json`, lookup через global words с fallback на Virgil Core и endpoint rebuild для одной книги.
- Library dictionary распространён на все актуальные книги A1 Chapter 1 для RU/UK: per-book word/phrase seeds, book layers и чистые global words/phrases пересобраны.
- Файл: [2026-07-09.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-09.md)

### 2026-07-03
- Из Virgil mobile убран тестовый AdMob/interstitial-контур; текст `Поддержка проекта` сохранён в store-сырьё и release-материалы как будущая стратегия окна `Что нового`.
- Файл: [2026-07-03.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-03.md)

### 2026-07-02
- Исправлено фактическое подключение review-exit interstitial и защита загрузки рекламы до инициализации SDK.
- Выход из swipe-review уточнён: interstitial показывается только после минимум 3 действий с карточками.
- В Virgil mobile подключена тестовая Google AdMob interstitial-реклама с правилом: первые 10 минут без рекламы, затем не чаще одного раза в 15 минут.
- Virgil подготовлен к следующему обновлению: pubspec.yaml поднят до 1.0.1+2, Settings будет показывать Version 1.0.1.
- В мобильной карточке книги добавлена проверка package после скачивания и UI-обработка ошибок Load/Open без падения приложения.
- В мобильных Settings удалён раздел языка интерфейса; beta/about-текст перенесён вниз над версией.
- Package id Virgil для Google Play изменён на `com.lexo.virgil`; signed AAB `1.0.0+1` пересобран, Play release package обновлён с новыми checksum; добавлены EN screenshots/feature graphic для default listing.
- Файл: [2026-07-02.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-02.md)

### 2026-07-01
- Собран чистый `Release/GooglePlay/1.0.0` пакет для Play Console: AAB, listing, screenshots, privacy policy, checklists и checksums без ключей.
- Virgil version привязана к `pubspec.yaml`: release `1.0.0+1`, Settings показывает `Version 1.0.0`; AAB пересобран и проверен.
- Подготовлены локальный `public/privacy-policy.html` и скрипты публикации GitHub Pages; GitHub connector не смог записать файл из-за 403.
- Privacy policy page упрощена до одной английской версии для Play Console.
- Подготовлена статическая EN/UK/RU privacy policy page для публикации URL в Google Play Console.
- Файл: [2026-07-01.md](/mnt/d/Programs/LEXO/Docs/History/2026-07-01.md)

### 2026-06-30
- Подготовлен Google Play listing package: UK/RU описания, release notes, privacy policy drafts, feature graphics и Data Safety checklist.
- Проведён Google Play release audit Virgil: AAB собирается, targetSdk=36, тесты проходят; выявлены риски по секретам, store materials и Data Safety.
- Google Play promo screenshots разнесены по языковым папкам `uk` и `ru`; генератор получил параметр `-Language uk|ru`.
- Google Play promo screenshots очищены: тонкая рамка телефона, без лишней подложки, обновлены украинские тексты для 6 карточек.
- Пересобраны 6 Google Play promo screenshots 1080x1920 для Virgil из реальных скринов приложения, подписи заменены на украинские.
- Заменён launcher icon Virgil: добавлен 1024px master и пересобраны iOS/Android PNG.
- В мобильный Settings добавлена английская строка Version 1.0.0.
- В мобильный Settings добавлен выбор языка интерфейса RU/UK и переключаемая beta-надпись под ним.
- В A1 Workbench/CloudLibrary словарях заполнены пустые RU/UK word-card entries: в Core добавлены только новые ключи, существующие entries не изменялись; повторный аудит показал missing=0.
- Файл: [2026-06-30.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-30.md)

### 2026-06-26
- В Virgil добавлен первый экран выбора языка перевода после установки: он появляется только до создания mobile_settings.json.
- Файл: [2026-06-26.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-26.md)

### 2026-06-25
- Workbench Clean selected переведён на scoped-очистку отмеченных text/dictionary/Kokoro voice artifacts без удаления невыбранных частей книги; добавлен backend endpoint для очистки TTS выбранных voices.
- Файл: [2026-06-25.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-25.md)

### 2026-06-24
- Ошибочная обработка 9 TTS WAV-сегментов в `book_bdcc11162ee4` отменена; из ZIP `A Voice from Online` извлечён slow-сегмент MP3, созданы тестовые копии с увеличенными паузами x1.5/x2/x2.25/x4.5, clean/smooth/fade100/soft-edges/envelope/edges-x3 x4.5-версии, pitch-preserving копия дорожки x1.5 и цельные Kokoro slow WAV для двух абзацев на speed 0.85/0.75/0.70/0.65/0.60, цельный no-split speed 0.60 и word-by-word speed 0.60.
- Файл: [2026-06-24.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-24.md)

### 2026-06-22
- В `A Voice from Online` исправлено побуквенное `W-A-L-K-E-R` на `WALKER`: обновлены TXT/Corpus, Core и book seed, RU/UK JSON, один reader-сегмент и его TTS для `af_heart`; остальные тексты проверены.
- Сетка книг главы стала адаптивной: две увеличенные колонки на узком экране, три колонки на широком, обложки 2:3 и ограничение ширины 180 px.
- Файл: [2026-06-22.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-22.md)

### 2026-06-19
- В десяти RU/UK JSON главы 9 заполнены 338 пустых вхождений: создано 86 новых Core-статей без изменения существующих; пустых записей в главе не осталось.
- Для актуальных New Student и Grandma's Dinner штатно пересобраны четыре словарных JSON; source TXT, package manifest и неизменность остальных файлов проверены.
- Удалены два stale output-каталога старых New Student и Grandma’s Dinner; актуальные замены проверены, старых ID и дублей больше нет. В новых словарях главы 9 отдельно зафиксированы 338 пустых вхождений.
- В существующих RU/UK словарных JSON заполнены 730 пустых вхождений: создано 227 новых точных Core-статей без изменения 778 существующих; пустых записей больше нет.
- Созданы и проверены пять финальных обложек A1 Chapter 10 `Numbers & Money`; после QA банкноты с псевдознаками на `The Phone Fund` заменены чистой версией.
- Файл: [2026-06-19.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-19.md)

### 2026-06-18
- Созданы и проверены пять финальных обложек A1 Chapter 9 `Weather & Nature` в едином стиле серии с акцентом teal.
- Созданы и проверены пять финальных обложек A1 Chapter 8 `City & Transport`; после QA удалена случайная псевдонадпись на одном из вариантов.
- Созданы и проверены пять финальных обложек A1 Chapter 7 `Clothes & Shopping`; сцены построены по полным текстам, сюжетным брифам и универсальному контракту серии.
- Созданы и проверены пять финальных обложек A1 Chapter 6 `Daily Routine & Time` в формате 1024 x 1536 RGB PNG.
- Выполнен полный A1 quality pass `Virgil Core Dictionary`: исправлены 88 статей RU/UK, ложные title-`PROPN` переведены на lexical fallback, пересобраны словари 27 книг и 15 локальных CloudLibrary ZIP.
- Добавлены 45 точных отсутствующих ключей; после обновления 42 manifest-ов и 9 ZIP пустых RU/UK словарных значений не осталось.
- Удалены фильтры книг по `plan/план`: Workbench исключает только `chapter_images`, поэтому настоящие книги `Plant` и `Plan` больше не скрываются в Workbench/mobile.
- Файл: [2026-06-18.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-18.md)

### 2026-06-17
- Исправлены явные русские значения в украинском разделе `Virgil Core Dictionary`; mobile package теперь всегда включает оба словарных manifest-а `ru` и `uk`.
- Core дополнен очевидными word-level соответствиями из RU/UK переводов A1 Chapter 1; в README словаря добавлена инструкция segment-derived enrichment для будущих книг.
- Core обновлён по пяти свежим книгам A1 Chapter 2 (`Family`): добавлены полезные entries, шумные POS/title-ключи оставлены вне словаря.
- Core обновлён по 15 актуальным книгам A1 Chapters 3-5; старый `Late for Class` output и stale-обложки удалены.
- В `Virgil Core Dictionary` выполнен quality pass: широкие внешнесловарные значения сжаты до A1-смыслов, `wrong|PROPN` удалён.
- Из Core удалены явно плохие внешнесловарные значения вроде `bag = уродина`, `chicken = ссыкун` и metadata-пометки.
- Исправлен Workbench `Start`: действия берут только выбранные книги, видимые после применённых фильтров.
- Исправлен Workbench source-фильтр: `A Plant by the Window` больше не скрывается как `plan`.
- Book Library сохраняет фильтры при прокрутке, а общий checkbox выбора теперь умеет снимать выбор.
- Google Translation `5000` переведён в скрытый warning threshold; confirmation-dialog убран до block limit `495000` при free tier `500000`.
- Файл: [2026-06-17.md](/mnt/d/Programs/LEXO/Docs/History/2026-06-17.md)

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
