import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../api/api_client.dart';
import '../detail_sheet_models.dart';
import '../features/reader/reader_feature.dart';
import '../models.dart';
import '../widgets/reader_detail_sheet.dart';
import '../widgets/reader_text_flow.dart';
import '../widgets/reader_playback_bar.dart';
import '../widgets/tts_panel.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.api, required this.bookId});

  final LexoApiClient api;
  final String bookId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const Duration _pollInterval = Duration(seconds: 1);

  late final ReaderFeatureController _controller;
  ReaderFeatureState _state = const ReaderFeatureState();
  late final Player _audioPlayer;
  Timer? _pollTimer;
  bool _playerExpanded = true;

  double _selectedPlaybackSpeed() {
    final selectedLevel = _selectedLevel();
    return selectedLevel?.effectivePlaybackSpeed ?? 1.0;
  }

  TtsLevel? _selectedLevel() {
    final selectedId = _state.selectedLevelIds.isEmpty ? null : _state.selectedLevelIds.first;
    if (selectedId == null) {
      return null;
    }
    for (final level in _state.ttsLevels) {
      if (level.id == selectedId) {
        return level;
      }
    }
    return null;
  }

  String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(0)}x';
    }
    if ((speed * 10) % 10 == 0) {
      return '${speed.toStringAsFixed(1)}x';
    }
    return '${speed.toStringAsFixed(2)}x';
  }

  String _speedLabel() {
    final selectedLevel = _selectedLevel();
    return _formatSpeed(selectedLevel?.playbackSpeed ?? 1.0);
  }

  String _requiredAudioVariant() {
    return _selectedLevel()?.audioVariant ?? 'base';
  }

  Future<void> _applyPlaybackSpeed() async {
    await _audioPlayer.setRate(_selectedPlaybackSpeed());
  }

  Future<void> _showSpeedPicker() async {
    if (_state.ttsLevels.isEmpty) {
      return;
    }
    final selectedId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Скорость'),
        children: [
          for (final level in _state.ttsLevels)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(level.id),
              child: Row(
                children: [
                  Expanded(child: Text('${level.name} ${_formatSpeed(level.playbackSpeed)}')),
                  if (level.id == _selectedLevel()?.id) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (selectedId == null) {
      return;
    }
    setState(() => _state = _state.copyWith(selectedLevelIds: {selectedId}));
    await _applyPlaybackSpeed();
  }

  TtsJobItem? _selectedJob() {
    final voiceId = _state.selectedVoiceId;
    if (voiceId == null) {
      return null;
    }
    final requiredAudioVariant = _requiredAudioVariant();
    for (final job in _state.ttsState?.jobs ?? const <TtsJobItem>[]) {
      if (job.voiceId == voiceId && job.audioVariant == requiredAudioVariant) {
        return job;
      }
    }
    return null;
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
    developer.log('Loading reader payload', name: 'LEXO_UI');
    setState(() {
      _state = _state.copyWith(
        loading: true,
        clearError: true,
      );
    });
    try {
      final result = await _controller.load(widget.bookId);
      if (!mounted) {
        return;
      }
      final availableVoiceIds = result.ttsProfiles.map((item) => item.voiceId).toSet();
      final activeVoiceId = result.ttsState.activeJob?.voiceId;
      String? selectedVoiceId;
      if (activeVoiceId != null && availableVoiceIds.contains(activeVoiceId)) {
        selectedVoiceId = activeVoiceId;
      } else if (_state.selectedVoiceId != null && availableVoiceIds.contains(_state.selectedVoiceId)) {
        selectedVoiceId = _state.selectedVoiceId;
      } else {
        selectedVoiceId = result.ttsProfiles.isNotEmpty ? result.ttsProfiles.first.voiceId : null;
      }
      var selectedLevelIds = _state.selectedLevelIds;
      final hasSelectedLevel = result.ttsLevels.any(
        (item) => selectedLevelIds.isNotEmpty && item.id == selectedLevelIds.first,
      );
      if (result.ttsLevels.isNotEmpty && (!hasSelectedLevel || selectedLevelIds.isEmpty)) {
        final normal = result.ttsLevels.where((item) => item.name == 'Normal');
        selectedLevelIds = {normal.isNotEmpty ? normal.first.id : result.ttsLevels.first.id};
      }
      TtsPackageState? packageState = result.ttsPackageState;
      if (selectedVoiceId != null &&
          selectedVoiceId.isNotEmpty &&
          packageState?.voiceId != selectedVoiceId) {
        try {
          packageState = await _controller.refreshTtsPackageState(
            bookId: widget.bookId,
            voiceId: selectedVoiceId,
          );
        } catch (_) {
          packageState = result.ttsPackageState;
        }
      }
      setState(() {
        _state = _state.copyWith(
          payload: result.payload,
          ttsProfiles: result.ttsProfiles,
          ttsLevels: result.ttsLevels,
          ttsState: result.ttsState,
          ttsPackageState: packageState,
          selectedVoiceId: selectedVoiceId,
          selectedLevelIds: selectedLevelIds,
          loading: false,
        );
      });
      await _applyPlaybackSpeed();
      _syncPolling(result.ttsState, packageState);
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
    try {
      final nextState = await _controller.refreshTtsState(widget.bookId);
      if (!mounted) {
        return;
      }
      TtsPackageState? nextPackageState = _state.ttsPackageState;
      final voiceId = _state.selectedVoiceId;
      if (voiceId != null && voiceId.isNotEmpty) {
        try {
          nextPackageState = await _controller.refreshTtsPackageState(
            bookId: widget.bookId,
            voiceId: voiceId,
          );
        } catch (_) {
          // Не ломаем polling package state из-за временной ошибки.
        }
      }
      setState(() => _state = _state.copyWith(ttsState: nextState, ttsPackageState: nextPackageState));
      _syncPolling(nextState, nextPackageState);
    } catch (_) {
      // Не ломаем экран из-за временной ошибки polling.
    }
  }

  void _syncPolling(TtsState? state, TtsPackageState? packageState) {
    if ((state?.hasGeneratingJobs ?? false) || (packageState?.isRunning ?? false)) {
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

  Future<void> _runGenerateVoice({required bool overwrite}) async {
    final voiceId = _state.selectedVoiceId;
    if (voiceId == null || _state.selectedLevelIds.isEmpty) {
      return;
    }
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      await _audioPlayer.stop();
      final packageState = await _controller.generateTtsPackage(
        bookId: widget.bookId,
        voiceId: voiceId,
        overwrite: overwrite,
        overwriteWordAudio: overwrite,
      );
      final state = await _controller.refreshTtsState(widget.bookId);
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(ttsState: state, ttsPackageState: packageState));
      _syncPolling(state, packageState);
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
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      await _audioPlayer.stop();
      final state = await _controller.startTtsPlayback(
        bookId: widget.bookId,
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
    final activeJob = _state.ttsState?.activeJob;
    if (activeJob == null) {
      return;
    }
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      if (action == 'pause') {
        await _audioPlayer.pause();
      }
      final state = await _controller.controlTts(
        bookId: widget.bookId,
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
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      await _audioPlayer.stop();
      final state = await _controller.controlTts(
        bookId: widget.bookId,
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
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    final index = math.max(
      0,
      math.min(activeJob.currentSegmentIndex, state.activeSegments.length - 1),
    );
    final segment = state.activeSegments[index];
    final file = File(segment.audioPath);
    if (!file.existsSync()) {
      throw Exception('Audio file not found: ${segment.audioPath}');
    }
    await _audioPlayer.stop();
    await _audioPlayer.open(Media(segment.audioPath), play: true);
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
      final nextState = await _controller.controlTts(
        bookId: widget.bookId,
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
    developer.log('Saving reader position: $paragraphIndex', name: 'LEXO_UI');
    try {
      await _controller.saveReaderPosition(widget.bookId, paragraphIndex);
    } catch (_) {
      // Не прерываем чтение из-за ошибки сохранения позиции.
    }
  }

  void _handleWordTap(ParagraphItem item, ParagraphWordItem word) {
    final focusText = word.unitTranslationFocusText.trim().isNotEmpty
        ? word.unitTranslationFocusText
        : (word.unitTranslationSpanText.trim().isNotEmpty
              ? word.unitTranslationSpanText
              : (word.translationFocusText.trim().isNotEmpty
                    ? word.translationFocusText
                    : word.translationSpanText));
    setState(() {
      _state = _state.copyWith(
        selectedParagraphIndex: item.index,
        selectedTapUnitId: word.tapUnitId,
        translationLeftText: word.unitTranslationLeftText.trim().isNotEmpty
            ? word.unitTranslationLeftText
            : word.translationLeftText,
        translationFocusText: focusText.isNotEmpty ? focusText : word.text,
        translationRightText: word.unitTranslationRightText.trim().isNotEmpty
            ? word.unitTranslationRightText
            : word.translationRightText,
      );
    });
    _savePosition(item.index);
  }

  Future<void> _handleWordLongPress(ParagraphItem item, ParagraphWordItem word) async {
    _handleWordTap(item, word);
    DetailSheetPayload payload;
    try {
      payload = await _controller.getDetailSheet(
        bookId: widget.bookId,
        wordId: word.id,
      );
    } catch (_) {
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
        heightFactor: 0.72,
        child: ReaderDetailSheet(
          payload: payload,
          onSaveUnit: (unit) => _saveDetailUnit(word.id, unit),
        ),
      ),
    );
  }

  Future<String?> _saveDetailUnit(String wordId, DetailSheetUnitItem unit) async {
    try {
      final result = await _controller.saveDetailUnit(
        bookId: widget.bookId,
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

  @override
  Widget build(BuildContext context) {
    final payload = _state.payload;
    final ttsState = _state.ttsState;
    return Scaffold(
      appBar: AppBar(
        title: Text(payload?.title ?? 'Reader'),
        actions: [
          IconButton(
            onPressed: _state.loading || _state.actionBusy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _state.loading
          ? const Center(child: CircularProgressIndicator())
          : _state.error != null
              ? Center(child: Text(_state.error!))
              : payload == null || payload.paragraphs.isEmpty
                  ? const Center(child: Text('Нет данных для чтения'))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 20, 0, 20),
                          child: TtsPanel(
                            profiles: _state.ttsProfiles,
                            levels: _state.ttsLevels,
                            selectedVoiceId: _state.selectedVoiceId,
                            selectedLevelIds: _state.selectedLevelIds,
                            state: ttsState,
                            packageState: _state.ttsPackageState,
                            busy: _state.actionBusy,
                            onVoiceChanged: (value) async {
                              setState(() => _state = _state.copyWith(selectedVoiceId: value));
                              if (value == null || value.isEmpty) {
                                return;
                              }
                              try {
                                final packageState = await _controller.refreshTtsPackageState(
                                  bookId: widget.bookId,
                                  voiceId: value,
                                );
                                if (!mounted) {
                                  return;
                                }
                                setState(() => _state = _state.copyWith(ttsPackageState: packageState));
                                _syncPolling(_state.ttsState, packageState);
                              } catch (_) {
                                // Не ломаем выбор голоса из-за package-state.
                              }
                            },
                            onLevelToggle: (levelId, selected) {
                              if (!selected) {
                                return;
                              }
                              setState(() => _state = _state.copyWith(selectedLevelIds: {levelId}));
                              _applyPlaybackSpeed();
                            },
                            onGenerate: _generateVoice,
                            onOverwriteGenerate: _overwriteVoice,
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
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
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: ReaderPlaybackBar(
                                  expanded: _playerExpanded,
                                  hasPlayableJob: _selectedJob()?.isReady ?? false,
                                  isPlaying: ttsState?.activeJob?.playbackState == 'playing',
                                  isPaused: ttsState?.activeJob?.playbackState == 'paused',
                                  busy: _state.actionBusy,
                                  onToggleExpand: () =>
                                      setState(() => _playerExpanded = !_playerExpanded),
                                  onPlayPause: _togglePlayPause,
                                  onStop: () {
                                    final activeJob = _state.ttsState?.activeJob;
                                    if (activeJob != null) {
                                      _stopJob(activeJob.jobId);
                                    }
                                  },
                                  onPrev: () => _controlPlayback('prev'),
                                  onNext: () => _controlPlayback('next'),
                                  onSpeedTap: _showSpeedPicker,
                                  onSpeedLongPress: _showSpeedPicker,
                                  speedLabel: _speedLabel(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}
