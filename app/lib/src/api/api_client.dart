import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../models.dart';

class LexoApiClient {
  LexoApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultBaseUrl();

  String _baseUrl;
  final HttpClient _http = HttpClient();

  String get baseUrl => _baseUrl;

  void setBaseUrl(String? value) {
    final next = (value ?? '').trim();
    _baseUrl = next.isEmpty ? _defaultBaseUrl() : next;
  }

  static String _defaultBaseUrl() {
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

  Future<Map<String, dynamic>> importBookText({
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

  Future<Map<String, dynamic>> getMobileBookPackage(String bookId) async {
    return _get('/mobile/books/package?book_id=$bookId');
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
    developer.log('GET $uri', name: 'LEXO_API');
    final request = await _http.getUrl(uri);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    if (response.statusCode >= 400) {
      throw LexoApiException('Audio download failed with status ${response.statusCode}');
    }
    return bytes;
  }

  Future<TtsState> generateTts({
    required String bookId,
    required String voiceId,
    required List<int> levelIds,
    String mode = 'play_from_current',
  }) async {
    final data = await _post(
      '/tts/generate',
      {
        'book_id': bookId,
        'voice_id': voiceId,
        'level_ids': levelIds,
        'mode': mode,
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

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    developer.log('GET $uri', name: 'LEXO_API');
    final request = await _http.getUrl(uri);
    final response = await request.close();
    return _readJson(response, 'GET', uri);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    developer.log(
      'POST $uri payload=${jsonEncode(payload)}',
      name: 'LEXO_API',
    );
    final request = await _http.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    return _readJson(response, 'POST', uri);
  }

  Future<Map<String, dynamic>> _readJson(
    HttpClientResponse response,
    String method,
    Uri uri,
  ) async {
    final body = await utf8.decoder.bind(response).join();
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
