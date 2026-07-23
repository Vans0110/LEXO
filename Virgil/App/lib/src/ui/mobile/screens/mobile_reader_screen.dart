import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../api/api_client.dart';
import '../../../detail_sheet_models.dart';
import '../../../features/reader/reader_feature.dart';
import '../../../mobile/mobile_cards_repository.dart';
import '../../../mobile/mobile_audio_handler.dart';
import '../../../mobile/mobile_package_models.dart';
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
    this.libraryPlaybackQueue = const <String>[],
    this.onPlaybackRepeatModeChanged,
    this.onLibraryPlaybackCompleted,
    this.preferredVoiceId = 'af_heart',
    this.autoplayVoiceId,
    this.autoplayLevelIds = const <int>{},
    this.autoplayToken = 0,
    this.onCardsChanged,
    this.preferredPlaybackSpeed = 0.8,
  });

  final LexoApiClient api;
  final String localBookId;
  final MobileCardsRepository cardsRepository;
  final String deviceId;
  final ReaderPlaybackRepeatMode playbackRepeatMode;
  final List<String> libraryPlaybackQueue;
  final ValueChanged<ReaderPlaybackRepeatMode>? onPlaybackRepeatModeChanged;
  final Future<bool> Function({
    String? voiceId,
    required Set<int> selectedLevelIds,
  })? onLibraryPlaybackCompleted;
  final String preferredVoiceId;
  final double preferredPlaybackSpeed;
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
  StreamSubscription<audio_service.MediaItem?>? _backgroundMediaSubscription;
  StreamSubscription<audio_service.PlaybackState>?
      _backgroundPlaybackSubscription;
  audio_service.MediaItem? _pendingBackgroundMediaItem;

  ReaderFeatureState _state =
      const ReaderFeatureState(selectedLevelIds: <int>{});
  String? _desktopBookId;
  bool _playerExpanded = true;
  bool _useLocalPlayback = false;
  bool _playingWordAudio = false;
  bool _handlingBackgroundCompletion = false;
  ReaderPlaybackRepeatMode _localPlaybackRepeatMode =
      ReaderPlaybackRepeatMode.off;
  int _playbackCycleToken = 0;
  int _handledAutoplayToken = 0;
  Map<String, List<TtsSegmentItem>> _localSegmentsByJobId = const {};
  Map<String, DetailSheetPayload> _detailByWordId = const {};

  double _selectedPlaybackSpeed() {
    final selectedLevel = _selectedLevel();
    return selectedLevel == null
        ? widget.preferredPlaybackSpeed
        : _playbackSpeedForLevel(selectedLevel);
  }

  double _playbackSpeedForLevel(TtsLevel level) {
    if (level.playbackSpeed < 0.95) {
      return 0.8;
    }
    return level.effectivePlaybackSpeed;
  }

  TtsLevel? _selectedLevel() {
    final selectedId =
        _state.selectedLevelIds.isEmpty ? null : _state.selectedLevelIds.first;
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
    if ((speed * 10).round() == speed * 10) {
      return '${speed.toStringAsFixed(1)}x';
    }
    return '${speed.toStringAsFixed(2)}x';
  }

  Future<void> _applyPlaybackSpeed() async {
    await _audioPlayer.setRate(_selectedPlaybackSpeed());
    await LexoBackgroundAudio.handler?.setSpeed(_selectedPlaybackSpeed());
  }

  String _requiredAudioVariant() {
    return _selectedLevel()?.audioVariant ?? 'base';
  }

  ReaderPlaybackRepeatMode get _effectivePlaybackRepeatMode {
    return widget.onPlaybackRepeatModeChanged == null
        ? _localPlaybackRepeatMode
        : widget.playbackRepeatMode;
  }

  PlaylistMode _nativePlaylistModeFor(ReaderPlaybackRepeatMode mode) {
    return mode == ReaderPlaybackRepeatMode.repeatBook
        ? PlaylistMode.loop
        : PlaylistMode.none;
  }

  void _changePlaybackRepeatMode(ReaderPlaybackRepeatMode mode) {
    _playbackCycleToken += 1;
    final nextMode = widget.onLibraryPlaybackCompleted == null &&
            mode == ReaderPlaybackRepeatMode.playLibraryOnce
        ? ReaderPlaybackRepeatMode.off
        : mode;
    unawaited(_audioPlayer.setPlaylistMode(_nativePlaylistModeFor(nextMode)));
    unawaited(
      LexoBackgroundAudio.handler?.setRepeatBook(
              nextMode == ReaderPlaybackRepeatMode.repeatBook) ??
          Future<void>.value(),
    );
    final handler = widget.onPlaybackRepeatModeChanged;
    if (handler != null) {
      handler(nextMode);
      return;
    }
    setState(() => _localPlaybackRepeatMode = nextMode);
    if (nextMode == ReaderPlaybackRepeatMode.repeatBook ||
        nextMode == ReaderPlaybackRepeatMode.playLibraryOnce) {
      unawaited(_rebuildBackgroundQueueForActiveJob(repeatMode: nextMode));
    }
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
    final backgroundHandler = LexoBackgroundAudio.handler;
    _backgroundMediaSubscription = backgroundHandler?.mediaItem.listen((item) {
      if (mounted) {
        _syncBackgroundMediaItem(item);
      }
    });
    _backgroundPlaybackSubscription =
        backgroundHandler?.playbackState.listen((state) {
      if (mounted) {
        _syncBackgroundPlaybackState(state);
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
    _backgroundMediaSubscription?.cancel();
    _backgroundPlaybackSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MobileReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackRepeatMode != widget.playbackRepeatMode) {
      _playbackCycleToken += 1;
      unawaited(
        _audioPlayer.setPlaylistMode(
            _nativePlaylistModeFor(_effectivePlaybackRepeatMode)),
      );
      unawaited(
        LexoBackgroundAudio.handler?.setRepeatBook(
              _effectivePlaybackRepeatMode ==
                  ReaderPlaybackRepeatMode.repeatBook,
            ) ??
            Future<void>.value(),
      );
    }
    if ((oldWidget.playbackRepeatMode != widget.playbackRepeatMode ||
            oldWidget.libraryPlaybackQueue != widget.libraryPlaybackQueue) &&
        (_effectivePlaybackRepeatMode == ReaderPlaybackRepeatMode.repeatBook ||
            _effectivePlaybackRepeatMode ==
                ReaderPlaybackRepeatMode.playLibraryOnce)) {
      unawaited(
        _rebuildBackgroundQueueForActiveJob(
          repeatMode: _effectivePlaybackRepeatMode,
        ),
      );
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
      String? selectedVoiceId =
          profiles.isNotEmpty ? profiles.first.voiceId : null;
      var selectedLevelIds = _state.selectedLevelIds;
      final availableVoiceIds = profiles.map((item) => item.voiceId).toSet();
      final activeVoiceId = ttsState.activeJob?.voiceId;
      final requestedVoiceId = (widget.autoplayVoiceId ?? '').trim();
      final preferredVoiceId = widget.preferredVoiceId.trim();
      final packageVoiceId = (package.meta.selectedVoiceId ?? '').trim();
      final previousVoiceId = (_state.selectedVoiceId ?? '').trim();
      if (requestedVoiceId.isNotEmpty &&
          availableVoiceIds.contains(requestedVoiceId)) {
        selectedVoiceId = requestedVoiceId;
      } else if (preferredVoiceId.isNotEmpty &&
          availableVoiceIds.contains(preferredVoiceId)) {
        selectedVoiceId = preferredVoiceId;
      } else if (packageVoiceId.isNotEmpty &&
          availableVoiceIds.contains(packageVoiceId)) {
        selectedVoiceId = packageVoiceId;
      } else if (previousVoiceId.isNotEmpty &&
          availableVoiceIds.contains(previousVoiceId)) {
        selectedVoiceId = previousVoiceId;
      } else if (activeVoiceId != null &&
          availableVoiceIds.contains(activeVoiceId)) {
        selectedVoiceId = activeVoiceId;
      }

      if (widget.autoplayLevelIds.isNotEmpty) {
        final availableLevelIds = levels.map((item) => item.id).toSet();
        final requestedLevelIds =
            widget.autoplayLevelIds.intersection(availableLevelIds);
        if (requestedLevelIds.isNotEmpty) {
          selectedLevelIds = requestedLevelIds;
        }
      }
      final hasSelectedLevel = levels.any(
        (item) =>
            selectedLevelIds.isNotEmpty && item.id == selectedLevelIds.first,
      );
      if (levels.isNotEmpty &&
          (!hasSelectedLevel || selectedLevelIds.isEmpty)) {
        final preferredLevel = _closestLevelForSpeed(
          levels,
          widget.preferredPlaybackSpeed,
        );
        selectedLevelIds = {preferredLevel.id};
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
      final pendingBackgroundMediaItem = _pendingBackgroundMediaItem;
      if (pendingBackgroundMediaItem != null) {
        _pendingBackgroundMediaItem = null;
        _syncBackgroundMediaItem(pendingBackgroundMediaItem);
      }
      await _applyPlaybackSpeed();
      await _maybeStartAutoplay();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() =>
          _state = _state.copyWith(loading: false, error: error.toString()));
    } finally {
      if (mounted && _state.loading) {
        setState(() => _state = _state.copyWith(loading: false));
      }
    }
  }

  Future<void> _maybeStartAutoplay() async {
    if (widget.autoplayToken <= 0 ||
        _handledAutoplayToken == widget.autoplayToken) {
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
    return _collectLocalPlaylistPathsForBook(
        widget.localBookId, jobId, segments);
  }

  Future<List<String>?> _collectLocalPlaylistPathsForBook(
    String localBookId,
    String jobId,
    List<TtsSegmentItem> segments,
  ) async {
    if (jobId.isEmpty || segments.isEmpty) {
      return null;
    }
    final paths = <String>[];
    for (final segment in segments) {
      final cached = await _packageRepository.getCachedAudioPath(
        localBookId: localBookId,
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

  TtsJobItem? _findPlayableJobForPackage(
      MobileBookPackage package, TtsJobItem selectedJob) {
    for (final job in package.ttsState.jobs) {
      if (job.voiceId == selectedJob.voiceId &&
          job.audioVariant == selectedJob.audioVariant &&
          job.isReady) {
        return job;
      }
    }
    return null;
  }

  Future<LexoPlaybackRequest> _buildBackgroundPlaybackRequest({
    required TtsJobItem selectedJob,
    required List<TtsSegmentItem> localSegments,
    required List<String> localAudioPaths,
    ReaderPlaybackRepeatMode? repeatMode,
    int initialIndex = 0,
  }) async {
    final effectiveRepeatMode = repeatMode ?? _effectivePlaybackRepeatMode;
    final segments = <LexoPlaybackSegment>[
      ..._buildPlaybackSegments(
        localBookId: widget.localBookId,
        title: _state.payload?.title ?? selectedJob.levelName,
        job: selectedJob,
        localSegments: localSegments,
        localAudioPaths: localAudioPaths,
      ),
    ];

    if (effectiveRepeatMode == ReaderPlaybackRepeatMode.playLibraryOnce) {
      final queue = widget.libraryPlaybackQueue
          .where((id) => id.trim().isNotEmpty)
          .toList();
      final currentIndex = queue.indexOf(widget.localBookId);
      final nextBookIds = currentIndex < 0
          ? const <String>[]
          : <String>[
              ...queue.skip(currentIndex + 1),
              ...queue.take(currentIndex),
            ];
      var hasQueuedFollowingBook = false;
      for (final localBookId in nextBookIds) {
        final package = await _packageRepository.readPackage(localBookId);
        final job = _findPlayableJobForPackage(package, selectedJob);
        if (job == null) {
          continue;
        }
        final packageSegments = package.segmentsForJob(job.jobId);
        final packageAudioPaths = await _collectLocalPlaylistPathsForBook(
          localBookId,
          job.jobId,
          packageSegments,
        );
        if (packageAudioPaths == null ||
            packageAudioPaths.length != packageSegments.length) {
          continue;
        }
        if (!hasQueuedFollowingBook) {
          segments.add(
            _buildSilenceSegment(
              localBookId: widget.localBookId,
              selectedJob: selectedJob,
              title: _state.payload?.title ?? selectedJob.levelName,
            ),
          );
        } else {
          segments.add(
            _buildSilenceSegment(
              localBookId: localBookId,
              selectedJob: job,
              title: package.meta.title,
            ),
          );
        }
        hasQueuedFollowingBook = true;
        segments.addAll(
          _buildPlaybackSegments(
            localBookId: localBookId,
            title: package.meta.title,
            job: job,
            localSegments: packageSegments,
            localAudioPaths: packageAudioPaths,
          ),
        );
      }
    }
    if (effectiveRepeatMode == ReaderPlaybackRepeatMode.repeatBook) {
      segments.add(
        _buildSilenceSegment(
          localBookId: widget.localBookId,
          selectedJob: selectedJob,
          title: _state.payload?.title ?? selectedJob.levelName,
        ),
      );
    }

    return LexoPlaybackRequest(
      playbackSpeed: _selectedPlaybackSpeed(),
      repeatBook: effectiveRepeatMode == ReaderPlaybackRepeatMode.repeatBook,
      segments: segments,
      initialIndex: initialIndex,
    );
  }

  LexoPlaybackSegment _buildSilenceSegment({
    required String localBookId,
    required TtsJobItem selectedJob,
    required String title,
  }) {
    return LexoPlaybackSegment(
      bookId: localBookId,
      title: title,
      jobId: selectedJob.jobId,
      voiceId: selectedJob.voiceId,
      levelId: selectedJob.levelId,
      levelName: 'Pause',
      segmentIndex: -1,
      segmentNumber: selectedJob.totalSegments,
      totalSegments: selectedJob.totalSegments,
      audioPath: '',
      isSilence: true,
      silenceDuration: const Duration(seconds: 5),
    );
  }

  int _queueIndexForCurrentSegment(
    TtsJobItem activeJob,
    List<TtsSegmentItem> localSegments,
  ) {
    final currentSegmentIndex = activeJob.currentSegmentIndex;
    for (var index = 0; index < localSegments.length; index += 1) {
      if (localSegments[index].segmentIndex == currentSegmentIndex) {
        return index;
      }
    }
    return currentSegmentIndex
        .clamp(0, math.max(0, localSegments.length - 1))
        .toInt();
  }

  Future<void> _rebuildBackgroundQueueForActiveJob({
    ReaderPlaybackRepeatMode? repeatMode,
  }) async {
    if (!_useLocalPlayback || _playingWordAudio) {
      return;
    }
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    final localSegments =
        _localSegmentsByJobId[activeJob.jobId] ?? state.activeSegments;
    final localAudioPaths =
        await _collectLocalPlaylistPaths(activeJob.jobId, localSegments);
    if (!mounted ||
        localSegments.isEmpty ||
        localAudioPaths == null ||
        localAudioPaths.length != localSegments.length) {
      return;
    }
    final backgroundHandler = await LexoBackgroundAudio.ensureInitialized();
    if (backgroundHandler == null) {
      return;
    }
    final request = await _buildBackgroundPlaybackRequest(
      selectedJob: activeJob,
      localSegments: localSegments,
      localAudioPaths: localAudioPaths,
      repeatMode: repeatMode,
      initialIndex: _queueIndexForCurrentSegment(activeJob, localSegments),
    );
    if (!mounted || request.segments.isEmpty) {
      return;
    }
    final bookCount =
        request.segments.map((segment) => segment.bookId).toSet().length;
    final queueBooks = <String>[];
    for (final segment in request.segments) {
      if (segment.isSilence) {
        continue;
      }
      if (queueBooks.isEmpty || queueBooks.last != segment.bookId) {
        queueBooks.add(segment.bookId);
      }
    }
    developer.log(
      'BACKGROUND_QUEUE_REBUILD mode=${repeatMode ?? _effectivePlaybackRepeatMode} '
      'books=$bookCount segments=${request.segments.length} initial_index=${request.initialIndex} '
      'queue_books=${queueBooks.join(',')}',
      name: 'LEXO_UI',
    );
    await _audioPlayer.stop();
    await _audioPlayer.setPlaylistMode(PlaylistMode.none);
    await backgroundHandler.playBook(request);
  }

  List<LexoPlaybackSegment> _buildPlaybackSegments({
    required String localBookId,
    required String title,
    required TtsJobItem job,
    required List<TtsSegmentItem> localSegments,
    required List<String> localAudioPaths,
  }) {
    return [
      for (var i = 0; i < localSegments.length; i += 1)
        LexoPlaybackSegment(
          bookId: localBookId,
          title: title,
          jobId: job.jobId,
          voiceId: job.voiceId,
          levelId: job.levelId,
          levelName: job.levelName,
          segmentIndex: localSegments[i].segmentIndex,
          segmentNumber: i + 1,
          totalSegments: localSegments.length,
          audioPath: localAudioPaths[i],
        ),
    ];
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
      playbackProgress: activeJob.totalSegments > 0
          ? ((index + 1) / activeJob.totalSegments)
          : 0,
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

  void _syncBackgroundMediaItem(audio_service.MediaItem? item) {
    if (item == null) {
      return;
    }
    final state = _state.ttsState;
    if (state == null) {
      _pendingBackgroundMediaItem = item;
      return;
    }
    final extras = item.extras ?? const <String, dynamic>{};
    if (extras['is_silence'] == true) {
      return;
    }
    final mediaBookId = extras['book_id'] as String? ?? '';
    final mediaJobId = extras['job_id'] as String? ?? '';
    if (mediaBookId != widget.localBookId || mediaJobId.isEmpty) {
      return;
    }
    var activeJob = state.activeJob;
    var activeSegments = state.activeSegments;
    if (activeJob == null ||
        activeJob.jobId != mediaJobId ||
        activeSegments.isEmpty) {
      for (final job in state.jobs) {
        if (job.jobId == mediaJobId) {
          activeJob = _copyJob(job, playbackState: 'playing');
          activeSegments =
              _localSegmentsByJobId[mediaJobId] ?? const <TtsSegmentItem>[];
          break;
        }
      }
    }
    if (activeJob == null || activeSegments.isEmpty) {
      _pendingBackgroundMediaItem = item;
      return;
    }
    final segmentIndex =
        extras['segment_index'] as int? ?? activeJob.currentSegmentIndex;
    final segmentNumber =
        extras['segment_number'] as int? ?? activeJob.currentSegmentNumber;
    final totalSegments =
        extras['total_segments'] as int? ?? activeJob.totalSegments;
    final nextJob = _copyJob(
      activeJob,
      currentSegmentIndex: segmentIndex,
      currentSegmentNumber: segmentNumber,
      playbackProgress: totalSegments > 0
          ? segmentNumber / totalSegments
          : activeJob.playbackProgress,
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
          activeSegments: activeSegments,
        ),
      );
      _useLocalPlayback = true;
    });
  }

  void _syncBackgroundPlaybackState(audio_service.PlaybackState playbackState) {
    if (!_useLocalPlayback) {
      return;
    }
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    if (playbackState.processingState ==
        audio_service.AudioProcessingState.completed) {
      if (!_handlingBackgroundCompletion) {
        unawaited(_handleBackgroundBookCompleted());
      }
      return;
    }
    final nextPlaybackState = playbackState.playing ? 'playing' : 'paused';
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

  Future<void> _handleBackgroundBookCompleted() async {
    final state = _state.ttsState;
    final activeJob = state?.activeJob;
    if (state == null || activeJob == null || state.activeSegments.isEmpty) {
      return;
    }
    if (_effectivePlaybackRepeatMode ==
        ReaderPlaybackRepeatMode.playLibraryOnce) {
      await LexoBackgroundAudio.handler?.stop();
      widget.onPlaybackRepeatModeChanged?.call(ReaderPlaybackRepeatMode.off);
      if (!mounted) {
        return;
      }
      setState(() {
        _useLocalPlayback = false;
        _localPlaybackRepeatMode = ReaderPlaybackRepeatMode.off;
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
    _handlingBackgroundCompletion = true;
    try {
      await _handleBookCompleted(activeJob, state.jobs);
    } finally {
      _handlingBackgroundCompletion = false;
    }
  }

  Future<void> _startPlayback(String jobId) async {
    _playbackCycleToken += 1;
    final localSegments =
        _localSegmentsByJobId[jobId] ?? const <TtsSegmentItem>[];
    final localAudioPaths =
        await _collectLocalPlaylistPaths(jobId, localSegments);
    if (localSegments.isNotEmpty &&
        localAudioPaths != null &&
        localAudioPaths.length == localSegments.length) {
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
              playbackProgress: selectedJob.totalSegments > 0
                  ? 1 / selectedJob.totalSegments
                  : 0,
              errorMessage: selectedJob.errorMessage,
            ),
            activeSegments: localSegments,
          ),
        );
      });
      final backgroundHandler = await LexoBackgroundAudio.ensureInitialized();
      if (backgroundHandler != null) {
        await _audioPlayer.stop();
        await _audioPlayer.setPlaylistMode(PlaylistMode.none);
        final request = await _buildBackgroundPlaybackRequest(
          selectedJob: selectedJob,
          localSegments: localSegments,
          localAudioPaths: localAudioPaths,
        );
        await backgroundHandler.playBook(request);
        return;
      }
      await _audioPlayer.stop();
      await _audioPlayer.setPlaylistMode(
          _nativePlaylistModeFor(_effectivePlaybackRepeatMode));
      await _audioPlayer.open(playlist, play: true);
      await _applyPlaybackSpeed();
      return;
    }
    setState(() {
      _state = _state.copyWith(
        error: 'No local audio for this voice. Sync first.',
      );
    });
  }

  Future<void> _controlPlayback(String action) async {
    final activeJob = _state.ttsState?.activeJob;
    if (activeJob == null) {
      return;
    }
    if (_useLocalPlayback) {
      final backgroundHandler = LexoBackgroundAudio.handler;
      if (backgroundHandler != null) {
        if (action == 'pause') {
          await backgroundHandler.pause();
        } else if (action == 'resume') {
          await backgroundHandler.setSpeed(_selectedPlaybackSpeed());
          await backgroundHandler.play();
        } else if (action == 'next') {
          await backgroundHandler.skipToNext();
        } else if (action == 'prev') {
          await backgroundHandler.skipToPrevious();
        }
      } else {
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
      }
      return;
    }
    setState(() {
      _state = _state.copyWith(
        error: 'Playback is available only for locally synced audio',
      );
    });
  }

  Future<void> _stopJob(String jobId) async {
    _playbackCycleToken += 1;
    await LexoBackgroundAudio.handler?.stop();
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
        error: 'Playback stopped: local audio is unavailable',
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
    if (_effectivePlaybackRepeatMode == ReaderPlaybackRepeatMode.repeatBook) {
      return;
    }

    final cycleToken = ++_playbackCycleToken;
    await LexoBackgroundAudio.handler?.stop();
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
    return _formatSpeed(
      selectedLevel == null
          ? widget.preferredPlaybackSpeed
          : _playbackSpeedForLevel(selectedLevel),
    );
  }

  TtsLevel _closestLevelForSpeed(List<TtsLevel> levels, double speed) {
    var best = levels.first;
    var bestDelta = (_playbackSpeedForLevel(best) - speed).abs();
    for (final level in levels.skip(1)) {
      final delta = (_playbackSpeedForLevel(level) - speed).abs();
      if (delta < bestDelta) {
        best = level;
        bestDelta = delta;
      }
    }
    return best;
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
                title: Text(
                    '${level.name} ${_formatSpeed(_playbackSpeedForLevel(level))}'),
                trailing: level.id == _selectedLevel()?.id
                    ? const Icon(Icons.check)
                    : null,
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
    setState(() =>
        _state = _state.copyWith(lastSavedParagraphIndex: paragraphIndex));
    try {
      await _packageRepository.saveReaderPosition(
          widget.localBookId, paragraphIndex);
    } catch (_) {}
  }

  void _handleWordTap(ParagraphItem item, ParagraphWordItem word) {
    final focusText = word.effectiveFocusText?.trim() ?? '';
    final effective = focusText.isNotEmpty
        ? null
        : buildPreferredSourceFirstFocus(item: item, word: word);
    setState(() {
      _state = _state.copyWith(
        selectedParagraphIndex: item.index,
        selectedTapUnitId: word.tapUnitId,
        translationLeftText: effective?.left ?? (word.effectiveLeftText ?? ''),
        translationFocusText:
            effective?.focus ?? (focusText.isNotEmpty ? focusText : word.text),
        translationRightText:
            effective?.right ?? (word.effectiveRightText ?? ''),
      );
    });
    _savePosition(item.index);
  }

  Future<void> _handleWordLongPress(
      ParagraphItem item, ParagraphWordItem word) async {
    _handleWordTap(item, word);
    final dictionaryPayload = _detailByWordId[word.id];
    final isMultiWordBlock = const {'block', 'grammar_group', 'alignment_group'}
        .contains(word.effectiveAlignmentKind);
    final payload = isMultiWordBlock
        ? DetailSheetPayload.fromSelection(item: item, word: word)
        : (dictionaryPayload ??
            DetailSheetPayload.fromSelection(item: item, word: word));
    _logDetailSheet(item.index, word, payload);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.78,
        child: ReaderDetailSheet(
          payload: payload,
          onSaveWord: (unit, translations) =>
              _saveDictionaryCard(payload, unit, translations),
          onPlayWordAudio: () => _playDetailWordAudio(payload),
        ),
      ),
    );
  }

  Set<String> _detailWordAudioCandidates(DetailSheetPayload payload) {
    return <String>{
      payload.dictionaryEntry?.lemma.trim() ?? '',
      ...payload.units.where((unit) => unit.isPrimary).map((unit) =>
          unit.lemma.trim().isNotEmpty ? unit.lemma.trim() : unit.text.trim()),
      payload.sheetSourceText.trim(),
    }..removeWhere((value) => value.isEmpty);
  }

  Future<String?> _resolveDetailWordAudioPath(
      DetailSheetPayload payload) async {
    final voiceId = (_state.selectedVoiceId ?? widget.preferredVoiceId).trim();
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
        throw Exception('Local word audio not found. Sync the book first.');
      }
      _playbackCycleToken += 1;
      await LexoBackgroundAudio.handler?.stop();
      await _audioPlayer.stop();
      await _audioPlayer.setPlaylistMode(PlaylistMode.none);
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
        SnackBar(content: Text('Could not play word audio: $error')),
      );
    }
  }

  Future<void> _saveDictionaryCard(
    DetailSheetPayload payload,
    DetailSheetUnitItem unit,
    List<String> translations,
  ) async {
    final unitPayload = DetailSheetPayload(
      wordId: unit.id,
      tapUnitId: unit.id,
      sheetSourceText:
          unit.surfaceText.trim().isNotEmpty ? unit.surfaceText : unit.text,
      sheetTranslationText: unit.translation,
      exampleSourceText: unit.exampleSourceText.trim().isNotEmpty
          ? unit.exampleSourceText
          : payload.exampleSourceText,
      exampleTranslationText: unit.exampleTranslationText.trim().isNotEmpty
          ? unit.exampleTranslationText
          : payload.exampleTranslationText,
      sourceFirst: null,
      dictionaryEntry: null,
      units: [unit],
    );
    try {
      await widget.cardsRepository.saveDictionaryCard(
        deviceId: widget.deviceId,
        originBookId: _desktopBookId ?? widget.localBookId,
        payload: unitPayload,
        translations: translations,
      );
      widget.onCardsChanged?.call();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card added')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save card: $error')),
      );
    }
  }

  void _logDetailSheet(
      int paragraphIndex, ParagraphWordItem word, DetailSheetPayload payload) {
    final unitsText = payload.units
        .map(
          (unit) =>
              '[${unit.type}] text="${unit.text}" surface="${unit.surfaceText}" '
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
    final playerBottomPadding = _playerExpanded ? 75.0 : 39.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(payload?.title ?? 'Reader'),
      ),
      body: _state.loading
          ? const Center(child: CircularProgressIndicator())
          : payload == null || payload.paragraphs.isEmpty
              ? Center(child: Text(_state.error ?? 'No reader data'))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          if (_state.error != null &&
                              _state.error!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Text(
                                _state.error!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          Expanded(
                            child: ReaderTextFlow(
                              payload: payload,
                              translationLeftText: _state.translationLeftText,
                              translationFocusText: _state.translationFocusText,
                              translationRightText: _state.translationRightText,
                              selectedParagraphIndex:
                                  _state.selectedParagraphIndex,
                              selectedTapUnitId: _state.selectedTapUnitId,
                              onWordTap: _handleWordTap,
                              onWordLongPress: _handleWordLongPress,
                              bottomContentPadding: playerBottomPadding +
                                  MediaQuery.paddingOf(context).bottom,
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
                        isPlaying: _state.ttsState?.activeJob?.playbackState ==
                            'playing',
                        isPaused: _state.ttsState?.activeJob?.playbackState ==
                            'paused',
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
