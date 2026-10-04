// The Protein Consistency card (Stats PR 8b, Phase 3) — the signal end to end.
//
// Scenario S-2216 (the card on the layer, and its dismissal), S-2206/S-2207
// (the own-baseline copy, with and without a bodyweight) and S-2215 (two
// cautions qualifying) of
// `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/2026-10-03-08b-stats-pr8b-protein-consistency-plan.md`,
// on both repository implementations.
//
// The card is produced by the app's real registry (`buildSignalRegistry()`),
// which the screen falls back to when no `signals:` seam is passed, so this
// file exercises the shipped signal, the shipped 14-day window and the shipped
// copy — nothing here is stubbed.
//
// Every fixture has to satisfy the Mix layer's rated-baseline gate for the
// Stats window (>= 4 rated blocks, so the layer renders at all) and the
// signal's own gates (>= 10 logged days in the window, >= 2 resistance
// sessions, the shortfall test). The arithmetic is in the plan's evidence file;
// the fixture comments below carry the figures each block contributes.
//
// The window is period-scoped over `day(20)`…today so the Mix layer renders
// above the Signals layer, exactly as F-FUEL does in
// `test/fuel_vs_load_signal_screen_test.dart`, whose helper pattern this file
// copies. The real registry also holds Fuel vs Load, Progression Rate, Modality
// Mix Shift and Interference, so every assertion names the Protein Consistency
// card by its key rather than counting cards.
//
// S-2215's plan text expects "exactly one card, Fuel vs Load", which the shipped
// `resolveSignals` cannot produce: two cautions qualify and the framework renders
// the top `kSignalMaxCards` of a single kind (`lib/core/models/signals.dart`,
// pinned by `test/signals_layer_screen_test.dart`). Framework files are frozen
// (D-1518), so S-2215's screen group pins the reachable contract — Fuel vs Load
// above Protein Consistency, and the Protein card left on screen once Fuel vs
// Load is dismissed. The finding is logged in the plan's evidence file.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. The dismissals are Mock-only for the same
// reason — a Hive write started in a widget test's fake-async zone cannot drain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/protein_consistency.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/fuel_vs_load_signal.dart';
import 'package:omnitrain/core/services/signals/protein_consistency_signal.dart';
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

/// The card's key, the dismissal key and the store entry (D-1502).
const String _kCardKey = 'signal_card_protein-consistency';
const String _kDismissKey = 'signal_dismiss_protein-consistency';
const String _kSignalId = 'protein-consistency';

/// The kind label a caution card carries (D-1001).
const String _kCautionLabel = 'Worth a look';

/// The Fuel vs Load card's key and dismiss key, for S-2215's ordering.
const String _kFuelCardKey = 'signal_card_fuel-vs-load';
const String _kFuelDismissKey = 'signal_dismiss_fuel-vs-load';

/// S-2201's copy: 120 g averaged against a 150 g target, 20% under (D-1512).
const String _kObservationTarget =
    'Protein has averaged 120 g/day over the last 2 weeks, about 20% under '
    'your 150 g target.';
const String _kSuggestionTarget =
    'Bringing protein back toward your target is one option.';

/// S-2206's copy: 118 g averaged against a usual 145 g, at 70 kg (D-1513,
/// D-1514, D-1515).
const String _kObservationOwn =
    'Protein has averaged 118 g/day (1.7 g/kg) over the last 2 weeks, down '
    'from your usual 145 g.';
const String _kSuggestionOwn =
    'Commonly cited guidance for strength training is around 1.6 g/kg of '
    'bodyweight.';

/// S-2207's copy: the same average with no bodyweight on file, so no g/kg
/// figure and no suggestion at all (D-1514, D-1515).
const String _kObservationOwnNoKg =
    'Protein has averaged 118 g/day over the last 2 weeks, down from your '
    'usual 145 g.';

/// The sentence the own-baseline suggestion opens with — asserted absent when
/// there is no bodyweight.
const String _kSuggestionStem = 'Commonly cited guidance';

// ─── calendar anchors ───────────────────────────────────────────────────────

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
/// Resistance time.
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
/// the window's start at `day(20)` and so lets the Mix layer render.
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

/// The load history every fixture here shares: five rated sessions in the prior
/// period, five in the recent one, and four rated sessions in the older blocks
/// the window's own baseline reads.
///
/// A window's baseline is the twelve 7-day blocks before its start day, so the
/// window (starting `day(20)`) reads days 21…104. The five prior-period sessions
/// rate three of those blocks and the four older sessions rate one each, so the
/// window clears the Mix layer's four-rated-week gate (D-1502).
///
/// The recent period's sessions sit on `day(20)`, `day(16)`, `day(12)`,
/// `day(8)` and `day(4)`: exactly three of them — `day(12)`, `day(8)` and
/// `day(4)` — fall inside the rule's 14-day window, which is what its
/// `>= 2 resistance sessions` gate reads (D-1510).
Future<void> _seedLoad(WorkoutRepository repo) async {
  for (final days in [41, 36, 31, 26, 21]) {
    final id = 'prot-prior-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 4);
    await _seedSetEffort(repo, sessionId: id);
  }

  for (final days in [20, 16, 12, 8, 4]) {
    final id = 'prot-recent-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 5);
    await _seedSetEffort(repo, sessionId: id);
  }

  for (final days in [48, 62, 76, 90]) {
    final id = 'prot-base-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 4);
    await _seedSetEffort(repo, sessionId: id);
  }
}

/// The rated blocks the window's baseline reads, with no session inside the
/// rule's 14-day window: the four older baseline blocks only.
///
/// Used by the `fewer than two resistance sessions` abstention — the Mix layer
/// still renders (four rated blocks, and one window session carries time), but
/// the rule's resistance gate sees one.
Future<void> _seedBaselineOnlyLoad(WorkoutRepository repo) async {
  for (final days in [48, 62, 76, 90]) {
    final id = 'prot-baseonly-$days';
    await _seedSession(repo, sessionId: id, daysAgo: days, rating: 4);
    await _seedSetEffort(repo, sessionId: id);
  }
  // One rated session inside the window, so `windowTimeSeconds > 0` and the Mix
  // layer is not null — but it is the window's only resistance session.
  await _seedSession(repo, sessionId: 'prot-one', daysAgo: 5, rating: 4);
  await _seedSetEffort(repo, sessionId: 'prot-one');
}

// ─── food fixtures ──────────────────────────────────────────────────────────

/// The repository's food log, emptied: the Mock harness opens with
/// `SeedData.sampleConsumedFoods()` already written, the Hive harness empty.
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

/// The 14-day window's logged days: `day(13)`…`day(2)`, [protein] grams each.
///
/// Twelve logged days clears the rule's `>= 10` gate with room to spare, and
/// the days are deliberately short of the window's end so a fixture never has
/// to reason about today's own row.
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

/// The eight 7-day blocks the rule's own baseline reads, at [protein] grams a
/// day: `[69-63]` and `[62-56]` hold 7 of 7 (two consistent blocks — the
/// `>= 2` gate, D-1509), the other six hold 3 of 7.
Future<void> _seedBaselineFood(
  WorkoutRepository repo, {
  required String prefix,
  required int protein,
  required int calories,
}) async {
  for (var daysAgo = 69; daysAgo >= 63; daysAgo--) {
    await _seedFood(
      repo,
      id: '$prefix-a-$daysAgo',
      daysAgo: daysAgo,
      protein: protein,
      calories: calories,
    );
  }
  for (var daysAgo = 62; daysAgo >= 56; daysAgo--) {
    await _seedFood(
      repo,
      id: '$prefix-b-$daysAgo',
      daysAgo: daysAgo,
      protein: protein,
      calories: calories,
    );
  }
  for (final start in [55, 48, 41, 34, 27, 20]) {
    for (var offset = 0; offset < 3; offset++) {
      final daysAgo = start - offset;
      await _seedFood(
        repo,
        id: '$prefix-c-$daysAgo',
        daysAgo: daysAgo,
        protein: protein,
        calories: calories,
      );
    }
  }
}

/// The stored protein target [protein] grams from `day(13)` on: the repository
/// walks backward for the most recent ancestor, so the whole window inherits it
/// (F-1 — the shipped target screen cannot set a protein target, so the test
/// writes one directly).
Future<void> _seedWindowTarget(
  WorkoutRepository repo, {
  required double protein,
}) => repo.saveNutritionTargetForDate(
  _day(13).millisecondsSinceEpoch,
  NutritionTarget(calories: 2000, protein: protein, carbs: 250, fat: 70),
);

/// The latest bodyweight on file, in the canonical kilogram unit (D-1511).
Future<void> _seedBodyWeightKg(WorkoutRepository repo, double kg) =>
    repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bw-1',
        measurementType: 'bodyweight',
        value: kg,
        unitId: 'unit-kg',
        recordedAtMs: _at(30, 8),
      ),
    );

// ─── fixtures ───────────────────────────────────────────────────────────────

/// F-PROT (S-2216): the target comparison. Twelve window days at 120 g against
/// a 150 g target — `20 × 1440 = 28,800 <= 17 × 2100 = 35,700`, so the card
/// fires at 20% (D-1508).
///
/// Fuel vs Load abstains: only twelve days are logged, so its six-block
/// consistency gate finds 0 of 7 in `[20-14]`.
Future<void> _seedFProt(WorkoutRepository repo) async {
  await _seedLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  await _seedWindowFood(repo, prefix: 'fprot', protein: 120, calories: 2040);
  await _seedWindowTarget(repo, protein: 150);
}

/// F-OWN (S-2206) and F-OWN-NBW (S-2207): the own-baseline comparison, the only
/// path a real user can reach. No target is stored, so the twelve window days
/// at 118 g are compared with the usual 145 g —
/// `100 × 1416 × 14 = 1,982,400 <= 83 × 2030 × 12 = 2,021,880` (D-1508).
///
/// [bodyWeightKg] null leaves no bodyweight on file, which drops the g/kg
/// figure and the suggestion entirely (D-1514, D-1515).
Future<void> _seedFOwn(WorkoutRepository repo, {double? bodyWeightKg}) async {
  await _seedLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  await _seedWindowFood(repo, prefix: 'fown', protein: 118, calories: 2000);
  await _seedBaselineFood(repo, prefix: 'fown', protein: 145, calories: 2000);
  if (bodyWeightKg != null) await _seedBodyWeightKg(repo, bodyWeightKg);
}

/// F-MERGED (S-2215): F-FUEL's 42 logged days and load history, with the window
/// days at 120 g against a 150 g target. Both cautions qualify — Fuel vs Load
/// (300) and Protein Consistency (200).
Future<void> _seedFMerged(WorkoutRepository repo) async {
  await _seedLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  for (var daysAgo = 41; daysAgo >= 21; daysAgo--) {
    await _seedFood(
      repo,
      id: 'fmerged-prior-$daysAgo',
      daysAgo: daysAgo,
      protein: 120,
      calories: 2000,
    );
  }
  for (var daysAgo = 20; daysAgo >= 0; daysAgo--) {
    await _seedFood(
      repo,
      id: 'fmerged-recent-$daysAgo',
      daysAgo: daysAgo,
      protein: 120,
      calories: 2040,
    );
  }
  await _seedWindowTarget(repo, protein: 150);
}

/// F-NOFOOD: the load, the period-scoped window and an empty food log. The
/// layer renders; the rule's logged-days gate finds nothing.
Future<void> _seedFNoFood(WorkoutRepository repo) async {
  await _seedLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
}

/// F-ONESESSION: F-PROT's food and target, with one resistance session in the
/// window. Every other gate passes, so only the `>= 2` resistance gate can make
/// the rule abstain (D-1510).
Future<void> _seedFOneSession(WorkoutRepository repo) async {
  await _seedBaselineOnlyLoad(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  await _seedWindowFood(
    repo,
    prefix: 'fonesession',
    protein: 120,
    calories: 2040,
  );
  await _seedWindowTarget(repo, protein: 150);
}

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Protein Consistency signal — ${harness.name}', () {
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
        List<Signal>? signals = const [ProteinConsistencySignal()],
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
        List<Signal>? signals = const [ProteinConsistencySignal()],
      }) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await pumpStats(tester, signals: signals);
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

      // ─── S-2216, the target comparison ────────────────────────────────────

      group('S-2216 the card on the layer', () {
        setUp(() => _seedFProt(repo));

        testWidgets('the caution card shows with S-2201\'s copy, the caution '
            'label and its key, below the Mix layer', (tester) async {
          await pumpStats(
            tester,
            signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()],
          );

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kCautionLabel), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text(_kObservationTarget), findsOneWidget);
          expect(find.text(_kSuggestionTarget), findsOneWidget);

          // Fuel vs Load's own consistency gate fails on twelve logged days, so
          // this fixture isolates the protein card.
          expect(find.byKey(const Key(_kFuelCardKey)), findsNothing);

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
          expect(find.byKey(const Key('fuel_section')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2216, the dismissal ────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level round
      // trip (S-1712 in `test/signals_service_test.dart`); the screen-level
      // behaviour asserted here — the card gone in the frame after the tap, and
      // still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-2216 the card is dismissible', () {
          setUp(() => _seedFProt(repo));

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

      // ─── S-2206, the own-baseline comparison ──────────────────────────────

      group('S-2206 the own-baseline card', () {
        setUp(() => _seedFOwn(repo, bodyWeightKg: 70));

        testWidgets('names the usual level and the per-kilogram figure, and '
            'carries the reference suggestion', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kCautionLabel), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text(_kObservationOwn), findsOneWidget);
          expect(find.text(_kSuggestionOwn), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2207, no bodyweight on file ────────────────────────────────────

      group('S-2207 with no bodyweight', () {
        setUp(() => _seedFOwn(repo));

        testWidgets('drops the g/kg figure and renders no second line at all', (
          tester,
        ) async {
          await pumpStats(tester);

          final card = find.byKey(const Key(_kCardKey));
          expect(card, findsOneWidget);
          expect(find.text(_kObservationOwnNoKg), findsOneWidget);
          expect(find.text(_kObservationOwn), findsNothing);
          expect(find.textContaining(_kSuggestionStem), findsNothing);

          // No empty second line: the card holds no blank Text.
          expect(
            find.descendant(of: card, matching: find.text('')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2215, two cautions qualifying ──────────────────────────────────

      group('S-2215 two cautions qualifying', () {
        setUp(() => _seedFMerged(repo));

        testWidgets(
          'renders the higher-priority caution above the protein card',
          (tester) async {
            await pumpStats(
              tester,
              signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()],
            );

            // Both cautions qualify. The framework renders the top
            // `kSignalMaxCards` of a single kind, so the layer carries both, Fuel
            // vs Load (300) first — Protein Consistency is never above it.
            final fuel = find.byKey(const Key(_kFuelCardKey));
            expect(fuel, findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
            expect(
              tester.getTopLeft(fuel).dy,
              lessThan(tester.getTopLeft(find.byKey(const Key(_kCardKey))).dy),
            );
            expect(find.text(_kObservationTarget), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );

        // Mock-only, for the same reason as S-2216's dismissal.
        if (harness.name == 'Mock') {
          testWidgets('dismissing Fuel vs Load leaves the protein card on the '
              'layer', (tester) async {
            await pumpStats(
              tester,
              signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()],
            );

            await tester.tap(find.byKey(const Key(_kFuelDismissKey)));
            await tester.pump();

            expect(find.byKey(const Key(_kFuelCardKey)), findsNothing);
            expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
            expect(find.text(_kObservationTarget), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsNothing);

            await settleStore(tester);
            final store = await _readDismissals(repo);
            expect(store['fuel-vs-load'], isA<int>());

            await reopen(
              tester,
              signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()],
            );
            expect(find.byKey(const Key(_kFuelCardKey)), findsNothing);
            expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          });
        }
      });

      // ─── the rule abstains ────────────────────────────────────────────────

      group('the rule abstains', () {
        group('an empty food log', () {
          setUp(() => _seedFNoFood(repo));

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
          });
        });

        group('one resistance session in the window', () {
          setUp(() => _seedFOneSession(repo));

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
          });
        });
      });

      // ─── the adapter ──────────────────────────────────────────────────────

      // D-1502: the card's identity — the id, the kind, the priority and the
      // title — is the adapter's, and the copy comes from the pure builder.
      group('the adapter', () {
        setUp(() => _seedFProt(repo));

        test(
          'proposes the card with its own identity and the rule\'s copy',
          () async {
            final now = DateTime.now();
            final card = await const ProteinConsistencySignal().evaluate(
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
            expect(card.priority, kProteinConsistencyPriority);
            expect(card.title, 'Protein consistency');
            expect(card.observation, _kObservationTarget);
            expect(card.suggestion, _kSuggestionTarget);
          },
        );
      });
    });
  }
}
