import 'package:flutter/material.dart';

class MobileSettingsScreen extends StatelessWidget {
  const MobileSettingsScreen({
    super.key,
    this.title = 'Settings',
    this.currentBookTitle,
    this.busy = false,
    this.errorText,
    this.hostUrl,
    this.lastSyncAt,
    this.pendingChangesCount = 0,
    this.debugText,
    this.onEditHostUrl,
    this.onSync,
    this.onCopyDebugLog,
  });

  final String title;
  final String? currentBookTitle;
  final bool busy;
  final String? errorText;
  final String? hostUrl;
  final String? lastSyncAt;
  final int pendingChangesCount;
  final String? debugText;
  final VoidCallback? onEditHostUrl;
  final VoidCallback? onSync;
  final VoidCallback? onCopyDebugLog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
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
                        Icon(Icons.sync_outlined),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sync',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Последняя синхронизация: '
                      '${(lastSyncAt == null || lastSyncAt!.trim().isEmpty) ? 'ещё не было' : lastSyncAt!}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Несинхронизированные изменения: '
                      '${pendingChangesCount > 0 ? 'да ($pendingChangesCount)' : 'нет'}',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : onSync,
                      icon: const Icon(Icons.sync_outlined),
                      label: Text(busy ? 'Синхронизация...' : 'Синхронизировать'),
                    ),
                  ],
                ),
              ),
            ),
            if (debugText != null && debugText!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bug_report_outlined),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Sync Debug',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: onCopyDebugLog,
                            icon: const Icon(Icons.copy_all_outlined),
                            label: const Text('Копировать'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        debugText!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (errorText != null && errorText!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
