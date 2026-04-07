import 'dart:developer' as developer;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../models.dart';
import '../../../screens/cards_list_screen.dart';
import '../../../screens/home_screen.dart';
import '../../../screens/reader_screen.dart';
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

  void _handleLibraryLoaded(LibraryPayload payload) {
    final activeBookId = payload.activeBookId;
    if (activeBookId == null || activeBookId.isEmpty) {
      return;
    }
    LibraryBookItem? activeItem;
    for (final item in payload.items) {
      if (item.id == activeBookId) {
        activeItem = item;
        break;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBookId = activeBookId;
      _activeBookTitle = activeItem?.title ?? _activeBookTitle;
    });
  }

  void _handleBookOpened(LibraryBookItem item) {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBookId = item.id;
      _activeBookTitle = item.title;
      _selectedIndex = 1;
      _settingsError = null;
    });
  }

  Future<void> _pickAndImport() async {
    const typeGroup = XTypeGroup(label: 'text', extensions: ['txt']);
    developer.log('DESKTOP_IMPORT_PICK_START', name: 'LEXO_IMPORT');
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) {
      developer.log('DESKTOP_IMPORT_PICK_CANCELLED', name: 'LEXO_IMPORT');
      return;
    }
    setState(() {
      _settingsBusy = true;
      _settingsError = null;
    });
    try {
      developer.log(
        'DESKTOP_IMPORT_FILE name=${file.name} path=${file.path}',
        name: 'LEXO_IMPORT',
      );
      final sourceText = await file.readAsString();
      developer.log(
        'DESKTOP_IMPORT_READ_OK chars=${sourceText.length}',
        name: 'LEXO_IMPORT',
      );
      final title = file.name.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
      developer.log(
        'DESKTOP_IMPORT_API_START title="$title"',
        name: 'LEXO_IMPORT',
      );
      await widget.api.importDesktopBookText(
        title: title,
        sourceText: sourceText,
      );
      developer.log('DESKTOP_IMPORT_API_OK', name: 'LEXO_IMPORT');
      if (!mounted) {
        return;
      }
      setState(() {
        _libraryReloadTick += 1;
        _selectedIndex = 0;
      });
    } catch (error) {
      developer.log(
        'DESKTOP_IMPORT_ERROR error=$error',
        name: 'LEXO_IMPORT',
      );
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
    setState(() {
      _libraryReloadTick += 1;
      _settingsError = null;
    });
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
          _selectedIndex = index;
          if (index == 2) {
            _cardsReloadTick += 1;
          }
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
            'Откройте книгу во вкладке Library, чтобы перейти к чтению.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
