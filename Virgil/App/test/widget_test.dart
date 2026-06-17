import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virgil/src/ui/mobile/screens/mobile_reader_catalog_screen.dart';

void main() {
  testWidgets('Virgil reader catalog smoke test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MobileReaderCatalogScreen(),
      ),
    );

    expect(find.text('Virgil'), findsWidgets);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Downloaded Books'), findsOneWidget);
    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Introduction'), findsOneWidget);
    expect(find.text('Books'), findsNothing);
  });

  testWidgets('adaptive book grid aligns rows at top and last row left',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: VirgilAdaptiveBookGrid(
              children: [
                SizedBox(key: ValueKey('one'), width: 116, height: 180),
                SizedBox(key: ValueKey('two'), width: 116, height: 140),
                SizedBox(key: ValueKey('three'), width: 116, height: 160),
                SizedBox(key: ValueKey('four'), width: 116, height: 120),
                SizedBox(key: ValueKey('five'), width: 116, height: 150),
              ],
            ),
          ),
        ),
      ),
    );

    final one = tester.getTopLeft(find.byKey(const ValueKey('one')));
    final two = tester.getTopLeft(find.byKey(const ValueKey('two')));
    final three = tester.getTopLeft(find.byKey(const ValueKey('three')));
    final four = tester.getTopLeft(find.byKey(const ValueKey('four')));
    final five = tester.getTopLeft(find.byKey(const ValueKey('five')));

    expect(two.dy, one.dy);
    expect(four.dy, three.dy);
    expect(five.dx, one.dx);
  });
}
