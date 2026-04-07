import 'dart:developer' as developer;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../features/library/library_feature.dart';
import '../models.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final LibraryFeatureController _controller;
  LibraryFeatureState _state = const LibraryFeatureState(busy: true);

  @override
  void initState() {
    super.initState();
    _controller = LibraryFeatureController(widget.api);
    _loadStatus();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    developer.log('Loading library', name: 'LEXO_UI');
    setState(() {
      _state = _state.copyWith(
        busy: true,
        clearError: true,
      );
    });
    try {
      final nextState = await _controller.load(_state);
      if (!mounted) {
        return;
      }
      setState(() => _state = nextState);
      if (nextState.library != null) {
        widget.onLibraryLoaded?.call(nextState.library!);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(busy: false, error: error.toString()));
    } finally {
      if (mounted && _state.busy) {
        setState(() => _state = _state.copyWith(busy: false));
      }
    }
  }

  Future<void> _pickAndImport() async {
    const typeGroup = XTypeGroup(label: 'text', extensions: ['txt']);
    developer.log('HOME_IMPORT_PICK_START', name: 'LEXO_IMPORT');
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) {
      developer.log('HOME_IMPORT_PICK_CANCELLED', name: 'LEXO_IMPORT');
      return;
    }
    developer.log(
      'HOME_IMPORT_FILE name=${file.name} path=${file.path}',
      name: 'LEXO_IMPORT',
    );
    setState(() {
      _state = _state.copyWith(
        busy: true,
        clearError: true,
      );
    });
    try {
      final sourceText = await file.readAsString();
      developer.log(
        'HOME_IMPORT_READ_OK chars=${sourceText.length}',
        name: 'LEXO_IMPORT',
      );
      final title = file.name.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
      developer.log(
        'HOME_IMPORT_API_START title="$title"',
        name: 'LEXO_IMPORT',
      );
      final nextState = await _controller.importBookText(
        _state,
        title: title,
        sourceText: sourceText,
      );
      developer.log('HOME_IMPORT_API_OK', name: 'LEXO_IMPORT');
      if (!mounted) {
        return;
      }
      setState(() => _state = nextState);
      if (nextState.library != null) {
        widget.onLibraryLoaded?.call(nextState.library!);
      }
    } catch (error) {
      developer.log(
        'HOME_IMPORT_ERROR error=$error',
        name: 'LEXO_IMPORT',
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(busy: false, error: error.toString()));
    } finally {
      if (mounted && _state.busy) {
        setState(() => _state = _state.copyWith(busy: false));
      }
    }
  }

  Future<bool> _confirmDelete(LibraryBookItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete book'),
        content: Text('Удалить "${item.title}" из библиотеки? Это удалит текст и TTS-файлы.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final library = _state.library;
    return Scaffold(
      appBar: AppBar(title: const Text('LEXO')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Library',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _state.busy ? null : _pickAndImport,
                  child: Text(_state.busy ? 'Подождите...' : 'Load TXT'),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: library == null || library.items.isEmpty
                      ? const Center(child: Text('Библиотека пока пуста'))
                      : ListView.separated(
                          itemCount: library.items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = library.items[index];
                            return Card(
                              child: ListTile(
                                title: Text(item.title),
                                subtitle: Text(
                                  '${item.sourceLang} -> ${item.targetLang} | ${item.modelName} | позиция ${item.currentParagraphIndex + 1}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton(
                                      onPressed: _state.busy || _state.openingBookId != null
                                          ? null
                                          : () async {
                                              setState(() {
                                                _state = _state.copyWith(
                                                  openingBookId: item.id,
                                                  clearError: true,
                                                );
                                              });
                                              try {
                                                await _controller.openBook(item.id);
                                                if (!mounted) return;
                                                setState(
                                                  () => _state = _state.copyWith(clearOpeningBookId: true),
                                                );
                                                widget.onBookOpened?.call(item);
                                                if (widget.onBookOpened != null) {
                                                  await _loadStatus();
                                                  return;
                                                }
                                                await Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => ReaderScreen(
                                                      api: widget.api,
                                                      bookId: item.id,
                                                    ),
                                                  ),
                                                );
                                                if (!mounted) return;
                                                await _loadStatus();
                                              } catch (error) {
                                                if (!mounted) {
                                                  return;
                                                }
                                                setState(
                                                  () => _state = _state.copyWith(error: error.toString()),
                                                );
                                              } finally {
                                                if (mounted) {
                                                  setState(
                                                    () => _state = _state.copyWith(clearOpeningBookId: true),
                                                  );
                                                }
                                              }
                                            },
                                      child: Text(
                                        _state.openingBookId == item.id
                                            ? 'Opening...'
                                            : (item.isActive ? 'Open Active' : 'Open'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _state.busy
                                          ? null
                                          : () async {
                                              final confirmed = await _confirmDelete(item);
                                              if (!confirmed || !mounted) {
                                                return;
                                              }
                                              setState(() {
                                                _state = _state.copyWith(
                                                  busy: true,
                                                  clearError: true,
                                                );
                                              });
                                              try {
                                                final nextState = await _controller.deleteBook(_state, item.id);
                                                if (!mounted) return;
                                                setState(() => _state = nextState);
                                                if (nextState.library != null) {
                                                  widget.onLibraryLoaded?.call(nextState.library!);
                                                }
                                              } catch (error) {
                                                if (!mounted) {
                                                  return;
                                                }
                                                setState(
                                                  () => _state = _state.copyWith(
                                                    busy: false,
                                                    error: error.toString(),
                                                  ),
                                                );
                                              } finally {
                                                if (mounted && _state.busy) {
                                                  setState(() => _state = _state.copyWith(busy: false));
                                                }
                                              }
                                            },
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_state.error != null) ...[
                  const SizedBox(height: 16),
                  Text(_state.error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _state.busy ? null : _loadStatus,
                  child: const Text('Refresh Library'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
