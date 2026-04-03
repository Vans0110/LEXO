import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../mobile/mobile_package_repository.dart';
import '../../../mobile/mobile_settings_repository.dart';
import '../../../models.dart';
import 'mobile_library_screen.dart';
import 'mobile_reader_screen.dart';
import 'mobile_settings_screen.dart';

class MobileShellScreen extends StatefulWidget {
  const MobileShellScreen({super.key, required this.api});

  final LexoApiClient api;

  @override
  State<MobileShellScreen> createState() => _MobileShellScreenState();
}

class _MobileShellScreenState extends State<MobileShellScreen> {
  late final MobileBookPackageRepository _packageRepository;
  late final MobileSettingsRepository _settingsRepository;

  int _selectedIndex = 0;
  int _libraryReloadTick = 0;
  bool _settingsBusy = false;
  String? _settingsError;
  String? _activeBookId;
  String? _activeBookTitle;
  MobileAppSettings _appSettings = const MobileAppSettings();

  @override
  void initState() {
    super.initState();
    _packageRepository = MobileBookPackageRepository();
    _settingsRepository = MobileSettingsRepository();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsRepository.load();
      widget.api.setBaseUrl(settings.hostUrl);
      if (!mounted) {
        return;
      }
      setState(() => _appSettings = settings);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _settingsError = error.toString());
    }
  }

  void _handleLibraryLoaded(LibraryPayload payload) {
    if (_activeBookId != null) {
      return;
    }
    final activeBookId = payload.activeBookId;
    if (activeBookId == null) {
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
      _activeBookTitle = activeItem?.title;
    });
  }

  void _handleBookOpened(LibraryBookItem item) {
    setState(() {
      _activeBookId = item.id;
      _activeBookTitle = item.title;
      _selectedIndex = 1;
      _settingsError = null;
    });
  }

  Future<void> _pickAndImport() async {
    const typeGroup = XTypeGroup(label: 'text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) {
      return;
    }
    setState(() {
      _settingsBusy = true;
      _settingsError = null;
    });
    try {
      final sourceText = await File(file.path).readAsString();
      final title = _deriveTitle(file.path);
      final package = await widget.api.importBookText(
        title: title,
        sourceText: sourceText,
      );
      await _packageRepository.savePackage(package);
      if (!mounted) {
        return;
      }
      final meta = package['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      setState(() {
        _activeBookId = meta['local_book_id'] as String? ?? _activeBookId;
        _activeBookTitle = meta['title'] as String? ?? _activeBookTitle;
        _libraryReloadTick += 1;
        _selectedIndex = 0;
      });
    } catch (error) {
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

  Future<void> _importFromDesktop() async {
    setState(() {
      _settingsBusy = true;
      _settingsError = null;
    });
    try {
      final library = await widget.api.getDesktopBooksForMobile();
      if (!mounted) {
        return;
      }
      final selected = await showModalBottomSheet<LibraryBookItem>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final item in library.items)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text('${item.sourceLang} -> ${item.targetLang}'),
                  onTap: () => Navigator.of(context).pop(item),
                ),
            ],
          ),
        ),
      );
      if (selected == null) {
        return;
      }
      final package = await widget.api.getMobileBookPackage(selected.id);
      await _packageRepository.savePackage(package);
      if (!mounted) {
        return;
      }
      final meta = package['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      setState(() {
        _activeBookId = meta['local_book_id'] as String? ?? _activeBookId;
        _activeBookTitle = meta['title'] as String? ?? _activeBookTitle;
        _libraryReloadTick += 1;
        _selectedIndex = 0;
      });
    } catch (error) {
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

  Future<void> _editHostUrl() async {
    final controller = TextEditingController(text: _appSettings.hostUrl ?? widget.api.baseUrl);
    final submitted = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Host URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'http://192.168.x.x:8765',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Use Default'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (submitted == null) {
      return;
    }
    final nextUrl = submitted.trim();
    if (nextUrl.isNotEmpty &&
        !(nextUrl.startsWith('http://') || nextUrl.startsWith('https://'))) {
      setState(() => _settingsError = 'Host URL должен начинаться с http:// или https://');
      return;
    }
    setState(() {
      _settingsBusy = true;
      _settingsError = null;
    });
    try {
      final nextSettings = await _settingsRepository.save(
        nextUrl.isEmpty
            ? _appSettings.copyWith(clearHostUrl: true)
            : _appSettings.copyWith(hostUrl: nextUrl),
      );
      widget.api.setBaseUrl(nextSettings.hostUrl);
      if (!mounted) {
        return;
      }
      setState(() => _appSettings = nextSettings);
    } catch (error) {
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

  Future<void> _updateCurrentBook() async {
    final activeBookId = _activeBookId;
    if (activeBookId == null || activeBookId.isEmpty) {
      return;
    }
    setState(() {
      _settingsBusy = true;
      _settingsError = null;
    });
    try {
      final localPackage = await _packageRepository.readPackage(activeBookId);
      final desktopBookId = localPackage.meta.desktopBookId;
      if (desktopBookId.isEmpty) {
        throw Exception('У текущей mobile-книги нет связи с desktop library');
      }
      final package = await widget.api.getMobileBookPackage(desktopBookId);
      final meta = package['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
      meta['local_book_id'] = activeBookId;
      meta['current_paragraph_index'] = localPackage.meta.currentParagraphIndex;
      meta['last_opened_at'] = localPackage.meta.lastOpenedAt;
      package['meta'] = meta;
      final readerPayload = package['reader_payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
      readerPayload['current_paragraph_index'] = localPackage.meta.currentParagraphIndex;
      package['reader_payload'] = readerPayload;
      await _packageRepository.savePackage(package);
      if (!mounted) {
        return;
      }
      setState(() {
        _activeBookTitle = meta['title'] as String? ?? _activeBookTitle;
        _libraryReloadTick += 1;
      });
    } catch (error) {
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

  String _deriveTitle(String filePath) {
    final name = filePath.split(Platform.pathSeparator).last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0) {
      return name;
    }
    return name.substring(0, dotIndex);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MobileLibraryScreen(
        api: widget.api,
        onBookOpened: _handleBookOpened,
        onLibraryLoaded: _handleLibraryLoaded,
        reloadTick: _libraryReloadTick,
      ),
      _activeBookId == null
          ? const _MobileReaderPlaceholder()
          : MobileReaderScreen(
              key: ValueKey(_activeBookId),
              api: widget.api,
              localBookId: _activeBookId!,
            ),
      MobileSettingsScreen(
        title: 'Settings',
        currentBookTitle: _activeBookTitle,
        busy: _settingsBusy,
        errorText: _settingsError,
        onImportBook: _pickAndImport,
        onImportFromDesktop: _importFromDesktop,
        hostUrl: _appSettings.hostUrl ?? widget.api.baseUrl,
        onEditHostUrl: _editHostUrl,
        onUpdateCurrentBook: _activeBookId == null ? null : _updateCurrentBook,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _MobileReaderPlaceholder extends StatelessWidget {
  const _MobileReaderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
      ),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Откройте книгу во вкладке Library, чтобы перейти к чтению.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
