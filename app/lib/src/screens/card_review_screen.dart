import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../cards_models.dart';

class CardReviewScreen extends StatefulWidget {
  const CardReviewScreen({
    super.key,
    required this.api,
    required this.items,
  });

  final LexoApiClient api;
  final List<SavedCardItem> items;

  @override
  State<CardReviewScreen> createState() => _CardReviewScreenState();
}

class _CardReviewScreenState extends State<CardReviewScreen> {
  late final List<SavedCardItem> _queue;
  bool _busy = false;
  int _completed = 0;
  int _advanced = 0;
  int _difficult = 0;
  int _mastered = 0;

  @override
  void initState() {
    super.initState();
    _queue = List<SavedCardItem>.from(widget.items);
  }

  Future<void> _applySwipe(String direction) async {
    if (_busy || _queue.isEmpty) {
      return;
    }
    final current = _queue.first;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.applyReviewResult(
        cardId: current.id,
        direction: direction,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _queue.removeAt(0);
        _completed += 1;
        if (direction == 'right') {
          _advanced += 1;
          if (updated.status == 'mastered') {
            _mastered += 1;
          }
        } else {
          _difficult += 1;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить карточку: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _queue.isNotEmpty ? _queue.first : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: current == null
          ? _ReviewFinished(
              completed: _completed,
              advanced: _advanced,
              difficult: _difficult,
              mastered: _mastered,
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Осталось: ${_queue.length}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: widget.items.isEmpty ? 0 : _completed / widget.items.length,
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Dismissible(
                        key: ValueKey(current.id),
                        direction: DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          await _applySwipe(
                            direction == DismissDirection.endToStart ? 'left' : 'right',
                          );
                          return false;
                        },
                        background: _SwipeBackground(
                          alignment: Alignment.centerLeft,
                          color: Colors.green,
                          label: 'Знаю',
                          icon: Icons.arrow_forward,
                        ),
                        secondaryBackground: _SwipeBackground(
                          alignment: Alignment.centerRight,
                          color: Colors.orange,
                          label: 'Сложно',
                          icon: Icons.arrow_back,
                        ),
                        child: _ReviewCard(item: current),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _applySwipe('left'),
                            icon: const Icon(Icons.swipe_left),
                            label: const Text('Не знаю'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _applySwipe('right'),
                            icon: const Icon(Icons.swipe_right),
                            label: const Text('Знаю'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item});

  final SavedCardItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  item.progressLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const Spacer(),
              Text(
                item.headText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 18),
              Text(
                item.translation,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.label,
    required this.icon,
  });

  final Alignment alignment;
  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(label),
            const SizedBox(width: 8),
            Icon(icon),
          ] else ...[
            Icon(icon),
            const SizedBox(width: 8),
            Text(label),
          ],
        ],
      ),
    );
  }
}

class _ReviewFinished extends StatelessWidget {
  const _ReviewFinished({
    required this.completed,
    required this.advanced,
    required this.difficult,
    required this.mastered,
  });

  final int completed;
  final int advanced;
  final int difficult;
  final int mastered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Сессия завершена', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text('$completed карточек просмотрено'),
            Text('$advanced продвинулись'),
            Text('$difficult остались сложными'),
            Text('$mastered уже закреплены'),
          ],
        ),
      ),
    );
  }
}
