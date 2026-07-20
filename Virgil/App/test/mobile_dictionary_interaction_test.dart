import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/detail_sheet_models.dart';
import 'package:virgil/src/models.dart';
import 'package:virgil/src/mobile/mobile_package_models.dart';
import 'package:virgil/src/mobile/mobile_package_repository.dart';
import 'package:virgil/src/mobile/virgil_bundled_book_repository.dart';
import 'package:virgil/src/widgets/continuous_translation_strip.dart';
import 'package:virgil/src/widgets/interactive_paragraph_text.dart';
import 'package:virgil/src/widgets/reader_detail_sheet.dart';

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
      'blocks': [
        {
          'segment_id': 'segment_1',
          'source': 'rest of the day',
          'translation': 'до конца дня',
          'block_type': 'grammar_construction',
          'explanation': 'Указывает на оставшуюся часть времени.',
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
      'blocks': {
        'rest of the day': {
          'translations': ['оставшаяся часть дня', 'до конца дня'],
          'variants': [
            {
              'translation': 'оставшаяся часть дня',
              'translation_kind': 'dictionary_fallback',
            },
            {
              'translation': 'до конца дня',
              'translation_kind': 'contextual',
            },
          ],
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
    'blocks': <Map<String, dynamic>>[],
  };
  package['dictionary_manifest'] = {'entries': dictionaryEntries};
  return package;
}

void main() {
  testWidgets('selected multi-word group fills the whitespace between words',
      (tester) async {
    const groupId = 'group_there_are';
    const tokens = [
      ParagraphTokenItem(
        id: 'token_there',
        text: 'There',
        kind: 'word',
        orderIndex: 0,
        tapUnitId: groupId,
        wordId: 'word_there',
      ),
      ParagraphTokenItem(
        id: 'token_space',
        text: ' ',
        kind: 'punctuation',
        orderIndex: 1,
        tapUnitId: null,
        wordId: null,
      ),
      ParagraphTokenItem(
        id: 'token_are',
        text: 'are',
        kind: 'word',
        orderIndex: 2,
        tapUnitId: groupId,
        wordId: 'word_are',
      ),
    ];
    final words = [
      ParagraphWordItem.fromJson({
        ..._word('word_there', 'There', 'PRON', 0),
        'tap_unit_id': groupId,
      }),
      ParagraphWordItem.fromJson({
        ..._word('word_are', 'are', 'AUX', 1),
        'tap_unit_id': groupId,
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveParagraphText(
            tokens: tokens,
            words: words,
            selectedTapUnitId: groupId,
            onWordTap: (_) {},
            onWordLongPress: (_) {},
          ),
        ),
      ),
    );

    final whitespace = tester.widget<Container>(
      find
          .ancestor(
            of: find.text(' '),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(whitespace.color, isNotNull);
  });

  test('reader lexicon restores runtime dictionary and alignments', () {
    final lexicon = <String, dynamic>{
      'version': 3,
      'book_id': 'book-test',
      'source_lang': 'en',
      'target_lang': 'ru',
      'words': {
        'room|NOUN': {
          'translations': ['комната', 'комнату'],
        },
      },
      'blocks': {
        'sit down': {
          'translations': ['садится'],
        },
      },
      'word_alignments': [
        {
          'word_id': 'word-room',
          'dictionary_key': 'room|NOUN',
          'translation': 'комнату',
        },
      ],
      'block_alignments': [
        {
          'segment_id': 'segment-1',
          'block_key': 'sit down',
          'source': 'sit down',
          'translation': 'садится',
        },
      ],
    };

    final dictionary = dictionaryManifestFromReaderLexicon(lexicon);
    final alignment = alignmentFromReaderLexicon(lexicon);

    expect((dictionary['entries'] as Map)['room|NOUN']['translations'],
        ['комната', 'комнату']);
    expect((alignment['entries'] as List).single['translation'], 'комнату');
    expect(
        (alignment['entries'] as List).single, isNot(contains('translations')));
    expect((alignment['blocks'] as List).single['block_key'], 'sit down');
  });

  test('block alignment owns one source block and builds a multi-word card',
      () {
    final normalized = normalizeMobilePackageJsonForTest(
      normalizeMobilePackageJsonForTest(_package()),
    );
    final paragraphJson = (normalized['reader_payload']['paragraphs'] as List)
        .first as Map<String, dynamic>;
    final wordsJson =
        (paragraphJson['words'] as List).cast<Map<String, dynamic>>();
    final blockId = wordsJson.first['tap_unit_id'];

    expect(blockId, startsWith('block_segment_1_'));
    expect(wordsJson.every((word) => word['tap_unit_id'] == blockId), isTrue);
    expect(
        wordsJson
            .every((word) => word['source_unit_text'] == 'rest of the day'),
        isTrue);
    expect(
        wordsJson
            .every((word) => (word['block_alignments'] as List).length == 1),
        isTrue);
    expect(wordsJson.map((word) => word['target_start_index']).toSet(), {2});
    expect(wordsJson.map((word) => word['target_end_index']).toSet(), {4});

    final package = MobileBookPackage(normalized);
    final paragraph = package.readerPayload.paragraphs.single;
    final blockCard = DetailSheetPayload.fromSelection(
      item: paragraph,
      word: paragraph.words.first,
    );
    expect(blockCard.sheetSourceText, 'rest of the day');
    expect(blockCard.blockType, 'grammar_construction');
    expect(blockCard.blockDictionaryTranslation, 'оставшаяся часть дня');
    expect(blockCard.blockTranslation, 'до конца дня');
    expect(
        blockCard.blockExplanation, 'Указывает на оставшуюся часть времени.');
    expect(blockCard.units.map((unit) => unit.surfaceText),
        ['rest', 'of', 'the', 'day']);
    expect(blockCard.units.map((unit) => unit.translation),
        ['отдых', 'из', 'этот', 'день']);
    expect(package.detailByWordId, contains('word_of'));
    expect(package.detailByWordId, contains('word_the'));
  });

  test('POS grammar groups attach function words to a lexical head', () {
    final cases = <(Map<String, dynamic>, String)>[
      (
        _grammarPackage(
          [('the', 'DET', 'этот'), ('classroom', 'NOUN', 'класс')],
          ['класс'],
        ),
        'класс',
      ),
      (
        _grammarPackage(
          [
            ('a', 'DET', 'один'),
            ('new', 'ADJ', 'новая'),
            ('student', 'NOUN', 'ученица'),
          ],
          ['новая', 'ученица'],
        ),
        'новая ученица',
      ),
      (
        _grammarPackage(
          [('is', 'AUX', 'есть'), ('late', 'ADJ', 'опоздала')],
          ['опоздала'],
        ),
        'опоздала',
      ),
      (
        _grammarPackage(
          [
            ('does', 'AUX', 'делает'),
            ('not', 'PART', 'не'),
            ('know', 'VERB', 'знает'),
          ],
          ['не', 'знает'],
        ),
        'не знает',
      ),
      (
        _grammarPackage(
          [('into', 'ADP', 'в'), ('room', 'NOUN', 'комнату')],
          ['в', 'комнату'],
        ),
        'в комнату',
      ),
      (
        _grammarPackage(
          [
            ('with', 'ADP', 'с'),
            ('the', 'DET', 'этот'),
            ('class', 'NOUN', 'классом'),
          ],
          ['с', 'классом'],
        ),
        'с классом',
      ),
    ];

    for (final (raw, expectedTranslation) in cases) {
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
      expect(card.sheetTranslationText, expectedTranslation);
      expect(card.units.length, paragraph.words.length);
      expect(card.units.first.type, 'GRAMMAR');
      expect(card.units.first.translation, isNotEmpty);
      expect(card.units.last.isPrimary, isTrue);
    }
  });

  test('grammar groups preserve occurrence spans with repeated target words',
      () {
    final raw = _grammarPackage(
      [('into', 'ADP', 'в'), ('room', 'NOUN', 'комнате')],
      ['в', 'доме', 'в', 'комнате'],
    );
    final entries =
        (raw['word_to_word'] as Map<String, dynamic>)['entries'] as List;
    entries[0]['target_start_index'] = 2;
    entries[0]['target_end_index'] = 2;
    entries[1]['target_start_index'] = 3;
    entries[1]['target_end_index'] = 3;

    final package = MobileBookPackage(normalizeMobilePackageJsonForTest(raw));
    final paragraph = package.readerPayload.paragraphs.single;
    final card = DetailSheetPayload.fromSelection(
      item: paragraph,
      word: paragraph.words.first,
    );

    expect(card.sheetTranslationText, 'в комнате');
    expect(paragraph.words.first.targetStartIndex, 2);
    expect(paragraph.words.last.targetEndIndex, 3);
  });

  test('display highlight can include a target insertion without changing card',
      () {
    final raw = _grammarPackage(
      [('fourteen', 'NUM', 'четырнадцать')],
      ['комната', 'номер', 'четырнадцать'],
    );
    final entry = ((raw['word_to_word'] as Map<String, dynamic>)['entries']
            as List<dynamic>)
        .single as Map<String, dynamic>;
    entry['target_start_index'] = 2;
    entry['target_end_index'] = 2;
    entry['highlight_target_start_index'] = 1;
    entry['highlight_target_end_index'] = 2;
    entry['target_coverage_kind'] = 'insertion';

    final package = MobileBookPackage(normalizeMobilePackageJsonForTest(raw));
    final paragraph = package.readerPayload.paragraphs.single;
    final word = paragraph.words.single;
    final card = DetailSheetPayload.fromSelection(item: paragraph, word: word);

    expect(word.targetStartIndex, 2);
    expect(word.targetEndIndex, 2);
    expect(word.highlightTargetStartIndex, 1);
    expect(word.highlightTargetEndIndex, 2);
    expect(card.sheetSourceText, 'fourteen');
    expect(card.sheetTranslationText, 'четырнадцать');
  });

  test('POS grammar groups attach AUX through ADP to a lexical head', () {
    final raw = _grammarPackage(
      [
        ('is', 'AUX', ''),
        ('in', 'ADP', 'in'),
        ('Room', 'NOUN', 'room'),
      ],
      ['in', 'room'],
    );

    final package = MobileBookPackage(normalizeMobilePackageJsonForTest(raw));
    final paragraph = package.readerPayload.paragraphs.single;
    final groupId = paragraph.words.first.tapUnitId;

    expect(groupId, startsWith('grammar_segment_1_is_in_Room'));
    expect(paragraph.words.every((word) => word.tapUnitId == groupId), isTrue);
    expect(paragraph.words.first.sourceUnitText, 'is in Room');
    expect(paragraph.words.first.effectiveFocusText, 'in room');
  });

  test('verified ownership stays separate from expanded target highlight', () {
    final raw = _grammarPackage(
      [
        ('am', 'AUX', ''),
        ('in', 'ADP', 'в'),
        ('the', 'DET', ''),
        ('wrong', 'ADJ', 'той'),
        ('room', 'NOUN', 'комнате'),
      ],
      ['не', 'в', 'той', 'комнате'],
    );
    final entries = ((raw['word_to_word'] as Map)['entries'] as List)
        .cast<Map<String, dynamic>>();
    for (var index = 0; index < entries.length; index++) {
      entries[index].addAll({
        'verified_occurrence': true,
        'owner_unit_id': 'owner_$index',
        'tap_unit_id': 'verified_word_$index',
        'verification_status': 'verified',
      });
    }
    entries[3].addAll({
      'target_start_index': 2,
      'target_end_index': 2,
      'highlight_target_start_index': 0,
      'highlight_target_end_index': 2,
      'target_coverage_kind': 'restructure',
    });

    final package = MobileBookPackage(normalizeMobilePackageJsonForTest(raw));
    final words = package.readerPayload.paragraphs.single.words;

    expect(words.map((word) => word.tapUnitId).toList(), [
      'verified_word_0',
      'verified_word_1',
      'verified_word_2',
      'verified_word_3',
      'verified_word_4',
    ]);
    expect(words[3].sourceUnitText, 'wrong');
    expect(words[3].targetStartIndex, 2);
    expect(words[3].targetEndIndex, 2);
    expect(words[3].highlightTargetStartIndex, 0);
    expect(words[3].highlightTargetEndIndex, 2);
  });

  test('shared verified tap id creates a source block without POS guessing',
      () {
    final raw = _grammarPackage(
      [('blue', 'ADJ', 'синий'), ('door', 'NOUN', 'дверь')],
      ['синяя', 'дверь'],
    );
    final entries = ((raw['word_to_word'] as Map)['entries'] as List)
        .cast<Map<String, dynamic>>();
    for (final entry in entries) {
      entry.addAll({
        'verified_occurrence': true,
        'owner_unit_id': 'verified_block',
        'tap_unit_id': 'verified_block',
        'verification_status': 'verified',
      });
    }

    final package = MobileBookPackage(normalizeMobilePackageJsonForTest(raw));
    final words = package.readerPayload.paragraphs.single.words;

    expect(words.every((word) => word.tapUnitId == 'verified_block'), isTrue);
    expect(words.every((word) => word.sourceUnitText == 'blue door'), isTrue);
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

  testWidgets('Words show function explanation without a translation',
      (tester) async {
    final payload = DetailSheetPayload.fromJson({
      'word_id': 'word_is',
      'tap_unit_id': 'word_is',
      'sheet_source_text': 'is',
      'sheet_translation_text': '',
      'example_source_text': 'Her English class is in Room fourteen.',
      'example_translation_text': '',
      'units': [
        {
          'id': 'word_is',
          'type': 'GRAMMAR',
          'text': 'is',
          'translation': '',
          'function_word_label': 'Auxiliary verb',
          'function_word_explanation':
              'Connects the subject to its description.',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReaderDetailSheet(payload: payload)),
      ),
    );

    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Auxiliary verb'), findsOneWidget);
    expect(
      find.text('Connects the subject to its description.'),
      findsOneWidget,
    );
  });

  testWidgets('inflected be form keeps surface title and its own explanation',
      (tester) async {
    final raw = _grammarPackage(
      [('are', 'VERB', '')],
      ['находятся'],
    );
    raw['dictionary_manifest'] = {
      'entries': <String, dynamic>{},
      'function_words': {
        'are|AUX': {
          'surface': 'are',
          'base_form': 'be',
          'translation': 'быть',
          'label': 'Форма be для you, we, they',
          'explanation': 'Подробное описание формы are.',
          'usage': 'Употребляется с you, we, they.',
          'examples': [
            {
              'source': 'There are books.',
              'translation': 'Есть книги.',
            }
          ],
          'match_keys': ['are|VERB'],
        },
      },
    };
    final rawParagraph =
        ((raw['reader_payload'] as Map<String, dynamic>)['paragraphs'] as List)
            .single as Map<String, dynamic>;
    ((rawParagraph['words'] as List).single as Map<String, dynamic>)['lemma'] =
        'be';

    final package = MobileBookPackage(normalizeMobilePackageJsonForTest(raw));
    final paragraph = package.readerPayload.paragraphs.single;
    final detail = DetailSheetPayload.fromSelection(
      item: paragraph,
      word: paragraph.words.single,
    );
    final unit = detail.units.single;

    expect(unit.text, 'are');
    expect(unit.lemma, 'be');
    expect(unit.translation, 'быть');
    expect(unit.functionWordBaseForm, 'be');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ReaderDetailSheet(payload: detail))),
    );
    expect(find.text('are'), findsWidgets);
    expect(find.text('Начальная форма: be'), findsOneWidget);
    expect(find.text('Форма be для you, we, they'), findsOneWidget);
    expect(find.text('Подробное описание формы are.'), findsOneWidget);
    expect(find.text('Употребление: Употребляется с you, we, they.'),
        findsOneWidget);
    expect(find.text('There are books. — Есть книги.'), findsOneWidget);
    expect(find.text('be'), findsNothing);
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

  testWidgets('detail sheet saves each vertical Words item independently',
      (tester) async {
    final payload = DetailSheetPayload.fromJson({
      'word_id': 'block_id',
      'tap_unit_id': 'block_id',
      'sheet_source_text': 'next to',
      'sheet_translation_text': 'рядом с',
      'example_source_text': 'Please sit next to Amir.',
      'example_translation_text': 'Пожалуйста, сядьте рядом с Амиром.',
      'dictionary_entry': {
        'query': 'next to',
        'lemma': 'next to',
        'has_content': true,
        'translations': ['рядом с'],
      },
      'units': [
        {
          'id': 'word_next',
          'text': 'next',
          'surface_text': 'next',
          'lemma': 'next',
          'translation': 'рядом',
          'is_primary': true,
        },
        {
          'id': 'word_to',
          'text': 'to',
          'surface_text': 'to',
          'lemma': 'to',
          'translation': 'на / с',
          'is_primary': true,
        },
      ],
    });
    DetailSheetUnitItem? savedUnit;
    List<String>? savedTranslations;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderDetailSheet(
            payload: payload,
            onSaveWord: (unit, translations) async {
              savedUnit = unit;
              savedTranslations = translations;
            },
          ),
        ),
      ),
    );

    expect(find.byTooltip('Save word'), findsNWidgets(2));
    expect(find.text('Save'), findsNothing);
    expect(tester.getTopLeft(find.text('next')).dy,
        lessThan(tester.getTopLeft(find.text('to')).dy));

    await tester.tap(find.byTooltip('Save word').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(savedUnit?.id, 'word_next');
    expect(savedTranslations, ['рядом']);
  });

  testWidgets('detail sheet renders a nested Blocks card with dictionary value',
      (tester) async {
    final payload = DetailSheetPayload.fromJson({
      'word_id': 'block_id',
      'tap_unit_id': 'block_id',
      'sheet_source_text': 'the rest of',
      'sheet_translation_text': 'конца',
      'example_source_text':
          'She checks every room number carefully for the rest of the day.',
      'example_translation_text':
          'Она внимательно проверяет номера всех комнат до конца дня.',
      'units': const <Map<String, dynamic>>[],
      'block_source': 'the rest of',
      'block_translation': 'конца',
      'block_dictionary_translation': 'оставшаяся часть чего-либо',
      'block_type': 'grammar_construction',
      'block_explanation':
          'Указывает на часть времени, количества или предмета, которая ещё осталась.',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReaderDetailSheet(payload: payload)),
      ),
    );

    expect(find.text('Blocks'), findsOneWidget);
    expect(find.text('the rest of'), findsNWidgets(2));
    expect(find.text('оставшаяся часть чего-либо'), findsOneWidget);
    expect(find.text('Тип: грамматическая конструкция'), findsOneWidget);
    expect(
      find.text(
        'Указывает на часть времени, количества или предмета, которая ещё осталась.',
      ),
      findsOneWidget,
    );
    expect(find.text('конца'), findsOneWidget);
  });

  testWidgets('all supported block types have Russian labels', (tester) async {
    const labels = <String, String>{
      'phrasal_verb': 'фразовый глагол',
      'fixed_expression': 'устойчивое выражение',
      'collocation': 'словосочетание',
      'grammar_construction': 'грамматическая конструкция',
      'prepositional_group': 'предложная группа',
      'name_group': 'группа имени собственного',
      'reordered_block': 'блок с изменённым порядком слов',
    };

    for (final entry in labels.entries) {
      final payload = DetailSheetPayload.fromJson({
        'word_id': 'block_id',
        'tap_unit_id': 'block_id',
        'sheet_source_text': 'source block',
        'sheet_translation_text': 'перевод',
        'units': const <Map<String, dynamic>>[],
        'block_source': 'source block',
        'block_translation': 'перевод',
        'block_type': entry.key,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReaderDetailSheet(payload: payload)),
        ),
      );
      expect(find.text('Тип: ${entry.value}'), findsOneWidget);
    }
  });
}
