# MVP20: Stable Translation QA Architecture

## Цель

Перестроить текущий `translation QA` так, чтобы он:

- работал стабильно на разных книгах без book-specific словарей
- проверял качество перевода по языковым и смысловым инвариантам, а не по ручным спискам слов
- умел переоценивать уже импортированные книги
- не принимал плохой `target_text` молча
- запускал осмысленный `retry`, если ошибка действительно найдена
- давал прозрачный отчёт:
  - что именно не так
  - какой кандидат был отброшен
  - какой кандидат был принят
  - почему

## Главная проблема текущего состояния

Сейчас QA уже встроен в pipeline, но он всё ещё опирается на хрупкие эвристики.

Это приводит к трём системным проблемам:

1. `QA` нестабилен между книгами.
2. `QA` лучше ловит отдельные заранее известные классы ошибок, чем универсальные ошибки языка и смысла.
3. `Retry` пока недостаточно осмысленный:
   - часто есть fallback по provider
   - но нет достаточного “reason-aware correction loop”

## Что считается недопустимым в финальной версии

В production QA нельзя опираться на:

- списки конкретных “правильных” переводов
- book-specific паттерны под одну книгу
- ручные словари персонажей, написанные человеком под конкретную книгу
- узкие списки ошибок уровня:
  - `KNOWN_RU_TYPO_WORDS = {"едит"}`
  - списки женских имён
  - списки “опасных слов” как основной механизм

Допустимы только:

- общие языковые правила
- общие грамматические признаки
- общие relation/frame invariants
- автоматически собранная память книги

## Что должно получиться в итоге

После MVP20 система должна работать так:

1. Сегмент переводится.
2. QA проверяет его несколькими независимыми слоями.
3. Если найден критичный дефект:
   - сегмент не принимается
   - запускается retry по причине ошибки
4. Если есть несколько кандидатов:
   - выбирается лучший не по “похожести строк”, а по устойчивым языковым сигналам
5. Для уже импортированной книги можно заново запустить оценку текущим QA.
6. Отчёт показывает:
   - какой был дефект
   - какой кандидат победил
   - был ли retry
   - почему финальный сегмент принят

---

## Блок A. Обязательные архитектурные принципы

### A1. Direct target check важнее back-translation

Главный сигнал:

- `source EN -> target RU`

Вторичный сигнал:

- `source EN -> back EN`

`back_translation` нельзя использовать как главный источник истины.

Он нужен только как:

- дополнительный semantic check
- detector галлюцинаций
- арбитр спорных случаев

### A2. QA должен проверять инварианты, а не слова

Нужно проверять:

- сущность осталась сущностью
- субъект остался субъектом
- владелец не исчез
- направление не пропало
- тип действия не сменился
- русская грамматика не развалилась
- новая информация не появилась из воздуха

### A3. Книга должна иметь автоматически построенную память

Нужна `book entity memory`, которую система строит сама:

- recurring entities
- aliases
- role hints
- animate/inanimate hints
- likely gender
- observed translations

Это не ручной словарь.  
Это автоматически собранный локальный контекст книги.

### A4. QA должен быть переиспользуемым

Нужен отдельный rebuild/re-evaluate path:

- для уже импортированных книг
- без ручного повторного импорта
- с тем же `book_id`

---

## Блок B. Что нужно убрать или переписать

### B1. Убрать хрупкие словарные эвристики как primary logic

В первую очередь убрать из роли “главного механизма”:

- `KNOWN_RU_TYPO_WORDS`
- маленькие списки женских имён
- маленькие списки мужских предикатов
- короткие списки motion/title слов как единственный detector

Они могут временно остаться как fallback-эвристики, но не как основа verdict.

### B2. Убрать поверхностную проверку possessive по токенам

Проверка вида:

- “в source есть `his/her`, а в target нет `его/её/свой`”

недостаточна.

Нужно перейти к relation-aware проверке:

- owner
- possessed noun
- сохранность отношения владения

### B3. Убрать зависимость verdict от back-only шума

Сегмент нельзя валить только потому, что:

- back-translation перефразировал
- back-translation сменил время
- back-translation додумал лишнее

если `target RU` сам по себе хороший.

---

## Блок C. Целевая архитектура QA

Новый QA должен состоять из 6 слоёв.

### C1. Technical Layer

Назначение:

- отсеивать явный мусор

Что проверяет:

- пустой перевод
- копирование source
- повтор токенов
- мусорные символы
- очевидный length mismatch
- английский хвост в русском

Этот слой остаётся, но не должен решать смысловые задачи.

### C2. RU Grammar Layer

Назначение:

- проверять русский текст как русский

Что должен ловить:

- орфографию
- морфологические ошибки
- ошибки согласования
- ошибки рода
- грамматически сломанные предикативные конструкции
- неестественные literal-кальки, если они ломают русскую грамматику

Технология:

- морфологический анализатор RU
- spell-check layer
- признаки рода/числа/падежа/части речи

Это должен быть главный direct-target слой.

### C3. Identity Layer

Назначение:

- следить за сущностями

Что должен ловить:

- proper name исчез
- proper name превратился в common noun
- actor/speaker/pet name потерялся
- entity count/type drift на коротких сегментах

Технология:

- NER
- proper-name detector
- recurring entity memory

### C4. Relation / Frame Layer

Назначение:

- проверять сохранность отношений и типа события

Что должен ловить:

- потеря possessive relation
- потеря subject/object relation
- direction/location loss
- speech attribution drift
- habitual vs event drift
- motion transport drift
- predicate class drift

Технология:

- dependency parsing
- compact semantic frame

### C5. Back Support Layer

Назначение:

- не быть главным, а усиливать сигнал

Что делает:

- обнаруживает semantic drift
- обнаруживает hallucinated extra information
- обнаруживает contradiction / underspecification

### C6. NLI Layer

Назначение:

- финальный semantic arbiter

Что проверяет:

- `source EN` entails `back EN`
- `back EN` entails `source EN`

Что должен ловить:

- логическое противоречие
- добавленные детали, которых не было
- сильное смысловое расхождение

Этот слой вводится после стабилизации grammar/relation/entity.

---

## Блок D. Целевая модель решений

Текущих `pass/warn/fail` недостаточно.

Нужна внутренняя decision-model:

- `accept`
- `accept_low_confidence`
- `retry_required`
- `reject`

### D1. `accept`

Условия:

- нет критичных ошибок
- score высокий
- retry-флагов нет

### D2. `accept_low_confidence`

Условия:

- явного брака нет
- есть вторичные риски
- можно строить alignment с пониженной уверенностью

### D3. `retry_required`

Условия:

- найден дефект, который может быть исправлен альтернативным переводом

Примеры:

- spelling error
- possessive lost
- directional title
- gender mismatch
- motion drift

### D4. `reject`

Условия:

- все кандидаты плохие
- alignment строить нельзя
- сегмент сохраняется только как проблемный

---

## Блок E. Retry policy

### E1. Текущий retry недостаточен

Сейчас retry в основном означает:

- попробовать другого provider
- выбрать лучший candidate

Этого недостаточно.

### E2. Нужен reason-aware retry

Для каждой группы ошибок нужен собственный retry-mode.

#### Title mode

Если найдено:

- `target_directional_title`
- title explosion

то retry должен жёстко требовать:

- title-like output
- noun phrase / short heading
- без narrative expansion

#### Possessive mode

Если найдено:

- `target_possessive_relation_lost`

то retry должен требовать:

- сохранить owner relation
- не терять референцию владельца

#### Grammar mode

Если найдено:

- spelling
- agreement
- gender mismatch

то retry должен пытаться получить более грамматически правильный RU target.

#### Motion / event mode

Если найдено:

- habitual/event drift
- transport drift

то retry должен удерживать event semantics.

### E3. Acceptance policy

Сегмент нельзя принимать, если есть hard retry reason:

- `ru_spelling_error`
- `ru_agreement_error`
- `ru_gender_mismatch`
- `target_possessive_relation_lost`
- `target_directional_title`
- `target_motion_transport_drift`

---

## Блок F. Book memory

### F1. Нужен автоматический memory-store книги

Новый модуль должен собирать и хранить:

- canonical entity mentions
- aliases
- likely gender
- animate/inanimate hints
- role hints:
  - speaker
  - actor
  - pet
  - location
- observed RU renderings

### F2. Память строится автоматически

Источник:

- первые появления сущности
- повторяющиеся сущности
- relation/frame context
- target-side agreement signals

### F3. Что это даст

Например, если `Luna`:

- уже встречалась как animate recurring entity
- уже имела согласование как женская/одушевлённая кличка

то потом:

- перевод в common noun
- смена роли
- смена типа сущности

должны штрафоваться сильнее.

---

## Блок G. Переоценка книги

### G1. Build/rebuild path обязателен

Система должна уметь:

- брать уже импортированную книгу
- заново прогонять её текущим QA
- обновлять `segments`, отчёт и логи

### G2. Rebuild должен использовать тот же pipeline

Это не просто `UPDATE quality_score`.

Это:

- повторное построение segment payload
- повторный candidate selection
- повторный retry
- повторная запись alignment decision

### G3. Reader/TTS данные должны корректно обновляться

При rebuild должны:

- очищаться старые runtime-артефакты книги
- сохраняться метаданные книги
- не ломаться reader position

---

## Блок H. Файлы и модули

### H1. `engine/segment_quality.py`

Оставить orchestration-слоем.

Там должно быть:

1. technical
2. ru grammar
3. identity
4. relation/frame
5. back support
6. nli
7. decision

### H2. `engine/qa_ru_quality.py`

Перестроить в основной RU grammar layer.

Нужно:

- убрать роль словарных заглушек как primary logic
- интегрировать морфологический анализ
- добавить spelling/grammar detectors

### H3. Новый `engine/qa_relations.py`

Вынести сюда:

- possessive preservation
- subject/object preservation
- speaker attribution preservation
- owner/body-part relation

### H4. `engine/qa_entities.py`

Оставить за:

- entity extraction
- identity preservation
- entity-memory hooks

### H5. `engine/qa_frames.py`

Оставить за:

- compact semantic frame extraction
- frame comparison

### H6. Новый `engine/qa_memory.py`

Нужен для:

- entity memory книги
- speaker memory
- observed translation memory

### H7. Новый `engine/qa_retry.py`

Вынести сюда:

- retry classification
- candidate acceptance
- rank key
- hard/soft retry policy

### H8. `engine/storage.py`

Оставить orchestration storage-слоем.

Он должен:

- вызывать pipeline
- сохранять candidates / winner
- запускать rebuild
- писать отчёты

### H9. `engine/api.py`

Нужно:

- оставить report API
- добавить API для rebuild и debug QA

### H10. `scripts/check_pipeline_regressions.py`

Оставить как synthetic regression.

Нужно добавить отдельный файл:

- `scripts/check_book_quality_regressions.py`

для regression по реальным книгам.

---

## Блок I. Данные в БД

В `segments` должны остаться или быть добавлены:

- `quality_score`
- `quality_status`
- `decision_status`
- `semantic_score`
- `ru_quality_score`
- `quality_flags`
- `ru_quality_flags`
- `retry_reason_flags`
- `back_translation`
- `translation_attempt_count`
- `provider_used`
- `alignment_confidence`
- `winner_reason`
- `candidate_count`

Для структурных слоёв:

- `source_entities_json`
- `target_entities_json`
- `back_entities_json`
- `entity_preservation_score`
- `entity_flags`
- `source_frame_json`
- `target_frame_json`
- `back_frame_json`
- `frame_preservation_score`
- `frame_flags`

Для memory/debug:

- optional `qa_trace_json`

Если хранение trace в `segments` слишком раздувает таблицу, его можно писать в лог.

---

## Блок J. Debug/report contract

Для каждого сегмента отчёт должен показывать:

- `source_text`
- `target_text`
- `back_translation`
- `segment_type`
- `translation_kind`
- `provider_used`
- `translation_attempt_count`
- `decision_status`
- `quality_status`
- `quality_score`
- `ru_quality_score`
- `quality_flags`
- `ru_quality_flags`
- `retry_reason_flags`
- `winner_reason`
- `alignment_confidence`

Если было несколько кандидатов, для debug режима нужно уметь показать:

- список кандидатов
- почему каждый проиграл
- почему победитель принят

---

## Блок K. Regression strategy

### K1. Synthetic regression

Сохраняется текущий `check_pipeline_regressions.py`.

Он должен покрывать:

- technical defects
- ru grammar defects
- possessive loss
- title drift
- motion drift
- entity degradation
- retry triggering
- rebuild path

### K2. Golden-book regression

Нужен новый regression по реальным книгам.

Минимум:

- `The Sunny Morning`
- ещё 2 книги другого типа

Для каждой книги фиксировать:

- список проблемных сегментов
- expected verdict
- expected retry
- expected final winner

### K3. Regression должен проверять не только flags

Нужно проверять:

- был ли retry
- сменился ли winner
- изменился ли `target_text`
- строится ли alignment

---

## Блок L. Этапы внедрения

### Этап 1. Инфраструктура

Сделать:

- rebuild/re-evaluate path
- decision statuses
- нормальный debug-report
- сохранение candidate winner reason

Готовность:

- уже импортированная книга может быть честно пересчитана новым QA

### Этап 2. RU grammar layer

Сделать:

- spell/morph integration
- agreement detection
- gender mismatch detection без списков имён как primary logic

Готовность:

- `едит`
- ошибки согласования
- простые gender mismatches

ловятся без ручного словаря конкретных ошибок.

### Этап 3. Relation layer

Сделать:

- relation-aware possessive preservation
- owner/body-part relation
- speaker attribution relation

Готовность:

- `his friend -> свою подругу` не штрафуется
- `his legs -> на ногах` штрафуется

### Этап 4. Identity memory

Сделать:

- entity memory per book
- recurring entity tracking
- stronger entity consistency

Готовность:

- recurring entities стабильно проверяются между главами

### Этап 5. Frame stabilization

Сделать:

- stronger motion/speech/state comparison
- better event vs habitual detection
- better direction preservation

### Этап 6. NLI layer

Сделать:

- entailment / contradiction check
- hallucination detection

### Этап 7. Golden-book QA

Сделать:

- regression на нескольких реальных книгах
- стабильные критерии качества

---

## Блок M. Критерий готовности MVP20

MVP20 считается завершённым, когда выполнены все условия:

1. QA больше не зависит от book-specific словарей.
2. RU grammar defects ловятся не через ручные списки, а через языковой анализ.
3. Possessive relation проверяется не по токенам, а по связи.
4. Entity consistency поддерживается автоматически через память книги.
5. Back-translation не является главным источником verdict.
6. Плохой сегмент не принимается без retry.
7. Уже импортированную книгу можно честно пересчитать текущим QA.
8. Regression проходит не только на synthetic cases, но и на нескольких реальных книгах.

---

## Блок N. Что не входит в MVP20

Чтобы не расползтись, в этот MVP не входят:

- полный переход на LLM-based редактор перевода
- сложная stylistic ranking модель
- UI-редактор переводов руками
- сегментация как отдельный большой рефактор

Сегментация важна, но это следующий крупный блок после стабилизации translation QA.

---

## Итог

MVP20 — это не “ещё чуть-чуть подкрутить эвристики”.

Это переход:

- от строковых и словарных правил
- к устойчивой языковой архитектуре

Ключевой результат:

QA должен стать переносимым между книгами и устойчивым к новым текстам без ручной подгонки.
