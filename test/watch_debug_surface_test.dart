// The QA surface of iteration 1 step 5: create → log → kill → restore, driven
// through the UI a human taps on hardware.
//
// Plan: `docs/plans/2026-07-13-06-a1-watch-session-engine-plan.md`.
//
// This is a harness test, not a scenario test: S-001 and S-002 already prove the
// engine restores, and this proves the surface QA is handed actually drives the
// engine — including the "kill" that throws the engine away.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/debug/watch_session_debug_surface.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';

void main() {
  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WatchSessionDebugSurface(store: InMemoryWatchSessionStore()),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets(
    'new session, a logged set, and a kill all survive on one store',
    (tester) async {
      await pumpSurface(tester);
      expect(find.text('No session stored.'), findsOneWidget);

      await tap(tester, 'New session');
      expect(find.text('Session active'), findsOneWidget);
      expect(find.text('exercise: 1 of 3 — Back Squat'), findsOneWidget);

      await tap(tester, 'Log set');
      expect(find.text('entries logged: 1'), findsOneWidget);

      await tap(tester, 'Simulate kill');
      expect(
        find.textContaining('engine discarded'),
        findsOneWidget,
        reason: 'the surface reports the restore it just performed',
      );
      expect(
        find.text('entries logged: 1'),
        findsOneWidget,
        reason: 'the restored engine reads storage, not the discarded one',
      );
      expect(find.text('exercise: 1 of 3 — Back Squat'), findsOneWidget);

      // Advance, then kill again: position has to come back from storage too.
      await tap(tester, 'Next exercise');
      await tap(tester, 'Simulate kill');
      expect(find.text('exercise: 2 of 3 — Bench Press'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  /// The surface's one-line rest readout, as the user reads it.
  String restLine(WidgetTester tester) => tester
      .widgetList<Text>(find.textContaining('rest:'))
      .map((text) => text.data ?? '')
      .single;

  testWidgets('a rest timer is restored from its timestamps, not a counter', (
    tester,
  ) async {
    await pumpSurface(tester);

    await tap(tester, 'New session');
    await tap(tester, 'Rest 90s');
    expect(restLine(tester), contains('rest: running'));
    expect(restLine(tester), contains('left'));

    await tap(tester, 'Simulate kill');
    expect(
      restLine(tester),
      contains('rest: running'),
      reason:
          'timestamps restore a running timer; a stored countdown could not',
    );

    await tap(tester, 'Pause rest');
    expect(restLine(tester), contains('rest: paused'));

    final held = restLine(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(
      restLine(tester),
      held,
      reason:
          'the readout is derived from stored instants, so pausing holds it',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the engine, not the store, owns what the summary counts', (
    tester,
  ) async {
    await pumpSurface(tester);

    await tap(tester, 'New session');
    await tap(tester, 'Log set');
    await tap(tester, 'Log set');
    expect(find.text('entries logged: 2'), findsOneWidget);
    expect(find.text('unconfirmed owed to phone: 2'), findsOneWidget);

    await tap(tester, 'Prune confirmed');
    expect(
      find.text('entries logged: 2'),
      findsOneWidget,
      reason: 'nothing is confirmed yet, so nothing may be dropped',
    );

    await tap(tester, 'Confirm all');
    await tap(tester, 'Prune confirmed');
    expect(find.text('entries logged: 0'), findsOneWidget);
    expect(
      find.text('unconfirmed owed to phone: 0'),
      findsOneWidget,
      reason: 'a prune the engine performed is reflected in its own view',
    );

    await tester.pumpWidget(const SizedBox());
  });
}
