// The Progression Rate card (Stats PR 6b, Phase 2) — the signal end to end.
//
// Scenarios S-1801, S-1812 and S-1813 of
// `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.md`,
// on both repository implementations.
//
// The screen is given only this signal through the `signals:` seam, so a
// signal added later cannot change these scenarios. The signal itself, its
// window and its copy are the shipped ones — nothing about the signal is
// stubbed.
//
// F-PR is the plan's nine-session fixture. Its sessions carry a rating, so the
// weeks behind the window meet the Mix layer's rated-baseline gate that the
// Signals layer shares (D-1006): a period-scoped window holds the day-5
// session, and the day-12…61 sessions are the rated baseline.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. S-1812's second seed and S-1813's tap are
// the exceptions — both are documented where they appear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/progression_rate_signal.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block below the Signals layer is laid out, so an
/// assertion on a block's presence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// The observation and the suggestion the plan pins (D-1109), verbatim.
const String _kFprObservation =
    'Resistance progression rate is 80% over the last 4 weeks, up from 65%.';
const String _kFprSuggestion = 'The current approach is working.';

// ─── F-PR ───────────────────────────────────────────────────────────────────

/// F-PR's nine sessions, in the order the plan's table lists them.
const List<int> _kFprDays = [61, 54, 47, 40, 33, 26, 19, 12, 5];

/// F-PR's weights per exercise, one rep per set, so the estimated 1RM is
/// monotone in the weight.
const Map<String, List<double>> _kFprWeights = {
  'ex-a': [100, 110, 120, 130, 140, 150, 160, 170, 180],
  'ex-b': [200, 210, 220, 215, 230, 240, 250, 245, 260],
  'ex-c': [300, 310, 305, 320, 330, 340, 335, 350, 360],
  'ex-d': [400, 410, 405, 420, 415, 430, 425, 440, 450],
  'ex-e': [500, 510, 505, 500, 495, 520, 515, 530, 540],
};

/// The rating every F-PR session carries, so the baseline weeks behind the
/// window are rated enough for the gate.
const int _kFprRating = 4;

/// Local midnight of the day [daysAgo] days back.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// [daysAgo]'s day at [hour] o'clock, in epoch ms.
int _at(int daysAgo, int hour) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
}

/// One completed, rated session with one segment, written directly because the
/// shared `seedSession` cannot express a rating.
Future<void> _seedRatedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  String? modality,
}) async {
  final start = _at(daysAgo, 9);
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + 3600000,
      sessionFeeling: _kFprRating,
      modality: modality,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

/// F-PR: nine rated sessions carrying all five exercises, plus the
/// period-scoped window whose rated baseline meets the gate.
Future<void> _seedFpr(WorkoutRepository repo) async {
  for (final id in _kFprWeights.keys) {
    await seedExercise(
      repo,
      id: id,
      name: id,
      capabilities: const ['load', 'reps'],
    );
  }
  for (var i = 0; i < _kFprDays.length; i++) {
    final day = _kFprDays[i];
    await _seedRatedSession(
      repo,
      sessionId: 'fpr-s$day',
      daysAgo: day,
      modality: 'resistance',
    );
    for (final entry in _kFprWeights.entries) {
      await seedSetEffort(
        repo,
        segmentId: 'seg-fpr-s$day',
        effortId: 'fpr-e$day-${entry.key}',
        exerciseId: entry.key,
        entryCount: 1,
        hasExtraWeight: false,
        weightFactor: entry.value[i],
      );
    }
  }
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-1', daysAgo: 1);
  await _seedFood(repo, id: 'food-2', daysAgo: 2);
}

/// Three further recent ex-a sessions, each lighter than the one before, so the
/// recent rate falls under `kProgressionRateMinRate` (S-1812).
Future<void> _seedFallingSessions(WorkoutRepository repo) async {
  const days = [3, 2, 1];
  const weights = [100.0, 90.0, 80.0];
  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    await _seedRatedSession(
      repo,
      sessionId: 'fpr-s$day',
      daysAgo: day,
      modality: 'resistance',
    );
    await seedSetEffort(
      repo,
      segmentId: 'seg-fpr-s$day',
      effortId: 'fpr-e$day-ex-a',
      exerciseId: 'ex-a',
      entryCount: 1,
      hasExtraWeight: false,
      weightFactor: weights[i],
    );
  }
}

/// A training period from [daysAgo] to the end of today, named [name].
///
/// `resolveWindow` prefers it over the recency fallback, which is what keeps
/// the baseline sessions outside the window.
Future<void> _seedPeriod(
  WorkoutRepository repo, {
  required String name,
  required int daysAgo,
}) async {
  final start = _day(daysAgo);
  final now = DateTime.now();
  await repo.createPeriod(
    TrainingPeriod(
      id: 'period-1',
      ownerUserId: 'user-1',
      name: name,
      startDateMs: start.millisecondsSinceEpoch,
      endDateMs: DateTime(
        now.year,
        now.month,
        now.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch,
      focusModalities: const [],
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    ),
  );
}

/// The repository's food log, emptied: the Mock harness opens with
/// `SeedData.sampleConsumedFoods()` already written, the Hive harness empty.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back, so the Fuel
/// row renders below the Instruments list.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
}) async {
  final dateMs = _day(daysAgo).millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: id,
      name: id,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 100,
      carbs: 400,
      fiber: 0,
      fat: 0,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 0,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

/// Every card key on screen, in document order.
List<String> _cardKeys() {
  final keys = <String>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'signal_card_',
                ),
          )
          .evaluate()) {
    keys.add((element.widget.key! as ValueKey<String>).value);
  }
  return keys;
}

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Progression Rate signal — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
      });

      tearDown(() async {
        await harness.close();
      });

      /// Pumps the Stats screen with only this signal injected through the
      /// `signals:` seam.
      Future<void> pumpStats(
        WidgetTester tester, {
        Size size = _kTallViewport,
      }) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
              signals: const [ProgressionRateSignal()],
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      /// Rebuilds the screen from scratch, so a second load really happens.
      Future<void> reopen(WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await pumpStats(tester);
      }

      /// Gives a repository write started inside a test body a real
      /// event-loop turn (see `test/signals_layer_screen_test.dart`).
      Future<void> settleStore(WidgetTester tester) async {
        for (var round = 0; round < 3; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      // ─── S-1801 ────────────────────────────────────────────────────────────

      group('S-1801 the card, end to end', () {
        setUp(() => _seedFpr(repo));

        testWidgets('the real card shows with the exact copy, the Positive '
            'label and its key, and no quiet line', (tester) async {
          await pumpStats(tester);

          expect(_cardKeys(), ['signal_card_progression-rate']);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text('Positive'), findsOneWidget);
          expect(find.text(_kFprObservation), findsOneWidget);
          expect(find.text(_kFprSuggestion), findsOneWidget);

          // The layer sits in its slot, under the Mix layer and above ALL
          // TIME, and the card is the layer's top card.
          final signalsTop = tester
              .getTopLeft(find.byKey(const Key('signals_layer')))
              .dy;
          expect(
            signalsTop,
            greaterThan(
              tester.getTopLeft(find.byKey(const Key('mix_layer'))).dy,
            ),
          );
          expect(
            signalsTop,
            lessThan(tester.getTopLeft(find.text('ALL TIME')).dy),
          );
          expect(
            tester
                .getTopLeft(find.byKey(const Key('signal_card_progression-rate')))
                .dy,
            greaterThan(tester.getTopLeft(find.text('SIGNALS')).dy),
          );

          // The blocks below are undisturbed.
          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(find.byKey(const Key('all_time_card')), findsOneWidget);
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.byKey(const Key('fuel_section')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1812 ────────────────────────────────────────────────────────────

      group('S-1812 the card disappears when the condition clears', () {
        setUp(() => _seedFpr(repo));

        testWidgets('the card shows, three falling sessions drop the recent '
            'rate, and the second open shows the quiet line', (tester) async {
          await pumpStats(tester);
          expect(_cardKeys(), ['signal_card_progression-rate']);

          // The extra sessions run outside the fake clock: Hive's file I/O
          // never settles under `FakeAsync`.
          await tester.runAsync(() => _seedFallingSessions(repo));
          await reopen(tester);

          expect(_cardKeys(), isEmpty);
          expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
        });
      });

      // ─── S-1813 ────────────────────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level
      // round trip (S-1712 in `test/signals_service_test.dart`); the
      // screen-level behaviour asserted here — the card gone in the frame
      // after the tap, and still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-1813 the real card is dismissible', () {
          setUp(() => _seedFpr(repo));

          testWidgets('one tap removes the card in the tap frame, the store '
              'holds the id, and the next open is still quiet', (tester) async {
            await pumpStats(tester);
            expect(_cardKeys(), ['signal_card_progression-rate']);

            final dismiss = find.byKey(
              const Key('signal_dismiss_progression-rate'),
            );
            expect(dismiss, findsOneWidget);
            expect(tester.widget<IconButton>(dismiss).tooltip, 'Dismiss signal');

            await tester.tap(dismiss);

            // The view moves in the tap's own frame, before the write settles
            // (D-1010).
            await tester.pump();
            expect(
              find.byKey(const Key('signal_card_progression-rate')),
              findsNothing,
            );
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);

            await settleStore(tester);
            final store = await _readDismissals(repo);
            expect(store['progression-rate'], isA<int>());

            await reopen(tester);
            expect(_cardKeys(), isEmpty);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          });
        });
      }
    });
  }
}
