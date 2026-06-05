import '../models.dart';
import '../detail_sheet_models.dart';

class MobileBookPackageMeta {
  const MobileBookPackageMeta({
    required this.localBookId,
    required this.desktopBookId,
    required this.title,
    required this.sourceName,
    required this.sourceLang,
    required this.targetLang,
    required this.modelName,
    required this.status,
    required this.currentParagraphIndex,
    required this.packageVersion,
    required this.contentHash,
    this.coverPath,
    this.selectedVoiceId,
    this.exportedAt,
    this.lastOpenedAt,
  });

  final String localBookId;
  final String desktopBookId;
  final String title;
  final String sourceName;
  final String sourceLang;
  final String targetLang;
  final String modelName;
  final String status;
  final int currentParagraphIndex;
  final int packageVersion;
  final String contentHash;
  final String? coverPath;
  final String? selectedVoiceId;
  final String? exportedAt;
  final String? lastOpenedAt;

  factory MobileBookPackageMeta.fromJson(Map<String, dynamic> json) {
    return MobileBookPackageMeta(
      localBookId: json['local_book_id'] as String? ?? '',
      desktopBookId: json['desktop_book_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      sourceLang: json['source_lang'] as String? ?? '',
      targetLang: json['target_lang'] as String? ?? '',
      modelName: json['model_name'] as String? ?? '',
      status: json['status'] as String? ?? 'ready',
      currentParagraphIndex: json['current_paragraph_index'] as int? ?? 0,
      packageVersion: json['package_version'] as int? ?? 1,
      contentHash: json['content_hash'] as String? ?? '',
      coverPath: json['cover'] as String?,
      selectedVoiceId: json['selected_voice_id'] as String?,
      exportedAt: json['exported_at'] as String?,
      lastOpenedAt: json['last_opened_at'] as String?,
    );
  }

  LibraryBookItem toLibraryItem({
    required bool isActive,
    String? coverFilePath,
  }) {
    return LibraryBookItem(
      id: localBookId,
      title: title,
      sourceName: sourceName,
      sourceLang: sourceLang,
      targetLang: targetLang,
      status: status,
      modelName: modelName,
      currentParagraphIndex: currentParagraphIndex,
      isActive: isActive,
      desktopBookId: desktopBookId,
      contentHash: contentHash,
      coverFilePath: coverFilePath,
    );
  }
}

class MobileBookPackage {
  MobileBookPackage(this.rawJson)
      : meta = MobileBookPackageMeta.fromJson(
          (rawJson['meta'] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
        ),
        readerPayload = ReaderPayload.fromJson(
          (rawJson['reader_payload'] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
        ),
        profiles = ((rawJson['tts_manifest'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})['profiles'] as List<dynamic>? ??
                const [])
            .cast<Map<String, dynamic>>()
            .map(TtsProfile.fromJson)
            .toList(),
        levels = ((rawJson['tts_manifest'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})['levels'] as List<dynamic>? ??
                const [])
            .cast<Map<String, dynamic>>()
            .map(TtsLevel.fromJson)
            .toList(),
        ttsState = _buildTtsState(
          (rawJson['tts_manifest'] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
        ),
        segmentsByJobId = _buildSegmentsByJobId(
          (rawJson['tts_manifest'] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
        ),
        wordAudioVoiceIds = _buildWordAudioVoiceIds(
          rawJson['word_audio_manifest'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
        ),
        wordAudioEntriesByVoice = _buildWordAudioEntriesByVoice(
          rawJson['word_audio_manifest'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
        ),
        dictionaryManifest =
            rawJson['dictionary_manifest'] as Map<String, dynamic>? ??
                const <String, dynamic>{},
        detailByWordId = _buildDetailByWordId(
          rawJson['detail_manifest'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
          rawJson['dictionary_manifest'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
          rawJson['reader_payload'] as Map<String, dynamic>? ??
              const <String, dynamic>{},
        );

  final Map<String, dynamic> rawJson;
  final MobileBookPackageMeta meta;
  final ReaderPayload readerPayload;
  final List<TtsProfile> profiles;
  final List<TtsLevel> levels;
  final TtsState ttsState;
  final Map<String, List<TtsSegmentItem>> segmentsByJobId;
  final List<String> wordAudioVoiceIds;
  final Map<String, List<String>> wordAudioEntriesByVoice;
  final Map<String, dynamic> dictionaryManifest;
  final Map<String, DetailSheetPayload> detailByWordId;

  List<TtsSegmentItem> segmentsForJob(String jobId) {
    return segmentsByJobId[jobId] ?? const <TtsSegmentItem>[];
  }

  String get wordAudioVoiceId =>
      wordAudioVoiceIds.isEmpty ? '' : wordAudioVoiceIds.first;

  List<String> get wordAudioEntries {
    final result = <String>{};
    for (final entries in wordAudioEntriesByVoice.values) {
      result.addAll(entries);
    }
    return result.toList();
  }

  bool hasWordAudioVoice(String voiceId) =>
      wordAudioEntriesByVoice.containsKey(voiceId.trim());

  List<String> wordAudioEntriesForVoice(String voiceId) =>
      wordAudioEntriesByVoice[voiceId.trim()] ?? const <String>[];

  static TtsState _buildTtsState(Map<String, dynamic> manifest) {
    final jobsJson = (manifest['jobs'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final jobs = jobsJson.map(TtsJobItem.fromJson).toList();
    Map<String, dynamic>? activeJobJson;
    for (final job in jobsJson) {
      final playbackState = job['playback_state'] as String? ?? 'idle';
      if (playbackState == 'playing' || playbackState == 'paused') {
        activeJobJson = job;
        break;
      }
    }
    final activeSegments =
        ((activeJobJson?['segments'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TtsSegmentItem.fromJson)
            .toList();
    return TtsState(
      jobs: jobs,
      activeJob:
          activeJobJson != null ? TtsJobItem.fromJson(activeJobJson) : null,
      activeSegments: activeSegments,
    );
  }

  static Map<String, List<TtsSegmentItem>> _buildSegmentsByJobId(
      Map<String, dynamic> manifest) {
    final jobsJson = (manifest['jobs'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final result = <String, List<TtsSegmentItem>>{};
    for (final job in jobsJson) {
      final jobId = job['id'] as String? ?? '';
      if (jobId.isEmpty) {
        continue;
      }
      result[jobId] = ((job['segments'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TtsSegmentItem.fromJson)
          .toList();
    }
    return result;
  }

  static List<String> _buildWordAudioVoiceIds(Map<String, dynamic> manifest) {
    final voices = _buildWordAudioEntriesByVoice(manifest).keys.toList()
      ..sort();
    final legacyVoiceId = (manifest['voice_id'] ?? '').toString().trim();
    if (legacyVoiceId.isNotEmpty && voices.remove(legacyVoiceId)) {
      voices.insert(0, legacyVoiceId);
    }
    return voices;
  }

  static Map<String, List<String>> _buildWordAudioEntriesByVoice(
      Map<String, dynamic> manifest) {
    final result = <String, List<String>>{};
    final voices = manifest['voices'];
    if (voices is Map<String, dynamic>) {
      for (final entry in voices.entries) {
        final voiceId = entry.key.trim();
        if (voiceId.isEmpty) {
          continue;
        }
        final payload = entry.value;
        final items = payload is Map<String, dynamic>
            ? payload['items'] as List<dynamic>? ?? const []
            : payload is List<dynamic>
                ? payload
                : const [];
        final words = items
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (words.isNotEmpty) {
          result[voiceId] = words;
        }
      }
    }
    final legacyVoiceId = (manifest['voice_id'] ?? '').toString().trim();
    if (legacyVoiceId.isNotEmpty && !result.containsKey(legacyVoiceId)) {
      final words = (manifest['items'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (words.isNotEmpty) {
        result[legacyVoiceId] = words;
      }
    }
    return result;
  }

  static Map<String, DetailSheetPayload> _buildDetailByWordId(
    Map<String, dynamic> manifest,
    Map<String, dynamic> dictionaryManifest,
    Map<String, dynamic> readerPayload,
  ) {
    final result = <String, DetailSheetPayload>{};
    manifest.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = DetailSheetPayload.fromJson(value);
      }
    });
    final dictionaryEntries =
        dictionaryManifest['entries'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    final paragraphs =
        (readerPayload['paragraphs'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
    for (final paragraph in paragraphs) {
      final sourceText = paragraph['source_text'] as String? ?? '';
      final words = (paragraph['words'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final word in words) {
        final wordId = word['id'] as String? ?? '';
        if (wordId.isEmpty || result.containsKey(wordId)) {
          continue;
        }
        final lemma =
            ((word['lemma'] as String?) ?? (word['text'] as String?) ?? '')
                .trim()
                .toLowerCase();
        final pos = (word['pos'] as String? ?? '').trim().toUpperCase();
        final dictionaryKey = '$lemma|$pos';
        final dictionaryEntry = dictionaryEntries[dictionaryKey];
        if (dictionaryEntry is! Map<String, dynamic>) {
          continue;
        }
        result[wordId] = DetailSheetPayload.fromJson({
          'word_id': wordId,
          'tap_unit_id': word['tap_unit_id'] as String? ?? wordId,
          'sheet_source_text': (word['source_unit_text'] as String?) ??
              (word['text'] as String?) ??
              '',
          'sheet_translation_text': '',
          'example_source_text':
              word['segment_source_text'] as String? ?? sourceText,
          'example_translation_text': '',
          'source_first': null,
          'dictionary_entry': dictionaryEntry,
          'units': [
            {
              'unit_id': word['lexical_unit_id'] as String? ?? wordId,
              'source_text': word['text'] as String? ?? '',
              'translation': '',
              'grammar_hint': word['grammar_hint'] as String? ?? '',
              'morph_label': word['morph_label'] as String? ?? '',
              'is_primary': true,
              'is_grammar': false,
            }
          ],
        });
      }
    }
    return result;
  }
}
