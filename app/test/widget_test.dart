import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_app/src/app.dart';

void main() {
  testWidgets('LEXO app smoke test', (tester) async {
    await tester.pumpWidget(const LexoApp());

    expect(find.text('LEXO'), findsWidgets);
  });
}
