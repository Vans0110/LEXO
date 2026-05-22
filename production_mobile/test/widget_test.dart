import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nove/src/ui/mobile/screens/mobile_reader_catalog_screen.dart';

void main() {
  testWidgets('Nove reader catalog smoke test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MobileReaderCatalogScreen(),
      ),
    );

    expect(find.text('Nove'), findsWidgets);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Introduction'), findsOneWidget);
    expect(find.text('Books'), findsNothing);
  });
}
