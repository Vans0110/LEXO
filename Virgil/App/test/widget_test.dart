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
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: VirgilAdaptiveBookGrid(
              itemCount: 5,
              itemBuilder: (_, index, width) => SizedBox(
                key: ValueKey(['one', 'two', 'three', 'four', 'five'][index]),
                width: width,
                height: [180.0, 140.0, 160.0, 120.0, 150.0][index],
              ),
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
    expect(tester.getSize(find.byKey(const ValueKey('one'))).width, 143);
  });

  testWidgets('adaptive book grid uses three capped columns on wide screens',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: VirgilAdaptiveBookGrid(
              itemCount: 5,
              itemBuilder: (_, index, width) => SizedBox(
                key: ValueKey(index),
                width: width,
                height: 150,
              ),
            ),
          ),
        ),
      ),
    );

    final one = tester.getTopLeft(find.byKey(const ValueKey(0)));
    final two = tester.getTopLeft(find.byKey(const ValueKey(1)));
    final three = tester.getTopLeft(find.byKey(const ValueKey(2)));
    final four = tester.getTopLeft(find.byKey(const ValueKey(3)));
    final five = tester.getTopLeft(find.byKey(const ValueKey(4)));

    expect(two.dy, one.dy);
    expect(three.dy, one.dy);
    expect(four.dx, one.dx);
    expect(five.dx, two.dx);
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 180);
  });
}
