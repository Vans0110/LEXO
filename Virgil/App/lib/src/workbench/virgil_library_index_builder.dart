import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'virgil_workbench_library_models.dart';

class VirgilLibraryIndexBuilder {
  const VirgilLibraryIndexBuilder({
    required this.libraryDir,
    this.log,
  });

  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  final Directory libraryDir;
  final void Function(String message)? log;

  Future<int> removeBooksMissingFrom(Directory sourceBooksDir) async {
    await libraryDir.create(recursive: true);
    if (!sourceBooksDir.existsSync()) {
      throw StateError(
        'Workbench books directory does not exist: ${sourceBooksDir.path}',
      );
    }
    final sourceKeys = sourceBooksDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.txt'))
        .where((file) => !_isChapterImagesPath(file.path))
        .map((file) => _sourceBookKey(sourceBooksDir, file))
        .where((key) => key.isNotEmpty)
        .toSet();
    if (sourceKeys.isEmpty) {
      throw StateError(
        'No Workbench TXT books found; refusing to clean CloudLibrary.',
      );
    }

    var removed = 0;
    final zipFiles = libraryDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.zip'))
        .toList();
    for (final zipFile in zipFiles) {
      final manifest = await _manifestForZip(zipFile);
      if (manifest == null) {
        continue;
      }
      final key = _manifestBookKey(manifest);
      if (key.isEmpty || sourceKeys.contains(key)) {
        continue;
      }
      await _deleteExtractedCover(zipFile, manifest);
      await zipFile.delete();
      removed++;
      log?.call(
        'Remove stale local library book: '
        '${(manifest['title'] ?? zipFile.path).toString()}',
      );
    }
    log?.call('CloudLibrary cleanup: removed $removed stale books');
    return removed;
  }

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
      'base_path': 'virgil/library',
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
      final manifest = _manifestFromArchive(archive);
      if (manifest == null) {
        return null;
      }
      final relativeZipPath = _relativePath(zipFile);
      final contentHash = await _sha256File(zipFile);
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
        'content_hash': contentHash,
        if (coverPath.isNotEmpty) 'cover_path': coverPath,
        'size_bytes': await zipFile.length(),
        'updated_at': (manifest['generated_at'] ?? '').toString(),
      };
    } catch (error) {
      log?.call('Skip index entry for ${zipFile.path}: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _manifestForZip(File zipFile) async {
    try {
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      return _manifestFromArchive(archive);
    } catch (error) {
      log?.call('Skip stale check for ${zipFile.path}: $error');
      return null;
    }
  }

  Map<String, dynamic>? _manifestFromArchive(Archive archive) {
    final manifestFile = archive.files
        .where((file) => file.isFile && file.name == 'manifest.json')
        .firstOrNull;
    if (manifestFile == null) {
      return null;
    }
    return jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;
  }

  String _sourceBookKey(Directory sourceBooksDir, File file) {
    final parts = _relativeParts(sourceBooksDir.path, file.path);
    if (parts.length < 3) {
      return '';
    }
    final level = virgilWorkbenchNormalizeLevel(parts.first);
    final chapterId = virgilWorkbenchChapterId(parts[1]);
    final title = _basenameWithoutExtension(parts.last);
    return _bookKey(level, 'chapters', chapterId, title);
  }

  String _manifestBookKey(Map<String, dynamic> manifest) {
    return _bookKey(
      (manifest['level'] ?? '').toString(),
      (manifest['section'] ?? '').toString(),
      (manifest['chapter_id'] ?? '').toString(),
      (manifest['title'] ?? '').toString(),
    );
  }

  String _bookKey(
    String level,
    String section,
    String chapterId,
    String title,
  ) {
    final normalizedTitle = title
        .trim()
        .toLowerCase()
        .replaceAll('\u2019', "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    if (level.trim().isEmpty ||
        section.trim().isEmpty ||
        normalizedTitle.isEmpty) {
      return '';
    }
    return [
      level.trim().toLowerCase(),
      section.trim().toLowerCase(),
      chapterId.trim().toLowerCase(),
      normalizedTitle,
    ].join('|');
  }

  Future<void> _deleteExtractedCover(
    File zipFile,
    Map<String, dynamic> manifest,
  ) async {
    final coverName = (manifest['cover'] ?? '').toString();
    final extension =
        _extension(coverName).isEmpty ? '.png' : _extension(coverName);
    final relativeZipPath = _relativePath(zipFile);
    final parts = relativeZipPath.split('/');
    if (parts.length < 3) {
      return;
    }
    final zipName = parts.last;
    final baseName = zipName.toLowerCase().endsWith('.zip')
        ? zipName.substring(0, zipName.length - 4)
        : zipName;
    final cover = File(
      '${libraryDir.path}/${parts[0]}/${parts[1]}/covers/'
      '$baseName$extension',
    );
    if (cover.existsSync()) {
      await cover.delete();
    }
  }

  bool _isChapterImagesPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/chapter_images/');
  }

  List<String> _relativeParts(String rootPath, String filePath) {
    final root = rootPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final file = filePath.replaceAll('\\', '/');
    final relative =
        file.startsWith('$root/') ? file.substring(root.length + 1) : file;
    return relative.split('/').where((part) => part.isNotEmpty).toList();
  }

  String _basenameWithoutExtension(String path) {
    final dot = path.lastIndexOf('.');
    return dot <= 0 ? path : path.substring(0, dot);
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
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
