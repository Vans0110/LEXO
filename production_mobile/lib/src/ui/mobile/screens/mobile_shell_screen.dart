import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../cards_models.dart';
import '../../../mobile/mobile_audio_handler.dart';
import '../../../mobile/mobile_cards_repository.dart';
import '../../../mobile/mobile_package_models.dart';
import '../../../mobile/mobile_package_repository.dart';
import '../../../mobile/mobile_settings_repository.dart';
import '../../../mobile/nove_bundled_book_repository.dart';
import '../../../models.dart';
import '../../../screens/cards_list_screen.dart';
import '../../../widgets/reader_playback_bar.dart';
import 'mobile_settings_screen.dart';
import 'reader_empty_screen.dart';
import 'mobile_reader_catalog_screen.dart';
import 'mobile_reader_screen.dart';

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
  late final NoveBundledBookRepository _bundledRepository;

  int _selectedIndex = 0;
  int _libraryReloadTick = 0;
  int _readerReloadTick = 0;
  int _cardsReloadTick = 0;
  String? _activeBookId;
  MobileAppSettings _appSettings = const MobileAppSettings();
  LibraryPayload? _library;
  StreamSubscription<audio_service.MediaItem?>? _backgroundMediaSubscription;
  ReaderPlaybackRepeatMode _playbackRepeatMode = ReaderPlaybackRepeatMode.off;
  List<String> _libraryPlaybackQueue = const <String>[];
  String? _pendingAutoplayVoiceId;
  Set<int> _pendingAutoplayLevelIds = const <int>{};
  int _autoplayToken = 0;

  @override
  void initState() {
    super.initState();
    _cardsRepository = MobileCardsRepository();
    _packageRepository = MobileBookPackageRepository();
    _settingsRepository = MobileSettingsRepository();
    _bundledRepository = NoveBundledBookRepository();
    _backgroundMediaSubscription =
        LexoBackgroundAudio.handler?.mediaItem.listen((item) {
      if (item != null) {
        unawaited(_syncActiveBookFromBackground(item));
      }
    });
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _backgroundMediaSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      var settings = await _settingsRepository.load();
      if (settings.deviceId == null || settings.deviceId!.trim().isEmpty) {
        settings = await _settingsRepository.save(
          settings.copyWith(deviceId: _newUuid()),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() => _appSettings = settings);
    } catch (_) {}
  }

  Future<void> _setPreferredTargetLang(String lang) async {
    final next = await _settingsRepository.save(
      _appSettings.copyWith(preferredTargetLang: lang),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = next;
      _libraryReloadTick += 1;
      _readerReloadTick += 1;
    });
    await _refreshActiveBundledBookForLanguage();
  }

  Future<void> _setPreferredVoice(String voiceId) async {
    final next = await _settingsRepository.save(
      _appSettings.copyWith(preferredVoiceId: voiceId),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = next;
      _libraryReloadTick += 1;
      _readerReloadTick += 1;
    });
  }

  Future<void> _refreshActiveBundledBookForLanguage() async {
    final activeBookId = _activeBookId;
    if (activeBookId == null || activeBookId.isEmpty) {
      return;
    }
    try {
      final package = await _packageRepository.readPackage(activeBookId);
      final assetPath = package.meta.contentHash;
      if (!assetPath.startsWith('cloud:') || !assetPath.endsWith('.zip')) {
        return;
      }
      final bundledBook =
          await _bundledRepository.findBookByAssetPath(assetPath);
      if (bundledBook == null) {
        return;
      }
      await _bundledRepository.importBook(bundledBook);
      if (!mounted) {
        return;
      }
      setState(() {
        _libraryReloadTick += 1;
        _readerReloadTick += 1;
      });
    } catch (_) {}
  }

  void _handleLibraryLoaded(LibraryPayload payload) {
    _library = payload;
  }

  void _handleBookOpened(LibraryBookItem item) {
    setState(() {
      _activeBookId = item.id;
      _selectedIndex = 1;
      _pendingAutoplayVoiceId = null;
      _pendingAutoplayLevelIds = const <int>{};
    });
  }

  Future<void> _syncActiveBookFromBackground(
      audio_service.MediaItem item) async {
    if (item.extras?['is_silence'] == true) {
      return;
    }
    final localBookId = item.extras?['book_id'] as String? ?? '';
    if (localBookId.isEmpty || localBookId == _activeBookId) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBookId = localBookId;
      _selectedIndex = 1;
      _pendingAutoplayVoiceId = null;
      _pendingAutoplayLevelIds = const <int>{};
    });
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
        library = await _packageRepository.listBooks();
      } catch (_) {
        if (mounted) {
          setState(() => _playbackRepeatMode = ReaderPlaybackRepeatMode.off);
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
      await _packageRepository.markBookOpened(next.id);
      if (!mounted) {
        return true;
      }
      setState(() {
        _library = library;
        _activeBookId = next.id;
        _selectedIndex = 1;
        _pendingAutoplayVoiceId = voiceId;
        _pendingAutoplayLevelIds = Set<int>.of(selectedLevelIds);
        _autoplayToken += 1;
      });
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _playbackRepeatMode = ReaderPlaybackRepeatMode.off);
      }
      return false;
    }
  }

  Future<void> _handleCardsChanged() async {
    if (!mounted) {
      return;
    }
    setState(() => _cardsReloadTick += 1);
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
    setState(() => _cardsReloadTick += 1);
  }

  Future<SavedCardItem> _applyLocalReviewResult(
      String cardId, String direction) {
    return _cardsRepository.applyReviewResult(
        cardId: cardId, direction: direction);
  }

  Future<String?> _resolveLocalCardAudioPath(SavedCardItem item) async {
    final sourceBookId = item.sourceBookId.trim();
    if (sourceBookId.isEmpty) {
      return null;
    }
    MobileBookPackage? package =
        await _packageRepository.findByDesktopBookId(sourceBookId);
    if (package == null) {
      try {
        package = await _packageRepository.readPackage(sourceBookId);
      } catch (_) {
        package = null;
      }
    }
    if (package == null) {
      return null;
    }
    final voiceId = package.wordAudioVoiceId.trim();
    if (voiceId.isEmpty) {
      return null;
    }
    final candidates = <String>{
      item.lemma.trim(),
      item.headText.trim(),
      item.surfaceText.trim(),
    }..removeWhere((value) => value.isEmpty);
    for (final candidate in candidates) {
      final cached = await _packageRepository.getCachedWordAudioPath(
        localBookId: package.meta.localBookId,
        voiceId: voiceId,
        word: candidate,
      );
      if (cached != null) {
        return cached;
      }
    }
    return null;
  }

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MobileReaderCatalogScreen(
        onBookOpened: _handleBookOpened,
        onLibraryLoaded: _handleLibraryLoaded,
        reloadTick: _libraryReloadTick,
        settings: _appSettings,
      ),
      _activeBookId == null
          ? const ReaderEmptyScreen()
          : MobileReaderScreen(
              key: ValueKey(
                '${_activeBookId}_${_appSettings.preferredTargetLang}_${_appSettings.preferredVoiceId}_$_readerReloadTick',
              ),
              api: widget.api,
              localBookId: _activeBookId!,
              cardsRepository: _cardsRepository,
              deviceId: _appSettings.deviceId ?? '',
              preferredVoiceId: _appSettings.preferredVoiceId,
              playbackRepeatMode: _playbackRepeatMode,
              libraryPlaybackQueue: _libraryPlaybackQueue,
              onPlaybackRepeatModeChanged: _handlePlaybackRepeatModeChanged,
              onLibraryPlaybackCompleted: _handleLibraryPlaybackCompleted,
              autoplayVoiceId: _pendingAutoplayVoiceId,
              autoplayLevelIds: _pendingAutoplayLevelIds,
              autoplayToken: _autoplayToken,
              onCardsChanged: _handleCardsChanged,
            ),
      CardsListScreen(
        api: widget.api,
        reloadTick: _cardsReloadTick,
        loadCards: _loadLocalCards,
        loadReviewCards: _loadLocalReviewCards,
        deleteCard: _deleteLocalCard,
        applyReviewResult: _applyLocalReviewResult,
        resolveLocalWordAudioPath: _resolveLocalCardAudioPath,
      ),
      MobileSettingsScreen(
        settings: _appSettings,
        onPreferredTargetLangChanged: _setPreferredTargetLang,
        onPreferredVoiceChanged: _setPreferredVoice,
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
          if (index == 0) {
            _libraryReloadTick += 1;
          }
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
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
