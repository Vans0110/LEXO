import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class NoveFavoritesRepository {
  Future<Set<String>> load() async {
    final file = await _file();
    if (!file.existsSync()) {
      return <String>{};
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (raw['items'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> toggle(String key) async {
    final items = await load();
    if (items.contains(key)) {
      items.remove(key);
    } else {
      items.add(key);
    }
    await save(items);
    return items;
  }

  Future<Set<String>> remove(String key) async {
    final items = await load();
    items.remove(key);
    await save(items);
    return items;
  }

  Future<void> save(Set<String> items) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'items': items.toList()..sort()}),
      encoding: utf8,
      flush: true,
    );
  }

  Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/nove_favorites.json');
  }
}
