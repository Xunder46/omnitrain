// filepath: test/omni_bottom_cta_secondary_test.dart
//
// S-93.1..3 — the optional secondary action of `OmniBottomCTA`: same height,
// width, radius and margins as the primary button, stacked directly above it.
// Used by the food editor for Delete food / Reset to original.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/layout/omni_bottom_cta.dart';

Widget _host({
  String? secondaryLabel,
  bool destructive = false,
  VoidCallback? onSecondary,
}) {
  return MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: OmniBottomCTA(
        label: 'Save',
        buttonKey: const Key('primary'),
        onPressed: () {},
        secondaryLabel: secondaryLabel,
        secondaryButtonKey: const Key('secondary'),
        isSecondaryDestructive: destructive,
        onSecondaryPressed: onSecondary,
      ),
    ),
  );
}

void main() {
  testWidgets('S-93.1: no secondary label renders no secondary button', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    expect(find.byKey(const Key('primary')), findsOneWidget);
    expect(find.byKey(const Key('secondary')), findsNothing);
  });

  testWidgets(
    'S-93.2: the secondary button has the primary height, width and radius, '
    'and sits directly above it',
    (tester) async {
      await tester.pumpWidget(_host(secondaryLabel: 'Delete food'));
      final primary = tester.getRect(find.byKey(const Key('primary')));
      final secondary = tester.getRect(find.byKey(const Key('secondary')));

      expect(secondary.height, OmniTheme.buttonPrimaryHeight);
      expect(secondary.height, primary.height);
      expect(secondary.left, primary.left);
      expect(secondary.right, primary.right);
      expect(secondary.bottom, lessThan(primary.top));
      expect(primary.top - secondary.bottom, OmniTheme.bottomCTASecondaryGap);

      final style = tester
          .widget<OutlinedButton>(find.byKey(const Key('secondary')))
          .style!;
      final shape =
          style.shape!.resolve(<WidgetState>{}) as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(OmniTheme.buttonBorderRadius),
      );
    },
  );

  testWidgets(
    'S-93.3: destructive secondary uses the error colour, tap works',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          secondaryLabel: 'Delete food',
          destructive: true,
          onSecondary: () => taps++,
        ),
      );
      final theme = Theme.of(
        tester.element(find.byKey(const Key('secondary'))),
      );
      final style = tester
          .widget<OutlinedButton>(find.byKey(const Key('secondary')))
          .style!;
      expect(
        style.foregroundColor!.resolve(<WidgetState>{}),
        theme.colorScheme.error,
      );

      await tester.tap(find.byKey(const Key('secondary')));
      expect(taps, 1);
    },
  );
}
