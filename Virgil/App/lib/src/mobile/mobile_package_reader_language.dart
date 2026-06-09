import 'mobile_settings_repository.dart';

Future<Map<String, dynamic>> selectReaderPayloadForSettings(
  Map<String, dynamic> packageJson,
) async {
  final readerPayloads =
      packageJson['reader_payloads'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
  final settings = await MobileSettingsRepository().load();
  final preferred = settings.preferredTargetLang;
  final selected = readerPayloads[preferred];
  if (selected is Map<String, dynamic>) {
    packageJson['reader_payload'] = selected;
    final meta =
        packageJson['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    meta['target_lang'] = selected['target_lang'] ?? preferred;
    packageJson['meta'] = meta;
  }
  final dictionaryManifests =
      packageJson['dictionary_manifests'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
  final selectedDictionary = dictionaryManifests[preferred];
  if (selectedDictionary is Map<String, dynamic>) {
    packageJson['dictionary_manifest'] = selectedDictionary;
  }
  return packageJson;
}
