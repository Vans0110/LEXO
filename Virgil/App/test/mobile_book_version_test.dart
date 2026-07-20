import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/mobile/mobile_book_version.dart';
import 'package:virgil/src/models.dart';

void main() {
  LibraryBookItem book(String id, String hash) => LibraryBookItem(
        id: id,
        title: id,
        sourceName: '',
        sourceLang: 'en',
        targetLang: 'ru',
        status: 'ready',
        modelName: '',
        currentParagraphIndex: 0,
        isActive: true,
        contentHash: hash,
      );

  LibraryPayload library(LibraryBookItem item) => LibraryPayload(
        activeBookId: item.id,
        items: [item],
      );

  test('active reader reloads when installed package hash changes', () {
    expect(
      activeBookPackageChanged(
        previous: library(book('book-1', 'old-hash')),
        next: library(book('book-1', 'new-hash')),
        activeBookId: 'book-1',
      ),
      isTrue,
    );
  });

  test('active reader stays mounted when package hash is unchanged', () {
    expect(
      activeBookPackageChanged(
        previous: library(book('book-1', 'same-hash')),
        next: library(book('book-1', 'same-hash')),
        activeBookId: 'book-1',
      ),
      isFalse,
    );
  });

  test('another updated book does not reload the active reader', () {
    expect(
      activeBookPackageChanged(
        previous: library(book('book-2', 'old-hash')),
        next: library(book('book-2', 'new-hash')),
        activeBookId: 'book-1',
      ),
      isFalse,
    );
  });
}
