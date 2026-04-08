import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const String kFallbackMobileHostUrl = 'http://192.168.1.50:8765';
const String kDefaultMobileHostUrl = String.fromEnvironment(
  'LEXO_DEFAULT_MOBILE_HOST_URL',
  defaultValue: kFallbackMobileHostUrl,
);

class MobileAppSettings {
  const MobileAppSettings({
    this.hostUrl = kDefaultMobileHostUrl,
    this.deviceId,
    this.lastSyncAt,
  });

  final String? hostUrl;
  final String? deviceId;
  final String? lastSyncAt;

  MobileAppSettings copyWith({
    String? hostUrl,
    String? deviceId,
    String? lastSyncAt,
    bool clearHostUrl = false,
    bool clearLastSyncAt = false,
  }) {
    return MobileAppSettings(
      hostUrl: clearHostUrl ? null : (hostUrl ?? this.hostUrl),
      deviceId: deviceId ?? this.deviceId,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host_url': hostUrl,
      'device_id': deviceId,
      'last_sync_at': lastSyncAt,
    };
  }

  factory MobileAppSettings.fromJson(Map<String, dynamic> json) {
    return MobileAppSettings(
      hostUrl: (json['host_url'] as String?)?.trim().isEmpty ?? true
          ? kDefaultMobileHostUrl
          : json['host_url'] as String?,
      deviceId: json['device_id'] as String?,
      lastSyncAt: json['last_sync_at'] as String?,
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
