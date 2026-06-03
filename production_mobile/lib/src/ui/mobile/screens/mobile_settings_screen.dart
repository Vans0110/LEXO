import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../mobile/mobile_settings_repository.dart';
import '../../../mobile/nove_download_options.dart';

const _feedbackEmail = 'ivan.kurtinov@gmail.com';
const _appVersion = '0.1.0+1';

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
                    child: Text(option.title),
                  ),
              ],
              onChanged: (value) {
                if (value != null && value != settings.preferredVoiceId) {
                  onPreferredVoiceChanged(value);
                }
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Feedback',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Жалобы и предложения'),
              subtitle: const Text('Сообщение, email для ответа и техинфо'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _FeedbackDialog(settings: settings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.settings});

  final MobileAppSettings settings;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    if (!_formKey.currentState!.validate() || _busy) {
      return;
    }
    setState(() => _busy = true);
    final body = _buildFeedbackBody();
    final uri = Uri(
      scheme: 'mailto',
      path: _feedbackEmail,
      queryParameters: {
        'subject': 'Nove feedback',
        'body': body,
      },
    );
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) {
        return;
      }
      if (launched) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Откройте почту и отправьте письмо')),
        );
        return;
      }
      await _copyFeedback(body);
    } catch (_) {
      if (mounted) {
        await _copyFeedback(body);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copyFeedback(String body) async {
    await Clipboard.setData(
      ClipboardData(
          text: 'To: $_feedbackEmail\nSubject: Nove feedback\n\n$body'),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Письмо скопировано в буфер')),
    );
  }

  String _buildFeedbackBody() {
    final replyEmail = _emailController.text.trim();
    final message = _messageController.text.trim();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    return [
      'Message:',
      message,
      '',
      'Reply email: ${replyEmail.isEmpty ? 'not provided' : replyEmail}',
      '',
      'Technical info:',
      'feedback_created_at_utc: $createdAt',
      'install_id: ${widget.settings.deviceId?.trim().isNotEmpty == true ? widget.settings.deviceId : 'not set'}',
      'app: Nove',
      'app_version: $_appVersion',
      'platform: ${Platform.operatingSystem}',
      'platform_version: ${Platform.operatingSystemVersion}',
      'locale: $locale',
      'preferred_target_lang: ${widget.settings.preferredTargetLang}',
      'preferred_voice_id: ${widget.settings.preferredVoiceId}',
    ].join('\n');
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return null;
    }
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    return valid ? null : 'Введите корректный email';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Жалобы и предложения'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email для ответа',
                  helperText: 'Необязательно',
                  border: OutlineInputBorder(),
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageController,
                minLines: 5,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Сообщение',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Напишите сообщение';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Text(
                'К письму будет добавлена техническая информация: install ID, версия, платформа, язык и голос.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _sendFeedback,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mail_outline),
          label: const Text('Отправить'),
        ),
      ],
    );
  }
}
