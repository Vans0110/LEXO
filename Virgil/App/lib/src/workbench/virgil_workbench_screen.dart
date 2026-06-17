import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../mobile/virgil_a1_chapters.dart';
import 'virgil_workbench_book_status.dart';
import 'virgil_workbench_book_library.dart';
import 'virgil_workbench_library_models.dart';
import 'virgil_workbench_builder.dart';
import 'virgil_workbench_paths.dart';
import 'virgil_workbench_form_panels.dart';
import 'virgil_library_index_builder.dart';
import 'virgil_workbench_status_panel.dart';

const _ruContextDictionarySource = 'wiktionary_freedict_nllb_en_ru_context_v3';
const _ukContextDictionarySource = 'wiktionary_nllb_en_uk_context_v3';

String _expectedDictionarySource(String lang) =>
    lang == 'uk' ? _ukContextDictionarySource : _ruContextDictionarySource;

class VirgilWorkbenchScreen extends StatefulWidget {
  const VirgilWorkbenchScreen({super.key, required this.api});

  final LexoApiClient api;

  @override
  State<VirgilWorkbenchScreen> createState() => _VirgilWorkbenchScreenState();
}

class _WorkbenchExportStatus {
  const _WorkbenchExportStatus({
    required this.bookId,
    required this.languages,
    required this.dictionaries,
    required this.dictionarySources,
    required this.hasAudio,
    required this.audioVoices,
    required this.profileVoices,
    required this.hasCover,
  });

  final String bookId;
  final Set<String> languages;
  final Set<String> dictionaries;
  final Map<String, String> dictionarySources;
  final bool hasAudio;
  final Set<String> audioVoices;
  final Set<String> profileVoices;
  final bool hasCover;

  bool hasLanguages(Iterable<String> targetLanguages) =>
      targetLanguages.every(languages.contains);

  bool hasDictionaries(Iterable<String> targetLanguages) =>
      targetLanguages.every((lang) =>
          dictionaries.contains(lang) &&
          dictionarySources[lang] == _expectedDictionarySource(lang));

  bool hasAudioFor(Iterable<String> voiceIds) =>
      voiceIds.every(audioVoices.contains);

  Set<String> missingProfileVoicesFor(Iterable<String> availableVoiceIds) {
    final available = availableVoiceIds.toSet();
    return profileVoices
        .difference(audioVoices)
        .where(available.contains)
        .toSet();
  }
}

class _VirgilWorkbenchScreenState extends State<VirgilWorkbenchScreen> {
  static const _levels = ['a1', 'a2', 'b1', 'b2', 'c1'];
  static const _sections = ['chapters', 'more_a1_stories'];
  static const _translationLangs = ['ru', 'uk'];
  static const _fallbackVoiceId = 'af_heart';

  String _level = _levels.first;
  String _section = _sections.first;
  String _chapterId = virgilDefaultA1ChapterId;
  Set<String> _targetLangs = {'ru'};
  String _title = '';
  String _sourceText = '';
  String _sourcePath = '';
  String _coverPath = '';
  String? _bookId;
  Map<String, String> _bookIdsByTargetLang = const {};
  Map<String, Map<String, dynamic>> _packagesByTargetLang = const {};
  Set<String> _dictionaryLangs = {'ru'};
  String? _voiceId = _fallbackVoiceId;
  Set<String> _voiceIds = {_fallbackVoiceId};
  bool _busy = false;
  String? _error;
  String? _outputPath;
  String _log = '';
  List<TtsProfile> _voices = const [];
  TtsPackageState? _packageState;
  GoogleTranslateUsage? _googleUsage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVoices());
    unawaited(_loadGoogleUsage());
  }

  @override
  void dispose() {
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

  Future<void> _loadGoogleUsage() async {
    try {
      final usage = await widget.api.getGoogleTranslateUsage();
      if (!mounted) {
        return;
      }
      setState(() => _googleUsage = usage);
    } catch (error) {
      _appendLog('Google usage load failed: $error');
    }
  }

  Future<void> _importCurrentBookToBackend({
    bool readerOnly = false,
    required List<String> selectedLangs,
  }) async {
    if (selectedLangs.isEmpty) {
      return;
    }
    await _confirmGoogleTranslationUse(
      selectedLangs: selectedLangs,
      readerOnly: readerOnly,
    );
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
        stableBookKey: _stableBookKey(),
      );
      final meta =
          package['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final bookId =
          (meta['desktop_book_id'] ?? meta['local_book_id'] ?? '').toString();
      if (bookId.isEmpty) {
        throw Exception('Backend did not return book id for $targetLang.');
      }
      imported[targetLang] = bookId;
      packages[targetLang] = package;
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

  Future<void> _confirmGoogleTranslationUse({
    required List<String> selectedLangs,
    required bool readerOnly,
  }) async {
    final estimatedPerLang = _estimateGoogleCharacters('$_title\n$_sourceText');
    final estimatedTotal = estimatedPerLang * selectedLangs.length;
    if (estimatedTotal <= 0) {
      return;
    }
    await _loadGoogleUsage();
    final usage = _googleUsage;
    final used = usage?.characterCount ?? 0;
    final safetyLimit = usage?.safetyLimit ?? 5000;
    final freeLimit = usage?.freeCharacterLimit ?? 500000;
    final after = used + estimatedTotal;
    if (after > safetyLimit) {
      throw Exception(
        'Google limit blocked: $used + $estimatedTotal > $safetyLimit chars.',
      );
    }
    if (!mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Use Google Translation?'),
        content: Text(
          '${readerOnly ? 'Update text' : 'Process book'} will send about '
          '${_formatCount(estimatedTotal)} chars to Google for '
          '${selectedLangs.map((lang) => lang.toUpperCase()).join('+')}.\n\n'
          'Current month used: ${_formatCount(used)} chars.\n'
          'Work cap: up to ${_formatCount(safetyLimit)} chars; '
          'after this: ${_formatCount(after)}.\n'
          'Free tier: ${_formatCount(used)} / ${_formatCount(freeLimit)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use Google'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      throw Exception('Google translation was not confirmed.');
    }
  }

  Future<void> _generateVoicePackages({
    required Iterable<String> voiceIds,
    required bool waitForReady,
    bool overwrite = false,
  }) async {
    final normalizedVoiceIds = voiceIds
        .map((voiceId) => voiceId.trim())
        .where((voiceId) => voiceId.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    for (final voiceId in normalizedVoiceIds) {
      await _generateCurrentPackage(
        voiceId: voiceId,
        waitForReady: waitForReady,
        overwrite: overwrite,
      );
    }
  }

  Future<void> _generateCurrentPackage({
    required String voiceId,
    required bool waitForReady,
    bool overwrite = false,
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
      overwrite: overwrite,
      overwriteWordAudio: overwrite,
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

  Future<void> _exportCurrentFiles({
    bool textOnly = false,
    required List<String> targetLangs,
  }) async {
    final bookId = _bookId;
    if (bookId == null || bookId.isEmpty) {
      throw Exception('Import the book to backend first.');
    }
    final outputDir = await VirgilWorkbenchBuilder(
      api: widget.api,
      level: _level,
      section: _section,
      chapterId: _section == 'chapters' ? _chapterId : '',
      chapterTitle:
          _section == 'chapters' ? virgilA1ChapterTitle(_chapterId) : '',
      sourcePath: _sourcePath,
      coverPath: _coverPath,
      log: _appendLog,
      targetLangs: targetLangs,
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
    unawaited(_loadGoogleUsage());
    _appendLog('Export done: ${outputDir.path}');
  }

  Future<void> _syncLibraryToR2() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final indexBuilder = VirgilLibraryIndexBuilder(
        libraryDir: VirgilWorkbenchPaths.cloudLibrary,
        log: _appendLog,
      );
      final outputStatuses = await VirgilWorkbenchBookStatusLoader(
        appRoot: VirgilWorkbenchPaths.workspaceRoot,
      ).loadOutputStatuses();
      await indexBuilder.removeBooksMissingFrom(
        VirgilWorkbenchPaths.books,
        outputStatuses: outputStatuses,
      );
      await indexBuilder.rebuild();
      _appendLog('Upload book files to R2 (index excluded)');
      final filesResult = await Process.run(
        'rclone',
        [
          'copy',
          VirgilWorkbenchPaths.cloudLibrary.path,
          'r2books:books/virgil/library',
          '--exclude',
          'library_index.json',
          '--s3-no-check-bucket',
          '--progress',
        ],
      );
      final stdoutText = filesResult.stdout.toString().trim();
      final stderrText = filesResult.stderr.toString().trim();
      if (stdoutText.isNotEmpty) {
        _appendLog(stdoutText);
      }
      if (filesResult.exitCode != 0) {
        throw Exception(
          'R2 file upload failed (${filesResult.exitCode}): $stderrText',
        );
      }
      if (stderrText.isNotEmpty) {
        _appendLog(stderrText);
      }
      _appendLog('Publish library_index.json last');
      final indexResult = await Process.run(
        'rclone',
        [
          'copy',
          '${VirgilWorkbenchPaths.cloudLibrary.path}\\library_index.json',
          'r2books:books/virgil/library',
          '--s3-no-check-bucket',
          '--progress',
        ],
      );
      final indexStdout = indexResult.stdout.toString().trim();
      final indexStderr = indexResult.stderr.toString().trim();
      if (indexStdout.isNotEmpty) {
        _appendLog(indexStdout);
      }
      if (indexResult.exitCode != 0) {
        throw Exception(
          'R2 index publish failed (${indexResult.exitCode}): $indexStderr',
        );
      }
      if (indexStderr.isNotEmpty) {
        _appendLog(indexStderr);
      }
      _appendLog('Remove stale R2 files after index publish');
      final cleanupResult = await Process.run(
        'rclone',
        [
          'sync',
          VirgilWorkbenchPaths.cloudLibrary.path,
          'r2books:books/virgil/library',
          '--exclude',
          'library_index.json',
          '--s3-no-check-bucket',
          '--progress',
        ],
      );
      final cleanupStdout = cleanupResult.stdout.toString().trim();
      final cleanupStderr = cleanupResult.stderr.toString().trim();
      if (cleanupStdout.isNotEmpty) {
        _appendLog(cleanupStdout);
      }
      if (cleanupResult.exitCode != 0) {
        throw Exception(
          'R2 stale file cleanup failed (${cleanupResult.exitCode}): '
          '$cleanupStderr',
        );
      }
      if (cleanupStderr.isNotEmpty) {
        _appendLog(cleanupStderr);
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
    return selected;
  }

  List<String> _selectedDictionaryLangs() {
    final selected = [
      for (final lang in _translationLangs)
        if (_dictionaryLangs.contains(lang)) lang,
    ];
    return selected;
  }

  int _estimateGoogleCharacters(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (_isAsciiLetterOrDigit(rune) ||
          char.trim().isEmpty ||
          '.,!?'.contains(char)) {
        buffer.write(char);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim().length;
  }

  bool _isAsciiLetterOrDigit(int rune) {
    return (rune >= 48 && rune <= 57) ||
        (rune >= 65 && rune <= 90) ||
        (rune >= 97 && rune <= 122);
  }

  String _formatCount(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index += 1) {
      final remaining = text.length - index;
      buffer.write(text[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  String _stableBookKey() {
    final chapterKey = _section == 'chapters' ? _chapterId : '';
    return [
      'virgil',
      _level.trim().toLowerCase(),
      _section.trim().toLowerCase(),
      chapterKey.trim().toLowerCase(),
      _title.trim().toLowerCase(),
    ].join('|');
  }

  List<String> _selectedVoiceIds() {
    final available = _voices.map((voice) => voice.voiceId).toSet();
    final selected = [
      for (final voiceId in _voiceIds)
        if (available.isEmpty || available.contains(voiceId)) voiceId,
    ]..sort();
    return selected;
  }

  void _toggleTargetLang(String lang, bool selected) {
    final next = Set<String>.of(_targetLangs);
    if (selected) {
      next.add(lang);
    } else {
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

  void _toggleDictionaryLang(String lang, bool selected) {
    final next = Set<String>.of(_dictionaryLangs);
    if (selected) {
      next.add(lang);
    } else {
      next.remove(lang);
    }
    setState(() {
      _dictionaryLangs = next;
      _packageState = null;
      _outputPath = null;
    });
  }

  void _toggleVoice(String voiceId, bool selected) {
    final next = Set<String>.of(_voiceIds);
    if (selected) {
      next.add(voiceId);
    } else {
      next.remove(voiceId);
    }
    setState(() {
      _voiceIds = next;
      _voiceId = next.contains(_voiceId)
          ? _voiceId
          : (next.isEmpty ? null : next.first);
      _packageState = null;
    });
  }

  void _selectLibraryBook(VirgilWorkbenchBookSelection selection) {
    setState(() {
      _level = selection.level;
      _section = selection.section;
      if (selection.chapterId.isNotEmpty) {
        _chapterId = selection.chapterId;
      }
      _title = selection.title;
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

  Future<void> _updateLibraryTextOnly(
    List<VirgilWorkbenchBookSelection> selections, {
    required List<String> languages,
  }) async {
    if (selections.isEmpty || languages.isEmpty) {
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
        await _importCurrentBookToBackend(
          readerOnly: true,
          selectedLangs: languages,
        );
        await _exportCurrentFiles(textOnly: true, targetLangs: languages);
      }
      unawaited(_loadGoogleUsage());
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

  Future<void> _updateLibraryDictionariesOnly(
    List<VirgilWorkbenchBookSelection> selections, {
    required List<String> languages,
  }) async {
    if (selections.isEmpty || languages.isEmpty) {
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
        final currentStatus = await _readCurrentExportStatus(selection);
        if (currentStatus.bookId.isEmpty) {
          throw Exception(
            'Cannot refresh dictionaries for ${selection.title}: '
            'existing book_id was not found. Run Text first.',
          );
        }
        _applyLibrarySelection(selection);
        _bookId = currentStatus.bookId;
        _bookIdsByTargetLang = {
          for (final lang in languages) lang: currentStatus.bookId,
        };
        final outputDir = await VirgilWorkbenchBuilder(
          api: widget.api,
          level: _level,
          section: _section,
          chapterId: _section == 'chapters' ? _chapterId : '',
          chapterTitle:
              _section == 'chapters' ? virgilA1ChapterTitle(_chapterId) : '',
          sourcePath: _sourcePath,
          coverPath: _coverPath,
          log: _appendLog,
          targetLangs: languages,
          bookIdsByTargetLang: _bookIdsByTargetLang,
          packagesByTargetLang: const {},
        ).refreshDictionaries(
          bookId: currentStatus.bookId,
          fallbackTitle: selection.title,
          languages: languages,
        );
        if (mounted) {
          setState(() => _outputPath = outputDir.path);
        }
        _appendLog('Dictionary refresh done: ${outputDir.path}');
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

  Future<void> _startLibraryBooks(
      List<VirgilWorkbenchBookSelection> selections) async {
    if (selections.isEmpty) {
      return;
    }
    final selectedTextLangs = _selectedTargetLangs();
    final selectedDictionaryLangs = _selectedDictionaryLangs();
    final selectedVoiceIds = _selectedVoiceIds();
    if (selectedTextLangs.isEmpty &&
        selectedDictionaryLangs.isEmpty &&
        selectedVoiceIds.isEmpty) {
      return;
    }
    if (selectedTextLangs.isNotEmpty) {
      await _updateLibraryTextOnly(
        selections,
        languages: selectedTextLangs,
      );
    }
    if (selectedDictionaryLangs.isNotEmpty) {
      await _updateLibraryDictionariesOnly(
        selections,
        languages: selectedDictionaryLangs,
      );
    }
    if (selectedVoiceIds.isNotEmpty) {
      await _updateLibraryAudioOnly(selections);
    }
  }

  Future<void> _updateLibraryAudioOnly(
      List<VirgilWorkbenchBookSelection> selections) async {
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
        final currentStatus = await _readCurrentExportStatus(selection);
        if (currentStatus.bookId.isEmpty) {
          throw Exception(
            'Cannot refresh voices for ${selection.title}: '
            'existing book_id was not found.',
          );
        }
        _applyLibrarySelection(selection);
        _bookId = currentStatus.bookId;
        final selectedVoiceIds = _selectedVoiceIds();
        _appendLog(
          'Rewrite voices only: ${selection.title} '
          '(${selectedVoiceIds.join(', ')})',
        );
        await _generateVoicePackages(
          voiceIds: selectedVoiceIds,
          waitForReady: true,
          overwrite: true,
        );
        final outputDir = await VirgilWorkbenchBuilder(
          api: widget.api,
          level: _level,
          section: _section,
          chapterId: _section == 'chapters' ? _chapterId : '',
          chapterTitle:
              _section == 'chapters' ? virgilA1ChapterTitle(_chapterId) : '',
          sourcePath: _sourcePath,
          coverPath: _coverPath,
          log: _appendLog,
          targetLangs: _selectedTargetLangs(),
          bookIdsByTargetLang: const {},
          packagesByTargetLang: const {},
        ).refreshAudio(
          bookId: currentStatus.bookId,
          fallbackTitle: selection.title,
        );
        if (mounted) {
          setState(() => _outputPath = outputDir.path);
        }
        _appendLog('Voice refresh done: ${outputDir.path}');
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

  List<VirgilWorkbenchBookSelection> _selectedLibraryBooks =
      const <VirgilWorkbenchBookSelection>[];
  int _libraryRefreshRevision = 0;

  Future<void> _cleanCurrentBookArtifacts() async {
    final selections = _selectedLibraryBooks.isNotEmpty
        ? _selectedLibraryBooks
        : <VirgilWorkbenchBookSelection>[
            if (_title.trim().isNotEmpty)
              VirgilWorkbenchBookSelection(
                level: _level,
                section: _section,
                chapterId: _section == 'chapters' ? _chapterId : '',
                title: _title.trim(),
                sourcePath: _sourcePath,
                sourceText: _sourceText,
                coverPath: _coverPath,
                exportedLanguages: const <String>{},
                hasAudio: false,
              ),
          ];
    if (selections.isEmpty) {
      setState(() => _error = 'Select or load a book before cleaning.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          selections.length == 1
              ? 'Clean "${selections.single.title}"?'
              : 'Clean ${selections.length} books?',
        ),
        content: const Text(
          'This deletes generated output, installed ZIP files, and matching '
          'backend books. Source TXT files, covers, and Cloudflare R2 are not '
          'changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clean'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final selection in selections) {
        final currentBookId =
            selections.length == 1 && selection.sourcePath == _sourcePath
                ? _bookId
                : null;
        await _cleanBookArtifacts(
          selection,
          currentBookId: currentBookId,
        );
      }
      if (mounted) {
        setState(() {
          _bookId = null;
          _bookIdsByTargetLang = const {};
          _packagesByTargetLang = const {};
          _packageState = null;
          _outputPath = null;
          _selectedLibraryBooks = const <VirgilWorkbenchBookSelection>[];
          _libraryRefreshRevision++;
        });
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

  Future<void> _cleanBookArtifacts(
    VirgilWorkbenchBookSelection selection, {
    String? currentBookId,
  }) async {
    final outputRoot = Directory(
      '${VirgilWorkbenchPaths.output.path}/${selection.level}/${selection.section}',
    );
    final outputDir = await _findOutputDirForSelection(outputRoot, selection);
    final status = await _readCurrentExportStatus(selection);
    final bookIds = <String>{
      if ((currentBookId ?? '').isNotEmpty) currentBookId!,
      if (status.bookId.isNotEmpty) status.bookId,
    };
    if (outputDir != null && outputDir.existsSync()) {
      final outputZip = File(
        '${outputDir.parent.path}/${outputDir.uri.pathSegments.where((segment) => segment.isNotEmpty).last}.zip',
      );
      await outputDir.delete(recursive: true);
      _appendLog('Clean output dir: ${outputDir.path}');
      if (outputZip.existsSync()) {
        await outputZip.delete();
        _appendLog('Clean output zip: ${outputZip.path}');
      }
    } else {
      _appendLog('Clean output dir: nothing found for ${selection.title}');
    }
    final deletedInstalledZips =
        await _deleteInstalledZipsForSelection(selection);
    for (final path in deletedInstalledZips) {
      _appendLog('Clean installed zip: $path');
    }
    for (final bookId in bookIds) {
      try {
        await widget.api.deleteBook(bookId);
        _appendLog('Clean backend book: $bookId');
      } catch (error) {
        _appendLog('Clean backend book skipped: $bookId ($error)');
      }
    }
  }

  Future<_WorkbenchExportStatus> _readCurrentExportStatus(
      VirgilWorkbenchBookSelection selection) async {
    final outputRoot = Directory(
      '${VirgilWorkbenchPaths.output.path}/${selection.level}/${selection.section}',
    );
    final outputDir = await _findOutputDirForSelection(outputRoot, selection);
    final languages = <String>{};
    final dictionaries = <String>{};
    final dictionarySources = <String, String>{};
    final audioVoices = <String>{};
    final profileVoices = <String>{};
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
          profileVoices.addAll(_readTtsProfileVoiceIds(manifest));
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
    profileVoices.addAll(zipStatus.profileVoices);
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
      profileVoices: profileVoices,
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
    VirgilWorkbenchBookSelection selection,
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
      VirgilWorkbenchBookSelection selection) async {
    final zipRoot = Directory(
      '${VirgilWorkbenchPaths.cloudLibrary.path}/${selection.level}/${selection.section}/books_zip',
    );
    if (!zipRoot.existsSync()) {
      return const _WorkbenchExportStatus(
        bookId: '',
        languages: <String>{},
        dictionaries: <String>{},
        dictionarySources: <String, String>{},
        hasAudio: false,
        audioVoices: <String>{},
        profileVoices: <String>{},
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
        final profileVoices = <String>{};
        final bookId = (manifest['book_id'] ?? '').toString();
        for (final file in archive.files) {
          if (!file.isFile) {
            continue;
          }
          if (_isChapterImagesPath(file.name)) {
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
              profileVoices.addAll(_readTtsProfileVoiceIds(ttsManifest));
            } catch (_) {}
          }
        }
        final hasAudio = archive.files.any((file) =>
            file.isFile &&
            !_isChapterImagesPath(file.name) &&
            file.name.startsWith('audio/segments/') &&
            file.name.endsWith('.mp3'));
        if (hasAudio && audioVoices.isEmpty) {
          audioVoices.add(_fallbackVoiceId);
        }
        final hasCover = archive.files.any((file) =>
            file.isFile &&
            !_isChapterImagesPath(file.name) &&
            const ['cover.png', 'cover.jpg', 'cover.jpeg'].contains(file.name));
        return _WorkbenchExportStatus(
          bookId: bookId,
          languages: languages,
          dictionaries: dictionaries,
          dictionarySources: dictionarySources,
          hasAudio: hasAudio,
          audioVoices: audioVoices,
          profileVoices: profileVoices,
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
      profileVoices: <String>{},
      hasCover: false,
    );
  }

  Future<List<String>> _deleteInstalledZipsForSelection(
      VirgilWorkbenchBookSelection selection) async {
    final zipRoot = Directory(
      '${VirgilWorkbenchPaths.cloudLibrary.path}/${selection.level}/${selection.section}/books_zip',
    );
    if (!zipRoot.existsSync()) {
      return const <String>[];
    }
    final deleted = <String>[];
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
        final path = entity.path;
        await entity.delete();
        deleted.add(path);
      } catch (_) {
        continue;
      }
    }
    return deleted;
  }

  Set<String> _readTtsVoiceIds(Map<String, dynamic> manifest) {
    final result = <String>{};
    final jobs = manifest['jobs'] as List<dynamic>? ?? const [];
    for (final job in jobs.whereType<Map>()) {
      if ((job['status'] ?? '').toString() != 'ready') {
        continue;
      }
      final voiceId = (job['voice_id'] ?? '').toString();
      if (voiceId.isNotEmpty) {
        result.add(voiceId);
      }
    }
    return result;
  }

  Set<String> _readTtsProfileVoiceIds(Map<String, dynamic> manifest) {
    final result = <String>{};
    final profiles = manifest['profiles'] as List<dynamic>? ?? const [];
    for (final profile in profiles.whereType<Map>()) {
      final voiceId = (profile['voice_id'] ?? '').toString();
      if (voiceId.isNotEmpty) {
        result.add(voiceId);
      }
    }
    return result;
  }

  bool _isChapterImagesPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized == 'chapter_images' ||
        normalized.contains('/chapter_images/') ||
        normalized.startsWith('chapter_images/');
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

  void _applyLibrarySelection(VirgilWorkbenchBookSelection selection) {
    _level = selection.level;
    _section = selection.section;
    if (selection.chapterId.isNotEmpty) {
      _chapterId = selection.chapterId;
    }
    _title = selection.title;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Virgil Workbench')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            VirgilWorkbenchGoogleUsagePanel(
              key: const ValueKey('google-usage-panel'),
              usage: _googleUsage,
            ),
            const SizedBox(
              key: ValueKey('after-google-usage-panel'),
              height: 12,
            ),
            VirgilWorkbenchBookLibrary(
              key: const ValueKey('workbench-book-library'),
              busy: _busy,
              canStartActions: _targetLangs.isNotEmpty ||
                  _dictionaryLangs.isNotEmpty ||
                  _voiceIds.isNotEmpty,
              onSelected: _selectLibraryBook,
              onStart: _startLibraryBooks,
              onClean: _cleanCurrentBookArtifacts,
              onSyncToR2: _syncLibraryToR2,
              onSelectionChanged: (selections) =>
                  setState(() => _selectedLibraryBooks = selections),
              refreshRevision: _libraryRefreshRevision,
            ),
            const SizedBox(
              key: ValueKey('after-book-library'),
              height: 18,
            ),
            VirgilWorkbenchTranslationLanguagePanel(
              key: const ValueKey('translation-language-panel'),
              selectedLangs: _targetLangs,
              busy: _busy,
              onChanged: _toggleTargetLang,
            ),
            const SizedBox(
              key: ValueKey('after-translation-language-panel'),
              height: 12,
            ),
            VirgilWorkbenchDictionaryLanguagePanel(
              key: const ValueKey('dictionary-language-panel'),
              selectedLangs: _dictionaryLangs,
              busy: _busy,
              onChanged: _toggleDictionaryLang,
            ),
            const SizedBox(
              key: ValueKey('after-dictionary-language-panel'),
              height: 12,
            ),
            VirgilWorkbenchVoicePanel(
              key: const ValueKey('voice-panel'),
              voices: _voices,
              selectedVoiceIds: _voiceIds,
              busy: _busy,
              onChanged: _toggleVoice,
            ),
            const SizedBox(
              key: ValueKey('after-voice-panel'),
              height: 18,
            ),
            VirgilWorkbenchStatusPanel(
              key: const ValueKey('status-panel'),
              sourcePath: _sourcePath,
              coverPath: _coverPath,
              bookId: _bookId,
              outputPath: _outputPath,
              packageState: _packageState,
            ),
            if (_error != null) ...[
              const SizedBox(
                key: ValueKey('before-error'),
                height: 12,
              ),
              Text(_error!,
                  key: const ValueKey('workbench-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(
              key: ValueKey('before-log'),
              height: 18,
            ),
            SelectableText(
              _log.isEmpty ? 'Log is empty.' : _log,
              key: const ValueKey('workbench-log'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
