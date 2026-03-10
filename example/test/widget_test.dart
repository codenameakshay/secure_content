import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('counter increments in secure area', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Secure counter: 0'), findsOneWidget);

    await tester.tap(find.text('Increment secure counter'));
    await tester.pump();

    expect(find.text('Secure counter: 1'), findsOneWidget);
  });
}
