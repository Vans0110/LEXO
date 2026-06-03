import 'dart:io';

import 'package:flutter/material.dart';

import 'nove_workbench_book_status.dart';

class NoveWorkbenchBookTile extends StatelessWidget {
  const NoveWorkbenchBookTile({
    super.key,
    required this.title,
    required this.level,
    required this.chapterTitle,
    required this.coverPath,
    required this.status,
    required this.busy,
    required this.onSelected,
    required this.onRefresh,
    required this.onRefreshDictionary,
  });

  final String title;
  final String level;
  final String chapterTitle;
  final String coverPath;
  final NoveWorkbenchBookStatus? status;
  final bool busy;
  final VoidCallback onSelected;
  final VoidCallback onRefresh;
  final VoidCallback onRefreshDictionary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final processed = status?.isProcessed ?? false;
    final resolvedCoverPath =
        coverPath.isNotEmpty ? coverPath : (status?.coverPath ?? '');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: processed
            ? colorScheme.primaryContainer.withValues(alpha: 0.34)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor(colorScheme, processed)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _BookCoverPreview(
                path: resolvedCoverPath, hasCover: status?.hasCover),
            const SizedBox(width: 14),
            Expanded(child: _BookStatusBody(tile: this)),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Refresh book',
                  onPressed: busy ? null : onRefresh,
                  icon: const Icon(Icons.refresh_outlined),
                ),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: 'Refresh dictionaries',
                  onPressed: busy ? null : onRefreshDictionary,
                  icon: const Icon(Icons.menu_book_outlined),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: busy ? null : onSelected,
                  child: const Text('Use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String statusText() {
    if (status == null) {
      return coverPath.isEmpty ? 'Not exported, no cover' : 'Not exported';
    }
    final place = status!.hasInstalledZip
        ? 'installed zip'
        : (status!.hasOutput ? 'output ready' : 'partial');
    final langs = status!.languages.isEmpty
        ? 'no langs'
        : (status!.languages.toList()..sort()).join('+').toUpperCase();
    final audio = status!.hasPlayerMetadataProblem
        ? 'audio metadata broken'
        : (status!.hasAudio
            ? (status!.missingPlayerVoiceIds.isEmpty
                ? 'audio ready'
                : 'audio partial')
            : 'no audio');
    final cover =
        (coverPath.isNotEmpty || status!.hasCover) ? 'cover ready' : 'no cover';
    return '$place, $langs, $audio, $cover';
  }

  Color _borderColor(ColorScheme colorScheme, bool processed) {
    if (status?.hasPlayerMetadataProblem ?? false) {
      return colorScheme.error.withValues(alpha: 0.7);
    }
    if (processed) {
      return colorScheme.primary.withValues(alpha: 0.45);
    }
    return colorScheme.outlineVariant;
  }
}

class _BookStatusBody extends StatelessWidget {
  const _BookStatusBody({required this.tile});

  final NoveWorkbenchBookTile tile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = tile.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tile.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${tile.level.toUpperCase()} / ${tile.chapterTitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatusSection(
              title: 'TXT',
              children: [
                const _StatusRow(label: 'EN source', ready: true),
                _StatusRow(
                  label: 'RU reader',
                  ready: status?.hasLanguage('ru') ?? false,
                ),
                _StatusRow(
                  label: 'UK reader',
                  ready: status?.hasLanguage('uk') ?? false,
                ),
              ],
            ),
            _StatusSection(
              title: 'Dictionary',
              children: [
                _StatusRow(
                  label: 'RU dictionary',
                  ready: status?.hasDictionary('ru') ?? false,
                ),
                _StatusRow(
                  label: 'UK dictionary',
                  ready: status?.hasDictionary('uk') ?? false,
                ),
              ],
            ),
            _StatusSection(
              title: 'Voice',
              children: _voiceRows(status),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          tile.statusText(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  List<Widget> _voiceRows(NoveWorkbenchBookStatus? status) {
    if (status == null) {
      return const [
        _StatusRow(label: 'Player audio', ready: false),
        _StatusRow(label: 'Word audio', ready: false),
      ];
    }
    final rows = <Widget>[];
    final playerVoiceIds = status.playerLevelsByVoice.keys.toList()..sort();
    for (final voiceId in playerVoiceIds) {
      final levels = (status.playerLevelsByVoice[voiceId] ?? const <String>{})
          .toList()
        ..sort();
      final levelSuffix = levels.isEmpty ? '' : ' (${levels.join('/')})';
      rows.add(_StatusRow(label: '$voiceId$levelSuffix', ready: true));
    }
    final missingVoiceIds = status.missingPlayerVoiceIds.toList()..sort();
    for (final voiceId in missingVoiceIds) {
      rows.add(_StatusRow(label: voiceId, ready: false));
    }
    if (rows.isEmpty) {
      rows.add(const _StatusRow(label: 'Player audio', ready: false));
    }
    final wordVoiceIds = status.wordAudioCountsByVoice.keys.toList()..sort();
    for (final voiceId in wordVoiceIds) {
      final count = status.wordAudioCountsByVoice[voiceId] ?? 0;
      rows.add(
        _StatusRow(
          label: '$voiceId word ($count)',
          ready: count > 0,
        ),
      );
    }
    for (final voiceId in status.missingWordAudioVoiceIds.toList()..sort()) {
      rows.add(_StatusRow(label: '$voiceId word missing', ready: false));
    }
    if (wordVoiceIds.isEmpty && status.wordAudioCount == 0) {
      rows.add(const _StatusRow(label: 'Word audio (0 files)', ready: false));
    }
    return rows;
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          ...children,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = ready ? colorScheme.primary : colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ready ? colorScheme.onSurfaceVariant : color,
                fontSize: 11,
                fontWeight: ready ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookCoverPreview extends StatelessWidget {
  const _BookCoverPreview({required this.path, required this.hasCover});

  final String path;
  final bool? hasCover;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final file = path.isEmpty ? null : File(path);
    final canShow = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 92,
        height: 138,
        color: colorScheme.surfaceContainerHighest,
        child: canShow
            ? Image.file(file, fit: BoxFit.cover)
            : Icon(
                hasCover == true
                    ? Icons.image_outlined
                    : Icons.hide_image_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }
}
