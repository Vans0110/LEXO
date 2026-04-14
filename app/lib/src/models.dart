class BookStatus {
  const BookStatus({
    this.id,
    required this.hasBook,
    required this.status,
    this.title,
    this.sourceName,
    this.sourceLang,
    this.targetLang,
    this.modelName,
    this.errorMessage,
    this.paragraphCount = 0,
    this.currentParagraphIndex = 0,
  });

  final String? id;
  final bool hasBook;
  final String status;
  final String? title;
  final String? sourceName;
  final String? sourceLang;
  final String? targetLang;
  final String? modelName;
  final String? errorMessage;
  final int paragraphCount;
  final int currentParagraphIndex;

  factory BookStatus.fromJson(Map<String, dynamic> json) {
    return BookStatus(
      id: json['id'] as String?,
      hasBook: json['has_book'] as bool? ?? false,
      status: json['status'] as String? ?? 'empty',
      title: json['title'] as String?,
      sourceName: json['source_name'] as String?,
      sourceLang: json['source_lang'] as String?,
      targetLang: json['target_lang'] as String?,
      modelName: json['model_name'] as String?,
      errorMessage: json['error_message'] as String?,
      paragraphCount: json['paragraph_count'] as int? ?? 0,
      currentParagraphIndex: json['current_paragraph_index'] as int? ?? 0,
    );
  }
}

class LibraryBookItem {
  const LibraryBookItem({
    required this.id,
    required this.title,
    required this.sourceName,
    required this.sourceLang,
    required this.targetLang,
    required this.status,
    required this.modelName,
    required this.currentParagraphIndex,
    required this.isActive,
    this.desktopBookId,
    this.contentHash,
    this.errorMessage,
  });

  final String id;
  final String title;
  final String sourceName;
  final String sourceLang;
  final String targetLang;
  final String status;
  final String modelName;
  final int currentParagraphIndex;
  final bool isActive;
  final String? desktopBookId;
  final String? contentHash;
  final String? errorMessage;

  factory LibraryBookItem.fromJson(Map<String, dynamic> json) {
    return LibraryBookItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      sourceLang: json['source_lang'] as String? ?? '',
      targetLang: json['target_lang'] as String? ?? '',
      status: json['status'] as String? ?? 'empty',
      modelName: json['model_name'] as String? ?? '',
      currentParagraphIndex: json['current_paragraph_index'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? false,
      desktopBookId: json['desktop_book_id'] as String?,
      contentHash: json['content_hash'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class LibraryPayload {
  const LibraryPayload({
    required this.activeBookId,
    required this.items,
  });

  final String? activeBookId;
  final List<LibraryBookItem> items;

  factory LibraryPayload.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LibraryBookItem.fromJson)
        .toList();
    return LibraryPayload(
      activeBookId: json['active_book_id'] as String?,
      items: items,
    );
  }
}

class ParagraphItem {
  const ParagraphItem({
    required this.index,
    required this.sourceText,
    required this.targetText,
    required this.tokens,
    required this.words,
  });

  final int index;
  final String sourceText;
  final String targetText;
  final List<ParagraphTokenItem> tokens;
  final List<ParagraphWordItem> words;

  factory ParagraphItem.fromJson(Map<String, dynamic> json) {
    var tokens = (json['tokens'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ParagraphTokenItem.fromJson)
        .toList();
    final words = (json['words'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ParagraphWordItem.fromJson)
        .toList();
    final sourceText = json['source_text'] as String? ?? '';
    if (tokens.isEmpty && sourceText.isNotEmpty) {
      tokens = [
        ParagraphTokenItem(
          id: 'legacy_text',
          text: sourceText,
          kind: 'punctuation',
          orderIndex: 0,
          tapUnitId: null,
          wordId: null,
        ),
      ];
    }
    return ParagraphItem(
      index: json['index'] as int,
      sourceText: sourceText,
      targetText: json['target_text'] as String? ?? '',
      tokens: tokens,
      words: words,
    );
  }
}

class ParagraphTokenItem {
  const ParagraphTokenItem({
    required this.id,
    required this.text,
    required this.kind,
    required this.orderIndex,
    required this.tapUnitId,
    required this.wordId,
  });

  final String id;
  final String text;
  final String kind;
  final int orderIndex;
  final String? tapUnitId;
  final String? wordId;

  bool get isWord => kind == 'word';

  factory ParagraphTokenItem.fromJson(Map<String, dynamic> json) {
    return ParagraphTokenItem(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      kind: json['kind'] as String? ?? 'punctuation',
      orderIndex: json['order_index'] as int? ?? 0,
      tapUnitId: json['tap_unit_id'] as String?,
      wordId: json['word_id'] as String?,
    );
  }
}

class ParagraphWordItem {
  const ParagraphWordItem({
    required this.id,
    required this.text,
    required this.orderIndex,
    required this.anchorWordId,
    required this.tapUnitId,
    required this.sourceUnitText,
    required this.translationSpanText,
    required this.translationLeftText,
    required this.translationFocusText,
    required this.translationRightText,
    required this.unitTranslationSpanText,
    required this.unitTranslationLeftText,
    required this.unitTranslationFocusText,
    required this.unitTranslationRightText,
    this.segmentSourceText,
    this.segmentTargetText,
    this.lemma,
    this.pos,
    this.morph,
    this.lexicalUnitId,
    this.lexicalUnitType,
    this.grammarHint,
    this.morphLabel,
  });

  final String id;
  final String text;
  final int orderIndex;
  final String? anchorWordId;
  final String tapUnitId;
  final String sourceUnitText;
  final String translationSpanText;
  final String translationLeftText;
  final String translationFocusText;
  final String translationRightText;
  final String unitTranslationSpanText;
  final String unitTranslationLeftText;
  final String unitTranslationFocusText;
  final String unitTranslationRightText;
  final String? segmentSourceText;
  final String? segmentTargetText;
  final String? lemma;
  final String? pos;
  final String? morph;
  final String? lexicalUnitId;
  final String? lexicalUnitType;
  final String? grammarHint;
  final String? morphLabel;

  factory ParagraphWordItem.fromJson(Map<String, dynamic> json) {
    return ParagraphWordItem(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      orderIndex: json['order_index'] as int? ?? 0,
      anchorWordId: json['anchor_word_id'] as String?,
      tapUnitId: json['tap_unit_id'] as String? ?? '',
      sourceUnitText: json['source_unit_text'] as String? ?? '',
      translationSpanText: json['translation_span_text'] as String? ?? '',
      translationLeftText: json['translation_left_text'] as String? ?? '',
      translationFocusText: json['translation_focus_text'] as String? ?? '',
      translationRightText: json['translation_right_text'] as String? ?? '',
      unitTranslationSpanText: json['unit_translation_span_text'] as String? ?? '',
      unitTranslationLeftText: json['unit_translation_left_text'] as String? ?? '',
      unitTranslationFocusText: json['unit_translation_focus_text'] as String? ?? '',
      unitTranslationRightText: json['unit_translation_right_text'] as String? ?? '',
      segmentSourceText: json['segment_source_text'] as String?,
      segmentTargetText: json['segment_target_text'] as String?,
      lemma: json['lemma'] as String?,
      pos: json['pos'] as String?,
      morph: json['morph'] as String?,
      lexicalUnitId: json['lexical_unit_id'] as String?,
      lexicalUnitType: json['lexical_unit_type'] as String?,
      grammarHint: json['grammar_hint'] as String?,
      morphLabel: json['morph_label'] as String?,
    );
  }
}

class ReaderPayload {
  const ReaderPayload({
    required this.bookId,
    required this.title,
    required this.status,
    required this.sourceLang,
    required this.targetLang,
    required this.currentParagraphIndex,
    required this.paragraphs,
  });

  final String? bookId;
  final String? title;
  final String status;
  final String? sourceLang;
  final String? targetLang;
  final int currentParagraphIndex;
  final List<ParagraphItem> paragraphs;

  factory ReaderPayload.fromJson(Map<String, dynamic> json) {
    final items = (json['paragraphs'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ParagraphItem.fromJson)
        .toList();
    return ReaderPayload(
      bookId: json['book_id'] as String?,
      title: json['title'] as String?,
      status: json['status'] as String? ?? 'empty',
      sourceLang: json['source_lang'] as String?,
      targetLang: json['target_lang'] as String?,
      currentParagraphIndex: json['current_paragraph_index'] as int? ?? 0,
      paragraphs: items,
    );
  }
}

class TtsProfile {
  const TtsProfile({
    required this.id,
    required this.engineId,
    required this.voiceId,
    required this.displayName,
    required this.lang,
  });

  final String id;
  final String engineId;
  final String voiceId;
  final String displayName;
  final String lang;

  factory TtsProfile.fromJson(Map<String, dynamic> json) {
    return TtsProfile(
      id: json['id'] as String,
      engineId: json['engine_id'] as String,
      voiceId: json['voice_id'] as String,
      displayName: json['display_name'] as String,
      lang: json['lang'] as String? ?? 'en',
    );
  }
}

class TtsSegmentItem {
  const TtsSegmentItem({
    required this.segmentIndex,
    required this.paragraphIndex,
    required this.sourceText,
    required this.audioPath,
    required this.durationMs,
    required this.pauseAfterMs,
    required this.status,
  });

  final int segmentIndex;
  final int paragraphIndex;
  final String sourceText;
  final String audioPath;
  final int durationMs;
  final int pauseAfterMs;
  final String status;

  factory TtsSegmentItem.fromJson(Map<String, dynamic> json) {
    return TtsSegmentItem(
      segmentIndex: json['segment_index'] as int,
      paragraphIndex: json['paragraph_index'] as int,
      sourceText: json['source_text'] as String? ?? '',
      audioPath: json['audio_path'] as String? ?? '',
      durationMs: json['duration_ms'] as int? ?? 0,
      pauseAfterMs: json['pause_after_ms'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
    );
  }
}

class TtsLevel {
  const TtsLevel({
    required this.id,
    required this.name,
    required this.playbackSpeed,
    this.effectivePlaybackSpeed = 1.0,
    this.audioVariant = 'base',
    this.nativeRate = 0.89,
  });

  final int id;
  final String name;
  final double playbackSpeed;
  final double effectivePlaybackSpeed;
  final String audioVariant;
  final double nativeRate;

  factory TtsLevel.fromJson(Map<String, dynamic> json) {
    return TtsLevel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      playbackSpeed: (json['playback_speed'] as num?)?.toDouble() ?? 1.0,
      effectivePlaybackSpeed:
          (json['effective_playback_speed'] as num?)?.toDouble()
          ?? (json['playback_speed'] as num?)?.toDouble()
          ?? 1.0,
      audioVariant: json['audio_variant'] as String? ?? 'base',
      nativeRate: (json['native_rate'] as num?)?.toDouble() ?? 0.89,
    );
  }
}

class TtsJobItem {
  const TtsJobItem({
    required this.jobId,
    required this.levelId,
    required this.levelName,
    required this.targetWpm,
    required this.audioVariant,
    required this.nativeRate,
    required this.rate,
    required this.pauseScale,
    required this.voiceId,
    required this.status,
    required this.playbackState,
    required this.currentSegmentIndex,
    required this.totalSegments,
    required this.readySegments,
    required this.generationProgress,
    required this.currentSegmentNumber,
    required this.playbackProgress,
    this.errorMessage,
  });

  final String jobId;
  final int levelId;
  final String levelName;
  final int targetWpm;
  final String audioVariant;
  final double nativeRate;
  final double rate;
  final double pauseScale;
  final String voiceId;
  final String status;
  final String playbackState;
  final int currentSegmentIndex;
  final int totalSegments;
  final int readySegments;
  final double generationProgress;
  final int currentSegmentNumber;
  final double playbackProgress;
  final String? errorMessage;

  bool get hasJob => jobId.isNotEmpty;
  bool get isReady => status == 'ready';
  bool get isGenerating => status == 'queued' || status == 'generating';
  bool get isActive => playbackState == 'playing' || playbackState == 'paused';
  String get statusLabel {
    switch (status) {
      case 'queued':
        return 'В очереди';
      case 'generating':
        return 'Генерация';
      case 'ready':
        return 'Готово';
      case 'error':
        return 'Ошибка';
      default:
        return status;
    }
  }

  String get playbackStateLabel {
    switch (playbackState) {
      case 'playing':
        return 'Воспроизведение';
      case 'paused':
        return 'Пауза';
      default:
        return 'Ожидание';
    }
  }

  factory TtsJobItem.fromJson(Map<String, dynamic> json) {
    return TtsJobItem(
      jobId: json['id'] as String? ?? '',
      levelId: json['level_id'] as int? ?? 0,
      levelName: json['level_name'] as String? ?? '',
      targetWpm: json['target_wpm'] as int? ?? 0,
      audioVariant: json['audio_variant'] as String? ?? 'base',
      nativeRate: (json['native_rate'] as num?)?.toDouble() ?? 0.89,
      rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
      pauseScale: (json['pause_scale'] as num?)?.toDouble() ?? 1.0,
      voiceId: json['voice_id'] as String? ?? '',
      status: json['status'] as String? ?? 'idle',
      playbackState: json['playback_state'] as String? ?? 'idle',
      currentSegmentIndex: json['current_segment_index'] as int? ?? 0,
      totalSegments: json['total_segments'] as int? ?? 0,
      readySegments: json['ready_segments'] as int? ?? 0,
      generationProgress:
          (json['generation_progress'] as num?)?.toDouble() ?? 0.0,
      currentSegmentNumber: json['current_segment_number'] as int? ?? 0,
      playbackProgress:
          (json['playback_progress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class TtsState {
  const TtsState({
    required this.jobs,
    required this.activeJob,
    required this.activeSegments,
  });

  final List<TtsJobItem> jobs;
  final TtsJobItem? activeJob;
  final List<TtsSegmentItem> activeSegments;

  bool get hasActiveJob => activeJob != null && activeJob!.hasJob;
  bool get hasGeneratingJobs => jobs.any((item) => item.isGenerating);

  factory TtsState.fromJson(Map<String, dynamic> json) {
    final jobs = (json['jobs'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TtsJobItem.fromJson)
        .toList();
    final activeJobJson = json['active_job'] as Map<String, dynamic>?;
    final activeSegments = (json['active_segments'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TtsSegmentItem.fromJson)
        .toList();
    return TtsState(
      jobs: jobs,
      activeJob: activeJobJson != null ? TtsJobItem.fromJson(activeJobJson) : null,
      activeSegments: activeSegments,
    );
  }
}

class TtsPackageStage {
  const TtsPackageStage({
    required this.stageKey,
    required this.label,
    required this.status,
    required this.doneCount,
    required this.totalCount,
    required this.errorMessage,
  });

  final String stageKey;
  final String label;
  final String status;
  final int doneCount;
  final int totalCount;
  final String errorMessage;

  bool get isRunning => status == 'queued' || status == 'running';
  bool get isDone => status == 'done';
  bool get isError => status == 'error';

  factory TtsPackageStage.fromJson(Map<String, dynamic> json) {
    return TtsPackageStage(
      stageKey: json['stage_key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      doneCount: json['done_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
      errorMessage: json['error_message'] as String? ?? '',
    );
  }
}

class TtsPackageState {
  const TtsPackageState({
    required this.packageJobId,
    required this.bookId,
    required this.voiceId,
    required this.status,
    required this.errorMessage,
    required this.stages,
  });

  final String packageJobId;
  final String bookId;
  final String voiceId;
  final String status;
  final String errorMessage;
  final List<TtsPackageStage> stages;

  bool get hasJob => packageJobId.isNotEmpty;
  bool get isRunning => status == 'queued' || status == 'running';

  factory TtsPackageState.fromJson(Map<String, dynamic> json) {
    return TtsPackageState(
      packageJobId: json['package_job_id'] as String? ?? '',
      bookId: json['book_id'] as String? ?? '',
      voiceId: json['voice_id'] as String? ?? '',
      status: json['status'] as String? ?? 'idle',
      errorMessage: json['error_message'] as String? ?? '',
      stages: (json['stages'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TtsPackageStage.fromJson)
          .toList(),
    );
  }
}

class WordLookup {
  const WordLookup({
    required this.word,
    required this.lemma,
    required this.partOfSpeech,
    required this.mainMeaning,
    required this.otherMeanings,
    required this.fromCache,
  });

  final String word;
  final String lemma;
  final String partOfSpeech;
  final String mainMeaning;
  final List<String> otherMeanings;
  final bool fromCache;

  factory WordLookup.fromJson(Map<String, dynamic> json) {
    return WordLookup(
      word: json['word'] as String,
      lemma: json['lemma'] as String,
      partOfSpeech: json['part_of_speech'] as String? ?? 'unknown',
      mainMeaning: json['main_meaning'] as String? ?? '',
      otherMeanings: (json['other_meanings'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      fromCache: json['from_cache'] as bool? ?? false,
    );
  }
}

class SavedWordItem {
  const SavedWordItem({
    required this.word,
    required this.lemma,
    required this.translation,
    required this.addedAt,
  });

  final String word;
  final String lemma;
  final String translation;
  final String addedAt;

  factory SavedWordItem.fromJson(Map<String, dynamic> json) {
    return SavedWordItem(
      word: json['word'] as String,
      lemma: json['lemma'] as String,
      translation: json['translation'] as String,
      addedAt: json['added_at'] as String,
    );
  }
}
