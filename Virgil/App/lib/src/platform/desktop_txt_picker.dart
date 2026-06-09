import 'dart:io';

import 'package:flutter/services.dart';

class PickedTxtFile {
  const PickedTxtFile({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;

  String get titleCandidate {
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt') && name.length > 4) {
      return name.substring(0, name.length - 4);
    }
    return name;
  }
}

class DesktopTxtPicker {
  static const MethodChannel _channel =
      MethodChannel('lexo/windows_file_picker');

  static Future<PickedTxtFile?> pickTxtFile() async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
          'Windows TXT picker is unavailable on this platform.');
    }
    final raw = await _channel.invokeMethod<Object?>('pickTxtFile');
    if (raw == null) {
      return null;
    }
    final map = Map<Object?, Object?>.from(raw as Map);
    final path = map['path'] as String?;
    final name = map['name'] as String?;
    if (path == null ||
        name == null ||
        path.trim().isEmpty ||
        name.trim().isEmpty) {
      throw const FormatException('TXT picker returned an invalid payload.');
    }
    return PickedTxtFile(path: path, name: name);
  }
}
