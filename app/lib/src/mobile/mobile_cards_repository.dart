import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../cards_models.dart';
import '../detail_sheet_models.dart';

class MobileCardsRepository {
  Future<SavedCardsPayload> listCards({String? status}) async {
    final items = await _readCards();
    final normalizedStatus = (status ?? '').trim().toLowerCase();
    final filtered = items
        .where((item) => !item.isDeleted)
        .where((item) => normalizedStatus.isEmpty || item.status == normalizedStatus)
        .toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return SavedCardsPayload(
      items: filtered,
      summary: _buildSummary(filtered),
    );
  }

  Future<SavedCardsPayload> getReviewCards() async {
    final items = await _readCards();
    final filtered = items
        .where((item) => !item.isDeleted)
        .where((item) => item.cardType == 'lexical' || item.cardType == 'phrase')
        .toList()
      ..sort((left, right) {
        final scoreCompare = left.progressScore.compareTo(right.progressScore);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return left.createdAt.compareTo(right.createdAt);
      });
    return SavedCardsPayload(
      items: filtered.take(50).toList(),
      summary: _buildSummary(filtered),
    );
  }

  Future<Map<String, dynamic>> saveDetailUnit({
    required String deviceId,
    required String originBookId,
    required DetailSheetUnitItem unit,
  }) async {
    final items = await _readCards();
    final existing = items.where((item) => !item.isDeleted).firstWhere(
          (item) =>
              item.sourceBookId == originBookId &&
              item.cardType == unit.type.toLowerCase() &&
              item.lemma == unit.lemma &&
              item.translation == unit.translation,
          orElse: () => const SavedCardItem(
            id: '',
            deviceId: '',
            cardType: '',
            headText: '',
            surfaceText: '',
            lemma: '',
            translation: '',
            exampleText: '',
            exampleTranslation: '',
            pos: '',
            grammarLabel: '',
            morphLabel: '',
            sourceBookId: '',
            sourceUnitId: '',
            createdAt: '',
            updatedAt: '',
            deletedAt: '',
            syncState: 'synced',
            status: 'new',
            progressScore: 0,
            reviewCount: 0,
            lastReviewedAt: '',
          ),
        );
    if (existing.id.isNotEmpty) {
      return {
        'ok': true,
        'saved': false,
        'item': existing.toJson(),
      };
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final card = SavedCardItem(
      id: _newUuid(),
      deviceId: deviceId,
      cardType: unit.type.toLowerCase(),
      headText: unit.text,
      surfaceText: unit.surfaceText,
      lemma: unit.lemma,
      translation: unit.translation,
      exampleText: unit.exampleSourceText,
      exampleTranslation: unit.exampleTranslationText,
      pos: '',
      grammarLabel: unit.grammarHint,
      morphLabel: unit.morphLabel,
      sourceBookId: originBookId,
      sourceUnitId: unit.id,
      createdAt: now,
      updatedAt: now,
      deletedAt: '',
      syncState: 'local_new',
      status: 'new',
      progressScore: 0,
      reviewCount: 0,
      lastReviewedAt: '',
    );
    items.add(card);
    await _writeCards(items);
    return {
      'ok': true,
      'saved': true,
      'item': card.toJson(),
    };
  }

  Future<SavedCardItem> applyReviewResult({
    required String cardId,
    required String direction,
  }) async {
    final items = await _readCards();
    final index = items.indexWhere((item) => item.id == cardId);
    if (index < 0) {
      throw Exception('Card not found: $cardId');
    }
    final current = items[index];
    final now = DateTime.now().toUtc().toIso8601String();
    final nextScore = direction == 'right'
        ? min(7, current.progressScore + 1)
        : (current.progressScore > 1 ? max(0, current.progressScore - 1) : current.progressScore);
    final updated = SavedCardItem(
      id: current.id,
      deviceId: current.deviceId,
      cardType: current.cardType,
      headText: current.headText,
      surfaceText: current.surfaceText,
      lemma: current.lemma,
      translation: current.translation,
      exampleText: current.exampleText,
      exampleTranslation: current.exampleTranslation,
      pos: current.pos,
      grammarLabel: current.grammarLabel,
      morphLabel: current.morphLabel,
      sourceBookId: current.sourceBookId,
      sourceUnitId: current.sourceUnitId,
      createdAt: current.createdAt,
      updatedAt: now,
      deletedAt: current.deletedAt,
      syncState: current.syncState == 'local_new' ? 'local_new' : 'local_modified',
      status: _statusForScore(nextScore),
      progressScore: nextScore,
      reviewCount: current.reviewCount + 1,
      lastReviewedAt: now,
    );
    items[index] = updated;
    await _writeCards(items);
    return updated;
  }

  Future<Map<String, dynamic>> deleteCard({
    required String cardId,
  }) async {
    final items = await _readCards();
    final index = items.indexWhere((item) => item.id == cardId);
    if (index < 0) {
      throw Exception('Card not found: $cardId');
    }
    final current = items[index];
    if (current.syncState == 'local_new') {
      items.removeAt(index);
      await _writeCards(items);
      return {
        'ok': true,
        'deleted': true,
        'item': current.toJson(),
      };
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final deleted = SavedCardItem(
      id: current.id,
      deviceId: current.deviceId,
      cardType: current.cardType,
      headText: current.headText,
      surfaceText: current.surfaceText,
      lemma: current.lemma,
      translation: current.translation,
      exampleText: current.exampleText,
      exampleTranslation: current.exampleTranslation,
      pos: current.pos,
      grammarLabel: current.grammarLabel,
      morphLabel: current.morphLabel,
      sourceBookId: current.sourceBookId,
      sourceUnitId: current.sourceUnitId,
      createdAt: current.createdAt,
      updatedAt: now,
      deletedAt: now,
      syncState: 'local_deleted',
      status: current.status,
      progressScore: current.progressScore,
      reviewCount: current.reviewCount,
      lastReviewedAt: current.lastReviewedAt,
    );
    items[index] = deleted;
    await _writeCards(items);
    return {
      'ok': true,
      'deleted': true,
      'item': deleted.toJson(),
    };
  }

  Future<int> pendingChangesCount() async {
    final items = await _readCards();
    return items.where((item) => item.syncState != 'synced').length;
  }

  Future<List<Map<String, dynamic>>> exportDelta() async {
    final items = await _readCards();
    return items
        .where((item) => item.syncState != 'synced')
        .map((item) => item.toJson())
        .toList();
  }

  Future<void> replaceWithMergedCards(List<Map<String, dynamic>> mergedCards) async {
    final items = mergedCards.map(SavedCardItem.fromJson).map(_markSynced).toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    await _writeCards(items);
  }

  Future<void> markPendingAsSynced() async {
    final items = await _readCards();
    final next = items
        .map((item) => item.syncState == 'synced' ? item : _markSynced(item))
        .toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    await _writeCards(next);
  }

  SavedCardItem _markSynced(SavedCardItem item) {
    return SavedCardItem(
      id: item.id,
      deviceId: item.deviceId,
      cardType: item.cardType,
      headText: item.headText,
      surfaceText: item.surfaceText,
      lemma: item.lemma,
      translation: item.translation,
      exampleText: item.exampleText,
      exampleTranslation: item.exampleTranslation,
      pos: item.pos,
      grammarLabel: item.grammarLabel,
      morphLabel: item.morphLabel,
      sourceBookId: item.sourceBookId,
      sourceUnitId: item.sourceUnitId,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      deletedAt: item.deletedAt,
      syncState: 'synced',
      status: item.status,
      progressScore: item.progressScore,
      reviewCount: item.reviewCount,
      lastReviewedAt: item.lastReviewedAt,
    );
  }

  CardsSummary _buildSummary(List<SavedCardItem> items) {
    var fresh = 0;
    var learning = 0;
    var known = 0;
    var mastered = 0;
    for (final item in items) {
      switch (item.status) {
        case 'new':
          fresh += 1;
          break;
        case 'learning':
          learning += 1;
          break;
        case 'known':
          known += 1;
          break;
        case 'mastered':
          mastered += 1;
          break;
      }
    }
    return CardsSummary(
      total: items.length,
      fresh: fresh,
      learning: learning,
      known: known,
      mastered: mastered,
    );
  }

  String _statusForScore(int score) {
    if (score <= 0) {
      return 'new';
    }
    if (score <= 3) {
      return 'learning';
    }
    if (score <= 5) {
      return 'known';
    }
    return 'mastered';
  }

  Future<List<SavedCardItem>> _readCards() async {
    final file = await _cardsFile();
    if (!file.existsSync()) {
      return <SavedCardItem>[];
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (raw['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(SavedCardItem.fromJson)
        .toList();
  }

  Future<void> _writeCards(List<SavedCardItem> items) async {
    final file = await _cardsFile();
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'items': items.map((item) => item.toJson()).toList(),
      }),
      encoding: utf8,
    );
  }

  Future<File> _cardsFile() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/mobile_cards.json');
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
}
