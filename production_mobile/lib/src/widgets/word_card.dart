import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';

class WordCard extends StatelessWidget {
  const WordCard({
    super.key,
    required this.api,
    required this.lookup,
  });

  final LexoApiClient api;
  final WordLookup lookup;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lookup.word,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Lemma: ${lookup.lemma}'),
            Text('Part of speech: ${lookup.partOfSpeech}'),
            const SizedBox(height: 12),
            Text('Main meaning: ${lookup.mainMeaning}'),
            if (lookup.otherMeanings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Other meanings: ${lookup.otherMeanings.join(', ')}'),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: () async {
                    developer.log(
                      'Requesting word audio for "${lookup.word}"',
                      name: 'LEXO_UI',
                    );
                    try {
                      final result = await api.requestWordAudio(lookup.word);
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Stub audio: ${result['audio_path']}'),
                        ),
                      );
                    } catch (error, stackTrace) {
                      developer.log(
                        'Word audio failed for "${lookup.word}": $error',
                        name: 'LEXO_UI',
                        error: error,
                        stackTrace: stackTrace,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Word audio error: $error')),
                      );
                    }
                  },
                  child: const Text('Play word'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    developer.log(
                      'Saving word "${lookup.word}"',
                      name: 'LEXO_UI',
                    );
                    await api.saveWord(lookup.word);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Word saved')),
                    );
                  },
                  child: const Text('Save word'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
