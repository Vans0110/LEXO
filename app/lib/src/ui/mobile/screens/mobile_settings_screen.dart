import 'package:flutter/material.dart';

import '../../../models.dart';
import '../../../widgets/tts_panel.dart';

class MobileSettingsScreen extends StatelessWidget {
  const MobileSettingsScreen({
    super.key,
    this.title = 'Settings',
    this.currentBookTitle,
    this.busy = false,
    this.errorText,
    this.onImportBook,
    this.onImportFromDesktop,
    this.hostUrl,
    this.onEditHostUrl,
    this.onUpdateCurrentBook,
    this.profiles = const [],
    this.levels = const [],
    this.selectedVoiceId,
    this.selectedLevelIds = const {},
    this.state,
    this.onVoiceChanged,
    this.onLevelToggle,
    this.onGenerate,
    this.onPause,
    this.onResume,
    this.onPrev,
    this.onNext,
    this.onStartJob,
    this.onStopJob,
  });

  final String title;
  final String? currentBookTitle;
  final bool busy;
  final String? errorText;
  final VoidCallback? onImportBook;
  final VoidCallback? onImportFromDesktop;
  final String? hostUrl;
  final VoidCallback? onEditHostUrl;
  final VoidCallback? onUpdateCurrentBook;
  final List<TtsProfile> profiles;
  final List<TtsLevel> levels;
  final String? selectedVoiceId;
  final Set<int> selectedLevelIds;
  final TtsState? state;
  final ValueChanged<String?>? onVoiceChanged;
  final void Function(int levelId, bool selected)? onLevelToggle;
  final VoidCallback? onGenerate;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(String jobId)? onStartJob;
  final void Function(String jobId)? onStopJob;

  @override
  Widget build(BuildContext context) {
    final hasTtsControls =
        profiles.isNotEmpty &&
        levels.isNotEmpty &&
        onVoiceChanged != null &&
        onLevelToggle != null &&
        onGenerate != null &&
        onPause != null &&
        onResume != null &&
        onPrev != null &&
        onNext != null &&
        onStartJob != null &&
        onStopJob != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (currentBookTitle != null) ...[
              Text(
                currentBookTitle!,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Текущая книга для чтения и озвучки'),
              const SizedBox(height: 20),
            ],
            if (onImportBook != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.upload_file_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Загрузка',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: busy ? null : onImportBook,
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Загрузить TXT-книгу'),
                      ),
                      if (onImportFromDesktop != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: busy ? null : onImportFromDesktop,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Импорт из Desktop'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.dns_outlined),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Host',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(hostUrl == null || hostUrl!.trim().isEmpty ? 'Default host' : hostUrl!),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onEditHostUrl,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Настроить Host URL'),
                    ),
                    if (onUpdateCurrentBook != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onUpdateCurrentBook,
                        icon: const Icon(Icons.sync_outlined),
                        label: const Text('Обновить текущую книгу'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (errorText != null && errorText!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.graphic_eq),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Озвучка',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!hasTtsControls)
                      const Text('Откройте книгу, чтобы управлять озвучкой.')
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TtsPanel(
                          profiles: profiles,
                          levels: levels,
                          selectedVoiceId: selectedVoiceId,
                          selectedLevelIds: selectedLevelIds,
                          state: state,
                          busy: busy,
                          onVoiceChanged: onVoiceChanged!,
                          onLevelToggle: onLevelToggle!,
                          onGenerate: onGenerate!,
                          onPause: onPause!,
                          onResume: onResume!,
                          onPrev: onPrev!,
                          onNext: onNext!,
                          onStartJob: onStartJob!,
                          onStopJob: onStopJob!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
