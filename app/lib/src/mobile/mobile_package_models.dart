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
      exportedAt: json['exported_at'] as String?,
      lastOpenedAt: json['last_opened_at'] as String?,
    );
  }

  LibraryBookItem toLibraryItem({required bool isActive}) {
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
    );
  }
}

class MobileBookPackage {
  MobileBookPackage(this.rawJson)
      : meta = MobileBookPackageMeta.fromJson(
          (rawJson['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
        ),
        readerPayload = ReaderPayload.fromJson(
          (rawJson['reader_payload'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
        ),
        profiles = ((rawJson['tts_manifest'] as Map<String, dynamic>? ?? const <String, dynamic>{})['profiles']
                    as List<dynamic>? ??
                const [])
            .cast<Map<String, dynamic>>()
            .map(TtsProfile.fromJson)
            .toList(),
        levels = ((rawJson['tts_manifest'] as Map<String, dynamic>? ?? const <String, dynamic>{})['levels']
                    as List<dynamic>? ??
                const [])
            .cast<Map<String, dynamic>>()
            .map(TtsLevel.fromJson)
            .toList(),
        ttsState = _buildTtsState(
          (rawJson['tts_manifest'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
        ),
        segmentsByJobId = _buildSegmentsByJobId(
          (rawJson['tts_manifest'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
        ),
        detailByWordId = _buildDetailByWordId(
          rawJson['detail_manifest'] as Map<String, dynamic>? ?? const <String, dynamic>{},
        );

  final Map<String, dynamic> rawJson;
  final MobileBookPackageMeta meta;
  final ReaderPayload readerPayload;
  final List<TtsProfile> profiles;
  final List<TtsLevel> levels;
  final TtsState ttsState;
  final Map<String, List<TtsSegmentItem>> segmentsByJobId;
  final Map<String, DetailSheetPayload> detailByWordId;

  List<TtsSegmentItem> segmentsForJob(String jobId) {
    return segmentsByJobId[jobId] ?? const <TtsSegmentItem>[];
  }

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
    final activeSegments = ((activeJobJson?['segments'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TtsSegmentItem.fromJson)
        .toList();
    return TtsState(
      jobs: jobs,
      activeJob: activeJobJson != null ? TtsJobItem.fromJson(activeJobJson) : null,
      activeSegments: activeSegments,
    );
  }

  static Map<String, List<TtsSegmentItem>> _buildSegmentsByJobId(Map<String, dynamic> manifest) {
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

  static Map<String, DetailSheetPayload> _buildDetailByWordId(Map<String, dynamic> manifest) {
    final result = <String, DetailSheetPayload>{};
    manifest.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = DetailSheetPayload.fromJson(value);
      }
    });
    return result;
  }
}
