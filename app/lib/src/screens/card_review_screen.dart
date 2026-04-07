import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../cards_models.dart';

class CardReviewScreen extends StatefulWidget {
  const CardReviewScreen({
    super.key,
    this.api,
    required this.items,
    this.onApplyReviewResult,
  });

  final LexoApiClient? api;
  final List<SavedCardItem> items;
  final Future<SavedCardItem> Function(String cardId, String direction)? onApplyReviewResult;

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
      final callback = widget.onApplyReviewResult;
      final updated = callback != null
          ? await callback(current.id, direction)
          : await widget.api!.applyReviewResult(
              cardId: current.id,
              direction: direction,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _queue.removeAt(0);
        _queue.add(updated);
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
    final current = _queue.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Dismissible(
                  key: ValueKey('${current.id}-${current.progressScore}-${current.reviewCount}'),
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
              _ReviewProgressStrip(score: item.progressScore),
              const SizedBox(height: 16),
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

class _ReviewProgressStrip extends StatelessWidget {
  const _ReviewProgressStrip({required this.score});

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
