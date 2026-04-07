import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/api_client.dart';
import '../../../cards_models.dart';
import '../../../mobile/mobile_cards_repository.dart';
import '../../../mobile/mobile_package_repository.dart';
import '../../../mobile/mobile_settings_repository.dart';
import '../../../mobile/mobile_sync_debug_logger.dart';
import '../../../models.dart';
import '../../../screens/cards_list_screen.dart';
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
  late final MobileCardsRepository _cardsRepository;
  late final MobileBookPackageRepository _packageRepository;
  late final MobileSettingsRepository _settingsRepository;
  late final MobileSyncDebugLogger _syncLogger;

  int _selectedIndex = 0;
  int _libraryReloadTick = 0;
  int _cardsReloadTick = 0;
  int _pendingChangesCount = 0;
  bool _settingsBusy = false;
  String? _settingsError;
  String? _activeBookId;
  String? _activeBookTitle;
  String _syncDebugText = '';
  MobileAppSettings _appSettings = const MobileAppSettings();

  @override
  void initState() {
    super.initState();
    _cardsRepository = MobileCardsRepository();
    _packageRepository = MobileBookPackageRepository();
    _settingsRepository = MobileSettingsRepository();
    _syncLogger = MobileSyncDebugLogger(widget.api);
    _syncDebugText = _syncLogger.debugReport;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      var settings = await _settingsRepository.load();
      if (settings.deviceId == null || settings.deviceId!.trim().isEmpty) {
        settings = await _settingsRepository.save(
          settings.copyWith(deviceId: _newUuid()),
        );
      }
      widget.api.setBaseUrl(settings.hostUrl);
      final pendingChangesCount = await _cardsRepository.pendingChangesCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _appSettings = settings;
        _pendingChangesCount = pendingChangesCount;
      });
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

  Future<void> _syncCards() async {
    final deviceId = _appSettings.deviceId;
    if (deviceId == null || deviceId.trim().isEmpty) {
      setState(() => _settingsError = 'Не найден device_id для mobile sync');
      return;
    }
    setState(() {
      _settingsBusy = true;
      _settingsError = null;
    });
    try {
      final cardsDelta = await _cardsRepository.exportDelta();
      await _syncLogger.startSession('manual_sync_button');
      _refreshSyncDebugText();
      await _syncLogger.log(
        'SYNC_START device_id=$deviceId last_sync_at=${_appSettings.lastSyncAt} cards_delta=${cardsDelta.length}',
      );
      _refreshSyncDebugText();
      final result = await widget.api.syncMobileCardsFull(
        deviceId: deviceId,
        lastSyncAt: _appSettings.lastSyncAt,
        cardsDelta: cardsDelta,
      );
      final mergedCards = (result['merged_cards'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      await _syncLogger.log(
        'SYNC_CARDS_MERGED count=${mergedCards.length}',
      );
      _refreshSyncDebugText();
      await _cardsRepository.replaceWithMergedCards(mergedCards);
      final syncedBooks = await _syncBooksFromDesktopHost();
      final serverSyncTime = result['server_sync_time'] as String? ?? DateTime.now().toUtc().toIso8601String();
      await _syncLogger.log(
        'SYNC_SERVER_TIME value=$serverSyncTime',
      );
      _refreshSyncDebugText();
      final nextSettings = await _settingsRepository.save(
        _appSettings.copyWith(lastSyncAt: serverSyncTime),
      );
      final pendingChangesCount = await _cardsRepository.pendingChangesCount();
      final logPath = await _syncLogger.logFilePath();
      await _syncLogger.log(
        'SYNC_DONE books_synced=$syncedBooks pending_changes=$pendingChangesCount log_path="$logPath"',
      );
      _refreshSyncDebugText();
      if (!mounted) {
        return;
      }
      setState(() {
        _appSettings = nextSettings;
        _pendingChangesCount = pendingChangesCount;
        _cardsReloadTick += 1;
        _libraryReloadTick += syncedBooks > 0 ? 1 : 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncedBooks > 0
                ? 'Синхронизация завершена: книги обновлены ($syncedBooks)'
                : 'Синхронизация завершена',
          ),
        ),
      );
    } catch (error) {
      await _syncLogger.log('SYNC_ERROR error="$error"');
      _refreshSyncDebugText();
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

  Future<SavedCardsPayload> _loadLocalCards() {
    return _cardsRepository.listCards();
  }

  Future<SavedCardsPayload> _loadLocalReviewCards() {
    return _cardsRepository.getReviewCards();
  }

  Future<void> _deleteLocalCard(SavedCardItem item) async {
    await _cardsRepository.deleteCard(cardId: item.id);
    if (!mounted) {
      return;
    }
    final pendingChangesCount = await _cardsRepository.pendingChangesCount();
    setState(() {
      _pendingChangesCount = pendingChangesCount;
      _cardsReloadTick += 1;
    });
  }

  Future<SavedCardItem> _applyLocalReviewResult(String cardId, String direction) async {
    final updated = await _cardsRepository.applyReviewResult(cardId: cardId, direction: direction);
    if (!mounted) {
      return updated;
    }
    final pendingChangesCount = await _cardsRepository.pendingChangesCount();
    setState(() => _pendingChangesCount = pendingChangesCount);
    return updated;
  }

  Future<void> _handleCardsChanged() async {
    final pendingChangesCount = await _cardsRepository.pendingChangesCount();
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingChangesCount = pendingChangesCount;
      _cardsReloadTick += 1;
    });
  }

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<int> _syncBooksFromDesktopHost() async {
    final desktopLibrary = await widget.api.getDesktopBooksForMobile();
    await _syncLogger.log('SYNC_BOOKS_LIBRARY count=${desktopLibrary.items.length}');
    _refreshSyncDebugText();
    var syncedCount = 0;
    for (final item in desktopLibrary.items) {
      final existingByDesktop = await _packageRepository.findByDesktopBookId(item.id);
      final existing = existingByDesktop ??
          await _packageRepository.findByContentHash(item.contentHash ?? '');
      await _syncLogger.log(
        'SYNC_BOOK_PULL desktop_id=${item.id} title="${item.title}" '
        'existing_local_id=${existing?.meta.localBookId ?? ''} existing_hash=${existing?.meta.contentHash ?? ''} '
        'remote_hash=${item.contentHash ?? ''}',
      );
      _refreshSyncDebugText();
      final package = await widget.api.getMobileBookPackage(item.id);
      final meta = package['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final readerPayload = package['reader_payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
      if (existing != null) {
        meta['local_book_id'] = existing.meta.localBookId;
        meta['current_paragraph_index'] = existing.meta.currentParagraphIndex;
        if (existing.meta.lastOpenedAt != null && existing.meta.lastOpenedAt!.trim().isNotEmpty) {
          meta['last_opened_at'] = existing.meta.lastOpenedAt;
        }
        readerPayload['current_paragraph_index'] = existing.meta.currentParagraphIndex;
      }
      await _syncLogger.log(
        'SYNC_BOOK_SAVE desktop_id=${item.id} local_id=${meta['local_book_id'] ?? meta['desktop_book_id'] ?? ''} '
        'title="${meta['title'] ?? ''}" paragraph_index=${readerPayload['current_paragraph_index'] ?? meta['current_paragraph_index'] ?? 0}',
      );
      _refreshSyncDebugText();
      package['meta'] = meta;
      package['reader_payload'] = readerPayload;
      await _packageRepository.savePackage(package);
      final localBookId = (meta['local_book_id'] ?? meta['desktop_book_id'] ?? '') as String;
      final ttsManifest = package['tts_manifest'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final jobs = (ttsManifest['jobs'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      var expectedAudioSegments = 0;
      var presentAudioSegments = 0;
      var audioSyncedCount = 0;
      final failedSegments = <String>[];
      for (final job in jobs) {
        final jobId = job['id'] as String? ?? '';
        final status = job['status'] as String? ?? '';
        if (jobId.isEmpty || status != 'ready') {
          continue;
        }
        final segments = (job['segments'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        for (final segment in segments) {
          final segmentIndex = segment['segment_index'] as int? ?? 0;
          expectedAudioSegments += 1;
          final cached = await _packageRepository.getCachedAudioPath(
            localBookId: localBookId,
            jobId: jobId,
            segmentIndex: segmentIndex,
          );
          if (cached != null) {
            presentAudioSegments += 1;
            continue;
          }
          try {
            final bytes = await widget.api.downloadTtsAudio(
              bookId: item.id,
              jobId: jobId,
              segmentIndex: segmentIndex,
            );
            await _packageRepository.ensureAudioFile(
              localBookId: localBookId,
              jobId: jobId,
              segmentIndex: segmentIndex,
              bytes: bytes,
            );
            audioSyncedCount += 1;
            presentAudioSegments += 1;
          } catch (error) {
            failedSegments.add('$jobId:$segmentIndex');
            await _syncLogger.log(
              'SYNC_BOOK_AUDIO_SEGMENT_ERROR desktop_id=${item.id} local_id=$localBookId '
              'job_id=$jobId segment_index=$segmentIndex error="$error"',
            );
            _refreshSyncDebugText();
          }
        }
      }
      await _syncLogger.log(
        'SYNC_BOOK_AUDIO desktop_id=${item.id} local_id=$localBookId '
        'expected=$expectedAudioSegments present=$presentAudioSegments '
        'downloaded=$audioSyncedCount failed=${failedSegments.length}'
        '${failedSegments.isEmpty ? '' : ' failed_segments=${failedSegments.join(',')}'}',
      );
      _refreshSyncDebugText();
      syncedCount += 1;
    }
    final localLibrary = await _packageRepository.listBooks();
    await _syncLogger.log(
      'SYNC_BOOKS_DONE synced=$syncedCount local_library_count=${localLibrary.items.length}',
    );
    _refreshSyncDebugText();
    return syncedCount;
  }

  void _refreshSyncDebugText() {
    final next = _syncLogger.debugReport;
    if (!mounted) {
      _syncDebugText = next;
      return;
    }
    setState(() => _syncDebugText = next);
  }

  Future<void> _copySyncDebugLog() async {
    final text = _syncDebugText.trim();
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync debug скопирован')),
    );
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
              cardsRepository: _cardsRepository,
              deviceId: _appSettings.deviceId ?? '',
              onCardsChanged: _handleCardsChanged,
            ),
      CardsListScreen(
        api: widget.api,
        reloadTick: _cardsReloadTick,
        loadCards: _loadLocalCards,
        loadReviewCards: _loadLocalReviewCards,
        deleteCard: _deleteLocalCard,
        applyReviewResult: _applyLocalReviewResult,
      ),
      MobileSettingsScreen(
        title: 'Settings',
        currentBookTitle: _activeBookTitle,
        busy: _settingsBusy,
        errorText: _settingsError,
        hostUrl: _appSettings.hostUrl ?? widget.api.baseUrl,
        lastSyncAt: _appSettings.lastSyncAt,
        pendingChangesCount: _pendingChangesCount,
        debugText: _syncDebugText,
        onEditHostUrl: _editHostUrl,
        onSync: _syncCards,
        onCopyDebugLog: _copySyncDebugLog,
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
