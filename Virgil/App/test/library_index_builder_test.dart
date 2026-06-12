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

  test('cleanup removes ZIP and cover missing from Workbench sources',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('virgil_cleanup_test_');
    final libraryDir = Directory('${tempDir.path}/library');
    final booksDir = Directory('${tempDir.path}/books');
    try {
      final chapterDir = Directory(
        '${booksDir.path}/A1/Chapter 1 - Introduction',
      );
      await chapterDir.create(recursive: true);
      await File('${chapterDir.path}/Current Book.txt').writeAsString('Text');

      final currentZip = await _writeBookZip(
        libraryDir,
        fileName: 'book_current_current_book.zip',
        bookId: 'book_current',
        title: 'Current Book',
      );
      final staleZip = await _writeBookZip(
        libraryDir,
        fileName: 'book_stale_stale_book.zip',
        bookId: 'book_stale',
        title: 'Stale Book',
      );
      final coversDir = Directory('${libraryDir.path}/a1/chapters/covers');
      await coversDir.create(recursive: true);
      final currentCover =
          File('${coversDir.path}/book_current_current_book.png');
      final staleCover = File('${coversDir.path}/book_stale_stale_book.png');
      await currentCover.writeAsBytes([1]);
      await staleCover.writeAsBytes([2]);

      final builder = VirgilLibraryIndexBuilder(libraryDir: libraryDir);
      final removed = await builder.removeBooksMissingFrom(booksDir);
      final indexFile = await builder.rebuild();
      final payload =
          jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
      final books = payload['books'] as List<dynamic>;

      expect(removed, 1);
      expect(currentZip.existsSync(), isTrue);
      expect(currentCover.existsSync(), isTrue);
      expect(staleZip.existsSync(), isFalse);
      expect(staleCover.existsSync(), isFalse);
      expect(books, hasLength(1));
      expect((books.single as Map<String, dynamic>)['book_id'], 'book_current');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

Future<File> _writeBookZip(
  Directory libraryDir, {
  required String fileName,
  required String bookId,
  required String title,
}) async {
  final zipFile = File('${libraryDir.path}/a1/chapters/books_zip/$fileName');
  await zipFile.parent.create(recursive: true);
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'book_id': bookId,
          'title': title,
          'level': 'a1',
          'section': 'chapters',
          'chapter_id': 'chapter_01_introduction',
          'chapter_title': 'Chapter 1 \u2014 Introduction',
          'cover': 'cover.png',
          'source_lang': 'en',
          'target_lang': 'ru',
        }),
      ),
    )
    ..addFile(ArchiveFile('cover.png', 1, [1]));
  await zipFile.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return zipFile;
}
