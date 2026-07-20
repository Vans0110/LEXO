import 'models.dart';

const _sourceFirstPunctuationUnits = {
  '"',
  "'",
  '.',
  ',',
  '!',
  '?',
  ':',
  ';',
  '(',
  ')'
};

bool _isSourceFirstPunctuationUnit(Map<String, dynamic> unit) {
  final sourceText = (unit['source_text'] as String? ?? '').trim();
  return _sourceFirstPunctuationUnits.contains(sourceText);
}

Map<String, dynamic>? _selectSourceFirstCompactedUnit({
  required List<Map<String, dynamic>> analysisUnits,
  required ParagraphWordItem word,
}) {
  final visibleUnits = analysisUnits
      .where((unit) => !_isSourceFirstPunctuationUnit(unit))
      .toList();
  if (word.orderIndexInSegment < 0 ||
      word.orderIndexInSegment >= visibleUnits.length) {
    return null;
  }
  return visibleUnits[word.orderIndexInSegment];
}

Map<String, dynamic>? _selectSourceFirstTimeUnit({
  required List<Map<String, dynamic>> analysisUnits,
  required ParagraphWordItem word,
}) {
  final wordText = word.text.trim();
  if (int.tryParse(wordText) == null) {
    return null;
  }
  final candidates = analysisUnits.where((unit) {
    final sourceText = unit['source_text'] as String? ?? '';
    return sourceText.contains(':') && sourceText.contains(wordText);
  }).toList();
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((left, right) {
    final leftStart = left['token_start'] as int? ?? 0;
    final rightStart = right['token_start'] as int? ?? 0;
    return (leftStart - word.orderIndexInSegment).abs().compareTo(
          (rightStart - word.orderIndexInSegment).abs(),
        );
  });
  return candidates.first;
}

ParagraphSegmentV2Item? _findSourceFirstSegment({
  required ParagraphItem item,
  required ParagraphWordItem word,
}) {
  for (final entry in item.segmentsV2) {
    final matchesSegmentId =
        (word.segmentId ?? '').isNotEmpty && entry.id == word.segmentId;
    final matchesSourceText = (word.segmentId ?? '').isEmpty &&
        entry.sourceText == (word.segmentSourceText ?? '');
    if (matchesSegmentId || matchesSourceText) {
      return entry;
    }
  }
  return null;
}

Map<String, dynamic>? _selectSourceFirstUnit({
  required ParagraphSegmentV2Item segment,
  required ParagraphWordItem word,
}) {
  final analysisUnits =
      (segment.sourceAnalysis['units'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
  if (analysisUnits.isEmpty) {
    return null;
  }

  final timeUnit = _selectSourceFirstTimeUnit(
    analysisUnits: analysisUnits,
    word: word,
  );
  if (timeUnit != null) {
    return timeUnit;
  }

  final normalizedWord = word.text.trim().toLowerCase();
  if (normalizedWord.isNotEmpty) {
    for (final unit in analysisUnits) {
      if ((unit['source_text'] as String? ?? '').trim().toLowerCase() ==
          normalizedWord) {
        return unit;
      }
    }
  }

  final compactedUnit = _selectSourceFirstCompactedUnit(
    analysisUnits: analysisUnits,
    word: word,
  );
  if (compactedUnit != null) {
    return compactedUnit;
  }

  final exactTokenUnits = analysisUnits.where((unit) {
    final start = unit['token_start'] as int? ?? -1;
    final end = unit['token_end'] as int? ?? -1;
    return word.orderIndexInSegment >= start && word.orderIndexInSegment <= end;
  }).toList();
  final exactNonPunctuation = exactTokenUnits
      .where((unit) => !_isSourceFirstPunctuationUnit(unit))
      .toList();
  if (exactNonPunctuation.isNotEmpty) {
    exactNonPunctuation.sort((left, right) {
      final leftWidth =
          (left['token_end'] as int? ?? left['token_start'] as int? ?? 0) -
              (left['token_start'] as int? ?? 0);
      final rightWidth =
          (right['token_end'] as int? ?? right['token_start'] as int? ?? 0) -
              (right['token_start'] as int? ?? 0);
      if (leftWidth != rightWidth) {
        return leftWidth.compareTo(rightWidth);
      }
      final leftStart = left['token_start'] as int? ?? 0;
      final rightStart = right['token_start'] as int? ?? 0;
      return leftStart.compareTo(rightStart);
    });
    return exactNonPunctuation.first;
  }
  if (exactTokenUnits.isNotEmpty) {
    exactTokenUnits.sort((left, right) {
      final leftWidth =
          (left['token_end'] as int? ?? left['token_start'] as int? ?? 0) -
              (left['token_start'] as int? ?? 0);
      final rightWidth =
          (right['token_end'] as int? ?? right['token_start'] as int? ?? 0) -
              (right['token_start'] as int? ?? 0);
      if (leftWidth != rightWidth) {
        return leftWidth.compareTo(rightWidth);
      }
      final leftStart = left['token_start'] as int? ?? 0;
      final rightStart = right['token_start'] as int? ?? 0;
      return leftStart.compareTo(rightStart);
    });
    return exactTokenUnits.first;
  }

  analysisUnits.sort((left, right) {
    final leftStart = left['token_start'] as int? ?? 0;
    final rightStart = right['token_start'] as int? ?? 0;
    final leftDistance = (leftStart - word.orderIndexInSegment).abs();
    final rightDistance = (rightStart - word.orderIndexInSegment).abs();
    if (leftDistance != rightDistance) {
      return leftDistance.compareTo(rightDistance);
    }
    return leftStart.compareTo(rightStart);
  });
  return analysisUnits.first;
}

Map<String, dynamic>? _sourceFirstCoverageForUnit({
  required ParagraphSegmentV2Item segment,
  required Map<String, dynamic>? unit,
}) {
  if (unit == null) {
    return null;
  }
  final coverageUnits =
      segment.sourceCoverage['units'] as Map<String, dynamic>? ?? const {};
  return coverageUnits[unit['unit_id']] as Map<String, dynamic>?;
}

Map<String, dynamic>? _sourceFirstGroupForUnit({
  required ParagraphSegmentV2Item segment,
  required Map<String, dynamic>? unit,
  required Map<String, dynamic>? coverage,
}) {
  if (unit == null) {
    return null;
  }
  final groups =
      (segment.sourceAnalysis['groups'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
  final groupCoverages =
      segment.sourceCoverage['groups'] as Map<String, dynamic>? ?? const {};
  final ownerGroupId = coverage?['owner_unit_id'] as String? ?? '';

  Map<String, dynamic>? baseGroup;
  if (ownerGroupId.isNotEmpty) {
    for (final group in groups) {
      if ((group['group_id'] as String? ?? '') == ownerGroupId) {
        baseGroup = group;
        break;
      }
    }
  }
  if (baseGroup == null) {
    for (final group in groups) {
      if (((group['unit_ids'] as List<dynamic>? ?? const []))
          .contains(unit['unit_id'])) {
        baseGroup = group;
        break;
      }
    }
  }
  if (baseGroup == null) {
    return null;
  }
  return {
    ...baseGroup,
    'coverage': groupCoverages[baseGroup['group_id']] as Map<String, dynamic>?,
  };
}

DetailSheetSourceFirstPayload? buildLocalSourceFirstPayload({
  required ParagraphItem item,
  required ParagraphWordItem word,
}) {
  final segment = _findSourceFirstSegment(item: item, word: word);
  if (segment == null) {
    return null;
  }
  final selectedUnit = _selectSourceFirstUnit(segment: segment, word: word);
  final coverage =
      _sourceFirstCoverageForUnit(segment: segment, unit: selectedUnit);
  final selectedGroup = _sourceFirstGroupForUnit(
    segment: segment,
    unit: selectedUnit,
    coverage: coverage,
  );
  final runtimeEffectiveUnits =
      segment.sourceEffective['units'] as Map<String, dynamic>? ?? const {};
  final runtimeEffectiveCoverage = selectedUnit == null
      ? null
      : runtimeEffectiveUnits[selectedUnit['unit_id']] as Map<String, dynamic>?;
  final effectiveCoverage = runtimeEffectiveCoverage ??
      ((coverage != null &&
              (coverage['target_text'] as String? ?? '').trim().isNotEmpty)
          ? {
              ...coverage,
            }
          : (selectedGroup == null
              ? coverage
              : {
                  ...(selectedGroup['coverage'] as Map<String, dynamic>? ??
                      const <String, dynamic>{}),
                  'effective_source': 'owner_group',
                  'derived_from_group_id': selectedGroup['group_id'],
                }));
  final selectedUnitWithCoverage = selectedUnit == null
      ? null
      : {
          ...selectedUnit,
          'coverage': coverage,
          'effective_coverage': effectiveCoverage,
        };
  return DetailSheetSourceFirstPayload(
    segmentId: segment.id,
    analysisVersion: segment.analysisVersion,
    sourceText: segment.sourceText,
    targetText: segment.targetText,
    selectedUnit: selectedUnitWithCoverage,
    selectedGroup: selectedGroup,
    units: (segment.sourceAnalysis['units'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>(),
    groups: (segment.sourceAnalysis['groups'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>(),
  );
}

({String left, String focus, String right})? _backendSourceFirstFocus({
  required ParagraphWordItem word,
}) {
  final focusText = word.effectiveFocusText?.trim() ?? '';
  if (focusText.isEmpty) {
    return null;
  }
  return (
    left: word.effectiveLeftText?.trim() ?? '',
    focus: focusText,
    right: word.effectiveRightText?.trim() ?? '',
  );
}

({String left, String focus, String right})? buildLocalSourceFirstFocus({
  required ParagraphItem item,
  required ParagraphWordItem word,
}) {
  final payload = buildLocalSourceFirstPayload(item: item, word: word);
  final selectedUnit = payload?.selectedUnit;
  final selectedGroup = payload?.selectedGroup;
  final coverage =
      selectedUnit?['effective_coverage'] as Map<String, dynamic>? ??
          selectedUnit?['coverage'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
  if (payload == null || selectedUnit == null) {
    return null;
  }
  final segment = _findSourceFirstSegment(item: item, word: word);
  final targetTokens =
      ((segment?.sourceCoverage['target_tokens']) as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
  final start = coverage['target_token_start'] as int?;
  final end = coverage['target_token_end'] as int?;
  final coverageText = coverage['target_text'] as String? ?? '';
  if (start == null || end == null || targetTokens.isEmpty) {
    final groupCoverage = selectedGroup?['coverage'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final groupText = groupCoverage['target_text'] as String? ?? '';
    final groupStart = groupCoverage['target_token_start'] as int?;
    final groupEnd = groupCoverage['target_token_end'] as int?;
    if (groupStart != null && groupEnd != null && targetTokens.isNotEmpty) {
      final safeGroupStart = groupStart.clamp(0, targetTokens.length - 1);
      final safeGroupEnd =
          groupEnd.clamp(safeGroupStart, targetTokens.length - 1);
      final left = targetTokens
          .sublist(safeGroupStart > 3 ? safeGroupStart - 3 : 0, safeGroupStart)
          .map((token) => token['text'] as String? ?? '')
          .where((text) => text.isNotEmpty)
          .join(' ');
      final focus = targetTokens
          .sublist(safeGroupStart, safeGroupEnd + 1)
          .map((token) => token['text'] as String? ?? '')
          .where((text) => text.isNotEmpty)
          .join(' ');
      final right = targetTokens
          .sublist(
            safeGroupEnd + 1,
            (safeGroupEnd + 4) <= targetTokens.length
                ? safeGroupEnd + 4
                : targetTokens.length,
          )
          .map((token) => token['text'] as String? ?? '')
          .where((text) => text.isNotEmpty)
          .join(' ');
      return (
        left: left,
        focus: focus.isNotEmpty ? focus : groupText,
        right: right
      );
    }
    if (groupText.trim().isNotEmpty) {
      return (left: '', focus: groupText, right: '');
    }
    if (coverageText.trim().isEmpty) {
      return null;
    }
    return (left: '', focus: coverageText, right: '');
  }
  final safeStart = start.clamp(0, targetTokens.length - 1);
  final safeEnd = end.clamp(safeStart, targetTokens.length - 1);
  final left = targetTokens
      .sublist(safeStart > 3 ? safeStart - 3 : 0, safeStart)
      .map((token) => token['text'] as String? ?? '')
      .where((text) => text.isNotEmpty)
      .join(' ');
  final focus = targetTokens
      .sublist(safeStart, safeEnd + 1)
      .map((token) => token['text'] as String? ?? '')
      .where((text) => text.isNotEmpty)
      .join(' ');
  final right = targetTokens
      .sublist(
          safeEnd + 1,
          (safeEnd + 4) <= targetTokens.length
              ? safeEnd + 4
              : targetTokens.length)
      .map((token) => token['text'] as String? ?? '')
      .where((text) => text.isNotEmpty)
      .join(' ');
  return (
    left: left,
    focus: focus.isNotEmpty ? focus : coverageText,
    right: right
  );
}

({String left, String focus, String right})? buildPreferredSourceFirstFocus({
  required ParagraphItem item,
  required ParagraphWordItem word,
}) {
  return _backendSourceFirstFocus(word: word) ??
      buildLocalSourceFirstFocus(item: item, word: word);
}

class DetailSheetPayload {
  const DetailSheetPayload({
    required this.wordId,
    required this.tapUnitId,
    required this.sheetSourceText,
    required this.sheetTranslationText,
    required this.exampleSourceText,
    required this.exampleTranslationText,
    required this.sourceFirst,
    required this.dictionaryEntry,
    required this.units,
    this.blockSource = '',
    this.blockTranslation = '',
    this.blockDictionaryTranslation = '',
    this.blockType = '',
    this.blockExplanation = '',
  });

  final String wordId;
  final String tapUnitId;
  final String sheetSourceText;
  final String sheetTranslationText;
  final String exampleSourceText;
  final String exampleTranslationText;
  final DetailSheetSourceFirstPayload? sourceFirst;
  final DetailSheetDictionaryEntry? dictionaryEntry;
  final List<DetailSheetUnitItem> units;
  final String blockSource;
  final String blockTranslation;
  final String blockDictionaryTranslation;
  final String blockType;
  final String blockExplanation;

  factory DetailSheetPayload.fromJson(Map<String, dynamic> json) {
    return DetailSheetPayload(
      wordId: json['word_id'] as String? ?? '',
      tapUnitId: json['tap_unit_id'] as String? ?? '',
      sheetSourceText: json['sheet_source_text'] as String? ?? '',
      sheetTranslationText: json['sheet_translation_text'] as String? ?? '',
      exampleSourceText: json['example_source_text'] as String? ?? '',
      exampleTranslationText: json['example_translation_text'] as String? ?? '',
      sourceFirst: (json['source_first'] as Map<String, dynamic>?) != null
          ? DetailSheetSourceFirstPayload.fromJson(
              json['source_first'] as Map<String, dynamic>)
          : null,
      dictionaryEntry:
          (json['dictionary_entry'] as Map<String, dynamic>?) != null
              ? DetailSheetDictionaryEntry.fromJson(
                  json['dictionary_entry'] as Map<String, dynamic>)
              : null,
      units: (json['units'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DetailSheetUnitItem.fromJson)
          .toList(),
      blockSource: json['block_source'] as String? ?? '',
      blockTranslation: json['block_translation'] as String? ?? '',
      blockDictionaryTranslation:
          json['block_dictionary_translation'] as String? ?? '',
      blockType: json['block_type'] as String? ?? '',
      blockExplanation: json['block_explanation'] as String? ?? '',
    );
  }

  factory DetailSheetPayload.fromSelection({
    required ParagraphItem item,
    required ParagraphWordItem word,
  }) {
    final sourceFirst = buildLocalSourceFirstPayload(item: item, word: word);
    final sourceFirstCoverage = sourceFirst?.selectedUnit?['effective_coverage']
            as Map<String, dynamic>? ??
        sourceFirst?.selectedUnit?['coverage'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final selectedWords = item.words
        .where((entry) => entry.tapUnitId == word.tapUnitId)
        .toList()
      ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex));
    final units = <DetailSheetUnitItem>[];
    var index = 0;
    while (index < selectedWords.length) {
      final current = selectedWords[index];
      final lexicalUnitId = current.lexicalUnitId?.isNotEmpty == true
          ? current.lexicalUnitId!
          : current.id;
      final lexicalUnitType = current.isFunctionWord
          ? 'GRAMMAR'
          : (current.lexicalUnitType?.isNotEmpty == true
              ? current.lexicalUnitType!
              : (current.grammarHint?.isNotEmpty == true
                  ? 'GRAMMAR'
                  : 'LEXICAL'));
      final grouped = <ParagraphWordItem>[current];
      while (index + grouped.length < selectedWords.length &&
          selectedWords[index + grouped.length].lexicalUnitId ==
              lexicalUnitId) {
        grouped.add(selectedWords[index + grouped.length]);
      }
      final surfaceText = grouped.map((entry) => entry.text).join(' ');
      final lemmaText = grouped
          .map((entry) =>
              (entry.lemma?.isNotEmpty == true ? entry.lemma! : entry.text))
          .join(' ');
      final displayText = surfaceText;
      final dictionaryTranslation = grouped
          .expand((entry) => entry.dictionaryTranslations)
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .join(' / ');
      final functionTranslation = grouped
          .map((entry) => entry.functionWordTranslation?.trim() ?? '')
          .firstWhere((entry) => entry.isNotEmpty, orElse: () => '');
      final translation = dictionaryTranslation.isNotEmpty
          ? dictionaryTranslation
          : functionTranslation;
      units.add(
        DetailSheetUnitItem(
          id: lexicalUnitId,
          type: lexicalUnitType,
          text: displayText,
          surfaceText: surfaceText,
          lemma: lemmaText,
          translation: translation,
          grammarHint: grouped
              .map((entry) => entry.grammarHint?.trim() ?? '')
              .firstWhere((entry) => entry.isNotEmpty, orElse: () => ''),
          morphLabel: grouped
              .map((entry) => entry.morphLabel?.trim() ?? '')
              .firstWhere((entry) => entry.isNotEmpty, orElse: () => ''),
          functionWordLabel: grouped
              .map((entry) => entry.functionWordLabel?.trim() ?? '')
              .firstWhere((entry) => entry.isNotEmpty, orElse: () => ''),
          functionWordExplanation: grouped
              .map((entry) => entry.functionWordExplanation?.trim() ?? '')
              .firstWhere((entry) => entry.isNotEmpty, orElse: () => ''),
          functionWordBaseForm: grouped
              .map((entry) => entry.functionWordBaseForm?.trim() ?? '')
              .firstWhere((entry) => entry.isNotEmpty, orElse: () => ''),
          functionWordTranslation: functionTranslation,
          functionWordUsage: grouped
              .map((entry) => entry.functionWordUsage?.trim() ?? '')
              .firstWhere((entry) => entry.isNotEmpty, orElse: () => ''),
          functionWordExamples:
              grouped.expand((entry) => entry.functionWordExamples).toList(),
          isPrimary: lexicalUnitType != 'GRAMMAR',
          exampleSourceText: grouped.first.segmentSourceText ?? item.sourceText,
          exampleTranslationText:
              grouped.first.segmentTargetText ?? item.targetText,
        ),
      );
      index += grouped.length;
    }
    return DetailSheetPayload(
      wordId: word.id,
      tapUnitId: word.tapUnitId,
      sheetSourceText: word.sourceUnitText,
      sheetTranslationText:
          (word.effectiveTranslationText?.trim().isNotEmpty == true)
              ? (word.effectiveTranslationText ?? '')
              : ((sourceFirstCoverage['target_text'] as String? ?? '')
                      .trim()
                      .isNotEmpty
                  ? (sourceFirstCoverage['target_text'] as String? ?? '')
                  : ''),
      exampleSourceText: word.segmentSourceText ?? item.sourceText,
      exampleTranslationText: word.segmentTargetText ?? item.targetText,
      sourceFirst: sourceFirst,
      dictionaryEntry: null,
      units: units,
      blockSource: word.blockSource ?? '',
      blockTranslation: word.blockTranslation ?? '',
      blockDictionaryTranslation: word.blockDictionaryTranslation ?? '',
      blockType: word.blockType ?? '',
      blockExplanation: word.blockExplanation ?? '',
    );
  }
}

class DetailSheetDictionaryEntry {
  const DetailSheetDictionaryEntry({
    required this.query,
    required this.lemma,
    required this.transcript,
    required this.wordFound,
    required this.wordEntry,
    required this.translations,
    required this.partOfSpeech,
    required this.definitions,
    required this.inflectedForms,
    required this.verbForms,
    required this.phrasals,
    required this.entries,
    required this.hasContent,
    required this.note,
  });

  final String query;
  final String lemma;
  final String transcript;
  final bool wordFound;
  final DetailSheetDictionaryWordEntry? wordEntry;
  final List<String> translations;
  final String partOfSpeech;
  final List<String> definitions;
  final List<String> inflectedForms;
  final DetailSheetDictionaryVerbForms? verbForms;
  final List<DetailSheetDictionaryPhrasalItem> phrasals;
  final List<DetailSheetDictionaryArticle> entries;
  final bool hasContent;
  final String note;

  factory DetailSheetDictionaryEntry.fromJson(Map<String, dynamic> json) {
    final wordEntryJson = json['word_entry'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final verbFormsJson = json['verb_forms'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return DetailSheetDictionaryEntry(
      query: json['query'] as String? ?? '',
      lemma: json['lemma'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      wordFound: json['word_found'] as bool? ?? false,
      wordEntry: wordEntryJson.isEmpty
          ? null
          : DetailSheetDictionaryWordEntry.fromJson(wordEntryJson),
      translations: (json['translations'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      partOfSpeech: json['part_of_speech'] as String? ?? '',
      definitions: (json['definitions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      inflectedForms: (json['inflected_forms'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      verbForms: verbFormsJson.isEmpty
          ? null
          : DetailSheetDictionaryVerbForms.fromJson(verbFormsJson),
      phrasals: (json['phrasals'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DetailSheetDictionaryPhrasalItem.fromJson)
          .toList(),
      entries: (json['entries'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DetailSheetDictionaryArticle.fromJson)
          .toList(),
      hasContent: json['has_content'] as bool? ?? false,
      note: json['note'] as String? ?? '',
    );
  }
}

class DetailSheetDictionaryArticle {
  const DetailSheetDictionaryArticle({
    required this.source,
    required this.lemma,
    required this.partOfSpeech,
    required this.transcript,
    required this.translations,
    required this.definitions,
  });

  final String source;
  final String lemma;
  final String partOfSpeech;
  final String transcript;
  final List<String> translations;
  final List<String> definitions;

  factory DetailSheetDictionaryArticle.fromJson(Map<String, dynamic> json) {
    return DetailSheetDictionaryArticle(
      source: json['source'] as String? ?? '',
      lemma: json['lemma'] as String? ?? '',
      partOfSpeech: json['part_of_speech'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      translations: (json['translations'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      definitions: (json['definitions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class DetailSheetDictionaryWordEntry {
  const DetailSheetDictionaryWordEntry({
    required this.word,
    required this.stem,
    required this.normal,
    required this.transcript,
    required this.ngslRank,
    required this.ngslRankRef,
    required this.enTranslate,
    required this.similar,
  });

  final String word;
  final String stem;
  final String normal;
  final String transcript;
  final int ngslRank;
  final String ngslRankRef;
  final bool enTranslate;
  final List<String> similar;

  factory DetailSheetDictionaryWordEntry.fromJson(Map<String, dynamic> json) {
    return DetailSheetDictionaryWordEntry(
      word: json['word'] as String? ?? '',
      stem: json['stem'] as String? ?? '',
      normal: json['normal'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      ngslRank: json['ngsl_rank'] as int? ?? 0,
      ngslRankRef: json['ngsl_rank_ref'] as String? ?? '',
      enTranslate: json['en_translate'] as bool? ?? false,
      similar: (json['similar'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class DetailSheetDictionaryVerbForms {
  const DetailSheetDictionaryVerbForms({
    required this.verb,
    required this.present,
    required this.past,
    required this.participle,
  });

  final String verb;
  final String present;
  final String past;
  final String participle;

  factory DetailSheetDictionaryVerbForms.fromJson(Map<String, dynamic> json) {
    return DetailSheetDictionaryVerbForms(
      verb: json['verb'] as String? ?? '',
      present: json['present'] as String? ?? '',
      past: json['past'] as String? ?? '',
      participle: json['participle'] as String? ?? '',
    );
  }
}

class DetailSheetDictionaryPhrasalItem {
  const DetailSheetDictionaryPhrasalItem({
    required this.word,
    required this.transcript,
    required this.translation,
    required this.definitions,
    required this.linkWords,
  });

  final String word;
  final String transcript;
  final String translation;
  final List<String> definitions;
  final List<String> linkWords;

  factory DetailSheetDictionaryPhrasalItem.fromJson(Map<String, dynamic> json) {
    return DetailSheetDictionaryPhrasalItem(
      word: json['word'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      definitions: (json['definitions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      linkWords: (json['link_words'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class DetailSheetSourceFirstPayload {
  const DetailSheetSourceFirstPayload({
    required this.segmentId,
    required this.analysisVersion,
    required this.sourceText,
    required this.targetText,
    required this.selectedUnit,
    required this.selectedGroup,
    required this.units,
    required this.groups,
  });

  final String segmentId;
  final String analysisVersion;
  final String sourceText;
  final String targetText;
  final Map<String, dynamic>? selectedUnit;
  final Map<String, dynamic>? selectedGroup;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> groups;

  factory DetailSheetSourceFirstPayload.fromJson(Map<String, dynamic> json) {
    return DetailSheetSourceFirstPayload(
      segmentId: json['segment_id'] as String? ?? '',
      analysisVersion: json['analysis_version'] as String? ?? 'legacy_v1',
      sourceText: json['source_text'] as String? ?? '',
      targetText: json['target_text'] as String? ?? '',
      selectedUnit: json['selected_unit'] as Map<String, dynamic>?,
      selectedGroup: json['selected_group'] as Map<String, dynamic>?,
      units: (json['units'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
    );
  }
}

class DetailSheetUnitItem {
  const DetailSheetUnitItem({
    required this.id,
    required this.type,
    required this.text,
    required this.surfaceText,
    required this.lemma,
    required this.translation,
    required this.grammarHint,
    required this.morphLabel,
    this.functionWordLabel = '',
    this.functionWordExplanation = '',
    this.functionWordBaseForm = '',
    this.functionWordTranslation = '',
    this.functionWordUsage = '',
    this.functionWordExamples = const <Map<String, String>>[],
    required this.isPrimary,
    required this.exampleSourceText,
    required this.exampleTranslationText,
  });

  final String id;
  final String type;
  final String text;
  final String surfaceText;
  final String lemma;
  final String translation;
  final String grammarHint;
  final String morphLabel;
  final String functionWordLabel;
  final String functionWordExplanation;
  final String functionWordBaseForm;
  final String functionWordTranslation;
  final String functionWordUsage;
  final List<Map<String, String>> functionWordExamples;
  final bool isPrimary;
  final String exampleSourceText;
  final String exampleTranslationText;

  bool get isGrammar => type == 'GRAMMAR';
  bool get isBlock => type == 'BLOCK';

  factory DetailSheetUnitItem.fromJson(Map<String, dynamic> json) {
    return DetailSheetUnitItem(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'LEXICAL',
      text: json['text'] as String? ?? '',
      surfaceText: json['surface_text'] as String? ?? '',
      lemma: json['lemma'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      grammarHint: json['grammar_hint'] as String? ?? '',
      morphLabel: json['morph_label'] as String? ?? '',
      functionWordLabel: json['function_word_label'] as String? ?? '',
      functionWordExplanation:
          json['function_word_explanation'] as String? ?? '',
      functionWordBaseForm: json['function_word_base_form'] as String? ?? '',
      functionWordTranslation:
          json['function_word_translation'] as String? ?? '',
      functionWordUsage: json['function_word_usage'] as String? ?? '',
      functionWordExamples:
          (json['function_word_examples'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map((example) => {
                    'source': (example['source'] ?? '').toString(),
                    'translation': (example['translation'] ?? '').toString(),
                  })
              .toList(),
      isPrimary: json['is_primary'] as bool? ?? false,
      exampleSourceText: json['example_source_text'] as String? ?? '',
      exampleTranslationText: json['example_translation_text'] as String? ?? '',
    );
  }
}
