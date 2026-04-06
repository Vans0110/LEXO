import '../../api/api_client.dart';
import '../../detail_sheet_models.dart';
import '../../models.dart';

class ReaderFeatureState {
  const ReaderFeatureState({
    this.payload,
    this.ttsProfiles = const [],
    this.ttsLevels = const [],
    this.ttsState,
    this.selectedLevelIds = const {2},
    this.selectedVoiceId,
    this.loading = true,
    this.actionBusy = false,
    this.error,
    this.lastSavedParagraphIndex,
    this.selectedParagraphIndex,
    this.selectedTapUnitId,
    this.translationLeftText,
    this.translationFocusText,
    this.translationRightText,
  });

  final ReaderPayload? payload;
  final List<TtsProfile> ttsProfiles;
  final List<TtsLevel> ttsLevels;
  final TtsState? ttsState;
  final Set<int> selectedLevelIds;
  final String? selectedVoiceId;
  final bool loading;
  final bool actionBusy;
  final String? error;
  final int? lastSavedParagraphIndex;
  final int? selectedParagraphIndex;
  final String? selectedTapUnitId;
  final String? translationLeftText;
  final String? translationFocusText;
  final String? translationRightText;

  ReaderFeatureState copyWith({
    ReaderPayload? payload,
    List<TtsProfile>? ttsProfiles,
    List<TtsLevel>? ttsLevels,
    TtsState? ttsState,
    Set<int>? selectedLevelIds,
    String? selectedVoiceId,
    bool? loading,
    bool? actionBusy,
    String? error,
    int? lastSavedParagraphIndex,
    int? selectedParagraphIndex,
    String? selectedTapUnitId,
    String? translationLeftText,
    String? translationFocusText,
    String? translationRightText,
    bool clearError = false,
  }) {
    return ReaderFeatureState(
      payload: payload ?? this.payload,
      ttsProfiles: ttsProfiles ?? this.ttsProfiles,
      ttsLevels: ttsLevels ?? this.ttsLevels,
      ttsState: ttsState ?? this.ttsState,
      selectedLevelIds: selectedLevelIds ?? this.selectedLevelIds,
      selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
      loading: loading ?? this.loading,
      actionBusy: actionBusy ?? this.actionBusy,
      error: clearError ? null : (error ?? this.error),
      lastSavedParagraphIndex: lastSavedParagraphIndex ?? this.lastSavedParagraphIndex,
      selectedParagraphIndex: selectedParagraphIndex ?? this.selectedParagraphIndex,
      selectedTapUnitId: selectedTapUnitId ?? this.selectedTapUnitId,
      translationLeftText: translationLeftText ?? this.translationLeftText,
      translationFocusText: translationFocusText ?? this.translationFocusText,
      translationRightText: translationRightText ?? this.translationRightText,
    );
  }
}

class ReaderFeatureLoadResult {
  const ReaderFeatureLoadResult({
    required this.payload,
    required this.ttsProfiles,
    required this.ttsLevels,
    required this.ttsState,
  });

  final ReaderPayload payload;
  final List<TtsProfile> ttsProfiles;
  final List<TtsLevel> ttsLevels;
  final TtsState ttsState;
}

class ReaderTtsLoadResult {
  const ReaderTtsLoadResult({
    required this.ttsProfiles,
    required this.ttsLevels,
    required this.ttsState,
  });

  final List<TtsProfile> ttsProfiles;
  final List<TtsLevel> ttsLevels;
  final TtsState ttsState;
}

class ReaderFeatureController {
  ReaderFeatureController(this._api);

  final LexoApiClient _api;

  Future<ReaderFeatureLoadResult> load(String bookId) async {
    final payload = await _api.getReaderPayload(bookId);
    final profiles = await _api.getTtsProfiles();
    final levels = await _api.getTtsLevels();
    final ttsState = await _api.getTtsState(bookId);
    return ReaderFeatureLoadResult(
      payload: payload,
      ttsProfiles: profiles,
      ttsLevels: levels,
      ttsState: ttsState,
    );
  }

  Future<ReaderTtsLoadResult> loadTts(String bookId) async {
    final profiles = await _api.getTtsProfiles();
    final levels = await _api.getTtsLevels();
    final ttsState = await _api.getTtsState(bookId);
    return ReaderTtsLoadResult(
      ttsProfiles: profiles,
      ttsLevels: levels,
      ttsState: ttsState,
    );
  }

  Future<void> saveReaderPosition(String bookId, int paragraphIndex) async {
    await _api.saveReaderPosition(bookId, paragraphIndex);
  }

  Future<DetailSheetPayload> getDetailSheet({
    required String bookId,
    required String wordId,
  }) {
    return _api.getDetailSheet(bookId: bookId, wordId: wordId);
  }

  Future<Map<String, dynamic>> saveDetailUnit({
    required String bookId,
    required String wordId,
    required String unitId,
  }) {
    return _api.saveDetailUnit(bookId: bookId, wordId: wordId, unitId: unitId);
  }

  Future<TtsState> refreshTtsState(String bookId) async {
    return _api.getTtsState(bookId);
  }

  Future<TtsState> generateTts({
    required String bookId,
    required String voiceId,
    required List<int> levelIds,
    String mode = 'play_from_current',
    bool overwrite = false,
  }) {
    return _api.generateTts(
      bookId: bookId,
      voiceId: voiceId,
      levelIds: levelIds,
      mode: mode,
      overwrite: overwrite,
    );
  }

  Future<TtsState> startTtsPlayback({
    required String bookId,
    required String jobId,
  }) {
    return _api.startTtsPlayback(bookId: bookId, jobId: jobId);
  }

  Future<TtsState> controlTts({
    required String bookId,
    required String jobId,
    required String action,
  }) {
    return _api.controlTts(bookId: bookId, jobId: jobId, action: action);
  }
}
