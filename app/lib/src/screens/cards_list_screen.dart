import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../cards_models.dart';
import 'card_review_screen.dart';

class CardsListScreen extends StatefulWidget {
  const CardsListScreen({
    super.key,
    this.api,
    this.reloadTick = 0,
    this.loadCards,
    this.loadReviewCards,
    this.deleteCard,
    this.applyReviewResult,
    this.resolveLocalWordAudioPath,
  });

  final LexoApiClient? api;
  final int reloadTick;
  final Future<SavedCardsPayload> Function()? loadCards;
  final Future<SavedCardsPayload> Function()? loadReviewCards;
  final Future<void> Function(SavedCardItem item)? deleteCard;
  final Future<SavedCardItem> Function(String cardId, String direction)? applyReviewResult;
  final Future<String?> Function(SavedCardItem item)? resolveLocalWordAudioPath;

  @override
  State<CardsListScreen> createState() => _CardsListScreenState();
}

class _CardsListScreenState extends State<CardsListScreen> {
  SavedCardsPayload? _payload;
  bool _busy = true;
  String? _error;
  late final Player _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = Player();
    _load();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CardsListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadTick != widget.reloadTick) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final loader = widget.loadCards;
      final payload = loader != null ? await loader() : await widget.api!.getSavedCards();
      if (!mounted) {
        return;
      }
      setState(() => _payload = payload);
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

  Future<void> _startReview() async {
    try {
      final reviewLoader = widget.loadReviewCards;
      final payload = reviewLoader != null ? await reviewLoader() : await widget.api!.getReviewCards();
      if (!mounted) {
        return;
      }
      if (payload.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет карточек для повторения')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CardReviewScreen(
            api: widget.api,
            items: payload.items,
            onApplyReviewResult: widget.applyReviewResult,
            resolveLocalWordAudioPath: widget.resolveLocalWordAudioPath,
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось запустить повторение: $error')),
      );
    }
  }

  Future<void> _deleteCard(SavedCardItem item) async {
    try {
      final deleter = widget.deleteCard;
      if (deleter != null) {
        await deleter(item);
      } else {
        await widget.api!.deleteSavedCard(cardId: item.id);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удалено: ${item.headText}')),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $error')),
      );
    }
  }

  Future<void> _playWordAudio(SavedCardItem item) async {
    final resolver = widget.resolveLocalWordAudioPath;
    String audioPath;
    if (resolver != null) {
      final resolved = await resolver(item);
      if (resolved == null || resolved.trim().isEmpty) {
        throw Exception('Локальный word audio не найден. Выполните Синхронизацию книги.');
      }
      audioPath = resolved;
    } else {
      final api = widget.api;
      if (api == null) {
        throw Exception('API is not available for word audio');
      }
      final bytes = await api.downloadWordAudio(item.headText);
      final tempDir = await getTemporaryDirectory();
      final audioFile = File('${tempDir.path}/lexo_card_word_${item.headText.hashCode}.wav');
      await audioFile.writeAsBytes(bytes, flush: true);
      audioPath = audioFile.path;
    }
    await _audioPlayer.stop();
    await _audioPlayer.open(Media(audioPath), play: true);
  }

  Future<bool> _confirmDelete(SavedCardItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить карточку?'),
        content: Text('Карточка "${item.headText}" будет удалена из списка.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final items = payload?.items ?? const <SavedCardItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cards'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _startReview,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Review'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : items.isEmpty
                          ? const Center(
                              child: Text('Карточек пока нет. Добавьте их из reader через long press.'),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return Dismissible(
                                    key: ValueKey(item.id),
                                    direction: DismissDirection.startToEnd,
                                    confirmDismiss: (_) async {
                                      await _deleteCard(item);
                                      return true;
                                    },
                                    background: const _DeleteBackground(),
                                    child: _CardListTile(
                                      item: item,
                                      onPlayAudio: () async {
                                        try {
                                          await _playWordAudio(item);
                                        } catch (error) {
                                          if (!mounted) {
                                            return;
                                          }
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Не удалось проиграть слово: $error')),
                                          );
                                        }
                                      },
                                      onLongPress: () async {
                                        final confirmed = await _confirmDelete(item);
                                        if (!confirmed) {
                                          return;
                                        }
                                        await _deleteCard(item);
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardListTile extends StatelessWidget {
  const _CardListTile({
    required this.item,
    this.onPlayAudio,
    this.onLongPress,
  });

  final SavedCardItem item;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          title: Text(
            item.headText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          trailing: IconButton(
            onPressed: onPlayAudio,
            icon: const Icon(Icons.volume_up_outlined),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _ProgressStrip(score: item.progressScore),
          ),
        ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < 7; index++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: index < score
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (index < 6) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Удалить', style: TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}
