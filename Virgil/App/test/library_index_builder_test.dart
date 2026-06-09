import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/mobile/virgil_bundled_book_repository.dart';
import 'package:virgil/src/workbench/virgil_library_index_builder.dart';

void main() {
  test('library index stores the ZIP SHA-256 as content_hash', () async {
    final libraryDir =
        await Directory.systemTemp.createTemp('virgil_index_test_');
    try {
      final zipFile =
          File('${libraryDir.path}/a1/chapters/books_zip/book_test.zip');
      await zipFile.parent.create(recursive: true);
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'book_id': 'book_test',
              'title': 'Test Book',
              'level': 'a1',
              'section': 'chapters',
              'source_lang': 'en',
              'target_lang': 'ru',
            }),
          ),
        );
      final zipBytes = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipBytes, flush: true);

      final indexFile = await VirgilLibraryIndexBuilder(
        libraryDir: libraryDir,
      ).rebuild();
      final payload =
          jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
      final books = payload['books'] as List<dynamic>;
      final book = books.single as Map<String, dynamic>;

      expect(book['book_id'], 'book_test');
      expect(book['content_hash'], sha256.convert(zipBytes).toString());
    } finally {
      await libraryDir.delete(recursive: true);
    }
  });

  test('downloaded ZIP must match the published SHA-256', () async {
    final tempDir = await Directory.systemTemp.createTemp('virgil_hash_test_');
    try {
      final zipFile = File('${tempDir.path}/book.zip');
      final bytes = utf8.encode('book archive bytes');
      await zipFile.writeAsBytes(bytes, flush: true);

      await verifyVirgilBookArchiveHash(
        zipFile,
        sha256.convert(bytes).toString(),
      );

      await expectLater(
        verifyVirgilBookArchiveHash(zipFile, List.filled(64, '0').join()),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
