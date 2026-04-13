import 'package:flutter/material.dart';

import '../models.dart';

class TtsPanel extends StatelessWidget {
  const TtsPanel({
    super.key,
    required this.profiles,
    required this.levels,
    required this.selectedVoiceId,
    required this.selectedLevelIds,
    required this.state,
    required this.busy,
    required this.onVoiceChanged,
    required this.onLevelToggle,
    required this.onGenerate,
    required this.onOverwriteGenerate,
  });

  final List<TtsProfile> profiles;
  final List<TtsLevel> levels;
  final String? selectedVoiceId;
  final Set<int> selectedLevelIds;
  final TtsState? state;
  final bool busy;
  final ValueChanged<String?> onVoiceChanged;
  final void Function(int levelId, bool selected) onLevelToggle;
  final VoidCallback onGenerate;
  final VoidCallback onOverwriteGenerate;

  @override
  Widget build(BuildContext context) {
    final jobs = state?.jobs ?? const <TtsJobItem>[];
    final selectedLevelId = selectedLevelIds.isEmpty ? null : selectedLevelIds.first;
    TtsLevel? selectedLevel;
    if (selectedLevelId != null) {
      for (final level in levels) {
        if (level.id == selectedLevelId) {
          selectedLevel = level;
          break;
        }
      }
    }
    TtsJobItem? selectedJob;
    final requiredAudioVariant = selectedLevel?.audioVariant ?? 'base';
    for (final job in jobs) {
      if ((selectedVoiceId == null || job.voiceId == selectedVoiceId) &&
          job.audioVariant == requiredAudioVariant) {
        selectedJob = job;
        break;
      }
    }
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.speed_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Speed',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: selectedLevelId,
                items: levels
                    .map(
                      (level) => DropdownMenuItem<int>(
                        value: level.id,
                        child: Text('${level.name} ${(level.playbackSpeed).toStringAsFixed(2)}x'),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) {
                          onLevelToggle(value, true);
                        }
                      },
                decoration: const InputDecoration(
                  labelText: 'Speed',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedVoiceId,
                items: profiles
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.voiceId,
                        child: Text(item.displayName),
                      ),
                    )
                    .toList(),
                onChanged: busy ? null : onVoiceChanged,
                decoration: const InputDecoration(
                  labelText: 'Voice',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (selectedLevel != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${selectedLevel.name} • ${selectedLevel.playbackSpeed.toStringAsFixed(2)}x',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || selectedVoiceId == null || selectedLevelId == null
                    ? null
                    : onGenerate,
                child: const Text('Generate'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy || selectedJob == null ? null : onOverwriteGenerate,
                child: const Text('Overwrite'),
              ),
              const SizedBox(height: 12),
              if (selectedJob == null)
                const Text('Для этого голоса генерации ещё нет')
              else ...[
                Text(
                  selectedJob.statusLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: selectedJob.generationProgress.clamp(0.0, 1.0),
                ),
                const SizedBox(height: 6),
                Text('${selectedJob.readySegments}/${selectedJob.totalSegments}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
