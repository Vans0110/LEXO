# MVP21 — Source-First Segmentation and Coverage Rewrite Plan

## 1. Цель

Перестроить текущий pipeline `segment -> translation -> word alignment -> tap unit` в архитектуру:

- `source-first`
- `unit-first`
- `relation-aware`
- без словарей как primary logic
- без подгонки под конкретную книгу

Главная продуктовая цель:

- перевод сегмента может оставаться естественным
- учебная логика должна быть стабильной
- слово, группа слов и блок должны разбираться из `source`
- `target` должен только подтверждать покрытие
- если покрытие ненадёжно, система не должна врать

---

## 2. Главная проблема текущего состояния

Сейчас проект работает по legacy-модели:

1. `segmenter` режет текст в основном как предложения с несколькими special-case правилами.
2. `translator` переводит каждый segment rule-first или provider-first.
3. `word_alignment` пытается раздать target токены source словам.
4. поверх уже построенного word mapping собираются `tap units`.
5. QA и validation режут часть ложных совпадений post factum.

Это рождает системный дефект:

- смысловой блок не является первичной сущностью
- сначала ломается word mapping
- потом UI и tap unit пытаются это маскировать
- на одной книге это выглядит “почти хорошо”
- на другой книге начинает сыпаться

---

## 3. Анализ текущего кода

## 3.1 Сегментация

Текущий вход в сегментацию:

- [engine/segmenter.py](/mnt/d/Programs/LEXO/engine/segmenter.py)

Что делает `split_study_segments(...)` сейчас:

- special-case:
  - `Chapter ...`
  - `Chapter N: Title`
  - `At 10:00 AM`
  - `In the morning/afternoon/evening`
  - short title line
- иначе режет почти sentence-based через punctuation split

Что это значит:

- typed segmentation почти не реализована
- `sentence ~= segment`
- сегмент часто слишком широкий для стабильного учебного анализа

Ограничения текущего слоя:

- нет entity/reporting/dialogue-aware segmentation
- нет разрезания на subject/predicate/object groups
- нет разрезания coordination внутри clause
- нет специального path для `formula`, `reporting`, `action group`, `object group`

---

## 3.2 Запросы к модели перевода

Текущий вход:

- [engine/translator.py](/mnt/d/Programs/LEXO/engine/translator.py)
- [engine/storage.py](/mnt/d/Programs/LEXO/engine/storage.py)

Как сейчас строится перевод:

1. `storage._build_paragraph_payloads(...)` вызывает `split_study_segments(...)`
2. затем `translate_segment_batch(...)`
3. если есть `target_text` в самом segment spec, перевод не запрашивается
4. если `resolve_didactic_translation(...)` вернёт rule translation, модель не вызывается
5. иначе вызывается provider
6. затем `storage._select_segment_translation(...)` прогоняет QA
7. при проблемах идут:
   - `top-5 nbest`
   - merge retry
   - fallback provider

Текущая модель запросов к provider:

- запрос идёт не на unit, а на целый segment
- segment type почти не влияет на формат запроса к модели
- нет source-unit-aware prompting
- нет отдельного semantic contract для coverage

Текущее состояние `didactic_rules`:

- [engine/didactic_rules.py](/mnt/d/Programs/LEXO/engine/didactic_rules.py)
- сейчас rule-first didactic layer фактически пустой

Это хорошо:

- в текущем runtime уже нет большого слоя post-edit словарей после provider

Но это не решает проблему:

- смысловой анализ всё равно не вынесен в source-first слой

---

## 3.3 Текущий alignment

Текущий вход:

- [engine/word_alignment.py](/mnt/d/Programs/LEXO/engine/word_alignment.py)

Текущий pipeline `build_word_mappings(...)`:

1. tokenize source / target
2. найти hard anchors
3. `_assign_window_targets(...)`
4. function words наследуют target
5. применяются special overrides
6. выполняется validation
7. только после этого строятся `tap units`

Критический дефект архитектуры:

- unit не управляет alignment
- unit строится из уже готового alignment
- coverage вторичен, но притворяется первичным

Следствие:

- `wake up`
- `good morning`
- `How are you`
- `Anna says`
- `orange juice`
- coordination и reorder

могут вести себя по-разному на разных книгах и разных переводах

---

## 3.4 Текущий segment QA

Текущий вход:

- [engine/segment_quality.py](/mnt/d/Programs/LEXO/engine/segment_quality.py)

Сильные стороны:

- direct target layer уже есть
- RU quality layer уже есть
- entity/frame/verb/relation layers уже есть
- retry pipeline уже существует

Слабые стороны:

- QA оценивает качество segment translation
- QA не валидирует source-unit graph
- QA не валидирует typed segmentation
- QA не валидирует group/relation coverage отдельно от whole-segment verdict

Итог:

- segment translation может быть хорошим
- а учебная сегментация и coverage при этом плохими

---

## 3.5 Текущее `v2_core`

Текущий вход:

- [engine/v2_core/source_analyzer.py](/mnt/d/Programs/LEXO/engine/v2_core/source_analyzer.py)
- [engine/v2_core/lookup.py](/mnt/d/Programs/LEXO/engine/v2_core/lookup.py)
- [engine/v2_core/coverage.py](/mnt/d/Programs/LEXO/engine/v2_core/coverage.py)
- [engine/v2_core/models.py](/mnt/d/Programs/LEXO/engine/v2_core/models.py)

Сильные стороны:

- уже есть правильное направление:
  - `SourceUnit`
  - `LookupResult`
  - `TargetCoverage`
  - `CoverageStatus`

Проблемы текущего `v2_core`:

- сам `source_analyzer` пока pattern-list based
- `lookup` пока держится на ручных phrase/grammar/lexical словарях
- `coverage` пока держится на `NORMALIZED_EQUIVALENTS`
- это пока sandbox/demo path, а не production architecture

Итог:

- `v2_core` полезен как каркас данных
- но его текущую реализацию нельзя просто перенести в production как есть

---

## 4. Все текущие вшитые словари и списки, которые надо вывести из primary logic

Ниже перечислено то, что либо уже влияет на runtime, либо заложено в V2-прототипе и не должно стать production-истиной.

## 4.1 Runtime-слой `word_alignment.py`

### A. `ANCHOR_TRANSLATIONS`

Текущее назначение:

- `chapter -> глава`
- `am -> утра`
- `pm -> дня/вечера`

Почему убрать из primary logic:

- anchor не должен зависеть от ручного target token dictionary
- `AM/PM` должны определяться как `META/TIME`
- `chapter` должен определяться как `META/HEADING`

Замена:

- source type detection
- meta parser
- target coverage по typed meta block

### B. `REPORTING_VERB_TRANSLATIONS`

Текущее назначение:

- ручной список reporting verb translation candidates
- rescue/fix reporting verb target

Почему убрать:

- это список словоформ, а не класс действия
- не масштабируется
- ломается на новых книгах и новых глаголах

Замена:

- source predicate class = `REPORTING`
- target-side reporting predicate detection
- frame-preservation check для reporting relation

### C. `_target_possessive_candidates_for_source(...)`

Текущее назначение:

- `his -> его`
- `her -> её`
- и т.д.

Почему убрать:

- relation `owner -> object` нельзя сводить к токенам

Замена:

- possessive relation graph
- target-side relation preservation

### D. `_target_noun_candidates_for_possessive_pair(...)`

Текущее назначение:

- частные noun rescue пары:
  - `dog`
  - `cat`
  - `friend`
  - `book`
  - и т.д.

Почему убрать:

- book/task-specific leakage
- неуниверсально

Замена:

- object relation coverage
- noun phrase head detection

### E. Жёсткие lexical classes внутри aligner

Сейчас используются как structural shortcuts:

- `PARTICLE_WORDS`
- `TIME_OF_DAY_WORDS`
- `QUESTION_MODIFIER_WORDS`
- `NUMBER_WORDS`
- `CLOCK_MARKER_WORDS`
- `PRONOUN_WORDS`
- `ARTICLE_WORDS`
- `COPULA_WORDS`
- `PREPOSITION_WORDS`
- `CONJUNCTION_WORDS`

Что важно:

- не все эти списки надо удалить из кода
- но они не должны быть primary meaning layer

Разделение:

- допустимо оставить closed-class grammar inventories:
  - articles
  - prepositions
  - conjunctions
  - pronouns
  - auxiliary/copula
  - AM/PM markers
  - clock markers
- недопустимо использовать их как substitute for semantic understanding

То есть:

- closed-class inventories допустимы как grammar parser infrastructure
- lexical translation lists недопустимы как источник истины

---

## 4.2 Prototype-слой `v2_core`

### F. `PHRASE_PATTERNS`

Сейчас:

- `wake up`
- `look at`
- `good morning`
- `have to`

Почему убрать из production primary logic:

- это маленький curated phrase list

Замена:

- phrasal verb detector
- formula detector
- construction detector

### G. `GRAMMAR_PATTERNS`

Сейчас:

- `it is`
- `there is`
- `going to`
- `used to`
- `do not`

Что делать:

- не использовать как final hardcoded список
- заменить grammar construction recognizer-ом

### H. `PHRASE_TRANSLATIONS`

Сейчас:

- ручной phrase dictionary в [engine/v2_core/lookup.py](/mnt/d/Programs/LEXO/engine/v2_core/lookup.py)

Убрать из primary logic.

### I. `GRAMMAR_EXPLANATIONS`

Сейчас:

- ручной explanation list

Что делать:

- можно временно оставить как UI fallback
- нельзя делать из этого production semantic source

### J. `LEXICAL_TRANSLATIONS`

Сейчас:

- большой ручной список английских слов и переводов

Убрать из primary logic полностью.

### K. `NORMALIZED_EQUIVALENTS`

Сейчас:

- ручной target normalization dict в coverage resolver

Убрать из primary logic.

Замена:

- morphological normalization
- lemma/inflection normalization
- target parser

---

## 5. Что допускается оставить

Ниже то, что не является “запрещённым словарём” при правильной роли.

### Допустимо оставить:

- служебные grammar inventories:
  - articles
  - conjunctions
  - prepositions
  - pronouns
  - auxiliaries
  - punctuation classes
  - AM/PM markers
  - clock markers
- number-word parser
- generic title/chapter recognizer
- generic formula of tokenizer/pos/dependency output labels
- auto-built book memory

### Недопустимо оставлять как primary logic:

- ручные lexical translation pairs
- ручные reporting verb translation lists
- ручные possessive noun rescue pairs
- book-specific names
- target-side exact lexical replacement lists
- phrase dictionary как основной способ понять блок

---

## 6. Целевая новая архитектура

Новая архитектура должна быть многослойной.

## 6.1 Слой A. Typed Segmentation

Вместо:

- `sentence ~= segment`

Нужно:

- `segment = minimal analyzable study clause`

Новый typed segmenter должен уметь:

- dialogue split
- reporting clause split
- time/meta split
- coordination split по clause-level predicate
- не резать устойчивые phrase unit-ы и noun phrase head blocks без причины

Минимальные типы segment:

- `heading_title`
- `heading_chapter`
- `time_meta`
- `dialogue_quote`
- `reporting_clause`
- `simple_clause`
- `compound_clause`
- `formula_clause`
- `fallback_sentence`

Ключевой принцип:

- сегмент не обязан равняться учебной единице
- сегмент должен быть контейнером, внутри которого source analysis стабилен

## 6.2 Слой B. Source Token Graph

Для каждого segment строится source graph:

- tokens
- POS/morph
- dependency links
- clause boundaries

Это не словарь.
Это структурный разбор source.

## 6.3 Слой C. Source Units

Поверх token graph строятся unit-ы трёх уровней.

### Уровень 1. Atomic units

- отдельные слова и минимальные unit-ы:
  - `he`
  - `eats`
  - `eggs`
  - `toast`
  - `orange`
  - `juice`

### Уровень 2. Relation links

- `subject_of`
- `object_of`
- `modifier_of`
- `particle_of`
- `coord_with`
- `owner_of`
- `speaker_of`
- `time_of`

### Уровень 3. Group units

- coordinated object group
- noun phrase group
- phrasal verb group
- formula group
- time/meta group
- reporting group

Ключевое правило:

- block не заменяет слова
- block объединяет слова

## 6.4 Слой D. Lookup

Lookup должен строиться source-first.

Источники lookup по приоритету:

1. structural explanation
2. generic grammar explanation
3. generic lemma dictionary / lexical resource
4. model-backed unit lookup fallback

Запрещено:

- ручной curated runtime dictionary как основной semantic source

## 6.5 Слой E. Target Coverage

Coverage ищется не для каждого слова любой ценой, а для unit-а и relation-а.

Статусы:

- `exact`
- `reordered`
- `absorbed`
- `phrase_owned`
- `fuzzy`
- `none`

Coverage должен искать:

- atomic coverage
- group coverage
- relation evidence

Пример:

`orange juice`

должно храниться как:

- `orange` atomic
- `juice` atomic
- `orange -> modifies -> juice`
- `orange juice` noun-phrase group

Coverage может быть:

- для `juice` exact
- для `orange` modifier-attached
- для NP group exact

## 6.6 Слой F. QA

Нужны 4 разные QA-подсистемы:

1. `segment QA`
2. `source graph QA`
3. `coverage QA`
4. `tap payload QA`

### Segment QA

- оценивает качество перевода сегмента как целого

### Source graph QA

- проверяет, что source parse и unit graph валидны

### Coverage QA

- проверяет, что coverage не врёт

### Tap payload QA

- проверяет, что пользователь при тапе видит правильный owner/group/focus

---

## 7. Как должны строиться запросы к модели

## 7.1 Что остаётся

Основной перевод книги по-прежнему можно делать segment-level provider path.

Это значит:

- не нужно сразу переводить каждый unit отдельно
- не нужно ломать текущий provider pipeline на первом этапе

## 7.2 Что меняется

Модель больше не является источником структуры.

Новая роль модели:

1. перевод segment
2. при необходимости n-best candidates
3. optional fallback lookup для missing lexical unit
4. optional arbitration для спорного coverage/relation case

## 7.3 Что модель не должна решать

- где предмет
- где сказуемое
- где coordination
- где modifier/head
- где reporting relation

Это должен решать source analyzer.

## 7.4 Дополнительные model calls, которые допустимы

Только как fallback, не как primary logic:

- unit lookup fallback:
  - для редкого lexical unit без словарного ресурса
- candidate arbitration:
  - между 2-3 уже построенными структурными гипотезами
- segment simplification helper:
  - только в offline debug/rebuild path

---

## 8. Примеры целевой логики

## 8.1 `He eats eggs and toast.`

Source atomic units:

- `he`
- `eats`
- `eggs`
- `toast`

Relations:

- `subject_of(eats, he)`
- `object_of(eats, eggs)`
- `object_of(eats, toast)`
- `coord_with(eggs, toast)`

Group:

- `coordinated_object_group = eggs + toast`

Важно:

- это не словарь `eggs and toast`
- это structural parse

## 8.2 `He drinks orange juice.`

Source atomic units:

- `he`
- `drinks`
- `orange`
- `juice`

Relations:

- `subject_of(drinks, he)`
- `object_of(drinks, juice)`
- `modifier_of(orange, juice)`

Group:

- `noun_phrase = orange juice`

Важно:

- `orange` и `juice` делимы
- но над ними должен жить group block

## 8.3 `Tom wakes up at 7:00 AM.`

Atomic units:

- `Tom`
- `wakes`
- `up`
- `7:00`
- `AM`

Relations:

- `particle_of(up, wakes)`
- `time_of(wakes_up_group, time_group)`

Groups:

- `phrasal_verb_group = wakes up`
- `time_group = 7:00 AM`

## 8.4 `"Good morning, Luna!" Tom says.`

Atomic units:

- `Good`
- `morning`
- `Luna`
- `Tom`
- `says`

Groups:

- `formula_group = good morning`
- `entity_group = Luna`
- `reporting_group = Tom says`

Relations:

- `speaker_of(reporting_group, Tom)`
- `quoted_to(formula_group, Luna)`

---

## 9. Новые сущности данных

Нужно расширить текущий `v2_core` контракт до production-ready структуры.

Минимальные таблицы/контракты:

- `source_tokens_v2`
- `source_units_v2`
- `source_relations_v2`
- `source_groups_v2`
- `unit_lookup_v2`
- `unit_coverage_v2`
- `group_coverage_v2`
- `tap_payload_v2`

Дополнительно:

- `segment_meta_json`
- `analysis_version`
- `coverage_version`
- `qa_version`

Ключевой принцип:

- legacy таблицы пока не удалять
- новый контур строить параллельно

---

## 10. Что удалить или вывести из основного пути

## 10.1 Сразу вывести из primary logic

- `ANCHOR_TRANSLATIONS`
- `REPORTING_VERB_TRANSLATIONS`
- `_target_possessive_candidates_for_source(...)`
- `_target_noun_candidates_for_possessive_pair(...)`
- `v2_core.PHRASE_TRANSLATIONS`
- `v2_core.LEXICAL_TRANSLATIONS`
- `v2_core.NORMALIZED_EQUIVALENTS`

## 10.2 Перевести в “infrastructure only”

- `ARTICLE_WORDS`
- `COPULA_WORDS`
- `PREPOSITION_WORDS`
- `CONJUNCTION_WORDS`
- `PRONOUN_WORDS`
- `PARTICLE_WORDS`
- `TIME_OF_DAY_WORDS`
- `QUESTION_MODIFIER_WORDS`
- `NUMBER_WORDS`
- `CLOCK_MARKER_WORDS`

Новая роль этих списков:

- parser hints
- token class inventories
- grammar detection support

Не новая роль:

- не переводной словарь
- не primary semantic resolver

---

## 11. Поэтапный план изменений

## Этап 1. Freeze legacy и ввести новый production plan

Задачи:

- объявить текущий `build_word_mappings(...)` legacy-only
- зафиксировать, что новые фичи туда не добавляются, кроме bugfix
- зафиксировать новый `analysis_version = v2_source_first`

Результат:

- прекращаем наращивать словари в legacy aligner

## Этап 2. Typed segmenter v2

Файлы:

- `engine/segmenter.py`
- новый модуль `engine/segmenter_v2.py`

Задачи:

- добавить clause-aware segmentation
- добавить dialogue/reporting split
- добавить segment meta
- сохранить backward-compatible assemble path

Проверка:

- новые regression cases на:
  - reporting
  - formula
  - time
  - compound actions

## Этап 3. Production source analyzer

Файлы:

- новый модуль `engine/v2_core/source_graph.py`
- переработка `engine/v2_core/source_analyzer.py`

Задачи:

- уйти от `PHRASE_PATTERNS` и `GRAMMAR_PATTERNS`
- строить units из POS/morph/dependency graph
- ввести:
  - atomic units
  - relations
  - groups

Проверка:

- на examples:
  - `eggs and toast`
  - `orange juice`
  - `wake up`
  - `good morning`
  - `Tom says`

## Этап 4. Lookup rewrite

Файлы:

- `engine/v2_core/lookup.py`
- возможно новый `engine/v2_core/lookup_resources.py`

Задачи:

- убрать `PHRASE_TRANSLATIONS`
- убрать `LEXICAL_TRANSLATIONS`
- убрать grammar-specific hardcoded explanations как primary source
- построить layered lookup:
  - structural explanation
  - grammar explanation
  - generic lexical resource
  - fallback resolver

Проверка:

- lookup остаётся валидным без ручных книжных словарей

## Этап 5. Coverage rewrite

Файлы:

- `engine/v2_core/coverage.py`

Задачи:

- убрать `NORMALIZED_EQUIVALENTS`
- перейти на target token normalization + morphology
- искать coverage для:
  - atomic units
  - groups
  - relations

Проверка:

- coverage не врёт в reorder/absorbed cases

## Этап 6. Storage integration

Файлы:

- `engine/storage.py`

Задачи:

- сохранять новый source graph
- сохранять unit/group coverage
- ввести rebuild path для существующих книг
- не ломать legacy reader сразу

Проверка:

- можно переоценить уже импортированную книгу

## Этап 7. Reader integration

Файлы:

- `app/lib/src/screens/reader_screen.dart`
- `app/lib/src/widgets/interactive_paragraph_text.dart`

Задачи:

- tap должен опираться на new unit/group payload
- user должен иметь:
  - atomic tap
  - owner/group explanation
  - честный coverage status

Проверка:

- не должно быть ложного focus span
- не должно быть UI-дублей

## Этап 8. QA split

Файлы:

- `engine/segment_quality.py`
- новые QA-модули:
  - `engine/source_graph_quality.py`
  - `engine/coverage_quality.py`

Задачи:

- разделить QA на:
  - segment translation QA
  - source graph QA
  - coverage QA

Проверка:

- можно отдельно видеть:
  - хороший перевод / плохой coverage
  - хороший graph / плохой segment split

## Этап 9. Remove old primary dictionaries

После прохождения regression suite:

- удалить использование:
  - `ANCHOR_TRANSLATIONS`
  - `REPORTING_VERB_TRANSLATIONS`
  - possessive rescue dicts
  - `v2_core` lexical phrase dicts

Если что-то временно остаётся:

- оставить только под feature flag
- не использовать по умолчанию

---

## 12. Риски

Главные риски:

1. Перепутать grammar inventories и запретные словари.
2. Слишком рано удалить legacy rescue path и получить массовую деградацию.
3. Построить только block layer и потерять atomic learning value.
4. Перегрузить pipeline внешним NLP, который нестабилен offline.

Как снижать риски:

- новый контур строить параллельно
- оставлять rebuild path
- держать regression suite по нескольким книгам
- тестировать отдельно:
  - segmentation
  - source graph
  - coverage
  - reader tap

---

## 13. Критерии готовности

Этап считается успешным только если:

1. На новых книгах нет необходимости добавлять ручные lexical translation pairs.
2. Reporting/possessive/time cases не требуют ручных target word rescue lists.
3. `orange juice`, `eggs and toast`, `wake up`, `good morning` разбираются стабильно и объяснимо.
4. Tap payload не зависит от ложного word-level exact mapping.
5. Segment QA и coverage QA можно запускать отдельно.
6. Уже импортированную книгу можно переоценить без полного ручного реимпорта.

---

## 14. Итоговое решение

Новый pipeline должен работать так:

1. typed segmenter режет text на analyzable segments
2. source analyzer строит tokens, units, relations, groups
3. translator переводит segment
4. QA оценивает segment translation
5. coverage resolver ищет target coverage для units/groups
6. coverage QA валидирует coverage
7. reader показывает atomic unit + owner/group + честный coverage status

Это принципиально отличается от текущего legacy пути:

- сейчас: `word mapping -> units`
- нужно: `source units -> coverage`

Главная договорённость MVP21:

- больше не наращивать словари как primary logic
- перевод и coverage должны быть следствием source structure
- target не должен задавать смысл

