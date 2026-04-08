import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../cards_models.dart';
import '../detail_sheet_models.dart';
import '../models.dart';

class LexoApiClient {
  static const int _audioDownloadMaxAttempts = 3;
  static const Duration _hostProbeTimeout = Duration(seconds: 1);
  static const Duration _debugLogTimeout = Duration(milliseconds: 700);

  LexoApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultBaseUrl();

  String _baseUrl;

  String get baseUrl => _baseUrl;

  void setBaseUrl(String? value) {
    final next = (value ?? '').trim();
    _baseUrl = next.isEmpty ? _defaultBaseUrl() : next;
  }

  static String _defaultBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment('LEXO_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }
    final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
    return 'http://$host:8765';
  }

  Future<BookStatus> getBookStatus() async {
    final data = await _get('/book');
    return BookStatus.fromJson(data);
  }

  Future<LibraryPayload> getBooks() async {
    final data = await _get('/books');
    return LibraryPayload.fromJson(data);
  }

  Future<LibraryPayload> getDesktopBooksForMobile() async {
    final data = await _get('/mobile/desktop-books');
    return LibraryPayload.fromJson(data);
  }

  Future<BookStatus> importBook(String sourcePath) async {
    final data = await _post('/books/import', {'source_path': sourcePath});
    return BookStatus.fromJson(data);
  }

  Future<BookStatus> importDesktopBookText({
    required String title,
    required String sourceText,
    String sourceLang = 'en',
    String targetLang = 'ru',
  }) async {
    final data = await _post(
      '/books/import-text',
      {
        'title': title,
        'source_text': sourceText,
        'source_lang': sourceLang,
        'target_lang': targetLang,
      },
    );
    return BookStatus.fromJson(data);
  }

  Future<Map<String, dynamic>> importMobileBookText({
    required String title,
    required String sourceText,
    String sourceLang = 'en',
    String targetLang = 'ru',
  }) async {
    return _post(
      '/mobile/books/import-text',
      {
        'title': title,
        'source_text': sourceText,
        'source_lang': sourceLang,
        'target_lang': targetLang,
      },
    );
  }

  Future<BookStatus> openBook(String bookId) async {
    final data = await _post('/books/open', {'book_id': bookId});
    return BookStatus.fromJson(data);
  }

  Future<void> deleteBook(String bookId) async {
    await _post('/books/delete', {'book_id': bookId});
  }

  Future<ReaderPayload> getReaderPayload(String bookId) async {
    final data = await _get('/reader/paragraphs?book_id=$bookId');
    return ReaderPayload.fromJson(data);
  }

  Future<DetailSheetPayload> getDetailSheet({
    required String bookId,
    required String wordId,
  }) async {
    final data = await _get('/reader/detail-sheet?book_id=$bookId&word_id=$wordId');
    return DetailSheetPayload.fromJson(data);
  }

  Future<Map<String, dynamic>> saveDetailUnit({
    required String bookId,
    required String wordId,
    required String unitId,
  }) {
    return _post(
      '/reader/detail-sheet/save',
      {
        'book_id': bookId,
        'word_id': wordId,
        'unit_id': unitId,
      },
    );
  }

  Future<List<SavedWordItem>> getSavedWords() async {
    final data = await _get('/saved-words');
    return (data['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(SavedWordItem.fromJson)
        .toList();
  }

  Future<SavedCardsPayload> getSavedCards({String? status}) async {
    final suffix = (status == null || status.isEmpty) ? '' : '?status=$status';
    final data = await _get('/cards$suffix');
    return SavedCardsPayload.fromJson(data);
  }

  Future<SavedCardsPayload> getReviewCards() async {
    final data = await _get('/cards/review');
    return SavedCardsPayload.fromJson(data);
  }

  Future<SavedCardItem> applyReviewResult({
    required String cardId,
    required String direction,
  }) async {
    final data = await _post(
      '/cards/review/result',
      {
        'card_id': cardId,
        'direction': direction,
      },
    );
    return SavedCardItem.fromJson(data['item'] as Map<String, dynamic>? ?? const {});
  }

  Future<Map<String, dynamic>> deleteSavedCard({
    required String cardId,
  }) {
    return _post(
      '/cards/delete',
      {
        'card_id': cardId,
      },
    );
  }

  Future<Map<String, dynamic>> saveWord(String word) {
    return _post('/saved-words/raw', {'word': word});
  }

  Future<Map<String, dynamic>> requestWordAudio(String word) {
    return _post('/word/audio', {'word': word});
  }

  Future<Map<String, dynamic>> getMobileBookPackage(String bookId) async {
    return _get('/mobile/books/package?book_id=$bookId');
  }

  Future<Map<String, dynamic>> getMobileBookPackageManifest(String bookId) async {
    return _get('/mobile/books/package-manifest?book_id=$bookId');
  }

  Future<Map<String, dynamic>> getMobileBookPackagePart({
    required String bookId,
    required String partId,
  }) async {
    return _get('/mobile/books/package-part?book_id=$bookId&part_id=$partId');
  }

  Future<Map<String, dynamic>> downloadMobileBookPackageChunked(String bookId) async {
    final manifest = await getMobileBookPackageManifest(bookId);
    final meta = manifest['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final partItems = (manifest['parts'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final paragraphs = <Map<String, dynamic>>[];
    final readerPayload = <String, dynamic>{
      'book_id': meta['desktop_book_id'] ?? meta['local_book_id'],
      'title': meta['title'],
      'status': meta['status'] ?? 'ready',
      'source_lang': meta['source_lang'],
      'target_lang': meta['target_lang'],
      'current_paragraph_index': meta['current_paragraph_index'] ?? 0,
      'paragraphs': paragraphs,
    };
    final package = <String, dynamic>{
      'meta': <String, dynamic>{...meta},
      'source_text': '',
      'reader_payload': readerPayload,
      'tts_manifest': <String, dynamic>{},
    };
    for (final part in partItems) {
      final partId = part['part_id'] as String? ?? '';
      if (partId.isEmpty) {
        continue;
      }
      final partResponse = await getMobileBookPackagePart(bookId: bookId, partId: partId);
      final kind = partResponse['kind'] as String? ?? '';
      final payload = partResponse['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
      switch (kind) {
        case 'meta':
          package['meta'] = payload;
          break;
        case 'source_text':
          package['source_text'] = payload['source_text'] as String? ?? '';
          break;
        case 'reader_meta':
          readerPayload
            ..['book_id'] = payload['book_id']
            ..['title'] = payload['title']
            ..['status'] = payload['status'] ?? 'ready'
            ..['source_lang'] = payload['source_lang']
            ..['target_lang'] = payload['target_lang']
            ..['current_paragraph_index'] = payload['current_paragraph_index'] ?? 0;
          break;
        case 'reader_paragraphs':
          paragraphs.addAll(
            (payload['paragraphs'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>(),
          );
          break;
        case 'tts_manifest':
          package['tts_manifest'] = payload;
          break;
      }
    }
    return package;
  }

  Future<Map<String, dynamic>> syncMobileCardsFull({
    required String deviceId,
    required String? lastSyncAt,
    required List<Map<String, dynamic>> cardsDelta,
  }) {
    return _post(
      '/mobile/sync/full',
      {
        'device_id': deviceId,
        'last_sync_at': lastSyncAt,
        'cards_delta': cardsDelta,
      },
    );
  }

  Future<bool> pingHost() async {
    try {
      final data = await _get('/health', timeout: _hostProbeTimeout);
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> postMobileDebugLog({
    required String tag,
    required String message,
  }) async {
    await _post(
      '/mobile/debug/log',
      {
        'tag': tag,
        'message': message,
      },
      timeout: _debugLogTimeout,
    );
  }

  Future<List<TtsProfile>> getTtsProfiles() async {
    final data = await _get('/tts/profiles');
    return (data['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TtsProfile.fromJson)
        .toList();
  }

  Future<List<TtsLevel>> getTtsLevels() async {
    final data = await _get('/tts/levels');
    return (data['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TtsLevel.fromJson)
        .toList();
  }

  Future<TtsState> getTtsState(String bookId) async {
    final data = await _get('/tts/state?book_id=$bookId');
    return TtsState.fromJson(data);
  }

  Future<List<int>> downloadTtsAudio({
    required String bookId,
    required String jobId,
    required int segmentIndex,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/mobile/books/audio?book_id=$bookId&job_id=$jobId&segment_index=$segmentIndex',
    );
    Object? lastError;
    for (var attempt = 1; attempt <= _audioDownloadMaxAttempts; attempt += 1) {
      developer.log('GET $uri attempt=$attempt', name: 'LEXO_API');
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
          buffer.addAll(chunk);
          return buffer;
        });
        if (response.statusCode >= 400) {
          throw LexoApiException('Audio download failed with status ${response.statusCode}');
        }
        developer.log(
          'AUDIO_OK GET $uri attempt=$attempt bytes=${bytes.length}',
          name: 'LEXO_API',
        );
        return bytes;
      } on HttpException catch (error) {
        lastError = error;
        developer.log(
          'AUDIO_RETRY GET $uri attempt=$attempt error=$error',
          name: 'LEXO_API',
        );
        if (attempt >= _audioDownloadMaxAttempts) {
          rethrow;
        }
      } finally {
        client.close(force: true);
      }
    }
    throw lastError is Exception
        ? lastError
        : LexoApiException('Audio download failed after $_audioDownloadMaxAttempts attempts');
  }

  Future<TtsState> generateTts({
    required String bookId,
    required String voiceId,
    required List<int> levelIds,
    String mode = 'play_from_current',
    bool overwrite = false,
  }) async {
    final data = await _post(
      '/tts/generate',
      {
        'book_id': bookId,
        'voice_id': voiceId,
        'level_ids': levelIds,
        'mode': mode,
        'overwrite': overwrite,
      },
    );
    return TtsState.fromJson(data);
  }

  Future<TtsState> startTtsPlayback({
    required String bookId,
    required String jobId,
  }) async {
    final data = await _post(
      '/tts/start',
      {'book_id': bookId, 'job_id': jobId},
    );
    return TtsState.fromJson(data);
  }

  Future<TtsState> controlTts({
    required String bookId,
    required String jobId,
    required String action,
  }) async {
    final data = await _post(
      '/tts/control',
      {'book_id': bookId, 'job_id': jobId, 'action': action},
    );
    return TtsState.fromJson(data);
  }

  Future<void> saveReaderPosition(String bookId, int paragraphIndex) async {
    await _post('/reader/position', {'book_id': bookId, 'paragraph_index': paragraphIndex});
  }

  Future<Map<String, dynamic>> _get(String path, {Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    developer.log('GET $uri', name: 'LEXO_API');
    final client = HttpClient();
    if (timeout != null) {
      client.connectionTimeout = timeout;
    }
    final request = await client.getUrl(uri).timeout(timeout ?? const Duration(days: 1));
    request.persistentConnection = false;
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    final response = await request.close().timeout(timeout ?? const Duration(days: 1));
    try {
      return await _readJson(response, 'GET', uri);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
    {Duration? timeout}
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    developer.log(
      'POST $uri payload=${jsonEncode(payload)}',
      name: 'LEXO_API',
    );
    final client = HttpClient();
    if (timeout != null) {
      client.connectionTimeout = timeout;
    }
    final request = await client.postUrl(uri).timeout(timeout ?? const Duration(days: 1));
    request.persistentConnection = false;
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(timeout ?? const Duration(days: 1));
    try {
      return await _readJson(response, 'POST', uri);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _readJson(
    HttpClientResponse response,
    String method,
    Uri uri,
  ) async {
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    late final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException catch (error) {
      body = utf8.decode(bytes, allowMalformed: true);
      developer.log(
        'RESPONSE UTF8_FALLBACK $method $uri error=$error bytes=${bytes.length}',
        name: 'LEXO_API',
      );
    }
    developer.log(
      'RESPONSE ${response.statusCode} $method $uri body=$body',
      name: 'LEXO_API',
    );
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw LexoApiException(data['error']?.toString() ?? 'Unknown API error');
    }
    return data;
  }
}

class LexoApiException implements Exception {
  LexoApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
