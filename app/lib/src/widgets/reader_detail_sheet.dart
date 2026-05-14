import 'package:flutter/material.dart';

import '../detail_sheet_models.dart';

class ReaderDetailSheet extends StatelessWidget {
  const ReaderDetailSheet({
    super.key,
    required this.payload,
    this.onSaveDictionaryCard,
    this.onPlayWordAudio,
  });

  final DetailSheetPayload payload;
  final Future<void> Function(List<String> translations)? onSaveDictionaryCard;
  final Future<void> Function()? onPlayWordAudio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          shrinkWrap: true,
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
                if (onPlayWordAudio != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Озвучить слово',
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
            if (payload.dictionaryEntry?.hasContent == true || (payload.dictionaryEntry?.note.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              _DictionaryBlock(
                entry: payload.dictionaryEntry!,
                onSaveCard: onSaveDictionaryCard,
              ),
            ],
            if (payload.sourceFirst != null) ...[
              const SizedBox(height: 16),
              _SourceFirstBlock(payload: payload.sourceFirst!),
            ],
            if (payload.units.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (var index = 0; index < payload.units.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                _UnitRow(item: payload.units[index]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DictionaryBlock extends StatelessWidget {
  const _DictionaryBlock({
    required this.entry,
    required this.onSaveCard,
  });

  final DetailSheetDictionaryEntry entry;
  final Future<void> Function(List<String> translations)? onSaveCard;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wordEntry = entry.wordEntry;
    final verbForms = entry.verbForms;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withOpacity(0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.tertiary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dictionary',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (entry.query.trim().isNotEmpty)
            Text(
              entry.query,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          if (onSaveCard != null && _dictionaryTranslationOptions(entry).isNotEmpty) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _openSaveSelection(context, entry, onSaveCard!),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Сохранить'),
            ),
          ],
          if (entry.entries.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var index = 0; index < entry.entries.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              _DictionaryArticleBlock(article: entry.entries[index]),
            ],
          ],
          if (wordEntry != null && wordEntry.transcript.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              wordEntry.transcript,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
          if (verbForms != null &&
              (verbForms.present.trim().isNotEmpty ||
                  verbForms.past.trim().isNotEmpty ||
                  verbForms.participle.trim().isNotEmpty)) ...[
            const SizedBox(height: 10),
            Text(
              'Verb forms',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (verbForms.present.trim().isNotEmpty) Text('Present: ${verbForms.present}'),
            if (verbForms.past.trim().isNotEmpty) Text('Past: ${verbForms.past}'),
            if (verbForms.participle.trim().isNotEmpty) Text('Participle: ${verbForms.participle}'),
          ],
          if (entry.inflectedForms.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Forms: ${entry.inflectedForms.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (wordEntry != null && wordEntry.similar.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Related: ${wordEntry.similar.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (entry.phrasals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Phrasal verbs',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            for (final phrasal in entry.phrasals) ...[
              Text(
                phrasal.word,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (phrasal.transcript.trim().isNotEmpty)
                Text(
                  phrasal.transcript,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              if (phrasal.translation.trim().isNotEmpty)
                Text(
                  phrasal.translation,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              for (final definition in phrasal.definitions.take(3))
                Text(
                  '• $definition',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
            ],
          ],
          if (entry.note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openSaveSelection(
    BuildContext context,
    DetailSheetDictionaryEntry entry,
    Future<void> Function(List<String> translations) onSave,
  ) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DictionarySaveSelectionSheet(
        options: _dictionaryTranslationOptions(entry),
      ),
    );
    if (selected == null || selected.isEmpty) {
      return;
    }
    await onSave(selected);
  }
}

List<_DictionaryTranslationOption> _dictionaryTranslationOptions(DetailSheetDictionaryEntry entry) {
  final result = <_DictionaryTranslationOption>[];
  final seen = <String>{};
  for (final article in entry.entries) {
    final sourceParts = [
      if (article.source.trim().isNotEmpty) article.source.trim(),
      if (article.partOfSpeech.trim().isNotEmpty) article.partOfSpeech.trim(),
    ];
    final sourceLabel = sourceParts.join(' · ');
    for (final translation in article.translations) {
      final text = translation.trim();
      final key = text.toLowerCase();
      if (text.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      result.add(_DictionaryTranslationOption(text: text, sourceLabel: sourceLabel));
    }
  }
  for (final translation in entry.translations) {
    final text = translation.trim();
    final key = text.toLowerCase();
    if (text.isEmpty || seen.contains(key)) {
      continue;
    }
    seen.add(key);
    result.add(_DictionaryTranslationOption(text: text, sourceLabel: ''));
  }
  return result;
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
  State<_DictionarySaveSelectionSheet> createState() => _DictionarySaveSelectionSheetState();
}

class _DictionarySaveSelectionSheetState extends State<_DictionarySaveSelectionSheet> {
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
              'Выберите перевод',
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
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
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
                  child: Text(_selected.length == widget.options.length ? 'Снять все' : 'Выбрать все'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected.toList()),
                  child: const Text('ОК'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DictionaryArticleBlock extends StatelessWidget {
  const _DictionaryArticleBlock({required this.article});

  final DetailSheetDictionaryArticle article;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleParts = [
      if (article.source.trim().isNotEmpty) article.source,
      if (article.partOfSpeech.trim().isNotEmpty) article.partOfSpeech,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleParts.join(' · '),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (article.lemma.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              article.lemma,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (article.transcript.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              article.transcript,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
          if (article.translations.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final translation in article.translations.take(8))
              Text(
                '• $translation',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
          ],
          if (article.definitions.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final definition in article.definitions.take(2))
              Text(
                '• $definition',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ],
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
    final coverage = selectedUnit['effective_coverage'] as Map<String, dynamic>? ??
        selectedUnit['coverage'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final coverageStatus = coverage['coverage_status'] as String? ?? '';
    final coverageText = coverage['target_text'] as String? ?? '';
    final groupText = selectedGroup['source_text'] as String? ?? '';
    final groupType = selectedGroup['type'] as String? ?? '';
    final groupCoverage = selectedGroup['coverage'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final groupCoverageStatus = groupCoverage['coverage_status'] as String? ?? '';
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

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.item,
  });

  final DetailSheetUnitItem item;

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
        ],
      ),
    );
  }
}
