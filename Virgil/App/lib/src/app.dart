import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'ui/mobile/screens/mobile_shell_screen.dart';
import 'workbench/virgil_workbench_screen.dart';

void runLexoApp() {
  runApp(const LexoApp());
}

class LexoApp extends StatelessWidget {
  const LexoApp({super.key});

  static final LexoApiClient _api = LexoApiClient();
  static const _mode = String.fromEnvironment(
    'VIRGIL_MODE',
    defaultValue: 'mobile',
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Virgil',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A5A44)),
        scaffoldBackgroundColor: const Color(0xFFF5EFE6),
      ),
      home: LayoutBuilder(
        builder: (context, constraints) {
          if (_mode == 'workbench') {
            return VirgilWorkbenchScreen(api: _api);
          }
          if (_mode == 'mobile') {
            return MobileShellScreen(api: _api);
          }
          if (constraints.maxWidth >= 760) {
            return VirgilWorkbenchScreen(api: _api);
          }
          return MobileShellScreen(api: _api);
        },
      ),
    );
  }
}
