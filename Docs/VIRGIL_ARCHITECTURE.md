# Архитектура Virgil

Этот документ — актуальная карта связей мобильного приложения, Workbench,
backend и книжных данных. Источник истины для деталей — текущий код; история
принятых изменений находится в `Docs/History/INDEX.md`.

## 1. Границы проекта

- `Virgil/App/` — единственный активный Flutter-клиент.
- `Studio/Workbench/Books/` — исходные тексты и обложки книг.
- `Studio/Backend/` — локальный API, обработка книг, словари, TTS и базы данных.
- `Studio/Runtime/workbench_output/` — собранные папки и ZIP-пакеты книг.
- `Studio/CloudLibrary/` — локальное зеркало публикуемого каталога R2.
- `Release/` — выходные Android/iOS и store-материалы; не runtime-источник книг.
- `Archive/` — legacy, не участвующий в актуальных потоках.

## 2. Точки входа

`Virgil/App/lib/main.dart` выполняет общую инициализацию Flutter, MediaKit и
background audio, затем вызывает `runLexoApp()`.

`Virgil/App/lib/src/app.dart` выбирает режим compile-time параметром
`VIRGIL_MODE`:

- `mobile` -> `MobileShellScreen`;
- `workbench` -> `VirgilWorkbenchScreen`;
- при неизвестном режиме используется ширина окна как запасной выбор.

Основные команды из корня workspace:

- `START_VIRGIL.bat` — Android development build;
- `START_WORKBENCH.bat` — backend + Windows Workbench;
- `BUILD_RELEASE.bat` — Google Play AAB;
- `BUILD_IOS.bat` — публикация обновления и запуск GitHub iOS build.

## 3. Мобильные экраны и ответственность

- `mobile_shell_screen.dart` — нижняя навигация и корневой mobile shell.
- `mobile_library_screen.dart` — облачный/локальный каталог книг.
- `virgil_book_detail_screen.dart` — карточка книги, загрузка и открытие.
- `mobile_reader_catalog_screen.dart` — каталог доступных глав Reader.
- `mobile_reader_screen.dart` — чтение, tap/long press и управление плеером.
- `mobile_settings_screen.dart` — мобильные настройки.
- `mobile_language_setup_screen.dart` — выбор языка перевода.

Карточки сохранённых слов обслуживаются `mobile_cards_repository.dart` и
соответствующими экранами/моделями. Аудио и фоновое воспроизведение находятся в
`mobile_audio_handler.dart` и reader playback widgets.

Рекламного runtime-контура в текущем Virgil нет. Старые записи о рекламе в
истории относятся к удалённой реализации и не являются актуальной архитектурой.

## 4. Доставка и открытие книги

Поток мобильной библиотеки:

```text
Cloudflare R2 library_index.json
  -> выбор книги
  -> загрузка ZIP
  -> распаковка в локальное хранилище приложения
  -> создание/чтение package.json
  -> выбор языковых reader/dictionary/word_to_word
  -> полностью локальный Reader
```

Ключевой класс — `VirgilBundledBookRepository`. Он загружает индекс и ZIP,
проверяет пакет, читает языковые JSON и сохраняет нормализованный локальный
`package.json`. `MobilePackageRepository` перечисляет установленные пакеты,
открывает их и подготавливает reader/detail модели.

`mobile_package_reader_language.dart` переключает активные payload по выбранному
языку перевода без повторной загрузки книги.

## 5. Состав книжного пакета

Workbench создаёт языковые файлы и описывает их в manifest/package metadata:

- `reader_<lang>.json` — параллельные сегменты, source words и данные Reader;
- `dictionary_<lang>.json` — книжный срез слов и фраз из Global dictionaries;
- `word_to_word_<lang>.json` — occurrence-level параллельное сопоставление;
- `word_to_word.json` — совместимый alias языка по умолчанию;
- аудиофайлы, обложка и прочие перечисленные package assets.

Локальный мобильный `package.json` объединяет выбранный reader payload,
словарные manifests и word-to-word по языкам. Reader не обращается к backend во
время обычного чтения установленной книги.

## 6. Владение словарными данными

### Global Words

`Studio/Backend/data/dictionaries/library_<lang>/global_words_<lang>.json` —
накопительный источник уникальных `lemma|POS` и их переводов. При добавлении
книги одинаковое значение пропускается; новый контекстный перевод сохраняется
как вариант.

### Global Blocks

`global_blocks_<lang>.json` — накопительный источник минимальных переиспользуемых
многословных значений. Блок нужен только тогда, когда смысл нельзя корректно
восстановить независимыми переводами составляющих слов. Каждый блок хранит тип,
переводы, формы, компоненты, provenance и короткое универсальное пояснение.

### Global Function Words

`global_function_words_<lang>.json` хранит пояснения служебных слов. Вместе с
Global Words и Global Blocks это третий и последний глобальный словарь языка.

### Book dictionary

`dictionary_<lang>.json` создаётся Workbench для конкретной книги из текущих
Global Words, Global Blocks и Global Function Words. Это производный, доступный offline слой. Раздел
`Words` в detail sheet получает переводы слов именно отсюда по `lemma|POS`.

### Word-to-word

`word_to_word_<lang>.json` строится после книжного словаря. Он связывает каждое
вхождение source word с target span и хранит contextual translation, владельца
tap-блока, phrase/grammar grouping и причины отсутствия самостоятельного
соответствия.

Word-to-word не является словарём значений для раздела `Words`. В UI он отвечает
за контекстный заголовок карточки, параллельную подсветку и границы общего блока.

## 7. Односторонняя пересборка словаря

Команда обновления Dictionary в Workbench должна выполнять только этот поток:

```text
Global Words + Global Blocks + Global Function Words
  -> book dictionary_<lang>.json
  -> word_to_word_<lang>.json по тексту и параллельным сегментам
  -> обновление package/ZIP
```

Она не должна читать skill-owned проверочный word-to-word как runtime-источник,
пересобирать seed-файлы, изменять book layer или переносить данные книги обратно
в Globals.

Seed/book-layer skills и skill-owned `word_to_word_ru.json` используются для
создания и внутренней проверки словарных файлов. Они не являются мобильным
runtime-контрактом и сами не обновляют ZIP.

## 8. Построение и публикация книги

`VirgilWorkbenchBuilder` получает backend package, записывает языковые reader,
dictionary и word-to-word файлы, собирает package metadata и ZIP.

Workbench поддерживает два разных действия:

- пересборка локальных артефактов выбранной книги;
- публикация готовых пакетов в R2 и обновление каталога.

При публикации `library_index.json` создаётся из локального CloudLibrary и
загружается последним. Это не позволяет мобильному каталогу увидеть запись до
того, как доступен сам пакет.

## 9. Backend

- `engine/main.py` — запуск backend;
- `engine/api.py` — HTTP API;
- `engine/storage.py` — хранение книг, reader payload, dictionary manifests,
  package export и карточки;
- `engine/library_dictionary.py` — доступ к Global/книжным словарным данным;
- `engine/source_pos_lemma.py` и `engine/tokenization.py` — source morphology;
- `engine/tts/` — генерация и кэширование речи;
- `tests/` — backend regression tests.

Workbench обращается к backend через `Virgil/App/lib/src/api/api_client.dart`.
Мобильное чтение уже установленного пакета от backend не зависит.

## 10. Проверка изменений

Минимальная проверка зависит от изменённого контура:

- Flutter UI/models/repositories: `flutter analyze` и релевантные Flutter tests;
- backend/dictionary pipeline: Python unit tests соответствующего модуля;
- package builder: пересборка тестовой книги и сверка созданных JSON/ZIP;
- mobile runtime: установка debug APK и проверка выбранной книги в эмуляторе;
- документация: проверка ссылок, путей и `git diff --check`.

## 11. Где искать актуальное решение

1. `Docs/History/INDEX.md` — какие существенные решения уже приняты.
2. Этот документ — связи контуров и владельцы данных.
3. `Virgil/App/README.md` — быстрый вход в Flutter-код.
4. `Studio/Workbench/README.md` — запуск и директории Workbench.
5. Текущий код — окончательный источник истины при любом расхождении.

Планы и отвергнутые варианты не дублируются здесь: их следует фиксировать в
истории или отдельном плане, чтобы архитектурная карта описывала только реально
работающий контур.
