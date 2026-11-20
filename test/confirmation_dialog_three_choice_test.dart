// Plan 277 P3a — the shared three-choice scope dialog (D-27707).
//
// `showThreeChoice` / `threeChoice` on ConfirmationDialog: Cancel
// (TextButton) first, then "Just this one" (OutlinedButton), then "This and
// all after it" (FilledButton; error pair when destructive). Barrier tap and
// the back gesture coalesce to ThreeChoice.cancel. Three actions stack
// downward when the row is too narrow, so a 390x844 phone holds all three
// without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/dialogs/confirmation_dialog.dart';

ThreeChoice? _lastResult;

void main() {
  tearDown(() => _lastResult = null);

  /// Pumps a host whose button opens [ConfirmationDialog.showThreeChoice].
  Future<void> pumpHost(
    WidgetTester tester, {
    bool isDestructive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  _lastResult = await ConfirmationDialog.showThreeChoice(
                    context: context,
                    title: 'Delete this session?',
                    body: const Text('It is part of a repeating series.'),
                    firstLabel: 'Just this one',
                    secondLabel: 'This and all after it',
                    cancelLabel: 'Cancel',
                    firstKey: const Key('test-first'),
                    secondKey: const Key('test-second'),
                    cancelKey: const Key('test-cancel'),
                    isDestructive: isDestructive,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'P3a: the three actions render in the order cancel, first, second',
    (tester) async {
      // Wide surface: the one-row layout the overflow direction falls back
      // from; the 390x844 stacked layout is tested below.
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfirmationDialog.threeChoice(
              title: 'Delete this session?',
              firstLabel: 'Just this one',
              secondLabel: 'This and all after it',
              cancelLabel: 'Cancel',
              firstKey: const Key('test-first'),
              secondKey: const Key('test-second'),
              cancelKey: const Key('test-cancel'),
              isDestructive: true,
            ),
          ),
        ),
      );

      final types = <String, Rect>{
        'cancel': tester.getRect(find.byType(TextButton)),
        'first': tester.getRect(find.byType(OutlinedButton)),
        'second': tester.getRect(find.byType(FilledButton)),
      };
      // Not overflowing: one row, so the order reads left to right.
      expect(
        types['cancel']!.left,
        lessThan(types['first']!.left),
        reason: 'cancel sits before first',
      );
      expect(
        types['first']!.left,
        lessThan(types['second']!.left),
        reason: 'first sits before second',
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Just this one'), findsOneWidget);
      expect(find.text('This and all after it'), findsOneWidget);
    },
  );

  testWidgets('P3a: the cancel action returns ThreeChoice.cancel', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('test-cancel')));
    await tester.pumpAndSettle();

    expect(_lastResult, ThreeChoice.cancel);
  });

  testWidgets(
    'P3a: the first action ("Just this one") returns ThreeChoice.first',
    (tester) async {
      await pumpHost(tester);
      await tester.tap(find.byKey(const Key('test-first')));
      await tester.pumpAndSettle();

      expect(_lastResult, ThreeChoice.first);
    },
  );

  testWidgets('P3a: the second action ("This and all after it") returns '
      'ThreeChoice.second', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('test-second')));
    await tester.pumpAndSettle();

    expect(_lastResult, ThreeChoice.second);
  });

  testWidgets('P3a: a barrier tap returns ThreeChoice.cancel', (tester) async {
    await pumpHost(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(_lastResult, ThreeChoice.cancel);
  });

  testWidgets('P3a: the back gesture (Navigator.pop) returns '
      'ThreeChoice.cancel', (tester) async {
    await pumpHost(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_lastResult, ThreeChoice.cancel);
  });

  testWidgets('P3a: on a 390x844 phone surface the three buttons stack without '
      'overflow and every button is hittable inside the surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHost(tester);

    expect(tester.takeException(), isNull);

    final surface = Offset.zero & const Size(390, 844);
    for (final key in const [
      Key('test-cancel'),
      Key('test-first'),
      Key('test-second'),
    ]) {
      final rect = tester.getRect(find.byKey(key));
      expect(
        surface.contains(rect.topLeft),
        isTrue,
        reason: 'button $key starts inside the surface',
      );
      expect(
        surface.contains(rect.bottomRight),
        isTrue,
        reason: 'button $key ends inside the surface',
      );
      // Stacked downward: the three actions never share one row.
      expect(rect.width, lessThan(390));
    }

    // Every button actually receives a tap.
    await tester.tap(find.byKey(const Key('test-cancel')));
    await tester.pumpAndSettle();
    expect(_lastResult, ThreeChoice.cancel);
  });

  testWidgets('P3a: isDestructive gives the second button the error pair; the '
      'non-destructive call keeps the theme defaults', (tester) async {
    final scheme = ThemeData().colorScheme;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfirmationDialog.threeChoice(
            title: 'Delete this session?',
            firstLabel: 'Just this one',
            secondLabel: 'This and all after it',
            cancelLabel: 'Cancel',
            firstKey: const Key('test-first'),
            secondKey: const Key('test-second'),
            cancelKey: const Key('test-cancel'),
            isDestructive: true,
          ),
        ),
      ),
    );
    final destructive = tester
        .widget<FilledButton>(find.byKey(const Key('test-second')))
        .style!;
    expect(destructive.shape?.resolve({}), isA<RoundedRectangleBorder>());
    expect(
      (destructive.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(OmniTheme.buttonUtilityRadius),
    );
    expect(destructive.backgroundColor!.resolve({}), scheme.error);
    expect(destructive.foregroundColor!.resolve({}), scheme.onError);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfirmationDialog.threeChoice(
            title: 'Change this session?',
            firstLabel: 'Just this one',
            secondLabel: 'This and all after it',
            cancelLabel: 'Cancel',
            firstKey: const Key('test-first'),
            secondKey: const Key('test-second'),
            cancelKey: const Key('test-cancel'),
            isDestructive: false,
          ),
        ),
      ),
    );
    final routine = tester
        .widget<FilledButton>(find.byKey(const Key('test-second')))
        .style!;
    expect(routine.backgroundColor, isNull);
    expect(routine.foregroundColor, isNull);
    expect(routine.shape?.resolve({}), isA<RoundedRectangleBorder>());
  });
}
