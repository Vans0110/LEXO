import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../api/api_client.dart';
import '../../../detail_sheet_models.dart';
import '../../../features/reader/reader_feature.dart';
import '../../../mobile/mobile_package_repository.dart';
import '../../../models.dart';
import '../../../widgets/reader_detail_sheet.dart';
import '../../../widgets/reader_playback_bar.dart';
import '../../../widgets/reader_text_flow.dart';
import 'mobile_settings_screen.dart';

class MobileReaderScreen extends StatefulWidget {
  const MobileReaderScreen({super.key, required this.api, required this.localBookId});

  final LexoApiClient api;
  final String localBookId;

  @override
  State<MobileReaderScreen> createState() => _MobileReaderScreenState();
}

class _MobileReaderScreenState extends State<MobileReaderScreen> {
  static const Duration _pollInterval = Duration(seconds: 1);

  late final ReaderFeatureController _controller;
  late final MobileBookPackageRepository _packageRepository;
  late final Player _audioPlayer;

  ReaderFeatureState _state = const ReaderFeatureState();
  Timer? _pollTimer;
  String? _desktopBookId;
  bool _playerExpanded = true;

  double _selectedPlaybackSpeed() {
    final selectedId = _state.selectedLevelIds.isEmpty ? null : _state.selectedLevelIds.first;
    if (selectedId == null) {
      return 1.0;
    }
    for (final level in _state.ttsLevels) {
      if (level.id == selectedId) {
        return level.playbackSpeed;
      }
    }
    return 1.0;
  }

  Future<void> _applyPlaybackSpeed() async {
    await _audioPlayer.setRate(_selectedPlaybackSpeed());
  }

  Future<void> _togglePlayPause() async {
    final activeJob = _state.ttsState?.activeJob;
    if (activeJob != null && activeJob.isActive) {
      if (activeJob.playbackState == 'playing') {
        await _controlPlayback('pause');
      } else if (activeJob.playbackState == 'paused') {
        await _controlPlayback('resume');
      }
      return;
    }
    final selectedJob = _selectedJob();
    if (selectedJob == null || !selectedJob.isReady) {
      return;
    }
    await _startPlayback(selectedJob.jobId);
  }

  @override
  void initState() {
    super.initState();
    _controller = ReaderFeatureController(widget.api);
    _packageRepository = MobileBookPackageRepository();
    _audioPlayer = Player();
    _audioPlayer.stream.completed.listen((completed) {
      if (mounted && completed) {
        _handleTrackCompleted();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    developer.log('Loading local mobile reader payload', name: 'LEXO_UI');
    setState(() => _state = _state.copyWith(loading: true, clearError: true));
    try {
      final package = await _packageRepository.readPackage(widget.localBookId);
      final desktopBookId = package.meta.desktopBookId;
      List<TtsProfile> profiles = const [];
      List<TtsLevel> levels = const [];
      TtsState? ttsState;
      String? selectedVoiceId;
      var selectedLevelIds = _state.selectedLevelIds;

      if (desktopBookId.isNotEmpty) {
        try {
          final ttsResult = await _controller.loadTts(desktopBookId);
          profiles = ttsResult.ttsProfiles;
          levels = ttsResult.ttsLevels;
          ttsState = ttsResult.ttsState;
          final availableVoiceIds = profiles.map((item) => item.voiceId).toSet();
          final activeVoiceId = ttsState.activeJob?.voiceId;
          if (activeVoiceId != null && availableVoiceIds.contains(activeVoiceId)) {
            selectedVoiceId = activeVoiceId;
          } else if (_state.selectedVoiceId != null &&
              availableVoiceIds.contains(_state.selectedVoiceId)) {
            selectedVoiceId = _state.selectedVoiceId;
          } else {
            selectedVoiceId = profiles.isNotEmpty ? profiles.first.voiceId : null;
          }
          if (levels.isNotEmpty && selectedLevelIds.isEmpty) {
            final normal = levels.where((item) => item.name == 'Normal');
            selectedLevelIds = {normal.isNotEmpty ? normal.first.id : levels.first.id};
          }
        } catch (error) {
          developer.log('Remote TTS unavailable: $error', name: 'LEXO_UI');
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _desktopBookId = desktopBookId;
        _state = _state.copyWith(
          payload: package.readerPayload,
          ttsProfiles: profiles,
          ttsLevels: levels,
          ttsState: ttsState,
          selectedVoiceId: selectedVoiceId,
          selectedLevelIds: selectedLevelIds,
          loading: false,
          lastSavedParagraphIndex: package.readerPayload.currentParagraphIndex,
        );
      });
      await _applyPlaybackSpeed();
      _syncPolling(ttsState);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(loading: false, error: error.toString()));
    } finally {
      if (mounted && _state.loading) {
        setState(() => _state = _state.copyWith(loading: false));
      }
    }
  }

  Future<void> _refreshTtsState() async {
    final desktopBookId = _desktopBookId;
    if (desktopBookId == null || desktopBookId.isEmpty) {
      return;
    }
    try {
      final nextState = await _controller.refreshTtsState(desktopBookId);
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: nextState));
      _syncPolling(nextState);
    } catch (_) {}
  }

  void _syncPolling(TtsState? state) {
    if (state?.hasGeneratingJobs ?? false) {
      _pollTimer ??= Timer.periodic(_pollInterval, (_) => _refreshTtsState());
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _generateVoice() async {
    await _runGenerateVoice(overwrite: false);
  }

  Future<void> _overwriteVoice() async {
    await _runGenerateVoice(overwrite: true);
  }

  TtsJobItem? _selectedJob() {
    final voiceId = _state.selectedVoiceId;
    if (voiceId == null) {
      return null;
    }
    for (final job in _state.ttsState?.jobs ?? const <TtsJobItem>[]) {
      if (job.voiceId == voiceId) {
        return job;
      }
    }
    return null;
  }

  Future<void> _runGenerateVoice({required bool overwrite}) async {
    final desktopBookId = _desktopBookId;
    final voiceId = _state.selectedVoiceId;
    if (desktopBookId == null ||
        desktopBookId.isEmpty ||
        voiceId == null ||
        _state.selectedLevelIds.isEmpty) {
      return;
    }
    final selectedJob = _selectedJob();
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      await _audioPlayer.stop();
      if (overwrite && selectedJob != null) {
        await _packageRepository.deleteJobAudio(
          localBookId: widget.localBookId,
          jobId: selectedJob.jobId,
        );
      }
      final state = await _controller.generateTts(
        bookId: desktopBookId,
        voiceId: voiceId,
        levelIds: [_state.selectedLevelIds.first],
        overwrite: overwrite,
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: state));
      _syncPolling(state);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(error: error.toString()));
    } finally {
      if (mounted) {
        setState(() => _state = _state.copyWith(actionBusy: false));
      }
    }
  }

  Future<void> _startPlayback(String jobId) async {
    final desktopBookId = _desktopBookId;
    if (desktopBookId == null || desktopBookId.isEmpty) {
      return;
    }
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      await _audioPlayer.stop();
      final state = await _controller.startTtsPlayback(
        bookId: desktopBookId,
        jobId: jobId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: state));
      await _applyPlaybackSpeed();
      await _playCurrentSegment();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(error: error.toString()));
    } finally {
      if (mounted) {
        setState(() => _state = _state.copyWith(actionBusy: false));
      }
    }
  }

  Future<void> _controlPlayback(String action) async {
    final desktopBookId = _desktopBookId;
    final activeJob = _state.ttsState?.activeJob;
    if (desktopBookId == null || desktopBookId.isEmpty || activeJob == null) {
      return;
    }
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      if (action == 'pause') {
        await _audioPlayer.pause();
      }
      final state = await _controller.controlTts(
        bookId: desktopBookId,
        jobId: activeJob.jobId,
        action: action,
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: state));
      if (action == 'resume') {
        await _applyPlaybackSpeed();
        await _audioPlayer.play();
      } else if (action == 'next' || action == 'prev') {
        await _playCurrentSegment();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(error: error.toString()));
    } finally {
      if (mounted) {
        setState(() => _state = _state.copyWith(actionBusy: false));
      }
    }
  }

  Future<void> _stopJob(String jobId) async {
    final desktopBookId = _desktopBookId;
    if (desktopBookId == null || desktopBookId.isEmpty) {
      return;
    }
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      await _audioPlayer.stop();
      final state = await _controller.controlTts(
        bookId: desktopBookId,
        jobId: jobId,
        action: 'stop',
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: state));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(error: error.toString()));
    } finally {
      if (mounted) {
        setState(() => _state = _state.copyWith(actionBusy: false));
      }
    }
  }

  Future<void> _playCurrentSegment() async {
    final desktopBookId = _desktopBookId;
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (desktopBookId == null ||
        desktopBookId.isEmpty ||
        state == null ||
        activeJob == null ||
        state.activeSegments.isEmpty) {
      return;
    }
    final index = math.max(
      0,
      math.min(activeJob.currentSegmentIndex, state.activeSegments.length - 1),
    );
    final segment = state.activeSegments[index];
    var localAudioPath = await _packageRepository.getCachedAudioPath(
      localBookId: widget.localBookId,
      jobId: activeJob.jobId,
      segmentIndex: segment.segmentIndex,
    );
    if (localAudioPath == null) {
      final bytes = await widget.api.downloadTtsAudio(
        bookId: desktopBookId,
        jobId: activeJob.jobId,
        segmentIndex: segment.segmentIndex,
      );
      localAudioPath = await _packageRepository.ensureAudioFile(
        localBookId: widget.localBookId,
        jobId: activeJob.jobId,
        segmentIndex: segment.segmentIndex,
        bytes: bytes,
      );
    }
    await _audioPlayer.stop();
    await _audioPlayer.open(Media(localAudioPath), play: true);
    await _applyPlaybackSpeed();
  }

  Future<void> _handleTrackCompleted() async {
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    if (activeJob.currentSegmentIndex >= state.activeSegments.length - 1) {
      return;
    }
    try {
      final desktopBookId = _desktopBookId;
      if (desktopBookId == null || desktopBookId.isEmpty) {
        return;
      }
      final nextState = await _controller.controlTts(
        bookId: desktopBookId,
        jobId: activeJob.jobId,
        action: 'next',
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: nextState));
      final currentSegment = state.activeSegments[activeJob.currentSegmentIndex];
      final gap = Duration(milliseconds: currentSegment.pauseAfterMs);
      if (gap > Duration.zero) {
        await Future<void>.delayed(gap);
      }
      await _playCurrentSegment();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(error: error.toString()));
    }
  }

  Future<void> _savePosition(int paragraphIndex) async {
    if (_state.lastSavedParagraphIndex == paragraphIndex) {
      return;
    }
    setState(() => _state = _state.copyWith(lastSavedParagraphIndex: paragraphIndex));
    try {
      await _packageRepository.saveReaderPosition(widget.localBookId, paragraphIndex);
      final desktopBookId = _desktopBookId;
      if (desktopBookId != null && desktopBookId.isNotEmpty) {
        await _controller.saveReaderPosition(desktopBookId, paragraphIndex);
      }
    } catch (_) {}
  }

  void _handleWordTap(ParagraphItem item, ParagraphWordItem word) {
    final focusText = word.translationFocusText.trim().isNotEmpty
        ? word.translationFocusText
        : word.translationSpanText;
    setState(() {
      _state = _state.copyWith(
        selectedParagraphIndex: item.index,
        selectedTapUnitId: word.tapUnitId,
        translationLeftText: word.translationLeftText,
        translationFocusText: focusText.isNotEmpty ? focusText : word.text,
        translationRightText: word.translationRightText,
      );
    });
    _savePosition(item.index);
  }

  Future<void> _handleWordLongPress(ParagraphItem item, ParagraphWordItem word) async {
    _handleWordTap(item, word);
    DetailSheetPayload payload;
    final desktopBookId = _desktopBookId;
    if (desktopBookId != null && desktopBookId.isNotEmpty) {
      try {
        payload = await _controller.getDetailSheet(
          bookId: desktopBookId,
          wordId: word.id,
        );
      } catch (_) {
        payload = DetailSheetPayload.fromSelection(item: item, word: word);
      }
    } else {
      payload = DetailSheetPayload.fromSelection(item: item, word: word);
    }
    _logDetailSheet(item.index, word, payload);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.78,
        child: ReaderDetailSheet(
          payload: payload,
          onSaveUnit: (desktopBookId != null && desktopBookId.isNotEmpty)
              ? (unit) => _saveDetailUnit(desktopBookId, word.id, unit)
              : null,
        ),
      ),
    );
  }

  Future<String?> _saveDetailUnit(
    String bookId,
    String wordId,
    DetailSheetUnitItem unit,
  ) async {
    try {
      final result = await _controller.saveDetailUnit(
        bookId: bookId,
        wordId: wordId,
        unitId: unit.id,
      );
      final saved = result['saved'] as bool? ?? false;
      return saved ? 'Добавлено в Cards' : 'Карточка уже есть';
    } catch (error) {
      return 'Не удалось добавить: $error';
    }
  }

  void _logDetailSheet(int paragraphIndex, ParagraphWordItem word, DetailSheetPayload payload) {
    final unitsText = payload.units
        .map(
          (unit) => '[${unit.type}] text="${unit.text}" surface="${unit.surfaceText}" '
              'translation="${unit.translation}" hint="${unit.grammarHint}" morph="${unit.morphLabel}"',
        )
        .join(' | ');
    debugPrint(
      'DETAIL_SHEET_OPEN paragraph=$paragraphIndex word="${word.text}" '
      'selected_block="${payload.sheetSourceText}" block_translation="${payload.sheetTranslationText}" '
      'units=${payload.units.length} $unitsText',
    );
  }

  Future<void> _openSettings() async {
    final hasRemoteTts = (_desktopBookId?.isNotEmpty ?? false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileSettingsScreen(
          title: 'Reader settings',
          currentBookTitle: _state.payload?.title,
          busy: _state.actionBusy,
          errorText: _state.error,
          profiles: _state.ttsProfiles,
          levels: _state.ttsLevels,
          selectedVoiceId: _state.selectedVoiceId,
          selectedLevelIds: _state.selectedLevelIds,
          state: _state.ttsState,
          onVoiceChanged: hasRemoteTts
              ? (value) => setState(() => _state = _state.copyWith(selectedVoiceId: value))
              : null,
          onLevelToggle: hasRemoteTts
              ? (levelId, selected) {
                  if (!selected) {
                    return;
                  }
                  setState(() => _state = _state.copyWith(selectedLevelIds: {levelId}));
                  _applyPlaybackSpeed();
                }
              : null,
          onGenerate: hasRemoteTts ? _generateVoice : null,
          onOverwriteGenerate: hasRemoteTts ? _overwriteVoice : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = _state.payload;
    return Scaffold(
      appBar: AppBar(
        title: Text(payload?.title ?? 'Reader'),
        actions: [
          IconButton(
            onPressed: _state.loading ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: _state.loading || _state.actionBusy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _state.loading
          ? const Center(child: CircularProgressIndicator())
          : payload == null || payload.paragraphs.isEmpty
              ? Center(child: Text(_state.error ?? 'Нет данных для чтения'))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          if (_state.error != null && _state.error!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Text(
                                _state.error!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          Expanded(
                            child: ReaderTextFlow(
                              payload: payload,
                              translationLeftText: _state.translationLeftText,
                              translationFocusText: _state.translationFocusText,
                              translationRightText: _state.translationRightText,
                              selectedParagraphIndex: _state.selectedParagraphIndex,
                              selectedTapUnitId: _state.selectedTapUnitId,
                              onWordTap: _handleWordTap,
                              onWordLongPress: _handleWordLongPress,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ReaderPlaybackBar(
                        expanded: _playerExpanded,
                        hasPlayableJob: _selectedJob()?.isReady ?? false,
                        isPlaying: _state.ttsState?.activeJob?.playbackState == 'playing',
                        isPaused: _state.ttsState?.activeJob?.playbackState == 'paused',
                        busy: _state.actionBusy,
                        onToggleExpand: () => setState(() => _playerExpanded = !_playerExpanded),
                        onPlayPause: _togglePlayPause,
                        onStop: () {
                          final activeJob = _state.ttsState?.activeJob;
                          if (activeJob != null) {
                            _stopJob(activeJob.jobId);
                          }
                        },
                        onPrev: () => _controlPlayback('prev'),
                        onNext: () => _controlPlayback('next'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
