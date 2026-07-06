// Tests for the startup-failure screen and the retry path that
// re-runs the entire `main()` initialization sequence. The
// scenarios in `.github/agents/plans/startup-failure-screen-plan.md`
// (S-001..S-004) map 1:1 to the four tests below.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app/startup_root.dart';
import 'package:omnitrain/features/startup/startup_failure_screen.dart';

void main() {
  group('StartupFailureScreen', () {
    testWidgets(
      'S-001 — copy has no developer terminology and the Retry control is present',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: StartupFailureScreen(onRetry: () {}),
          ),
        );
        await tester.pumpAndSettle();

        // Collect every visible Text payload in the widget tree,
        // lowercased, so a single contains() check covers every
        // label we render (headline, secondary line, button text).
        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => (t.data ?? '').toLowerCase())
            .join('\n');

        // The explicit assertions called out in the acceptance
        // criteria: no "console", no raw error text, no log
        // language, no exception/stack/debug/developer verbiage.
        expect(visibleText, isNot(contains('console')));
        expect(visibleText, isNot(contains('error')));
        expect(visibleText, isNot(contains('exception')));
        expect(visibleText, isNot(contains('stack')));
        expect(visibleText, isNot(contains('debug')));
        expect(visibleText, isNot(contains('developer')));

        // Retry control is visible and enabled.
        final retryFinder = find.widgetWithText(FilledButton, 'Retry');
        expect(retryFinder, findsOneWidget);
        final FilledButton retry = tester.widget(retryFinder);
        expect(retry.onPressed, isNotNull);
      },
    );
  });

  group('StartupRoot — retry wiring', () {
    testWidgets(
      'S-002 — tapping Retry re-invokes the startup routine exactly once more',
      (WidgetTester tester) async {
        var callCount = 0;

        Future<Widget> alwaysFail() async {
          callCount += 1;
          throw StateError('simulated startup failure');
        }

        await tester.pumpWidget(
          StartupRoot(startupRunner: alwaysFail),
        );
        await tester.pumpAndSettle();

        // The first attempt runs from initState.
        expect(callCount, 1);
        expect(find.byType(StartupFailureScreen), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pumpAndSettle();

        // Exactly one additional invocation — no surprise retries.
        expect(callCount, 2);
        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-003 — retry after a transient failure lands in the normal app surface',
      (WidgetTester tester) async {
        var attempt = 0;

        Future<Widget> recoverOnRetry() async {
          attempt += 1;
          if (attempt == 1) {
            throw StateError('transient');
          }
          // Wrap in a MaterialApp so the Scaffold has the
          // Directionality ancestor it requires — mirrors what
          // `MyApp(...)` does in production.
          return const MaterialApp(
            home: Scaffold(body: Text('APP-SURFACE-MARKER')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(startupRunner: recoverOnRetry),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(find.text('APP-SURFACE-MARKER'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pumpAndSettle();

        // After the retry succeeds the failure screen is gone and
        // the widget the runner returned is now mounted.
        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.text('APP-SURFACE-MARKER'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-004 — repeated retries under persistent failure stay on the failure screen without throwing',
      (WidgetTester tester) async {
        var callCount = 0;

        Future<Widget> persistentFailure() async {
          callCount += 1;
          throw StateError('never recovers');
        }

        await tester.pumpWidget(
          StartupRoot(startupRunner: persistentFailure),
        );
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          expect(
            find.byType(StartupFailureScreen),
            findsOneWidget,
            reason: 'failure screen must remain on iteration $i',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'no exception must escape on iteration $i',
          );

          await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
          await tester.pumpAndSettle();
        }

        // Initial attempt + 3 retries = 4 runner invocations.
        expect(callCount, 4);
        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-005 — a successful first attempt never renders the failure screen',
      (WidgetTester tester) async {
        Future<Widget> succeedImmediately() async {
          return const MaterialApp(
            home: Scaffold(body: Text('FIRST-LAUNCH-SURFACE')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(startupRunner: succeedImmediately),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.text('FIRST-LAUNCH-SURFACE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}