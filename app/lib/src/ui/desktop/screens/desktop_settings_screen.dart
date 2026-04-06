import 'package:flutter/material.dart';

class DesktopSettingsScreen extends StatelessWidget {
  const DesktopSettingsScreen({
    super.key,
    this.currentBookTitle,
    this.busy = false,
    this.errorText,
    this.onImportBook,
    this.onRefreshLibrary,
  });

  final String? currentBookTitle;
  final bool busy;
  final String? errorText;
  final VoidCallback? onImportBook;
  final VoidCallback? onRefreshLibrary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (currentBookTitle != null && currentBookTitle!.trim().isNotEmpty) ...[
                Text(
                  currentBookTitle!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                const Text('Текущая книга для чтения на desktop'),
                const SizedBox(height: 20),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Library Actions',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: busy ? null : onImportBook,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Load TXT'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onRefreshLibrary,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Library'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      Text(
                        'Desktop Shell',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Навигация desktop теперь приведена к mobile shell: Library, Reader и Settings доступны через нижние вкладки.',
                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
