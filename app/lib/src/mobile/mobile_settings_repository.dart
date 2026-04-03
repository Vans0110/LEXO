import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class MobileAppSettings {
  const MobileAppSettings({
    this.hostUrl,
  });

  final String? hostUrl;

  MobileAppSettings copyWith({
    String? hostUrl,
    bool clearHostUrl = false,
  }) {
    return MobileAppSettings(
      hostUrl: clearHostUrl ? null : (hostUrl ?? this.hostUrl),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host_url': hostUrl,
    };
  }

  factory MobileAppSettings.fromJson(Map<String, dynamic> json) {
    return MobileAppSettings(
      hostUrl: json['host_url'] as String?,
    );
  }
}

class MobileSettingsRepository {
  Future<MobileAppSettings> load() async {
    final file = await _settingsFile();
    if (!file.existsSync()) {
      return const MobileAppSettings();
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return MobileAppSettings.fromJson(raw);
  }

  Future<MobileAppSettings> save(MobileAppSettings settings) async {
    final file = await _settingsFile();
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      encoding: utf8,
    );
    return settings;
  }

  Future<File> _settingsFile() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/mobile_settings.json');
  }
}
