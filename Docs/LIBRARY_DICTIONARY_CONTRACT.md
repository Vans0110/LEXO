# LEXO Library Dictionary Contract

## Назначение

Глобальный словарь LEXO накапливается только из реально переведённых книг библиотеки. Он является источником кандидатов для word-to-word alignment и словарных карточек. Модель или внешний словарь не должны добавлять набор «возможных» переводов, которых нет в книгах.

## Источники истины

1. Исходный текст книги.
2. Проверенный перевод сегмента этой книги.
3. Размеченный source span и соответствующий target span.
4. Уже накопленный глобальный словарь как набор кандидатов, но не как доказательство контекстного соответствия.

## Единица слова

Ключ слова: `lemma + POS`.

Словоформы `walk`, `walks`, `walked`, `walking` принадлежат одной лемме, если POS совпадает. Одинаковое написание с разными POS хранится раздельно.

## Анализ новой книги

Для каждого вхождения слова:

1. Найти его source segment и проверенный target segment.
2. Получить кандидатов `translations[]` из глобального словаря по `lemma + POS`.
3. Выбрать кандидат только тогда, когда его точная или контекстная словоформа присутствует в target segment.
4. Сохранить конкретный target span, а не только строку словарного перевода.
5. Разрешить изменение рода, числа, падежа и лица.
6. Разрешить обратный порядок target spans.
7. Если один source token не имеет самостоятельного target span, присоединить его к подтверждённому phrase/grammar block.
8. Если подходящего кандидата нет, извлечь один новый вариант только из target segment.
9. Не добавлять сомнительный вариант автоматически.

## Накопление переводов

Каждая книга может добавить один уникальный подтверждённый вариант для `lemma + POS`. Повтор того же варианта не создаёт новую строку.

Существующие переводы:

- не удаляются;
- не заменяются автоматически;
- сохраняют происхождение по `book_id`;
- используются как кандидаты в следующих книгах.

Пример накопления:

```text
room|NOUN
  translations: [комната, кабинет]
  variants:
    - translation: комната
      book_ids: [book_a]
    - translation: кабинет
      book_ids: [book_b, book_c]
```

## Контекстная форма и словарная форма

Словарная карточка может показывать базовый вариант `английский`. Alignment обязан указывать на реальную форму внутри предложения: `английского`.

Верхняя translation strip всегда показывает полный target segment. Отдельный словарный перевод не может заменять предложение.

## Фразы и grammar blocks

Фразы хранятся отдельно от слов по нормализованному source text. Для них действуют те же правила накопления и provenance.

Служебные слова (`ADP`, `AUX`, `DET`, `PART`, союзы) не получают искусственный standalone-перевод, если в target segment нет самостоятельного соответствия. Они входят в смысловой блок, например:

```text
is a new       → новая
is in          → проходит в
at Hill        → Хилл
Room fourteen  → кабинете №14
```

## Формат книжного слоя

Книжный слой содержит:

- `book_id`, языки и parallel segments;
- слова: `word`, `lemma`, `pos`, `translation`;
- фразы: `source`, `translation`;
- occurrence alignment при его наличии: source span, target span, segment id и alignment kind.

## Формат глобального слова

Обязательные поля:

- `lemma`;
- `pos`;
- `translations[]` — совместимый плоский список кандидатов;
- `variants[]` — варианты с provenance;
- `variants[].translation`;
- `variants[].book_ids[]`;
- `variants[].source_forms[]`.

## Merge

Merge книжного слоя:

1. Нормализует ключ и перевод.
2. Добавляет отсутствующий перевод в `translations[]`.
3. Создаёт или дополняет соответствующий элемент `variants[]`.
4. Добавляет `book_id` и source form без дублей.
5. Никогда не удаляет другие варианты.
6. Повторный merge должен быть идемпотентным.

## Запреты

Запрещено:

- генерировать сразу несколько переводов «на всякий случай»;
- выбирать первый перевод без проверки target segment;
- подменять полный перевод предложения словарной леммой;
- требовать монотонного порядка target spans;
- добавлять перевод, отсутствующий по смыслу в книге;
- автоматически заменять старые значения глобального словаря.

## Проверка качества

После пересборки обязательны:

- пустые переводы: 0;
- дубли в `translations[]`, `book_ids[]`, `source_forms[]`: 0;
- каждый глобальный вариант имеет provenance;
- повторная пересборка не меняет файлы;
- word-to-word выбирает вариант, присутствующий в target segment;
- при отсутствии span UI сохраняет полный target segment без ложной подсветки.
## Phrase components and detail cards

- Phrase record MAY contain `components[]`; every component carries `source`, `lemma`, `pos`, `translation` and global provenance `book_ids[]`.
- Phrase translation owns only the phrase header/tap block. It MUST NOT replace the individual translation of every source word.
- The `Words` section is built only from occurrence-level `word_to_word` entries; function words inside a phrase retain their component translation.
- Dictionary-backed mobile cards MUST ignore legacy `source_first_*` and `unit_translation_*` values from reader payloads.
- Empty diagnostic `Source-first` blocks MUST NOT be shown in the user card.
