// The Fuel vs Load card (Stats PR 8a, Phase 3) — the signal end to end.
//
// Scenario S-2113 (the card on the layer, and its dismissal) and S-2111 at the
// screen (a period measuring time suppresses the card) of
// `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md`,
// on both repository implementations.
//
// The card is produced by the app's real registry (`buildSignalRegistry()`),
// which the screen falls back to when no `signals:` seam is passed, so this
// file exercises the shipped signal, the shipped 21-day period walk and the
// shipped copy — nothing here is stubbed.
//
// F-FUEL has to satisfy four things at once: the Mix layer's rated-baseline
// gate for the Stats window (>= 4 rated blocks, so the layer renders), the
// signal's own measure gate on BOTH 21-day periods (load, not time), the
// six-block consistency gate over the 42 logged days, and a load rise of at
// least 20% with an intake rise inside the 5% tolerance. The arithmetic is in
// the plan's evidence file; the fixture comments below carry the figures each
// block contributes.
//
// The window is period-scoped over `day(20)`…today — the same bounds as the
// signal's own recent period — so the window's payload and the recent period's
// payload are the same figures, and the rated baseline blocks the window needs
// are the ones the recent period needs.
//
// The real registry also holds Progression Rate, Modality Mix Shift and
// Interference, so every assertion here names the Fuel vs Load card by its key
// rather than counting cards. None of the other three qualifies in F-FUEL:
// every effort is a `set` (no Sports time for Interference), both Mix bars are
// 100% Resistance (nothing for Mix Shift to report), and every session carries
// a unique exercise id, so each exercise has one progression sample and
// Progression Rate counts nothing.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. S-2113's tap is the exception — it is
// Mock-only, because a Hive write started in a widget test's fake-async zone
// cannot drain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/fuel_vs_load.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/fuel_vs_load_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
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

/// The card's key, the dismissal key and the store entry (D-1415).
const String _kCardKey = 'signal_card_fuel-vs-load';
const String _kDismissKey = 'signal_dismiss_fuel-vs-load';
const String _kSignalId = 'fuel-vs-load';

/// The kind label a caution card carries (D-1001).
const String _kCautionLabel = 'Worth a look';

/// The card's copy for F-FUEL: load up 25% (1250 against 1000) and intake up
/// 2% (2040 against 2000) (D-1412, D-1413).
const String _kObservation =
    'Training load is up 25% over the last 3 weeks; your average daily intake '
    'has not risen with it.';
const String _kSuggestion =
    'Worth checking that intake is keeping up with training.';

/// The calories F-FUEL logs on each of the recent 21 days, and on each of the
/// prior 21 (S-2101).
const int _kRecentCalories = 2040;
const int _kPriorCalories = 2000;

// ─── F-FUEL ─────────────────────────────────────────────────────────────────

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

/// One completed session with one segment, written directly because the shared
/// `seedSession` cannot express a rating. A null [rating] is an unrated
/// session, whose time counts against the Mix layer's rated share.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required int? rating,
  int minutes = 50,
}) async {
  final start = _at(daysAgo, 9);
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + minutes * 60000,
      sessionFeeling: rating,
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

/// A `set` effort on [sessionId] — resistance load, and the effort kind that
/// measures no time at all (D-902), so the session's whole duration is its
/// Resistance time and its load is `minutes × rating`.
///
/// The exercise id is unique to the session, so no exercise ever has two
/// progression samples and Progression Rate stays silent.
Future<void> _seedSetEffort(
  WorkoutRepository repo, {
  required String sessionId,
}) async {
  final exerciseId = 'ex-squat-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-set',
    exerciseId: exerciseId,
    entryCount: 3,
    hasExtraWeight: false,
    weightFactor: 100.0,
    repsBase: 5,
  );
}

/// A training period from [daysAgo] to the end of today, named [name].
///
/// `resolveWindow` prefers it over the recency fallback, which is what keeps
/// the window's start at `day(20)` — the same day the signal's own recent
/// period starts on.
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

/// One logged `ConsumedFood` on the local day [daysAgo] days back carrying
/// [calories].
///
/// `caloriesConsumed` is `protein × 4 + carbs × 4 + fat × 9` scaled by
/// `amountConsumed / referenceAmount`, which is 1 here, so the macros below
/// are the calorie figure exactly: 4 × (protein + carbs).
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required int calories,
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
      protein: (calories ~/ 20).toDouble(),
      carbs: (calories ~/ 5).toDouble(),
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

/// The load history every F-FUEL variant shares: five rated sessions in the
/// prior period (1000 load minutes), five in the recent one (1250), and four
/// rated sessions in the older blocks each period's own baseline reads.
///
/// A period's baseline is the twelve 7-day blocks before its own start day, so
/// the prior period (starting `day(41)`) reads days 42…125 and the window and
/// recent period (starting `day(20)`) read days 21…104. The five prior-period
/// sessions rate three of the recent period's blocks; these four rate one block
/// each of the older span, so both periods clear the Mix layer's four-rated-week
/// gate (D-1407, D-1203).
Future<void> _seedLoad(WorkoutRepository repo) async {
  // Prior period `[day(41), day(20) − 1 ms]`: 5 × (50 min × 4) = 1000.
  for (final days in [41, 36, 31, 26, 21]) {
    final id = 'ffuel-prior-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 4);
    await _seedSetEffort(repo, sessionId: id);
  }

  // Recent period `[day(20), now]`: 5 × (50 min × 5) = 1250.
  for (final days in [20, 16, 12, 8, 4]) {
    final id = 'ffuel-recent-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 5);
    await _seedSetEffort(repo, sessionId: id);
  }

  // One rated session in each of four older baseline blocks, all before the
  // prior period's start (`day(41)`) so they add no load to either period: the
  // blocks `[48…42]`, `[62…56]`, `[76…70]` and `[90…84]`.
  for (final days in [48, 62, 76, 90]) {
    final id = 'ffuel-base-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 4);
    await _seedSetEffort(repo, sessionId: id);
  }
}

/// The 42 logged days of S-2101 — every day from `day(41)` to `day(0)` — so
/// each of the six gate blocks holds 7 of 7.
Future<void> _seedFoodLog(WorkoutRepository repo) async {
  for (var daysAgo = 41; daysAgo >= 21; daysAgo--) {
    await _seedFood(
      repo,
      id: 'food-prior-$daysAgo',
      daysAgo: daysAgo,
      calories: _kPriorCalories,
    );
  }
  for (var daysAgo = 20; daysAgo >= 0; daysAgo--) {
    await _seedFood(
      repo,
      id: 'food-recent-$daysAgo',
      daysAgo: daysAgo,
      calories: _kRecentCalories,
    );
  }
}

/// F-FUEL: the load history, the period-scoped window and the 42 logged days.
Future<void> _seedFFuel(WorkoutRepository repo) async {
  await _seedLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  await _seedFoodLog(repo);
}

/// F-NOFOOD: F-FUEL's load and window, with the food log left empty. The
/// consistency gate finds 0 of 7 in every block, so the rule abstains while the
/// layer still renders.
Future<void> _seedFNoFood(WorkoutRepository repo) async {
  await _seedLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
}

/// F-TIME21: F-FUEL plus one unrated 100-minute session inside the recent
/// period, so that period's unrated time share is `6000 / 21000 = 0.286 > 0.25`
/// and the Mix layer measures it in time (S-2111).
///
/// The session is unrated, so it adds no load: the load figures stay 1250 and
/// 1000, and the rated baseline is untouched — only the measure changes.
Future<void> _seedFTime21(WorkoutRepository repo) async {
  await _seedFFuel(repo);
  await _seedSession(
    repo,
    sessionId: 'ftime-unrated',
    daysAgo: 2,
    rating: null,
    minutes: 100,
  );
  await _seedSetEffort(repo, sessionId: 'ftime-unrated');
}

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Fuel vs Load signal — ${harness.name}', () {
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

      /// Pumps the Stats screen with no `signals:` seam, so the layer evaluates
      /// the app's real registry.
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
              signals: const [FuelVsLoadSignal()],
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

      // ─── S-2113 ────────────────────────────────────────────────────────────

      group('S-2113 the card on the layer', () {
        setUp(() => _seedFFuel(repo));

        testWidgets('the caution card shows with the exact copy, the caution '
            'label and its key, below the Mix layer', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kCautionLabel), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text(_kObservation), findsOneWidget);
          expect(find.text(_kSuggestion), findsOneWidget);

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

      // ─── S-2113, the dismissal ─────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level
      // round trip (S-1712 in `test/signals_service_test.dart`); the
      // screen-level behaviour asserted here — the card gone in the frame
      // after the tap, and still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-2113 the card is dismissible', () {
          setUp(() => _seedFFuel(repo));

          testWidgets('one tap removes the card in the tap frame, the store '
              'holds the id, and the next open is still quiet', (tester) async {
            await pumpStats(tester);
            expect(find.byKey(const Key(_kCardKey)), findsOneWidget);

            final dismiss = find.byKey(const Key(_kDismissKey));
            expect(dismiss, findsOneWidget);
            expect(
              tester.widget<IconButton>(dismiss).tooltip,
              'Dismiss signal',
            );

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

      // ─── the gate: no food, and a period that measures time ────────────────

      group('the rule abstains', () {
        group('an empty food log', () {
          setUp(() => _seedFNoFood(repo));

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(find.text(_kCautionLabel), findsNothing);
          });
        });

        group('a period the Mix layer measures in time', () {
          setUp(() => _seedFTime21(repo));

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(find.text(_kCautionLabel), findsNothing);
          });
        });
      });

      // ─── the adapter ───────────────────────────────────────────────────────

      // D-1415: the card's identity — the id, the kind, the priority and the
      // title — is the adapter's, and the copy comes from the pure builder.
      group('the adapter', () {
        setUp(() => _seedFFuel(repo));

        test(
          'proposes the card with its own identity and the rule\'s copy',
          () async {
            final now = DateTime.now();
            final card = await const FuelVsLoadSignal().evaluate(
              SignalContext(
                now: now,
                window: StatsWindow(
                  fromMs: _day(20),
                  toMs: now,
                  label: 'Test window',
                  isPeriodScoped: false,
                ),
                mix: null,
                progressService: StatsProgressService(repo),
                repository: repo,
              ),
            );

            expect(card, isNotNull);
            expect(card!.id, _kSignalId);
            expect(card.kind, SignalKind.caution);
            expect(card.priority, kFuelVsLoadPriority);
            expect(card.title, 'Fuel vs load');
            expect(card.observation, _kObservation);
            expect(card.suggestion, _kSuggestion);
          },
        );
      });
    });
  }
}
