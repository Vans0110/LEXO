import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'mobile_package_models.dart';
import 'mobile_package_reader_language.dart';

Map<String, dynamic> _normalizeWordPayload(Map<String, dynamic> rawWord) {
  final word = <String, dynamic>{...rawWord};
  final sourceFirstFocus = word['source_first_focus_text'] as String? ?? '';
  final sourceFirstLeft = word['source_first_left_text'] as String? ?? '';
  final sourceFirstRight = word['source_first_right_text'] as String? ?? '';
  final unitFocus = word['unit_translation_focus_text'] as String? ?? '';
  final unitSpan = word['unit_translation_span_text'] as String? ?? '';
  final unitLeft = word['unit_translation_left_text'] as String? ?? '';
  final unitRight = word['unit_translation_right_text'] as String? ?? '';
  final legacyFocus = word['translation_focus_text'] as String? ?? '';
  final legacySpan = word['translation_span_text'] as String? ?? '';
  final legacyLeft = word['translation_left_text'] as String? ?? '';
  final legacyRight = word['translation_right_text'] as String? ?? '';
  word['effective_translation_text'] =
      (word['effective_translation_text'] as String?)?.isNotEmpty == true
          ? word['effective_translation_text']
          : (sourceFirstFocus.isNotEmpty
              ? sourceFirstFocus
              : (unitFocus.isNotEmpty
                  ? unitFocus
                  : (unitSpan.isNotEmpty
                      ? unitSpan
                      : (legacyFocus.isNotEmpty ? legacyFocus : legacySpan))));
  word['effective_left_text'] =
      (word['effective_left_text'] as String?)?.isNotEmpty == true
          ? word['effective_left_text']
          : (sourceFirstLeft.isNotEmpty
              ? sourceFirstLeft
              : (unitLeft.isNotEmpty ? unitLeft : legacyLeft));
  word['effective_focus_text'] =
      (word['effective_focus_text'] as String?)?.isNotEmpty == true
          ? word['effective_focus_text']
          : (sourceFirstFocus.isNotEmpty
              ? sourceFirstFocus
              : (unitFocus.isNotEmpty
                  ? unitFocus
                  : (legacyFocus.isNotEmpty ? legacyFocus : legacySpan)));
  word['effective_right_text'] =
      (word['effective_right_text'] as String?)?.isNotEmpty == true
          ? word['effective_right_text']
          : (sourceFirstRight.isNotEmpty
              ? sourceFirstRight
              : (unitRight.isNotEmpty ? unitRight : legacyRight));
  word['effective_matched_by'] =
      (word['effective_matched_by'] as String?)?.isNotEmpty == true
          ? word['effective_matched_by']
          : (((word['source_first_unit_id'] as String?)?.isNotEmpty == true)
              ? 'source_first'
              : (unitFocus.isNotEmpty
                  ? 'legacy_unit'
                  : (legacyFocus.isNotEmpty ? 'legacy_alignment' : '')));
  word['effective_alignment_kind'] =
      (word['effective_alignment_kind'] as String?)?.isNotEmpty == true
          ? word['effective_alignment_kind']
          : (word['alignment_kind'] as String? ?? '');
  word['effective_coverage_status'] =
      (word['effective_coverage_status'] as String?)?.isNotEmpty == true
          ? word['effective_coverage_status']
          : (word['source_first_coverage_status'] as String? ?? '');
  return word;
}

Map<String, dynamic> _normalizeDetailPayload(Map<String, dynamic> rawDetail) {
  final detail = <String, dynamic>{...rawDetail};
  final units = (detail['units'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final sourceFirst = detail['source_first'] as Map<String, dynamic>? ??
      const <String, dynamic>{};
  final selectedUnit = sourceFirst['selected_unit'] as Map<String, dynamic>? ??
      const <String, dynamic>{};
  final effectiveCoverage =
      selectedUnit['effective_coverage'] as Map<String, dynamic>? ??
          selectedUnit['coverage'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
  if ((detail['sheet_translation_text'] as String? ?? '').trim().isEmpty) {
    final fallbackTranslation =
        (effectiveCoverage['target_text'] as String? ?? '').trim().isNotEmpty
            ? (effectiveCoverage['target_text'] as String? ?? '')
            : units
                .map((unit) => unit['translation'] as String? ?? '')
                .firstWhere((value) => value.trim().isNotEmpty,
                    orElse: () => '');
    detail['sheet_translation_text'] = fallbackTranslation;
  }
  return detail;
}

Map<String, dynamic> _normalizePackageJson(Map<String, dynamic> rawPackage) {
  final package = <String, dynamic>{...rawPackage};
  final meta = <String, dynamic>{
    ...(package['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{})
  };
  final readerPayload = <String, dynamic>{
    ...(package['reader_payload'] as Map<String, dynamic>? ??
        const <String, dynamic>{}),
  };
  final paragraphs = (readerPayload['paragraphs'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((paragraph) {
    final normalizedParagraph = <String, dynamic>{...paragraph};
    normalizedParagraph['words'] =
        (paragraph['words'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_normalizeWordPayload)
            .toList();
    return normalizedParagraph;
  }).toList();
  readerPayload['paragraphs'] = paragraphs;
  package['reader_payload'] = readerPayload;
  package['dictionary_manifest'] =
      package['dictionary_manifest'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
  package['dictionary_manifests'] =
      package['dictionary_manifests'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
  final detailManifest = <String, dynamic>{};
  (package['detail_manifest'] as Map<String, dynamic>? ??
          const <String, dynamic>{})
      .forEach((key, value) {
    if (value is Map<String, dynamic>) {
      detailManifest[key] = _normalizeDetailPayload(value);
    }
  });
  package['detail_manifest'] = detailManifest;
  meta['package_version'] = (meta['package_version'] as int?) ?? 2;
  package['meta'] = meta;
  return package;
}

class MobileBookPackageRepository {
  static const _libraryDirName = 'mobile_library';

  Future<Directory> _libraryDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/$_libraryDirName');
    await dir.create(recursive: true);
    return dir;
  }

  Future<LibraryPayload> listBooks() async {
    final packages = await listPackages();
    packages.sort((a, b) {
      final left = a.meta.lastOpenedAt ?? a.meta.exportedAt ?? '';
      final right = b.meta.lastOpenedAt ?? b.meta.exportedAt ?? '';
      return right.compareTo(left);
    });
    final activeBookId =
        packages.isEmpty ? null : packages.first.meta.localBookId;
    return LibraryPayload(
      activeBookId: activeBookId,
      items: [
        for (final package in packages)
          package.meta.toLibraryItem(
              isActive: package.meta.localBookId == activeBookId),
      ],
    );
  }

  Future<List<MobileBookPackage>> listPackages() async {
    final dir = await _libraryDir();
    final packages = <MobileBookPackage>[];
    for (final entity in dir.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final packageFile = File('${entity.path}/package.json');
      if (!packageFile.existsSync()) {
        continue;
      }
      final raw = _normalizePackageJson(
        jsonDecode(packageFile.readAsStringSync()) as Map<String, dynamic>,
      );
      packages.add(MobileBookPackage(raw));
    }
    return packages;
  }

  Future<MobileBookPackage> readPackage(String localBookId) async {
    final packageFile = await _packageFile(localBookId);
    if (!packageFile.existsSync()) {
      throw Exception('Local book package not found: $localBookId');
    }
    final raw = _normalizePackageJson(
      await selectReaderPayloadForSettings(_normalizePackageJson(
        jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>,
      )),
    );
    return MobileBookPackage(raw);
  }

  Future<void> savePackage(Map<String, dynamic> packageJson) async {
    final normalizedPackage = _normalizePackageJson(packageJson);
    final meta = normalizedPackage['meta'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final localBookId = meta['local_book_id'] as String? ??
        meta['desktop_book_id'] as String? ??
        '';
    if (localBookId.isEmpty) {
      throw Exception('Package does not contain local_book_id');
    }
    final bookDir = await _bookDir(localBookId);
    await bookDir.create(recursive: true);
    final packageFile = File('${bookDir.path}/package.json');
    await packageFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(normalizedPackage),
      encoding: utf8,
    );
  }

  Future<MobileBookPackage?> findByDesktopBookId(String desktopBookId) async {
    final packages = await listPackages();
    for (final package in packages) {
      if (package.meta.desktopBookId == desktopBookId) {
        return package;
      }
    }
    return null;
  }

  Future<MobileBookPackage?> findByContentHash(String contentHash) async {
    if (contentHash.trim().isEmpty) {
      return null;
    }
    final packages = await listPackages();
    for (final package in packages) {
      if (package.meta.contentHash == contentHash) {
        return package;
      }
    }
    return null;
  }

  Future<void> deletePackage(String localBookId) async {
    final libraryDir = await _libraryDir();
    final bookDir = await _bookDir(localBookId);
    if (bookDir.existsSync()) {
      await bookDir.delete(recursive: true);
    }
    for (final entity in libraryDir.listSync()) {
      if (entity is! Directory || !entity.existsSync()) {
        continue;
      }
      final packageFile = File('${entity.path}/package.json');
      if (!packageFile.existsSync()) {
        continue;
      }
      try {
        final raw =
            jsonDecode(packageFile.readAsStringSync()) as Map<String, dynamic>;
        final meta =
            raw['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        final ids = <String>{
          (meta['local_book_id'] ?? '').toString(),
          (meta['desktop_book_id'] ?? '').toString(),
        };
        if (ids.contains(localBookId)) {
          await entity.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> markBookOpened(String localBookId) async {
    final packageFile = await _packageFile(localBookId);
    if (!packageFile.existsSync()) {
      throw Exception('Local book package not found: $localBookId');
    }
    final raw =
        jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
    final meta = raw['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    meta['last_opened_at'] = DateTime.now().toUtc().toIso8601String();
    raw['meta'] = meta;
    await packageFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(raw),
      encoding: utf8,
    );
  }

  Future<void> saveReaderPosition(
      String localBookId, int paragraphIndex) async {
    final package = await readPackage(localBookId);
    final meta =
        package.rawJson['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final readerPayload =
        package.rawJson['reader_payload'] as Map<String, dynamic>? ??
            <String, dynamic>{};
    meta['current_paragraph_index'] = paragraphIndex;
    readerPayload['current_paragraph_index'] = paragraphIndex;
    package.rawJson['meta'] = meta;
    package.rawJson['reader_payload'] = readerPayload;
    await savePackage(package.rawJson);
  }

  Future<String> ensureAudioFile({
    required String localBookId,
    required String jobId,
    required int segmentIndex,
    required List<int> bytes,
  }) async {
    final audioFile = await _audioFile(localBookId, jobId, segmentIndex);
    if (!audioFile.parent.existsSync()) {
      await audioFile.parent.create(recursive: true);
    }
    if (!audioFile.existsSync()) {
      await audioFile.writeAsBytes(bytes, flush: true);
    }
    return audioFile.path;
  }

  Future<String?> getCachedAudioPath({
    required String localBookId,
    required String jobId,
    required int segmentIndex,
  }) async {
    for (final audioFile
        in await _audioFileCandidates(localBookId, jobId, segmentIndex)) {
      if (audioFile.existsSync()) {
        return audioFile.path;
      }
    }
    return null;
  }

  Future<String> ensureWordAudioFile({
    required String localBookId,
    required String voiceId,
    required String word,
    required List<int> bytes,
  }) async {
    final audioFile = await _wordAudioFile(localBookId, voiceId, word);
    if (!audioFile.parent.existsSync()) {
      await audioFile.parent.create(recursive: true);
    }
    if (!audioFile.existsSync()) {
      await audioFile.writeAsBytes(bytes, flush: true);
    }
    return audioFile.path;
  }

  Future<String?> getCachedWordAudioPath({
    required String localBookId,
    required String voiceId,
    required String word,
  }) async {
    for (final audioFile
        in await _wordAudioFileCandidates(localBookId, voiceId, word)) {
      if (audioFile.existsSync()) {
        return audioFile.path;
      }
    }
    return null;
  }

  Future<void> deleteJobAudio({
    required String localBookId,
    required String jobId,
  }) async {
    final bookDir = await _bookDir(localBookId);
    final audioDir = Directory('${bookDir.path}/audio/$jobId');
    if (audioDir.existsSync()) {
      await audioDir.delete(recursive: true);
    }
  }

  Future<Directory> _bookDir(String localBookId) async {
    final dir = await _libraryDir();
    return Directory('${dir.path}/$localBookId');
  }

  Future<File> _packageFile(String localBookId) async {
    final bookDir = await _bookDir(localBookId);
    return File('${bookDir.path}/package.json');
  }

  Future<File> _audioFile(
      String localBookId, String jobId, int segmentIndex) async {
    final bookDir = await _bookDir(localBookId);
    return File('${bookDir.path}/audio/$jobId/$segmentIndex.wav');
  }

  Future<List<File>> _audioFileCandidates(
      String localBookId, String jobId, int segmentIndex) async {
    final bookDir = await _bookDir(localBookId);
    return [
      File('${bookDir.path}/audio/$jobId/$segmentIndex.wav'),
      File('${bookDir.path}/audio/$jobId/$segmentIndex.mp3'),
    ];
  }

  Future<File> _wordAudioFile(
      String localBookId, String voiceId, String word) async {
    final bookDir = await _bookDir(localBookId);
    final key = _wordAudioKey(word);
    return File('${bookDir.path}/word_audio/$voiceId/$key.wav');
  }

  Future<List<File>> _wordAudioFileCandidates(
      String localBookId, String voiceId, String word) async {
    final bookDir = await _bookDir(localBookId);
    final key = _wordAudioKey(word);
    return [
      File('${bookDir.path}/word_audio/$voiceId/$key.wav'),
      File('${bookDir.path}/word_audio/$voiceId/$key.mp3'),
    ];
  }

  String _wordAudioKey(String word) {
    final normalized = word.trim().toLowerCase();
    final bytes = utf8.encode(normalized);
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
