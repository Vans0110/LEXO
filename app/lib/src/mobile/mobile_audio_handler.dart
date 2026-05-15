import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

class LexoPlaybackSegment {
  const LexoPlaybackSegment({
    required this.bookId,
    required this.title,
    required this.jobId,
    required this.voiceId,
    required this.levelId,
    required this.levelName,
    required this.segmentIndex,
    required this.segmentNumber,
    required this.totalSegments,
    required this.audioPath,
    this.isSilence = false,
    this.silenceDuration = Duration.zero,
  });

  final String bookId;
  final String title;
  final String jobId;
  final String voiceId;
  final int levelId;
  final String levelName;
  final int segmentIndex;
  final int segmentNumber;
  final int totalSegments;
  final String audioPath;
  final bool isSilence;
  final Duration silenceDuration;
}

class LexoPlaybackRequest {
  const LexoPlaybackRequest({
    required this.playbackSpeed,
    required this.repeatBook,
    required this.segments,
    this.initialIndex = 0,
  });

  final double playbackSpeed;
  final bool repeatBook;
  final List<LexoPlaybackSegment> segments;
  final int initialIndex;
}

class LexoAudioHandler extends audio_service.BaseAudioHandler
    with audio_service.QueueHandler, audio_service.SeekHandler {
  LexoAudioHandler() {
    _player.currentIndexStream.listen(_publishCurrentMediaItem);
    _player.playerStateStream.listen(_publishPlaybackState);
    playbackState.add(_emptyPlaybackState());
  }

  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  List<audio_service.MediaItem> _mediaItems = const <audio_service.MediaItem>[];

  audio_service.PlaybackState _emptyPlaybackState() {
    return audio_service.PlaybackState(
      controls: [audio_service.MediaControl.play],
      processingState: audio_service.AudioProcessingState.idle,
    );
  }

  Future<void> playBook(LexoPlaybackRequest request) async {
    if (request.segments.isEmpty) {
      return;
    }
    _mediaItems = [
      for (final segment in request.segments)
        audio_service.MediaItem(
          id: '${segment.bookId}|${segment.jobId}|${segment.segmentIndex}',
          title: segment.title,
          artist: segment.levelName,
          extras: <String, Object>{
            'book_id': segment.bookId,
            'job_id': segment.jobId,
            'voice_id': segment.voiceId,
            'level_id': segment.levelId,
            'segment_index': segment.segmentIndex,
            'segment_number': segment.segmentNumber,
            'total_segments': segment.totalSegments,
            'is_silence': segment.isSilence,
          },
        ),
    ];
    queue.add(_mediaItems);
    final initialIndex = request.initialIndex.clamp(0, _mediaItems.length - 1).toInt();
    mediaItem.add(_mediaItems[initialIndex]);
    await _player.stop();
    await _player.setAudioSources(
      [
        for (final segment in request.segments)
          segment.isSilence
              ? just_audio.SilenceAudioSource(duration: segment.silenceDuration)
              : just_audio.AudioSource.uri(Uri.file(segment.audioPath)),
      ],
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );
    await _player.setSpeed(request.playbackSpeed);
    await _player.setLoopMode(
      request.repeatBook ? just_audio.LoopMode.all : just_audio.LoopMode.off,
    );
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _mediaItems = const <audio_service.MediaItem>[];
    queue.add(const <audio_service.MediaItem>[]);
    mediaItem.add(null);
    playbackState.add(_emptyPlaybackState());
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) {
    return _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setRepeatBook(bool repeatBook) {
    return _player.setLoopMode(
      repeatBook ? just_audio.LoopMode.all : just_audio.LoopMode.off,
    );
  }

  void _publishCurrentMediaItem(int? index) {
    if (index == null || index < 0 || index >= _mediaItems.length) {
      return;
    }
    mediaItem.add(_mediaItems[index]);
  }

  void _publishPlaybackState(just_audio.PlayerState state) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          audio_service.MediaControl.skipToPrevious,
          state.playing ? audio_service.MediaControl.pause : audio_service.MediaControl.play,
          audio_service.MediaControl.stop,
          audio_service.MediaControl.skipToNext,
        ],
        processingState: _mapProcessingState(state.processingState),
        playing: state.playing,
        speed: _player.speed,
        updatePosition: _player.position,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  audio_service.AudioProcessingState _mapProcessingState(
    just_audio.ProcessingState state,
  ) {
    switch (state) {
      case just_audio.ProcessingState.idle:
        return audio_service.AudioProcessingState.idle;
      case just_audio.ProcessingState.loading:
        return audio_service.AudioProcessingState.loading;
      case just_audio.ProcessingState.buffering:
        return audio_service.AudioProcessingState.buffering;
      case just_audio.ProcessingState.ready:
        return audio_service.AudioProcessingState.ready;
      case just_audio.ProcessingState.completed:
        return audio_service.AudioProcessingState.completed;
    }
  }
}

class LexoBackgroundAudio {
  LexoBackgroundAudio._();

  static LexoAudioHandler? _handler;

  static LexoAudioHandler? get handler => _handler;

  static bool get isSupported {
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  static Future<LexoAudioHandler?> ensureInitialized() async {
    if (!isSupported) {
      return null;
    }
    final existing = _handler;
    if (existing != null) {
      return existing;
    }

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    late final LexoAudioHandler delegate;
    await audio_service.AudioService.init(
      builder: () {
        delegate = LexoAudioHandler();
        return delegate;
      },
      config: const audio_service.AudioServiceConfig(
        androidNotificationChannelId: 'lexo.mobile.playback',
        androidNotificationChannelName: 'LEXO playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    _handler = delegate;
    return delegate;
  }
}
