import 'package:flutter/material.dart';

import '../models.dart';
import '../api/api_client.dart';

class VirgilWorkbenchStatusPanel extends StatelessWidget {
  const VirgilWorkbenchStatusPanel({
    super.key,
    required this.sourcePath,
    required this.coverPath,
    required this.bookId,
    required this.outputPath,
    required this.packageState,
  });

  final String sourcePath;
  final String coverPath;
  final String? bookId;
  final String? outputPath;
  final TtsPackageState? packageState;

  @override
  Widget build(BuildContext context) {
    final state = packageState;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('TXT: ${sourcePath.isEmpty ? '-' : sourcePath}'),
            Text('cover: ${coverPath.isEmpty ? '-' : coverPath}'),
            Text('book_id: ${bookId ?? '-'}'),
            Text('output: ${outputPath ?? '-'}'),
            if (state != null) ...[
              const SizedBox(height: 10),
              Text('TTS package: ${state.status}'),
              if (state.errorMessage.trim().isNotEmpty)
                Text(
                  state.errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final stage in state.stages)
                Text(
                  '${stage.label}: ${stage.status} ${stage.doneCount}/${stage.totalCount}'
                  '${stage.errorMessage.trim().isEmpty ? '' : ' - ${stage.errorMessage}'}',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class VirgilWorkbenchGoogleUsagePanel extends StatelessWidget {
  const VirgilWorkbenchGoogleUsagePanel({
    super.key,
    required this.usage,
  });

  final GoogleTranslateUsage? usage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _GoogleUsageText(usage: usage),
      ),
    );
  }
}

class _GoogleUsageText extends StatelessWidget {
  const _GoogleUsageText({required this.usage});

  final GoogleTranslateUsage? usage;

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    if (usage == null) {
      return const Text('Google chars: loading...');
    }
    final byLang = usage.byLang.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final languageText = byLang.isEmpty
        ? 'no local records yet'
        : byLang
            .map(
                (entry) => '${entry.key.toUpperCase()} ${_format(entry.value)}')
            .join(', ');
    return Text(
      'Google chars ${usage.month}: '
      '${_format(usage.characterCount)} used. '
      'Work cap: up to ${_format(usage.safetyLimit)}; '
      'free tier: ${_format(usage.characterCount)} / '
      '${_format(usage.freeCharacterLimit)} '
      '(cap left ${_format(usage.remainingBeforeSafetyLimit)}, '
      'free left ${_format(usage.remainingFreeCharacters)}; $languageText)',
    );
  }
}

String _format(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    final remaining = text.length - index;
    buffer.write(text[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}
