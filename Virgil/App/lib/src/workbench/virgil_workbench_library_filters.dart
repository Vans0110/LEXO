import 'package:flutter/material.dart';

enum VirgilWorkbenchReadyFilter {
  all,
  ready,
  incomplete,
}

class VirgilWorkbenchLibraryFilters extends StatelessWidget {
  const VirgilWorkbenchLibraryFilters({
    super.key,
    required this.level,
    required this.chapter,
    required this.readyFilter,
    required this.levels,
    required this.chapters,
    required this.busy,
    required this.onLevelChanged,
    required this.onChapterChanged,
    required this.onReadyFilterChanged,
    required this.onApply,
    required this.hasPendingChanges,
  });

  final String level;
  final String chapter;
  final VirgilWorkbenchReadyFilter readyFilter;
  final List<String> levels;
  final List<String> chapters;
  final bool busy;
  final ValueChanged<String> onLevelChanged;
  final ValueChanged<String> onChapterChanged;
  final ValueChanged<VirgilWorkbenchReadyFilter> onReadyFilterChanged;
  final VoidCallback onApply;
  final bool hasPendingChanges;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _FilterDropdown<String>(
          width: 150,
          label: 'Level',
          value: level,
          items: [
            const DropdownMenuItem(value: '', child: Text('All levels')),
            for (final item in levels)
              DropdownMenuItem(
                value: item,
                child: Text(item.toUpperCase()),
              ),
          ],
          onChanged: busy ? null : onLevelChanged,
        ),
        _FilterDropdown<String>(
          width: 260,
          label: 'Chapter',
          value: chapter,
          items: [
            const DropdownMenuItem(value: '', child: Text('All chapters')),
            for (final item in chapters)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: busy ? null : onChapterChanged,
        ),
        _FilterDropdown<VirgilWorkbenchReadyFilter>(
          width: 180,
          label: 'Build status',
          value: readyFilter,
          items: const [
            DropdownMenuItem(
              value: VirgilWorkbenchReadyFilter.all,
              child: Text('All books'),
            ),
            DropdownMenuItem(
              value: VirgilWorkbenchReadyFilter.ready,
              child: Text('Built'),
            ),
            DropdownMenuItem(
              value: VirgilWorkbenchReadyFilter.incomplete,
              child: Text('Not built'),
            ),
          ],
          onChanged: busy ? null : onReadyFilterChanged,
        ),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: busy || !hasPendingChanges ? null : onApply,
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final double width;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        key: ValueKey<T>(value),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items,
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) {
                  onChanged!(value);
                }
              },
      ),
    );
  }
}
