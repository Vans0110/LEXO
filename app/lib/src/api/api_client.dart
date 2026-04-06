import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../cards_models.dart';
import '../detail_sheet_models.dart';
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

  Future<Map<String, dynamic>> saveWord(String word) {
    return _post('/saved-words/raw', {'word': word});
  }

  Future<Map<String, dynamic>> requestWordAudio(String word) {
    return _post('/word/audio', {'word': word});
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
