import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';

class MobileSyncDebugLogger {
  MobileSyncDebugLogger(this._api);

  final LexoApiClient _api;
  final List<String> _recentLines = <String>[];
  String? _lastRemoteError;

  String get debugReport {
    final parts = <String>[
      if (_lastRemoteError != null && _lastRemoteError!.trim().isNotEmpty) _lastRemoteError!,
      ..._recentLines,
    ];
    return parts.join('\n');
  }

  Future<void> log(String message) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final line = '[$timestamp] $message';
    _recentLines.add(line);
    if (_recentLines.length > 60) {
      _recentLines.removeRange(0, _recentLines.length - 60);
    }
    developer.log(line, name: 'LEXO_SYNC');
    try {
      await _api.postMobileDebugLog(
        tag: 'MOBILE_SYNC',
        message: line,
      );
      _lastRemoteError = null;
    } catch (error) {
      _lastRemoteError = 'REMOTE_LOG_ERROR: $error';
      developer.log(_lastRemoteError!, name: 'LEXO_SYNC');
    }
    final file = await _logFile();
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<String> logFilePath() async {
    final file = await _logFile();
    return file.path;
  }

  Future<void> startSession(String reason) async {
    await log('SESSION_START reason="$reason"');
  }

  Future<File> _logFile() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/mobile_sync_debug.log');
  }
}
