class VirgilA1Chapter {
  const VirgilA1Chapter({
    required this.id,
    required this.title,
    this.imageAssetPath,
  });

  final String id;
  final String title;
  final String? imageAssetPath;
}

const virgilA1Chapters = [
  VirgilA1Chapter(
    id: 'chapter_01_introduction',
    title: 'Chapter 1 — Introduction',
    imageAssetPath: 'assets/ui/chapters/a1/chapter_01_introduction.png',
  ),
  VirgilA1Chapter(
    id: 'chapter_02_family',
    title: 'Chapter 2 — Family',
    imageAssetPath: 'assets/ui/chapters/a1/chapter_02_family.png',
  ),
  VirgilA1Chapter(
    id: 'chapter_03_home_furniture',
    title: 'Chapter 3 — Home & Furniture',
    imageAssetPath: 'assets/ui/chapters/a1/chapter_03_home_furniture.png',
  ),
  VirgilA1Chapter(
    id: 'chapter_04_food_drinks',
    title: 'Chapter 4 — Food & Drinks',
    imageAssetPath: 'assets/ui/chapters/a1/chapter_04_food_drinks.png',
  ),
  VirgilA1Chapter(
    id: 'chapter_05_work_study',
    title: 'Chapter 5 — Work & Study',
    imageAssetPath: 'assets/ui/chapters/a1/chapter_05_work_study.png',
  ),
  VirgilA1Chapter(
      id: 'chapter_06_daily_routine_time',
      title: 'Chapter 6 — Daily Routine & Time'),
  VirgilA1Chapter(
      id: 'chapter_07_clothes_shopping',
      title: 'Chapter 7 — Clothes & Shopping'),
  VirgilA1Chapter(
      id: 'chapter_08_city_transport', title: 'Chapter 8 — City & Transport'),
  VirgilA1Chapter(
      id: 'chapter_09_weather_nature', title: 'Chapter 9 — Weather & Nature'),
  VirgilA1Chapter(
      id: 'chapter_10_numbers_money', title: 'Chapter 10 — Numbers & Money'),
  VirgilA1Chapter(
      id: 'chapter_11_health_body', title: 'Chapter 11 — Health & Body'),
  VirgilA1Chapter(
      id: 'chapter_12_travel_plans', title: 'Chapter 12 — Travel & Plans'),
];

const virgilDefaultA1ChapterId = 'chapter_01_introduction';

String virgilA1ChapterTitle(String chapterId) {
  for (final chapter in virgilA1Chapters) {
    if (chapter.id == chapterId) {
      return chapter.title;
    }
  }
  return virgilA1Chapters.first.title;
}
