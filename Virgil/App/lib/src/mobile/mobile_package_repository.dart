import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'mobile_package_models.dart';
import 'mobile_package_reader_language.dart';

List<String> _targetTokens(String text) {
  return RegExp(r'[\p{L}\p{N}]+', unicode: true)
      .allMatches(text)
      .map((match) => match.group(0)?.trim() ?? '')
      .where((token) => token.isNotEmpty)
      .toList();
}

int _findTokenStart(List<String> targetTokens, String translation) {
  final wanted =
      _targetTokens(translation).map((token) => token.toLowerCase()).toList();
  if (wanted.isEmpty || wanted.length > targetTokens.length) {
    return -1;
  }
  final haystack = targetTokens.map((token) => token.toLowerCase()).toList();
  for (var index = 0; index <= haystack.length - wanted.length; index++) {
    var matches = true;
    for (var offset = 0; offset < wanted.length; offset++) {
      if (haystack[index + offset] != wanted[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return index;
    }
  }
  if (wanted.length != 1) {
    return -1;
  }
  final source = wanted.single;
  var bestIndex = -1;
  var bestScore = 0.0;
  for (var index = 0; index < haystack.length; index++) {
    final candidate = haystack[index];
    final shortest =
        source.length < candidate.length ? source.length : candidate.length;
    var commonPrefix = 0;
    while (commonPrefix < shortest &&
        source.codeUnitAt(commonPrefix) == candidate.codeUnitAt(commonPrefix)) {
      commonPrefix += 1;
    }
    if (commonPrefix < 3) {
      continue;
    }
    final score = commonPrefix / shortest;
    if (score >= 0.6 && score > bestScore) {
      bestIndex = index;
      bestScore = score;
    }
  }
  return bestIndex;
}

Map<String, Map<String, dynamic>> _wordAlignmentById(
    Map<String, dynamic> package) {
  final wordToWord = package['word_to_word'] as Map<String, dynamic>? ??
      const <String, dynamic>{};
  final result = <String, Map<String, dynamic>>{};
  for (final entry
      in (wordToWord['entries'] as List<dynamic>? ?? const <dynamic>[])) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final wordId = (entry['word_id'] ?? '').toString().trim();
    if (wordId.isEmpty) {
      continue;
    }
    result[wordId] = entry;
  }
  return result;
}

List<Map<String, dynamic>> _phraseAlignments(Map<String, dynamic> package) {
  final wordToWord = package['word_to_word'] as Map<String, dynamic>? ??
      const <String, dynamic>{};
  return (wordToWord['phrases'] as List<dynamic>? ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .where((entry) =>
          (entry['segment_id'] ?? '').toString().trim().isNotEmpty &&
          (entry['source'] ?? '').toString().trim().isNotEmpty &&
          (entry['translation'] ?? '').toString().trim().isNotEmpty)
      .toList();
}

List<String> _sourceTokens(String text) {
  return RegExp(r'[a-zA-Z0-9]+')
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)?.trim() ?? '')
      .where((token) => token.isNotEmpty)
      .toList();
}

bool _phraseTokenMatches(String phraseToken, Map<String, dynamic> word) {
  final surface = (word['text'] ?? '').toString().trim().toLowerCase();
  final lemma = (word['lemma'] ?? '').toString().trim().toLowerCase();
  return phraseToken == surface || phraseToken == lemma;
}

List<Map<String, dynamic>> _findPhraseWords(
  List<Map<String, dynamic>> words,
  String segmentId,
  String phraseSource,
) {
  final phraseTokens = _sourceTokens(phraseSource);
  if (phraseTokens.isEmpty) {
    return const <Map<String, dynamic>>[];
  }
  final segmentWords = words
      .where((word) => (word['segment_id'] ?? '').toString() == segmentId)
      .toList()
    ..sort((left, right) => ((left['order_index'] as int?) ?? 0)
        .compareTo((right['order_index'] as int?) ?? 0));
  if (phraseTokens.length > segmentWords.length) {
    return const <Map<String, dynamic>>[];
  }
  for (var index = 0;
      index <= segmentWords.length - phraseTokens.length;
      index++) {
    var matches = true;
    for (var offset = 0; offset < phraseTokens.length; offset++) {
      if (!_phraseTokenMatches(
          phraseTokens[offset], segmentWords[index + offset])) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return segmentWords.sublist(index, index + phraseTokens.length);
    }
  }
  return const <Map<String, dynamic>>[];
}

bool _isLexicalHeadPos(Object? value) => const {
      'ADJ',
      'NOUN',
      'PROPN',
      'VERB',
    }.contains(value?.toString().trim().toUpperCase());

void _applyPosGrammarGroups(
  List<Map<String, dynamic>> words,
  Map<String, List<String>> tokensBySegmentId,
) {
  final segmentIds = words
      .map((word) => (word['segment_id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final segmentId in segmentIds) {
    final segmentWords = words
        .where((word) => (word['segment_id'] ?? '').toString() == segmentId)
        .toList()
      ..sort((left, right) => ((left['order_index_in_segment'] as int?) ?? 0)
          .compareTo((right['order_index_in_segment'] as int?) ?? 0));
    for (var index = 0; index < segmentWords.length; index++) {
      final first = segmentWords[index];
      if ((first['effective_alignment_kind'] ?? '').toString() == 'phrase') {
        continue;
      }
      final firstPos = (first['pos'] ?? '').toString().trim().toUpperCase();
      if (!const {'ADP', 'DET', 'AUX', 'PART'}.contains(firstPos)) {
        continue;
      }
      final group = <Map<String, dynamic>>[first];
      var headFound = false;
      var hasDeterminer = firstPos == 'DET';
      for (var nextIndex = index + 1;
          nextIndex < segmentWords.length;
          nextIndex++) {
        final next = segmentWords[nextIndex];
        if ((next['effective_alignment_kind'] ?? '').toString() == 'phrase') {
          break;
        }
        final pos = (next['pos'] ?? '').toString().trim().toUpperCase();
        final allowedModifier = const {
          'ADJ',
          'ADV',
          'DET',
          'NUM',
          'PART',
        }.contains(pos);
        if (pos == 'DET') {
          hasDeterminer = true;
          group.add(next);
          continue;
        }
        if (pos == 'ADJ' && hasDeterminer && firstPos != 'AUX') {
          group.add(next);
          continue;
        }
        if (_isLexicalHeadPos(pos)) {
          group.add(next);
          headFound = true;
          break;
        }
        if (!allowedModifier) {
          break;
        }
        group.add(next);
      }
      if (!headFound || group.length < 2) {
        continue;
      }
      final source = group
          .map((word) => (word['text'] ?? '').toString().trim())
          .where((text) => text.isNotEmpty)
          .join(' ');
      if (source.isEmpty) {
        continue;
      }
      final lexicalSpans = group
          .where((word) => !_isFunctionWordPos(word['pos']))
          .map((word) => (
                (word['target_start_index'] as int?) ?? -1,
                (word['target_end_index'] as int?) ?? -1,
              ))
          .where((span) => span.$1 >= 0 && span.$2 >= span.$1)
          .toList();
      final start = lexicalSpans.isEmpty
          ? -1
          : lexicalSpans.map((span) => span.$1).reduce((a, b) => a < b ? a : b);
      final end = lexicalSpans.isEmpty
          ? -1
          : lexicalSpans.map((span) => span.$2).reduce((a, b) => a > b ? a : b);
      final groupId =
          'grammar_${segmentId}_${source.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}';
      final targetTokens = tokensBySegmentId[segmentId] ?? const <String>[];
      final target = start >= 0 && end < targetTokens.length
          ? targetTokens.sublist(start, end + 1).join(' ')
          : '';
      for (final word in group) {
        word['tap_unit_id'] = groupId;
        word['source_unit_text'] = source;
        word['effective_alignment_kind'] = 'grammar_group';
        word['effective_matched_by'] = 'pos_grammar_group';
        word['grammar_group_translation'] = target;
        if (target.isNotEmpty) {
          word['effective_translation_text'] = target;
          word['effective_focus_text'] = target;
        }
        if (start >= 0 && end >= start) {
          word['target_start_index'] = start;
          word['target_end_index'] = end;
        }
      }
      index += group.length - 1;
    }
  }
}

Map<String, dynamic> _applyDictionaryAlignmentToParagraph(
  Map<String, dynamic> paragraph,
  Map<String, Map<String, dynamic>> alignmentByWordId,
  List<Map<String, dynamic>> phraseAlignments,
) {
  final normalizedParagraph = <String, dynamic>{...paragraph};
  final tokensBySegmentId = <String, List<String>>{};
  final segments = (paragraph['segments_v2'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((segment) {
    final next = <String, dynamic>{...segment};
    final segmentId = (next['id'] ?? '').toString();
    final targetText = (next['target_text'] ?? '').toString();
    if (segmentId.isNotEmpty) {
      final tokens = _targetTokens(targetText);
      tokensBySegmentId[segmentId] = tokens;
      final currentAlignment =
          next['segment_alignment'] as Map<String, dynamic>? ??
              const <String, dynamic>{};
      if ((currentAlignment['target_tokens'] as List<dynamic>? ?? const [])
          .isEmpty) {
        next['segment_alignment'] = {
          ...currentAlignment,
          'target_tokens': tokens,
          'alignment_source': 'dictionary_alignment',
        };
      }
    }
    return next;
  }).toList();
  normalizedParagraph['segments_v2'] = segments;

  final words = (paragraph['words'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((word) {
    final next = <String, dynamic>{...word};
    for (final legacyKey in const {
      'source_first_focus_text',
      'source_first_left_text',
      'source_first_right_text',
      'unit_translation_focus_text',
      'unit_translation_span_text',
      'unit_translation_left_text',
      'unit_translation_right_text',
    }) {
      next.remove(legacyKey);
    }
    final wordId = (next['id'] ?? '').toString();
    if (_isFunctionWordPos(next['pos'])) {
      next['tap_unit_id'] = '';
    }
    final alignment = alignmentByWordId[wordId];
    if (alignment == null) {
      return next;
    }
    final translation = (alignment['translation'] ?? '').toString().trim();
    if (translation.isEmpty) {
      return next;
    }
    final segmentId =
        (next['segment_id'] ?? alignment['segment_id'] ?? '').toString();
    final tokens = tokensBySegmentId[segmentId] ?? const <String>[];
    final start = _findTokenStart(tokens, translation);
    next['translation_focus_text'] = translation;
    next['translation_span_text'] = translation;
    next['unit_translation_focus_text'] = translation;
    next['unit_translation_span_text'] = translation;
    next['effective_translation_text'] = translation;
    next['effective_focus_text'] = translation;
    next['effective_matched_by'] = 'dictionary_alignment';
    next['effective_alignment_kind'] = 'word';
    next['effective_coverage_status'] = 'dictionary';
    if (start >= 0) {
      final length = _targetTokens(translation).length;
      next['target_start_index'] = start;
      next['target_end_index'] = start + length - 1;
    }
    return next;
  }).toList();

  for (final phrase in phraseAlignments) {
    final segmentId = (phrase['segment_id'] ?? '').toString();
    final source = (phrase['source'] ?? '').toString().trim();
    final translation = (phrase['translation'] ?? '').toString().trim();
    if (segmentId.isEmpty || source.isEmpty || translation.isEmpty) {
      continue;
    }
    final phraseWords = _findPhraseWords(words, segmentId, source);
    if (phraseWords.isEmpty) {
      continue;
    }
    final tokens = tokensBySegmentId[segmentId] ?? const <String>[];
    final start = _findTokenStart(tokens, translation);
    final length = _targetTokens(translation).length;
    final phraseId =
        'phrase_${segmentId}_${source.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}';
    for (final word in phraseWords) {
      final attachedPhrases =
          (word['phrase_alignments'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .toList();
      if (!attachedPhrases.any((item) =>
          item['source'] == source &&
          item['translation'] == translation &&
          item['segment_id'] == segmentId)) {
        attachedPhrases.add({
          'source': source,
          'translation': translation,
          'segment_id': segmentId,
        });
      }
      word['phrase_alignments'] = attachedPhrases;
      word['tap_unit_id'] = phraseId;
      word['source_unit_text'] = source;
      word['translation_focus_text'] = translation;
      word['translation_span_text'] = translation;
      word['effective_translation_text'] = translation;
      word['effective_focus_text'] = translation;
      word['effective_matched_by'] = 'dictionary_phrase_alignment';
      word['effective_alignment_kind'] = 'phrase';
      word['effective_coverage_status'] = 'dictionary';
      if (start >= 0 && length > 0) {
        word['target_start_index'] = start;
        word['target_end_index'] = start + length - 1;
      }
    }
  }

  _applyPosGrammarGroups(words, tokensBySegmentId);

  final tapUnitByWordId = <String, String>{};
  for (final word in words) {
    final wordId = (word['id'] ?? '').toString();
    final tapUnitId = (word['tap_unit_id'] ?? '').toString();
    if (wordId.isNotEmpty && tapUnitId.isNotEmpty) {
      tapUnitByWordId[wordId] = tapUnitId;
    }
  }
  normalizedParagraph['tokens'] =
      (paragraph['tokens'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((token) {
    final next = <String, dynamic>{...token};
    final wordId = (next['word_id'] ?? '').toString();
    final tapUnitId = tapUnitByWordId[wordId];
    if (tapUnitId != null) {
      next['tap_unit_id'] = tapUnitId;
    } else {
      next.remove('tap_unit_id');
    }
    return next;
  }).toList();
  normalizedParagraph['words'] = words;
  return normalizedParagraph;
}

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
  final alignmentByWordId = _wordAlignmentById(package);
  final phraseAlignments = _phraseAlignments(package);
  final paragraphs = (readerPayload['paragraphs'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((paragraph) {
    final alignedParagraph = _applyDictionaryAlignmentToParagraph(
      paragraph,
      alignmentByWordId,
      phraseAlignments,
    );
    alignedParagraph['words'] =
        (alignedParagraph['words'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_normalizeWordPayload)
            .toList();
    return alignedParagraph;
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

Map<String, dynamic> normalizeMobilePackageJsonForTest(
  Map<String, dynamic> rawPackage,
) =>
    _normalizePackageJson(rawPackage);
bool _isFunctionWordPos(Object? value) => const {
      'ADP',
      'AUX',
      'CCONJ',
      'DET',
      'PART',
      'SCONJ',
    }.contains(value?.toString().trim().toUpperCase());

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
            isActive: package.meta.localBookId == activeBookId,
            coverFilePath: _coverFilePath(package),
          ),
      ],
    );
  }

  String? _coverFilePath(MobileBookPackage package) {
    final coverPath = package.meta.coverPath?.trim() ?? '';
    final bookDir = package.rawJson['_book_dir']?.toString() ?? '';
    if (coverPath.isEmpty || bookDir.isEmpty) {
      return null;
    }
    final normalized = coverPath.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalized) ||
        normalized.split('/').contains('..')) {
      return null;
    }
    return '$bookDir/$normalized';
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
      raw['_book_dir'] = entity.path;
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
