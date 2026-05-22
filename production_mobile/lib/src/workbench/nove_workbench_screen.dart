import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../mobile/nove_a1_chapters.dart';
import '../platform/desktop_txt_picker.dart';
import 'nove_workbench_book_library.dart';
import 'nove_workbench_builder.dart';
import 'nove_workbench_form_panels.dart';
import 'nove_library_index_builder.dart';
import 'nove_workbench_status_panel.dart';

class NoveWorkbenchScreen extends StatefulWidget {
  const NoveWorkbenchScreen({super.key, required this.api});

  final LexoApiClient api;

  @override
  State<NoveWorkbenchScreen> createState() => _NoveWorkbenchScreenState();
}

class _WorkbenchExportStatus {
  const _WorkbenchExportStatus({
    required this.bookId,
    required this.languages,
    required this.dictionaries,
    required this.dictionarySources,
    required this.hasAudio,
    required this.audioVoices,
    required this.hasCover,
  });

  final String bookId;
  final Set<String> languages;
  final Set<String> dictionaries;
  final Map<String, String> dictionarySources;
  final bool hasAudio;
  final Set<String> audioVoices;
  final bool hasCover;

  bool hasLanguages(Iterable<String> targetLanguages) =>
      targetLanguages.every(languages.contains);

  bool hasDictionaries(Iterable<String> targetLanguages) =>
      targetLanguages.every((lang) =>
          dictionaries.contains(lang) &&
          dictionarySources[lang] == 'marian_en_$lang');

  bool hasAudioFor(Iterable<String> voiceIds) =>
      voiceIds.every(audioVoices.contains);
}

class _NoveWorkbenchScreenState extends State<NoveWorkbenchScreen> {
  static const _levels = ['a1', 'a2', 'b1', 'b2', 'c1'];
  static const _sections = ['chapters', 'more_a1_stories'];
  static const _translationLangs = ['ru', 'uk'];
  static const _fallbackVoiceId = 'af_heart';

  String _level = _levels.first;
  String _section = _sections.first;
  String _chapterId = noveDefaultA1ChapterId;
  Set<String> _targetLangs = {'ru'};
  String _title = '';
  String _sourceText = '';
  String _sourcePath = '';
  String _coverPath = '';
  String? _bookId;
  Map<String, String> _bookIdsByTargetLang = const {};
  Map<String, Map<String, dynamic>> _packagesByTargetLang = const {};
  String? _voiceId = _fallbackVoiceId;
  Set<String> _voiceIds = {_fallbackVoiceId};
  bool _busy = false;
  String? _error;
  String? _outputPath;
  String _log = '';
  List<TtsProfile> _voices = const [];
  TtsPackageState? _packageState;
  Timer? _pollTimer;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    unawaited(_loadVoices());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await widget.api.getTtsProfiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _voices = voices;
        final availableVoiceIds = voices.map((voice) => voice.voiceId).toSet();
        final defaultVoiceId = availableVoiceIds.contains(_fallbackVoiceId)
            ? _fallbackVoiceId
            : (voices.isEmpty ? _fallbackVoiceId : voices.first.voiceId);
        _voiceId = defaultVoiceId;
        _voiceIds = _voiceIds.intersection(availableVoiceIds);
        if (_voiceIds.isEmpty) {
          _voiceIds = {defaultVoiceId};
        }
      });
    } catch (error) {
      _appendLog('Voice load failed: $error');
      if (!mounted) {
        return;
      }
      setState(() => _voiceId ??= _fallbackVoiceId);
    }
  }

  Future<void> _pickTxt() async {
    final picked = await DesktopTxtPicker.pickTxtFile();
    if (picked == null) {
      return;
    }
    final text = await File(picked.path).readAsString();
    if (!mounted) {
      return;
    }
    setState(() {
      _title = picked.titleCandidate;
      _titleController.text = _title;
      _sourcePath = picked.path;
      _sourceText = text;
      _bookId = null;
      _bookIdsByTargetLang = const {};
      _packagesByTargetLang = const {};
      _packageState = null;
      _outputPath = null;
      _error = null;
    });
    _appendLog('Loaded TXT: ${picked.path} (${text.length} chars)');
  }

  Future<void> _pickCover() async {
    const imageGroup = XTypeGroup(
      label: 'Book cover',
      extensions: ['jpg', 'jpeg', 'png'],
      mimeTypes: ['image/jpeg', 'image/png'],
    );
    final picked = await openFile(acceptedTypeGroups: const [imageGroup]);
    if (picked == null) {
      return;
    }
    final path = picked.path;
    if (path.trim().isEmpty) {
      setState(() => _error = 'Could not read the cover path.');
      return;
    }
    setState(() {
      _coverPath = path;
      _error = null;
    });
    _appendLog('Cover selected: $path');
  }

  Future<void> _importToBackend() async {
    if (_sourceText.trim().isEmpty || _title.trim().isEmpty) {
      setState(() => _error = 'TXT and book title are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _importCurrentBookToBackend();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importCurrentBookToBackend({bool readerOnly = false}) async {
    final selectedLangs = _selectedTargetLangs();
    final imported = <String, String>{};
    final packages = <String, Map<String, dynamic>>{};
    for (final targetLang in selectedLangs) {
      _appendLog(readerOnly
          ? 'Update text import: "$_title" en->$targetLang'
          : 'Import to backend: "$_title" en->$targetLang');
      final package = await widget.api.importMobileBookText(
        title: _title.trim(),
        sourceText: _sourceText,
        targetLang: targetLang,
        readerOnly: readerOnly,
      );
      final meta =
          package['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final bookId =
          (meta['desktop_book_id'] ?? meta['local_book_id'] ?? '').toString();
      if (bookId.isEmpty) {
        throw Exception('Backend did not return book id for $targetLang.');
      }
      imported[targetLang] = bookId;
      packages[targetLang] = readerOnly
          ? package
          : await widget.api.downloadMobileBookPackageChunked(bookId);
      _appendLog(readerOnly
          ? 'Text updated $targetLang book_id=$bookId'
          : 'Imported $targetLang book_id=$bookId');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _bookIdsByTargetLang = imported;
      _packagesByTargetLang = packages;
      _bookId = imported[selectedLangs.first];
    });
  }

  Future<void> _generatePackage() async {
    final bookId = _bookId;
    final selectedVoiceIds = _selectedVoiceIds();
    if (bookId == null || bookId.isEmpty || selectedVoiceIds.isEmpty) {
      setState(() => _error = 'book_id and Kokoro voice are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _generateSelectedVoicePackages(waitForReady: false);
      _syncPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _generateSelectedVoicePackages({
    required bool waitForReady,
  }) async {
    for (final voiceId in _selectedVoiceIds()) {
      await _generateCurrentPackage(
        voiceId: voiceId,
        waitForReady: waitForReady,
      );
    }
  }

  Future<void> _generateCurrentPackage({
    required String voiceId,
    required bool waitForReady,
  }) async {
    final bookId = _bookId;
    if (bookId == null || bookId.isEmpty || voiceId.isEmpty) {
      throw Exception('book_id and Kokoro voice are required.');
    }
    if (_voices.isEmpty) {
      await _loadVoices();
    }
    _appendLog('Generate Kokoro package: book_id=$bookId voice=$voiceId');
    if (mounted) {
      setState(() => _voiceId = voiceId);
    } else {
      _voiceId = voiceId;
    }
    var state = await widget.api.generateTtsPackage(
      bookId: bookId,
      voiceId: voiceId,
      overwrite: false,
      overwriteWordAudio: false,
    );
    if (mounted) {
      setState(() => _packageState = state);
    }
    if (!waitForReady) {
      return;
    }
    while (state.isRunning) {
      await Future<void>.delayed(const Duration(seconds: 2));
      state = await widget.api.getTtsPackageState(
        bookId: bookId,
        voiceId: voiceId,
      );
      if (mounted) {
        setState(() => _packageState = state);
      }
    }
    _appendLog('TTS package status: ${state.status}');
  }

  void _syncPolling() {
    _pollTimer?.cancel();
    final state = _packageState;
    if (state == null || !state.isRunning) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final bookId = _bookId;
      final voiceId = _voiceId;
      if (bookId == null || voiceId == null) {
        return;
      }
      try {
        final next = await widget.api
            .getTtsPackageState(bookId: bookId, voiceId: voiceId);
        if (!mounted) {
          return;
        }
        setState(() => _packageState = next);
        if (!next.isRunning) {
          _pollTimer?.cancel();
          _appendLog('TTS package status: ${next.status}');
        }
      } catch (error) {
        _appendLog('Package polling failed: $error');
      }
    });
  }

  Future<void> _exportFiles() async {
    final bookId = _bookId;
    if (bookId == null || bookId.isEmpty) {
      setState(() => _error = 'Import the book to backend first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _exportCurrentFiles();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _updateCurrentTextOnly() async {
    if (_sourceText.trim().isEmpty || _title.trim().isEmpty) {
      setState(() => _error = 'TXT and book title are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _importCurrentBookToBackend(readerOnly: true);
      await _exportCurrentFiles(textOnly: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _exportCurrentFiles({bool textOnly = false}) async {
    final bookId = _bookId;
    if (bookId == null || bookId.isEmpty) {
      throw Exception('Import the book to backend first.');
    }
    final outputDir = await NoveWorkbenchBuilder(
      api: widget.api,
      level: _level,
      section: _section,
      chapterId: _section == 'chapters' ? _chapterId : '',
      chapterTitle:
          _section == 'chapters' ? noveA1ChapterTitle(_chapterId) : '',
      sourcePath: _sourcePath,
      coverPath: _coverPath,
      log: _appendLog,
      targetLangs: _selectedTargetLangs(),
      bookIdsByTargetLang: _bookIdsByTargetLang,
      packagesByTargetLang: _packagesByTargetLang,
    ).exportFiles(
      bookId: bookId,
      fallbackTitle: _title,
      textOnly: textOnly,
    );
    if (!mounted) {
      return;
    }
    setState(() => _outputPath = outputDir.path);
    _appendLog('Export done: ${outputDir.path}');
  }

  Future<void> _syncLibraryToR2() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await NoveLibraryIndexBuilder(
        libraryDir: Directory('${Directory.current.path}/assets/library'),
        log: _appendLog,
      ).rebuild();
      _appendLog('Sync to R2: r2books:books/nove/library');
      final result = await Process.run(
        'rclone',
        [
          'sync',
          '${Directory.current.path}\\assets\\library',
          'r2books:books/nove/library',
          '--progress',
        ],
      );
      final stdoutText = result.stdout.toString().trim();
      final stderrText = result.stderr.toString().trim();
      if (stdoutText.isNotEmpty) {
        _appendLog(stdoutText);
      }
      if (result.exitCode != 0) {
        throw Exception(
          'R2 sync failed (${result.exitCode}): $stderrText',
        );
      }
      if (stderrText.isNotEmpty) {
        _appendLog(stderrText);
      }
      _appendLog('R2 sync done.');
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _appendLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    if (!mounted) {
      _log = _log.isEmpty ? line : '$_log\n$line';
      return;
    }
    setState(() => _log = _log.isEmpty ? line : '$_log\n$line');
  }

  List<String> _selectedTargetLangs() {
    final selected = [
      for (final lang in _translationLangs)
        if (_targetLangs.contains(lang)) lang,
    ];
    return selected.isEmpty ? const ['ru'] : selected;
  }

  List<String> _selectedVoiceIds() {
    final available = _voices.map((voice) => voice.voiceId).toSet();
    final selected = [
      for (final voiceId in _voiceIds)
        if (available.isEmpty || available.contains(voiceId)) voiceId,
    ]..sort();
    return selected.isEmpty ? const [_fallbackVoiceId] : selected;
  }

  void _toggleTargetLang(String lang, bool selected) {
    final next = Set<String>.of(_targetLangs);
    if (selected) {
      next.add(lang);
    } else if (next.length > 1) {
      next.remove(lang);
    }
    setState(() {
      _targetLangs = next;
      _bookId = null;
      _bookIdsByTargetLang = const {};
      _packagesByTargetLang = const {};
      _packageState = null;
      _outputPath = null;
    });
  }

  void _toggleVoice(String voiceId, bool selected) {
    final next = Set<String>.of(_voiceIds);
    if (selected) {
      next.add(voiceId);
    } else if (next.length > 1) {
      next.remove(voiceId);
    }
    setState(() {
      _voiceIds = next;
      _voiceId = next.contains(_voiceId) ? _voiceId : next.first;
      _packageState = null;
    });
  }

  void _selectLibraryBook(NoveWorkbenchBookSelection selection) {
    setState(() {
      _level = selection.level;
      _section = selection.section;
      if (selection.chapterId.isNotEmpty) {
        _chapterId = selection.chapterId;
      }
      _title = selection.title;
      _titleController.text = selection.title;
      _sourcePath = selection.sourcePath;
      _sourceText = selection.sourceText;
      _coverPath = selection.coverPath;
      _bookId = null;
      _bookIdsByTargetLang = const {};
      _packagesByTargetLang = const {};
      _packageState = null;
      _outputPath = null;
      _error = null;
    });
    _appendLog(
      'Selected library book: ${selection.sourcePath} (${selection.sourceText.length} chars)',
    );
  }

  Future<void> _processLibraryBooks(
      List<NoveWorkbenchBookSelection> selections) async {
    if (selections.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final selection in selections) {
        if (!mounted) {
          return;
        }
        final selectedLangs = _selectedTargetLangs();
        final currentStatus = await _readCurrentExportStatus(selection);
        final hasRequestedLanguages = currentStatus.hasLanguages(selectedLangs);
        final hasRequestedDictionaries =
            currentStatus.hasDictionaries(selectedLangs);
        final selectedVoiceIds = _selectedVoiceIds();
        final hasAudio = currentStatus.hasAudioFor(selectedVoiceIds);
        if (hasRequestedLanguages && hasRequestedDictionaries && hasAudio) {
          if (selection.coverPath.isNotEmpty && !currentStatus.hasCover) {
            _appendLog(
              'Repack ready book: ${selection.title} (add cover, no audio generation)',
            );
            _applyLibrarySelection(selection);
            _bookId = currentStatus.bookId;
            if (_bookId == null || _bookId!.isEmpty) {
              throw Exception(
                  'Cannot repack ${selection.title}: existing book_id not found.');
            }
            await _exportCurrentFiles(textOnly: true);
          } else {
            _appendLog(
              'Skip ready book: ${selection.title} (${selectedLangs.join('+').toUpperCase()}, audio ready)',
            );
          }
          continue;
        }
        _applyLibrarySelection(selection);
        await _importCurrentBookToBackend();
        if (hasAudio) {
          _appendLog(
              'Skip Kokoro package: ${selection.title} already has audio');
        } else {
          await _generateSelectedVoicePackages(waitForReady: true);
        }
        if (hasRequestedLanguages && hasAudio && !hasRequestedDictionaries) {
          final missingDictionaries = selectedLangs
              .where((lang) => !currentStatus.dictionaries.contains(lang))
              .map((lang) => 'dictionary_$lang.json')
              .toList();
          final staleDictionaries = selectedLangs
              .where((lang) =>
                  currentStatus.dictionaries.contains(lang) &&
                  currentStatus.dictionarySources[lang] != 'marian_en_$lang')
              .map((lang) => 'dictionary_$lang.json')
              .toList();
          final reason = [
            if (missingDictionaries.isNotEmpty)
              'missing ${missingDictionaries.join(', ')}',
            if (staleDictionaries.isNotEmpty)
              'stale ${staleDictionaries.join(', ')}',
          ].join('; ');
          _appendLog('Re-export metadata: ${selection.title} ($reason)');
        }
        await _exportCurrentFiles();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _updateLibraryTextOnly(
      List<NoveWorkbenchBookSelection> selections) async {
    if (selections.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final selection in selections) {
        if (!mounted) {
          return;
        }
        _applyLibrarySelection(selection);
        await _importCurrentBookToBackend(readerOnly: true);
        await _exportCurrentFiles(textOnly: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<_WorkbenchExportStatus> _readCurrentExportStatus(
      NoveWorkbenchBookSelection selection) async {
    final outputRoot = Directory(
      '${Directory.current.path}/workbench/output/${selection.level}/${selection.section}',
    );
    final outputDir = await _findOutputDirForSelection(outputRoot, selection);
    final languages = <String>{};
    final dictionaries = <String>{};
    final dictionarySources = <String, String>{};
    final audioVoices = <String>{};
    var bookId = '';
    var hasAudio = false;
    if (outputDir != null) {
      final manifestFile = File('${outputDir.path}/manifest.json');
      if (manifestFile.existsSync()) {
        try {
          final manifest = jsonDecode(await manifestFile.readAsString())
              as Map<String, dynamic>;
          bookId = (manifest['book_id'] ?? '').toString();
        } catch (_) {}
      }
      final ttsManifestFile = File('${outputDir.path}/tts_manifest.json');
      if (ttsManifestFile.existsSync()) {
        try {
          final manifest = jsonDecode(await ttsManifestFile.readAsString())
              as Map<String, dynamic>;
          audioVoices.addAll(_readTtsVoiceIds(manifest));
        } catch (_) {}
      }
      for (final entity in outputDir.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final normalized = entity.path.replaceAll('\\', '/');
        final fileName = normalized.split('/').last;
        final readerMatch =
            RegExp(r'^reader_([a-z]{2})\.json$').firstMatch(fileName);
        if (readerMatch != null) {
          languages.add(readerMatch.group(1)!);
        }
        final dictionaryMatch =
            RegExp(r'^dictionary_([a-z]{2})\.json$').firstMatch(fileName);
        if (dictionaryMatch != null) {
          final lang = dictionaryMatch.group(1)!;
          dictionaries.add(lang);
          dictionarySources[lang] = await _readDictionarySource(entity);
        }
        if (normalized.contains('/audio/segments/') &&
            normalized.endsWith('.mp3')) {
          hasAudio = true;
        }
      }
    }
    final zipStatus = await _readInstalledZipStatus(selection);
    languages.addAll(zipStatus.languages);
    dictionaries.addAll(zipStatus.dictionaries);
    dictionarySources.addAll(zipStatus.dictionarySources);
    audioVoices.addAll(zipStatus.audioVoices);
    if (bookId.isEmpty) {
      bookId = zipStatus.bookId;
    }
    hasAudio = hasAudio || zipStatus.hasAudio;
    if (hasAudio && audioVoices.isEmpty) {
      audioVoices.add(_fallbackVoiceId);
    }
    final hasCover = await _hasOutputCover(outputDir) || zipStatus.hasCover;
    return _WorkbenchExportStatus(
      bookId: bookId,
      languages: languages,
      dictionaries: dictionaries,
      dictionarySources: dictionarySources,
      hasAudio: hasAudio,
      audioVoices: audioVoices,
      hasCover: hasCover,
    );
  }

  Future<bool> _hasOutputCover(Directory? outputDir) async {
    if (outputDir == null || !outputDir.existsSync()) {
      return false;
    }
    for (final name in const ['cover.png', 'cover.jpg', 'cover.jpeg']) {
      if (File('${outputDir.path}/$name').existsSync()) {
        return true;
      }
    }
    return false;
  }

  Future<Directory?> _findOutputDirForSelection(
    Directory outputRoot,
    NoveWorkbenchBookSelection selection,
  ) async {
    if (!outputRoot.existsSync()) {
      return null;
    }
    for (final entity in outputRoot.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final manifestFile = File('${entity.path}/manifest.json');
      if (!manifestFile.existsSync()) {
        continue;
      }
      try {
        final manifest = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        if ((manifest['title'] ?? '').toString().trim() != selection.title) {
          continue;
        }
        if ((manifest['level'] ?? '').toString() != selection.level ||
            (manifest['section'] ?? '').toString() != selection.section) {
          continue;
        }
        if ((manifest['chapter_id'] ?? '').toString() != selection.chapterId) {
          continue;
        }
        return entity;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<_WorkbenchExportStatus> _readInstalledZipStatus(
      NoveWorkbenchBookSelection selection) async {
    final zipRoot = Directory(
      '${Directory.current.path}/assets/library/${selection.level}/${selection.section}/books_zip',
    );
    if (!zipRoot.existsSync()) {
      return const _WorkbenchExportStatus(
        bookId: '',
        languages: <String>{},
        dictionaries: <String>{},
        dictionarySources: <String, String>{},
        hasAudio: false,
        audioVoices: <String>{},
        hasCover: false,
      );
    }
    for (final entity in zipRoot.listSync()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.zip')) {
        continue;
      }
      try {
        final archive = ZipDecoder().decodeBytes(await entity.readAsBytes());
        final manifestFile = archive.files
            .where((file) => file.isFile && file.name == 'manifest.json')
            .firstOrNull;
        if (manifestFile == null) {
          continue;
        }
        final manifest = jsonDecode(
          utf8.decode(manifestFile.content as List<int>),
        ) as Map<String, dynamic>;
        if ((manifest['title'] ?? '').toString().trim() != selection.title) {
          continue;
        }
        if ((manifest['level'] ?? '').toString() != selection.level ||
            (manifest['section'] ?? '').toString() != selection.section ||
            (manifest['chapter_id'] ?? '').toString() != selection.chapterId) {
          continue;
        }
        final languages = <String>{};
        final dictionaries = <String>{};
        final dictionarySources = <String, String>{};
        final audioVoices = <String>{};
        final bookId = (manifest['book_id'] ?? '').toString();
        for (final file in archive.files) {
          if (!file.isFile) {
            continue;
          }
          final match =
              RegExp(r'^reader_([a-z]{2})\.json$').firstMatch(file.name);
          if (match != null) {
            languages.add(match.group(1)!);
          }
          final dictionaryMatch =
              RegExp(r'^dictionary_([a-z]{2})\.json$').firstMatch(file.name);
          if (dictionaryMatch != null) {
            final lang = dictionaryMatch.group(1)!;
            dictionaries.add(lang);
            dictionarySources[lang] = _dictionarySourceFromJsonBytes(
              file.content as List<int>,
            );
          }
          if (file.name == 'tts_manifest.json') {
            try {
              final ttsManifest =
                  jsonDecode(utf8.decode(file.content as List<int>))
                      as Map<String, dynamic>;
              audioVoices.addAll(_readTtsVoiceIds(ttsManifest));
            } catch (_) {}
          }
        }
        final hasAudio = archive.files.any((file) =>
            file.isFile &&
            file.name.startsWith('audio/segments/') &&
            file.name.endsWith('.mp3'));
        if (hasAudio && audioVoices.isEmpty) {
          audioVoices.add(_fallbackVoiceId);
        }
        final hasCover = archive.files.any((file) =>
            file.isFile &&
            const ['cover.png', 'cover.jpg', 'cover.jpeg'].contains(file.name));
        return _WorkbenchExportStatus(
          bookId: bookId,
          languages: languages,
          dictionaries: dictionaries,
          dictionarySources: dictionarySources,
          hasAudio: hasAudio,
          audioVoices: audioVoices,
          hasCover: hasCover,
        );
      } catch (_) {
        continue;
      }
    }
    return const _WorkbenchExportStatus(
      bookId: '',
      languages: <String>{},
      dictionaries: <String>{},
      dictionarySources: <String, String>{},
      hasAudio: false,
      audioVoices: <String>{},
      hasCover: false,
    );
  }

  Set<String> _readTtsVoiceIds(Map<String, dynamic> manifest) {
    final result = <String>{};
    final profiles = manifest['profiles'] as List<dynamic>? ?? const [];
    for (final profile in profiles.whereType<Map>()) {
      final voiceId = (profile['voice_id'] ?? '').toString();
      if (voiceId.isNotEmpty) {
        result.add(voiceId);
      }
    }
    final jobs = manifest['jobs'] as List<dynamic>? ?? const [];
    for (final job in jobs.whereType<Map>()) {
      final voiceId = (job['voice_id'] ?? '').toString();
      if (voiceId.isNotEmpty) {
        result.add(voiceId);
      }
    }
    return result;
  }

  Future<String> _readDictionarySource(File file) async {
    try {
      return _dictionarySourceFromJsonBytes(await file.readAsBytes());
    } catch (_) {
      return '';
    }
  }

  String _dictionarySourceFromJsonBytes(List<int> bytes) {
    try {
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return (payload['source'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  void _applyLibrarySelection(NoveWorkbenchBookSelection selection) {
    _level = selection.level;
    _section = selection.section;
    if (selection.chapterId.isNotEmpty) {
      _chapterId = selection.chapterId;
    }
    _title = selection.title;
    _titleController.text = selection.title;
    _sourcePath = selection.sourcePath;
    _sourceText = selection.sourceText;
    _coverPath = selection.coverPath;
    _bookId = null;
    _bookIdsByTargetLang = const {};
    _packagesByTargetLang = const {};
    _packageState = null;
    _outputPath = null;
    _error = null;
    _appendLog(
      'Selected library book: ${selection.sourcePath} (${selection.sourceText.length} chars)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canImport =
        !_busy && _sourceText.trim().isNotEmpty && _title.trim().isNotEmpty;
    final canGenerate =
        !_busy && (_bookId ?? '').isNotEmpty && _selectedVoiceIds().isNotEmpty;
    final canExport = !_busy && (_bookId ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Nove Workbench')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            NoveWorkbenchBookLibrary(
              busy: _busy,
              onSelected: _selectLibraryBook,
              onProcessAll: _processLibraryBooks,
              onUpdateTextOnly: _updateLibraryTextOnly,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pickTxt,
                  icon: const Icon(Icons.text_snippet_outlined),
                  label: const Text('Load TXT'),
                ),
                FilledButton.icon(
                  onPressed: canImport ? _importToBackend : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Import to backend'),
                ),
                FilledButton.icon(
                  onPressed: canGenerate ? _generatePackage : null,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: const Text('Generate Kokoro package'),
                ),
                FilledButton.icon(
                  onPressed: canExport ? _exportFiles : null,
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('Export files'),
                ),
                OutlinedButton.icon(
                  onPressed: canImport ? _updateCurrentTextOnly : null,
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Update text only'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _syncLibraryToR2,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Sync to R2'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Book title',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _title = value,
            ),
            const SizedBox(height: 12),
            NoveWorkbenchCoverPickerPanel(
              coverPath: _coverPath,
              busy: _busy,
              onPickCover: _pickCover,
              onClearCover: _coverPath.isEmpty
                  ? null
                  : () => setState(() => _coverPath = ''),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _level,
                    decoration: const InputDecoration(
                        labelText: 'Level', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'a1', child: Text('A1')),
                      DropdownMenuItem(value: 'a2', child: Text('A2')),
                      DropdownMenuItem(value: 'b1', child: Text('B1')),
                      DropdownMenuItem(value: 'b2', child: Text('B2')),
                      DropdownMenuItem(value: 'c1', child: Text('C1')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _level = value ?? _level),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _section,
                    decoration: const InputDecoration(
                        labelText: 'Section', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'chapters', child: Text('Chapters')),
                      DropdownMenuItem(
                          value: 'more_a1_stories',
                          child: Text('More A1 Stories')),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) =>
                            setState(() => _section = value ?? _section),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_section == 'chapters') ...[
              DropdownButtonFormField<String>(
                value: _chapterId,
                decoration: const InputDecoration(
                  labelText: 'A1 chapter',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final chapter in noveA1Chapters)
                    DropdownMenuItem(
                      value: chapter.id,
                      child: Text(chapter.title),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) =>
                        setState(() => _chapterId = value ?? _chapterId),
              ),
              const SizedBox(height: 12),
            ],
            NoveWorkbenchTranslationLanguagePanel(
              selectedLangs: _targetLangs,
              busy: _busy,
              onChanged: _toggleTargetLang,
            ),
            const SizedBox(height: 12),
            NoveWorkbenchVoicePanel(
              voices: _voices,
              selectedVoiceIds: _voiceIds,
              busy: _busy,
              onChanged: _toggleVoice,
            ),
            const SizedBox(height: 18),
            NoveWorkbenchStatusPanel(
              sourcePath: _sourcePath,
              coverPath: _coverPath,
              bookId: _bookId,
              outputPath: _outputPath,
              packageState: _packageState,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 18),
            SelectableText(
              _log.isEmpty ? 'Log is empty.' : _log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
