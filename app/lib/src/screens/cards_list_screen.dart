import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../cards_models.dart';
import 'card_review_screen.dart';

class CardsListScreen extends StatefulWidget {
  const CardsListScreen({
    super.key,
    required this.api,
    this.reloadTick = 0,
  });

  final LexoApiClient api;
  final int reloadTick;

  @override
  State<CardsListScreen> createState() => _CardsListScreenState();
}

class _CardsListScreenState extends State<CardsListScreen> {
  static const List<_CardsFilter> _filters = [
    _CardsFilter('all', 'Все'),
    _CardsFilter('new', 'Новые'),
    _CardsFilter('learning', 'Учу'),
    _CardsFilter('known', 'Знаю'),
    _CardsFilter('mastered', 'Закрепил'),
  ];

  SavedCardsPayload? _payload;
  bool _busy = true;
  String? _error;
  String _filter = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
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
      final payload = await widget.api.getSavedCards(
        status: _filter == 'all' ? null : _filter,
      );
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
      final payload = await widget.api.getReviewCards();
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
          builder: (_) => CardReviewScreen(api: widget.api, items: payload.items),
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

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final items = payload?.items ?? const <SavedCardItem>[];
    final visible = items.where((item) {
      if (_query.isEmpty) {
        return true;
      }
      final haystack = '${item.headText} ${item.translation} ${item.lemma}'.toLowerCase();
      return haystack.contains(_query);
    }).toList();

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
            if (payload != null) _SummaryStrip(summary: payload.summary),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Поиск карточек',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _startReview,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Review'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in _filters)
                  ChoiceChip(
                    label: Text(filter.label),
                    selected: _filter == filter.value,
                    onSelected: (selected) async {
                      if (!selected || _filter == filter.value) {
                        return;
                      }
                      setState(() => _filter = filter.value);
                      await _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : visible.isEmpty
                          ? const Center(
                              child: Text('Карточек пока нет. Добавьте их из reader через long press.'),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) => _CardListTile(item: visible[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});

  final CardsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryChip(label: 'Всего', value: summary.total),
        _SummaryChip(label: 'Новые', value: summary.fresh),
        _SummaryChip(label: 'Учу', value: summary.learning),
        _SummaryChip(label: 'Знаю', value: summary.known),
        _SummaryChip(label: 'Закрепил', value: summary.mastered),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}

class _CardListTile extends StatelessWidget {
  const _CardListTile({required this.item});

  final SavedCardItem item;

  @override
  Widget build(BuildContext context) {
    String typeLabel;
    if (item.cardType == 'phrase') {
      typeLabel = 'phrase';
    } else if (item.cardType == 'grammar') {
      typeLabel = 'grammar';
    } else {
      typeLabel = 'lexical';
    }
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        title: Text(item.headText),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item.translation),
            if (item.morphLabel.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${item.surfaceText} -> ${item.morphLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(typeLabel, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(item.progressLabel, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _CardsFilter {
  const _CardsFilter(this.value, this.label);

  final String value;
  final String label;
}
