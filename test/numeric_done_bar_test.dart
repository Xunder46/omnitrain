import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/inputs/numeric_field_with_done_bar.dart';

void main() {
  group('Numeric Done accessory bar — appearance', () {
    testWidgets(
      'Done bar appears above keyboard when a numeric set-logging field is focused',
      (tester) async {
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NumericFieldWithDoneBar(
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        // pumpAndSettle processes the addPostFrameCallback
        await tester.pumpAndSettle();

        expect(find.text('Done'), findsOneWidget);
      },
    );

    testWidgets('Done bar does not appear when a free-text field is focused', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              decoration: const InputDecoration(labelText: 'Session note'),
              maxLines: null,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsNothing);
    });

    testWidgets('Done bar disappears after the numeric field loses focus', (
      tester,
    ) async {
      final numericFocus = FocusNode();
      final otherFocus = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                NumericFieldWithDoneBar(
                  focusNode: numericFocus,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Reps'),
                ),
                TextField(
                  focusNode: otherFocus,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Reps',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);

      // Move focus to the free-text field — Done bar should disappear
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Note',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
    });
  });

  group('Numeric Done accessory bar — commit and dismiss', () {
    testWidgets(
      'tapping Done dismisses the keyboard and preserves the typed value',
      (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NumericFieldWithDoneBar(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Distance (m)'),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '1500');
        await tester.pumpAndSettle();

        expect(find.text('Done'), findsOneWidget);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        // Keyboard dismissed (focus gone) and value unchanged
        expect(focusNode.hasFocus, isFalse);
        expect(controller.text, '1500');
      },
    );

    testWidgets(
      'tapping Done with an empty field dismisses keyboard without changing value',
      (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NumericFieldWithDoneBar(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Time (s)'),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(focusNode.hasFocus, isFalse);
        expect(controller.text, '');
      },
    );
  });
}
