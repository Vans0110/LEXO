import 'package:flutter/material.dart';

import '../../../mobile/mobile_package_repository.dart';
import '../../../mobile/mobile_settings_repository.dart';
import '../../../mobile/virgil_a1_chapters.dart';
import '../../../mobile/virgil_bundled_book_repository.dart';
import '../../../mobile/virgil_download_options.dart';
import '../../../mobile/virgil_favorites_repository.dart';
import '../../../models.dart';
import '../widgets/virgil_book_cover.dart';
import 'virgil_book_detail_screen.dart';

class MobileReaderCatalogScreen extends StatefulWidget {
  const MobileReaderCatalogScreen({
    super.key,
    this.onBookOpened,
    this.onLibraryLoaded,
    this.reloadTick = 0,
    this.settings = const MobileAppSettings(),
  });

  final ValueChanged<LibraryBookItem>? onBookOpened;
  final ValueChanged<LibraryPayload>? onLibraryLoaded;
  final int reloadTick;
  final MobileAppSettings settings;

  @override
  State<MobileReaderCatalogScreen> createState() =>
      _MobileReaderCatalogScreenState();
}

class _MobileReaderCatalogScreenState extends State<MobileReaderCatalogScreen> {
  static const _levels = ['a1', 'a2', 'b1', 'b2', 'c1'];

  late final MobileBookPackageRepository _repository;
  late final VirgilBundledBookRepository _bundledRepository;
  late final VirgilFavoritesRepository _favoritesRepository;

  String? _error;
  LibraryPayload? _library;
  String _selectedLevel = _levels.first;
  List<VirgilBundledBookInfo> _chapterBooks = const [];
  List<VirgilBundledBookInfo> _moreStoriesBooks = const [];
  List<VirgilBundledBookInfo> _remoteBooks = const [];
  Set<String> _favorites = const <String>{};
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _repository = MobileBookPackageRepository();
    _bundledRepository = VirgilBundledBookRepository();
    _favoritesRepository = VirgilFavoritesRepository();
    _loadLibrary();
  }

  @override
  void didUpdateWidget(covariant MobileReaderCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadLibrary();
    }
  }

  Future<void> _loadLibrary() async {
    final requestId = ++_loadRequestId;
    setState(() => _error = null);
    try {
      final localResults = await Future.wait<Object>([
        _repository.listBooks(),
        _favoritesRepository.load(),
      ]);
      final nextLibrary = localResults[0] as LibraryPayload;
      final favorites = localResults[1] as Set<String>;
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _library = nextLibrary;
        _favorites = favorites;
      });
      widget.onLibraryLoaded?.call(nextLibrary);
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() => _error = 'Local library unavailable: $error');
      return;
    }

    try {
      final remoteBooks = await _bundledRepository.listBooks();
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _remoteBooks = remoteBooks;
        _applySelectedLevelBooks();
      });
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _chapterBooks = const [];
        _moreStoriesBooks = const [];
        _remoteBooks = const [];
        _error = 'Online library unavailable. Downloaded books are ready.';
      });
    }
  }

  Future<void> _toggleFavorite(String key) async {
    final next = await _favoritesRepository.toggle(key);
    if (mounted) {
      setState(() => _favorites = next);
    }
  }

  Future<LibraryBookItem?> _importBundledBook(
    VirgilBundledBookInfo item, {
    VirgilDownloadOptions options = const VirgilDownloadOptions(),
  }) async {
    final localBookId = await _bundledRepository.importBook(
      item,
      options: options,
    );
    final nextLibrary = await _repository.listBooks();
    if (!mounted) {
      return null;
    }
    setState(() => _library = nextLibrary);
    widget.onLibraryLoaded?.call(nextLibrary);
    for (final book in nextLibrary.items) {
      if (book.id == localBookId) {
        return book;
      }
    }
    return null;
  }

  Future<void> _openBook(LibraryBookItem item) async {
    await _repository.markBookOpened(item.id);
    widget.onBookOpened?.call(item);
  }

  Future<void> _deleteBook(LibraryBookItem item) async {
    await _repository.deletePackage(item.id);
    final nextFavorites = await _favoritesRepository.remove(item.id);
    if (mounted) {
      setState(() => _favorites = nextFavorites);
    }
    await _loadLibrary();
  }

  Future<bool> _openLocalDetail(
    LibraryBookItem item, {
    BuildContext? navigatorContext,
  }) async {
    final navContext = navigatorContext ?? context;
    final favoriteKey = item.id;
    final updateAvailable = _updateAvailable(item);
    final opened = await Navigator.of(navContext).push<bool>(
      MaterialPageRoute(
        builder: (_) => VirgilBookDetailScreen(
          title: item.title,
          subtitle: updateAvailable ? 'Update available' : 'Downloaded',
          favorite: _favorites.contains(favoriteKey),
          installed: true,
          localBook: item,
          bundledBook: null,
          busy: false,
          preferredTargetLang: widget.settings.preferredTargetLang,
          preferredVoiceId: widget.settings.preferredVoiceId,
          onToggleFavorite: () => _toggleFavorite(favoriteKey),
          onLoad: null,
          onOpen: _openBook,
          onDelete: _deleteBook,
        ),
      ),
    );
    if (opened == true) {
      return true;
    }
    await _loadLibrary();
    return false;
  }

  Future<bool> _openBundledDetail(
    VirgilBundledBookInfo item, {
    BuildContext? navigatorContext,
    bool closeParentOnOpen = false,
  }) async {
    final localBook = _findInstalledBook(item);
    final navContext = navigatorContext ?? context;
    final opened = await Navigator.of(navContext).push<bool>(
      MaterialPageRoute(
        builder: (_) => VirgilBookDetailScreen(
          title: item.title,
          subtitle: '${item.level.toUpperCase()} / ${_sectionTitle(item)}',
          favorite: localBook != null && _favorites.contains(item.bookId),
          installed: localBook != null,
          localBook: localBook,
          bundledBook: item,
          busy: false,
          preferredTargetLang: widget.settings.preferredTargetLang,
          preferredVoiceId: widget.settings.preferredVoiceId,
          onToggleFavorite: () => _toggleFavorite(item.bookId),
          onLoad: (options) async {
            return _importBundledBook(item, options: options);
          },
          onOpen: _openBook,
          onDelete: _deleteBook,
        ),
      ),
    );
    if (opened == true) {
      if (closeParentOnOpen &&
          navContext.mounted &&
          Navigator.of(navContext).canPop()) {
        Navigator.of(navContext).pop(true);
      }
      return true;
    }
    await _loadLibrary();
    return false;
  }

  Future<bool> _openChapterBooks(VirgilA1Chapter chapter) async {
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ChapterBooksScreen(
          title: '${_selectedLevel.toUpperCase()} Books',
          subtitle: chapter.title,
          books: _booksForChapter(chapter.id),
          coverBuilder: (context, item) => _bundledCover(
            item,
            navigatorContext: context,
            closeParentOnOpen: true,
          ),
        ),
      ),
    );
    if (opened == true) {
      return true;
    }
    await _loadLibrary();
    return false;
  }

  Future<void> _openAllChapterBooks() async {
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AllChaptersScreen(
          title: '${_selectedLevel.toUpperCase()} Chapters',
          books: _chapterBooks,
          onSelected: _openChapterBooks,
        ),
      ),
    );
    if (opened == true) {
      return;
    }
    await _loadLibrary();
  }

  LibraryBookItem? _findInstalledBook(VirgilBundledBookInfo item) {
    for (final book in _library?.items ?? const <LibraryBookItem>[]) {
      if (book.id == item.bookId) {
        return book;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final downloadedBooks = _library?.items ?? const <LibraryBookItem>[];
    final favoriteDownloadedBooks =
        downloadedBooks.where((book) => _favorites.contains(book.id)).toList();
    final levelLabel = _selectedLevel.toUpperCase();
    final showChapters = _selectedLevel == 'a1';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virgil'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadLibrary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Library',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _LevelTabs(
                levels: _levels,
                selectedLevel: _selectedLevel,
                onSelected: (level) {
                  if (level == _selectedLevel) {
                    return;
                  }
                  setState(() {
                    _selectedLevel = level;
                    _applySelectedLevelBooks();
                  });
                },
              ),
              const SizedBox(height: 18),
              _ShelfSection(
                title: 'Favorites',
                icon: Icons.star_outline,
                emptyText: 'No favorite books yet',
                horizontal: true,
                children: [
                  for (final item in favoriteDownloadedBooks) _localCover(item),
                ],
              ),
              const SizedBox(height: 14),
              _ShelfSection(
                title: 'Downloaded Books',
                icon: Icons.download_done_outlined,
                emptyText: 'No downloaded books yet',
                horizontal: true,
                children: [
                  for (final item in downloadedBooks) _localCover(item),
                ],
              ),
              const SizedBox(height: 14),
              if (showChapters) ...[
                _ChaptersCarousel(
                  books: _chapterBooks,
                  onSelected: _openChapterBooks,
                  onAll: _openAllChapterBooks,
                ),
                const SizedBox(height: 14),
              ],
              _ShelfSection(
                title: 'More $levelLabel Stories',
                icon: Icons.auto_stories_outlined,
                emptyText: 'No books yet. More coming soon.',
                children: [
                  for (final item in _moreStoriesBooks) _bundledCover(item),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bundledCover(
    VirgilBundledBookInfo item, {
    BuildContext? navigatorContext,
    bool closeParentOnOpen = false,
  }) {
    final installed = _findInstalledBook(item) != null;
    return VirgilBookCoverCard(
      title: item.title,
      subtitle: installed
          ? 'Loaded'
          : '${item.level.toUpperCase()} / ${_sectionTitle(item)}',
      favorite: installed && _favorites.contains(item.bookId),
      installed: installed,
      coverBytes: item.coverBytes,
      coverUrl: item.coverUrl,
      onTap: () => _openBundledDetail(
        item,
        navigatorContext: navigatorContext,
        closeParentOnOpen: closeParentOnOpen,
      ),
    );
  }

  Widget _localCover(LibraryBookItem item) {
    final updateAvailable = _updateAvailable(item);
    return VirgilBookCoverCard(
      title: item.title,
      subtitle: updateAvailable ? 'Update available' : 'Downloaded',
      favorite: _favorites.contains(item.id),
      installed: true,
      coverFilePath: item.coverFilePath,
      onTap: () => _openLocalDetail(item),
    );
  }

  bool _updateAvailable(LibraryBookItem item) {
    final remoteBook = _remoteBookById(item.id);
    if (remoteBook == null || remoteBook.contentHash.isEmpty) {
      return false;
    }
    final localHash = item.contentHash?.trim() ?? '';
    return localHash.isEmpty || localHash != remoteBook.contentHash;
  }

  VirgilBundledBookInfo? _remoteBookById(String bookId) {
    for (final book in _remoteBooks) {
      if (book.bookId == bookId) {
        return book;
      }
    }
    return null;
  }

  void _applySelectedLevelBooks() {
    _chapterBooks = _selectedLevel == 'a1'
        ? _remoteBooks
            .where((book) =>
                book.level == _selectedLevel && book.section == 'chapters')
            .toList()
        : const [];
    _moreStoriesBooks = _remoteBooks
        .where((book) =>
            book.level == _selectedLevel && book.section == 'more_a1_stories')
        .toList();
  }

  String _sectionTitle(VirgilBundledBookInfo item) {
    if (item.section == 'more_a1_stories') {
      return 'More A1 Stories';
    }
    return item.chapterTitle.isEmpty ? 'Chapters' : item.chapterTitle;
  }

  List<VirgilBundledBookInfo> _booksForChapter(String chapterId) {
    return _chapterBooks.where((book) => book.chapterId == chapterId).toList();
  }
}

class _LevelTabs extends StatelessWidget {
  const _LevelTabs({
    required this.levels,
    required this.selectedLevel,
    required this.onSelected,
  });

  final List<String> levels;
  final String selectedLevel;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final level in levels) ...[
              InkWell(
                onTap:
                    onSelected == null ? null : () => onSelected?.call(level),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 62,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: level == selectedLevel
                        ? colorScheme.primary
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: level == selectedLevel
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    level.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: level == selectedLevel
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (level != levels.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChaptersCarousel extends StatelessWidget {
  const _ChaptersCarousel({
    required this.books,
    required this.onSelected,
    required this.onAll,
  });

  final List<VirgilBundledBookInfo> books;
  final ValueChanged<VirgilA1Chapter> onSelected;
  final VoidCallback onAll;

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
                const Icon(Icons.bookmarks_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Chapters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: onAll,
                  child: const Text('All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _ChapterCard.height,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0;
                        index < virgilA1Chapters.length;
                        index++)
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: _ChapterCard(
                          index: index + 1,
                          chapter: virgilA1Chapters[index],
                          storyCount: _storyCount(virgilA1Chapters[index].id),
                          onTap: () => onSelected(virgilA1Chapters[index]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _storyCount(String chapterId) {
    return books.where((book) => book.chapterId == chapterId).length;
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.index,
    required this.chapter,
    required this.storyCount,
    required this.onTap,
  });

  final int index;
  final VirgilA1Chapter chapter;
  final int storyCount;
  final VoidCallback onTap;

  static const double width = 156;
  static const double height = 256;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: width,
        height: height,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chapter $index',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            SizedBox.square(
              dimension: 122,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: chapter.imageAssetPath == null
                    ? _ChapterImagePlaceholder(colorScheme: colorScheme)
                    : Image.asset(
                        chapter.imageAssetPath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _ChapterImagePlaceholder(
                          colorScheme: colorScheme,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: Text(
                _shortTitle(chapter.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$storyCount stories',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortTitle(String title) {
    final split = title.split('—');
    return split.length > 1 ? split.last.trim() : title;
  }
}

class _ChapterImagePlaceholder extends StatelessWidget {
  const _ChapterImagePlaceholder({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_outlined,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _AllChaptersScreen extends StatelessWidget {
  const _AllChaptersScreen({
    required this.title,
    required this.books,
    required this.onSelected,
  });

  final String title;
  final List<VirgilBundledBookInfo> books;
  final Future<bool> Function(VirgilA1Chapter chapter) onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: virgilA1Chapters.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final chapter = virgilA1Chapters[index];
            final count =
                books.where((book) => book.chapterId == chapter.id).length;
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              leading: _ChapterListImage(
                chapter: chapter,
                index: index + 1,
              ),
              title: Text(chapter.title),
              subtitle: Text('$count books'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final opened = await onSelected(chapter);
                if (opened && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChapterListImage extends StatelessWidget {
  const _ChapterListImage({
    required this.chapter,
    required this.index,
  });

  final VirgilA1Chapter chapter;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageAssetPath = chapter.imageAssetPath;
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageAssetPath == null
            ? _ChapterNumberPlaceholder(
                colorScheme: colorScheme,
                index: index,
              )
            : Image.asset(
                imageAssetPath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _ChapterNumberPlaceholder(
                  colorScheme: colorScheme,
                  index: index,
                ),
              ),
      ),
    );
  }
}

class _ChapterNumberPlaceholder extends StatelessWidget {
  const _ChapterNumberPlaceholder({
    required this.colorScheme,
    required this.index,
  });

  final ColorScheme colorScheme;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          '$index',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.children,
    this.horizontal = false,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final List<Widget> children;
  final bool horizontal;

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
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (children.isEmpty)
              Text(emptyText,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))
            else if (horizontal)
              SizedBox(
                height: 232,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final child in children)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: child,
                        ),
                    ],
                  ),
                ),
              )
            else
              Wrap(spacing: 14, runSpacing: 18, children: children),
          ],
        ),
      ),
    );
  }
}

class _ChapterBooksScreen extends StatelessWidget {
  const _ChapterBooksScreen({
    required this.title,
    required this.subtitle,
    required this.books,
    required this.coverBuilder,
  });

  final String title;
  final String subtitle;
  final List<VirgilBundledBookInfo> books;
  final Widget Function(BuildContext context, VirgilBundledBookInfo item)
      coverBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              subtitle,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            if (books.isEmpty)
              Text(
                'No books yet. More coming soon.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 14,
                runSpacing: 18,
                children: [
                  for (final book in books) coverBuilder(context, book),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
