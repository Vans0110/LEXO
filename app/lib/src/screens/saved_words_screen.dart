import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';

class SavedWordsScreen extends StatefulWidget {
  const SavedWordsScreen({super.key, required this.api});

  final LexoApiClient api;

  @override
  State<SavedWordsScreen> createState() => _SavedWordsScreenState();
}

class _SavedWordsScreenState extends State<SavedWordsScreen> {
  List<SavedWordItem> _items = const [];
  bool _busy = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await widget.api.getSavedWords();
      setState(() => _items = items);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items
        .where((item) => item.word.contains(_query) || item.lemma.contains(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Words')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Поиск по слову',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!)))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return ListTile(
                      title: Text(item.word),
                      subtitle: Text('${item.translation}\n${item.addedAt}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        onPressed: () async {
                          final result = await widget.api.requestWordAudio(item.word);
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Stub audio: ${result['audio_path']}')),
                          );
                        },
                        icon: const Icon(Icons.volume_up_outlined),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
