import 'package:flutter/material.dart';

import '../../../mobile/nove_download_options.dart';
import '../../../mobile/nove_bundled_book_repository.dart';
import '../../../models.dart';
import '../widgets/nove_book_cover.dart';

typedef NoveBookAction = Future<void> Function();
typedef NoveBookItemAction = Future<void> Function(LibraryBookItem item);
typedef NoveBookLoadAction = Future<LibraryBookItem?> Function(
    NoveDownloadOptions options);

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
    required this.preferredTargetLang,
    required this.preferredVoiceId,
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
  final String preferredTargetLang;
  final String preferredVoiceId;
  final NoveBookAction onToggleFavorite;
  final NoveBookLoadAction? onLoad;
  final NoveBookItemAction? onOpen;
  final NoveBookItemAction? onDelete;

  @override
  State<NoveBookDetailScreen> createState() => _NoveBookDetailScreenState();
}

class _NoveBookDetailScreenState extends State<NoveBookDetailScreen> {
  late bool _favorite = widget.favorite;
  late bool _installed = widget.installed;
  late LibraryBookItem? _localBook = widget.localBook;
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

  Future<void> _runLoadAction() async {
    final action = widget.onLoad;
    if (action == null || _actionBusy || widget.busy) {
      return;
    }
    final options = await showDialog<NoveDownloadOptions>(
      context: context,
      builder: (_) => _DownloadOptionsDialog(
        preferredTargetLang: widget.preferredTargetLang,
        preferredVoiceId: widget.preferredVoiceId,
      ),
    );
    if (options == null) {
      return;
    }
    setState(() => _actionBusy = true);
    try {
      final localBook = await action(options);
      if (!mounted) {
        return;
      }
      setState(() {
        _localBook = localBook;
        _installed = localBook != null;
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
                  coverUrl: widget.bundledBook?.coverUrl,
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
                  : _installed
                      ? _openLocalBook
                      : _runLoadAction,
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

class _DownloadOptionsDialog extends StatefulWidget {
  const _DownloadOptionsDialog({
    required this.preferredTargetLang,
    required this.preferredVoiceId,
  });

  final String preferredTargetLang;
  final String preferredVoiceId;

  @override
  State<_DownloadOptionsDialog> createState() => _DownloadOptionsDialogState();
}

class _DownloadOptionsDialogState extends State<_DownloadOptionsDialog> {
  late String _targetLang = widget.preferredTargetLang == 'uk' ? 'uk' : 'ru';
  late String _voiceId = _normalizedVoiceId(widget.preferredVoiceId);

  String _normalizedVoiceId(String voiceId) {
    final supported = noveVoiceOptions.map((option) => option.voiceId).toSet();
    return supported.contains(voiceId) ? voiceId : 'af_heart';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download book'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _targetLang,
            decoration: const InputDecoration(
              labelText: 'Translation',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'ru', child: Text('Russian')),
              DropdownMenuItem(value: 'uk', child: Text('Ukrainian')),
              DropdownMenuItem(value: '', child: Text('All available')),
            ],
            onChanged: (value) => setState(() => _targetLang = value ?? 'ru'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _voiceId,
            decoration: const InputDecoration(
              labelText: 'Voice',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All available')),
              for (final option in noveVoiceOptions)
                DropdownMenuItem(
                  value: option.voiceId,
                  child: Text(option.title),
                ),
            ],
            onChanged: (value) =>
                setState(() => _voiceId = value ?? 'af_heart'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            NoveDownloadOptions(
              targetLang: _targetLang.isEmpty ? null : _targetLang,
              voiceId: _voiceId.isEmpty ? null : _voiceId,
            ),
          ),
          child: const Text('Download'),
        ),
      ],
    );
  }
}
