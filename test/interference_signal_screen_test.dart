// The Cross-Modality Interference card (Stats PR 7b, Phase 3) — the signal end
// to end.
//
// Scenario S-2013 of
// `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md`,
// on both repository implementations.
//
// The screen is given only this signal through the `signals:` seam, so a
// signal added later cannot change these scenarios. The signal itself, its
// window and its copy are the shipped ones — nothing about the signal is
// stubbed.
//
// F-INT is the plan's seeded fixture, re-anchored to the real clock: 8 rated
// sports sessions, 10 rated lifting sessions, 3 follow-up lifting sessions and
// 4 rated baseline sessions. The period-scoped window `[day(10), now]` holds
// the day-10 sports session, and the rated sessions behind it clear the Mix
// layer's rated-baseline gate that the Signals layer shares (D-1006).
//
// Every assertion names the Interference card by its key rather than counting
// cards. Interference has the highest caution priority, so it is the first card
// whenever it shows.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. S-2013's tap is the exception — it is
// Mock-only, because a Hive write started in a widget test's fake-async zone
// cannot drain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/interference.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/interference_signal.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
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

/// The card's key, the dismissal key and the store entry (D-1315).
const String _kCardKey = 'signal_card_cross-modality-interference';
const String _kDismissKey = 'signal_dismiss_cross-modality-interference';
const String _kSignalId = 'cross-modality-interference';

/// The kind label a caution card carries (D-1001).
const String _kCautionLabel = 'Worth a look';

/// F-INT's exact copy (S-2005, D-1312–D-1314), verbatim.
const String _kObservation =
    'After 3 of your last 3 hard sports sessions, your next lifting day came '
    'in 10\u201316% below your usual on the same lifts. Sports load is up 38% '
    'over the last 3 weeks.';
const String _kSuggestion =
    'A lighter or isometric-focused day after hard sports sessions is one '
    'option.';

// ─── F-INT ──────────────────────────────────────────────────────────────────

/// F-INT's rated sports sessions: `daysAgo: (rating, round seconds)`, the round
/// effort being the session's whole duration.
const Map<int, (int, int)> _sportsSessions = {
  88: (4, 60),
  80: (4, 120),
  70: (4, 180),
  60: (4, 300),
  44: (4, 360),
  30: (5, 600),
  20: (4, 420),
  10: (5, 492),
};

/// F-INT's rated lifting sessions, all one `ex-lift` set of 1 rep at 100 kg.
const List<int> _liftDays = [62, 55, 50, 40, 33, 26, 22, 12, 6, 2];

/// F-INT's follow-ups: `daysAgo: weight`, one `ex-lift` set of 1 rep.
const Map<int, double> _followUps = {29: 84.0, 19: 90.0, 9: 89.0};

/// The rated sessions that put the Mix layer on the load measure: 4 distinct
/// 7-calendar-day blocks before the window's start day (D-908). They carry no
/// efforts, so they cannot reach the rule.
const List<int> _baselineDays = [96, 110, 124, 138];

/// Local midnight of the day [daysAgo] days back.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// 09:00 local on `day(daysAgo)` — every fixture session starts there.
DateTime _at(int daysAgo) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, 9);
}

/// A session with an explicit start, end and rating, plus the one segment its
/// efforts hang on. The shared `seedSession` cannot express these: it
/// hard-codes a 60-minute non-rolling session and takes no rating.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required DateTime end,
  int? rating,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: end.millisecondsSinceEpoch,
      sessionFeeling: rating,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
}

/// A sports session whose single finished round effort is its whole duration,
/// so its time and load are Sports only.
Future<void> _seedSportsSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required int seconds,
  int? rating,
}) async {
  await _seedSession(
    repo,
    id: id,
    start: start,
    end: start.add(Duration(seconds: seconds)),
    rating: rating,
  );
  await seedExercise(repo, id: 'ex-$id', name: 'Sports');
  await seedRoundEffort(
    repo,
    segmentId: 'seg-$id',
    effortId: 'ef-$id',
    exerciseId: 'ex-$id',
    rounds: [roundInstance('ef-$id', 0, durationSecs: seconds)],
  );
}

/// A one-hour lifting session carrying one `ex-lift` set of 1 rep at
/// [weightKg].
Future<void> _seedLiftingSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required double weightKg,
  int? rating = 4,
}) async {
  await _seedSession(
    repo,
    id: id,
    start: start,
    end: start.add(const Duration(hours: 1)),
    rating: rating,
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$id',
    effortId: 'ef-$id',
    exerciseId: 'ex-lift',
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: weightKg,
    repsBase: 1,
  );
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

/// F-INT: the plan's seeded fixture, re-anchored to the real clock.
Future<void> _seedFInt(WorkoutRepository repo) async {
  await seedExercise(
    repo,
    id: 'ex-lift',
    name: 'Lift',
    capabilities: const ['load', 'reps'],
  );
  for (final entry in _sportsSessions.entries) {
    await _seedSportsSession(
      repo,
      id: 'sports-${entry.key}',
      start: _at(entry.key),
      seconds: entry.value.$2,
      rating: entry.value.$1,
    );
  }
  for (final day in _liftDays) {
    await _seedLiftingSession(
      repo,
      id: 'lift-$day',
      start: _at(day),
      weightKg: 100.0,
    );
  }
  for (final entry in _followUps.entries) {
    await _seedLiftingSession(
      repo,
      id: 'fu-${entry.key}',
      start: _at(entry.key),
      weightKg: entry.value,
    );
  }
  for (final day in _baselineDays) {
    await _seedSession(
      repo,
      id: 'base-$day',
      start: _at(day),
      end: _at(day).add(const Duration(hours: 1)),
      rating: 4,
    );
  }
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-1', daysAgo: 1);
  await _seedFood(repo, id: 'food-2', daysAgo: 2);
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

    group('Cross-Modality Interference signal — ${harness.name}', () {
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
              signals: const [InterferenceSignal()],
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

      // ─── stage (a): the seeded history makes the rule fire ────────────────

      // The screen fixture's own precondition, asserted at the service level
      // first: the walk over F-INT must hand the rule the plan's pinned counts
      // and range (S-2005). If this fails, the seeding is wrong, not the card.
      test('S-2013 the seeded history makes the rule fire', () async {
        await _seedFInt(repo);

        final service = StatsProgressService(repo);
        final result = crossModalityInterference(
          sessions: await service.interferenceSessions(),
          now: DateTime.now(),
        );

        expect(result, isNotNull);
        expect(result!.k, 3);
        expect(result.n, 3);
        expect(result.lo, 10);
        expect(result.hi, 16);
        expect(result.hasSportsLoadRise, isTrue);
        expect(result.sportsLoadRisePercent, 38);
      });

      // ─── S-2013 ────────────────────────────────────────────────────────────

      group('S-2013 the card on the layer', () {
        setUp(() => _seedFInt(repo));

        testWidgets('the caution card shows with the exact copy, the caution '
            'label and its key, below the Mix layer', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key(_kCardKey)),
              matching: find.text(_kCautionLabel),
            ),
            findsOneWidget,
          );
          expect(find.text(_kObservation), findsOneWidget);
          expect(find.text(_kSuggestion), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);

          // Interference has the highest caution priority, so it is the first
          // card whenever it shows (D-1315).
          expect(_cardKeys().first, _kCardKey);

          // The layer sits in its slot, under the Mix layer and above ALL
          // TIME, and the card is inside it.
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
            tester.getTopLeft(find.byKey(const Key(_kCardKey))).dy,
            greaterThan(tester.getTopLeft(find.text('SIGNALS')).dy),
          );

          // The blocks below are undisturbed.
          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(find.byKey(const Key('all_time_card')), findsOneWidget);
          expect(find.byKey(const Key('fuel_section')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2013, the dismissal ─────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level
      // round trip (S-1712 in `test/signals_service_test.dart`); the
      // screen-level behaviour asserted here — the card gone in the frame
      // after the tap, and still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-2013 the card is dismissible', () {
          setUp(() => _seedFInt(repo));

          testWidgets('one tap removes the card in the tap frame, the store '
              'holds the id, and the next open still hides it', (tester) async {
            await pumpStats(tester);
            expect(find.byKey(const Key(_kCardKey)), findsOneWidget);

            final dismiss = find.byKey(const Key(_kDismissKey));
            expect(dismiss, findsOneWidget);
            expect(tester.widget<IconButton>(dismiss).tooltip, 'Dismiss signal');

            await tester.tap(dismiss);

            // The view moves in the tap's own frame, before the write settles
            // (D-1010).
            await tester.pump();
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);

            await settleStore(tester);
            final store = await _readDismissals(repo);
            expect(store[_kSignalId], isA<int>());

            await reopen(tester);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          });
        });
      }
    });
  }
}
