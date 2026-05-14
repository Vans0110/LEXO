# MVP23.10 — Word Tap / Owner Semantics Fix Plan

## 1. Цель

Вернуть reader/tap-контур к простому и проверяемому правилу:

- обычный tap по слову показывает перевод этого слова;
- phrase / compound owner не заменяет word-level результат, если word-level результат можно получить честно;
- phrase / compound сохраняется как дополнительный explanation layer для detail sheet, debug и обучения;
- слова без честного target span не получают выдуманный перевод.

Главный инвариант:

```text
word tap semantics != owner phrase semantics
```

## 2. Что сейчас сломано по факту

### 2.1. Phrase owner перебивает word tap

Пример:

```text
EN: "Good morning, Luna!"
RU: "Доброе утро, Луна!"
```

SimAlign даёт нормальные raw links:

```text
Good    -> Доброе
morning -> утро
Luna    -> Луна
```

Resolved layer выбирает:

```text
Good morning -> Доброе утро
type=phrase
status=aligned
```

Runtime adapter сейчас применяет phrase unit к каждому слову внутри range:

```text
Good    -> Доброе утро
morning -> Доброе утро
tap_unit_id = phrase id
```

Это ломает словарный / word-first tap UX: слово перестаёт быть самостоятельной tap-единицей, хотя clean word links были доступны.

### 2.2. Phrase owner используется как UI-склейка

В MVP23 было зафиксировано:

```text
owner не равен UI-склейке
compound не обязан становиться единым tap-unit
phrase/compound semantics задаёт backend
adapter только отображает backend truth
```

Фактически runtime сейчас делает:

```text
resolved phrase/compound unit -> один tap_unit_id для всех внутренних слов
```

Это допустимо только для phrase-only fallback, но не как общее правило.

### 2.3. Внутренние word units теряются из final payload

Для phrase winner resolver сейчас добавляет winner и считает source indexes covered.
После этого canonical внутренние words не попадают в final result как отдельные `aligned / absorbed / rejected` entries.

Итог:

```text
final JSON хранит owner,
но не хранит нормальный результат для word tap внутри owner.
```

Adapter вынужден раздавать owner span внутренним словам, потому что другой правды нет.

### 2.4. Source-first coverage конкурирует с resolved alignment

В payload одновременно есть:

- `segment_resolved_alignments.alignment_json`
- `segments.source_coverage_json`
- локальный UI helper `buildPreferredSourceFirstFocus(...)`

По MVP23.7 runtime/tap должен читать resolved layer как source of truth.
Source-first coverage может оставаться debug/detail layer, но не должен переигрывать resolved tap-result.

### 2.5. SimAlign raw signal шумит, но это ожидаемо

Пример:

```text
EN: He is a little tired but very happy.
RU: Он немного устал, но очень счастлив.
```

Raw links:

```text
He    -> Он
is    -> немного
a     -> устал
tired -> устал
but   -> но
very  -> очень
happy -> счастлив
```

`little` не получил raw link.

Это не делает SimAlign бесполезным. Это значит, что resolver должен уметь:

- не доверять raw links слепо;
- использовать dictionary / phrase patterns / local target context;
- распознавать `a little + adjective` как phrase/modifier pattern.

## 3. Где смотреть код

### Source unit / phrase builder

- `engine/alignment_units.py`

Риски:

- phrase становится canonical unit;
- internal word units могут подавляться owner-ом;
- `GRAMMAR_WORDS` содержит часть слов, которые для tap могут быть смысловыми modifiers (`very`, `up`, `but`), поэтому classification надо проверять по use case.

### Resolver

- `engine/alignment_resolver.py`

Риски:

- `_select_winners(...)` использует `used_source_indexes`, поэтому phrase winner suppresses internal words;
- final payload не сохраняет internal canonical word results после owner win;
- отсутствует явная owner relation в internal word entries.

### Feature scoring

- `engine/alignment_features.py`

Риски:

- phrase bonus может перебивать word-level clean links;
- grammar classifier слишком грубый для RU;
- dictionary score сейчас не защищает word-level result от phrase owner.

### Runtime adapter

- `engine/runtime_simalign_clean.py`

Риски:

- `_apply_resolved_alignments(...)` применяет любой aligned unit ко всем source indexes внутри range;
- phrase/compound span копируется в каждое внутреннее слово;
- `tap_unit_id` становится owner id;
- нет различия между `word_tap_unit_id` и `owner_unit_id`.

### Legacy/storage adapter paths

- `engine/storage.py`
- `engine/word_alignment.py`

Риски:

- часть mobile/export/detail payload может идти через storage path;
- там тоже есть `tap_unit_id`, `unit_translation_*`, `source_first_*`;
- правки runtime надо синхронизировать с mobile package/export.

### Flutter UI

- `app/lib/src/widgets/interactive_paragraph_text.dart`
- `app/lib/src/widgets/continuous_translation_strip.dart`
- `app/lib/src/screens/reader_screen.dart`
- `app/lib/src/ui/mobile/screens/mobile_reader_screen.dart`
- `app/lib/src/detail_sheet_models.dart`

Риски:

- UI сейчас знает только один `selectedTapUnitId`;
- detail fallback группирует words по `tapUnitId`;
- если backend отдаёт owner id как tap id, UI неизбежно склеивает words.

## 4. Целевой контракт после fix

### 4.1. Word-level fields

Каждое source word в reader payload должно иметь собственный tap result:

```json
{
  "id": "word_id",
  "text": "morning",
  "tap_unit_id": "<segment_id>::word::<word_id-or-unit-id>",
  "translation_focus_text": "утро",
  "target_start_index": 1,
  "target_end_index": 1,
  "alignment_status": "resolved_exact"
}
```

Если честного word span нет:

```json
{
  "text": "a",
  "translation_focus_text": "",
  "target_start_index": -1,
  "target_end_index": -1,
  "alignment_status": "absorbed"
}
```

### 4.2. Owner fields

Phrase / compound owner должен быть отдельным metadata layer:

```json
{
  "owner_unit_id": "<segment_id>::phrase::u_0_1_phrase_fixed_expression",
  "owner_source_text": "Good morning",
  "owner_target_text": "Доброе утро",
  "owner_type": "phrase",
  "owner_status": "aligned",
  "owner_target_start": 0,
  "owner_target_end": 1
}
```

Owner может использоваться:

- в detail sheet;
- в debug report;
- для optional "show phrase" UI;
- как fallback, если word-level result невозможен.

Owner не должен автоматически становиться `tap_unit_id` для обычного word tap.

### 4.3. Phrase-only fallback

Если phrase реально неделимая и internal word spans невозможны, допустимо:

```text
tap по любому internal word показывает phrase owner
```

Но это должно быть явное решение:

```json
"tap_mode": "owner_fallback"
```

А не побочный эффект отсутствия internal word entries.

## 5. План правок

## Шаг 1. Добавить diagnostic / regression script

Создать или расширить существующую диагностику, которая печатает для выбранной книги:

- word text;
- segment;
- tap id;
- word target span;
- word focus;
- owner id;
- owner target span;
- owner focus;
- status;
- reason.

Обязательные кейсы:

```text
Good morning -> Good/Доброе, morning/утро, owner/Доброе утро
wakes up -> проверить expected mode: phrase-only или split/fallback
a little tired -> little/немного, tired/устал, owner/little tired/немного устал
T-shirt -> футболку
Goodnight -> Спокойной ночи
thank you -> спасибо
In the afternoon -> Днем
Tom whispers -> whispers/шепчет, Tom/Том
```

Критерии:

```text
cross_segment_duplicate_tap_ids = 0
word tap не выбирает чужое слово
phrase owner не уничтожает clean word links
```

## Шаг 2. Изменить resolver final payload semantics

Файл:

- `engine/alignment_resolver.py`

Правка:

- winner selection может выбрать phrase/compound owner;
- final payload всё равно должен включать canonical internal word units;
- internal word units получают:
  - `aligned`, если есть clean independent word candidate;
  - `absorbed`, если они реально explained by owner and have no independent target;
  - `rejected`, если нет уверенного explanation.

Добавить meta для internal words:

```json
{
  "owner_unit_id": "u_0_1_phrase_fixed_expression",
  "owner_mode": "always_phrase",
  "owner_status": "aligned"
}
```

Не делать:

- не размазывать owner target span на все internal words;
- не удалять internal words из final payload только потому, что phrase won.

## Шаг 3. Добавить independent-word candidate preservation

Файл:

- `engine/alignment_resolver.py`

Правка:

- перед owner suppression сохранить best word-level candidate per `(source_start, source_end)`;
- если word candidate имеет clean raw/dictionary signal и не конфликтует по target с более сильным word, добавить его в final payload;
- phrase owner остаётся как owner unit.

Для `Good morning` expected final JSON:

```text
phrase Good morning -> Доброе утро aligned
word Good -> Доброе aligned owner_unit_id=phrase
word morning -> утро aligned owner_unit_id=phrase
```

## Шаг 4. Развести tap id и owner id в runtime adapter

Файл:

- `engine/runtime_simalign_clean.py`

Правка:

- `_apply_resolved_alignments(...)` не должен присваивать phrase/compound unit id как `tap_unit_id` internal words по умолчанию;
- word tap id строить из word unit / word id;
- owner fields переносить отдельно.

Expected:

```text
Good.tap_unit_id != morning.tap_unit_id
Good.owner_unit_id == morning.owner_unit_id
```

Исключение:

- если unit explicitly `tap_mode=owner_fallback`, тогда можно общий tap id.

## Шаг 5. Синхронизировать storage/mobile adapter path

Файлы:

- `engine/storage.py`
- `engine/word_alignment.py`
- `app/lib/src/mobile/mobile_package_repository.dart`

Проверить:

- mobile package получает такие же word/owner fields;
- offline detail sheet не группирует unrelated words только по owner id;
- `tap_unit_id` остаётся segment-scoped.

## Шаг 6. Убрать source-first override из ordinary tap

Файлы:

- `app/lib/src/screens/reader_screen.dart`
- `app/lib/src/ui/mobile/screens/mobile_reader_screen.dart`
- `app/lib/src/detail_sheet_models.dart`

Проверить:

- `buildPreferredSourceFirstFocus(...)` не должен перебивать resolved word tap;
- source-first можно показывать как debug/detail info;
- обычный tap берёт `effective_*` из backend word payload.

Возможный переходный вариант:

```text
if word.effectiveMatchedBy is non-empty -> use backend effective
else fallback to source_first
```

Но целевой вариант:

```text
backend effective is final truth
```

## Шаг 7. Добавить минимальные phrase rules

Файлы:

- `engine/alignment_units.py`
- `engine/alignment_resolver.py`
- возможно отдельный `engine/alignment_phrase_rules.py`

Минимальный набор:

```text
a little + ADJ/VERB-state -> little/modifier + head
thank you -> спасибо
goodnight -> спокойной ночи
in the afternoon -> днем
hyphen lexical token T-shirt -> футболку
```

Важно:

- эти rules не должны насильно склеивать UI tap;
- они должны дать candidate / owner / fallback, а не уничтожить word-level result.

## Шаг 8. Rebuild and compare

После правок:

```text
rebuild simalign
rebuild resolved alignment
reload reader payload
```

Сравнить:

- `segment_resolved_alignments.alignment_json`;
- reader words;
- UI tap simulation;
- missing content words list.

## 6. Что считать успехом

### Must pass

```text
Good -> Доброе
morning -> утро
Good morning owner -> Доброе утро
```

```text
little -> немного
tired -> устал
```

```text
tap Good highlights только Good, не весь phrase
detail sheet может показать phrase Good morning
```

```text
cross_segment_duplicate_tap_ids = 0
```

```text
content rejected list уменьшается
```

### Must not regress

```text
articles remain absorbed
segment translation remains unchanged
mobile package still opens
detail sheet still opens
compound bus driver still has owner explanation
```

## 7. Рискованные места

### Риск 1. Потерять phrase UX

Если полностью убрать owner tap, можно потерять полезные phrase explanations.

Митигировать:

- owner fields оставить;
- detail sheet показывает owner phrase;
- phrase можно показывать как дополнительную секцию, но не как замену word tap.

### Риск 2. Раздвоить truth ещё сильнее

Если оставить source-first override, можно получить:

```text
resolved говорит одно,
source_first показывает другое.
```

Митигировать:

- ordinary tap использует backend effective from resolved;
- source_first только debug / secondary.

### Риск 3. Слишком рано лечить все phrase cases

Не надо сразу писать большой phrase engine.

Митигировать:

- сначала исправить semantics owner vs word;
- потом добавить 5-6 curated patterns.

## 8. Recommended implementation order

1. Diagnostic script / report.
2. Resolver final payload: keep internal canonical word units.
3. Runtime adapter: word tap id separate from owner id.
4. UI: stop source-first override for ordinary tap if backend effective exists.
5. Curated phrase rules.
6. Rebuild active book.
7. Compare report before/after.
8. Update history.

## 9. Ключевой вывод

MVP23 direction remains correct.

Ошибка не в том, что появился resolver или SimAlign.
Ошибка в реализации границы:

```text
owner alignment был ошибочно превращён в основной word tap alignment
```

Исправление должно восстановить разделение:

```text
word alignment для tap
owner alignment для explanation
dictionary для lexical meaning
```
