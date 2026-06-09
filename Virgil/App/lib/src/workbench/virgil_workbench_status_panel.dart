import 'package:flutter/material.dart';

import '../models.dart';

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
