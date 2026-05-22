import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'nove_a1_chapters.dart';
import 'nove_download_options.dart';
import 'mobile_settings_repository.dart';

class NoveBundledBookInfo {
  const NoveBundledBookInfo({
    required this.assetPath,
    required this.bookId,
    required this.title,
    required this.level,
    required this.section,
    required this.chapterId,
    required this.chapterTitle,
    this.remoteZipUrl,
    this.coverPath,
    this.coverBytes,
  });

  final String assetPath;
  final String bookId;
  final String title;
  final String level;
  final String section;
  final String chapterId;
  final String chapterTitle;
  final String? remoteZipUrl;
  final String? coverPath;
  final Uint8List? coverBytes;

  bool get isRemote => (remoteZipUrl ?? '').trim().isNotEmpty;
}

class NoveBundledBookRepository {
  static const _cloudBaseUrl = String.fromEnvironment('NOVE_LIBRARY_BASE_URL');
  static const _libraryDirName = 'mobile_library';

  Map<String, dynamic>? _cloudIndexCache;
  final Map<String, Uint8List?> _coverCache = <String, Uint8List?>{};

  Future<List<NoveBundledBookInfo>> listBooks({
    String? level,
    String? section,
  }) async {
    return _listCloudBooks(level: level, section: section);
  }

  Future<List<NoveBundledBookInfo>> _listCloudBooks({
    String? level,
    String? section,
  }) async {
    final baseUrl = _normalizedCloudBaseUrl();
    if (baseUrl.isEmpty) {
      throw Exception('NOVE_LIBRARY_BASE_URL is required for cloud library.');
    }
    final payload = await _loadCloudIndex(baseUrl);
    final books = (payload['books'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final result = <NoveBundledBookInfo>[];
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

  Future<NoveBundledBookInfo> _cloudInfoFromJson(
    String baseUrl,
    Map<String, dynamic> json,
  ) async {
    final zipPath = (json['zip_path'] ?? '').toString();
    final coverPath = (json['cover_path'] ?? '').toString();
    final section = (json['section'] ?? '').toString();
    final rawChapterId = (json['chapter_id'] ?? '').toString();
    final chapterId = section == 'chapters' && rawChapterId.isEmpty
        ? noveDefaultA1ChapterId
        : rawChapterId;
    final chapterTitle = (json['chapter_title'] ?? '').toString().isEmpty
        ? (chapterId.isEmpty ? '' : noveA1ChapterTitle(chapterId))
        : (json['chapter_title'] ?? '').toString();
    final remoteZipUrl = '$baseUrl/${Uri.encodeFull(zipPath)}';
    final coverBytes =
        coverPath.isEmpty ? null : await _downloadCover(baseUrl, coverPath);
    return NoveBundledBookInfo(
      assetPath: 'cloud:$zipPath',
      bookId: (json['book_id'] ?? '').toString(),
      title: (json['title'] ?? zipPath.split('/').last).toString(),
      level: (json['level'] ?? '').toString(),
      section: section,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      remoteZipUrl: remoteZipUrl,
      coverPath: coverPath.isEmpty ? null : coverPath,
      coverBytes: coverBytes,
    );
  }

  bool _isPlanTitle(String title) {
    final normalized = title.trim().toLowerCase();
    return normalized.contains('plan') ||
        normalized.contains('\u043f\u043b\u0430\u043d');
  }

  Future<NoveBundledBookInfo?> findBookByAssetPath(String assetPath) async {
    if (assetPath.trim().isEmpty) {
      return null;
    }
    final books = await listBooks();
    for (final book in books) {
      if (book.assetPath == assetPath) {
        return book;
      }
    }
    return null;
  }

  Future<String> importBook(
    NoveBundledBookInfo info, {
    NoveDownloadOptions options = const NoveDownloadOptions(),
  }) async {
    final settings = await MobileSettingsRepository().load();
    final preferredTargetLang = options.targetLang?.trim().isNotEmpty == true
        ? options.targetLang!.trim()
        : settings.preferredTargetLang;
    final bytes = info.isRemote
        ? await _downloadBytes(info.remoteZipUrl!)
        : throw Exception('Cloud zip URL is required.');
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{
      for (final file in archive.files)
        if (file.isFile) file.name.replaceAll('\\', '/'): file,
    };
    final manifest = _readJson(files, 'manifest.json');
    final reader = _readReaderJson(files, preferredTargetLang);
    final readerPayloads = _readReaderPayloads(files, manifest);
    final dictionaryManifest = _readDictionaryJson(files, preferredTargetLang);
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
    final coverPath = (manifest['cover'] ?? '').toString();
    final chapterId = (manifest['chapter_id'] ?? info.chapterId).toString();
    final chapterTitle =
        (manifest['chapter_title'] ?? info.chapterTitle).toString();
    final localBookId = (manifest['book_id'] ?? info.bookId).toString();
    if (localBookId.isEmpty) {
      throw Exception('Bundled book does not contain book_id');
    }
    final bookDir = await _bookDir(localBookId);
    if (bookDir.existsSync()) {
      await bookDir.delete(recursive: true);
    }
    await bookDir.create(recursive: true);

    final package = {
      'meta': {
        'local_book_id': localBookId,
        'desktop_book_id': localBookId,
        'title': (manifest['title'] ?? info.title).toString(),
        'source_name': info.section,
        if (chapterId.isNotEmpty) 'chapter_id': chapterId,
        if (chapterTitle.isNotEmpty) 'chapter_title': chapterTitle,
        'source_lang': manifest['source_lang'] ?? 'en',
        'target_lang': reader['target_lang'] ?? manifest['target_lang'] ?? 'ru',
        'model_name': 'nove_bundle',
        'status': 'ready',
        'current_paragraph_index': 0,
        'package_version': 1,
        'content_hash': info.assetPath,
        'download_options': options.toJson(),
        if (options.targetLang?.trim().isNotEmpty == true)
          'selected_target_lang': options.targetLang!.trim(),
        if (selectedVoiceId.isNotEmpty) 'selected_voice_id': selectedVoiceId,
        if (coverPath.isNotEmpty) 'cover': coverPath,
        'exported_at': manifest['generated_at'],
      },
      'source_text': '',
      'reader_payload': reader,
      'reader_payloads': readerPayloads,
      'dictionary_manifest': dictionaryManifest,
      'dictionary_manifests': dictionaryManifests,
      'detail_manifest': _readOptionalJson(files, 'detail_manifest.json'),
      'tts_manifest': ttsManifest,
      'word_audio_manifest': wordAudioManifest,
      'word_to_word': _readOptionalJson(files, 'word_to_word.json'),
    };
    await File('${bookDir.path}/package.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(package),
      encoding: utf8,
      flush: true,
    );
    await _copyCover(files, bookDir, coverPath);
    await _copyAudio(files, bookDir, wordAudioManifest: wordAudioManifest);
    return localBookId;
  }

  bool _manifestContainsVoice(Map<String, dynamic> manifest, String voiceId) {
    final activeVoiceId = ((manifest['active_job'] as Map<String, dynamic>? ??
            const {})['voice_id'] as String? ??
        '');
    if (activeVoiceId == voiceId) {
      return true;
    }
    final profiles = manifest['profiles'] as List<dynamic>? ?? const [];
    for (final item in profiles.whereType<Map<String, dynamic>>()) {
      if ((item['voice_id'] ?? '').toString() == voiceId) {
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

  Future<Uint8List?> _downloadCover(String baseUrl, String coverPath) async {
    if (_coverCache.containsKey(coverPath)) {
      return _coverCache[coverPath];
    }
    final bytes =
        await _tryDownloadBytes('$baseUrl/${Uri.encodeFull(coverPath)}');
    _coverCache[coverPath] = bytes;
    return bytes;
  }

  Future<Uint8List?> _tryDownloadBytes(String url) async {
    try {
      return await _downloadBytes(url);
    } catch (_) {
      return null;
    }
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
    final wordAudioVoiceId =
        (wordAudioManifest['voice_id'] ?? 'af_heart').toString();
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
        await target.writeAsBytes(entry.value.content as List<int>,
            flush: true);
      }
      if (name.startsWith('audio/words/') && name.endsWith('.mp3')) {
        final fileName = name.split('/').last;
        final word = fileName.substring(0, fileName.length - 4);
        final target = File(
            '${bookDir.path}/word_audio/$wordAudioVoiceId/${_wordAudioKey(word)}.mp3');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value.content as List<int>,
            flush: true);
      }
    }
  }

  Future<void> _copyCover(Map<String, ArchiveFile> files, Directory bookDir,
      String coverPath) async {
    if (coverPath.trim().isEmpty) {
      return;
    }
    final coverFile = files[coverPath];
    if (coverFile == null) {
      return;
    }
    final target = File('${bookDir.path}/$coverPath');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(coverFile.content as List<int>, flush: true);
  }

  Future<Directory> _bookDir(String localBookId) async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/$_libraryDirName/$localBookId');
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
