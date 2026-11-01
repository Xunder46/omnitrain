// filepath: test/omni_utility_button_test.dart
//
// S-94.1..2 — OmniUtilityButton: the one outlined, icon-led, content-width
// control for an inline secondary action (Change rating, the food form's
// package-serving switch).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/buttons/omni_utility_button.dart';

void main() {
  testWidgets(
    'S-94.1: it is an outlined button with an icon, the utility radius and '
    'content width',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: OmniUtilityButton(
                buttonKey: const Key('u'),
                label: 'Change rating',
                icon: Icons.edit_outlined,
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      final finder = find.byKey(const Key('u'));
      final button = tester.widget<OutlinedButton>(finder);
      final shape =
          button.style!.shape!.resolve(<WidgetState>{})
              as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      );
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('Change rating'), findsOneWidget);
      expect(
        tester.getSize(finder).width,
        lessThan(300),
        reason: 'content-width, not full-width',
      );

      await tester.tap(finder);
      expect(taps, 1);
    },
  );

  testWidgets('S-94.2: a null onPressed disables it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OmniUtilityButton(
            buttonKey: Key('u'),
            label: 'Add rating',
            icon: Icons.add,
            onPressed: null,
          ),
        ),
      ),
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(const Key('u'))).enabled,
      isFalse,
    );
  });
}
