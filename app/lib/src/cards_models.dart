class SavedCardsPayload {
  const SavedCardsPayload({
    required this.items,
    required this.summary,
  });

  final List<SavedCardItem> items;
  final CardsSummary summary;

  factory SavedCardsPayload.fromJson(Map<String, dynamic> json) {
    return SavedCardsPayload(
      items: (json['items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(SavedCardItem.fromJson)
          .toList(),
      summary: CardsSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

class CardsSummary {
  const CardsSummary({
    required this.total,
    required this.fresh,
    required this.learning,
    required this.known,
    required this.mastered,
  });

  final int total;
  final int fresh;
  final int learning;
  final int known;
  final int mastered;

  factory CardsSummary.fromJson(Map<String, dynamic> json) {
    return CardsSummary(
      total: json['total'] as int? ?? 0,
      fresh: json['new'] as int? ?? 0,
      learning: json['learning'] as int? ?? 0,
      known: json['known'] as int? ?? 0,
      mastered: json['mastered'] as int? ?? 0,
    );
  }
}

class SavedCardItem {
  const SavedCardItem({
    required this.id,
    required this.cardType,
    required this.headText,
    required this.surfaceText,
    required this.lemma,
    required this.translation,
    required this.exampleText,
    required this.exampleTranslation,
    required this.pos,
    required this.grammarLabel,
    required this.morphLabel,
    required this.sourceBookId,
    required this.createdAt,
    required this.status,
    required this.progressScore,
    required this.reviewCount,
    required this.lastReviewedAt,
  });

  final String id;
  final String cardType;
  final String headText;
  final String surfaceText;
  final String lemma;
  final String translation;
  final String exampleText;
  final String exampleTranslation;
  final String pos;
  final String grammarLabel;
  final String morphLabel;
  final String sourceBookId;
  final String createdAt;
  final String status;
  final int progressScore;
  final int reviewCount;
  final String lastReviewedAt;

  bool get isPhrase => cardType == 'phrase';
  bool get isGrammar => cardType == 'grammar';

  String get progressLabel => '$progressScore/7';

  factory SavedCardItem.fromJson(Map<String, dynamic> json) {
    return SavedCardItem(
      id: json['id'] as String? ?? '',
      cardType: json['card_type'] as String? ?? 'lexical',
      headText: json['head_text'] as String? ?? '',
      surfaceText: json['surface_text'] as String? ?? '',
      lemma: json['lemma'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      exampleText: json['example_text'] as String? ?? '',
      exampleTranslation: json['example_translation'] as String? ?? '',
      pos: json['pos'] as String? ?? '',
      grammarLabel: json['grammar_label'] as String? ?? '',
      morphLabel: json['morph_label'] as String? ?? '',
      sourceBookId: json['source_book_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      status: json['status'] as String? ?? 'new',
      progressScore: json['progress_score'] as int? ?? 0,
      reviewCount: json['review_count'] as int? ?? 0,
      lastReviewedAt: json['last_reviewed_at'] as String? ?? '',
    );
  }
}
