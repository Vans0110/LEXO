import 'virgil_workbench_book_status.dart';
import 'virgil_workbench_library_filters.dart';

class VirgilWorkbenchBookSelection {
  const VirgilWorkbenchBookSelection({
    required this.level,
    required this.section,
    required this.chapterId,
    required this.title,
    required this.sourcePath,
    required this.sourceText,
    required this.coverPath,
    required this.exportedLanguages,
    required this.hasAudio,
  });

  final String level;
  final String section;
  final String chapterId;
  final String title;
  final String sourcePath;
  final String sourceText;
  final String coverPath;
  final Set<String> exportedLanguages;
  final bool hasAudio;

  bool hasLanguages(Iterable<String> languages) =>
      languages.every(exportedLanguages.contains);
}

class VirgilWorkbenchBookItem {
  const VirgilWorkbenchBookItem({
    required this.level,
    required this.section,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterNumber,
    required this.title,
    required this.sourcePath,
    required this.coverPath,
    required this.status,
  });

  final String level;
  final String section;
  final String chapterId;
  final String chapterTitle;
  final int chapterNumber;
  final String title;
  final String sourcePath;
  final String coverPath;
  final VirgilWorkbenchBookStatus? status;
}

String virgilWorkbenchNormalizeLevel(String value) {
  final level = value.trim().toLowerCase();
  return const {'a1', 'a2', 'b1', 'b2', 'c1'}.contains(level) ? level : 'a1';
}

int virgilWorkbenchChapterNumber(String folderName) {
  final match = RegExp(
    r'(?:chapter|\u0433\u043b\u0430\u0432\u0430)\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(folderName);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

String virgilWorkbenchChapterTopic(String folderName) {
  return folderName
      .replaceFirst(
        RegExp(
          r'^(?:chapter|\u0433\u043b\u0430\u0432\u0430)\s*\d+\s*[-\u2014]?\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

String virgilWorkbenchChapterId(String folderName) {
  final number = virgilWorkbenchChapterNumber(folderName);
  if (number == 0) {
    return '';
  }
  final topic = virgilWorkbenchChapterTopic(folderName)
      .toLowerCase()
      .replaceAll('&', ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final prefix = number.toString().padLeft(2, '0');
  return topic.isEmpty ? 'chapter_$prefix' : 'chapter_${prefix}_$topic';
}

String virgilWorkbenchChapterTitle(String folderName) {
  final number = virgilWorkbenchChapterNumber(folderName);
  final topic = virgilWorkbenchChapterTopic(folderName);
  if (number == 0) {
    return folderName;
  }
  return topic.isEmpty ? 'Chapter $number' : 'Chapter $number \u2014 $topic';
}

List<VirgilWorkbenchBookItem> virgilWorkbenchVisibleBooks({
  required List<VirgilWorkbenchBookItem> items,
  required String level,
  required String chapter,
  required VirgilWorkbenchReadyFilter readyFilter,
}) {
  final result = items.where((item) {
    if (level.isNotEmpty && item.level != level) {
      return false;
    }
    if (chapter.isNotEmpty && item.chapterTitle != chapter) {
      return false;
    }
    final ready = item.status?.isFullyBuilt ?? false;
    return switch (readyFilter) {
      VirgilWorkbenchReadyFilter.all => true,
      VirgilWorkbenchReadyFilter.ready => ready,
      VirgilWorkbenchReadyFilter.incomplete => !ready,
    };
  }).toList()
    ..sort((left, right) {
      final levelOrder = left.level.compareTo(right.level);
      if (levelOrder != 0) {
        return levelOrder;
      }
      final chapterOrder = left.chapterNumber.compareTo(right.chapterNumber);
      return chapterOrder != 0
          ? chapterOrder
          : left.title.compareTo(right.title);
    });
  return result;
}

List<String> virgilWorkbenchLevels(List<VirgilWorkbenchBookItem> items) {
  return items.map((item) => item.level).toSet().toList()..sort();
}

List<String> virgilWorkbenchChapters(
  List<VirgilWorkbenchBookItem> items,
  String level,
) {
  final chapterItems =
      items.where((item) => level.isEmpty || item.level == level).toList()
        ..sort(
          (left, right) => left.chapterNumber.compareTo(right.chapterNumber),
        );
  return chapterItems.map((item) => item.chapterTitle).toSet().toList();
}

String virgilWorkbenchBasenameWithoutExtension(String path) {
  final name = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

List<String> virgilWorkbenchRelativeParts(String rootPath, String filePath) {
  final root = rootPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final file = filePath.replaceAll('\\', '/');
  final relative =
      file.startsWith('$root/') ? file.substring(root.length + 1) : file;
  return relative.split('/').where((part) => part.isNotEmpty).toList();
}
