// The Sustained High Load card (Stats PR 9a, Phase 3A) — the signal end to end.
//
// Scenario S-2412 (the card on the layer, two cautions qualifying, and its
// dismissal) and the adapter half of S-2410(b) of
// `docs/plans/2026-10-04-09a-stats-pr9a-sustained-high-load-plan/2026-10-04-09a-stats-pr9a-sustained-high-load-plan.md`,
// on both repository implementations.
//
// The card is produced by the app's real registry (`buildSignalRegistry()`),
// which the screen falls back to when no `signals:` seam is passed, so this file
// exercises the shipped signal, the shipped Mix gate and the shipped copy —
// nothing here is stubbed.
//
// The fixtures are anchored to the real clock, not a fixed `now`: the weeks are
// the user's own calendar weeks, so each week is built as `startOfWeek(now)`
// minus seven days per week back and its session sits mid-week (start + 3 days,
// 09:00), which keeps it strictly inside its completed week whatever weekday the
// suite runs on. The arithmetic is the plan's own — ten rated weeks at
// `L = 240` (60 min × 4), two adjacent empty weeks, five at `L = 230`
// (46 min × 5) — and the sessions carry no efforts, so each week's load is
// exactly `minutes × rating` and no other signal sees an exercise or a modality.
//
// S-2412's plan text expects two qualifying cautions "in ascending priority
// (Sustained High Load first)", which the shipped `resolveSignals` cannot
// produce: it sorts a kind by priority *descending*, so Protein Consistency
// (200) renders above Sustained High Load (100). Framework files are frozen, so
// this file pins the reachable contract and the finding is logged in the plan's
// Assumption Log. Do not "fix" the test to match the plan.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. The dismissal is Mock-only for the same
// reason — a Hive write started in a widget test's fake-async zone cannot drain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/sustained_high_load.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/signals/protein_consistency_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals/sustained_high_load_signal.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
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

/// The card's key, the dismissal key and the store entry (D-1713).
const String _kCardKey = 'signal_card_sustained-high-load';
const String _kDismissKey = 'signal_dismiss_sustained-high-load';
const String _kSignalId = 'sustained-high-load';

/// The kind label a caution card carries (D-1001).
const String _kCautionLabel = 'Worth a look';

/// The Protein Consistency card's key, for S-2412's two-caution variant.
const String _kProteinCardKey = 'signal_card_protein-consistency';

/// S-2401's copy: five weeks, no easier week in the history, so no second
/// sentence (D-1712).
const String _kObservation =
    "You've had 5 consecutive weeks above your usual training load, with no "
    'easier week.';
const String _kSuggestion = 'An easier week is one option.';

// ─── calendar anchors ───────────────────────────────────────────────────────

/// Local midnight of the start of the week [weeksAgo] weeks before this week.
DateTime _weekStart(int weeksAgo) {
  final now = DateTime.now();
  final current = OmniDateUtils.startOfWeek(now, startOfWeek: 'monday');
  return DateTime(current.year, current.month, current.day - 7 * weeksAgo);
}

/// The epoch ms of the session slot in the week [weeksAgo] weeks back: three
/// days into the week, 09:00. Mid-week, so the session is never near a week
/// boundary and never after `now`.
int _atWeek(int weeksAgo) {
  final start = _weekStart(weeksAgo);
  return DateTime(start.year, start.month, start.day + 3, 9)
      .millisecondsSinceEpoch;
}

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

// ─── load fixtures ──────────────────────────────────────────────────────────

/// One completed session of [minutes] in the week [weeksAgo] weeks back, rated
/// [rating]. A null [rating] is an unrated session, whose time counts against
/// the Mix layer's rated share.
///
/// The session has a segment and no efforts: the shared split gives the whole
/// duration to Resistance, so its load is exactly `minutes × rating`.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required int weeksAgo,
  required int minutes,
  required int? rating,
}) async {
  final start = _atWeek(weeksAgo);
  await repo.createSession(
    TrainingSession(
      id: id,
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
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

/// A `set` effort on [sessionId] — a resistance session for the Protein
/// Consistency rule's own gate, and the effort kind that measures no time at
/// all (D-902), so the session's load is unchanged.
///
/// The exercise id is unique to the session, so no exercise ever has two
/// progression samples and Progression Rate stays silent.
Future<void> _seedResistanceEffort(
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

/// A rated resistance session on the local day [daysAgo] days back, carrying a
/// `set` effort so it counts for the Protein Consistency rule's resistance gate.
///
/// Its own exercise id is unique, so Progression Rate stays silent.
Future<void> _seedResistanceSession(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  int minutes = 40,
  int rating = 4,
}) async {
  final start = _at(daysAgo, 9);
  await repo.createSession(
    TrainingSession(
      id: id,
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
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await _seedResistanceEffort(repo, sessionId: id);
}

/// A training period from [daysAgo] to the end of today, named [name].
///
/// `resolveWindow` prefers it over the recency fallback, which is what keeps the
/// window's start at `day(20)` and so lets the Mix layer render above the
/// Signals layer.
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

/// F-9A (S-2401): seventeen completed calendar weeks, oldest first — ten at
/// `L = 240` (60 min × 4), two adjacent empty weeks, then five at `L = 230`
/// (46 min × 5).
///
/// The streak's baseline is `W1…W12`, summed 2400, so the usual is `200` and the
/// five streak weeks clear `230 × 100 >= 200 × 110`. The two adjacent empty
/// baseline weeks are the history's only easier weeks, which is one gap — below
/// the two-gap floor, so the copy carries no second sentence (S-2409 A).
Future<void> _seedF9A(WorkoutRepository repo) async {
  for (var k = 1; k <= 17; k++) {
    final weeksAgo = 18 - k;
    if (k <= 10) {
      await _seedSession(
        repo,
        id: 'w$k',
        weeksAgo: weeksAgo,
        minutes: 60,
        rating: 4,
      );
    } else if (k >= 13) {
      await _seedSession(
        repo,
        id: 'w$k',
        weeksAgo: weeksAgo,
        minutes: 46,
        rating: 5,
      );
    }
  }
}

/// F-FLAT: a history with no higher-load run — `W1…W12` at `L = 240` and
/// `W13…W17` at `L = 200` (50 min × 4). Every candidate's usual is at or above
/// 200, so no week reaches 110% of it and the rule abstains.
Future<void> _seedFFlat(WorkoutRepository repo) async {
  for (var k = 1; k <= 17; k++) {
    await _seedSession(
      repo,
      id: 'w$k',
      weeksAgo: 18 - k,
      minutes: k <= 12 ? 60 : 50,
      rating: 4,
    );
  }
}

/// F-MIXTIME (S-2410(b)): S-2401's shape with the streak block at `L = 240` and
/// a 300-minute unrated session beside each of the five streak weeks.
///
/// The streak still qualifies at rule level — baseline `W1…W12` sums 2400,
/// usual `200`, every streak week `240 × 100 >= 200 × 110` — but the streak
/// period's unrated share is `300 ÷ 360 = 0.83`, above
/// `kTrainingLoadMaxUnratedShare`, so `computeMixPeriod` measures it in time and
/// the adapter must abstain.
Future<void> _seedFMixTime(WorkoutRepository repo) async {
  for (var k = 1; k <= 17; k++) {
    if (k == 11 || k == 12) continue;
    final weeksAgo = 18 - k;
    await _seedSession(
      repo,
      id: 'w$k',
      weeksAgo: weeksAgo,
      minutes: 60,
      rating: 4,
    );
    if (k >= 13) {
      await _seedSession(
        repo,
        id: 'w$k-unrated',
        weeksAgo: weeksAgo,
        minutes: 300,
        rating: null,
      );
    }
  }
}

// ─── food fixtures ──────────────────────────────────────────────────────────

/// The repository's food log, emptied: the Mock harness opens with
/// `SeedData.sampleConsumedFoods()` already written, the Hive harness empty.
/// Every fixture here clears it, so no signal reads a nutrition row it did not
/// seed.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back carrying
/// [protein] grams and [calories] kcal.
///
/// `caloriesConsumed` is `protein × 4 + carbs × 4 + fat × 9` scaled by
/// `amountConsumed / referenceAmount`, which is 1 here, so the carbs below make
/// the calorie figure exact: `4 × (protein + carbs) == calories`.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required int protein,
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
      protein: protein.toDouble(),
      carbs: (calories / 4 - protein).toDouble(),
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

/// The Protein Consistency rule's 14-day window logged at [protein] grams a day:
/// `day(13)`…`day(2)`, twelve logged days against the `>= 10` gate.
Future<void> _seedWindowFood(
  WorkoutRepository repo, {
  required String prefix,
  required int protein,
  required int calories,
}) async {
  for (var daysAgo = 13; daysAgo >= 2; daysAgo--) {
    await _seedFood(
      repo,
      id: '$prefix-$daysAgo',
      daysAgo: daysAgo,
      protein: protein,
      calories: calories,
    );
  }
}

/// The stored protein target [protein] grams from `day(13)` on: the repository
/// walks backward for the most recent ancestor, so the whole window inherits it.
Future<void> _seedWindowTarget(
  WorkoutRepository repo, {
  required double protein,
}) => repo.saveNutritionTargetForDate(
  _day(13).millisecondsSinceEpoch,
  NutritionTarget(calories: 2000, protein: protein, carbs: 250, fat: 70),
);

// ─── composed fixtures ──────────────────────────────────────────────────────

/// F-CARD (S-2412): F-9A's seventeen weeks, the period-scoped window and an
/// empty food log, so Sustained High Load is the only signal that qualifies.
Future<void> _seedFCard(WorkoutRepository repo) async {
  await _seedF9A(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
}

/// F-TWO (S-2412, two cautions): F-CARD plus a qualifying Protein Consistency —
/// two resistance sessions inside the rule's own 14-day window (`W16`, `W17`)
/// and twelve window days at 120 g against a 150 g target, which is 20% under
/// (`20 × 1440 = 28,800 <= 17 × 2100 = 35,700`).
Future<void> _seedFTwo(WorkoutRepository repo) async {
  await _seedF9A(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  // Two resistance sessions inside the rule's own 14-day window, each on its
  // own exercise so Progression Rate sees no repeated sample. Days 13 and 7
  // back are always inside that window and always inside `W16`/`W17`, never
  // the current incomplete week, so the weekly loads above are unchanged.
  await _seedResistanceSession(repo, id: 'resist-13', daysAgo: 13);
  await _seedResistanceSession(repo, id: 'resist-7', daysAgo: 7);
  await _seedWindowFood(repo, prefix: 'ftwo', protein: 120, calories: 2040);
  await _seedWindowTarget(repo, protein: 150);
}

/// F-FLATWINDOW (the rule abstains): F-FLAT plus the period-scoped window and an
/// empty food log, so the layer renders with a history that holds no run.
Future<void> _seedFFlatWindow(WorkoutRepository repo) async {
  await _seedFFlat(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
}

/// F-MIXTIMEWINDOW (S-2410(b)): F-MIXTIME plus the period-scoped window and an
/// empty food log.
Future<void> _seedFMixTimeWindow(WorkoutRepository repo) async {
  await _seedFMixTime(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
}

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Sustained High Load signal — ${harness.name}', () {
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
        List<Signal>? signals = const [SustainedHighLoadSignal()],
      }) async {
        await tester.binding.setSurfaceSize(size);
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

      /// Rebuilds the screen from scratch, so a second load really happens.
      Future<void> reopen(
        WidgetTester tester, {
        List<Signal>? signals = const [SustainedHighLoadSignal()],
      }) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await pumpStats(tester, signals: signals);
      }

      /// Gives a repository write started inside a test body a real event-loop
      /// turn (see `test/signals_layer_screen_test.dart`).
      Future<void> settleStore(WidgetTester tester) async {
        for (var round = 0; round < 3; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      // ─── S-2412, the card on the layer ────────────────────────────────────

      group('S-2412 the card on the layer', () {
        setUp(() => _seedFCard(repo));

        testWidgets('the caution card shows with S-2401\'s copy, the caution '
            'label and its key, below the Mix layer', (tester) async {
          await pumpStats(
            tester,
            signals: const [SustainedHighLoadSignal(), ProteinConsistencySignal()],
          );

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kCautionLabel), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text(_kObservation), findsOneWidget);
          expect(find.text(_kSuggestion), findsOneWidget);

          // The history holds no effort and no modality, so no other signal can
          // qualify: this fixture isolates the Sustained High Load card.
          expect(
            find.byKey(const Key(_kProteinCardKey)),
            findsNothing,
          );

          // The layer sits in its slot, under the Mix layer and above ALL TIME,
          // and the card is inside it.
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
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2412, two cautions qualifying ──────────────────────────────────

      group('S-2412 two cautions qualifying', () {
        setUp(() => _seedFTwo(repo));

        testWidgets('renders the higher-priority caution above the Sustained '
            'High Load card', (tester) async {
          await pumpStats(
            tester,
            signals: const [SustainedHighLoadSignal(), ProteinConsistencySignal()],
          );

          // Both cautions qualify. The framework sorts a kind by priority
          // descending, so the layer carries Protein Consistency (200) above
          // Sustained High Load (100) — the plan's "ascending priority" text is
          // a defect, logged in the plan's Assumption Log.
          final protein = find.byKey(const Key(_kProteinCardKey));
          expect(protein, findsOneWidget);
          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(
            tester.getTopLeft(protein).dy,
            lessThan(tester.getTopLeft(find.byKey(const Key(_kCardKey))).dy),
          );
          expect(find.text(_kObservation), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2412, the dismissal ────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level round
      // trip (S-1712 in `test/signals_service_test.dart`); the screen-level
      // behaviour asserted here — the card gone in the frame after the tap, and
      // still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-2412 the card is dismissible', () {
          setUp(() => _seedFCard(repo));

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

      // ─── S-2410(b), the Mix gate at adapter level ─────────────────────────

      group('S-2410(b) the streak period measures time', () {
        setUp(() => _seedFMixTimeWindow(repo));

        test('the rule qualifies but the period the adapter reads is time', () async {
          final now = DateTime.now();
          final service = StatsProgressService(repo);

          final weeks = await service.weeklyLoads(now: now);
          final streak = sustainedHighLoadStreak(weeks: weeks);
          expect(streak.weekCount, 5);
          expect(streak.usualLoadMinutes, 200.0);
          expect(streak.ratedBaselineWeeks, 10);
          expect(
            sustainedHighLoad(weeks: weeks, mixShowsLoad: true),
            isNotNull,
          );

          final period = await service.computeMixPeriod(
            fromMs: streak.firstWeekStart!,
            toMs: now,
          );
          expect(period, isNotNull);
          expect(period!.measure, MixMeasure.time);
        });

        testWidgets('the card does not appear and the layer is quiet', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          expect(find.byKey(const Key(_kCardKey)), findsNothing);
          expect(find.text(_kObservation), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── the rule abstains ────────────────────────────────────────────────

      group('the rule abstains', () {
        group('no history at all', () {
          // The store holds nothing: no completed week exists and the Mix layer
          // has nothing to split, so the gate is unmet.
          setUp(() async {});

          testWidgets('renders no layer and no card', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsNothing);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(tester.takeException(), isNull);
          });
        });

        group('a history with no higher-load run', () {
          setUp(() => _seedFFlatWindow(repo));

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
          });
        });
      });
    });
  }
}
