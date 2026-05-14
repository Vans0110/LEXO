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
    this.playbackRepeatMode = ReaderPlaybackRepeatMode.off,
    this.onPlaybackRepeatModeChanged,
    this.onLibraryPlaybackCompleted,
    this.autoplayVoiceId,
    this.autoplayLevelIds = const <int>{},
    this.autoplayToken = 0,
    this.onCardsChanged,
  });

  final LexoApiClient api;
  final String localBookId;
  final MobileCardsRepository cardsRepository;
  final String deviceId;
  final ReaderPlaybackRepeatMode playbackRepeatMode;
  final ValueChanged<ReaderPlaybackRepeatMode>? onPlaybackRepeatModeChanged;
  final Future<bool> Function({
    String? voiceId,
    required Set<int> selectedLevelIds,
  })? onLibraryPlaybackCompleted;
  final String? autoplayVoiceId;
  final Set<int> autoplayLevelIds;
  final int autoplayToken;
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
  bool _playingWordAudio = false;
  ReaderPlaybackRepeatMode _localPlaybackRepeatMode = ReaderPlaybackRepeatMode.off;
  int _playbackCycleToken = 0;
  int _handledAutoplayToken = 0;
  Map<String, List<TtsSegmentItem>> _localSegmentsByJobId = const {};
  Map<String, DetailSheetPayload> _detailByWordId = const {};

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

  ReaderPlaybackRepeatMode get _effectivePlaybackRepeatMode {
    return widget.onPlaybackRepeatModeChanged == null
        ? _localPlaybackRepeatMode
        : widget.playbackRepeatMode;
  }

  void _changePlaybackRepeatMode(ReaderPlaybackRepeatMode mode) {
    _playbackCycleToken += 1;
    final nextMode = widget.onLibraryPlaybackCompleted == null &&
            mode == ReaderPlaybackRepeatMode.playLibraryOnce
        ? ReaderPlaybackRepeatMode.off
        : mode;
    final handler = widget.onPlaybackRepeatModeChanged;
    if (handler != null) {
      handler(nextMode);
      return;
    }
    setState(() => _localPlaybackRepeatMode = nextMode);
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
    _playbackCycleToken += 1;
    _playlistSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MobileReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackRepeatMode != widget.playbackRepeatMode) {
      _playbackCycleToken += 1;
    }
    if (oldWidget.autoplayToken != widget.autoplayToken) {
      _maybeStartAutoplay();
    }
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
      if ((widget.autoplayVoiceId ?? '').isNotEmpty &&
          availableVoiceIds.contains(widget.autoplayVoiceId)) {
        selectedVoiceId = widget.autoplayVoiceId;
      } else if (activeVoiceId != null && availableVoiceIds.contains(activeVoiceId)) {
        selectedVoiceId = activeVoiceId;
      } else if (_state.selectedVoiceId != null &&
          availableVoiceIds.contains(_state.selectedVoiceId)) {
        selectedVoiceId = _state.selectedVoiceId;
      }

      if (widget.autoplayLevelIds.isNotEmpty) {
        final availableLevelIds = levels.map((item) => item.id).toSet();
        final requestedLevelIds = widget.autoplayLevelIds.intersection(availableLevelIds);
        if (requestedLevelIds.isNotEmpty) {
          selectedLevelIds = requestedLevelIds;
        }
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
        _detailByWordId = package.detailByWordId;
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
      await _maybeStartAutoplay();
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

  Future<void> _maybeStartAutoplay() async {
    if (widget.autoplayToken <= 0 || _handledAutoplayToken == widget.autoplayToken) {
      return;
    }
    final selectedJob = _selectedJob();
    if (selectedJob == null || !selectedJob.isReady) {
      return;
    }
    _handledAutoplayToken = widget.autoplayToken;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    await _startPlayback(selectedJob.jobId);
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
    _playbackCycleToken += 1;
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
    _playbackCycleToken += 1;
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
    if (_playingWordAudio) {
      _playingWordAudio = false;
      return;
    }
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    if (_useLocalPlayback) {
      if (activeJob.currentSegmentIndex < state.activeSegments.length - 1) {
        return;
      }
      await _handleBookCompleted(activeJob, state.jobs);
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

  Future<void> _handleBookCompleted(
    TtsJobItem activeJob,
    List<TtsJobItem> jobs,
  ) async {
    final cycleToken = ++_playbackCycleToken;
    await _audioPlayer.stop();
    if (!mounted || cycleToken != _playbackCycleToken) {
      return;
    }

    if (_effectivePlaybackRepeatMode == ReaderPlaybackRepeatMode.off) {
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
      return;
    }

    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted || cycleToken != _playbackCycleToken) {
      return;
    }

    if (_effectivePlaybackRepeatMode == ReaderPlaybackRepeatMode.repeatBook) {
      await _startPlayback(activeJob.jobId);
      return;
    }

    final openedNext = await widget.onLibraryPlaybackCompleted?.call(
          voiceId: _state.selectedVoiceId,
          selectedLevelIds: Set<int>.of(_state.selectedLevelIds),
        ) ??
        false;
    if (openedNext) {
      return;
    }
    if (!mounted || cycleToken != _playbackCycleToken) {
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
    final focusText = word.effectiveFocusText?.trim() ?? '';
    final effective = focusText.isNotEmpty ? null : buildPreferredSourceFirstFocus(item: item, word: word);
    setState(() {
      _state = _state.copyWith(
        selectedParagraphIndex: item.index,
        selectedTapUnitId: word.tapUnitId,
        translationLeftText: effective?.left ?? (word.effectiveLeftText ?? ''),
        translationFocusText: effective?.focus ?? (focusText.isNotEmpty ? focusText : word.text),
        translationRightText: effective?.right ?? (word.effectiveRightText ?? ''),
      );
    });
    _savePosition(item.index);
  }

  Future<void> _handleWordLongPress(ParagraphItem item, ParagraphWordItem word) async {
    _handleWordTap(item, word);
    final payload = _detailByWordId[word.id] ?? DetailSheetPayload.fromSelection(item: item, word: word);
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
          onSaveDictionaryCard: (translations) => _saveDictionaryCard(payload, translations),
          onPlayWordAudio: () => _playDetailWordAudio(payload),
        ),
      ),
    );
  }

  Set<String> _detailWordAudioCandidates(DetailSheetPayload payload) {
    return <String>{
      payload.dictionaryEntry?.lemma.trim() ?? '',
      ...payload.units
          .where((unit) => unit.isPrimary)
          .map((unit) => unit.lemma.trim().isNotEmpty ? unit.lemma.trim() : unit.text.trim()),
      payload.sheetSourceText.trim(),
    }..removeWhere((value) => value.isEmpty);
  }

  Future<String?> _resolveDetailWordAudioPath(DetailSheetPayload payload) async {
    final package = await _packageRepository.readPackage(widget.localBookId);
    final voiceId = package.wordAudioVoiceId.trim();
    if (voiceId.isEmpty) {
      return null;
    }
    for (final candidate in _detailWordAudioCandidates(payload)) {
      final cached = await _packageRepository.getCachedWordAudioPath(
        localBookId: widget.localBookId,
        voiceId: voiceId,
        word: candidate,
      );
      if (cached != null) {
        return cached;
      }
    }
    return null;
  }

  Future<void> _playDetailWordAudio(DetailSheetPayload payload) async {
    try {
      final audioPath = await _resolveDetailWordAudioPath(payload);
      if (audioPath == null || audioPath.trim().isEmpty) {
        throw Exception('Локальный word audio не найден. Выполните Синхронизацию книги.');
      }
      _playbackCycleToken += 1;
      await _audioPlayer.stop();
      _useLocalPlayback = false;
      _playingWordAudio = true;
      await _audioPlayer.open(Media(audioPath), play: true);
      await _audioPlayer.setRate(1.0);
    } catch (error) {
      _playingWordAudio = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось озвучить слово: $error')),
      );
    }
  }

  Future<void> _saveDictionaryCard(DetailSheetPayload payload, List<String> translations) async {
    try {
      await widget.cardsRepository.saveDictionaryCard(
        deviceId: widget.deviceId,
        originBookId: _desktopBookId ?? widget.localBookId,
        payload: payload,
        translations: translations,
      );
      widget.onCardsChanged?.call();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Карточка добавлена')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить карточку: $error')),
      );
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
      'units=${payload.units.length} source_first=${payload.sourceFirst?.analysisVersion ?? ''} $unitsText',
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
                        onRepeatModeTap: () => _changePlaybackRepeatMode(
                          _effectivePlaybackRepeatMode.next,
                        ),
                        speedLabel: _speedLabel(),
                        repeatMode: _effectivePlaybackRepeatMode,
                      ),
                    ),
                  ],
                ),
    );
  }
}
