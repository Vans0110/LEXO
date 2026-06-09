import 'dart:io';

import 'package:flutter/material.dart';

import '../mobile/virgil_a1_chapters.dart';
import 'virgil_workbench_book_status.dart';
import 'virgil_workbench_paths.dart';
import 'virgil_workbench_book_tile.dart';

class VirgilWorkbenchBookSelection {
  const VirgilWorkbenchBookSelection({
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

class VirgilWorkbenchBookLibrary extends StatefulWidget {
  const VirgilWorkbenchBookLibrary({
    super.key,
    required this.busy,
    required this.onSelected,
    required this.onRefreshBook,
    required this.onRefreshDictionary,
    required this.onProcessAll,
    required this.onUpdateTextOnly,
    required this.onSelectionChanged,
    required this.refreshRevision,
  });

  final bool busy;
  final ValueChanged<VirgilWorkbenchBookSelection> onSelected;
  final Future<void> Function(VirgilWorkbenchBookSelection selection)
      onRefreshBook;
  final Future<void> Function(VirgilWorkbenchBookSelection selection)
      onRefreshDictionary;
  final ValueChanged<List<VirgilWorkbenchBookSelection>> onProcessAll;
  final ValueChanged<List<VirgilWorkbenchBookSelection>> onUpdateTextOnly;
  final ValueChanged<List<VirgilWorkbenchBookSelection>> onSelectionChanged;
  final int refreshRevision;

  @override
  State<VirgilWorkbenchBookLibrary> createState() =>
      _VirgilWorkbenchBookLibraryState();
}

class _VirgilWorkbenchBookLibraryState
    extends State<VirgilWorkbenchBookLibrary> {
  late Future<List<_WorkbenchBookItem>> _future;
  final Set<String> _selectedSourcePaths = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _loadBooks();
  }

  @override
  void didUpdateWidget(covariant VirgilWorkbenchBookLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshRevision != oldWidget.refreshRevision) {
      _selectedSourcePaths.clear();
      _refresh();
    }
  }

  void _refresh() {
    setState(() => _future = _loadBooks());
  }

  Future<List<_WorkbenchBookItem>> _loadBooks() async {
    final root = VirgilWorkbenchPaths.books;
    if (!root.existsSync()) {
      return const [];
    }
    final txtFiles = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !_isChapterImagesPath(file.path))
        .where((file) => file.path.toLowerCase().endsWith('.txt'))
        .where((file) => _isBookSource(root, file))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final statuses = await VirgilWorkbenchBookStatusLoader(
      appRoot: VirgilWorkbenchPaths.workspaceRoot,
    ).loadStatuses();
    return [
      for (final file in txtFiles) _buildItem(root, file, statuses),
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

  bool _isChapterImagesPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized == 'chapter_images' ||
        normalized.contains('/chapter_images/') ||
        normalized.startsWith('chapter_images/');
  }

  _WorkbenchBookItem _buildItem(
    Directory booksRoot,
    File source,
    Map<String, VirgilWorkbenchBookStatus> statuses,
  ) {
    final relativeParts = _relativeParts(booksRoot.path, source.path);
    final rawLevel = relativeParts.isNotEmpty ? relativeParts.first : 'a1';
    final rawChapter = relativeParts.length >= 2 ? relativeParts[1] : '';
    final level = _normalizeLevel(rawLevel);
    final title = _basenameWithoutExtension(source.path);
    final chapterId = _chapterIdFromFolder(rawChapter);
    final coverPath = _findCoverPath(source);
    final status =
        statuses[virgilWorkbenchBookStatusKey(level, chapterId, title)];
    return _WorkbenchBookItem(
      level: level,
      section: 'chapters',
      chapterId: chapterId,
      chapterTitle:
          chapterId.isEmpty ? rawChapter : virgilA1ChapterTitle(chapterId),
      title: title,
      sourcePath: source.path,
      coverPath: coverPath,
      status: status,
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
    if (number == null || number < 1 || number > virgilA1Chapters.length) {
      return '';
    }
    return virgilA1Chapters[number - 1].id;
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

  Future<void> _refreshBook(_WorkbenchBookItem item) async {
    final selection = await _selectionFor(item);
    if (!mounted) {
      return;
    }
    await widget.onRefreshBook(selection);
    if (!mounted) {
      return;
    }
    _refresh();
  }

  Future<void> _refreshDictionary(_WorkbenchBookItem item) async {
    final selection = await _selectionFor(item);
    if (!mounted) {
      return;
    }
    await widget.onRefreshDictionary(selection);
    if (!mounted) {
      return;
    }
    _refresh();
  }

  Future<VirgilWorkbenchBookSelection> _selectionFor(
      _WorkbenchBookItem item) async {
    final text = await File(item.sourcePath).readAsString();
    return VirgilWorkbenchBookSelection(
      level: item.level,
      section: item.section,
      chapterId: item.chapterId,
      title: item.title,
      sourcePath: item.sourcePath,
      sourceText: text,
      coverPath: item.coverPath,
      exportedLanguages: item.status?.languages ?? const <String>{},
      hasAudio: item.status?.hasAudio ?? false,
    );
  }

  VirgilWorkbenchBookSelection _selectionMetadataFor(_WorkbenchBookItem item) {
    return VirgilWorkbenchBookSelection(
      level: item.level,
      section: item.section,
      chapterId: item.chapterId,
      title: item.title,
      sourcePath: item.sourcePath,
      sourceText: '',
      coverPath: item.coverPath,
      exportedLanguages: item.status?.languages ?? const <String>{},
      hasAudio: item.status?.hasAudio ?? false,
    );
  }

  void _setSelected(
    List<_WorkbenchBookItem> items,
    _WorkbenchBookItem item,
    bool selected,
  ) {
    setState(() {
      if (selected) {
        _selectedSourcePaths.add(item.sourcePath);
      } else {
        _selectedSourcePaths.remove(item.sourcePath);
      }
    });
    _notifySelectionChanged(items);
  }

  void _setAllSelected(List<_WorkbenchBookItem> items, bool selected) {
    setState(() {
      _selectedSourcePaths.clear();
      if (selected) {
        _selectedSourcePaths.addAll(items.map((item) => item.sourcePath));
      }
    });
    _notifySelectionChanged(items);
  }

  void _notifySelectionChanged(List<_WorkbenchBookItem> items) {
    widget.onSelectionChanged([
      for (final item in items)
        if (_selectedSourcePaths.contains(item.sourcePath))
          _selectionMetadataFor(item),
    ]);
  }

  Future<void> _processAll(List<_WorkbenchBookItem> items) async {
    final selections = <VirgilWorkbenchBookSelection>[];
    for (final item in items) {
      selections.add(await _selectionFor(item));
    }
    if (!mounted) {
      return;
    }
    widget.onProcessAll(selections);
  }

  Future<void> _updateTextOnly(List<_WorkbenchBookItem> items) async {
    final selections = <VirgilWorkbenchBookSelection>[];
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
                    'No TXT books found in Studio/Workbench/Books.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          tristate: true,
                          value: _selectedSourcePaths.isEmpty
                              ? false
                              : (_selectedSourcePaths.length == items.length
                                  ? true
                                  : null),
                          onChanged: widget.busy
                              ? null
                              : (value) => _setAllSelected(
                                    items,
                                    value ?? true,
                                  ),
                        ),
                        Text(
                          'All (${_selectedSourcePaths.length}/${items.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Wrap(
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final item in items)
                      VirgilWorkbenchBookTile(
                        title: item.title,
                        level: item.level,
                        chapterTitle: item.chapterTitle,
                        coverPath: item.coverPath,
                        status: item.status,
                        busy: widget.busy,
                        selected:
                            _selectedSourcePaths.contains(item.sourcePath),
                        onSelectionChanged: (value) =>
                            _setSelected(items, item, value ?? false),
                        onSelected: () => _selectBook(item),
                        onRefresh: () => _refreshBook(item),
                        onRefreshDictionary: () => _refreshDictionary(item),
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

class _WorkbenchBookItem {
  const _WorkbenchBookItem({
    required this.level,
    required this.section,
    required this.chapterId,
    required this.chapterTitle,
    required this.title,
    required this.sourcePath,
    required this.coverPath,
    required this.status,
  });

  final String level;
  final String section;
  final String chapterId;
  final String chapterTitle;
  final String title;
  final String sourcePath;
  final String coverPath;
  final VirgilWorkbenchBookStatus? status;
}

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
