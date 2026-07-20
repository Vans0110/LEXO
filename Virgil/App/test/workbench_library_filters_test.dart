import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/workbench/virgil_workbench_book_status.dart';
import 'package:virgil/src/workbench/virgil_workbench_library_filters.dart';
import 'package:virgil/src/workbench/virgil_workbench_library_models.dart';

void main() {
  testWidgets('apply button commits pending filters and disables while busy',
      (tester) async {
    var applyCount = 0;

    Future<void> pumpFilters({
      required bool busy,
      required bool hasPendingChanges,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VirgilWorkbenchLibraryFilters(
              level: '',
              chapter: '',
              readyFilter: VirgilWorkbenchReadyFilter.all,
              levels: const ['a1'],
              chapters: const ['Chapter 1 \u2014 Introduction'],
              busy: busy,
              hasPendingChanges: hasPendingChanges,
              onLevelChanged: (_) {},
              onChapterChanged: (_) {},
              onReadyFilterChanged: (_) {},
              onApply: () => applyCount++,
            ),
          ),
        ),
      );
    }

    await pumpFilters(busy: false, hasPendingChanges: true);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    expect(applyCount, 1);

    await pumpFilters(busy: true, hasPendingChanges: true);
    final busyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    expect(busyButton.onPressed, isNull);

    await pumpFilters(busy: false, hasPendingChanges: false);
    final unchangedButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    expect(unchangedButton.onPressed, isNull);
  });

  test('chapter folders produce stable ids through chapter 20', () {
    expect(
      virgilWorkbenchChapterId('Chapter 13 - Hobbies & Free Time'),
      'chapter_13_hobbies_free_time',
    );
    expect(
      virgilWorkbenchChapterTitle('Chapter 20 - Review World'),
      'Chapter 20 \u2014 Review World',
    );
    expect(
      virgilWorkbenchChapterNumber('Chapter 20 - Review World'),
      20,
    );
    expect(
      virgilWorkbenchChapterId(
        '\u0413\u043b\u0430\u0432\u0430 13 - Hobbies & Free Time',
      ),
      'chapter_13_hobbies_free_time',
    );
  });

  test('only chapter_images paths are excluded from book sources', () {
    expect(
      virgilWorkbenchIsChapterImagesPath(
          r'D:\Programs\LEXO\Studio\Workbench\Books\A1\chapter_images\Полный план A1.txt'),
      isTrue,
    );
    expect(
      virgilWorkbenchIsChapterImagesPath(
          r'D:\Programs\LEXO\Studio\Workbench\Books\A1\Глава 3 - Home & Furniture\A Plant by the Window.txt'),
      isFalse,
    );
    expect(
      virgilWorkbenchIsChapterImagesPath(
          r'D:\Programs\LEXO\Studio\Workbench\Books\A1\Глава 12 - Travel & Plans\Our Summer Plan.txt'),
      isFalse,
    );
    expect(
      virgilWorkbenchIsChapterImagesPath(
          r'D:\Programs\LEXO\Studio\Workbench\Books\A1\Глава 17 - Animals & Pets\The Dog Walking Plan.txt'),
      isFalse,
    );
  });

  test('filters by level, chapter, and incomplete state', () {
    final items = [
      _item(
        level: 'a1',
        chapter: 'Chapter 1 \u2014 Introduction',
        chapterNumber: 1,
        title: 'First Day',
        status: _status(ready: true),
      ),
      _item(
        level: 'a1',
        chapter: 'Chapter 2 \u2014 Family',
        chapterNumber: 2,
        title: 'Grandma Dinner',
      ),
      _item(
        level: 'a2',
        chapter: 'Chapter 1 \u2014 Memories',
        chapterNumber: 1,
        title: 'Summer',
      ),
    ];

    final visible = virgilWorkbenchVisibleBooks(
      items: items,
      level: 'a1',
      chapter: 'Chapter 2 \u2014 Family',
      readyFilter: VirgilWorkbenchReadyFilter.incomplete,
    );

    expect(visible.map((item) => item.title), ['Grandma Dinner']);
  });

  test('start actions use only selected books visible after filters', () {
    final items = [
      _item(
        level: 'a1',
        chapter: 'Chapter 1 \u2014 Introduction',
        chapterNumber: 1,
        title: 'First Day',
        status: _status(ready: true),
      ),
      _item(
        level: 'a1',
        chapter: 'Chapter 2 \u2014 Family',
        chapterNumber: 2,
        title: 'Grandma Dinner',
      ),
      _item(
        level: 'a2',
        chapter: 'Chapter 1 \u2014 Memories',
        chapterNumber: 1,
        title: 'Summer',
      ),
    ];
    final visible = virgilWorkbenchVisibleBooks(
      items: items,
      level: 'a1',
      chapter: 'Chapter 2 \u2014 Family',
      readyFilter: VirgilWorkbenchReadyFilter.incomplete,
    );
    final selectedVisible = virgilWorkbenchSelectedVisibleBooks(
      visibleItems: visible,
      selectedSourcePaths: {
        'First Day.txt',
        'Grandma Dinner.txt',
      },
    );

    expect(selectedVisible.map((item) => item.title), ['Grandma Dinner']);
  });

  test('select all visible toggles off when every visible book is selected',
      () {
    expect(
      virgilWorkbenchShouldSelectAllVisible(
        visibleCount: 5,
        selectedVisibleCount: 0,
      ),
      isTrue,
    );
    expect(
      virgilWorkbenchShouldSelectAllVisible(
        visibleCount: 5,
        selectedVisibleCount: 3,
      ),
      isTrue,
    );
    expect(
      virgilWorkbenchShouldSelectAllVisible(
        visibleCount: 5,
        selectedVisibleCount: 5,
      ),
      isFalse,
    );
  });

  test(
    'fully built requires a reader dictionary pair, audio, cover, and zip',
    () {
      expect(_status(ready: true).isFullyBuilt, isTrue);
      expect(_status(ready: false).isFullyBuilt, isFalse);
    },
  );

  test('output is fully built with one selected voice', () {
    const status = VirgilWorkbenchBookStatus(
      title: 'Book',
      level: 'a1',
      chapterId: 'chapter_01',
      languages: {'ru', 'uk'},
      dictionaries: {'ru', 'uk'},
      hasAudio: true,
      hasCover: true,
      hasOutput: true,
      hasInstalledZip: false,
      coverPath: 'cover.png',
      audioVoiceIds: {'af_bella'},
      profileVoiceIds: {
        'am_adam',
        'af_bella',
        'af_heart',
        'am_michael',
        'af_sarah',
      },
      playerLevelsByVoice: {
        'af_bella': {'Normal'},
      },
      wordAudioVoiceId: 'af_bella',
      wordAudioCountsByVoice: {'af_bella': 10},
      segmentAudioCount: 10,
      wordAudioCount: 10,
    );

    expect(status.isOutputFullyBuilt, isTrue);
  });

  test('output is fully built with one available reader dictionary language',
      () {
    const status = VirgilWorkbenchBookStatus(
      title: 'RU-only Book',
      level: 'a1',
      chapterId: 'chapter_01',
      languages: {'ru'},
      dictionaries: {'ru'},
      hasAudio: true,
      hasCover: true,
      hasOutput: true,
      hasInstalledZip: false,
      coverPath: 'cover.png',
      audioVoiceIds: {'af_heart'},
      profileVoiceIds: {'af_heart'},
      playerLevelsByVoice: {
        'af_heart': {'Normal'},
      },
      wordAudioVoiceId: 'af_heart',
      wordAudioCountsByVoice: {'af_heart': 10},
      segmentAudioCount: 10,
      wordAudioCount: 10,
    );

    expect(status.isOutputFullyBuilt, isTrue);
  });
}

VirgilWorkbenchBookItem _item({
  required String level,
  required String chapter,
  required int chapterNumber,
  required String title,
  VirgilWorkbenchBookStatus? status,
}) {
  return VirgilWorkbenchBookItem(
    level: level,
    section: 'chapters',
    chapterId: 'chapter_${chapterNumber.toString().padLeft(2, '0')}',
    chapterTitle: chapter,
    chapterNumber: chapterNumber,
    title: title,
    sourcePath: '$title.txt',
    coverPath: '',
    status: status,
  );
}

VirgilWorkbenchBookStatus _status({required bool ready}) {
  return VirgilWorkbenchBookStatus(
    title: 'Book',
    level: 'a1',
    chapterId: 'chapter_01',
    languages: ready ? {'ru', 'uk'} : {'ru'},
    dictionaries: ready ? {'ru', 'uk'} : {'ru'},
    hasAudio: ready,
    hasCover: ready,
    hasOutput: ready,
    hasInstalledZip: ready,
    coverPath: ready ? 'cover.png' : '',
    audioVoiceIds: ready ? {'voice'} : {},
    profileVoiceIds: {'voice'},
    playerLevelsByVoice: ready
        ? {
            'voice': {'normal'},
          }
        : {},
    wordAudioVoiceId: ready ? 'voice' : '',
    wordAudioCountsByVoice: ready ? {'voice': 10} : {},
    segmentAudioCount: ready ? 10 : 0,
    wordAudioCount: ready ? 10 : 0,
  );
}
