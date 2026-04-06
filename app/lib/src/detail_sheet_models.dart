import 'models.dart';

class DetailSheetPayload {
  const DetailSheetPayload({
    required this.wordId,
    required this.tapUnitId,
    required this.sheetSourceText,
    required this.sheetTranslationText,
    required this.exampleSourceText,
    required this.exampleTranslationText,
    required this.units,
  });

  final String wordId;
  final String tapUnitId;
  final String sheetSourceText;
  final String sheetTranslationText;
  final String exampleSourceText;
  final String exampleTranslationText;
  final List<DetailSheetUnitItem> units;

  factory DetailSheetPayload.fromJson(Map<String, dynamic> json) {
    return DetailSheetPayload(
      wordId: json['word_id'] as String? ?? '',
      tapUnitId: json['tap_unit_id'] as String? ?? '',
      sheetSourceText: json['sheet_source_text'] as String? ?? '',
      sheetTranslationText: json['sheet_translation_text'] as String? ?? '',
      exampleSourceText: json['example_source_text'] as String? ?? '',
      exampleTranslationText: json['example_translation_text'] as String? ?? '',
      units: (json['units'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DetailSheetUnitItem.fromJson)
          .toList(),
    );
  }

  factory DetailSheetPayload.fromSelection({
    required ParagraphItem item,
    required ParagraphWordItem word,
  }) {
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
      final lexicalUnitType = current.lexicalUnitType?.isNotEmpty == true
          ? current.lexicalUnitType!
          : (current.grammarHint?.isNotEmpty == true ? 'GRAMMAR' : 'LEXICAL');
      final grouped = <ParagraphWordItem>[current];
      while (index + grouped.length < selectedWords.length &&
          selectedWords[index + grouped.length].lexicalUnitId == lexicalUnitId) {
        grouped.add(selectedWords[index + grouped.length]);
      }
      final surfaceText = grouped.map((entry) => entry.text).join(' ');
      final lemmaText = grouped
          .map((entry) => (entry.lemma?.isNotEmpty == true ? entry.lemma! : entry.text))
          .join(' ');
      final displayText = lexicalUnitType == 'GRAMMAR' ? surfaceText : lemmaText;
      final translation = grouped
          .map((entry) => entry.translationSpanText.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .join(' ');
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
          isPrimary: lexicalUnitType != 'GRAMMAR',
          exampleSourceText: grouped.first.segmentSourceText ?? item.sourceText,
          exampleTranslationText: grouped.first.segmentTargetText ?? item.targetText,
        ),
      );
      index += grouped.length;
    }
    return DetailSheetPayload(
      wordId: word.id,
      tapUnitId: word.tapUnitId,
      sheetSourceText: word.sourceUnitText,
      sheetTranslationText: word.translationFocusText.trim().isNotEmpty
          ? word.translationFocusText
          : word.translationSpanText,
      exampleSourceText: word.segmentSourceText ?? item.sourceText,
      exampleTranslationText: word.segmentTargetText ?? item.targetText,
      units: units,
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
  final bool isPrimary;
  final String exampleSourceText;
  final String exampleTranslationText;

  bool get isGrammar => type == 'GRAMMAR';
  bool get isPhrase => type == 'PHRASE';

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
      isPrimary: json['is_primary'] as bool? ?? false,
      exampleSourceText: json['example_source_text'] as String? ?? '',
      exampleTranslationText: json['example_translation_text'] as String? ?? '',
    );
  }
}
