import 'dart:io';

import 'package:virgil/src/workbench/virgil_library_index_builder.dart';

Future<void> main() async {
  final indexFile = await VirgilLibraryIndexBuilder(
    libraryDir: Directory('assets/library'),
    log: stdout.writeln,
  ).rebuild();
  stdout.writeln('Index written: ${indexFile.path}');
}
