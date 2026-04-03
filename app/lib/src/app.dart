import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/home_screen.dart';
import 'ui/mobile/screens/mobile_shell_screen.dart';

void runLexoApp() {
  runApp(const LexoApp());
}

class LexoApp extends StatelessWidget {
  const LexoApp({super.key});

  static final LexoApiClient _api = LexoApiClient();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LEXO',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A5A44)),
        scaffoldBackgroundColor: const Color(0xFFF5EFE6),
      ),
      home: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return MobileShellScreen(api: _api);
          }
          return HomeScreen(api: _api);
        },
      ),
    );
  }
}
