import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

class NoveLibraryIndexBuilder {
  const NoveLibraryIndexBuilder({
    required this.libraryDir,
    this.log,
  });

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  final Directory libraryDir;
  final void Function(String message)? log;

  Future<File> rebuild() async {
    await libraryDir.create(recursive: true);
    final books = <Map<String, dynamic>>[];
    final zipFiles = libraryDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.zip'))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final zipFile in zipFiles) {
      final entry = await _entryForZip(zipFile);
      if (entry != null) {
        books.add(entry);
      }
    }
    final payload = {
      'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'base_path': 'nove/library',
      'books': books,
    };
    final indexFile = File('${libraryDir.path}/library_index.json');
    await indexFile.writeAsString(
      _jsonEncoder.convert(payload),
      encoding: utf8,
      flush: true,
    );
    log?.call('Library index rebuilt: ${books.length} books');
    return indexFile;
  }

  Future<Map<String, dynamic>?> _entryForZip(File zipFile) async {
    try {
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      final manifestFile = archive.files
          .where((file) => file.isFile && file.name == 'manifest.json')
          .firstOrNull;
      if (manifestFile == null) {
        return null;
      }
      final manifest = jsonDecode(
        utf8.decode(manifestFile.content as List<int>),
      ) as Map<String, dynamic>;
      final relativeZipPath = _relativePath(zipFile);
      final coverPath = await _extractCover(
        archive: archive,
        manifest: manifest,
        relativeZipPath: relativeZipPath,
      );
      return {
        'book_id': (manifest['book_id'] ?? '').toString(),
        'title':
            (manifest['title'] ?? zipFile.uri.pathSegments.last).toString(),
        'level':
            (manifest['level'] ?? _pathPart(relativeZipPath, 0)).toString(),
        'section':
            (manifest['section'] ?? _pathPart(relativeZipPath, 1)).toString(),
        'chapter_id': (manifest['chapter_id'] ?? '').toString(),
        'chapter_title': (manifest['chapter_title'] ?? '').toString(),
        'source_lang': (manifest['source_lang'] ?? 'en').toString(),
        'target_lang': (manifest['target_lang'] ?? 'ru').toString(),
        'available_target_langs':
            manifest['available_target_langs'] as List<dynamic>? ?? const [],
        'zip_path': relativeZipPath,
        if (coverPath.isNotEmpty) 'cover_path': coverPath,
        'size_bytes': await zipFile.length(),
        'updated_at': (manifest['generated_at'] ?? '').toString(),
      };
    } catch (error) {
      log?.call('Skip index entry for ${zipFile.path}: $error');
      return null;
    }
  }

  Future<String> _extractCover({
    required Archive archive,
    required Map<String, dynamic> manifest,
    required String relativeZipPath,
  }) async {
    final coverName = (manifest['cover'] ?? '').toString();
    if (coverName.trim().isEmpty) {
      return '';
    }
    final coverFile = archive.files
        .where((file) => file.isFile && file.name == coverName)
        .firstOrNull;
    if (coverFile == null) {
      return '';
    }
    final zipParts = relativeZipPath.split('/');
    if (zipParts.length < 3) {
      return '';
    }
    final extension =
        _extension(coverName).isEmpty ? '.png' : _extension(coverName);
    final zipName = zipParts.last;
    final baseName = zipName.toLowerCase().endsWith('.zip')
        ? zipName.substring(0, zipName.length - 4)
        : zipName;
    final relativeCoverPath =
        '${zipParts[0]}/${zipParts[1]}/covers/$baseName$extension';
    final target = File('${libraryDir.path}/$relativeCoverPath');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(coverFile.content as List<int>, flush: true);
    return relativeCoverPath;
  }

  String _relativePath(File file) {
    final root = libraryDir.absolute.path.replaceAll('\\', '/');
    final path = file.absolute.path.replaceAll('\\', '/');
    return path.substring(root.length + 1);
  }

  String _pathPart(String path, int index) {
    final parts = path.split('/');
    return parts.length > index ? parts[index] : '';
  }

  String _extension(String path) {
    final fileName = path.split('/').last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot).toLowerCase();
  }
}
