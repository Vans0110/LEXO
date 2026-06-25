import 'dart:io';

import 'package:flutter/material.dart';

import 'virgil_workbench_library_filters.dart';
import 'virgil_workbench_library_models.dart';
import 'virgil_workbench_book_status.dart';
import 'virgil_workbench_paths.dart';
import 'virgil_workbench_book_tile.dart';

class VirgilWorkbenchBookLibrary extends StatefulWidget {
  const VirgilWorkbenchBookLibrary({
    super.key,
    required this.busy,
    required this.canStartActions,
    required this.onSelected,
    required this.onStart,
    required this.onClean,
    required this.onSyncToR2,
    required this.onSelectionChanged,
    required this.refreshRevision,
  });

  final bool busy;
  final bool canStartActions;
  final ValueChanged<VirgilWorkbenchBookSelection> onSelected;
  final Future<void> Function(List<VirgilWorkbenchBookSelection> selections)
      onStart;
  final VoidCallback onClean;
  final VoidCallback onSyncToR2;
  final ValueChanged<List<VirgilWorkbenchBookSelection>> onSelectionChanged;
  final int refreshRevision;

  @override
  State<VirgilWorkbenchBookLibrary> createState() =>
      _VirgilWorkbenchBookLibraryState();
}

class _VirgilWorkbenchBookLibraryState extends State<VirgilWorkbenchBookLibrary>
    with AutomaticKeepAliveClientMixin<VirgilWorkbenchBookLibrary> {
  late Future<List<VirgilWorkbenchBookItem>> _future;
  List<VirgilWorkbenchBookItem> _cachedItems = const [];
  final Set<String> _selectedSourcePaths = <String>{};
  String _levelFilter = '';
  String _chapterFilter = '';
  VirgilWorkbenchReadyFilter _readyFilter = VirgilWorkbenchReadyFilter.all;
  String _pendingLevelFilter = '';
  String _pendingChapterFilter = '';
  VirgilWorkbenchReadyFilter _pendingReadyFilter =
      VirgilWorkbenchReadyFilter.all;

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
      _future = _loadBooks();
    }
  }

  void _refresh() {
    setState(() => _future = _loadBooks());
  }

  Future<List<VirgilWorkbenchBookItem>> _loadBooks() async {
    final root = VirgilWorkbenchPaths.books;
    if (!root.existsSync()) {
      _cachedItems = const [];
      return const [];
    }
    final txtFiles = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !virgilWorkbenchIsChapterImagesPath(file.path))
        .where((file) => file.path.toLowerCase().endsWith('.txt'))
        .where((file) => _isBookSource(root, file))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final statuses = await VirgilWorkbenchBookStatusLoader(
      appRoot: VirgilWorkbenchPaths.workspaceRoot,
    ).loadStatuses();
    final items = [
      for (final file in txtFiles) _buildItem(root, file, statuses),
    ];
    _cachedItems = items;
    return items;
  }

  bool _isBookSource(Directory booksRoot, File file) {
    final parts = virgilWorkbenchRelativeParts(booksRoot.path, file.path);
    if (parts.length < 3) {
      return false;
    }
    return true;
  }

  VirgilWorkbenchBookItem _buildItem(
    Directory booksRoot,
    File source,
    Map<String, VirgilWorkbenchBookStatus> statuses,
  ) {
    final relativeParts =
        virgilWorkbenchRelativeParts(booksRoot.path, source.path);
    final rawLevel = relativeParts.isNotEmpty ? relativeParts.first : 'a1';
    final rawChapter = relativeParts.length >= 2 ? relativeParts[1] : '';
    final level = virgilWorkbenchNormalizeLevel(rawLevel);
    final title = virgilWorkbenchBasenameWithoutExtension(source.path);
    final chapterId = virgilWorkbenchChapterId(rawChapter);
    final coverPath = _findCoverPath(source);
    final status =
        statuses[virgilWorkbenchBookStatusKey(level, chapterId, title)];
    return VirgilWorkbenchBookItem(
      level: level,
      section: 'chapters',
      chapterId: chapterId,
      chapterTitle: virgilWorkbenchChapterTitle(rawChapter),
      chapterNumber: virgilWorkbenchChapterNumber(rawChapter),
      title: title,
      sourcePath: source.path,
      coverPath: coverPath,
      status: status,
    );
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

  Future<void> _selectBook(VirgilWorkbenchBookItem item) async {
    final selection = await _selectionFor(item);
    if (!mounted) {
      return;
    }
    widget.onSelected(selection);
  }

  Future<VirgilWorkbenchBookSelection> _selectionFor(
      VirgilWorkbenchBookItem item) async {
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

  VirgilWorkbenchBookSelection _selectionMetadataFor(
      VirgilWorkbenchBookItem item) {
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
    List<VirgilWorkbenchBookItem> items,
    VirgilWorkbenchBookItem item,
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

  void _setAllSelected(List<VirgilWorkbenchBookItem> items, bool selected) {
    setState(() {
      if (selected) {
        _selectedSourcePaths.addAll(items.map((item) => item.sourcePath));
      } else {
        _selectedSourcePaths.removeAll(items.map((item) => item.sourcePath));
      }
    });
  }

  List<VirgilWorkbenchBookItem> _selectedItems(
      List<VirgilWorkbenchBookItem> items) {
    return [
      for (final item in items)
        if (_selectedSourcePaths.contains(item.sourcePath)) item,
    ];
  }

  void _notifySelectionChanged(List<VirgilWorkbenchBookItem> items) {
    widget.onSelectionChanged([
      for (final item in items)
        if (_selectedSourcePaths.contains(item.sourcePath))
          _selectionMetadataFor(item),
    ]);
  }

  Future<void> _startSelected(List<VirgilWorkbenchBookItem> items) async {
    if (!widget.canStartActions || items.isEmpty) {
      return;
    }
    final selections = <VirgilWorkbenchBookSelection>[];
    for (final item in items) {
      selections.add(await _selectionFor(item));
    }
    if (!mounted) {
      return;
    }
    await widget.onStart(selections);
    if (mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            FutureBuilder<List<VirgilWorkbenchBookItem>>(
              future: _future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? _cachedItems;
                final loading =
                    snapshot.connectionState != ConnectionState.done;
                if (loading && items.isEmpty) {
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
                final visibleItems = virgilWorkbenchVisibleBooks(
                  items: items,
                  level: _levelFilter,
                  chapter: _chapterFilter,
                  readyFilter: _readyFilter,
                );
                final allSelectedItems = _selectedItems(items);
                final selectedItems = virgilWorkbenchSelectedVisibleBooks(
                  visibleItems: visibleItems,
                  selectedSourcePaths: _selectedSourcePaths,
                );
                final visibleSelectedCount = visibleItems
                    .where(
                      (item) => _selectedSourcePaths.contains(item.sourcePath),
                    )
                    .length;
                final allVisibleSelected = visibleItems.isNotEmpty &&
                    visibleSelectedCount == visibleItems.length;
                final canStart = !widget.busy &&
                    selectedItems.isNotEmpty &&
                    widget.canStartActions;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 10),
                    ],
                    VirgilWorkbenchLibraryFilters(
                      level: _pendingLevelFilter,
                      chapter: _pendingChapterFilter,
                      readyFilter: _pendingReadyFilter,
                      levels: virgilWorkbenchLevels(items),
                      chapters:
                          virgilWorkbenchChapters(items, _pendingLevelFilter),
                      busy: widget.busy,
                      onLevelChanged: (value) {
                        setState(() {
                          _pendingLevelFilter = value;
                          _pendingChapterFilter = '';
                        });
                      },
                      onChapterChanged: (value) =>
                          setState(() => _pendingChapterFilter = value),
                      onReadyFilterChanged: (value) =>
                          setState(() => _pendingReadyFilter = value),
                      hasPendingChanges: _pendingLevelFilter != _levelFilter ||
                          _pendingChapterFilter != _chapterFilter ||
                          _pendingReadyFilter != _readyFilter,
                      onApply: () {
                        setState(() {
                          _levelFilter = _pendingLevelFilter;
                          _chapterFilter = _pendingChapterFilter;
                          _readyFilter = _pendingReadyFilter;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          tristate: true,
                          value: visibleSelectedCount == 0
                              ? false
                              : (allVisibleSelected ? true : null),
                          onChanged: widget.busy || visibleItems.isEmpty
                              ? null
                              : (value) {
                                  _setAllSelected(
                                    visibleItems,
                                    virgilWorkbenchShouldSelectAllVisible(
                                      visibleCount: visibleItems.length,
                                      selectedVisibleCount:
                                          visibleSelectedCount,
                                    ),
                                  );
                                  _notifySelectionChanged(items);
                                },
                        ),
                        Text(
                          'Visible ($visibleSelectedCount/${visibleItems.length})'
                          ' · Selected ${selectedItems.length}'
                          '${allSelectedItems.length > selectedItems.length ? ' visible / ${allSelectedItems.length} total' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: canStart
                                  ? () => _startSelected(selectedItems)
                                  : null,
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: Text('Start (${selectedItems.length})'),
                            ),
                            OutlinedButton.icon(
                              onPressed: widget.busy || selectedItems.isEmpty
                                  ? null
                                  : widget.onClean,
                              icon:
                                  const Icon(Icons.cleaning_services_outlined),
                              label: Text(
                                'Clean selected (${selectedItems.length})',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: widget.busy ? null : widget.onSyncToR2,
                              icon: const Icon(Icons.cloud_sync_outlined),
                              label: const Text('Sync to R2'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (visibleItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'No books match the selected filters.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final item in visibleItems)
                      VirgilWorkbenchBookTile(
                        key: ValueKey(item.sourcePath),
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

  @override
  bool get wantKeepAlive => true;
}
