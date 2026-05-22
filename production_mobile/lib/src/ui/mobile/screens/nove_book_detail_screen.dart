import 'package:flutter/material.dart';

import '../../../mobile/nove_bundled_book_repository.dart';
import '../../../models.dart';
import '../widgets/nove_book_cover.dart';

typedef NoveBookAction = Future<void> Function();

class NoveBookDetailScreen extends StatefulWidget {
  const NoveBookDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.favorite,
    required this.installed,
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
  final LibraryBookItem? localBook;
  final NoveBundledBookInfo? bundledBook;
  final bool busy;
  final NoveBookAction onToggleFavorite;
  final NoveBookAction? onLoad;
  final NoveBookAction? onOpen;
  final NoveBookAction? onDelete;

  @override
  State<NoveBookDetailScreen> createState() => _NoveBookDetailScreenState();
}

class _NoveBookDetailScreenState extends State<NoveBookDetailScreen> {
  late bool _favorite = widget.favorite;
  late bool _installed = widget.installed;
  bool _actionBusy = false;

  Future<void> _runAction(NoveBookAction? action,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Book')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          children: [
            Center(
              child: SizedBox(
                width: 210,
                child: NoveCoverArt(
                  title: widget.title,
                  favorite: _favorite,
                  installed: _installed,
                  coverBytes: widget.bundledBook?.coverBytes,
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
            if (widget.subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _runAction(
                        widget.installed ? widget.onOpen : widget.onLoad,
                        closeAfter: _installed,
                        markInstalled: !_installed,
                      ),
              icon: Icon(_installed
                  ? Icons.menu_book_outlined
                  : Icons.download_outlined),
              label: Text(_installed ? 'Open' : 'Load'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy || !_installed ? null : _toggleFavorite,
              icon: Icon(_favorite ? Icons.star : Icons.star_outline),
              label: Text(
                  _favorite ? 'Remove from favorites' : 'Add to favorites'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy || !_installed
                  ? null
                  : () => _runAction(widget.onDelete, closeAfter: true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete book'),
            ),
          ],
        ),
      ),
    );
  }
}
