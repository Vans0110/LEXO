import '../../api/api_client.dart';
import '../../models.dart';

class LibraryFeatureState {
  const LibraryFeatureState({
    this.library,
    this.busy = false,
    this.openingBookId,
    this.error,
  });

  final LibraryPayload? library;
  final bool busy;
  final String? openingBookId;
  final String? error;

  LibraryFeatureState copyWith({
    LibraryPayload? library,
    bool? busy,
    String? openingBookId,
    String? error,
    bool clearOpeningBookId = false,
    bool clearError = false,
  }) {
    return LibraryFeatureState(
      library: library ?? this.library,
      busy: busy ?? this.busy,
      openingBookId: clearOpeningBookId ? null : (openingBookId ?? this.openingBookId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LibraryFeatureController {
  LibraryFeatureController(this._api);

  final LexoApiClient _api;

  Future<LibraryFeatureState> load(LibraryFeatureState current) async {
    final payload = await _api.getBooks();
    return current.copyWith(
      library: payload,
      busy: false,
      clearError: true,
      clearOpeningBookId: true,
    );
  }

  Future<LibraryFeatureState> importBook(
    LibraryFeatureState current,
    String sourcePath,
  ) async {
    await _api.importBook(sourcePath);
    return load(current);
  }

  Future<LibraryFeatureState> importBookText(
    LibraryFeatureState current, {
    required String title,
    required String sourceText,
  }) async {
    await _api.importDesktopBookText(
      title: title,
      sourceText: sourceText,
    );
    return load(current);
  }

  Future<void> openBook(String bookId) async {
    await _api.openBook(bookId);
  }

  Future<LibraryFeatureState> deleteBook(
    LibraryFeatureState current,
    String bookId,
  ) async {
    await _api.deleteBook(bookId);
    return load(current);
  }
}
