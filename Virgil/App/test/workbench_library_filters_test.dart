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

  test(
    'fully built requires every reader, dictionary, audio, cover, and zip',
    () {
      expect(_status(ready: true).isFullyBuilt, isTrue);
      expect(_status(ready: false).isFullyBuilt, isFalse);
    },
  );
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
