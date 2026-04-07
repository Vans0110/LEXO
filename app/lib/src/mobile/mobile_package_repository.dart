import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'mobile_package_models.dart';

class MobileBookPackageRepository {
  static const _libraryDirName = 'mobile_library';

  Future<Directory> _libraryDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/$_libraryDirName');
    await dir.create(recursive: true);
    return dir;
  }

  Future<LibraryPayload> listBooks() async {
    final packages = await listPackages();
    packages.sort((a, b) {
      final left = a.meta.lastOpenedAt ?? a.meta.exportedAt ?? '';
      final right = b.meta.lastOpenedAt ?? b.meta.exportedAt ?? '';
      return right.compareTo(left);
    });
    final activeBookId = packages.isEmpty ? null : packages.first.meta.localBookId;
    return LibraryPayload(
      activeBookId: activeBookId,
      items: [
        for (final package in packages)
          package.meta.toLibraryItem(isActive: package.meta.localBookId == activeBookId),
      ],
    );
  }

  Future<List<MobileBookPackage>> listPackages() async {
    final dir = await _libraryDir();
    final packages = <MobileBookPackage>[];
    for (final entity in dir.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final packageFile = File('${entity.path}/package.json');
      if (!packageFile.existsSync()) {
        continue;
      }
      final raw = jsonDecode(packageFile.readAsStringSync()) as Map<String, dynamic>;
      packages.add(MobileBookPackage(raw));
    }
    return packages;
  }

  Future<MobileBookPackage> readPackage(String localBookId) async {
    final packageFile = await _packageFile(localBookId);
    if (!packageFile.existsSync()) {
      throw Exception('Local book package not found: $localBookId');
    }
    final raw = jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
    return MobileBookPackage(raw);
  }

  Future<void> savePackage(Map<String, dynamic> packageJson) async {
    final meta = packageJson['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final localBookId = meta['local_book_id'] as String? ?? meta['desktop_book_id'] as String? ?? '';
    if (localBookId.isEmpty) {
      throw Exception('Package does not contain local_book_id');
    }
    final bookDir = await _bookDir(localBookId);
    await bookDir.create(recursive: true);
    final packageFile = File('${bookDir.path}/package.json');
    await packageFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(packageJson),
      encoding: utf8,
    );
  }

  Future<MobileBookPackage?> findByDesktopBookId(String desktopBookId) async {
    final packages = await listPackages();
    for (final package in packages) {
      if (package.meta.desktopBookId == desktopBookId) {
        return package;
      }
    }
    return null;
  }

  Future<MobileBookPackage?> findByContentHash(String contentHash) async {
    if (contentHash.trim().isEmpty) {
      return null;
    }
    final packages = await listPackages();
    for (final package in packages) {
      if (package.meta.contentHash == contentHash) {
        return package;
      }
    }
    return null;
  }

  Future<void> deletePackage(String localBookId) async {
    final bookDir = await _bookDir(localBookId);
    if (bookDir.existsSync()) {
      await bookDir.delete(recursive: true);
    }
  }

  Future<void> markBookOpened(String localBookId) async {
    final package = await readPackage(localBookId);
    final meta = package.rawJson['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    meta['last_opened_at'] = DateTime.now().toUtc().toIso8601String();
    package.rawJson['meta'] = meta;
    await savePackage(package.rawJson);
  }

  Future<void> saveReaderPosition(String localBookId, int paragraphIndex) async {
    final package = await readPackage(localBookId);
    final meta = package.rawJson['meta'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final readerPayload =
        package.rawJson['reader_payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
    meta['current_paragraph_index'] = paragraphIndex;
    readerPayload['current_paragraph_index'] = paragraphIndex;
    package.rawJson['meta'] = meta;
    package.rawJson['reader_payload'] = readerPayload;
    await savePackage(package.rawJson);
  }

  Future<String> ensureAudioFile({
    required String localBookId,
    required String jobId,
    required int segmentIndex,
    required List<int> bytes,
  }) async {
    final audioFile = await _audioFile(localBookId, jobId, segmentIndex);
    if (!audioFile.parent.existsSync()) {
      await audioFile.parent.create(recursive: true);
    }
    if (!audioFile.existsSync()) {
      await audioFile.writeAsBytes(bytes, flush: true);
    }
    return audioFile.path;
  }

  Future<String?> getCachedAudioPath({
    required String localBookId,
    required String jobId,
    required int segmentIndex,
  }) async {
    final audioFile = await _audioFile(localBookId, jobId, segmentIndex);
    if (!audioFile.existsSync()) {
      return null;
    }
    return audioFile.path;
  }

  Future<void> deleteJobAudio({
    required String localBookId,
    required String jobId,
  }) async {
    final bookDir = await _bookDir(localBookId);
    final audioDir = Directory('${bookDir.path}/audio/$jobId');
    if (audioDir.existsSync()) {
      await audioDir.delete(recursive: true);
    }
  }

  Future<Directory> _bookDir(String localBookId) async {
    final dir = await _libraryDir();
    return Directory('${dir.path}/$localBookId');
  }

  Future<File> _packageFile(String localBookId) async {
    final bookDir = await _bookDir(localBookId);
    return File('${bookDir.path}/package.json');
  }

  Future<File> _audioFile(String localBookId, String jobId, int segmentIndex) async {
    final bookDir = await _bookDir(localBookId);
    return File('${bookDir.path}/audio/$jobId/$segmentIndex.wav');
  }
}
