// Plan 213 — a dismissed signal can be brought back: the screen half.
//
// Scenarios S-21391…S-21395 of
// `docs/plans/2026-11-16-213-stats-dismissed-signal-can-be-brought-back-plan/`:
// the dismiss shows `Signal hidden for 14 days.` with an `Undo` action for
// 6 seconds, Undo restores the card and takes only that entry out of the
// store, a second dismissal replaces the message, an unanswered message
// changes nothing, and Undo still works after the Stats screen is popped.
//
// Mock only: a widget test body runs under `FakeAsync`, where a Hive read
// never settles, so the store under test is the in-memory
// `MockWorkoutRepository`, opened and seeded in `setUp`, never inside a
// `testWidgets` body. The stub signals need no ratings, so they speak from the
// first completed session (D-17501).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the Signals cards and their dismiss controls sit well
/// inside the viewport and are hittable.
const Size _kViewport = Size(400, 2400);

/// A registered signal whose card is fixed by the fixture (minimal `_StubSignal`
/// of `test/signals_layer_screen_test.dart`): it never abstains and never
/// waits, so one completed session is all the fixture needs.
class _StubSignal implements Signal {
  @override
  final String id;

  @override
  final SignalKind kind;

  @override
  final int priority = 10;

  @override
  final bool needsRatedWeeks = false;

  _StubSignal({
    required this.id,
    required this.kind,
  });

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: 'title $id',
      observation: 'observation $id',
    );
  }

  @override
  Future<String?> waitingFor(SignalContext context) async => null;
}

void main() {
  group('S-21391…S-21395 the dismiss message and its Undo', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      // One completed session, so the screen loads and the stub signals are
      // evaluated.
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
    });

    /// The store as the repository reads it back.
    Future<Map<String, int>> readStore() async => parseSignalDismissals(
          await repo.getPreferenceString(kSignalDismissalsKey),
        );

    /// Gives a store write started inside a test body a real event-loop turn
    /// (the Mock write still needs the loop), then a pump for whatever it
    /// scheduled after that.
    Future<void> settleStore(WidgetTester tester) async {
      for (var round = 0; round < 3; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    /// Presents the message and finishes its entrance: `showSnackBar`
    /// presents at the end of the current frame, so the entrance needs a
    /// second pump.
    Future<void> showMessage(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> pumpStats(
      WidgetTester tester, {
      required List<Signal> signals,
    }) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            signals: signals,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // ─── S-21391 ────────────────────────────────────────────────────────────

    testWidgets('S-21391 dismissing a card hides it and shows the hidden '
        'message with Undo', (tester) async {
      final positive = _StubSignal(id: 'p-1', kind: SignalKind.positive);
      await pumpStats(tester, signals: [positive]);
      expect(find.byKey(const Key('signal_card_p-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('signal_dismiss_p-1')));
      await showMessage(tester);

      expect(find.byKey(const Key('signal_card_p-1')), findsNothing);
      expect(find.text('Signal hidden for 14 days.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ─── S-21392 ────────────────────────────────────────────────────────────

    testWidgets('S-21392 Undo brings the card back and clears the store '
        'entry', (tester) async {
      final positive = _StubSignal(id: 'p-1', kind: SignalKind.positive);
      await pumpStats(tester, signals: [positive]);

      await tester.tap(find.byKey(const Key('signal_dismiss_p-1')));
      await showMessage(tester);

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(find.byKey(const Key('signal_card_p-1')), findsOneWidget);

      await settleStore(tester);
      final store = await readStore();
      expect(store.containsKey('p-1'), isFalse);
    });

    // ─── S-21393 ────────────────────────────────────────────────────────────

    testWidgets('S-21393 a second dismissal replaces the message and Undo '
        'restores only the newest dismissal', (tester) async {
      final caution = _StubSignal(id: 'c-1', kind: SignalKind.caution);
      final positive = _StubSignal(id: 'p-1', kind: SignalKind.positive);
      await pumpStats(tester, signals: [caution, positive]);

      await tester.tap(find.byKey(const Key('signal_dismiss_c-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('signal_card_c-1')), findsNothing);

      await tester.tap(find.byKey(const Key('signal_dismiss_p-1')));
      // The first message is exiting, so the second queues behind it; settle
      // both before counting.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signal_card_p-1')), findsNothing);
      expect(find.text('Signal hidden for 14 days.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(find.byKey(const Key('signal_card_p-1')), findsOneWidget);
      expect(find.byKey(const Key('signal_card_c-1')), findsNothing);

      await settleStore(tester);
      final store = await readStore();
      expect(store.containsKey('c-1'), isTrue);
      expect(store.containsKey('p-1'), isFalse);
    });

    // ─── S-21394 ────────────────────────────────────────────────────────────

    testWidgets('S-21394 an unanswered message times out and the dismissal '
        'stands', (tester) async {
      final positive = _StubSignal(id: 'p-1', kind: SignalKind.positive);
      await pumpStats(tester, signals: [positive]);

      await tester.tap(find.byKey(const Key('signal_dismiss_p-1')));
      await showMessage(tester);
      expect(find.text('Signal hidden for 14 days.'), findsOneWidget);

      // Never tapped: past the message's 6 seconds. The call site passes
      // `persist: false` (S-21396), so the bar leaves on its own.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      expect(find.text('Signal hidden for 14 days.'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(find.byKey(const Key('signal_card_p-1')), findsNothing);

      await settleStore(tester);
      final store = await readStore();
      expect(store.containsKey('p-1'), isTrue);
    });

    // ─── S-21395 ────────────────────────────────────────────────────────────

    testWidgets('S-21395 Undo still works after the Stats screen is popped', (
      tester,
    ) async {
      final positive = _StubSignal(id: 'p-1', kind: SignalKind.positive);
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StatsScreen(
                        workoutState: workoutState,
                        settingsState: settingsState,
                        signals: [positive],
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonBorderRadius,
                      ),
                    ),
                  ),
                  child: const Text('open stats'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open stats'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signal_card_p-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('signal_dismiss_p-1')));
      await showMessage(tester);
      expect(find.text('Signal hidden for 14 days.'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Signal hidden for 14 days.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();

      expect(tester.takeException(), isNull);

      await settleStore(tester);
      final store = await readStore();
      expect(store.containsKey('p-1'), isFalse);
    });
  });
}
