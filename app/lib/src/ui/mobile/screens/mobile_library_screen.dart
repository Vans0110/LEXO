import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../mobile/mobile_package_repository.dart';
import '../../../models.dart';
import 'mobile_reader_screen.dart';
import 'mobile_settings_screen.dart';

class MobileLibraryScreen extends StatefulWidget {
  const MobileLibraryScreen({
    super.key,
    required this.api,
    this.onBookOpened,
    this.onLibraryLoaded,
    this.reloadTick = 0,
  });

  final LexoApiClient api;
  final ValueChanged<LibraryBookItem>? onBookOpened;
  final ValueChanged<LibraryPayload>? onLibraryLoaded;
  final int reloadTick;

  @override
  State<MobileLibraryScreen> createState() => _MobileLibraryScreenState();
}

class _MobileLibraryScreenState extends State<MobileLibraryScreen> {
  late final MobileBookPackageRepository _repository;

  bool _busy = true;
  String? _error;
  String? _openingBookId;
  String? _updatingBookId;
  LibraryPayload? _library;

  @override
  void initState() {
    super.initState();
    _repository = MobileBookPackageRepository();
    _loadLibrary();
  }

  @override
  void didUpdateWidget(covariant MobileLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadLibrary();
    }
  }

  Future<void> _loadLibrary() async {
    developer.log('Loading local mobile library', name: 'LEXO_UI');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextLibrary = await _repository.listBooks();
      if (!mounted) {
        return;
      }
      setState(() => _library = nextLibrary);
      if (nextLibrary.items.isNotEmpty) {
        widget.onLibraryLoaded?.call(nextLibrary);
      }
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

  Future<bool> _confirmDelete(LibraryBookItem item) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Delete "${item.title}"?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text('Это удалит локальную mobile-копию книги и скачанные аудиофайлы.'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _openBook(LibraryBookItem item) async {
    setState(() {
      _openingBookId = item.id;
      _error = null;
    });
    try {
      await _repository.markBookOpened(item.id);
      if (!mounted) {
        return;
      }
      setState(() => _openingBookId = null);
      widget.onBookOpened?.call(item);
      if (widget.onBookOpened != null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MobileReaderScreen(
            api: widget.api,
            localBookId: item.id,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      await _loadLibrary();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _openingBookId = null;
      });
    }
  }

  Future<void> _deleteBook(LibraryBookItem item) async {
    final confirmed = await _confirmDelete(item);
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.deletePackage(item.id);
      if (!mounted) {
        return;
      }
      await _loadLibrary();
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

  Future<void> _updateBook(LibraryBookItem item) async {
    final desktopBookId = item.desktopBookId;
    if (desktopBookId == null || desktopBookId.isEmpty) {
      return;
    }
    setState(() {
      _updatingBookId = item.id;
      _error = null;
    });
    try {
      final localPackage = await _repository.readPackage(item.id);
      final package = await widget.api.getMobileBookPackage(desktopBookId);
      final meta = package['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
      meta['local_book_id'] = item.id;
      meta['current_paragraph_index'] = localPackage.meta.currentParagraphIndex;
      meta['last_opened_at'] = localPackage.meta.lastOpenedAt;
      package['meta'] = meta;
      final readerPayload = package['reader_payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
      readerPayload['current_paragraph_index'] = localPackage.meta.currentParagraphIndex;
      package['reader_payload'] = readerPayload;
      await _repository.savePackage(package);
      if (!mounted) {
        return;
      }
      await _loadLibrary();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _updatingBookId = null);
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileSettingsScreen(
          title: 'Settings',
          busy: _busy,
          errorText: _error,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEXO'),
        actions: [
          if (widget.onBookOpened == null)
            IconButton(
              onPressed: _busy ? null : _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          IconButton(
            onPressed: _busy ? null : _loadLibrary,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Library',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: library == null || library.items.isEmpty
                  ? const Center(child: Text('Локальная mobile-библиотека пока пуста'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: library.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = library.items[index];
                        final opening = _openingBookId == item.id;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (item.isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text('Active'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('${item.sourceLang} -> ${item.targetLang}'),
                                const SizedBox(height: 6),
                                Text('Позиция ${item.currentParagraphIndex + 1}'),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _busy || _openingBookId != null
                                            ? null
                                            : () => _openBook(item),
                                        child: Text(opening ? 'Opening...' : 'Open'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      onPressed: _busy ? null : () => _deleteBook(item),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
