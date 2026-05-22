import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import 'nove_library_index_builder.dart';

class NoveWorkbenchBuilder {
  const NoveWorkbenchBuilder({
    required this.api,
    required this.level,
    required this.section,
    required this.chapterId,
    required this.chapterTitle,
    required this.sourcePath,
    required this.coverPath,
    required this.log,
    required this.targetLangs,
    required this.bookIdsByTargetLang,
    required this.packagesByTargetLang,
  });

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  final LexoApiClient api;
  final String level;
  final String section;
  final String chapterId;
  final String chapterTitle;
  final String sourcePath;
  final String coverPath;
  final void Function(String message) log;
  final List<String> targetLangs;
  final Map<String, String> bookIdsByTargetLang;
  final Map<String, Map<String, dynamic>> packagesByTargetLang;

  Future<Directory> exportFiles({
    required String bookId,
    required String fallbackTitle,
    bool textOnly = false,
  }) async {
    log(textOnly
        ? 'Export text files only: $bookId'
        : 'Download mobile package: $bookId');
    final package = textOnly
        ? _initialPackageFor(bookId)
        : await api.downloadMobileBookPackageChunked(bookId);
    final meta =
        package['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final title = (meta['title'] ?? fallbackTitle).toString();
    final outputDir = await _createOutputDir(bookId, title);
    final coverFileName = await _resolveCoverFileName(outputDir);
    final existingLangs = await _existingReaderLangs(outputDir);
    final existingDictionaryLangs = await _existingDictionaryLangs(outputDir);
    final languagePackages = <String, Map<String, dynamic>>{};
    final normalizedTargetLangs = _normalizedTargetLangs();
    final exportLangs = {...existingLangs, ...normalizedTargetLangs}.toList()
      ..sort();
    for (final lang in normalizedTargetLangs) {
      final langBookId = bookIdsByTargetLang[lang] ??
          (lang == normalizedTargetLangs.first ? bookId : '');
      if (langBookId.trim().isEmpty) {
        log('Skip $lang reader export: missing book_id');
        continue;
      }
      languagePackages[lang] = packagesByTargetLang[lang] ??
          (textOnly
              ? _initialPackageFor(langBookId)
              : langBookId == bookId
                  ? package
                  : await api.downloadMobileBookPackageChunked(langBookId));
    }
    await _writeJson(outputDir, 'manifest.json',
        _buildManifest(bookId, title, coverFileName, exportLangs));
    await _writeJson(
      outputDir,
      'load_manifest.json',
      _buildLoadManifest(
        bookId,
        title,
        coverFileName,
        exportLangs,
        dictionaryLangs:
            textOnly ? existingDictionaryLangs : exportLangs.toSet(),
      ),
    );
    for (final entry in languagePackages.entries) {
      await _writeJson(
          outputDir, 'reader_${entry.key}.json', _readerPayload(entry.value));
      if (!textOnly) {
        await _writeJson(outputDir, 'dictionary_${entry.key}.json',
            _dictionaryManifestForLang(entry.key, entry.value));
      }
      await _writeJson(outputDir, 'word_to_word_${entry.key}.json',
          _buildWordToWordTemplate(bookId, entry.key, entry.value));
    }
    final defaultLang = languagePackages.containsKey('ru')
        ? 'ru'
        : (languagePackages.keys.isEmpty ? 'ru' : languagePackages.keys.first);
    final defaultPackage = languagePackages[defaultLang] ?? package;
    await _writeJson(outputDir, 'reader.json', _readerPayload(defaultPackage));
    if (!textOnly) {
      await _writeJson(
          outputDir, 'detail_manifest.json', package['detail_manifest'] ?? {});
      await _writeJson(outputDir, 'tts_manifest.json',
          await _ttsManifest(outputDir, package, defaultPackage));
      await _writeJson(outputDir, 'word_audio_manifest.json',
          package['word_audio_manifest'] ?? {});
    }
    await _writeJson(outputDir, 'word_to_word.json',
        _buildWordToWordTemplate(bookId, defaultLang, defaultPackage));
    if (textOnly) {
      log('Dictionary and audio kept unchanged.');
    } else {
      await _downloadSegmentAudio(outputDir, bookId, package);
      await _downloadWordAudio(outputDir, package);
    }
    await _createAndInstallZip(outputDir);
    await NoveLibraryIndexBuilder(
      libraryDir: Directory('${Directory.current.path}/assets/library'),
      log: log,
    ).rebuild();
    return outputDir;
  }

  Map<String, dynamic> _initialPackageFor(String bookId) {
    final package = packagesByTargetLang.values.firstWhere(
      (item) {
        final meta =
            item['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        return (meta['desktop_book_id'] ?? meta['local_book_id'] ?? '')
                .toString() ==
            bookId;
      },
      orElse: () => const <String, dynamic>{},
    );
    return package;
  }

  Future<Directory> _createOutputDir(String bookId, String title) async {
    final root =
        Directory('${Directory.current.path}/workbench/output/$level/$section');
    final safeTitle = _safeName(title.isEmpty ? bookId : title);
    final reusable = await _findReusableOutputDir(root, title);
    if (reusable != null) {
      log('Reuse output dir: ${reusable.path}');
      await Directory('${reusable.path}/audio/segments')
          .create(recursive: true);
      await Directory('${reusable.path}/audio/words').create(recursive: true);
      return reusable;
    }
    final dir = Directory('${root.path}/${_safeName(bookId)}_$safeTitle');
    await dir.create(recursive: true);
    await Directory('${dir.path}/audio/segments').create(recursive: true);
    await Directory('${dir.path}/audio/words').create(recursive: true);
    return dir;
  }

  Future<void> _downloadSegmentAudio(
    Directory outputDir,
    String bookId,
    Map<String, dynamic> package,
  ) async {
    final manifest = package['tts_manifest'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final jobs = (manifest['jobs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    var count = 0;
    for (final job in jobs) {
      final jobId = (job['id'] ?? '').toString();
      if (jobId.isEmpty || (job['status'] ?? '').toString() != 'ready') {
        continue;
      }
      final segments = (job['segments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final segment in segments) {
        final segmentIndex = segment['segment_index'] as int? ?? 0;
        final file = File(
            '${outputDir.path}/audio/segments/${_safeName(jobId)}_$segmentIndex.mp3');
        if (file.existsSync()) {
          continue;
        }
        final bytes = await api.downloadTtsAudio(
          bookId: bookId,
          jobId: jobId,
          segmentIndex: segmentIndex,
        );
        await file.writeAsBytes(bytes, flush: true);
        count += 1;
      }
    }
    log('Segment audio exported: $count files');
  }

  Future<void> _downloadWordAudio(
      Directory outputDir, Map<String, dynamic> package) async {
    final manifest = package['word_audio_manifest'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final voiceId = (manifest['voice_id'] ?? '').toString();
    final items = (manifest['items'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (voiceId.isEmpty || items.isEmpty) {
      log('Word audio skipped: empty manifest');
      return;
    }
    var count = 0;
    for (final word in items) {
      final file = File('${outputDir.path}/audio/words/${_safeName(word)}.mp3');
      if (file.existsSync()) {
        continue;
      }
      final bytes = await api.downloadWordAudio(word, voiceId: voiceId);
      await file.writeAsBytes(bytes, flush: true);
      count += 1;
    }
    log('Word audio exported: $count files');
  }

  Future<String> _copyCover(Directory outputDir) async {
    if (coverPath.trim().isEmpty) {
      return '';
    }
    final source = File(coverPath);
    if (!source.existsSync()) {
      throw Exception('Cover file not found: $coverPath');
    }
    final extension = _coverExtension(source.path);
    if (extension.isEmpty) {
      throw Exception('Cover must be JPG or PNG.');
    }
    final targetName = 'cover$extension';
    await source.copy('${outputDir.path}/$targetName');
    log('Cover exported: $targetName');
    return targetName;
  }

  Future<String> _resolveCoverFileName(Directory outputDir) async {
    if (coverPath.trim().isNotEmpty) {
      return _copyCover(outputDir);
    }
    return _existingCoverFileName(outputDir);
  }

  Map<String, dynamic> _buildManifest(String bookId, String title,
      String coverFileName, Iterable<String> availableTargetLangs) {
    final langs = availableTargetLangs.toList()..sort();
    return {
      'version': 1,
      'book_id': bookId,
      'title': title,
      'level': level,
      'section': section,
      if (chapterId.isNotEmpty) 'chapter_id': chapterId,
      if (chapterTitle.isNotEmpty) 'chapter_title': chapterTitle,
      if (coverFileName.isNotEmpty) 'cover': coverFileName,
      'source_lang': 'en',
      'target_lang':
          langs.contains('ru') ? 'ru' : (langs.isEmpty ? 'ru' : langs.first),
      'available_target_langs': langs,
      'source_path': sourcePath,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _buildLoadManifest(
    String bookId,
    String title,
    String coverFileName,
    Iterable<String> availableTargetLangs, {
    Set<String>? dictionaryLangs,
  }) {
    final langs = availableTargetLangs.toList()..sort();
    final dictionaries = (dictionaryLangs ?? langs.toSet()).toList()..sort();
    return {
      'version': 1,
      'book_id': bookId,
      'title': title,
      'level': level,
      'section': section,
      if (chapterId.isNotEmpty) 'chapter_id': chapterId,
      if (chapterTitle.isNotEmpty) 'chapter_title': chapterTitle,
      if (coverFileName.isNotEmpty) 'cover': coverFileName,
      'files': {
        'reader': 'reader.json',
        'readers': {
          for (final lang in langs) lang: 'reader_$lang.json',
        },
        'dictionaries': {
          for (final lang in dictionaries) lang: 'dictionary_$lang.json',
        },
        'detail_manifest': 'detail_manifest.json',
        'word_to_word': 'word_to_word.json',
        'word_to_word_by_lang': {
          for (final lang in langs) lang: 'word_to_word_$lang.json',
        },
        'tts': 'tts_manifest.json',
        'word_audio': 'word_audio_manifest.json',
      },
      'audio': {
        'segments': 'audio/segments',
        'words': 'audio/words',
      },
    };
  }

  Map<String, dynamic> _buildWordToWordTemplate(
      String bookId, String targetLang, Map<String, dynamic> package) {
    final reader = package['reader_payload'] as Map<String, dynamic>? ??
        package['reader'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final paragraphs = (reader['paragraphs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final entries = <Map<String, dynamic>>[];
    for (final paragraph in paragraphs) {
      final paragraphIndex = paragraph['index'] as int? ?? 0;
      final words = (paragraph['words'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final word in words) {
        final wordId = (word['id'] ?? '').toString();
        final text = (word['text'] ?? '').toString();
        if (wordId.isEmpty || text.trim().isEmpty) {
          continue;
        }
        entries.add({
          'word_id': wordId,
          'segment_id': word['segment_id'] ?? 'p$paragraphIndex',
          'surface': text,
          'lemma': word['lemma'] ?? text.toLowerCase(),
          'pos': word['pos'] ?? '',
          'translation': '',
          'note': '',
        });
      }
    }
    return {
      'version': 1,
      'book_id': bookId,
      'source_lang': 'en',
      'target_lang': targetLang,
      'entries': entries,
      'phrases': [],
    };
  }

  Map<String, dynamic> _dictionaryManifestForLang(
      String targetLang, Map<String, dynamic> package) {
    final manifests =
        package['dictionary_manifests'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    final selected = manifests[targetLang];
    if (selected is Map<String, dynamic>) {
      return selected;
    }
    return package['dictionary_manifest'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
  }

  Map<String, dynamic> _readerPayload(Map<String, dynamic> package) {
    return package['reader_payload'] as Map<String, dynamic>? ??
        package['reader'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _ttsManifest(
    Directory outputDir,
    Map<String, dynamic> package,
    Map<String, dynamic> defaultPackage,
  ) async {
    final incoming = package['tts_manifest'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    if (_hasTtsJobs(incoming)) {
      return incoming;
    }
    final existingFile = File('${outputDir.path}/tts_manifest.json');
    if (existingFile.existsSync()) {
      try {
        final existing = jsonDecode(await existingFile.readAsString())
            as Map<String, dynamic>;
        if (_hasTtsJobs(existing)) {
          log('Keep existing TTS manifest: package has no jobs.');
          return existing;
        }
      } catch (_) {
        // Fall through to manifest repair.
      }
    }
    return _rebuildTtsManifestFromAudio(
      outputDir,
      incoming,
      _readerPayload(defaultPackage),
    );
  }

  bool _hasTtsJobs(Map<String, dynamic> manifest) {
    final jobs = manifest['jobs'] as List<dynamic>? ?? const [];
    return jobs.isNotEmpty;
  }

  Map<String, dynamic> _rebuildTtsManifestFromAudio(
    Directory outputDir,
    Map<String, dynamic> baseManifest,
    Map<String, dynamic> reader,
  ) {
    final audioDir = Directory('${outputDir.path}/audio/segments');
    if (!audioDir.existsSync()) {
      return baseManifest;
    }
    final sourceByIndex = <int, ({int paragraphIndex, String sourceText})>{};
    final paragraphs =
        (reader['paragraphs'] as List<dynamic>? ?? const []).whereType<Map>();
    for (final paragraph in paragraphs) {
      final paragraphIndex = paragraph['index'] as int? ?? 0;
      final segments = (paragraph['segments_v2'] as List<dynamic>? ?? const [])
          .whereType<Map>();
      for (final segment in segments) {
        final index = segment['order_index'] as int? ?? sourceByIndex.length;
        sourceByIndex[index] = (
          paragraphIndex: paragraphIndex,
          sourceText: (segment['source_text'] ?? '').toString(),
        );
      }
    }
    final groups = <String, List<File>>{};
    for (final entity in audioDir.listSync()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.mp3')) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final stem = dot <= 0 ? name : name.substring(0, dot);
      final splitAt = stem.lastIndexOf('_');
      if (splitAt <= 0) {
        continue;
      }
      final jobId = stem.substring(0, splitAt);
      groups.putIfAbsent(jobId, () => <File>[]).add(entity);
    }
    if (groups.isEmpty) {
      return baseManifest;
    }
    final profiles = baseManifest['profiles'] as List<dynamic>? ?? const [];
    final levels = baseManifest['levels'] as List<dynamic>? ?? const [];
    final voiceId = profiles.whereType<Map>().isEmpty
        ? 'af_heart'
        : (profiles.whereType<Map>().first['voice_id'] ?? 'af_heart')
            .toString();
    final sortedGroups = groups.entries.toList()
      ..sort((left, right) {
        final leftTime = left.value
            .map((file) => file.lastModifiedSync())
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final rightTime = right.value
            .map((file) => file.lastModifiedSync())
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return rightTime.compareTo(leftTime);
      });
    final jobs = <Map<String, dynamic>>[];
    for (var i = 0; i < sortedGroups.length && i < levels.length; i += 1) {
      final level = levels[i] as Map? ?? const {};
      final files = sortedGroups[i].value;
      final segmentIndexes = files.map((file) {
        final stem = file.uri.pathSegments.last.split('.').first;
        return int.tryParse(stem.substring(stem.lastIndexOf('_') + 1)) ?? 0;
      }).toList()
        ..sort();
      jobs.add({
        'id': sortedGroups[i].key,
        'level_id': level['id'] ?? i + 1,
        'level_name': level['name'] ?? 'Audio',
        'target_wpm': 0,
        'audio_variant': level['audio_variant'] ?? 'base',
        'native_rate': level['native_rate'] ?? 0.89,
        'rate':
            level['effective_playback_speed'] ?? level['playback_speed'] ?? 1.0,
        'pause_scale': 1.0,
        'voice_id': voiceId,
        'status': 'ready',
        'playback_state': 'idle',
        'current_segment_index': 0,
        'total_segments': segmentIndexes.length,
        'ready_segments': segmentIndexes.length,
        'generation_progress': 1.0,
        'current_segment_number': 1,
        'playback_progress': 0.0,
        'segments': [
          for (final index in segmentIndexes)
            {
              'segment_index': index,
              'paragraph_index': sourceByIndex[index]?.paragraphIndex ?? 0,
              'source_text': sourceByIndex[index]?.sourceText ?? '',
              'audio_path': '',
              'duration_ms': 0,
              'pause_after_ms': 0,
              'status': 'ready',
            },
        ],
      });
    }
    log('Rebuilt TTS manifest from existing audio: ${jobs.length} jobs.');
    return {
      ...baseManifest,
      'jobs': jobs,
    };
  }

  List<String> _normalizedTargetLangs() {
    final langs = targetLangs
        .map((lang) => lang.trim().toLowerCase())
        .where((lang) => lang == 'ru' || lang == 'uk')
        .toSet()
        .toList();
    langs.sort();
    return langs.isEmpty ? const ['ru'] : langs;
  }

  Future<Directory?> _findReusableOutputDir(
      Directory root, String title) async {
    if (!root.existsSync()) {
      return null;
    }
    final normalizedTitle = title.trim();
    for (final entity in root.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final manifestFile = File('${entity.path}/manifest.json');
      if (!manifestFile.existsSync()) {
        continue;
      }
      try {
        final manifest = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        if ((manifest['title'] ?? '').toString().trim() != normalizedTitle) {
          continue;
        }
        if ((manifest['level'] ?? '').toString() != level ||
            (manifest['section'] ?? '').toString() != section) {
          continue;
        }
        if ((manifest['chapter_id'] ?? '').toString() != chapterId) {
          continue;
        }
        return entity;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> _writeJson(Directory dir, String name, Object value) async {
    final file = File('${dir.path}/$name');
    await file.writeAsString(_jsonEncoder.convert(value),
        encoding: utf8, flush: true);
  }

  Future<Set<String>> _existingReaderLangs(Directory outputDir) async {
    final langs = <String>{};
    if (!outputDir.existsSync()) {
      return langs;
    }
    for (final entity in outputDir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^reader_([a-z]{2})\.json$').firstMatch(name);
      if (match != null) {
        langs.add(match.group(1)!);
      }
    }
    return langs;
  }

  Future<Set<String>> _existingDictionaryLangs(Directory outputDir) async {
    final langs = <String>{};
    if (!outputDir.existsSync()) {
      return langs;
    }
    for (final entity in outputDir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^dictionary_([a-z]{2})\.json$').firstMatch(name);
      if (match != null) {
        langs.add(match.group(1)!);
      }
    }
    return langs;
  }

  Future<String> _existingCoverFileName(Directory outputDir) async {
    for (final name in const ['cover.png', 'cover.jpg', 'cover.jpeg']) {
      if (File('${outputDir.path}/$name').existsSync()) {
        return name;
      }
    }
    return '';
  }

  Future<void> _createAndInstallZip(Directory outputDir) async {
    final zipName =
        '${outputDir.uri.pathSegments.where((segment) => segment.isNotEmpty).last}.zip';
    final outputZip = File('${outputDir.parent.path}/$zipName');
    if (outputZip.existsSync()) {
      await outputZip.delete();
    }
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r'Compress-Archive -Path (Join-Path $env:NOVE_ZIP_SOURCE "*") -DestinationPath $env:NOVE_ZIP_DESTINATION -Force',
      ],
      environment: {
        'NOVE_ZIP_SOURCE': outputDir.path,
        'NOVE_ZIP_DESTINATION': outputZip.path,
      },
    );
    if (result.exitCode != 0) {
      throw Exception('Zip build failed: ${result.stderr}'.trim());
    }
    log('Zip created: ${outputZip.path}');

    final installDir = Directory(
        '${Directory.current.path}/assets/library/$level/$section/books_zip');
    await installDir.create(recursive: true);
    final installedZip = File('${installDir.path}/$zipName');
    if (installedZip.existsSync()) {
      await installedZip.delete();
    }
    await outputZip.copy(installedZip.path);
    log('Zip installed: ${installedZip.path}');
  }

  String _safeName(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return normalized
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _coverExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return '.jpg';
    }
    if (lower.endsWith('.png')) {
      return '.png';
    }
    return '';
  }
}
