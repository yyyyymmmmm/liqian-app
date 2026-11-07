import 'package:flutter_test/flutter_test.dart';
import 'package:liqian/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LiqianApp());
    expect(find.text('礼钱账本'), findsOneWidget);
  });
}
