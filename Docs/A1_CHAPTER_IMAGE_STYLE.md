# A1 Chapter Image Style

This document is the visual source of truth for A1 chapter images.

## Output contract

- Purpose: mobile chapter cards in Virgil.
- Orientation: landscape.
- Preferred aspect ratio: 5:4.
- Runtime behavior: the image can be cropped with `BoxFit.cover`.
- Keep faces, hands, and story-defining objects in the central safe area.
- Do not bake rounded corners or UI elements into the image.
- Do not include text, letters, numbers, labels, logos, or watermarks.

## Visual direction

Modern YA editorial book illustration with a sophisticated 2D
animated-film look. The images should feel warm, friendly, and accessible,
but not childish.

Use:

- expressive, slightly stylized young adult faces;
- natural adult proportions;
- clean silhouettes and soft rounded forms;
- subtle hand-painted texture;
- restrained background detail;
- warm contemporary European environments;
- one clear story moment and one chapter-specific color accent.

Avoid:

- anime, chibi, or children's-cartoon proportions;
- photorealistic or stock-photo appearance;
- collage layouts;
- excessive props and decorative detail;
- embedded headings, plaques, signs, or readable writing.

## Recurring characters

Use the recurring pair when it fits the scene:

- a dark-curly-haired young adult man;
- a warm brown-haired young adult woman.

Their clothes may change with the setting, but facial design, apparent age,
and overall proportions should remain recognizable across the series.
Supporting characters should add natural diversity without changing the
series style.

## Base prompt

```text
Create a premium landscape 5:4 chapter-card illustration for an
English-learning reading app.

STYLE:
Modern YA editorial book illustration with a sophisticated 2D animated-film
look. Warm, inviting, expressive slightly stylized young adult faces, clean
readable silhouettes, soft rounded forms, subtle hand-painted texture, and
natural adult proportions.

The image must feel friendly and approachable, but not childish. Not chibi,
not anime, not photorealistic, and not a stock-photo collage.

VISUAL SYSTEM:
A cozy contemporary European setting. Use warm cream, ochre, terracotta,
olive, and walnut colors with one distinct chapter-specific accent. Use soft
cinematic light, restrained background detail, and one clear story moment.

COMPOSITION:
Landscape 5:4 format for a small mobile chapter card. Strong visual hierarchy
and generous breathing room. Keep all important faces, hands, and objects
inside the central safe area for BoxFit.cover cropping.

Do not bake rounded corners into the image.

ABSOLUTELY NO:
title, chapter number, words, letters, numbers, readable signs, banners,
logos, typography, UI, frame, watermark, or text-like marks.
```

## Chapter scenarios

### 1. Introduction

Accent: muted navy blue.

The dark-curly-haired student with a navy backpack enters a charming old
university courtyard on an early autumn morning. The brown-haired woman and
two other students greet him with open, friendly gestures. The scene should
immediately communicate a first day, introductions, and a new beginning.

File: `chapter_01_introduction.png`

### 2. Family

Accent: plum purple.

A joyful multigenerational family shares a cozy evening dinner. Grandparents,
parents, a young adult daughter, and a younger child talk naturally around a
wooden table. The emotional center is warmth, belonging, and conversation.

File: `chapter_02_family.png`

### 3. Home & Furniture

Accent: terracotta.

The recurring pair unpack and arrange a new city apartment. He assembles a
simple wooden chair while she carries a houseplant near open moving boxes.
A sofa, lamp, and shelf support the theme without clutter.

File: `chapter_03_home_furniture.png`

### 4. Food & Drinks

Accent: fresh herb green.

The recurring pair cook together in a warm apartment kitchen. He stirs a pot
while she prepares a colorful salad. Bread, vegetables, and a glass pitcher
support the theme.

File: `chapter_04_food_drinks.png`

### 5. Work & Study

Accent: mustard yellow.

The recurring pair study together in a university library room. She explains
an idea while he listens and writes. An open laptop, notebooks, and a few
books create a focused collaborative scene.

File: `chapter_05_work_study.png`

### 6. Daily Routine & Time

Accent: soft sky blue.

The brown-haired woman has a lively morning at home. She puts on a jacket and
reaches for her keys while holding a mug. A plain clock face without numerals,
a packed bag, and breakfast suggest routine and time through action.

File: `chapter_06_daily_routine_time.png`

### 7. Clothes & Shopping

Accent: coral red.

The woman tries on a stylish coral jacket in a small clothing shop. Her male
friend gives an encouraging gesture while a shop assistant holds another
option. Keep racks and folded clothes simple.

File: `chapter_07_clothes_shopping.png`

### 8. City & Transport

Accent: transit blue.

The man checks a simple folded map near a bus stop while the woman points
toward the correct street. A blue city bus approaches in the middle ground.
The action should clearly communicate navigation and public transport.

File: `chapter_08_city_transport.png`

### 9. Weather & Nature

Accent: teal.

The recurring pair walk through an autumn park when sudden rain begins. They
laugh while sharing a teal umbrella. Wind moves amber leaves and a break in
the clouds adds contrast.

File: `chapter_09_weather_nature.png`

### 10. Numbers & Money

Accent: golden yellow.

The woman buys fruit from a friendly older market vendor and counts a few
plain coins in her palm. The man stands beside her with a reusable bag.
Produce and a simple balance scale support quantities and money.

File: `chapter_10_numbers_money.png`

### 11. Health & Body

Accent: muted red.

The man rests on a sofa with a blanket and looks mildly unwell. The woman
kindly brings him a warm mug and a plain medicine box. A thermometer and
tissues support the theme without suggesting an emergency.

File: `chapter_11_health_body.png`

### 12. Travel & Plans

Accent: clear sky blue.

The recurring pair stand with backpacks and a small suitcase at an elegant
railway station, happily checking a simple folded travel map. Friends approach
and a train waits softly in the background. The mood is hopeful anticipation.

File: `chapter_12_travel_plans.png`

## Project paths

Runtime Flutter assets:

`Virgil/App/assets/ui/chapters/a1/`

Studio source mirror:

`Studio/Workbench/Books/A1/chapter_images/`

Chapter declarations:

`Virgil/App/lib/src/mobile/virgil_a1_chapters.dart`
