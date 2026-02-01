// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain1/main.dart';

void main() {
  testWidgets('WorkoutSession basic interaction smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify header and initial set text are present.
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('SET 1 / 5'), findsOneWidget);

    // Tap the primary action (LOG SET) and verify set increments.
    await tester.tap(find.text('LOG SET'));
    await tester.pump();

    expect(find.text('SET 2 / 5'), findsOneWidget);
  });
}
