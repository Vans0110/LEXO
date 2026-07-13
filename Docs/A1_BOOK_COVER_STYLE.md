# A1 Book Cover Style

Этот документ — источник истины для обложек отдельных книг уровня A1.
Стиль рассчитан на текущий каталог и на его дальнейшее расширение.

Сценарии текущих книг находятся в
`Docs/Curriculum/A1_Corpus/A1_COVER_BRIEFS.md`.

## Назначение

- Обложка отдельной graded-reader книги в мобильной библиотеке Virgil.
- Основная аудитория: подростки и взрослые начинающие читатели.
- Обложка должна объяснять завязку истории без знания английского.
- При уменьшении до карточки должны сохраняться заголовок, главный герой,
  ключевое действие и эмоциональный тон.

## Технический контракт

- Формат: PNG.
- Размер: 1024 x 1536.
- Соотношение: 2:3, вертикальное.
- Цвет: RGB.
- Имя файла совпадает с именем TXT: `Book Title.txt` ->
  `Book Title.png`.
- Не добавлять рамку, скругления, тени карточки или элементы интерфейса.
- Важные лица, руки и предметы держать внутри центральных 80% изображения.
- Нижние 8% не должны содержать лицо или главный сюжетный предмет: эта зона
  может частично обрезаться в интерфейсе.

## Визуальное направление

Единый стиль серии:

> Тёплая современная YA-книжная иллюстрация с мягкой гуашевой и цифровой
> фактурой, выразительными естественными лицами, взрослыми пропорциями,
> ясными силуэтами и мягким кинематографическим светом.

Использовать:

- цельную рисованную сцену;
- слегка стилизованных, но естественных людей;
- современные европейские городские и домашние пространства;
- тёплую основу: cream, ochre, terracotta, olive, walnut;
- один цветовой акцент главы;
- один ясно читаемый эмоциональный момент;
- спокойный фон с достаточным свободным пространством.

Не использовать:

- фотореализм и вид стоковой фотографии;
- аниме, chibi и детские мультяшные пропорции;
- коллажи, комиксные панели и рваную бумагу;
- чрезмерное количество предметов и второстепенных сцен;
- драму или опасность сильнее, чем в тексте;
- известных людей, бренды и защищённые персонажи.

## Композиция

1. Верхние 22-28% — спокойная зона заголовка.
2. Заголовок крупный, обычно в одну или две строки.
3. Центральные 50-60% — одна главная сюжетная сцена.
4. На переднем плане — один или два главных героя.
5. Второстепенные персонажи допустимы только когда они нужны сюжету.
6. Фон показывает место действия, но не конкурирует с героями.
7. Обложка не пересказывает всю историю и не показывает развязку.

Для длинного названия:

- сначала уменьшить число строк и плотность букв;
- затем немного уменьшить кегль;
- не уменьшать заголовок до размера обычной подписи;
- не переносить отдельный артикль `A`, `An` или `The` на собственную строку,
  если этого можно избежать.

## Текст

- Единственный обязательный текст — точное название книги.
- Допустим только латинский заголовок из первой строки TXT.
- Запрещены подзаголовки, цитаты, слоганы, списки, номера глав, `A1`,
  диалоги, вывески и декоративные слова.
- Внутри сцены не должно быть читаемых сообщений, писем, цен, адресов,
  билетов, часов с цифрами или экранного текста.
- Если сюжет требует документ или телефон, показать его визуально, но текст
  на нём сделать нечитаемым.
- После генерации заголовок проверяется посимвольно. Обложка с ошибкой в
  заголовке не принимается.

## Персонажи

- Возраст, пол и роль берутся только из текста книги.
- Внешность, этничность и одежда не должны противоречить тексту.
- Если внешность не описана, выбирать естественный современный образ без
  стереотипов.
- Не переносить героя из другой книги только ради повторяемости серии.
- Если персонаж повторяется в нескольких книгах намеренно, сохранять его
  лицо, возраст, волосы и базовую цветовую палитру.
- Эмоция должна соответствовать выбранному моменту, а не финальному итогу
  всей истории.

## Цветовые акценты глав

1. Introduction — muted navy blue.
2. Family — plum purple.
3. Home & Furniture — terracotta.
4. Food & Drinks — fresh herb green.
5. Work & Study — mustard yellow.
6. Daily Routine & Time — soft sky blue.
7. Clothes & Shopping — coral red.
8. City & Transport — transit blue.
9. Weather & Nature — teal.
10. Numbers & Money — golden yellow.
11. Health & Body — muted red.
12. Travel & Plans — clear sky blue.
13. Hobbies & Free Time — violet.
14. Technology & Communication — electric blue.
15. Friends & Emotions — warm rose.
16. Holidays & Special Days — festive burgundy.
17. Animals & Pets — leaf green.
18. Problems & Small Adventures — amber orange.
19. Dreams & Future — deep indigo.
20. Review World — balanced navy and terracotta.

Акцент поддерживает серию, но не обязан занимать большую часть изображения.

## Универсальный промпт

```text
Use case: illustration-story.
Asset type: cover for an A1 English graded-reader book in a mobile reading
library.

Create a polished vertical 2:3 book cover at 1024 x 1536.

BOOK TITLE:
"{EXACT_TITLE}"

STORY MOMENT:
{ONE_SCENE_BRIEF}

CHARACTERS:
{CHARACTER_BRIEF}

SETTING AND MOOD:
{SETTING_AND_MOOD}

CHAPTER ACCENT:
Use {CHAPTER_ACCENT} as a restrained accent within a warm cream, ochre,
terracotta, olive, and walnut base palette.

COMPOSITION:
Use one cohesive main scene, not a collage. Reserve a calm light area in the
upper 22-28 percent for the title. Place the exact title "{EXACT_TITLE}" at
the top in a large, highly legible, friendly hand-painted dark navy type
style. Keep the main faces, hands, and story-defining object inside the
central safe area. The cover must remain readable as a small mobile card.

STYLE:
Warm contemporary YA editorial storybook illustration, soft gouache and
digital-paint texture, expressive but natural faces, natural adult
proportions, clear silhouettes, restrained detail, and soft cinematic light.
Suitable for teens and adults, friendly but not childish.

ABSOLUTELY NO:
Any text except the exact book title; subtitle; slogan; quote; speech bubble;
chapter number; A1 label; readable sign; readable phone, letter, ticket,
price, address, clock, or document; logo; watermark; UI; frame; collage;
torn-paper panel; photorealism; anime; chibi; duplicated person; distorted
hands; invented event; or final plot spoiler.
```

## Как построить бриф по новой книге

Бриф создаётся только после появления финального TXT.

1. Прочитать весь рассказ, а не только название.
2. Выписать главных героев, место, проблему, действие и эмоциональный сдвиг.
3. Выбрать один момент из первой половины истории:
   - момент встречи;
   - начало небольшой проблемы;
   - выбор;
   - совместное действие;
   - обнаружение важного предмета.
4. Не выбирать финальную развязку, мораль или сцену, которой нет в тексте.
5. Оставить максимум двух главных героев и один сюжетный предмет.
6. Сформулировать сцену одним-двумя предложениями.
7. Добавить только внешние признаки, прямо указанные в тексте.
8. Подставить цветовой акцент соответствующей главы.
9. Сгенерировать обложку и провести QA.
10. Только после принятия положить PNG рядом с TXT.

## Шаблон записи для расширения

Новые записи добавляются в `A1_COVER_BRIEFS.md` только для уже существующих
TXT.

```text
### {Book Title}

- File: `{Book Title}.png`
- Moment: {one real scene from the first half of the story}
- Characters: {main characters and only text-supported appearance details}
- Setting/mood: {place, time, emotional tone}
- Key object: {one object or none}
```

## Контроль качества

Обложка принимается, только если:

- размер точно 1024 x 1536;
- имя PNG соответствует имени TXT;
- заголовок написан без ошибок;
- нет другого читаемого текста;
- изображена одна сцена из реального рассказа;
- герои и место не противоречат TXT;
- сцена понятна в маленьком размере;
- стиль совпадает с образцом `First Day`;
- нет коллажа, фотореализма и детской стилизации;
- лица, руки и предметы не имеют заметных дефектов;
- обложка не раскрывает финал.

