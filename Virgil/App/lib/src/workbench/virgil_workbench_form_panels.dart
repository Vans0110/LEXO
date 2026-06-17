import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';

class VirgilWorkbenchCoverPickerPanel extends StatelessWidget {
  const VirgilWorkbenchCoverPickerPanel({
    super.key,
    required this.coverPath,
    required this.busy,
    required this.onPickCover,
    required this.onClearCover,
  });

  final String coverPath;
  final bool busy;
  final VoidCallback onPickCover;
  final VoidCallback? onClearCover;

  @override
  Widget build(BuildContext context) {
    final hasCover = coverPath.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              height: 132,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasCover
                    ? Image.file(File(coverPath), fit: BoxFit.cover)
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.image_outlined,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cover',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(hasCover ? coverPath : 'JPG or PNG, 2:3 works best'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: busy ? null : onPickCover,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(hasCover ? 'Replace cover' : 'Add cover'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onClearCover,
                        icon: const Icon(Icons.close_outlined),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VirgilWorkbenchTranslationLanguagePanel extends StatelessWidget {
  const VirgilWorkbenchTranslationLanguagePanel({
    super.key,
    required this.selectedLangs,
    required this.busy,
    required this.onChanged,
  });

  final Set<String> selectedLangs;
  final bool busy;
  final void Function(String lang, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Book translation language',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: selectedLangs.contains('ru'),
              onChanged:
                  busy ? null : (value) => onChanged('ru', value ?? false),
              title: const Text('Russian'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: selectedLangs.contains('uk'),
              onChanged:
                  busy ? null : (value) => onChanged('uk', value ?? false),
              title: const Text('Ukrainian'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class VirgilWorkbenchDictionaryLanguagePanel extends StatelessWidget {
  const VirgilWorkbenchDictionaryLanguagePanel({
    super.key,
    required this.selectedLangs,
    required this.busy,
    required this.onChanged,
  });

  final Set<String> selectedLangs;
  final bool busy;
  final void Function(String lang, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dictionary language',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: selectedLangs.contains('ru'),
              onChanged:
                  busy ? null : (value) => onChanged('ru', value ?? false),
              title: const Text('Russian words'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: selectedLangs.contains('uk'),
              onChanged:
                  busy ? null : (value) => onChanged('uk', value ?? false),
              title: const Text('Ukrainian words'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class VirgilWorkbenchVoicePanel extends StatelessWidget {
  const VirgilWorkbenchVoicePanel({
    super.key,
    required this.voices,
    required this.selectedVoiceIds,
    required this.busy,
    required this.onChanged,
  });

  final List<TtsProfile> voices;
  final Set<String> selectedVoiceIds;
  final bool busy;
  final void Function(String voiceId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final items = voices.isEmpty
        ? const [
            TtsProfile(
              id: 'kokoro_af_heart',
              engineId: 'kokoro',
              voiceId: 'af_heart',
              displayName: 'Heart',
              lang: 'en',
            ),
          ]
        : voices;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kokoro voices',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final voice in items)
              CheckboxListTile(
                value: selectedVoiceIds.contains(voice.voiceId),
                onChanged: busy
                    ? null
                    : (value) => onChanged(voice.voiceId, value ?? false),
                title: Text(voice.displayName),
                subtitle: Text(voice.voiceId),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }
}
