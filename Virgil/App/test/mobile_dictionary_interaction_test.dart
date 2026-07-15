import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/detail_sheet_models.dart';
import 'package:virgil/src/mobile/mobile_package_models.dart';
import 'package:virgil/src/mobile/mobile_package_repository.dart';
import 'package:virgil/src/widgets/continuous_translation_strip.dart';

Map<String, dynamic> _word(String id, String text, String pos, int index) => {
      'id': id,
      'text': text,
      'lemma': text,
      'pos': pos,
      'segment_id': 'segment_1',
      'order_index': index,
      'order_index_in_segment': index,
      'tap_unit_id': id,
      'source_unit_text': text,
      'target_start_index': -1,
      'target_end_index': -1,
    };

Map<String, dynamic> _package() {
  final words = [
    _word('word_rest', 'rest', 'NOUN', 0),
    _word('word_of', 'of', 'ADP', 1),
    _word('word_the', 'the', 'DET', 2),
    _word('word_day', 'day', 'NOUN', 3),
  ];
  return {
    'meta': {
      'local_book_id': 'book_1',
      'desktop_book_id': 'book_1',
      'title': 'Book',
    },
    'reader_payload': {
      'book_id': 'book_1',
      'title': 'Book',
      'status': 'ready',
      'paragraphs': [
        {
          'index': 0,
          'source_text': 'rest of the day',
          'target_text': 'Она работает до конца дня',
          'segments_v2': [
            {
              'id': 'segment_1',
              'source_text': 'rest of the day',
              'target_text': 'Она работает до конца дня',
              'segment_alignment': {
                'target_tokens': ['Она', 'работает', 'до', 'конца', 'дня'],
              },
            },
          ],
          'tokens': [
            for (final word in words)
              {
                'id': 'token_${word['id']}',
                'text': word['text'],
                'kind': 'word',
                'order_index': word['order_index'],
                'word_id': word['id'],
                'tap_unit_id': word['id'],
              },
          ],
          'words': words,
        },
      ],
    },
    'word_to_word': {
      'entries': [
        {
          'word_id': 'word_rest',
          'segment_id': 'segment_1',
          'translation': 'отдых',
        },
        {
          'word_id': 'word_of',
          'segment_id': 'segment_1',
          'translation': 'из',
        },
        {
          'word_id': 'word_the',
          'segment_id': 'segment_1',
          'translation': 'этот',
        },
        {
          'word_id': 'word_day',
          'segment_id': 'segment_1',
          'translation': 'день',
        },
      ],
      'phrases': [
        {
          'segment_id': 'segment_1',
          'source': 'rest of the day',
          'translation': 'до конца дня',
        },
      ],
    },
    'dictionary_manifest': {
      'entries': {
        'rest|NOUN': {
          'translations': ['отдых']
        },
        'of|ADP': {
          'translations': ['из']
        },
        'the|DET': {
          'translations': ['этот']
        },
        'day|NOUN': {
          'translations': ['день']
        },
      },
    },
  };
}

Map<String, dynamic> _grammarPackage(
  List<(String, String, String)> items,
  List<String> targetTokens,
) {
  final package = _package();
  final words = <Map<String, dynamic>>[];
  final entries = <Map<String, dynamic>>[];
  final dictionaryEntries = <String, dynamic>{};
  for (var index = 0; index < items.length; index++) {
    final (text, pos, translation) = items[index];
    final id = 'grammar_word_$index';
    words.add(_word(id, text, pos, index));
    entries.add({
      'word_id': id,
      'segment_id': 'segment_1',
      'translation': translation,
    });
    dictionaryEntries['${text.toLowerCase()}|$pos'] = {
      'translations': [translation],
    };
  }
  final paragraph =
      ((package['reader_payload'] as Map)['paragraphs'] as List).first as Map;
  paragraph['source_text'] = items.map((item) => item.$1).join(' ');
  paragraph['target_text'] = targetTokens.join(' ');
  paragraph['words'] = words;
  paragraph['tokens'] = [
    for (final word in words)
      {
        'id': 'token_${word['id']}',
        'text': word['text'],
        'kind': 'word',
        'order_index': word['order_index'],
        'word_id': word['id'],
        'tap_unit_id': word['id'],
      },
  ];
  paragraph['segments_v2'] = [
    {
      'id': 'segment_1',
      'source_text': paragraph['source_text'],
      'target_text': paragraph['target_text'],
      'segment_alignment': {'target_tokens': targetTokens},
    },
  ];
  package['word_to_word'] = {
    'entries': entries,
    'phrases': <Map<String, dynamic>>[],
  };
  package['dictionary_manifest'] = {'entries': dictionaryEntries};
  return package;
}

void main() {
  test('phrase alignment owns one source block and builds a multi-word card',
      () {
    final normalized = normalizeMobilePackageJsonForTest(
      normalizeMobilePackageJsonForTest(_package()),
    );
    final paragraphJson = (normalized['reader_payload']['paragraphs'] as List)
        .first as Map<String, dynamic>;
    final wordsJson =
        (paragraphJson['words'] as List).cast<Map<String, dynamic>>();
    final phraseId = wordsJson.first['tap_unit_id'];

    expect(phraseId, startsWith('phrase_segment_1_'));
    expect(wordsJson.every((word) => word['tap_unit_id'] == phraseId), isTrue);
    expect(
        wordsJson
            .every((word) => word['source_unit_text'] == 'rest of the day'),
        isTrue);
    expect(
        wordsJson
            .every((word) => (word['phrase_alignments'] as List).length == 1),
        isTrue);
    expect(wordsJson.map((word) => word['target_start_index']).toSet(), {2});
    expect(wordsJson.map((word) => word['target_end_index']).toSet(), {4});

    final package = MobileBookPackage(normalized);
    final paragraph = package.readerPayload.paragraphs.single;
    final phraseCard = DetailSheetPayload.fromSelection(
      item: paragraph,
      word: paragraph.words.first,
    );
    expect(phraseCard.sheetSourceText, 'rest of the day');
    expect(phraseCard.units.map((unit) => unit.surfaceText),
        ['rest', 'of', 'the', 'day']);
    expect(phraseCard.units.map((unit) => unit.translation),
        ['отдых', 'из', 'этот', 'день']);
    expect(package.detailByWordId, contains('word_of'));
    expect(package.detailByWordId, contains('word_the'));
  });

  test('POS grammar groups attach function words to a lexical head', () {
    final cases = <Map<String, dynamic>>[
      _grammarPackage(
        [('the', 'DET', 'этот'), ('classroom', 'NOUN', 'класс')],
        ['класс'],
      ),
      _grammarPackage(
        [
          ('a', 'DET', 'один'),
          ('new', 'ADJ', 'новый'),
          ('student', 'NOUN', 'ученица'),
        ],
        ['ученица'],
      ),
      _grammarPackage(
        [('is', 'AUX', 'есть'), ('late', 'ADJ', 'опоздала')],
        ['опоздала'],
      ),
      _grammarPackage(
        [
          ('does', 'AUX', 'делает'),
          ('not', 'PART', 'не'),
          ('know', 'VERB', 'знает'),
        ],
        ['не', 'знает'],
      ),
    ];

    for (final raw in cases) {
      final normalized = normalizeMobilePackageJsonForTest(raw);
      final package = MobileBookPackage(normalized);
      final paragraph = package.readerPayload.paragraphs.single;
      final groupId = paragraph.words.first.tapUnitId;
      expect(groupId, startsWith('grammar_segment_1_'));
      expect(
          paragraph.words.every((word) => word.tapUnitId == groupId), isTrue);
      expect(
          paragraph.words
              .every((word) => word.effectiveAlignmentKind == 'grammar_group'),
          isTrue);
      final card = DetailSheetPayload.fromSelection(
        item: paragraph,
        word: paragraph.words.first,
      );
      expect(card.units.length, paragraph.words.length);
      expect(card.units.first.type, 'GRAMMAR');
      expect(card.units.first.translation, isNotEmpty);
      expect(card.units.last.isPrimary, isTrue);
    }
  });

  test('unattached function word keeps its standalone tap target', () {
    final raw = _grammarPackage(
      [('of', 'ADP', 'из')],
      ['из'],
    );
    final normalized = normalizeMobilePackageJsonForTest(raw);
    final paragraph = (normalized['reader_payload']['paragraphs'] as List).first
        as Map<String, dynamic>;
    final word = ((paragraph['words'] as List).first as Map<String, dynamic>);
    final token = ((paragraph['tokens'] as List).first as Map<String, dynamic>);
    expect(word['tap_unit_id'], 'grammar_word_0');
    expect(token['tap_unit_id'], 'grammar_word_0');
    final package = MobileBookPackage(normalized);
    final detail = package.detailByWordId['grammar_word_0'];
    expect(detail, isNotNull);
    expect(detail!.sheetSourceText, 'of');
    expect(detail.sheetTranslationText, 'из');
  });

  test('Words use dictionary values while the header uses alignment', () {
    final raw = _grammarPackage(
      [('word', 'NOUN', 'контекст')],
      ['контекст'],
    );
    raw['dictionary_manifest'] = {
      'entries': {
        'word|NOUN': {
          'translations': ['словарное значение'],
        },
      },
    };

    final normalized = normalizeMobilePackageJsonForTest(raw);
    final package = MobileBookPackage(normalized);
    final detail = package.detailByWordId['grammar_word_0'];

    expect(detail, isNotNull);
    expect(detail!.sheetTranslationText, 'контекст');
    expect(detail.units.single.translation, 'словарное значение');
  });

  test('grammar groups allow reversed target order', () {
    final raw = _grammarPackage(
      [
        ('Sara', 'PROPN', 'Сара'),
        ('is', 'AUX', 'быть'),
        ('a', 'DET', 'один'),
        ('new', 'ADJ', 'новая'),
        ('student', 'NOUN', 'ученица'),
        ('at', 'ADP', 'у'),
        ('Hill', 'PROPN', 'Хилл'),
        ('School', 'NOUN', 'школы'),
      ],
      ['Сара', 'новая', 'ученица', 'школы', 'Хилл'],
    );

    final normalized = normalizeMobilePackageJsonForTest(raw);
    final package = MobileBookPackage(normalized);
    final words = package.readerPayload.paragraphs.single.words;

    expect(words[0].sourceUnitText, 'Sara');
    expect(words[0].effectiveFocusText, 'Сара');
    expect(words[1].sourceUnitText, 'is a new');
    expect(words[1].effectiveFocusText, 'новая');
    expect(words[2].tapUnitId, words[1].tapUnitId);
    expect(words[3].tapUnitId, words[1].tapUnitId);
    expect(words[4].sourceUnitText, 'student');
    expect(words[4].effectiveFocusText, 'ученица');
    expect(words[5].sourceUnitText, 'at Hill');
    expect(words[5].effectiveFocusText, 'Хилл');
    expect(words[6].tapUnitId, words[5].tapUnitId);
    expect(words[7].sourceUnitText, 'School');
    expect(words[7].effectiveFocusText, 'школы');
    expect(words[5].targetStartIndex, 4);
    expect(words[7].targetStartIndex, 3);
  });
  testWidgets('inflected target word stays inside the complete segment',
      (tester) async {
    final raw = _grammarPackage(
      [('English', 'ADJ', 'английский')],
      ['Её', 'урок', 'английского', 'языка'],
    );
    final normalized = normalizeMobilePackageJsonForTest(raw);
    final package = MobileBookPackage(normalized);
    final paragraph = package.readerPayload.paragraphs.single;
    final selected = paragraph.words.single;

    expect(selected.targetStartIndex, 2);
    expect(selected.targetEndIndex, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContinuousTranslationStrip(
            item: paragraph,
            selectedTapUnitId: selected.tapUnitId,
            translationLeftText: '',
            translationFocusText: 'английский',
            translationRightText: '',
          ),
        ),
      ),
    );

    expect(find.text('Её урок английского языка', findRichText: true),
        findsOneWidget);
    expect(find.text('английский'), findsNothing);
  });
  testWidgets('translation strip renders the complete selected segment',
      (tester) async {
    final normalized = normalizeMobilePackageJsonForTest(_package());
    final package = MobileBookPackage(normalized);
    final paragraph = package.readerPayload.paragraphs.single;
    final selected = paragraph.words.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContinuousTranslationStrip(
            item: paragraph,
            selectedTapUnitId: selected.tapUnitId,
            translationLeftText: null,
            translationFocusText: null,
            translationRightText: null,
          ),
        ),
      ),
    );

    expect(find.text('Она работает до конца дня', findRichText: true),
        findsOneWidget);
    final richText = tester.widget<Text>(find.byType(Text).last);
    expect(richText.maxLines, isNull);
    expect(richText.overflow, isNull);
  });
}
