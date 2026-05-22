import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models.dart';
import '../../../platform/desktop_txt_picker.dart';
import '../../../screens/cards_list_screen.dart';
import '../../../screens/home_screen.dart';
import '../../../screens/reader_screen.dart';
import '../../../widgets/reader_playback_bar.dart';
import 'desktop_settings_screen.dart';

class DesktopShellScreen extends StatefulWidget {
  const DesktopShellScreen({super.key, required this.api});

  final LexoApiClient api;

  @override
  State<DesktopShellScreen> createState() => _DesktopShellScreenState();
}

class _DesktopShellScreenState extends State<DesktopShellScreen> {
  int _selectedIndex = 0;
  int _libraryReloadTick = 0;
  int _cardsReloadTick = 0;
  bool _settingsBusy = false;
  String? _settingsError;
  String? _activeBookId;
  String? _activeBookTitle;
  LibraryPayload? _library;
  ReaderPlaybackRepeatMode _playbackRepeatMode = ReaderPlaybackRepeatMode.off;
  List<String> _libraryPlaybackQueue = const <String>[];
  String? _pendingAutoplayVoiceId;
  Set<int> _pendingAutoplayLevelIds = const <int>{};
  int _autoplayToken = 0;

  void _uiTrace(String message) {
    developer.log(message, name: 'LEXO_UI');
    debugPrint(message);
  }

  void _handleLibraryLoaded(LibraryPayload payload) {
    final activeBookId = payload.activeBookId;
    LibraryBookItem? activeItem;
    if (activeBookId != null && activeBookId.isNotEmpty) {
      for (final item in payload.items) {
        if (item.id == activeBookId) {
          activeItem = item;
          break;
        }
      }
    }
    if (!mounted) {
      return;
    }
    _uiTrace(
      'DESKTOP_LIBRARY_LOADED items=${payload.items.length} activeBookId=${payload.activeBookId ?? ''} '
      'selectedIndex=$_selectedIndex currentActiveBookId=${_activeBookId ?? ''}',
    );
    setState(() {
      _library = payload;
      _activeBookId = activeItem?.id;
      _activeBookTitle = activeItem?.title;
      if (_activeBookId == null && _selectedIndex == 1) {
        _selectedIndex = 0;
      }
    });
    _uiTrace(
      'DESKTOP_LIBRARY_APPLIED selectedIndex=$_selectedIndex activeBookId=${_activeBookId ?? ''} '
      'activeBookTitle="${_activeBookTitle ?? ''}"',
    );
  }

  void _handleBookOpened(LibraryBookItem item) {
    if (!mounted) {
      return;
    }
    _uiTrace('DESKTOP_BOOK_OPENED bookId=${item.id} title="${item.title}"');
    setState(() {
      _activeBookId = item.id;
      _activeBookTitle = item.title;
      _selectedIndex = 1;
      _settingsError = null;
      _pendingAutoplayVoiceId = null;
      _pendingAutoplayLevelIds = const <int>{};
    });
    _uiTrace(
      'DESKTOP_BOOK_OPENED_APPLIED selectedIndex=$_selectedIndex activeBookId=${_activeBookId ?? ''}',
    );
  }

  List<String> _currentLibraryQueue() {
    final items = _library?.items ?? const <LibraryBookItem>[];
    return items
        .map((item) => item.id)
        .where((id) => id.trim().isNotEmpty)
        .toList();
  }

  void _handlePlaybackRepeatModeChanged(ReaderPlaybackRepeatMode mode) {
    setState(() {
      _playbackRepeatMode = mode;
      _libraryPlaybackQueue = mode == ReaderPlaybackRepeatMode.playLibraryOnce
          ? _currentLibraryQueue()
          : const <String>[];
      if (mode == ReaderPlaybackRepeatMode.off) {
        _pendingAutoplayVoiceId = null;
        _pendingAutoplayLevelIds = const <int>{};
      }
    });
  }

  Future<bool> _handleLibraryPlaybackCompleted({
    String? voiceId,
    required Set<int> selectedLevelIds,
  }) async {
    if (_playbackRepeatMode != ReaderPlaybackRepeatMode.playLibraryOnce) {
      return false;
    }
    final currentBookId = _activeBookId;
    if (currentBookId == null || currentBookId.isEmpty) {
      return false;
    }
    var library = _library;
    if (library == null || library.items.isEmpty) {
      try {
        library = await widget.api.getBooks();
      } catch (error) {
        if (mounted) {
          setState(() {
            _settingsError = error.toString();
            _playbackRepeatMode = ReaderPlaybackRepeatMode.off;
          });
        }
        return false;
      }
    }
    final queue = _libraryPlaybackQueue.isNotEmpty
        ? _libraryPlaybackQueue
        : library.items.map((item) => item.id).toList();
    final currentIndex = queue.indexOf(currentBookId);
    final nextIndex = currentIndex + 1;
    if (currentIndex < 0 || nextIndex >= queue.length) {
      if (mounted) {
        setState(() {
          _playbackRepeatMode = ReaderPlaybackRepeatMode.off;
          _libraryPlaybackQueue = const <String>[];
        });
      }
      return false;
    }
    final nextBookId = queue[nextIndex];
    LibraryBookItem? nextBook;
    for (final item in library.items) {
      if (item.id == nextBookId) {
        nextBook = item;
        break;
      }
    }
    final next = nextBook;
    if (next == null) {
      return false;
    }
    try {
      await widget.api.openBook(next.id);
      if (!mounted) {
        return true;
      }
      setState(() {
        _library = library;
        _activeBookId = next.id;
        _activeBookTitle = next.title;
        _selectedIndex = 1;
        _settingsError = null;
        _pendingAutoplayVoiceId = voiceId;
        _pendingAutoplayLevelIds = Set<int>.of(selectedLevelIds);
        _autoplayToken += 1;
      });
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _settingsError = error.toString();
          _playbackRepeatMode = ReaderPlaybackRepeatMode.off;
        });
      }
      return false;
    }
  }

  Future<void> _pickAndImport() async {
    final startMessage =
        'DESKTOP_IMPORT_PICK_START selectedIndex=$_selectedIndex activeBookId=${_activeBookId ?? ''} '
        'activeBookTitle="${_activeBookTitle ?? ''}" settingsBusy=$_settingsBusy '
        'libraryReloadTick=$_libraryReloadTick';
    developer.log(startMessage, name: 'LEXO_IMPORT');
    debugPrint(startMessage);
    try {
      developer.log('DESKTOP_IMPORT_PICKER_AWAIT', name: 'LEXO_IMPORT');
      debugPrint('DESKTOP_IMPORT_PICKER_AWAIT');
      final pickedFile = await DesktopTxtPicker.pickTxtFile();
      if (pickedFile == null) {
        developer.log('DESKTOP_IMPORT_PICK_CANCELLED', name: 'LEXO_IMPORT');
        debugPrint('DESKTOP_IMPORT_PICK_CANCELLED');
        return;
      }
      developer.log('DESKTOP_IMPORT_PICKER_RETURNED', name: 'LEXO_IMPORT');
      debugPrint('DESKTOP_IMPORT_PICKER_RETURNED');
      setState(() {
        _settingsBusy = true;
        _settingsError = null;
      });
      final fileMessage =
          'DESKTOP_IMPORT_FILE name=${pickedFile.name} path=${pickedFile.path}';
      developer.log(fileMessage, name: 'LEXO_IMPORT');
      debugPrint(fileMessage);
      final sourceText = await File(pickedFile.path).readAsString();
      final readMessage = 'DESKTOP_IMPORT_READ_OK chars=${sourceText.length}';
      developer.log(readMessage, name: 'LEXO_IMPORT');
      debugPrint(readMessage);
      final title = pickedFile.titleCandidate.trim();
      final apiStartMessage = 'DESKTOP_IMPORT_API_START title="$title"';
      developer.log(apiStartMessage, name: 'LEXO_IMPORT');
      debugPrint(apiStartMessage);
      await widget.api.importDesktopBookText(
        title: title,
        sourceText: sourceText,
      );
      developer.log('DESKTOP_IMPORT_API_OK', name: 'LEXO_IMPORT');
      debugPrint('DESKTOP_IMPORT_API_OK');
      if (!mounted) {
        return;
      }
      setState(() {
        _libraryReloadTick += 1;
        _selectedIndex = 0;
      });
      final postStateMessage =
          'DESKTOP_IMPORT_POST_STATE selectedIndex=$_selectedIndex '
          'libraryReloadTick=$_libraryReloadTick';
      developer.log(postStateMessage, name: 'LEXO_IMPORT');
      debugPrint(postStateMessage);
    } catch (error) {
      final errorMessage = 'DESKTOP_IMPORT_ERROR error=$error';
      developer.log(errorMessage, name: 'LEXO_IMPORT');
      debugPrint(errorMessage);
      if (!mounted) {
        return;
      }
      setState(() => _settingsError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
      }
    }
  }

  void _refreshLibrary() {
    _uiTrace(
      'DESKTOP_REFRESH_LIBRARY_CLICK selectedIndex=$_selectedIndex '
      'libraryReloadTick=$_libraryReloadTick activeBookId=${_activeBookId ?? ''}',
    );
    setState(() {
      _libraryReloadTick += 1;
      _settingsError = null;
    });
    _uiTrace(
        'DESKTOP_REFRESH_LIBRARY_APPLIED libraryReloadTick=$_libraryReloadTick');
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        api: widget.api,
        onBookOpened: _handleBookOpened,
        onLibraryLoaded: _handleLibraryLoaded,
        reloadTick: _libraryReloadTick,
      ),
      _activeBookId == null
          ? const _DesktopReaderPlaceholder()
          : ReaderScreen(
              key: ValueKey(_activeBookId),
              api: widget.api,
              bookId: _activeBookId!,
              playbackRepeatMode: _playbackRepeatMode,
              onPlaybackRepeatModeChanged: _handlePlaybackRepeatModeChanged,
              onLibraryPlaybackCompleted: _handleLibraryPlaybackCompleted,
              autoplayVoiceId: _pendingAutoplayVoiceId,
              autoplayLevelIds: _pendingAutoplayLevelIds,
              autoplayToken: _autoplayToken,
            ),
      CardsListScreen(
        api: widget.api,
        reloadTick: _cardsReloadTick,
      ),
      DesktopSettingsScreen(
        currentBookTitle: _activeBookTitle,
        busy: _settingsBusy,
        errorText: _settingsError,
        onImportBook: _pickAndImport,
        onRefreshLibrary: _refreshLibrary,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() {
          _uiTrace(
            'DESKTOP_NAV_CLICK from=$_selectedIndex to=$index '
            'activeBookId=${_activeBookId ?? ''} cardsReloadTick=$_cardsReloadTick',
          );
          _selectedIndex = index;
          if (index == 2) {
            _cardsReloadTick += 1;
          }
          _uiTrace(
            'DESKTOP_NAV_APPLIED selectedIndex=$_selectedIndex cardsReloadTick=$_cardsReloadTick',
          );
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Reader',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Cards',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DesktopReaderPlaceholder extends StatelessWidget {
  const _DesktopReaderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Open a book from the Library tab to start reading.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
