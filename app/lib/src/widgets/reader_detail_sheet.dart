import 'package:flutter/material.dart';

import '../detail_sheet_models.dart';

class ReaderDetailSheet extends StatelessWidget {
  const ReaderDetailSheet({
    super.key,
    required this.payload,
    this.onSaveUnit,
  });

  final DetailSheetPayload payload;
  final Future<String?> Function(DetailSheetUnitItem unit)? onSaveUnit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              payload.sheetSourceText,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              payload.sheetTranslationText,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (payload.exampleSourceText.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.exampleSourceText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (payload.exampleTranslationText.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        payload.exampleTranslationText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: payload.units.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = payload.units[index];
                  return _UnitRow(item: item, onSaveUnit: onSaveUnit);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.item,
    this.onSaveUnit,
  });

  final DetailSheetUnitItem item;
  final Future<String?> Function(DetailSheetUnitItem unit)? onSaveUnit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hintText = item.isGrammar ? item.grammarHint : item.translation;
    final toneColor = item.isGrammar ? colorScheme.onSurfaceVariant : colorScheme.onSurface;
    final chipLabel = item.isPhrase
        ? 'Фраза'
        : item.isGrammar
            ? 'Грамматика'
            : 'Слово';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.isGrammar
            ? colorScheme.surfaceContainerHighest.withOpacity(0.35)
            : colorScheme.surfaceContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isPrimary
              ? colorScheme.outlineVariant.withOpacity(0.55)
              : colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: item.isGrammar ? FontWeight.w600 : FontWeight.w700,
                        color: toneColor,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(item.isPrimary ? 0.8 : 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chipLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (hintText.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hintText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: item.isGrammar ? colorScheme.onSurfaceVariant : colorScheme.primary,
                    fontWeight: item.isGrammar ? FontWeight.w500 : FontWeight.w600,
                  ),
            ),
          ],
          if (item.morphLabel.trim().isNotEmpty && item.surfaceText.trim().isNotEmpty && item.surfaceText != item.text) ...[
            const SizedBox(height: 6),
            Text(
              '${item.surfaceText} -> ${item.morphLabel}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (!item.isGrammar && onSaveUnit != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final message = await onSaveUnit!(item);
                  if (message == null || message.trim().isEmpty) {
                    return;
                  }
                  messenger.showSnackBar(SnackBar(content: Text(message)));
                },
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Добавить'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
