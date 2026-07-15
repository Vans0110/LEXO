import 'dart:io';

import 'package:virgil/src/api/api_client.dart';
import 'package:virgil/src/workbench/virgil_workbench_builder.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    args = [
      Platform.environment['LEXO_BOOK_ID'] ?? '',
      Platform.environment['LEXO_BOOK_TITLE'] ?? '',
      Platform.environment['LEXO_BOOK_LEVEL'] ?? '',
      Platform.environment['LEXO_BOOK_SECTION'] ?? '',
      Platform.environment['LEXO_BOOK_CHAPTER_ID'] ?? '',
      Platform.environment['LEXO_BOOK_SOURCE_PATH'] ?? '',
      Platform.environment['LEXO_BOOK_COVER_PATH'] ?? '',
    ];
  }
  if (args.length != 7) {
    stderr.writeln(
      'Usage: dart run tool/refresh_workbench_book.dart '
      '<book_id> <title> <level> <section> <chapter_id> <source_path> <cover_path>',
    );
    exitCode = 64;
    return;
  }
  final bookId = args[0];
  final title = args[1];
  final api = LexoApiClient(baseUrl: 'http://127.0.0.1:8765');
  final package = await api.downloadMobileBookPackageChunked(bookId);
  final output = await VirgilWorkbenchBuilder(
    api: api,
    level: args[2],
    section: args[3],
    chapterId: args[4],
    chapterTitle: 'Chapter 1 — Introduction',
    sourcePath: args[5],
    coverPath: args[6],
    log: stdout.writeln,
    targetLangs: const ['ru'],
    bookIdsByTargetLang: {'ru': bookId},
    packagesByTargetLang: {'ru': package},
  ).exportFiles(
    bookId: bookId,
    fallbackTitle: title,
    textOnly: true,
  );
  stdout.writeln('Updated: ${output.path}');
}
