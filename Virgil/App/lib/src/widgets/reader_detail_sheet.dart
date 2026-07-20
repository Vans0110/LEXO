import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../detail_sheet_models.dart';

class ReaderDetailSheet extends StatelessWidget {
  const ReaderDetailSheet({
    super.key,
    required this.payload,
    this.onSaveWord,
    this.onPlayWordAudio,
  });

  final DetailSheetPayload payload;
  final Future<void> Function(
    DetailSheetUnitItem unit,
    List<String> translations,
  )? onSaveWord;
  final Future<void> Function()? onPlayWordAudio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    payload.sheetSourceText,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy word',
                  onPressed: () => _copyText(
                      context, payload.sheetSourceText, 'Word copied'),
                  icon: const Icon(Icons.copy_outlined),
                ),
                if (onPlayWordAudio != null) ...[
                  IconButton(
                    tooltip: 'Play word audio',
                    onPressed: onPlayWordAudio,
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                ],
              ],
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            payload.exampleSourceText,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy segment',
                          onPressed: () => _copyText(
                            context,
                            payload.exampleSourceText,
                            'Segment copied',
                          ),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      ],
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
            if (payload.blockSource.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _BlockCard(payload: payload),
            ],
            if (_shouldShowUnitsBlock(payload)) ...[
              const SizedBox(height: 16),
              _UnitsBlock(units: payload.units, onSaveWord: onSaveWord),
            ],
            if (payload.sourceFirst != null &&
                (payload.sourceFirst!.units.isNotEmpty ||
                    payload.sourceFirst!.groups.isNotEmpty)) ...[
              const SizedBox(height: 16),
              _SourceFirstBlock(payload: payload.sourceFirst!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copyText(
      BuildContext context, String text, String message) async {
    final value = text.trim();
    if (value.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.payload});

  final DetailSheetPayload payload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Blocks',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(payload.blockSource,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (payload.blockTranslation.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(payload.blockTranslation,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
          ],
          if (payload.blockExplanation.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(payload.blockExplanation,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

bool _shouldShowUnitsBlock(DetailSheetPayload payload) {
  return payload.units.any((unit) => unit.translation.trim().isNotEmpty);
}

class _UnitsBlock extends StatelessWidget {
  const _UnitsBlock({required this.units, required this.onSaveWord});

  final List<DetailSheetUnitItem> units;
  final Future<void> Function(
    DetailSheetUnitItem unit,
    List<String> translations,
  )? onSaveWord;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Words',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < units.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          units[index].text,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (units[index].translation.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            units[index].translation,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                        if (units[index]
                            .functionWordExplanation
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          if (units[index].functionWordLabel.trim().isNotEmpty)
                            Text(
                              units[index].functionWordLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            units[index].functionWordExplanation,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onSaveWord != null &&
                      _unitTranslationOptions(units[index]).isNotEmpty)
                    IconButton(
                      tooltip: 'Save word',
                      onPressed: () => _openUnitSaveSelection(
                        context,
                        units[index],
                        onSaveWord!,
                      ),
                      icon: const Icon(Icons.bookmark_add_outlined),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<_DictionaryTranslationOption> _unitTranslationOptions(
    DetailSheetUnitItem unit) {
  final result = <_DictionaryTranslationOption>[];
  final seen = <String>{};
  for (final translation in unit.translation.split('/')) {
    final text = translation.trim();
    final key = text.toLowerCase();
    if (text.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(_DictionaryTranslationOption(text: text, sourceLabel: ''));
  }
  return result;
}

Future<void> _openUnitSaveSelection(
  BuildContext context,
  DetailSheetUnitItem unit,
  Future<void> Function(
    DetailSheetUnitItem unit,
    List<String> translations,
  ) onSave,
) async {
  final selected = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DictionarySaveSelectionSheet(
      options: _unitTranslationOptions(unit),
    ),
  );
  if (selected == null || selected.isEmpty) {
    return;
  }
  await onSave(unit, selected);
}

class _DictionaryTranslationOption {
  const _DictionaryTranslationOption({
    required this.text,
    required this.sourceLabel,
  });

  final String text;
  final String sourceLabel;
}

class _DictionarySaveSelectionSheet extends StatefulWidget {
  const _DictionarySaveSelectionSheet({
    required this.options,
  });

  final List<_DictionaryTranslationOption> options;

  @override
  State<_DictionarySaveSelectionSheet> createState() =>
      _DictionarySaveSelectionSheetState();
}

class _DictionarySaveSelectionSheetState
    extends State<_DictionarySaveSelectionSheet> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose translation',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.options.length,
                itemBuilder: (context, index) {
                  final option = widget.options[index];
                  final checked = _selected.contains(option.text);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: checked,
                    title: Text(option.text),
                    subtitle: option.sourceLabel.trim().isEmpty
                        ? null
                        : Text(
                            option.sourceLabel,
                            style:
                                TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selected.add(option.text);
                        } else {
                          _selected.remove(option.text);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == widget.options.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(widget.options.map((option) => option.text));
                      }
                    });
                  },
                  child: Text(_selected.length == widget.options.length
                      ? 'Clear all'
                      : 'Select all'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected.toList()),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceFirstBlock extends StatelessWidget {
  const _SourceFirstBlock({required this.payload});

  final DetailSheetSourceFirstPayload payload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedUnit = payload.selectedUnit ?? const <String, dynamic>{};
    final selectedGroup = payload.selectedGroup ?? const <String, dynamic>{};
    final selectedText = selectedUnit['source_text'] as String? ?? '';
    final selectedType = selectedUnit['type'] as String? ?? '';
    final coverage =
        selectedUnit['effective_coverage'] as Map<String, dynamic>? ??
            selectedUnit['coverage'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    final coverageStatus = coverage['coverage_status'] as String? ?? '';
    final coverageText = coverage['target_text'] as String? ?? '';
    final groupText = selectedGroup['source_text'] as String? ?? '';
    final groupType = selectedGroup['type'] as String? ?? '';
    final groupCoverage = selectedGroup['coverage'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final groupCoverageStatus =
        groupCoverage['coverage_status'] as String? ?? '';
    final groupCoverageText = groupCoverage['target_text'] as String? ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.secondary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Source-first',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (selectedText.trim().isNotEmpty)
            Text(
              '$selectedText${selectedType.isNotEmpty ? ' [$selectedType]' : ''}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          if (coverageStatus.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Coverage: $coverageStatus${coverageText.trim().isNotEmpty ? ' -> $coverageText' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (groupText.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Group: $groupText${groupType.isNotEmpty ? ' [$groupType]' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (groupCoverageStatus.trim().isNotEmpty)
              Text(
                'Group coverage: $groupCoverageStatus${groupCoverageText.trim().isNotEmpty ? ' -> $groupCoverageText' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Units: ${payload.units.length}  Groups: ${payload.groups.length}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
