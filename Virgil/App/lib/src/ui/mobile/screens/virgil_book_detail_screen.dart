import 'package:flutter/material.dart';

import '../../../mobile/virgil_download_options.dart';
import '../../../mobile/virgil_bundled_book_repository.dart';
import '../../../models.dart';
import '../widgets/virgil_book_cover.dart';

typedef VirgilBookAction = Future<void> Function();
typedef VirgilBookItemAction = Future<void> Function(LibraryBookItem item);
typedef VirgilBookLoadAction = Future<LibraryBookItem?> Function(
    VirgilDownloadOptions options);

class VirgilBookDetailScreen extends StatefulWidget {
  const VirgilBookDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.favorite,
    required this.installed,
    required this.updateAvailable,
    this.localBook,
    this.bundledBook,
    required this.busy,
    required this.onToggleFavorite,
    required this.onLoad,
    required this.onOpen,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final bool favorite;
  final bool installed;
  final bool updateAvailable;
  final LibraryBookItem? localBook;
  final VirgilBundledBookInfo? bundledBook;
  final bool busy;
  final VirgilBookAction onToggleFavorite;
  final VirgilBookLoadAction? onLoad;
  final VirgilBookItemAction? onOpen;
  final VirgilBookItemAction? onDelete;

  @override
  State<VirgilBookDetailScreen> createState() => _VirgilBookDetailScreenState();
}

class _VirgilBookDetailScreenState extends State<VirgilBookDetailScreen> {
  late bool _favorite = widget.favorite;
  late bool _installed = widget.installed;
  late bool _updateAvailable = widget.updateAvailable;
  late LibraryBookItem? _localBook = widget.localBook;
  bool _actionBusy = false;

  Future<void> _runAction(VirgilBookAction? action,
      {required bool closeAfter, bool markInstalled = false}) async {
    if (action == null || _actionBusy || widget.busy) {
      return;
    }
    setState(() => _actionBusy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      if (markInstalled) {
        setState(() => _installed = true);
      }
      if (closeAfter) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _runLoadAction() async {
    final action = widget.onLoad;
    if (action == null || _actionBusy || widget.busy) {
      return;
    }
    setState(() => _actionBusy = true);
    try {
      final localBook = await action(const VirgilDownloadOptions());
      if (!mounted) {
        return;
      }
      setState(() {
        _localBook = localBook;
        _installed = localBook != null;
        _updateAvailable = false;
      });
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _openLocalBook() async {
    final localBook = _localBook;
    final action = widget.onOpen;
    if (localBook == null || action == null || _actionBusy || widget.busy) {
      return;
    }
    await _runAction(
      () async {
        await action(localBook);
      },
      closeAfter: true,
    );
  }

  Future<void> _deleteLocalBook() async {
    final localBook = _localBook;
    final action = widget.onDelete;
    if (localBook == null || action == null || _actionBusy || widget.busy) {
      return;
    }
    await _runAction(
      () async {
        await action(localBook);
      },
      closeAfter: true,
    );
  }

  Future<void> _toggleFavorite() async {
    if (_actionBusy || widget.busy) {
      return;
    }
    setState(() => _favorite = !_favorite);
    try {
      await widget.onToggleFavorite();
    } catch (_) {
      if (mounted) {
        setState(() => _favorite = !_favorite);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy || _actionBusy;
    final subtitle = widget.updateAvailable && !_updateAvailable
        ? 'Downloaded'
        : widget.subtitle;
    return Scaffold(
      appBar: AppBar(title: const Text('Book')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          children: [
            Center(
              child: SizedBox(
                width: 210,
                child: VirgilCoverArt(
                  title: widget.title,
                  favorite: _favorite,
                  installed: _installed,
                  coverBytes: widget.bundledBook?.coverBytes,
                  coverUrl: widget.bundledBook?.coverUrl,
                  coverFilePath: _localBook?.coverFilePath,
                  height: 300,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : _updateAvailable
                      ? _runLoadAction
                      : _installed
                          ? _openLocalBook
                          : _runLoadAction,
              icon: Icon(
                _updateAvailable
                    ? Icons.download_for_offline_outlined
                    : _installed
                        ? Icons.menu_book_outlined
                        : Icons.download_outlined,
              ),
              label: Text(
                _updateAvailable ? 'Update' : (_installed ? 'Open' : 'Load'),
              ),
            ),
            if (_updateAvailable) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : _openLocalBook,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Open current version'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy || !_installed ? null : _toggleFavorite,
              icon: Icon(_favorite ? Icons.star : Icons.star_outline),
              label: Text(
                  _favorite ? 'Remove from favorites' : 'Add to favorites'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy || !_installed ? null : _deleteLocalBook,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete book'),
            ),
          ],
        ),
      ),
    );
  }
}
