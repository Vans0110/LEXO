import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../features/library/library_feature.dart';
import '../models.dart';
import '../platform/desktop_txt_picker.dart';
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

  void _uiTrace(String message) {
    developer.log(message, name: 'LEXO_UI');
    debugPrint(message);
  }

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
    _uiTrace(
      'HOME_LOAD_STATUS_START busy=${_state.busy} '
      'items=${_state.library?.items.length ?? -1} openingBookId=${_state.openingBookId ?? ''}',
    );
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
      _uiTrace(
        'HOME_LOAD_STATUS_OK items=${nextState.library?.items.length ?? -1} '
        'activeBookId=${nextState.library?.activeBookId ?? ''} busy=${nextState.busy}',
      );
      if (nextState.library != null) {
        widget.onLibraryLoaded?.call(nextState.library!);
      }
    } catch (error) {
      _uiTrace('HOME_LOAD_STATUS_ERROR error=$error');
      if (!mounted) {
        return;
      }
      setState(() => _state = _state.copyWith(busy: false, error: error.toString()));
    } finally {
      if (mounted && _state.busy) {
        setState(() => _state = _state.copyWith(busy: false));
      }
      _uiTrace('HOME_LOAD_STATUS_END busy=${_state.busy}');
    }
  }

  Future<void> _pickAndImport() async {
    final importStartMessage =
        'HOME_IMPORT_PICK_START busy=${_state.busy} '
        'items=${_state.library?.items.length ?? -1} openingBookId=${_state.openingBookId ?? ''}';
    developer.log(importStartMessage, name: 'LEXO_IMPORT');
    debugPrint(importStartMessage);
    try {
      developer.log('HOME_IMPORT_PICKER_AWAIT', name: 'LEXO_IMPORT');
      debugPrint('HOME_IMPORT_PICKER_AWAIT');
      final pickedFile = await DesktopTxtPicker.pickTxtFile();
      if (pickedFile == null) {
        developer.log('HOME_IMPORT_PICK_CANCELLED', name: 'LEXO_IMPORT');
        debugPrint('HOME_IMPORT_PICK_CANCELLED');
        return;
      }
      developer.log('HOME_IMPORT_PICKER_RETURNED', name: 'LEXO_IMPORT');
      debugPrint('HOME_IMPORT_PICKER_RETURNED');
      final importFileMessage = 'HOME_IMPORT_FILE name=${pickedFile.name} path=${pickedFile.path}';
      developer.log(importFileMessage, name: 'LEXO_IMPORT');
      debugPrint(importFileMessage);
      setState(() {
        _state = _state.copyWith(
          busy: true,
          clearError: true,
        );
      });
      final sourceText = await File(pickedFile.path).readAsString();
      final importReadMessage = 'HOME_IMPORT_READ_OK chars=${sourceText.length}';
      developer.log(importReadMessage, name: 'LEXO_IMPORT');
      debugPrint(importReadMessage);
      final title = pickedFile.titleCandidate.trim();
      final importApiMessage = 'HOME_IMPORT_API_START title="$title"';
      developer.log(importApiMessage, name: 'LEXO_IMPORT');
      debugPrint(importApiMessage);
      final nextState = await _controller.importBookText(
        _state,
        title: title,
        sourceText: sourceText,
      );
      developer.log('HOME_IMPORT_API_OK', name: 'LEXO_IMPORT');
      debugPrint('HOME_IMPORT_API_OK');
      if (!mounted) {
        return;
      }
      setState(() => _state = nextState);
      _uiTrace(
        'HOME_IMPORT_APPLIED items=${nextState.library?.items.length ?? -1} '
        'activeBookId=${nextState.library?.activeBookId ?? ''}',
      );
      if (nextState.library != null) {
        widget.onLibraryLoaded?.call(nextState.library!);
      }
    } catch (error) {
      final importErrorMessage = 'HOME_IMPORT_ERROR error=$error';
      developer.log(importErrorMessage, name: 'LEXO_IMPORT');
      debugPrint(importErrorMessage);
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
                  onPressed: _state.busy
                      ? null
                      : () {
                          _uiTrace(
                            'HOME_IMPORT_CLICK busy=${_state.busy} '
                            'items=${_state.library?.items.length ?? -1}',
                          );
                          _pickAndImport();
                        },
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
                                              _uiTrace(
                                                'HOME_OPEN_CLICK bookId=${item.id} title="${item.title}" '
                                                'items=${_state.library?.items.length ?? -1}',
                                              );
                                              setState(() {
                                                _state = _state.copyWith(
                                                  openingBookId: item.id,
                                                  clearError: true,
                                                );
                                              });
                                              try {
                                                await _controller.openBook(item.id);
                                                _uiTrace('HOME_OPEN_API_OK bookId=${item.id}');
                                                if (!mounted) return;
                                                setState(
                                                  () => _state = _state.copyWith(clearOpeningBookId: true),
                                                );
                                                widget.onBookOpened?.call(item);
                                                if (widget.onBookOpened != null) {
                                                  await _loadStatus();
                                                  return;
                                                }
                                                _uiTrace('HOME_OPEN_READER_PUSH bookId=${item.id}');
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
                                                _uiTrace('HOME_OPEN_ERROR bookId=${item.id} error=$error');
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
                                              _uiTrace(
                                                'HOME_DELETE_BUTTON_CLICK bookId=${item.id} title="${item.title}"',
                                              );
                                              final confirmed = await _confirmDelete(item);
                                              if (!confirmed || !mounted) {
                                                return;
                                              }
                                              final deleteStartMessage =
                                                  'HOME_DELETE_START bookId=${item.id} title="${item.title}" '
                                                  'itemsBefore=${_state.library?.items.length ?? -1}';
                                              developer.log(deleteStartMessage, name: 'LEXO_DELETE');
                                              debugPrint(deleteStartMessage);
                                              setState(() {
                                                _state = _state.copyWith(
                                                  busy: true,
                                                  clearError: true,
                                                );
                                              });
                                              try {
                                                final nextState = await _controller.deleteBook(_state, item.id);
                                                if (!mounted) return;
                                                final deleteOkMessage =
                                                    'HOME_DELETE_OK bookId=${item.id} '
                                                    'itemsAfter=${nextState.library?.items.length ?? -1} '
                                                    'activeBookId=${nextState.library?.activeBookId ?? ''}';
                                                developer.log(deleteOkMessage, name: 'LEXO_DELETE');
                                                debugPrint(deleteOkMessage);
                                                setState(() => _state = nextState);
                                                if (nextState.library != null) {
                                                  widget.onLibraryLoaded?.call(nextState.library!);
                                                }
                                              } catch (error) {
                                                final deleteErrorMessage =
                                                    'HOME_DELETE_ERROR bookId=${item.id} error=$error';
                                                developer.log(deleteErrorMessage, name: 'LEXO_DELETE');
                                                debugPrint(deleteErrorMessage);
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
                  onPressed: _state.busy
                      ? null
                      : () {
                          _uiTrace('HOME_REFRESH_CLICK');
                          _loadStatus();
                        },
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
