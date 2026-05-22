import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../mobile/nove_a1_chapters.dart';

class NoveWorkbenchBookSelection {
  const NoveWorkbenchBookSelection({
    required this.level,
    required this.section,
    required this.chapterId,
    required this.title,
    required this.sourcePath,
    required this.sourceText,
    required this.coverPath,
    required this.exportedLanguages,
    required this.hasAudio,
  });

  final String level;
  final String section;
  final String chapterId;
  final String title;
  final String sourcePath;
  final String sourceText;
  final String coverPath;
  final Set<String> exportedLanguages;
  final bool hasAudio;

  bool hasLanguages(Iterable<String> languages) =>
      languages.every(exportedLanguages.contains);
}

class NoveWorkbenchBookLibrary extends StatefulWidget {
  const NoveWorkbenchBookLibrary({
    super.key,
    required this.busy,
    required this.onSelected,
    required this.onProcessAll,
    required this.onUpdateTextOnly,
  });

  final bool busy;
  final ValueChanged<NoveWorkbenchBookSelection> onSelected;
  final ValueChanged<List<NoveWorkbenchBookSelection>> onProcessAll;
  final ValueChanged<List<NoveWorkbenchBookSelection>> onUpdateTextOnly;

  @override
  State<NoveWorkbenchBookLibrary> createState() =>
      _NoveWorkbenchBookLibraryState();
}

class _NoveWorkbenchBookLibraryState extends State<NoveWorkbenchBookLibrary> {
  late Future<List<_WorkbenchBookItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadBooks();
  }

  void _refresh() {
    setState(() => _future = _loadBooks());
  }

  Future<List<_WorkbenchBookItem>> _loadBooks() async {
    final root = Directory('${Directory.current.path}/Books');
    if (!root.existsSync()) {
      return const [];
    }
    final txtFiles = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.txt'))
        .where((file) => _isBookSource(root, file))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final zipStatuses = await _loadZipStatuses();
    return [
      for (final file in txtFiles) _buildItem(root, file, zipStatuses),
    ];
  }

  bool _isBookSource(Directory booksRoot, File file) {
    final parts = _relativeParts(booksRoot.path, file.path);
    if (parts.length < 3) {
      return false;
    }
    final title = _basenameWithoutExtension(file.path).trim().toLowerCase();
    if (title.contains('plan')) {
      return false;
    }
    return true;
  }

  Future<Map<String, _ZipStatus>> _loadZipStatuses() async {
    final result = <String, _ZipStatus>{};
    final assetsRoot = Directory('${Directory.current.path}/assets/library');
    if (!assetsRoot.existsSync()) {
      return result;
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
        final level = (manifest['level'] ?? '').toString();
        final chapterId = (manifest['chapter_id'] ?? '').toString();
        if (title.isEmpty || level.isEmpty) {
          continue;
        }
        final langs = (manifest['available_target_langs'] as List<dynamic>? ??
                [manifest['target_lang'] ?? 'ru'])
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toSet();
        final dictionaries = <String>{};
        for (final item in archive.files) {
          if (!item.isFile) {
            continue;
          }
          final match =
              RegExp(r'^dictionary_([a-z]{2})\.json$').firstMatch(item.name);
          if (match != null) {
            dictionaries.add(match.group(1)!);
          }
        }
        final hasAudio = archive.files.any((item) =>
            item.isFile &&
            item.name.startsWith('audio/segments/') &&
            item.name.endsWith('.mp3'));
        result[_statusKey(level, chapterId, title)] = _ZipStatus(
          zipPath: file.path,
          languages: langs,
          dictionaries: dictionaries,
          hasAudio: hasAudio,
        );
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  _WorkbenchBookItem _buildItem(
    Directory booksRoot,
    File source,
    Map<String, _ZipStatus> zipStatuses,
  ) {
    final relativeParts = _relativeParts(booksRoot.path, source.path);
    final rawLevel = relativeParts.isNotEmpty ? relativeParts.first : 'a1';
    final rawChapter = relativeParts.length >= 2 ? relativeParts[1] : '';
    final level = _normalizeLevel(rawLevel);
    final title = _basenameWithoutExtension(source.path);
    final chapterId = _chapterIdFromFolder(rawChapter);
    final coverPath = _findCoverPath(source);
    final zipStatus = zipStatuses[_statusKey(level, chapterId, title)];
    return _WorkbenchBookItem(
      level: level,
      section: 'chapters',
      chapterId: chapterId,
      chapterTitle:
          chapterId.isEmpty ? rawChapter : noveA1ChapterTitle(chapterId),
      title: title,
      sourcePath: source.path,
      coverPath: coverPath,
      zipStatus: zipStatus,
    );
  }

  String _normalizeLevel(String value) {
    final level = value.trim().toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2', 'c1'}.contains(level) ? level : 'a1';
  }

  String _chapterIdFromFolder(String folderName) {
    final match = RegExp(r'(?:chapter|\u0433\u043b\u0430\u0432\u0430)\s*(\d+)',
            caseSensitive: false)
        .firstMatch(folderName);
    if (match == null) {
      return '';
    }
    final number = int.tryParse(match.group(1) ?? '');
    if (number == null || number < 1 || number > noveA1Chapters.length) {
      return '';
    }
    return noveA1Chapters[number - 1].id;
  }

  String _findCoverPath(File source) {
    final stem = source.path.substring(0, source.path.length - 4);
    for (final extension in const ['.png', '.jpg', '.jpeg']) {
      final candidate = File('$stem$extension');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return '';
  }

  Future<void> _selectBook(_WorkbenchBookItem item) async {
    final selection = await _selectionFor(item);
    if (!mounted) {
      return;
    }
    widget.onSelected(selection);
  }

  Future<NoveWorkbenchBookSelection> _selectionFor(
      _WorkbenchBookItem item) async {
    final text = await File(item.sourcePath).readAsString();
    return NoveWorkbenchBookSelection(
      level: item.level,
      section: item.section,
      chapterId: item.chapterId,
      title: item.title,
      sourcePath: item.sourcePath,
      sourceText: text,
      coverPath: item.coverPath,
      exportedLanguages: item.zipStatus?.languages ?? const <String>{},
      hasAudio: item.zipStatus?.hasAudio ?? false,
    );
  }

  Future<void> _processAll(List<_WorkbenchBookItem> items) async {
    final selections = <NoveWorkbenchBookSelection>[];
    for (final item in items) {
      selections.add(await _selectionFor(item));
    }
    if (!mounted) {
      return;
    }
    widget.onProcessAll(selections);
  }

  Future<void> _updateTextOnly(List<_WorkbenchBookItem> items) async {
    final selections = <NoveWorkbenchBookSelection>[];
    for (final item in items) {
      selections.add(await _selectionFor(item));
    }
    if (!mounted) {
      return;
    }
    widget.onUpdateTextOnly(selections);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Book Library',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: widget.busy ? null : _refresh,
                  icon: const Icon(Icons.refresh_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<_WorkbenchBookItem>>(
              future: _future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <_WorkbenchBookItem>[];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (items.isEmpty) {
                  return Text(
                    'No TXT books found in production_mobile/Books.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: widget.busy
                                ? null
                                : () => _updateTextOnly(items),
                            icon: const Icon(Icons.article_outlined),
                            label: const Text('Update text only'),
                          ),
                          FilledButton.icon(
                            onPressed:
                                widget.busy ? null : () => _processAll(items),
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Process all'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in items)
                      _WorkbenchBookTile(
                        item: item,
                        busy: widget.busy,
                        onSelected: () => _selectBook(item),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchBookTile extends StatelessWidget {
  const _WorkbenchBookTile({
    required this.item,
    required this.busy,
    required this.onSelected,
  });

  final _WorkbenchBookItem item;
  final bool busy;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final status = item.zipStatus;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        status == null ? Icons.download_outlined : Icons.inventory_2_outlined,
      ),
      title: Text(item.title),
      subtitle: Text(
        '${item.level.toUpperCase()} / ${item.chapterTitle}\n${_statusText(status)}',
      ),
      isThreeLine: true,
      trailing: FilledButton(
        onPressed: busy ? null : onSelected,
        child: const Text('Use'),
      ),
      iconColor: status == null ? colorScheme.error : colorScheme.primary,
    );
  }

  String _statusText(_ZipStatus? status) {
    if (status == null) {
      return item.coverPath.isEmpty ? 'Not exported, no cover' : 'Not exported';
    }
    final langs = status.languages.toList()..sort();
    final missingDictionaries = langs
        .where((lang) => !status.dictionaries.contains(lang))
        .map((lang) => 'dictionary_$lang.json')
        .toList();
    final dictionary = missingDictionaries.isEmpty
        ? 'dictionary ready'
        : 'missing ${missingDictionaries.join(', ')}';
    final audio = status.hasAudio ? 'audio ready' : 'no audio';
    final cover = item.coverPath.isEmpty ? 'no cover' : 'cover ready';
    return 'Zip installed, ${langs.join('+').toUpperCase()}, $dictionary, $audio, $cover';
  }
}

class _WorkbenchBookItem {
  const _WorkbenchBookItem({
    required this.level,
    required this.section,
    required this.chapterId,
    required this.chapterTitle,
    required this.title,
    required this.sourcePath,
    required this.coverPath,
    required this.zipStatus,
  });

  final String level;
  final String section;
  final String chapterId;
  final String chapterTitle;
  final String title;
  final String sourcePath;
  final String coverPath;
  final _ZipStatus? zipStatus;
}

class _ZipStatus {
  const _ZipStatus({
    required this.zipPath,
    required this.languages,
    required this.dictionaries,
    required this.hasAudio,
  });

  final String zipPath;
  final Set<String> languages;
  final Set<String> dictionaries;
  final bool hasAudio;
}

String _statusKey(String level, String chapterId, String title) =>
    '${level.toLowerCase()}|$chapterId|${title.trim().toLowerCase()}';

String _basename(String path) =>
    path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;

String _basenameWithoutExtension(String path) {
  final name = _basename(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

List<String> _relativeParts(String rootPath, String filePath) {
  final root = rootPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final file = filePath.replaceAll('\\', '/');
  final relative =
      file.startsWith('$root/') ? file.substring(root.length + 1) : file;
  return relative.split('/').where((part) => part.isNotEmpty).toList();
}
