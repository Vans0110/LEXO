import 'package:flutter/material.dart';

class ImportTextDraft {
  const ImportTextDraft({
    required this.title,
    required this.sourceText,
  });

  final String title;
  final String sourceText;
}

Future<ImportTextDraft?> showImportTextDialog(
  BuildContext context, {
  String initialTitle = '',
  String initialSourceText = '',
}) {
  final titleController = TextEditingController(text: initialTitle);
  final sourceController = TextEditingController(text: initialSourceText);
  String? errorText;

  return showDialog<ImportTextDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final rawSource = sourceController.text.trim();
            final rawTitle = titleController.text.trim();
            if (rawSource.isEmpty) {
              setState(() => errorText = 'Enter the book text.');
              return;
            }
            final resolvedTitle =
                rawTitle.isNotEmpty ? rawTitle : _deriveTitle(rawSource);
            if (resolvedTitle.isEmpty) {
              setState(() => errorText = 'Enter the book title.');
              return;
            }
            Navigator.of(context).pop(
              ImportTextDraft(
                title: resolvedTitle,
                sourceText: sourceController.text,
              ),
            );
          }

          return AlertDialog(
            title: const Text('Import Text'),
            content: SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Book title',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: TextField(
                      controller: sourceController,
                      minLines: 18,
                      maxLines: 18,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: 'Source text',
                        hintText: 'Paste TXT content here',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  if (errorText != null && errorText!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Import'),
              ),
            ],
          );
        },
      );
    },
  );
}

String _deriveTitle(String sourceText) {
  for (final line in sourceText.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}
