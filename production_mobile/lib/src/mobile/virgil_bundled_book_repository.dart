import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'virgil_a1_chapters.dart';
import 'virgil_download_options.dart';
import 'mobile_settings_repository.dart';

class VirgilBundledBookInfo {
  const VirgilBundledBookInfo({
    required this.bookId,
    required this.title,
    required this.level,
    required this.section,
    required this.chapterId,
    required this.chapterTitle,
    required this.contentHash,
    this.remoteZipUrl,
    this.coverPath,
    this.coverUrl,
    this.coverBytes,
  });

  final String bookId;
  final String title;
  final String level;
  final String section;
  final String chapterId;
  final String chapterTitle;
  final String contentHash;
  final String? remoteZipUrl;
  final String? coverPath;
  final String? coverUrl;
  final Uint8List? coverBytes;

  bool get isRemote => (remoteZipUrl ?? '').trim().isNotEmpty;
}

class VirgilBundledBookRepository {
  static const _cloudBaseUrl =
      String.fromEnvironment('VIRGIL_LIBRARY_BASE_URL');
  static const _libraryDirName = 'mobile_library';

  Map<String, dynamic>? _cloudIndexCache;
  Future<Map<String, dynamic>>? _cloudIndexInFlight;

  Future<List<VirgilBundledBookInfo>> listBooks({
    String? level,
    String? section,
  }) async {
    return _listCloudBooks(level: level, section: section);
  }

  Future<List<VirgilBundledBookInfo>> _listCloudBooks({
    String? level,
    String? section,
  }) async {
    final baseUrl = _normalizedCloudBaseUrl();
    if (baseUrl.isEmpty) {
      throw Exception('VIRGIL_LIBRARY_BASE_URL is required for cloud library.');
    }
    final payload = await _loadCloudIndex(baseUrl);
    final books = (payload['books'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final result = <VirgilBundledBookInfo>[];
    for (final item in books) {
      final title = (item['title'] ?? '').toString();
      if (_isPlanTitle(title)) {
        continue;
      }
      if (level != null && (item['level'] ?? '').toString() != level) {
        continue;
      }
      if (section != null && (item['section'] ?? '').toString() != section) {
        continue;
      }
      final info = await _cloudInfoFromJson(baseUrl, item);
      result.add(info);
    }
    result.sort((left, right) => left.title.compareTo(right.title));
    return result;
  }

  Future<VirgilBundledBookInfo> _cloudInfoFromJson(
    String baseUrl,
    Map<String, dynamic> json,
  ) async {
    final zipPath = (json['zip_path'] ?? '').toString();
    final coverPath = (json['cover_path'] ?? '').toString();
    final section = (json['section'] ?? '').toString();
    final rawChapterId = (json['chapter_id'] ?? '').toString();
    final chapterId = section == 'chapters' && rawChapterId.isEmpty
        ? virgilDefaultA1ChapterId
        : rawChapterId;
    final chapterTitle = (json['chapter_title'] ?? '').toString().isEmpty
        ? (chapterId.isEmpty ? '' : virgilA1ChapterTitle(chapterId))
        : (json['chapter_title'] ?? '').toString();
    final remoteZipUrl = '$baseUrl/${Uri.encodeFull(zipPath)}';
    final coverUrl =
        coverPath.isEmpty ? null : '$baseUrl/${Uri.encodeFull(coverPath)}';
    return VirgilBundledBookInfo(
      bookId: (json['book_id'] ?? '').toString(),
      title: (json['title'] ?? zipPath.split('/').last).toString(),
      level: (json['level'] ?? '').toString(),
      section: section,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      contentHash: (json['content_hash'] ?? '').toString(),
      remoteZipUrl: remoteZipUrl,
      coverPath: coverPath.isEmpty ? null : coverPath,
      coverUrl: coverUrl,
    );
  }

  bool _isPlanTitle(String title) {
    final normalized = title.trim().toLowerCase();
    return normalized.contains('plan') ||
        normalized.contains('\u043f\u043b\u0430\u043d');
  }

  Future<VirgilBundledBookInfo?> findBookById(String bookId) async {
    if (bookId.trim().isEmpty) {
      return null;
    }
    final books = await listBooks();
    for (final book in books) {
      if (book.bookId == bookId) {
        return book;
      }
    }
    return null;
  }

  Future<String> importBook(
    VirgilBundledBookInfo info, {
    VirgilDownloadOptions options = const VirgilDownloadOptions(),
  }) async {
    final settings = await MobileSettingsRepository().load();
    final preferredTargetLang = options.targetLang?.trim().isNotEmpty == true
        ? options.targetLang!.trim()
        : settings.preferredTargetLang;
    if (!info.isRemote) {
      throw Exception('Cloud zip URL is required.');
    }
    final tempRoot = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final zipFile = File('${tempRoot.path}/virgil_book_$stamp.zip');
    InputFileStream? zipInput;
    Directory? stagingDir;
    Directory? backupDir;
    Directory? bookDir;
    try {
      await _downloadToFile(info.remoteZipUrl!, zipFile);
      zipInput = InputFileStream(zipFile.path);
      final archive = ZipDecoder().decodeStream(zipInput);
      final files = <String, ArchiveFile>{
        for (final file in archive.files)
          if (file.isFile) file.name.replaceAll('\\', '/'): file,
      };
      final manifest = _readJson(files, 'manifest.json');
      final reader = _readReaderJson(files, preferredTargetLang);
      final readerPayloads = _readReaderPayloads(files, manifest);
      final dictionaryManifest =
          _readDictionaryJson(files, preferredTargetLang);
      final dictionaryManifests = _readDictionaryPayloads(files, manifest);
      final ttsManifest = _readOptionalJson(files, 'tts_manifest.json');
      final wordAudioManifest =
          _readOptionalJson(files, 'word_audio_manifest.json');
      final selectedVoiceId = options.voiceId?.trim() ?? '';
      if (selectedVoiceId.isNotEmpty &&
          !_manifestContainsVoice(ttsManifest, selectedVoiceId)) {
        throw Exception(
            'Voice $selectedVoiceId is not available in this book package yet.');
      }
      final coverPath =
          _safeRelativePath((manifest['cover'] ?? '').toString()) ?? '';
      final chapterId = (manifest['chapter_id'] ?? info.chapterId).toString();
      final chapterTitle =
          (manifest['chapter_title'] ?? info.chapterTitle).toString();
      final localBookId = (manifest['book_id'] ?? info.bookId).toString();
      if (!_isSafeLocalBookId(localBookId)) {
        throw Exception('Bundled book does not contain book_id');
      }

      bookDir = await _bookDir(localBookId);
      stagingDir = Directory('${bookDir.path}.install-$stamp');
      backupDir = Directory('${bookDir.path}.backup-$stamp');
      await stagingDir.create(recursive: true);
      final previousMeta = await _readExistingMeta(bookDir);
      final package = {
        'meta': {
          'local_book_id': localBookId,
          'desktop_book_id': localBookId,
          'title': (manifest['title'] ?? info.title).toString(),
          'source_name': info.section,
          if (chapterId.isNotEmpty) 'chapter_id': chapterId,
          if (chapterTitle.isNotEmpty) 'chapter_title': chapterTitle,
          'source_lang': manifest['source_lang'] ?? 'en',
          'target_lang':
              reader['target_lang'] ?? manifest['target_lang'] ?? 'ru',
          'model_name': 'virgil_bundle',
          'status': 'ready',
          'current_paragraph_index':
              previousMeta?['current_paragraph_index'] ?? 0,
          'package_version': 1,
          'content_hash': info.contentHash,
          'download_options': options.toJson(),
          if (options.targetLang?.trim().isNotEmpty == true)
            'selected_target_lang': options.targetLang!.trim(),
          if (selectedVoiceId.isNotEmpty) 'selected_voice_id': selectedVoiceId,
          if (coverPath.isNotEmpty) 'cover': coverPath,
          'exported_at': manifest['generated_at'],
          if (previousMeta?['last_opened_at'] != null)
            'last_opened_at': previousMeta!['last_opened_at'],
        },
        'source_text': '',
        'reader_payload': {
          ...reader,
          'current_paragraph_index':
              previousMeta?['current_paragraph_index'] ?? 0,
        },
        'reader_payloads': readerPayloads,
        'dictionary_manifest': dictionaryManifest,
        'dictionary_manifests': dictionaryManifests,
        'detail_manifest': _readOptionalJson(files, 'detail_manifest.json'),
        'tts_manifest': ttsManifest,
        'word_audio_manifest': wordAudioManifest,
        'word_to_word': _readOptionalJson(files, 'word_to_word.json'),
      };
      await File('${stagingDir.path}/package.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(package),
        encoding: utf8,
        flush: true,
      );
      await _copyCover(files, stagingDir, coverPath);
      await _copyAudio(files, stagingDir, wordAudioManifest: wordAudioManifest);
      await _installStagedBook(
        bookDir: bookDir,
        stagingDir: stagingDir,
        backupDir: backupDir,
      );
      stagingDir = null;
      backupDir = null;
      return localBookId;
    } finally {
      await zipInput?.close();
      if (zipFile.existsSync()) {
        await zipFile.delete();
      }
      if (stagingDir?.existsSync() == true) {
        await stagingDir!.delete(recursive: true);
      }
      if (backupDir?.existsSync() == true) {
        if (bookDir?.existsSync() == true) {
          await backupDir!.delete(recursive: true);
        } else {
          await backupDir!.rename(bookDir!.path);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _readExistingMeta(Directory bookDir) async {
    final packageFile = File('${bookDir.path}/package.json');
    if (!packageFile.existsSync()) {
      return null;
    }
    try {
      final package =
          jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
      return package['meta'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _installStagedBook({
    required Directory bookDir,
    required Directory stagingDir,
    required Directory backupDir,
  }) async {
    if (!File('${stagingDir.path}/package.json').existsSync()) {
      throw Exception('Downloaded book package is incomplete.');
    }
    if (bookDir.existsSync()) {
      await bookDir.rename(backupDir.path);
    }
    try {
      await stagingDir.rename(bookDir.path);
    } catch (_) {
      if (!bookDir.existsSync() && backupDir.existsSync()) {
        await backupDir.rename(bookDir.path);
      }
      rethrow;
    }
    if (backupDir.existsSync()) {
      await backupDir.delete(recursive: true);
    }
  }

  Future<void> _downloadToFile(String url, File target) async {
    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('GET $url failed: ${response.statusCode}');
      }
      await target.parent.create(recursive: true);
      sink = target.openWrite();
      await sink.addStream(response);
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  bool _manifestContainsVoice(Map<String, dynamic> manifest, String voiceId) {
    final jobs = manifest['jobs'] as List<dynamic>? ?? const [];
    for (final item in jobs.whereType<Map<String, dynamic>>()) {
      final jobVoiceId = (item['voice_id'] ?? '').toString();
      final status = (item['status'] ?? '').toString();
      final segments = item['segments'] as List<dynamic>? ?? const [];
      if (jobVoiceId == voiceId && status == 'ready' && segments.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('GET $url failed: ${response.statusCode}');
      }
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _loadCloudIndex(String baseUrl) async {
    final cached = _cloudIndexCache;
    if (cached != null) {
      return cached;
    }
    final inFlight = _cloudIndexInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final loading = _loadCloudIndexFromNetwork(baseUrl);
    _cloudIndexInFlight = loading;
    try {
      return await loading;
    } finally {
      _cloudIndexInFlight = null;
    }
  }

  Future<Map<String, dynamic>> _loadCloudIndexFromNetwork(
      String baseUrl) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final bytes = await _downloadBytes('$baseUrl/library_index.json');
        final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        _cloudIndexCache = payload;
        return payload;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 350 * (attempt + 1)));
        }
      }
    }
    throw Exception('Cloud library index unavailable: $lastError');
  }

  String _normalizedCloudBaseUrl() {
    return _cloudBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, dynamic> _readJson(Map<String, ArchiveFile> files, String name) {
    final file = files[name];
    if (file == null) {
      throw Exception('Bundled book is missing $name');
    }
    return jsonDecode(utf8.decode(file.content as List<int>))
        as Map<String, dynamic>;
  }

  Map<String, dynamic> _readReaderJson(
      Map<String, ArchiveFile> files, String preferredTargetLang) {
    final langReaderName = 'reader_$preferredTargetLang.json';
    if (files.containsKey(langReaderName)) {
      return _readJson(files, langReaderName);
    }
    return _readJson(files, 'reader.json');
  }

  Map<String, dynamic> _readReaderPayloads(
      Map<String, ArchiveFile> files, Map<String, dynamic> manifest) {
    final langs =
        (manifest['available_target_langs'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .where((item) => item == 'ru' || item == 'uk')
            .toList();
    final payloads = <String, dynamic>{};
    for (final lang in langs) {
      final fileName = 'reader_$lang.json';
      if (files.containsKey(fileName)) {
        payloads[lang] = _readJson(files, fileName);
      }
    }
    return payloads;
  }

  Map<String, dynamic> _readDictionaryJson(
      Map<String, ArchiveFile> files, String preferredTargetLang) {
    final langDictionaryName = 'dictionary_$preferredTargetLang.json';
    if (files.containsKey(langDictionaryName)) {
      return _readOptionalJson(files, langDictionaryName);
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _readDictionaryPayloads(
      Map<String, ArchiveFile> files, Map<String, dynamic> manifest) {
    final langs =
        (manifest['available_target_langs'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .where((item) => item == 'ru' || item == 'uk')
            .toList();
    final payloads = <String, dynamic>{};
    for (final lang in langs) {
      final fileName = 'dictionary_$lang.json';
      if (files.containsKey(fileName)) {
        payloads[lang] = _readOptionalJson(files, fileName);
      }
    }
    return payloads;
  }

  Map<String, dynamic> _readOptionalJson(
      Map<String, ArchiveFile> files, String name) {
    final file = files[name];
    if (file == null) {
      return <String, dynamic>{};
    }
    return jsonDecode(utf8.decode(file.content as List<int>))
        as Map<String, dynamic>;
  }

  Future<void> _copyAudio(
    Map<String, ArchiveFile> files,
    Directory bookDir, {
    required Map<String, dynamic> wordAudioManifest,
  }) async {
    final legacyWordAudioVoiceId =
        (wordAudioManifest['voice_id'] ?? '').toString().trim();
    for (final entry in files.entries) {
      final name = entry.key;
      if (name.startsWith('audio/segments/') && name.endsWith('.mp3')) {
        final fileName = name.split('/').last;
        final splitAt = fileName.lastIndexOf('_');
        if (splitAt <= 0) {
          continue;
        }
        final jobId = fileName.substring(0, splitAt);
        final segment = fileName.substring(splitAt + 1, fileName.length - 4);
        final target = File('${bookDir.path}/audio/$jobId/$segment.mp3');
        await target.parent.create(recursive: true);
        await _writeArchiveFile(entry.value, target);
      }
      if (name.startsWith('audio/words/') && name.endsWith('.mp3')) {
        final parts = name.split('/');
        if (parts.length < 3) {
          continue;
        }
        final fileName = parts.last;
        final word = fileName.substring(0, fileName.length - 4);
        final nestedVoiceId = parts.length >= 4 ? parts[2].trim() : '';
        final wordAudioVoiceId =
            nestedVoiceId.isNotEmpty ? nestedVoiceId : legacyWordAudioVoiceId;
        if (wordAudioVoiceId.isEmpty) {
          continue;
        }
        final target = File(
            '${bookDir.path}/word_audio/$wordAudioVoiceId/${_wordAudioKey(word)}.mp3');
        await target.parent.create(recursive: true);
        await _writeArchiveFile(entry.value, target);
      }
    }
  }

  Future<void> _copyCover(Map<String, ArchiveFile> files, Directory bookDir,
      String coverPath) async {
    final safeCoverPath = _safeRelativePath(coverPath);
    if (safeCoverPath == null) {
      return;
    }
    final coverFile = files[safeCoverPath];
    if (coverFile == null) {
      return;
    }
    final target = File('${bookDir.path}/$safeCoverPath');
    await target.parent.create(recursive: true);
    await _writeArchiveFile(coverFile, target);
  }

  Future<void> _writeArchiveFile(ArchiveFile source, File target) async {
    final output = OutputFileStream(target.path);
    try {
      source.writeContent(output);
    } finally {
      await output.close();
    }
  }

  Future<Directory> _bookDir(String localBookId) async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/$_libraryDirName/$localBookId');
  }

  String? _safeRelativePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalized) ||
        normalized.split('/').contains('..')) {
      return null;
    }
    return normalized;
  }

  bool _isSafeLocalBookId(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty &&
        !normalized.contains('/') &&
        !normalized.contains('\\') &&
        normalized != '.' &&
        normalized != '..';
  }

  String _wordAudioKey(String word) {
    final bytes = utf8.encode(word.trim().toLowerCase());
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
