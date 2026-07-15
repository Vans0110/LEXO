import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import 'virgil_library_index_builder.dart';
import 'virgil_workbench_paths.dart';

class VirgilWorkbenchBuilder {
  const VirgilWorkbenchBuilder({
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
    await _writeJson(
      outputDir,
      'manifest.json',
      _buildManifest(
        bookId,
        title,
        coverFileName,
        exportLangs,
        bookIdsByTargetLang,
      ),
    );
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
        bookIdsByTargetLang: bookIdsByTargetLang,
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
    await VirgilLibraryIndexBuilder(
      libraryDir: VirgilWorkbenchPaths.cloudLibrary,
      log: log,
    ).rebuild();
    return outputDir;
  }

  Future<Directory> refreshDictionaries({
    required String bookId,
    required String fallbackTitle,
    required Iterable<String> languages,
  }) async {
    final normalizedLangs = languages
        .map((lang) => lang.trim().toLowerCase())
        .where((lang) => lang.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (normalizedLangs.isEmpty) {
      throw Exception('No dictionary languages selected.');
    }
    log('Refresh dictionaries: $bookId (${normalizedLangs.join(', ')})');
    final outputDir = await _findExistingOutputDir(bookId, fallbackTitle);
    if (outputDir == null) {
      throw Exception('Output package not found for $fallbackTitle.');
    }
    final loadManifestFile = File('${outputDir.path}/load_manifest.json');
    final loadManifest = await _readJsonObject(loadManifestFile);
    final packageByLang = <String, Map<String, dynamic>>{};
    for (final lang in normalizedLangs) {
      final langBookId = bookIdsByTargetLang[lang] ?? bookId;
      if (langBookId.trim().isEmpty) {
        log('Skip $lang dictionary refresh: missing book_id');
        continue;
      }
      if (lang == 'ru' || lang == 'uk') {
        final result = await api.rebuildLibraryDictionary(
          bookId: langBookId,
          targetLang: lang,
        );
        final wordCount = (result['word_count'] as num?)?.toInt() ?? 0;
        final translatedWordCount =
            (result['translated_word_count'] as num?)?.toInt() ?? 0;
        final missingWordCount =
            (result['missing_word_count'] as num?)?.toInt() ?? 0;
        if (wordCount == 0 || translatedWordCount == 0) {
          throw Exception(
            'Library dictionary $lang is empty for $langBookId. '
            'No matching Global dictionary words.',
          );
        }
        log(
          'Library dictionary $lang built from Globals: '
          '$translatedWordCount/$wordCount words, '
          '$missingWordCount missing, '
          '${result['phrase_count'] ?? 0} Global phrases',
        );
      }
      packageByLang[lang] =
          await api.downloadMobileBookPackageChunked(langBookId);
    }
    for (final entry in packageByLang.entries) {
      await _writeJson(outputDir, 'dictionary_${entry.key}.json',
          _dictionaryManifestForLang(entry.key, entry.value));
      await _writeJson(outputDir, 'word_to_word_${entry.key}.json',
          _buildWordToWordTemplate(bookId, entry.key, entry.value));
    }
    await _refreshDefaultReaderFiles(outputDir);
    await _writeJson(
      outputDir,
      'load_manifest.json',
      _loadManifestWithDictionaries(loadManifest, packageByLang.keys),
    );
    await _createAndInstallZip(outputDir);
    await VirgilLibraryIndexBuilder(
      libraryDir: VirgilWorkbenchPaths.cloudLibrary,
      log: log,
    ).rebuild();
    return outputDir;
  }

  Future<Directory> refreshAudio({
    required String bookId,
    required String fallbackTitle,
  }) async {
    log('Refresh audio only: $bookId');
    final outputDir = await _findExistingOutputDir(bookId, fallbackTitle);
    if (outputDir == null) {
      throw Exception('Output package not found for $fallbackTitle.');
    }
    final package = await api.downloadMobileBookPackageChunked(bookId);
    await _writeJson(
      outputDir,
      'tts_manifest.json',
      await _ttsManifest(outputDir, package, package),
    );
    await _writeJson(
      outputDir,
      'word_audio_manifest.json',
      package['word_audio_manifest'] ?? {},
    );
    final segmentAudioDir = Directory('${outputDir.path}/audio/segments');
    if (segmentAudioDir.existsSync()) {
      await segmentAudioDir.delete(recursive: true);
    }
    await segmentAudioDir.create(recursive: true);
    await _downloadSegmentAudio(outputDir, bookId, package);
    await _downloadWordAudio(outputDir, package);
    log('Reader and dictionaries kept unchanged.');
    await _createAndInstallZip(outputDir);
    await VirgilLibraryIndexBuilder(
      libraryDir: VirgilWorkbenchPaths.cloudLibrary,
      log: log,
    ).rebuild();
    return outputDir;
  }

  Future<Directory> cleanArtifacts({
    required String bookId,
    required String fallbackTitle,
    Iterable<String> textLangs = const <String>[],
    Iterable<String> dictionaryLangs = const <String>[],
    Iterable<String> voiceIds = const <String>[],
  }) async {
    final outputDir = await _findExistingOutputDir(bookId, fallbackTitle);
    if (outputDir == null) {
      throw Exception('Output package not found for $fallbackTitle.');
    }
    final cleanTextLangs = textLangs
        .map((lang) => lang.trim().toLowerCase())
        .where((lang) => lang.isNotEmpty)
        .toSet();
    final cleanDictionaryLangs = dictionaryLangs
        .map((lang) => lang.trim().toLowerCase())
        .where((lang) => lang.isNotEmpty)
        .toSet();
    final cleanVoiceIds = voiceIds
        .map((voiceId) => voiceId.trim())
        .where((voiceId) => voiceId.isNotEmpty)
        .toSet();
    log(
      'Clean selected artifacts: $bookId '
      'text=${cleanTextLangs.join(', ')} '
      'dictionary=${cleanDictionaryLangs.join(', ')} '
      'voices=${cleanVoiceIds.join(', ')}',
    );
    final loadManifestFile = File('${outputDir.path}/load_manifest.json');
    final loadManifest = await _readJsonObject(loadManifestFile);
    final files = Map<String, dynamic>.from(
        loadManifest['files'] as Map<String, dynamic>? ??
            const <String, dynamic>{});

    for (final lang in cleanTextLangs) {
      await _deleteIfExists(File('${outputDir.path}/reader_$lang.json'));
      await _deleteIfExists(File('${outputDir.path}/word_to_word_$lang.json'));
      log('Clean reader: $lang');
    }
    if (cleanTextLangs.isNotEmpty) {
      final readers = Map<String, dynamic>.from(
          files['readers'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      final wordToWordByLang = Map<String, dynamic>.from(
          files['word_to_word_by_lang'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      for (final lang in cleanTextLangs) {
        readers.remove(lang);
        wordToWordByLang.remove(lang);
      }
      files['readers'] = readers;
      files['word_to_word_by_lang'] = wordToWordByLang;
      await _refreshDefaultReaderFiles(outputDir);
    }

    for (final lang in cleanDictionaryLangs) {
      await _deleteIfExists(File('${outputDir.path}/dictionary_$lang.json'));
      log('Clean dictionary: $lang');
    }
    if (cleanDictionaryLangs.isNotEmpty) {
      final dictionaries = Map<String, dynamic>.from(
          files['dictionaries'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      for (final lang in cleanDictionaryLangs) {
        dictionaries.remove(lang);
      }
      files['dictionaries'] = dictionaries;
    }

    if (cleanVoiceIds.isNotEmpty) {
      await _cleanLocalVoiceArtifacts(outputDir, cleanVoiceIds);
    }

    loadManifest['files'] = files;
    await _writeJson(outputDir, 'load_manifest.json', loadManifest);
    await _createAndInstallZip(outputDir);
    await VirgilLibraryIndexBuilder(
      libraryDir: VirgilWorkbenchPaths.cloudLibrary,
      log: log,
    ).rebuild();
    return outputDir;
  }

  Future<void> _deleteIfExists(File file) async {
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _refreshDefaultReaderFiles(Directory outputDir) async {
    final remainingReaders = <String, File>{};
    for (final entity in outputDir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^reader_([a-z]{2})\.json$').firstMatch(name);
      if (match != null) {
        remainingReaders[match.group(1)!] = entity;
      }
    }
    final langs = remainingReaders.keys.toList()..sort();
    if (langs.isEmpty) {
      await _deleteIfExists(File('${outputDir.path}/reader.json'));
      await _deleteIfExists(File('${outputDir.path}/word_to_word.json'));
      return;
    }
    final defaultLang = langs.contains('ru') ? 'ru' : langs.first;
    await remainingReaders[defaultLang]!.copy('${outputDir.path}/reader.json');
    final wordToWord = File('${outputDir.path}/word_to_word_$defaultLang.json');
    if (wordToWord.existsSync()) {
      await wordToWord.copy('${outputDir.path}/word_to_word.json');
    } else {
      await _deleteIfExists(File('${outputDir.path}/word_to_word.json'));
    }
  }

  Future<void> _cleanLocalVoiceArtifacts(
      Directory outputDir, Set<String> voiceIds) async {
    final ttsManifestFile = File('${outputDir.path}/tts_manifest.json');
    final ttsManifest = await _readJsonObject(ttsManifestFile);
    final jobs = (ttsManifest['jobs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final keptJobs = <Map<String, dynamic>>[];
    final removedJobIds = <String>{};
    for (final job in jobs) {
      final voiceId = (job['voice_id'] ?? '').toString();
      if (voiceIds.contains(voiceId)) {
        final jobId = (job['id'] ?? '').toString();
        if (jobId.isNotEmpty) {
          removedJobIds.add(jobId);
        }
      } else {
        keptJobs.add(job);
      }
    }
    ttsManifest['jobs'] = keptJobs;
    await _writeJson(outputDir, 'tts_manifest.json', ttsManifest);

    final segmentDir = Directory('${outputDir.path}/audio/segments');
    if (segmentDir.existsSync()) {
      for (final entity in segmentDir.listSync()) {
        if (entity is! File) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        for (final jobId in removedJobIds) {
          if (name.startsWith('${_safeName(jobId)}_')) {
            await entity.delete();
            break;
          }
        }
      }
    }

    final wordManifestFile = File('${outputDir.path}/word_audio_manifest.json');
    final wordManifest = await _readJsonObject(wordManifestFile);
    final voices = Map<String, dynamic>.from(
        wordManifest['voices'] as Map<String, dynamic>? ??
            const <String, dynamic>{});
    for (final voiceId in voiceIds) {
      voices.remove(voiceId);
      final voiceDir = Directory('${outputDir.path}/audio/words/$voiceId');
      if (voiceDir.existsSync()) {
        await voiceDir.delete(recursive: true);
      }
    }
    wordManifest['voices'] = voices;
    final voiceKeys = voices.keys.map((key) => key.toString()).toList()..sort();
    wordManifest['voice_id'] = voiceKeys.isEmpty ? '' : voiceKeys.first;
    wordManifest['items'] = voiceKeys.isEmpty
        ? const <String>[]
        : ((voices[voiceKeys.first] as Map<String, dynamic>?)?['items'] ??
            const <String>[]);
    await _writeJson(outputDir, 'word_audio_manifest.json', wordManifest);
    log('Clean voices: ${voiceIds.join(', ')}');
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
        Directory('${VirgilWorkbenchPaths.output.path}/$level/$section');
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
    final voices = _wordAudioVoicesFromManifest(manifest);
    if (voices.isEmpty) {
      log('Word audio skipped: empty manifest');
      return;
    }
    final wordsRoot = Directory('${outputDir.path}/audio/words');
    if (wordsRoot.existsSync()) {
      await wordsRoot.delete(recursive: true);
    }
    await wordsRoot.create(recursive: true);
    var count = 0;
    for (final entry in voices.entries) {
      final voiceId = entry.key;
      final voiceDir = Directory('${wordsRoot.path}/$voiceId');
      await voiceDir.create(recursive: true);
      for (final word in entry.value) {
        final file = File('${voiceDir.path}/${_safeName(word)}.mp3');
        if (file.existsSync()) {
          continue;
        }
        final bytes = await api.downloadWordAudio(word, voiceId: voiceId);
        await file.writeAsBytes(bytes, flush: true);
        count += 1;
      }
    }
    log('Word audio exported: $count files');
  }

  Map<String, List<String>> _wordAudioVoicesFromManifest(
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

  Map<String, dynamic> _buildManifest(
      String bookId,
      String title,
      String coverFileName,
      Iterable<String> availableTargetLangs,
      Map<String, String> languageBookIds) {
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
      'book_ids_by_target_lang': {
        for (final lang in langs)
          if ((languageBookIds[lang] ?? '').trim().isNotEmpty)
            lang: languageBookIds[lang],
      },
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
    Map<String, String> bookIdsByTargetLang = const {},
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
      'book_ids_by_target_lang': {
        for (final lang in langs)
          if ((bookIdsByTargetLang[lang] ?? '').trim().isNotEmpty)
            lang: bookIdsByTargetLang[lang],
      },
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
    final dictionary = _dictionaryManifestForLang(targetLang, package);
    final dictionaryEntries = dictionary['entries'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final paragraphs = (reader['paragraphs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final targetTextBySegmentId = <String, String>{
      for (final paragraph in paragraphs)
        for (final segment
            in (paragraph['segments_v2'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>())
          (segment['id'] ?? '').toString():
              (segment['target_text'] ?? '').toString(),
    };
    final entries = <Map<String, dynamic>>[];
    final claimedBySegment = <String, Set<int>>{};
    for (final paragraph in paragraphs) {
      final paragraphIndex = paragraph['index'] as int? ?? 0;
      final words = (paragraph['words'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final wordCountBySegment = <String, int>{};
      for (final word in words) {
        final segmentId = (word['segment_id'] ?? 'p$paragraphIndex').toString();
        wordCountBySegment[segmentId] =
            (wordCountBySegment[segmentId] ?? 0) + 1;
      }
      for (final word in words) {
        final wordId = (word['id'] ?? '').toString();
        final text = (word['text'] ?? '').toString();
        if (wordId.isEmpty || text.trim().isEmpty) {
          continue;
        }
        final lemma = (word['lemma'] ?? text.toLowerCase()).toString();
        final pos = (word['pos'] ?? '').toString();
        final dictionaryEntry = dictionaryEntries[_dictionaryKey(lemma, pos)];
        final translations = dictionaryEntry is Map<String, dynamic>
            ? _stringList(dictionaryEntry['translations'])
            : const <String>[];
        final segmentId = (word['segment_id'] ?? 'p$paragraphIndex').toString();
        final selection = _selectContextualSpan(
          translations,
          targetTextBySegmentId[segmentId] ?? '',
          sourceIndex: word['order_index_in_segment'] as int? ?? 0,
          sourceCount: wordCountBySegment[segmentId] ?? 1,
          claimed: claimedBySegment.putIfAbsent(segmentId, () => <int>{}),
        );
        final selectedTranslation = selection['translation'] as String? ?? '';
        final targetStart = selection['start'] as int? ?? -1;
        final targetEnd = selection['end'] as int? ?? -1;
        if (targetStart >= 0) {
          claimedBySegment[segmentId]!.addAll(
            List<int>.generate(
              targetEnd - targetStart + 1,
              (index) => targetStart + index,
            ),
          );
        }
        entries.add({
          'word_id': wordId,
          'segment_id': segmentId,
          'surface': text,
          'lemma': lemma,
          'pos': pos,
          'translation': selectedTranslation,
          'translations': translations,
          'dictionary_key': _dictionaryKey(lemma, pos),
          'target_start_index': targetStart,
          'target_end_index': targetEnd,
          'source': dictionary['source'] ?? '',
          'note': translations.isEmpty ? 'missing_global_dictionary_entry' : '',
        });
      }
    }
    return {
      'version': 1,
      'book_id': bookId,
      'source_lang': 'en',
      'target_lang': targetLang,
      'source': dictionary['source'] ?? '',
      'entries': entries,
      'phrases': _buildPhraseAlignment(reader, dictionary),
    };
  }

  List<Map<String, dynamic>> _buildPhraseAlignment(
    Map<String, dynamic> reader,
    Map<String, dynamic> dictionary,
  ) {
    final phraseRecords = dictionary['phrases'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    if (phraseRecords.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    final paragraphs = (reader['paragraphs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final paragraph in paragraphs) {
      final paragraphIndex = paragraph['index'] as int? ?? 0;
      final segments = (paragraph['segments_v2'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      for (final segment in segments) {
        final segmentId = (segment['id'] ?? 'p$paragraphIndex').toString();
        final sourceText = (segment['source_text'] ?? '').toString();
        final targetText = (segment['target_text'] ?? '').toString();
        final normalizedSource = _normalizePhrase(sourceText);
        for (final phraseEntry in phraseRecords.entries) {
          final phrase = _normalizePhrase(phraseEntry.key);
          final record = phraseEntry.value;
          final sourceForms = record is Map<String, dynamic>
              ? _stringList(record['source_forms'])
              : const <String>[];
          final normalizedForms = <String>{
            phrase,
            ...sourceForms.map(_normalizePhrase),
          }..removeWhere((value) => value.isEmpty);
          if (phrase.isEmpty ||
              !normalizedForms.any(normalizedSource.contains)) {
            continue;
          }
          final dedupeKey = '$segmentId|$phrase';
          if (!seen.add(dedupeKey)) {
            continue;
          }
          final translations = record is Map<String, dynamic>
              ? _stringList(record['translations'])
              : const <String>[];
          final selectedTranslation =
              _selectContextualTranslation(translations, targetText);
          if (selectedTranslation.isEmpty) {
            continue;
          }
          result.add({
            'segment_id': segmentId,
            'paragraph_index': paragraphIndex,
            'source': phrase,
            'translation': selectedTranslation,
            'translations': translations,
            'dictionary_key': phrase,
            'alignment_kind': 'phrase',
          });
        }
      }
    }
    return result;
  }

  String _dictionaryKey(String lemma, String pos) {
    return '${lemma.trim().toLowerCase()}|${pos.trim().toUpperCase()}';
  }

  String _normalizePhrase(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  Map<String, dynamic> _selectContextualSpan(
    List<String> translations,
    String targetText, {
    required int sourceIndex,
    required int sourceCount,
    required Set<int> claimed,
  }) {
    final targetTokens = _translationTokens(targetText);
    final candidates = <Map<String, dynamic>>[];
    for (var translationIndex = 0;
        translationIndex < translations.length;
        translationIndex++) {
      final translation = translations[translationIndex];
      final wanted = _translationTokens(translation);
      if (wanted.isEmpty || wanted.length > targetTokens.length) {
        continue;
      }
      for (var start = 0;
          start <= targetTokens.length - wanted.length;
          start++) {
        final exact = List<int>.generate(wanted.length, (index) => index)
            .every((offset) => targetTokens[start + offset] == wanted[offset]);
        if (exact) {
          candidates.add({
            'translation': translation,
            'start': start,
            'end': start + wanted.length - 1,
            'exact': true,
            'translation_index': translationIndex,
          });
        }
      }
      if (wanted.length != 1) {
        continue;
      }
      for (var start = 0; start < targetTokens.length; start++) {
        final source = wanted.single;
        final target = targetTokens[start];
        final shortest =
            source.length < target.length ? source.length : target.length;
        var common = 0;
        while (common < shortest &&
            source.codeUnitAt(common) == target.codeUnitAt(common)) {
          common += 1;
        }
        if (common >= 3 && common / shortest >= 0.6) {
          candidates.add({
            'translation': translation,
            'start': start,
            'end': start,
            'exact': source == target,
            'translation_index': translationIndex,
          });
        }
      }
    }
    candidates.removeWhere((candidate) {
      final start = candidate['start'] as int;
      final end = candidate['end'] as int;
      return List<int>.generate(end - start + 1, (index) => start + index)
          .any(claimed.contains);
    });
    if (candidates.isEmpty) {
      return const {'translation': '', 'start': -1, 'end': -1};
    }
    final sourcePosition =
        (sourceIndex + 0.5) / (sourceCount < 1 ? 1 : sourceCount);
    candidates.sort((left, right) {
      final leftLength = (left['end'] as int) - (left['start'] as int) + 1;
      final rightLength = (right['end'] as int) - (right['start'] as int) + 1;
      final lengthOrder = rightLength.compareTo(leftLength);
      if (lengthOrder != 0) return lengthOrder;
      final exactOrder = (right['exact'] == true ? 1 : 0)
          .compareTo(left['exact'] == true ? 1 : 0);
      if (exactOrder != 0) return exactOrder;
      double distance(Map<String, dynamic> item) {
        final center =
            ((item['start'] as int) + (item['end'] as int)) / 2 + 0.5;
        return (sourcePosition - center / targetTokens.length).abs();
      }

      final distanceOrder = distance(left).compareTo(distance(right));
      if (distanceOrder != 0) return distanceOrder;
      return (left['translation_index'] as int)
          .compareTo(right['translation_index'] as int);
    });
    return candidates.first;
  }

  String _selectContextualTranslation(
    List<String> translations,
    String targetText,
  ) {
    final targetTokens = _translationTokens(targetText);
    if (translations.isEmpty || targetTokens.isEmpty) {
      return '';
    }
    for (final translation in translations) {
      final wanted = _translationTokens(translation);
      if (_containsTokenSequence(targetTokens, wanted)) {
        return translation;
      }
    }
    String selected = '';
    var bestScore = 0.0;
    for (final translation in translations) {
      final wanted = _translationTokens(translation);
      if (wanted.length != 1) {
        continue;
      }
      final source = wanted.single;
      for (final candidate in targetTokens) {
        final shortest =
            source.length < candidate.length ? source.length : candidate.length;
        var commonPrefix = 0;
        while (commonPrefix < shortest &&
            source.codeUnitAt(commonPrefix) ==
                candidate.codeUnitAt(commonPrefix)) {
          commonPrefix += 1;
        }
        if (commonPrefix < 3) {
          continue;
        }
        final score = commonPrefix / shortest;
        if (score >= 0.6 && score > bestScore) {
          selected = translation;
          bestScore = score;
        }
      }
    }
    return selected;
  }

  List<String> _translationTokens(String value) => RegExp(
        r'[\p{L}\p{N}]+',
        unicode: true,
      )
          .allMatches(value.toLowerCase())
          .map((match) => match.group(0) ?? '')
          .where((token) => token.isNotEmpty)
          .toList();

  bool _containsTokenSequence(List<String> haystack, List<String> wanted) {
    if (wanted.isEmpty || wanted.length > haystack.length) {
      return false;
    }
    for (var index = 0; index <= haystack.length - wanted.length; index++) {
      var matches = true;
      for (var offset = 0; offset < wanted.length; offset++) {
        if (haystack[index + offset] != wanted[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return true;
      }
    }
    return false;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    final result = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isEmpty || result.contains(text)) {
        continue;
      }
      result.add(text);
    }
    return result;
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

  Map<String, dynamic> _loadManifestWithDictionaries(
    Map<String, dynamic> loadManifest,
    Iterable<String> languages,
  ) {
    final next = Map<String, dynamic>.from(loadManifest);
    final files = Map<String, dynamic>.from(
        next['files'] as Map<String, dynamic>? ?? const <String, dynamic>{});
    final dictionaries = Map<String, dynamic>.from(
        files['dictionaries'] as Map<String, dynamic>? ??
            const <String, dynamic>{});
    final wordToWordByLang = Map<String, dynamic>.from(
        files['word_to_word_by_lang'] as Map<String, dynamic>? ??
            const <String, dynamic>{});
    for (final lang in languages) {
      dictionaries[lang] = 'dictionary_$lang.json';
      wordToWordByLang[lang] = 'word_to_word_$lang.json';
    }
    files['dictionaries'] = dictionaries;
    files['word_to_word_by_lang'] = wordToWordByLang;
    next['files'] = files;
    return next;
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

  Future<Map<String, dynamic>> _readJsonObject(File file) async {
    if (!file.existsSync()) {
      return <String, dynamic>{};
    }
    try {
      final payload = jsonDecode(await file.readAsString());
      return payload is Map<String, dynamic> ? payload : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Directory?> _findExistingOutputDir(
    String bookId,
    String fallbackTitle,
  ) async {
    final root =
        Directory('${VirgilWorkbenchPaths.output.path}/$level/$section');
    final reusable = await _findReusableOutputDir(root, fallbackTitle);
    if (reusable != null) {
      return reusable;
    }
    if (!root.existsSync()) {
      return null;
    }
    for (final entity in root.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final manifestFile = File('${entity.path}/manifest.json');
      if (!manifestFile.existsSync()) {
        continue;
      }
      final manifest = await _readJsonObject(manifestFile);
      if ((manifest['book_id'] ?? '').toString() == bookId) {
        return entity;
      }
    }
    return null;
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
        r'Compress-Archive -Path (Join-Path $env:VIRGIL_ZIP_SOURCE "*") -DestinationPath $env:VIRGIL_ZIP_DESTINATION -Force',
      ],
      environment: {
        'VIRGIL_ZIP_SOURCE': outputDir.path,
        'VIRGIL_ZIP_DESTINATION': outputZip.path,
      },
    );
    if (result.exitCode != 0) {
      throw Exception('Zip build failed: ${result.stderr}'.trim());
    }
    log('Zip created: ${outputZip.path}');

    final installDir = Directory(
      '${VirgilWorkbenchPaths.cloudLibrary.path}/$level/$section/books_zip',
    );
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
