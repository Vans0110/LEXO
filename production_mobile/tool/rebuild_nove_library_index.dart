import 'dart:io';

import 'package:nove/src/workbench/nove_library_index_builder.dart';

Future<void> main() async {
  final indexFile = await NoveLibraryIndexBuilder(
    libraryDir: Directory('assets/library'),
    log: stdout.writeln,
  ).rebuild();
  stdout.writeln('Index written: ${indexFile.path}');
}
