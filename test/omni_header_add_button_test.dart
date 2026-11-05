// Plan 91 — the one header "+".
//
// `docs/plans/2026-10-29-91-one-header-plus-plan` — S-9151 (one "+", its
// label, the header colour), S-9152 (same size whatever the label), S-9153
// (press shrink, release, cancel, reduced motion). The rules are D-91.2 and
// D-91.3 in that plan's ledger.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/buttons/omni_header_add_button.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';

const _key = Key('k');

Widget _headerTree({
  required VoidCallback onPressed,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      appBar: OmniBackHeader(
        title: 'T',
        actions: [
          OmniHeaderAddButton(
            label: 'New Thing',
            buttonKey: _key,
            onPressed: onPressed,
          ),
        ],
      ),
    ),
  );
}

Finder _underPiece(Finder matching) =>
    find.descendant(of: find.byType(OmniHeaderAddButton), matching: matching);

/// The horizontal scale the piece applies: the outermost `Transform` under
/// the piece (`Transform.scale` scales x and y and leaves z at 1).
double _appliedScale(WidgetTester tester) {
  final transform = tester
      .widgetList<Transform>(_underPiece(find.byType(Transform)))
      .first;
  return transform.transform.entry(0, 0);
}

void main() {
  group('S-9151..S-9153 OmniHeaderAddButton', () {
    testWidgets('S-9151: one "+", reads its label, uses the header colour', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_headerTree(onPressed: () => taps++));

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byKey(_key), findsOneWidget);
      final button = tester.widget<IconButton>(find.byKey(_key));
      expect(button.tooltip, 'New Thing');
      expect(button.color, OmniTheme.colors.textDominant);
      // One screen-reader stop: exactly one node carries the words (as label
      // or tooltip), and that node is the one that can be activated.
      final spoken = find.semantics.byPredicate(
        (n) => n.label == 'New Thing' || n.tooltip == 'New Thing',
      );
      expect(spoken, findsOne);
      expect(
        spoken.evaluate().single.getSemanticsData().hasAction(
          SemanticsAction.tap,
        ),
        isTrue,
      );
      expect(_underPiece(find.byType(Text)), findsNothing);

      await tester.tap(find.byKey(_key));
      await tester.pumpAndSettle();
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('S-9152: the same size whatever the label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                OmniHeaderAddButton(
                  label: 'New',
                  buttonKey: const Key('a'),
                  onPressed: () {},
                ),
                OmniHeaderAddButton(
                  label: 'New Category With A Very Long Name',
                  buttonKey: const Key('b'),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('a')), findsOneWidget);
      expect(find.byKey(const Key('b')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('a'))),
        tester.getSize(find.byKey(const Key('b'))),
      );
    });

    testWidgets('S-9153: shrinks while pressed, returns on release and on '
        'cancel, and applies instantly with reduced motion', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_headerTree(onPressed: () => taps++));
      expect(find.byKey(_key), findsOneWidget);
      final centre = tester.getCenter(find.byKey(_key));

      // (1) Press, hold, release.
      var gesture = await tester.startGesture(centre);
      await tester.pump(OmniTheme.animationDuration);
      expect(_underPiece(find.byType(AnimatedScale)), findsOneWidget);
      expect(
        tester
            .widget<AnimatedScale>(_underPiece(find.byType(AnimatedScale)))
            .scale,
        OmniTheme.pressedScale,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(_underPiece(find.byType(AnimatedScale)))
            .scale,
        1.0,
      );
      expect(taps, 1);

      // (2) Press, drag the finger off, lift: back to full size, no tap.
      gesture = await tester.startGesture(centre);
      await tester.pump(OmniTheme.animationDuration);
      await gesture.moveBy(const Offset(0, 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(_underPiece(find.byType(AnimatedScale)))
            .scale,
        1.0,
      );
      expect(taps, 1);

      // (3) Reduced motion: the scale applies on the first frame.
      await tester.pumpWidget(
        _headerTree(onPressed: () => taps++, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      expect(_underPiece(find.byType(AnimatedScale)), findsNothing);
      gesture = await tester.startGesture(tester.getCenter(find.byKey(_key)));
      await tester.pump();
      expect(_appliedScale(tester), closeTo(OmniTheme.pressedScale, 1e-9));
      await gesture.up();
      await tester.pump();
      expect(_appliedScale(tester), closeTo(1.0, 1e-9));
      await tester.pumpAndSettle();
    });
  });
}
