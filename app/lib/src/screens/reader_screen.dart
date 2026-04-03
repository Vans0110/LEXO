import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../api/api_client.dart';
import '../features/reader/reader_feature.dart';
import '../models.dart';
import '../widgets/reader_text_flow.dart';
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
      if (result.ttsLevels.isNotEmpty && selectedLevelIds.isEmpty) {
        selectedLevelIds = {result.ttsLevels.first.id};
      }
      setState(() {
        _state = _state.copyWith(
          payload: result.payload,
          ttsProfiles: result.ttsProfiles,
          ttsLevels: result.ttsLevels,
          ttsState: result.ttsState,
          selectedVoiceId: selectedVoiceId,
          selectedLevelIds: selectedLevelIds,
          loading: false,
        );
      });
      _syncPolling(result.ttsState);
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
      setState(() => _state = _state.copyWith(ttsState: nextState));
      _syncPolling(nextState);
    } catch (_) {
      // Не ломаем экран из-за временной ошибки polling.
    }
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
    final voiceId = _state.selectedVoiceId;
    if (voiceId == null || _state.selectedLevelIds.isEmpty) {
      return;
    }
    setState(() => _state = _state.copyWith(actionBusy: true, clearError: true));
    try {
      final state = await _controller.generateTts(
        bookId: widget.bookId,
        voiceId: voiceId,
        levelIds: [_state.selectedLevelIds.first],
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
    final focusText = word.translationFocusText.trim().isNotEmpty
        ? word.translationFocusText
        : word.translationSpanText;
    debugPrint(
      'WORD_TAP paragraph=${item.index} word="${word.text}" unit="${word.sourceUnitText}" ru="${focusText.isNotEmpty ? focusText : word.text}" '
      'span="${word.translationSpanText}" anchor="${word.anchorWordId ?? ''}" '
      'left="${word.translationLeftText}" right="${word.translationRightText}"',
    );
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
                            busy: _state.actionBusy,
                            onVoiceChanged: (value) => setState(
                              () => _state = _state.copyWith(selectedVoiceId: value),
                            ),
                            onLevelToggle: (levelId, selected) {
                              if (!selected) {
                                return;
                              }
                              setState(() => _state = _state.copyWith(selectedLevelIds: {levelId}));
                            },
                            onGenerate: _generateVoice,
                            onPause: () => _controlPlayback('pause'),
                            onResume: () => _controlPlayback('resume'),
                            onPrev: () => _controlPlayback('prev'),
                            onNext: () => _controlPlayback('next'),
                            onStartJob: _startPlayback,
                            onStopJob: _stopJob,
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
                          ),
                        ),
                      ],
                    ),
    );
  }
}
