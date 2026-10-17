import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/constants/workout_constants.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/widgets/session/set_count_stepper.dart';
import 'package:omnitrain/widgets/session/set_segment_bar.dart';

/// Hosts a widget the way the session screen does: inside a `MaterialApp`
/// and a `Scaffold`, at the default 800x600 test surface.
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

ColorScheme _schemeOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold))).colorScheme;

Finder _segment(int index) => find.byKey(Key('set-segment-$index'));

Finder _segmentBar(int index) =>
    find.descendant(of: _segment(index), matching: find.byType(Container));

BoxDecoration _decorationOf(WidgetTester tester, int index) =>
    tester.widget<Container>(_segmentBar(index)).decoration! as BoxDecoration;

double _barHeight(WidgetTester tester, int index) =>
    tester.getSize(_segmentBar(index)).height;

Finder _caption(int index) => find.byKey(Key('set-caption-$index'));

/// Any caption at all, whatever the index.
Finder _captionsPresent() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('set-caption-'),
);

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-4201 / S-4202 — SetSegmentBar
  // ══════════════════════════════════════════════════════════════════════════
  group('Mock S-4201 SetSegmentBar', () {
    testWidgets('one segment per set, 48 dp tall, tap reports its index', (
      tester,
    ) async {
      var tapped = -1;
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            onTap: (i) => tapped = i,
          ),
        ),
      );

      expect(_segment(0), findsOneWidget);
      expect(_segment(1), findsOneWidget);
      expect(_segment(2), findsOneWidget);

      expect(tester.getSize(_segment(2)).height, greaterThanOrEqualTo(48));

      await tester.tap(_segment(2));
      expect(tapped, 2);
    });

    testWidgets('each segment carries its own semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            onTap: (_) {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Set 1 of 3, logged'), findsOneWidget);
      expect(find.bySemanticsLabel('Set 2 of 3, current'), findsOneWidget);
      expect(find.bySemanticsLabel('Set 3 of 3, not logged'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('a logged segment is filled primary and 6 dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            onTap: (_) {},
          ),
        ),
      );

      final scheme = _schemeOf(tester);
      final decoration = _decorationOf(tester, 0);
      expect(decoration.color, scheme.primary);
      expect(decoration.border, isNull);
      expect(_barHeight(tester, 0), 6);
    });

    testWidgets('a focused unlogged segment is faint primary, no border, 6 dp '
        'tall', (tester) async {
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            onTap: (_) {},
          ),
        ),
      );

      final scheme = _schemeOf(tester);
      final decoration = _decorationOf(tester, 1);
      expect(decoration.color, scheme.primary.withAlpha(115));
      expect(decoration.border, isNull, reason: 'no outline anywhere');
      expect(_barHeight(tester, 1), 6);
    });

    testWidgets('an unlogged segment is onSurface 0.2 and 6 dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            onTap: (_) {},
          ),
        ),
      );

      final scheme = _schemeOf(tester);
      final decoration = _decorationOf(tester, 2);
      expect(decoration.color, scheme.onSurface.withAlpha(51));
      expect(decoration.border, isNull);
      expect(_barHeight(tester, 2), 6);
    });
  });

  group('Mock S-4202 SetSegmentBar logged and focused', () {
    testWidgets('the label reads logged, current and the fill is logged', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 1,
            onTap: (_) {},
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Set 2 of 3, logged, current'),
        findsOneWidget,
      );

      final scheme = _schemeOf(tester);
      final decoration = _decorationOf(tester, 1);
      expect(decoration.color, scheme.primary);
      expect(decoration.border, isNull);
      expect(_barHeight(tester, 1), 6);

      handle.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-4325 — SetSegmentBar captions
  // ══════════════════════════════════════════════════════════════════════════
  group('Mock S-4325 SetSegmentBar captions', () {
    const captions = <String?>['10×60', '8×62.5', null];

    testWidgets('one caption per set, in its cell, under a top-aligned bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            captions: captions,
            onTap: (_) {},
          ),
        ),
      );

      expect(_caption(0), findsOneWidget);
      expect(_caption(1), findsOneWidget);
      expect(_caption(2), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        final cell = tester.getRect(_segment(i));
        final bar = tester.getRect(_segmentBar(i));
        final caption = tester.getRect(_caption(i));

        expect(cell.height, greaterThanOrEqualTo(48));
        expect(bar.height, 6);
        expect(bar.top, cell.top, reason: 'the bar sits at the top of cell $i');
        expect(
          caption.top,
          greaterThanOrEqualTo(bar.bottom),
          reason: 'caption $i is under its own bar',
        );
        expect(caption.left, greaterThanOrEqualTo(cell.left));
        expect(caption.right, lessThanOrEqualTo(cell.right));
        expect(tester.widget<Text>(_caption(i)).maxLines, 1);
        expect(
          find.descendant(of: _segment(i), matching: find.byType(Container)),
          findsOneWidget,
          reason: 'the caption is not a Container (the segment finder)',
        );
      }

      expect(tester.widget<Text>(_caption(0)).data, '10×60');
      expect(tester.widget<Text>(_caption(1)).data, '8×62.5');
      expect(tester.widget<Text>(_caption(2)).data, '');
    });

    testWidgets('the focused caption is dominant, the others secondary', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            captions: captions,
            onTap: (_) {},
          ),
        ),
      );

      expect(
        tester.widget<Text>(_caption(1)).style?.color,
        OmniTheme.colors.textDominant,
      );
      expect(
        tester.widget<Text>(_caption(0)).style?.color,
        OmniTheme.colors.textSecondary,
      );
      expect(
        tester.widget<Text>(_caption(2)).style?.color,
        OmniTheme.colors.textSecondary,
      );
    });

    testWidgets('tapping a caption reports its index like the segment', (
      tester,
    ) async {
      var tapped = -1;
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 0,
            isLogged: (i) => i == 0,
            captions: captions,
            onTap: (i) => tapped = i,
          ),
        ),
      );

      await tester.tap(_caption(1));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('no captions without a list, with a short list or above the '
        'set cap', (tester) async {
      Future<void> pump({required int count, List<String?>? captions}) {
        return tester.pumpWidget(
          _host(
            SetSegmentBar(
              count: count,
              focusedIndex: 0,
              isLogged: (i) => i == 0,
              captions: captions,
              onTap: (_) {},
            ),
          ),
        );
      }

      expect(kSetBarCaptionMaxSets, 5);

      await pump(count: 3);
      expect(_captionsPresent(), findsNothing);

      await pump(count: 3, captions: const ['10×60', '8×62.5']);
      expect(_captionsPresent(), findsNothing);

      await pump(
        count: 6,
        captions: List<String?>.generate(6, (i) => '${i + 1}0×60'),
      );
      expect(_captionsPresent(), findsNothing);

      await pump(
        count: 5,
        captions: List<String?>.generate(5, (i) => '${i + 1}0×60'),
      );
      expect(_captionsPresent(), findsNWidgets(5));
    });

    testWidgets('S-4332 the caption row is 20 dp tall, 4 dp under its bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SetSegmentBar(
            count: 3,
            focusedIndex: 1,
            isLogged: (i) => i == 0,
            captions: captions,
            onTap: (_) {},
          ),
        ),
      );

      for (var i = 0; i < 3; i++) {
        final bar = tester.getRect(_segmentBar(i));
        final caption = tester.getRect(_caption(i));
        expect(caption.height, 20, reason: 'the caption row is a 20 dp slot');
        expect(
          caption.top - bar.bottom,
          4,
          reason: 'the gap under the bar of cell $i',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-4204 — SetCountStepper
  // ══════════════════════════════════════════════════════════════════════════
  group('Mock S-4204 SetCountStepper', () {
    testWidgets('tooltips, 48 dp targets and both callbacks fire', (
      tester,
    ) async {
      var adds = 0;
      var removes = 0;
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text: 'Set 2 of 3',
            canAdd: true,
            removeIsExercise: false,
            onAdd: () => adds++,
            onRemove: () => removes++,
          ),
        ),
      );

      expect(find.text('Set 2 of 3'), findsOneWidget);
      expect(find.text('SETS'), findsNothing);

      final box = find.ancestor(
        of: find.text('Set 2 of 3'),
        matching: find.byType(OmniSurface),
      );
      expect(box, findsOneWidget);
      expect(
        find.descendant(
          of: box,
          matching: find.byKey(const Key('set-count-add')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: box,
          matching: find.byKey(const Key('set-count-remove')),
        ),
        findsOneWidget,
      );

      expect(find.byTooltip('Remove set'), findsOneWidget);
      expect(find.byTooltip('Add set'), findsOneWidget);

      for (final key in const [Key('set-count-remove'), Key('set-count-add')]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(48),
          reason: '$key is a 48 dp target',
        );
        expect(
          tester.getSize(find.byKey(key)).width,
          greaterThanOrEqualTo(48),
          reason: '$key is a 48 dp target',
        );
      }

      await tester.tap(find.byKey(const Key('set-count-add')));
      expect(adds, 1);
      await tester.tap(find.byKey(const Key('set-count-remove')));
      expect(removes, 1);
    });

    testWidgets('add disabled at the cap carries the cap tooltip and fires '
        'nothing', (tester) async {
      var adds = 0;
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text:
                'Set ${WorkoutConstants.maxEntriesPerEffort} of '
                '${WorkoutConstants.maxEntriesPerEffort}',
            canAdd: false,
            removeIsExercise: false,
            onAdd: () => adds++,
            onRemove: () {},
          ),
        ),
      );

      expect(find.byTooltip('Max 12 entries'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-count-add')));
      expect(adds, 0);
    });

    testWidgets('a one-set exercise offers Remove exercise with a trash icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text: 'Set 1 of 1',
            canAdd: true,
            removeIsExercise: true,
            onAdd: () {},
            onRemove: () {},
          ),
        ),
      );

      expect(find.byTooltip('Remove exercise'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsNothing);
    });

    testWidgets('S-4333 the boxed control is inset, flat and centred on a '
        '390 dp screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text: 'Set 2 of 3',
            canAdd: true,
            removeIsExercise: false,
            onAdd: () {},
            onRemove: () {},
          ),
        ),
      );

      final box = find.ancestor(
        of: find.byKey(const Key('set-count-remove')),
        matching: find.byType(OmniSurface),
      );
      expect(box, findsOneWidget);

      final surface = tester.widget<OmniSurface>(box);
      expect(surface.showShadow, isFalse);
      expect(
        surface.padding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      );

      final boxRect = tester.getRect(box);
      expect(boxRect.left, 20);
      expect(boxRect.right, 370);

      final line = find.text('Set 2 of 3');
      expect(tester.getCenter(line).dx, closeTo(boxRect.center.dx, 0.5));

      final style = tester.widget<Text>(line).style!;
      expect(style.letterSpacing, 2.0);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.color, OmniTheme.colors.textSecondary);
    });

    testWidgets('addKey / removeKey override the default button keys', (
      tester,
    ) async {
      var adds = 0;
      var removes = 0;
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text: 'Set 2 of 3',
            canAdd: true,
            removeIsExercise: false,
            onAdd: () => adds++,
            onRemove: () => removes++,
            addKey: const Key('routine-add-set'),
            removeKey: const Key('routine-remove-set'),
          ),
        ),
      );

      expect(find.byKey(const Key('routine-add-set')), findsOneWidget);
      expect(find.byKey(const Key('routine-remove-set')), findsOneWidget);
      expect(find.byKey(const Key('set-count-add')), findsNothing);
      expect(find.byKey(const Key('set-count-remove')), findsNothing);

      await tester.tap(find.byKey(const Key('routine-add-set')));
      await tester.tap(find.byKey(const Key('routine-remove-set')));
      expect(adds, 1);
      expect(removes, 1);
    });

    testWidgets('canRemove false nulls the minus callback and leaves plus '
        'working', (tester) async {
      var adds = 0;
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text: 'Set 2 of 3',
            canAdd: true,
            removeIsExercise: false,
            canRemove: false,
            onAdd: () => adds++,
            onRemove: () {},
          ),
        ),
      );

      final minus = tester.widget<IconButton>(
        find.byKey(const Key('set-count-remove')),
      );
      expect(minus.onPressed, isNull);
      // The disabled button stays in the tree rather than disappearing.
      expect(minus.tooltip, 'Remove set');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('set-count-add')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('set-count-add')));
      expect(adds, 1);
    });

    testWidgets('without the new parameters the keys are set-count-add / '
        'set-count-remove and both buttons are enabled', (tester) async {
      var adds = 0;
      var removes = 0;
      await tester.pumpWidget(
        _host(
          SetCountStepper(
            text: 'Set 2 of 3',
            canAdd: true,
            removeIsExercise: false,
            onAdd: () => adds++,
            onRemove: () => removes++,
          ),
        ),
      );

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('set-count-add')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('set-count-remove')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('set-count-add')));
      await tester.tap(find.byKey(const Key('set-count-remove')));
      expect(adds, 1);
      expect(removes, 1);
    });
  });
}
