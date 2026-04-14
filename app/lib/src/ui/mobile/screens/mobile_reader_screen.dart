import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../api/api_client.dart';
import '../../../detail_sheet_models.dart';
import '../../../features/reader/reader_feature.dart';
import '../../../mobile/mobile_cards_repository.dart';
import '../../../mobile/mobile_package_repository.dart';
import '../../../models.dart';
import '../../../widgets/reader_detail_sheet.dart';
import '../../../widgets/reader_playback_bar.dart';
import '../../../widgets/reader_text_flow.dart';

class MobileReaderScreen extends StatefulWidget {
  const MobileReaderScreen({
    super.key,
    required this.api,
    required this.localBookId,
    required this.cardsRepository,
    required this.deviceId,
    this.onCardsChanged,
  });

  final LexoApiClient api;
  final String localBookId;
  final MobileCardsRepository cardsRepository;
  final String deviceId;
  final VoidCallback? onCardsChanged;

  @override
  State<MobileReaderScreen> createState() => _MobileReaderScreenState();
}

class _MobileReaderScreenState extends State<MobileReaderScreen> {
  late final MobileBookPackageRepository _packageRepository;
  late final Player _audioPlayer;
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;

  ReaderFeatureState _state = const ReaderFeatureState();
  String? _desktopBookId;
  bool _playerExpanded = true;
  bool _useLocalPlayback = false;
  Map<String, List<TtsSegmentItem>> _localSegmentsByJobId = const {};

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

  Future<void> _applyPlaybackSpeed() async {
    await _audioPlayer.setRate(_selectedPlaybackSpeed());
  }

  String _requiredAudioVariant() {
    return _selectedLevel()?.audioVariant ?? 'base';
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
    _packageRepository = MobileBookPackageRepository();
    _audioPlayer = Player();
    _playlistSubscription = _audioPlayer.stream.playlist.listen((playlist) {
      if (mounted) {
        _syncLocalPlaybackFromPlaylist(playlist);
      }
    });
    _playingSubscription = _audioPlayer.stream.playing.listen((playing) {
      if (mounted) {
        _syncLocalPlaybackPlaying(playing);
      }
    });
    _completedSubscription = _audioPlayer.stream.completed.listen((completed) {
      if (mounted && completed) {
        _handleTrackCompleted();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _playlistSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    developer.log('Loading local mobile reader payload', name: 'LEXO_UI');
    setState(() => _state = _state.copyWith(loading: true, clearError: true));
    try {
      final package = await _packageRepository.readPackage(widget.localBookId);
      final desktopBookId = package.meta.desktopBookId;
      List<TtsProfile> profiles = package.profiles;
      List<TtsLevel> levels = package.levels;
      final ttsState = package.ttsState;
      String? selectedVoiceId = profiles.isNotEmpty ? profiles.first.voiceId : null;
      var selectedLevelIds = _state.selectedLevelIds;
      final availableVoiceIds = profiles.map((item) => item.voiceId).toSet();
      final activeVoiceId = ttsState.activeJob?.voiceId;
      if (activeVoiceId != null && availableVoiceIds.contains(activeVoiceId)) {
        selectedVoiceId = activeVoiceId;
      } else if (_state.selectedVoiceId != null &&
          availableVoiceIds.contains(_state.selectedVoiceId)) {
        selectedVoiceId = _state.selectedVoiceId;
      }

      final hasSelectedLevel = levels.any(
        (item) => selectedLevelIds.isNotEmpty && item.id == selectedLevelIds.first,
      );
      if (levels.isNotEmpty && (!hasSelectedLevel || selectedLevelIds.isEmpty)) {
        final normal = levels.where((item) => item.name == 'Normal');
        selectedLevelIds = {normal.isNotEmpty ? normal.first.id : levels.first.id};
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _desktopBookId = desktopBookId;
        _localSegmentsByJobId = package.segmentsByJobId;
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

  Future<void> _generateVoice() async {
    setState(() {
      _state = _state.copyWith(
        error: 'Генерация TTS выполняется только через Синхронизацию с host',
      );
    });
  }

  Future<void> _overwriteVoice() async {
    setState(() {
      _state = _state.copyWith(
        error: 'Обновление TTS выполняется только через Синхронизацию с host',
      );
    });
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

  TtsJobItem _copyJob(
    TtsJobItem job, {
    String? playbackState,
    int? currentSegmentIndex,
    int? currentSegmentNumber,
    double? playbackProgress,
  }) {
    return TtsJobItem(
      jobId: job.jobId,
      levelId: job.levelId,
      levelName: job.levelName,
      targetWpm: job.targetWpm,
      audioVariant: job.audioVariant,
      nativeRate: job.nativeRate,
      rate: job.rate,
      pauseScale: job.pauseScale,
      voiceId: job.voiceId,
      status: job.status,
      playbackState: playbackState ?? job.playbackState,
      currentSegmentIndex: currentSegmentIndex ?? job.currentSegmentIndex,
      totalSegments: job.totalSegments,
      readySegments: job.readySegments,
      generationProgress: job.generationProgress,
      currentSegmentNumber: currentSegmentNumber ?? job.currentSegmentNumber,
      playbackProgress: playbackProgress ?? job.playbackProgress,
      errorMessage: job.errorMessage,
    );
  }

  Future<List<String>?> _collectLocalPlaylistPaths(
    String jobId,
    List<TtsSegmentItem> segments,
  ) async {
    if (jobId.isEmpty || segments.isEmpty) {
      return null;
    }
    final paths = <String>[];
    for (final segment in segments) {
      final cached = await _packageRepository.getCachedAudioPath(
        localBookId: widget.localBookId,
        jobId: jobId,
        segmentIndex: segment.segmentIndex,
      );
      if (cached == null) {
        return null;
      }
      paths.add(cached);
    }
    return paths;
  }

  void _syncLocalPlaybackFromPlaylist(Playlist playlist) {
    if (!_useLocalPlayback) {
      return;
    }
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    final index = math.max(
      0,
      math.min(playlist.index, state.activeSegments.length - 1),
    );
    final nextJob = _copyJob(
      activeJob,
      currentSegmentIndex: index,
      currentSegmentNumber: math.min(index + 1, activeJob.totalSegments),
      playbackProgress: activeJob.totalSegments > 0 ? ((index + 1) / activeJob.totalSegments) : 0,
    );
    if (nextJob.currentSegmentIndex == activeJob.currentSegmentIndex &&
        nextJob.currentSegmentNumber == activeJob.currentSegmentNumber &&
        nextJob.playbackProgress == activeJob.playbackProgress) {
      return;
    }
    setState(() {
      _state = _state.copyWith(
        ttsState: TtsState(
          jobs: state.jobs,
          activeJob: nextJob,
          activeSegments: state.activeSegments,
        ),
      );
    });
  }

  void _syncLocalPlaybackPlaying(bool playing) {
    if (!_useLocalPlayback) {
      return;
    }
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    final nextPlaybackState = playing ? 'playing' : 'paused';
    if (activeJob.playbackState == nextPlaybackState) {
      return;
    }
    setState(() {
      _state = _state.copyWith(
        ttsState: TtsState(
          jobs: state.jobs,
          activeJob: _copyJob(activeJob, playbackState: nextPlaybackState),
          activeSegments: state.activeSegments,
        ),
      );
    });
  }

  Future<void> _runGenerateVoice({required bool overwrite}) async {
    final selectedJob = _selectedJob();
    if (overwrite && selectedJob != null) {
      await _packageRepository.deleteJobAudio(
        localBookId: widget.localBookId,
        jobId: selectedJob.jobId,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _state = _state.copyWith(
        error: 'Генерация TTS выполняется только через Синхронизацию с host',
      );
    });
  }

  Future<void> _startPlayback(String jobId) async {
    final localSegments = _localSegmentsByJobId[jobId] ?? const <TtsSegmentItem>[];
    final localAudioPaths = await _collectLocalPlaylistPaths(jobId, localSegments);
    if (localSegments.isNotEmpty && localAudioPaths != null && localAudioPaths.length == localSegments.length) {
      final selectedJob = _selectedJob();
      if (selectedJob == null || selectedJob.jobId != jobId) {
        return;
      }
      final playlist = Playlist([
        for (final path in localAudioPaths) Media(path),
      ]);
      setState(() {
        _useLocalPlayback = true;
        _state = _state.copyWith(
          ttsState: TtsState(
            jobs: _state.ttsState?.jobs ?? const <TtsJobItem>[],
            activeJob: TtsJobItem(
              jobId: selectedJob.jobId,
              levelId: selectedJob.levelId,
              levelName: selectedJob.levelName,
              targetWpm: selectedJob.targetWpm,
              audioVariant: selectedJob.audioVariant,
              nativeRate: selectedJob.nativeRate,
              rate: selectedJob.rate,
              pauseScale: selectedJob.pauseScale,
              voiceId: selectedJob.voiceId,
              status: selectedJob.status,
              playbackState: 'playing',
              currentSegmentIndex: 0,
              totalSegments: selectedJob.totalSegments,
              readySegments: selectedJob.readySegments,
              generationProgress: selectedJob.generationProgress,
              currentSegmentNumber: 1,
              playbackProgress: selectedJob.totalSegments > 0 ? 1 / selectedJob.totalSegments : 0,
              errorMessage: selectedJob.errorMessage,
            ),
            activeSegments: localSegments,
          ),
        );
      });
      await _audioPlayer.stop();
      await _audioPlayer.setPlaylistMode(PlaylistMode.none);
      await _audioPlayer.open(playlist, play: true);
      await _applyPlaybackSpeed();
      return;
    }
    setState(() {
      _state = _state.copyWith(
        error: 'Для этого голоса нет локального audio. Выполните Синхронизацию.',
      );
    });
  }

  Future<void> _controlPlayback(String action) async {
    final activeJob = _state.ttsState?.activeJob;
    if (activeJob == null) {
      return;
    }
    if (_useLocalPlayback) {
      if (action == 'pause') {
        await _audioPlayer.pause();
      } else if (action == 'resume') {
        await _applyPlaybackSpeed();
        await _audioPlayer.play();
      } else if (action == 'next' || action == 'prev') {
        if (action == 'next') {
          await _audioPlayer.next();
        } else {
          await _audioPlayer.previous();
        }
      }
      return;
    }
    setState(() {
      _state = _state.copyWith(
        error: 'Playback доступен только для локально синхронизированного audio',
      );
    });
  }

  Future<void> _stopJob(String jobId) async {
    await _audioPlayer.stop();
    final jobs = _state.ttsState?.jobs ?? const <TtsJobItem>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _useLocalPlayback = false;
      _state = _state.copyWith(
        ttsState: TtsState(
          jobs: jobs,
          activeJob: null,
          activeSegments: const <TtsSegmentItem>[],
        ),
      );
    });
  }

  Future<void> _handleTrackCompleted() async {
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    if (_useLocalPlayback) {
      if (activeJob.currentSegmentIndex < state.activeSegments.length - 1) {
        return;
      }
      await _audioPlayer.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _useLocalPlayback = false;
        _state = _state.copyWith(
          ttsState: TtsState(
            jobs: state.jobs,
            activeJob: null,
            activeSegments: const <TtsSegmentItem>[],
          ),
        );
      });
      return;
    }
    await _audioPlayer.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _useLocalPlayback = false;
      _state = _state.copyWith(
        error: 'Playback остановлен: локальный audio для продолжения недоступен',
        ttsState: TtsState(
          jobs: state.jobs,
          activeJob: null,
          activeSegments: const <TtsSegmentItem>[],
        ),
      );
    });
  }

  String _speedLabel() {
    final selectedLevel = _selectedLevel();
    return _formatSpeed(selectedLevel?.playbackSpeed ?? 1.0);
  }

  Future<void> _showSpeedPicker() async {
    if (_state.ttsLevels.isEmpty) {
      return;
    }
    final selectedId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final level in _state.ttsLevels)
              ListTile(
                title: Text('${level.name} ${_formatSpeed(level.playbackSpeed)}'),
                trailing: level.id == _selectedLevel()?.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(level.id),
              ),
          ],
        ),
      ),
    );
    if (selectedId == null) {
      return;
    }
    setState(() => _state = _state.copyWith(selectedLevelIds: {selectedId}));
    await _applyPlaybackSpeed();
  }

  Future<void> _savePosition(int paragraphIndex) async {
    if (_state.lastSavedParagraphIndex == paragraphIndex) {
      return;
    }
    setState(() => _state = _state.copyWith(lastSavedParagraphIndex: paragraphIndex));
    try {
      await _packageRepository.saveReaderPosition(widget.localBookId, paragraphIndex);
    } catch (_) {}
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
    final payload = DetailSheetPayload.fromSelection(item: item, word: word);
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
          onSaveUnit: (unit) => _saveDetailUnit(unit),
        ),
      ),
    );
  }

  Future<String?> _saveDetailUnit(DetailSheetUnitItem unit) async {
    try {
      final originBookId = (_desktopBookId != null && _desktopBookId!.isNotEmpty)
          ? _desktopBookId!
          : widget.localBookId;
      final result = await widget.cardsRepository.saveDetailUnit(
        deviceId: widget.deviceId,
        originBookId: originBookId,
        unit: unit,
      );
      widget.onCardsChanged?.call();
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
                        onSpeedTap: _showSpeedPicker,
                        onSpeedLongPress: _showSpeedPicker,
                        speedLabel: _speedLabel(),
                      ),
                    ),
                  ],
                ),
    );
  }
}
