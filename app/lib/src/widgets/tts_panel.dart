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
    required this.onPause,
    required this.onResume,
    required this.onPrev,
    required this.onNext,
    required this.onStartJob,
    required this.onStopJob,
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
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final void Function(String jobId) onStartJob;
  final void Function(String jobId) onStopJob;

  @override
  Widget build(BuildContext context) {
    final activeJob = state?.activeJob;
    final jobs = state?.jobs ?? const <TtsJobItem>[];
    final selectedLevelId = selectedLevelIds.isEmpty ? null : selectedLevelIds.first;
    TtsLevel? selectedLevel;
    TtsJobItem? selectedJob;
    if (selectedLevelId != null) {
      for (final level in levels) {
        if (level.id == selectedLevelId) {
          selectedLevel = level;
          break;
        }
      }
      for (final job in jobs) {
        if (job.levelId == selectedLevelId &&
            (selectedVoiceId == null || job.voiceId == selectedVoiceId)) {
          selectedJob = job;
          break;
        }
      }
    }
    final selectedJobForStart =
        selectedJob != null && !busy && selectedJob.isReady
            ? () => onStartJob(selectedJob!.jobId)
            : null;
    final selectedJobForStop =
        selectedJob != null && !busy ? () => onStopJob(selectedJob!.jobId) : null;

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
                        child: Text('${level.name} ${level.targetWpm}'),
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
                  '${selectedLevel.name} • ${selectedLevel.targetWpm} WPM',
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
              FilledButton.tonal(
                onPressed: selectedJobForStart,
                child: const Text('Start'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: selectedJobForStop,
                child: const Text('Stop'),
              ),
              const SizedBox(height: 12),
              if (selectedJob == null)
                const Text('Для этой скорости генерации ещё нет')
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
              if (activeJob != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Active: ${activeJob.levelName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: activeJob.playbackProgress.clamp(0.0, 1.0),
                ),
                const SizedBox(height: 6),
                Text('${activeJob.currentSegmentNumber}/${activeJob.totalSegments}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: busy || !(state?.hasActiveJob ?? false) ? null : onPause,
                      child: const Text('Pause'),
                    ),
                    OutlinedButton(
                      onPressed: busy || !(state?.hasActiveJob ?? false) ? null : onResume,
                      child: const Text('Resume'),
                    ),
                    OutlinedButton(
                      onPressed: busy || !(state?.hasActiveJob ?? false) ? null : onPrev,
                      child: const Text('Prev'),
                    ),
                    OutlinedButton(
                      onPressed: busy || !(state?.hasActiveJob ?? false) ? null : onNext,
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
