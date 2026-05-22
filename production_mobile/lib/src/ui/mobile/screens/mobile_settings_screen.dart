import 'package:flutter/material.dart';

import '../../../mobile/mobile_settings_repository.dart';
import '../../../mobile/nove_download_options.dart';

class MobileSettingsScreen extends StatelessWidget {
  const MobileSettingsScreen({
    super.key,
    required this.settings,
    required this.onPreferredTargetLangChanged,
    required this.onPreferredVoiceChanged,
  });

  final MobileAppSettings settings;
  final ValueChanged<String> onPreferredTargetLangChanged;
  final ValueChanged<String> onPreferredVoiceChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Book translation language',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: settings.preferredTargetLang,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: [
                DropdownMenuItem(value: 'ru', child: Text('Russian')),
                DropdownMenuItem(value: 'uk', child: Text('Ukrainian')),
              ],
              onChanged: (value) {
                if (value != null && value != settings.preferredTargetLang) {
                  onPreferredTargetLangChanged(value);
                }
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Reading voice',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: settings.preferredVoiceId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: [
                for (final option in noveVoiceOptions)
                  DropdownMenuItem(
                    value: option.voiceId,
                    child: Text('${option.title} (${option.subtitle})'),
                  ),
              ],
              onChanged: (value) {
                if (value != null && value != settings.preferredVoiceId) {
                  onPreferredVoiceChanged(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
