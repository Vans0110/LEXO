import '../models.dart';

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
            .toList();

  final Map<String, dynamic> rawJson;
  final MobileBookPackageMeta meta;
  final ReaderPayload readerPayload;
  final List<TtsProfile> profiles;
  final List<TtsLevel> levels;
}
