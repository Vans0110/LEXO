import '../models.dart';

bool activeBookPackageChanged({
  required LibraryPayload? previous,
  required LibraryPayload next,
  required String? activeBookId,
}) {
  final bookId = activeBookId?.trim() ?? '';
  if (bookId.isEmpty || previous == null) {
    return false;
  }

  LibraryBookItem? previousBook;
  LibraryBookItem? nextBook;
  for (final item in previous.items) {
    if (item.id == bookId) {
      previousBook = item;
      break;
    }
  }
  for (final item in next.items) {
    if (item.id == bookId) {
      nextBook = item;
      break;
    }
  }
  if (previousBook == null || nextBook == null) {
    return false;
  }

  return (previousBook.contentHash ?? '').trim() !=
      (nextBook.contentHash ?? '').trim();
}
