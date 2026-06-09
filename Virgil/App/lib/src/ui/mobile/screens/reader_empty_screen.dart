import 'package:flutter/material.dart';

class ReaderEmptyScreen extends StatelessWidget {
  const ReaderEmptyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Open a book from the Library tab.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
