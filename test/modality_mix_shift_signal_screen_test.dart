// The Modality Mix Shift card (Stats PR 7a, Phase 2) — the signal end to end.
//
// Scenarios S-1909 and S-1904(b) of
// `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md`,
// on both repository implementations.
//
// The card is produced by the app's real registry (`buildSignalRegistry()`),
// which the screen falls back to when no `signals:` seam is passed, so this
// file exercises the shipped signal, the shipped period walk and the shipped
// copy — nothing here is stubbed.
//
// F-MIX is the plan's mixed history. It has to satisfy three things at once:
// the Mix layer's rated-baseline gate for the Stats window (>= 4 rated weeks),
// the signal's own 28-day period measure rule (load, not time), and a
// regularly trained modality whose recent share fell below half. The window is
// period-scoped so the rated baseline sessions stay outside it.
//
// The real registry also holds Progression Rate, so every assertion here names
// the Mix Shift card by its key rather than counting cards.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. S-1909's tap is the exception — it is
// Mock-only, because a Hive write started in a widget test's fake-async zone
// cannot drain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/modality_mix_shift.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/modality_mix_shift_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals/signal_registry.dart';
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

/// The card's key, the dismissal key and the store entry (D-1216).
const String _kCardKey = 'signal_card_modality-mix-shift';
const String _kDismissKey = 'signal_dismiss_modality-mix-shift';
const String _kSignalId = 'modality-mix-shift';

/// The kind label a caution card carries (D-1001).
const String _kCautionLabel = 'Worth a look';

// ─── F-MIX ──────────────────────────────────────────────────────────────────

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
  int? rating,
  int minutes = 60,
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
/// measures no time at all (D-902).
Future<void> _seedSetEffort(
  WorkoutRepository repo, {
  required String sessionId,
  double weightFactor = 100.0,
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
    weightFactor: weightFactor,
    repsBase: 5,
  );
}

/// A `timed` effort measuring [seconds] of cardio on [sessionId].
Future<void> _seedCardioEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required int seconds,
}) async {
  final exerciseId = 'ex-cardio-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Easy Run',
    capabilities: const ['time', 'distance'],
  );
  await seedHoldEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-cardio',
    exerciseId: exerciseId,
    entryCount: 1,
    secondsPerEntry: seconds,
    effortKind: 'timed',
  );
}

/// A `drill` effort measuring [seconds] of isometric work on [sessionId].
Future<void> _seedIsometricEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required int seconds,
}) async {
  final exerciseId = 'ex-hold-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Plank',
    capabilities: const ['hold'],
  );
  await seedHoldEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-isometric',
    exerciseId: exerciseId,
    entryCount: 1,
    secondsPerEntry: seconds,
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

/// F-MIX: a mixed history whose period `[day(27), now]` reads load, whose
/// baseline is rated enough for the gate, and whose isometric share has fallen
/// below half.
///
/// The period holds resistance and isometric work; the baseline holds all four
/// modalities, with isometric well above the regularly-trained floor. The
/// window is period-scoped over the last 3 days — narrower than the signal's
/// own 28-day period — so the baseline sessions stay outside it and a period
/// that followed the chip would lose the isometric work entirely.
Future<void> _seedFMix(WorkoutRepository repo) async {
  // The period `[day(27), now]`: resistance and isometric.
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-p1',
    daysAgo: 20,
    rating: 4,
  );
  await _seedSetEffort(repo, sessionId: 'fmix-p1', weightFactor: 100.0);
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-p2',
    daysAgo: 10,
    rating: 4,
  );
  await _seedSetEffort(repo, sessionId: 'fmix-p2', weightFactor: 100.0);
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-p3',
    daysAgo: 2,
    rating: 4,
  );
  await _seedIsometricEffort(repo, sessionId: 'fmix-p3', seconds: 300);

  // The baseline blocks before `day(27)`: one rated session in each of the
  // first five blocks, so `ratedBaselineWeeks` clears the gate. Isometric work
  // is spread across them, so its baseline share is well above the floor.
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-b0',
    daysAgo: 108,
    rating: 4,
  );
  await _seedIsometricEffort(repo, sessionId: 'fmix-b0', seconds: 1200);
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-b1',
    daysAgo: 101,
    rating: 4,
  );
  await _seedIsometricEffort(repo, sessionId: 'fmix-b1', seconds: 1200);
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-b2',
    daysAgo: 94,
    rating: 4,
  );
  await _seedIsometricEffort(repo, sessionId: 'fmix-b2', seconds: 1200);
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-b3',
    daysAgo: 87,
    rating: 4,
  );
  await _seedIsometricEffort(repo, sessionId: 'fmix-b3', seconds: 1200);
  await _seedRatedSession(
    repo,
    sessionId: 'fmix-b4',
    daysAgo: 80,
    rating: 4,
  );
  await _seedIsometricEffort(repo, sessionId: 'fmix-b4', seconds: 1200);

  await _seedPeriod(repo, name: 'Test Block', daysAgo: 3);
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-1', daysAgo: 1);
  await _seedFood(repo, id: 'food-2', daysAgo: 2);
}

/// F-TIME: five rated sessions, each one timed effort, a week apart, so the
/// signal's own period `[day(27), now]` has only two rated baseline blocks and
/// its measure is time (S-1904b).
///
/// The window is period-scoped over the last 14 days, which holds the `day(10)`
/// session and four rated baseline blocks — so the framework's gate is met and
/// the layer renders, while the signal abstains.
Future<void> _seedFTime(WorkoutRepository repo) async {
  for (final days in [10, 17, 24, 31, 38]) {
    await _seedRatedSession(
      repo,
      sessionId: 'ftime-$days',
      daysAgo: days,
      rating: 4,
    );
    await _seedCardioEffort(repo, sessionId: 'ftime-$days', seconds: 600);
  }
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 14);
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-1', daysAgo: 1);
  await _seedFood(repo, id: 'food-2', daysAgo: 2);
}

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Modality Mix Shift signal — ${harness.name}', () {
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

      // ─── S-1909 ────────────────────────────────────────────────────────────

      group('S-1909 the card on the layer', () {
        setUp(() => _seedFMix(repo));

        testWidgets('the caution card shows with the exact copy, the caution '
            'label and its key, below the Mix layer', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kCautionLabel), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);

          // The card's exact copy for F-MIX. Period: resistance 700 /
          // isometric 20 (total 720) → resistance 97%, isometric 3%. Baseline:
          // resistance 800 / isometric 400 (total 1200) → resistance 67%,
          // isometric 33%. Isometric fires (2 × 20 × 1200 < 400 × 720) and
          // resistance is the largest recent share, so the second sentence is
          // present.
          expect(
            find.text(
              'Isometric is 3% of your load over the last 4 weeks, down from '
              'its usual 33%. Resistance has grown to 97%.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'An isometric session this week would bring your mix back '
              'toward usual.',
            ),
            findsOneWidget,
          );

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

      // ─── S-1909, the period does not follow the window chip ────────────────

      // The mutation guard for D-1201: the signal's period is the 28 local
      // calendar days ending today, never the Stats window. F-MIX's window is
      // period-scoped to the last 3 days, so a period that followed the chip
      // would see only the `day(2)` session and too few rated baseline blocks
      // for the load measure — and the card would disappear. The card's
      // presence is the assertion.
      group('S-1909 the period does not follow the window chip', () {
        setUp(() => _seedFMix(repo));

        testWidgets('a window narrower than the period still shows the card',
            (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
        });
      });

      // ─── S-1904(b) ─────────────────────────────────────────────────────────

      group('S-1904b time mode suppresses the card', () {
        setUp(() => _seedFTime(repo));

        testWidgets('the layer renders the quiet line and no Mix Shift card',
            (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
          expect(find.byKey(const Key(_kCardKey)), findsNothing);
          expect(find.text(_kCautionLabel), findsNothing);
        });
      });

      // ─── S-1909, the dismissal ─────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level
      // round trip (S-1712 in `test/signals_service_test.dart`); the
      // screen-level behaviour asserted here — the card gone in the frame
      // after the tap, and still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-1909 the card is dismissible', () {
          setUp(() => _seedFMix(repo));

          testWidgets('one tap removes the card in the tap frame, the store '
              'holds the id, and the next open is still quiet', (tester) async {
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

      // ─── the structural guard: the payload's own segments ──────────────────

      // D-1205: the signal hands the period payload's own `measure`, `segments`
      // and `baselineSegments` to the rule and re-derives nothing. The guard
      // rebuilds the card's copy from the payload the service returns and
      // requires it to equal the card the signal produced — so a signal that
      // split the bar itself, or read a different payload, would disagree.
      group('the signal reads the period payload\'s own segments', () {
        setUp(() => _seedFMix(repo));

        test('the card\'s copy equals the copy built from the payload', () async {
          final now = DateTime.now();
          final fromMs = DateTime(
            now.year,
            now.month,
            now.day - (kModalityMixShiftPeriodDays - 1),
          );
          final payload = await StatsProgressService(
            repo,
          ).computeMixPeriod(fromMs: fromMs, toMs: now);
          expect(payload, isNotNull);

          final shift = modalityMixShift(
            measure: payload!.measure,
            recent: payload.segments,
            baseline: payload.baselineSegments,
          );
          expect(shift, isNotNull);
          final expected = modalityMixShiftCopy(shift!);

          final card = await const ModalityMixShiftSignal().evaluate(
            SignalContext(
              now: now,
              window: StatsWindow(
                fromMs: fromMs,
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
          expect(card!.observation, expected.observation);
          expect(card.suggestion, expected.suggestion);
          expect(card.id, _kSignalId);
          expect(card.kind, SignalKind.caution);
          expect(card.priority, kModalityMixShiftPriority);
        });
      });
    });
  }

  // ─── the structural guard: the registry ────────────────────────────────────

  // D-1215: the signal is one class plus one registry line, and no framework
  // file names a concrete signal. The registry is the only place a signal is
  // registered, so it must list exactly the shipped signals.
  group('the registry', () {
    test('lists exactly the seven shipped signals, in order', () {
      final registry = buildSignalRegistry();
      expect(registry.map((signal) => signal.id), [
        'cardio-efficiency-drift',
        'sustained-high-load',
        'protein-consistency',
        'fuel-vs-load',
        'progression-rate',
        'modality-mix-shift',
        'cross-modality-interference',
      ]);
    });
  });
}
