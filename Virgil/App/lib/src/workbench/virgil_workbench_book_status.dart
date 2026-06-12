import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

class VirgilWorkbenchBookStatus {
  const VirgilWorkbenchBookStatus({
    required this.title,
    required this.level,
    required this.chapterId,
    required this.languages,
    required this.dictionaries,
    required this.hasAudio,
    required this.hasCover,
    required this.hasOutput,
    required this.hasInstalledZip,
    required this.coverPath,
    required this.audioVoiceIds,
    required this.profileVoiceIds,
    required this.playerLevelsByVoice,
    required this.wordAudioVoiceId,
    required this.wordAudioCountsByVoice,
    required this.segmentAudioCount,
    required this.wordAudioCount,
  });

  final String title;
  final String level;
  final String chapterId;
  final Set<String> languages;
  final Set<String> dictionaries;
  final bool hasAudio;
  final bool hasCover;
  final bool hasOutput;
  final bool hasInstalledZip;
  final String coverPath;
  final Set<String> audioVoiceIds;
  final Set<String> profileVoiceIds;
  final Map<String, Set<String>> playerLevelsByVoice;
  final String wordAudioVoiceId;
  final Map<String, int> wordAudioCountsByVoice;
  final int segmentAudioCount;
  final int wordAudioCount;

  bool get hasPlayerReadyVoice =>
      audioVoiceIds.intersection(profileVoiceIds).isNotEmpty;

  Set<String> get missingPlayerVoiceIds =>
      profileVoiceIds.difference(audioVoiceIds);

  Set<String> get readyWordAudioVoiceIds => wordAudioCountsByVoice.entries
      .where((entry) => entry.value > 0)
      .map((entry) => entry.key)
      .toSet();

  Set<String> get missingWordAudioVoiceIds =>
      profileVoiceIds.difference(readyWordAudioVoiceIds);

  bool get hasPlayerMetadataProblem =>
      segmentAudioCount > 0 && !hasPlayerReadyVoice;

  bool get isProcessed =>
      hasOutput ||
      hasInstalledZip ||
      languages.isNotEmpty ||
      dictionaries.isNotEmpty ||
      hasAudio;

  bool get isFullyBuilt =>
      hasInstalledZip &&
      hasCover &&
      hasLanguage('ru') &&
      hasLanguage('uk') &&
      hasDictionary('ru') &&
      hasDictionary('uk') &&
      hasPlayerReadyVoice &&
      missingPlayerVoiceIds.isEmpty &&
      wordAudioCount > 0 &&
      missingWordAudioVoiceIds.isEmpty;

  bool hasLanguage(String language) => languages.contains(language);

  bool hasDictionary(String language) => dictionaries.contains(language);

  VirgilWorkbenchBookStatus merge(VirgilWorkbenchBookStatus other) {
    return VirgilWorkbenchBookStatus(
      title: title.isNotEmpty ? title : other.title,
      level: level.isNotEmpty ? level : other.level,
      chapterId: chapterId.isNotEmpty ? chapterId : other.chapterId,
      languages: {...languages, ...other.languages},
      dictionaries: {...dictionaries, ...other.dictionaries},
      hasAudio: hasAudio || other.hasAudio,
      hasCover: hasCover || other.hasCover,
      hasOutput: hasOutput || other.hasOutput,
      hasInstalledZip: hasInstalledZip || other.hasInstalledZip,
      coverPath: coverPath.isNotEmpty ? coverPath : other.coverPath,
      audioVoiceIds: {...audioVoiceIds, ...other.audioVoiceIds},
      profileVoiceIds: {...profileVoiceIds, ...other.profileVoiceIds},
      playerLevelsByVoice: _mergePlayerLevels(
        playerLevelsByVoice,
        other.playerLevelsByVoice,
      ),
      wordAudioVoiceId: wordAudioVoiceId.isNotEmpty
          ? wordAudioVoiceId
          : other.wordAudioVoiceId,
      wordAudioCountsByVoice: _mergeWordAudioCounts(
        wordAudioCountsByVoice,
        other.wordAudioCountsByVoice,
      ),
      segmentAudioCount: segmentAudioCount > other.segmentAudioCount
          ? segmentAudioCount
          : other.segmentAudioCount,
      wordAudioCount: wordAudioCount > other.wordAudioCount
          ? wordAudioCount
          : other.wordAudioCount,
    );
  }

  static Map<String, Set<String>> _mergePlayerLevels(
    Map<String, Set<String>> left,
    Map<String, Set<String>> right,
  ) {
    final result = <String, Set<String>>{};
    for (final entry in left.entries) {
      result[entry.key] = {...entry.value};
    }
    for (final entry in right.entries) {
      result.update(
        entry.key,
        (value) => {...value, ...entry.value},
        ifAbsent: () => {...entry.value},
      );
    }
    return result;
  }

  static Map<String, int> _mergeWordAudioCounts(
    Map<String, int> left,
    Map<String, int> right,
  ) {
    final result = <String, int>{...left};
    for (final entry in right.entries) {
      result.update(
        entry.key,
        (value) => value > entry.value ? value : entry.value,
        ifAbsent: () => entry.value,
      );
    }
    return result;
  }
}

class VirgilWorkbenchBookStatusLoader {
  const VirgilWorkbenchBookStatusLoader({required this.appRoot});

  final String appRoot;

  Future<Map<String, VirgilWorkbenchBookStatus>> loadStatuses() async {
    final result = <String, VirgilWorkbenchBookStatus>{};
    await _loadOutputStatuses(result);
    await _loadInstalledZipStatuses(result);
    return result;
  }

  Future<void> _loadOutputStatuses(
    Map<String, VirgilWorkbenchBookStatus> result,
  ) async {
    final outputRoot = Directory('$appRoot/Studio/Runtime/workbench_output');
    if (!outputRoot.existsSync()) {
      return;
    }
    final manifestFiles = outputRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => _basename(file.path) == 'manifest.json');
    for (final manifestFile in manifestFiles) {
      try {
        final manifest = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        final title = (manifest['title'] ?? '').toString().trim();
        final level = (manifest['level'] ?? '').toString().trim();
        final chapterId = (manifest['chapter_id'] ?? '').toString().trim();
        if (title.isEmpty || level.isEmpty) {
          continue;
        }
        final outputDir = manifestFile.parent;
        final status = _readOutputDirectoryStatus(
          outputDir: outputDir,
          title: title,
          level: level,
          chapterId: chapterId,
        );
        _merge(result, status);
      } catch (_) {
        continue;
      }
    }
  }

  VirgilWorkbenchBookStatus _readOutputDirectoryStatus({
    required Directory outputDir,
    required String title,
    required String level,
    required String chapterId,
  }) {
    final languages = <String>{};
    final dictionaries = <String>{};
    final audioVoiceIds = <String>{};
    final profileVoiceIds = <String>{};
    final playerLevelsByVoice = <String, Set<String>>{};
    final wordAudioCountsByVoice = <String, int>{};
    var wordAudioVoiceId = '';
    var segmentAudioCount = 0;
    var wordAudioCount = 0;
    var hasAudio = false;
    var hasCover = false;
    var coverPath = '';
    final ttsManifestFile = File('${outputDir.path}/tts_manifest.json');
    if (ttsManifestFile.existsSync()) {
      try {
        _readTtsManifest(
          jsonDecode(ttsManifestFile.readAsStringSync())
              as Map<String, dynamic>,
          audioVoiceIds: audioVoiceIds,
          profileVoiceIds: profileVoiceIds,
          playerLevelsByVoice: playerLevelsByVoice,
        );
      } catch (_) {}
    }
    final wordAudioManifestFile =
        File('${outputDir.path}/word_audio_manifest.json');
    if (wordAudioManifestFile.existsSync()) {
      try {
        final manifest = jsonDecode(wordAudioManifestFile.readAsStringSync())
            as Map<String, dynamic>;
        wordAudioVoiceId = (manifest['voice_id'] ?? '').toString();
        for (final voiceId in _readWordAudioManifestVoices(manifest)) {
          wordAudioCountsByVoice.putIfAbsent(voiceId, () => 0);
        }
      } catch (_) {}
    }
    for (final entity in outputDir.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final normalized = entity.path.replaceAll('\\', '/');
      if (_isChapterImagesPath(normalized)) {
        continue;
      }
      final fileName = _basename(normalized);
      final readerMatch =
          RegExp(r'^reader_([a-z]{2})\.json$').firstMatch(fileName);
      if (readerMatch != null) {
        languages.add(readerMatch.group(1)!);
      }
      final dictionaryMatch =
          RegExp(r'^dictionary_([a-z]{2})\.json$').firstMatch(fileName);
      if (dictionaryMatch != null) {
        dictionaries.add(dictionaryMatch.group(1)!);
      }
      if (normalized.contains('/audio/segments/') &&
          normalized.endsWith('.mp3')) {
        hasAudio = true;
        segmentAudioCount += 1;
      }
      if (normalized.contains('/audio/words/') && normalized.endsWith('.mp3')) {
        wordAudioCount += 1;
        final voiceId = _wordAudioVoiceIdFromPath(
          normalized,
          legacyVoiceId: wordAudioVoiceId,
        );
        if (voiceId.isNotEmpty) {
          wordAudioCountsByVoice.update(voiceId, (value) => value + 1,
              ifAbsent: () => 1);
        }
      }
      if (const {'cover.png', 'cover.jpg', 'cover.jpeg'}.contains(fileName)) {
        hasCover = true;
        coverPath = entity.path;
      }
    }
    return VirgilWorkbenchBookStatus(
      title: title,
      level: level,
      chapterId: chapterId,
      languages: languages,
      dictionaries: dictionaries,
      hasAudio: hasAudio,
      hasCover: hasCover,
      hasOutput: true,
      hasInstalledZip: false,
      coverPath: coverPath,
      audioVoiceIds: audioVoiceIds,
      profileVoiceIds: profileVoiceIds,
      playerLevelsByVoice: playerLevelsByVoice,
      wordAudioVoiceId: wordAudioVoiceId,
      wordAudioCountsByVoice: wordAudioCountsByVoice,
      segmentAudioCount: segmentAudioCount,
      wordAudioCount: wordAudioCount,
    );
  }

  Future<void> _loadInstalledZipStatuses(
    Map<String, VirgilWorkbenchBookStatus> result,
  ) async {
    final assetsRoot = Directory('$appRoot/Studio/CloudLibrary');
    if (!assetsRoot.existsSync()) {
      return;
    }
    final zipFiles = assetsRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.zip'));
    for (final file in zipFiles) {
      try {
        final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
        final manifestFile = archive.files
            .where((item) => item.isFile && item.name == 'manifest.json')
            .firstOrNull;
        if (manifestFile == null) {
          continue;
        }
        final manifest = jsonDecode(
          utf8.decode(manifestFile.content as List<int>),
        ) as Map<String, dynamic>;
        final title = (manifest['title'] ?? '').toString().trim();
        final level = (manifest['level'] ?? '').toString().trim();
        final chapterId = (manifest['chapter_id'] ?? '').toString().trim();
        if (title.isEmpty || level.isEmpty) {
          continue;
        }
        final languages = <String>{};
        final dictionaries = <String>{};
        final audioVoiceIds = <String>{};
        final profileVoiceIds = <String>{};
        final playerLevelsByVoice = <String, Set<String>>{};
        final wordAudioCountsByVoice = <String, int>{};
        var wordAudioVoiceId = '';
        var segmentAudioCount = 0;
        var wordAudioCount = 0;
        var hasAudio = false;
        var hasCover = false;
        final wordAudioManifestFile = archive.files
            .where((item) =>
                item.isFile &&
                item.name.replaceAll('\\', '/') == 'word_audio_manifest.json')
            .firstOrNull;
        if (wordAudioManifestFile != null) {
          try {
            final wordAudioManifest = jsonDecode(
                    utf8.decode(wordAudioManifestFile.content as List<int>))
                as Map<String, dynamic>;
            wordAudioVoiceId = (wordAudioManifest['voice_id'] ?? '').toString();
            for (final voiceId
                in _readWordAudioManifestVoices(wordAudioManifest)) {
              wordAudioCountsByVoice.putIfAbsent(voiceId, () => 0);
            }
          } catch (_) {}
        }
        for (final item in archive.files) {
          if (!item.isFile || _isChapterImagesPath(item.name)) {
            continue;
          }
          final readerMatch =
              RegExp(r'^reader_([a-z]{2})\.json$').firstMatch(item.name);
          if (readerMatch != null) {
            languages.add(readerMatch.group(1)!);
          }
          final dictionaryMatch =
              RegExp(r'^dictionary_([a-z]{2})\.json$').firstMatch(item.name);
          if (dictionaryMatch != null) {
            dictionaries.add(dictionaryMatch.group(1)!);
          }
          final normalizedName = item.name.replaceAll('\\', '/');
          if (normalizedName.startsWith('audio/segments/') &&
              normalizedName.endsWith('.mp3')) {
            hasAudio = true;
            segmentAudioCount += 1;
          }
          if (normalizedName.startsWith('audio/words/') &&
              normalizedName.endsWith('.mp3')) {
            wordAudioCount += 1;
            final voiceId = _wordAudioVoiceIdFromPath(
              normalizedName,
              legacyVoiceId: wordAudioVoiceId,
            );
            if (voiceId.isNotEmpty) {
              wordAudioCountsByVoice.update(voiceId, (value) => value + 1,
                  ifAbsent: () => 1);
            }
          }
          if (const {'cover.png', 'cover.jpg', 'cover.jpeg'}
              .contains(item.name)) {
            hasCover = true;
          }
          if (normalizedName == 'tts_manifest.json') {
            try {
              _readTtsManifest(
                jsonDecode(utf8.decode(item.content as List<int>))
                    as Map<String, dynamic>,
                audioVoiceIds: audioVoiceIds,
                profileVoiceIds: profileVoiceIds,
                playerLevelsByVoice: playerLevelsByVoice,
              );
            } catch (_) {}
          }
        }
        _merge(
          result,
          VirgilWorkbenchBookStatus(
            title: title,
            level: level,
            chapterId: chapterId,
            languages: languages,
            dictionaries: dictionaries,
            hasAudio: hasAudio,
            hasCover: hasCover,
            hasOutput: false,
            hasInstalledZip: true,
            coverPath: '',
            audioVoiceIds: audioVoiceIds,
            profileVoiceIds: profileVoiceIds,
            playerLevelsByVoice: playerLevelsByVoice,
            wordAudioVoiceId: wordAudioVoiceId,
            wordAudioCountsByVoice: wordAudioCountsByVoice,
            segmentAudioCount: segmentAudioCount,
            wordAudioCount: wordAudioCount,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  Set<String> _readWordAudioManifestVoices(Map<String, dynamic> manifest) {
    final result = <String>{};
    final legacyVoiceId = (manifest['voice_id'] ?? '').toString().trim();
    if (legacyVoiceId.isNotEmpty) {
      result.add(legacyVoiceId);
    }
    final voices = manifest['voices'];
    if (voices is Map<String, dynamic>) {
      for (final key in voices.keys) {
        final voiceId = key.toString().trim();
        if (voiceId.isNotEmpty) {
          result.add(voiceId);
        }
      }
    }
    return result;
  }

  String _wordAudioVoiceIdFromPath(
    String normalizedPath, {
    required String legacyVoiceId,
  }) {
    const marker = '/audio/words/';
    final markerIndex = normalizedPath.indexOf(marker);
    final relative = markerIndex >= 0
        ? normalizedPath.substring(markerIndex + marker.length)
        : normalizedPath.startsWith('audio/words/')
            ? normalizedPath.substring('audio/words/'.length)
            : '';
    final parts = relative.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) {
      return parts.first.trim();
    }
    return legacyVoiceId.trim();
  }

  void _merge(
    Map<String, VirgilWorkbenchBookStatus> result,
    VirgilWorkbenchBookStatus status,
  ) {
    final key = virgilWorkbenchBookStatusKey(
      status.level,
      status.chapterId,
      status.title,
    );
    final existing = result[key];
    result[key] = existing == null ? status : existing.merge(status);
  }

  void _readTtsManifest(
    Map<String, dynamic> manifest, {
    required Set<String> audioVoiceIds,
    required Set<String> profileVoiceIds,
    required Map<String, Set<String>> playerLevelsByVoice,
  }) {
    for (final item
        in (manifest['profiles'] as List<dynamic>? ?? const <dynamic>[])) {
      if (item is Map<String, dynamic>) {
        final voiceId = (item['voice_id'] ?? '').toString().trim();
        if (voiceId.isNotEmpty) {
          profileVoiceIds.add(voiceId);
        }
      }
    }
    for (final item
        in (manifest['jobs'] as List<dynamic>? ?? const <dynamic>[])) {
      if (item is Map<String, dynamic>) {
        final voiceId = (item['voice_id'] ?? '').toString().trim();
        final status = (item['status'] ?? '').toString();
        final segments =
            item['segments'] as List<dynamic>? ?? const <dynamic>[];
        if (voiceId.isNotEmpty && status == 'ready' && segments.isNotEmpty) {
          audioVoiceIds.add(voiceId);
          final levelName = (item['level_name'] ?? '').toString().trim();
          final audioVariant = (item['audio_variant'] ?? '').toString().trim();
          final levelLabel = levelName.isNotEmpty
              ? levelName
              : (audioVariant.isNotEmpty ? audioVariant : 'Audio');
          playerLevelsByVoice
              .putIfAbsent(voiceId, () => <String>{})
              .add(levelLabel);
        }
      }
    }
  }
}

String virgilWorkbenchBookStatusKey(
        String level, String chapterId, String title) =>
    '${level.toLowerCase()}|$chapterId|${title.trim().toLowerCase()}';

String _basename(String path) =>
    path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;

bool _isChapterImagesPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized == 'chapter_images' ||
      normalized.contains('/chapter_images/') ||
      normalized.startsWith('chapter_images/');
}
