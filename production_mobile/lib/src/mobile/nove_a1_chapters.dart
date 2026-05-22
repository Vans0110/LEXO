class NoveA1Chapter {
  const NoveA1Chapter({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;
}

const noveA1Chapters = [
  NoveA1Chapter(
      id: 'chapter_01_introduction', title: 'Chapter 1 — Introduction'),
  NoveA1Chapter(id: 'chapter_02_family', title: 'Chapter 2 — Family'),
  NoveA1Chapter(
      id: 'chapter_03_home_furniture', title: 'Chapter 3 — Home & Furniture'),
  NoveA1Chapter(
      id: 'chapter_04_food_drinks', title: 'Chapter 4 — Food & Drinks'),
  NoveA1Chapter(id: 'chapter_05_work_study', title: 'Chapter 5 — Work & Study'),
  NoveA1Chapter(
      id: 'chapter_06_daily_routine_time',
      title: 'Chapter 6 — Daily Routine & Time'),
  NoveA1Chapter(
      id: 'chapter_07_clothes_shopping',
      title: 'Chapter 7 — Clothes & Shopping'),
  NoveA1Chapter(
      id: 'chapter_08_city_transport', title: 'Chapter 8 — City & Transport'),
  NoveA1Chapter(
      id: 'chapter_09_weather_nature', title: 'Chapter 9 — Weather & Nature'),
  NoveA1Chapter(
      id: 'chapter_10_numbers_money', title: 'Chapter 10 — Numbers & Money'),
  NoveA1Chapter(
      id: 'chapter_11_health_body', title: 'Chapter 11 — Health & Body'),
  NoveA1Chapter(
      id: 'chapter_12_travel_plans', title: 'Chapter 12 — Travel & Plans'),
];

const noveDefaultA1ChapterId = 'chapter_01_introduction';

String noveA1ChapterTitle(String chapterId) {
  for (final chapter in noveA1Chapters) {
    if (chapter.id == chapterId) {
      return chapter.title;
    }
  }
  return noveA1Chapters.first.title;
}
