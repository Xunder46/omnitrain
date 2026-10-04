// The Cardio Efficiency Drift card (Stats PR 9b, Phase 3A) — the signal end to
// end.
//
// Scenario S-2511 (the card on the layer, the lifting sentence, the two-caution
// variant and the dismissal) of
// `docs/plans/2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan/2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.md`,
// on both repository implementations.
//
// The card is produced by the app's real registry (`buildSignalRegistry()`),
// which the screen falls back to when no `signals:` seam is passed, so this file
// exercises the shipped signal, the shipped Mix gate and the shipped copy —
// nothing here is stubbed.
//
// The fixtures are anchored to the real clock, not a fixed `now`: the windows
// are local calendar days, so every effort is placed with `_day(daysAgo)` and
// the drift is the plan's own arithmetic — four recent efforts at 480 s and
// 2790 m against four reference efforts at 480 s and 3000 m, all at 150 bpm, so
// the means are 2.325 and 2.5 and `p = 7`.
//
// S-2511's plan text expects two qualifying cautions "in ascending priority
// (Cardio Efficiency Drift first)", which the shipped `resolveSignals` cannot
// produce: it sorts a kind by priority *descending*, so Sustained High Load
// (100) renders above Cardio Efficiency Drift (50). Framework files are frozen,
// so this file pins the reachable contract and the finding is logged in the
// plan's Assumption Log. Do not "fix" the test to match the plan.
//
// The harness is opened and seeded in `setUp`, never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. The dismissal is Mock-only for the same
// reason — a Hive write started in a widget test's fake-async zone cannot drain.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/cardio_efficiency_drift.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/signals/cardio_efficiency_drift_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
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

/// The card's key, the dismissal key and the store entry (D-1809).
const String _kCardKey = 'signal_card_cardio-efficiency-drift';
const String _kDismissKey = 'signal_dismiss_cardio-efficiency-drift';
const String _kSignalId = 'cardio-efficiency-drift';

/// The kind label a caution card carries (D-1001).
const String _kCautionLabel = 'Worth a look';

/// The Sustained High Load card's key, for S-2511's two-caution variant.
const String _kSustainedCardKey = 'signal_card_sustained-high-load';

/// S-2501's copy: 7% worse, no lifting sentence (D-1808).
const String _kObservation =
    'At similar durations, your Treadmill Run efforts are about 7% less '
    'efficient (slower pace at the same heart rate) than 4–6 weeks ago.';
const String _kSuggestion = 'An easier week is one option.';

/// S-2509's second sentence, at exactly +15% (D-1807).
const String _kLiftSentence =
    ' Lifting load is 15% above your usual over the same period.';

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
  return DateTime(
    start.year,
    start.month,
    start.day + 3,
    9,
  ).millisecondsSinceEpoch;
}

// ─── cardio fixtures ────────────────────────────────────────────────────────

/// One completed cardio session on the local day [daysAgo] days back: a rated
/// session whose segment holds one `timed` effort for `ex-run` with a finished
/// 480-second instance, a paired distance row and an instance-scope summary at
/// 150 bpm.
///
/// The session's duration equals the instance's, so the shared split gives the
/// whole session to Cardio and its resistance remainder is zero. [rating] is
/// `null` for an unrated session, which is what keeps the Mix payload off the
/// load measure (D-908).
Future<void> _seedCardioSession(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double metres,
  String? source,
  int? rating = 3,
}) async {
  final start = _at(daysAgo, 9);
  final effortId = 'eff-$id';
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + 480000,
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
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$id',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'ex-run',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createTimedInstance(
    timedInstance(
      effortId,
      0,
      durationSecs: 480,
      entryIndex: 0,
      startedAtMs: start,
    ),
  );
  await repo.createObservation(
    distanceRow(effortId, 0, metres, atMs: fixtureRowAt(0), source: source),
  );
  await seedSensorSummary(
    repo,
    sensorSummary(
      sessionId: id,
      scope: SensorSummary.scopeTimedInstance,
      targetId: 'ti-$effortId-0',
      windowStartMs: start,
      windowEndMs: start + 480000,
      avgHeartRateBpm: 150,
    ),
  );
}

/// S-2501's cardio fixture: four recent efforts at 480 s and 2790 m (days 3, 6,
/// 9, 12) and four reference efforts at 480 s and 3000 m (days 30, 33, 36, 39),
/// all at 150 bpm.
///
/// [recentCount] and [referenceCount] trim the windows, so a variant can drop
/// below the three-effort floor; [recentSource] is the source the **first**
/// recent effort's row is stored with, so a variant can make one an estimate
/// while the others stay measured. [rating] is passed to every session, so
/// `null` seeds an entirely unrated history.
Future<void> _seedCardio(
  WorkoutRepository repo, {
  int recentCount = 4,
  int referenceCount = 4,
  String? recentSource,
  int? rating = 3,
}) async {
  await seedExercise(
    repo,
    id: 'ex-run',
    name: 'Treadmill Run',
    capabilities: const ['time', 'distance'],
  );

  const recentDays = [3, 6, 9, 12];
  const referenceDays = [30, 33, 36, 39];

  for (var i = 0; i < recentCount; i++) {
    await _seedCardioSession(
      repo,
      id: 's-recent-$i',
      daysAgo: recentDays[i],
      metres: 2790,
      source: i == 0 ? recentSource : null,
      rating: rating,
    );
  }
  for (var i = 0; i < referenceCount; i++) {
    await _seedCardioSession(
      repo,
      id: 's-ref-$i',
      daysAgo: referenceDays[i],
      metres: 3000,
      rating: rating,
    );
  }
}

/// Four rated cardio sessions in four distinct baseline blocks before the
/// window's start (`day(20)`): days 48, 62, 76 and 90.
///
/// They carry the Mix layer's rated-week floor, so `signalsGateMet` holds and
/// the layer renders. They are cardio, so they add no resistance load and no
/// second sentence.
Future<void> _seedRatedBaseline(WorkoutRepository repo) async {
  const days = [48, 62, 76, 90];
  for (var i = 0; i < days.length; i++) {
    await _seedCardioSession(
      repo,
      id: 's-base-$i',
      daysAgo: days[i],
      metres: 3000,
    );
  }
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

// ─── resistance fixtures (S-2509) ───────────────────────────────────────────

/// One resistance session on the local day [daysAgo] days back, lasting
/// [minutes] and rated [rating], with no effort at all.
///
/// With no effort the shared split gives the whole duration to Resistance, so
/// its load is exactly `minutes × rating` and no other signal sees an exercise.
/// A `null` [rating] leaves the session's time in the split but gives it zero
/// load (D-901), and — because the session is unrated — it cannot carry the
/// payload's rated-week floor (D-908).
Future<void> _seedResistanceSession(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required int minutes,
  required int? rating,
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
}

/// S-2509's resistance load: four rated sessions in the last 28 days at
/// `69 min × 5 = 345` each (`liftRecentLoad = 1380`) and twelve rated sessions
/// in the twelve baseline blocks of `[day(27), now]` at `60 min × 5 = 300` each
/// (`liftUsualLoad = 3600`).
///
/// `1380 × 84 × 100 = 11,592,000 >= 3600 × 28 × 115 = 11,592,000`, so the
/// second sentence fires at exactly +15%.
Future<void> _seedLiftLoad(WorkoutRepository repo) async {
  const recentDays = [2, 8, 15, 22];
  for (var i = 0; i < recentDays.length; i++) {
    await _seedResistanceSession(
      repo,
      id: 'lift-recent-$i',
      daysAgo: recentDays[i],
      minutes: 69,
      rating: 5,
    );
  }
  // The twelve blocks before `day(27)`: `day(28)…day(34)` through
  // `day(105)…day(111)`, one session in each.
  for (var i = 0; i < 12; i++) {
    await _seedResistanceSession(
      repo,
      id: 'lift-base-$i',
      daysAgo: 31 + i * 7,
      minutes: 60,
      rating: 5,
    );
  }
}

// ─── the payload's own measure (D-1807) ────────────────────────────────────

/// The summed measure of [section] in [segments] — the figure the adapter's own
/// `_resistanceLoad` adds up (D-1807).
double _sectionMeasure(List<MixSegment> segments, ExerciseSection section) =>
    segments
        .where((segment) => segment.section == section)
        .fold(0.0, (total, segment) => total + segment.measure);

/// F-TIME: the cardio fixture with **no** session rated anywhere, plus unrated
/// set-only resistance sessions inside the lifting payload's own 28 days and in
/// its twelve baseline blocks.
///
/// Nothing is rated, so `computeMixPeriod(day(27)…now)` measures TIME by
/// construction — `ratedBaselineWeeks` is 0, below `kTrainingLoadMinRatedWeeks`
/// (D-908) — and, in the time measure, carries **no** baseline segments at all.
/// The twelve baseline sessions' 720 minutes are therefore dropped before the
/// adapter ever sees them, while the window still holds 300 resistance minutes.
Future<void> _seedUnratedPayload(WorkoutRepository repo) async {
  await _seedCardio(repo, rating: null);
  await _seedUnratedLiftLoad(repo);
}

/// Four unrated resistance sessions inside the payload's 28 days (days 2, 8, 15
/// and 22, 75 min each, so 300 min of Resistance in the window) and twelve in
/// its twelve baseline blocks (days `31 + 7i`, `i = 0…11`, 60 min each, so
/// 720 min before the window).
///
/// The window's 300 minutes against the baseline's 720 would clear the lifting
/// sentence's test at +25% (`300 × 84 × 100 = 2,520,000 >= 720 × 28 × 115 =
/// 2,318,400`) — which is exactly why the payload's own measure matters: in the
/// time measure the baseline is not part of the payload, so the sentence cannot
/// fire.
Future<void> _seedUnratedLiftLoad(WorkoutRepository repo) async {
  const recentDays = [2, 8, 15, 22];
  for (var i = 0; i < recentDays.length; i++) {
    await _seedResistanceSession(
      repo,
      id: 'time-recent-$i',
      daysAgo: recentDays[i],
      minutes: 75,
      rating: null,
    );
  }
  for (var i = 0; i < 12; i++) {
    await _seedResistanceSession(
      repo,
      id: 'time-base-$i',
      daysAgo: 31 + i * 7,
      minutes: 60,
      rating: null,
    );
  }
}

/// The real period payload with its measure forced to time.
///
/// `StatsProgressService._mixPayload` returns `const []` for `baselineSegments`
/// whenever the measure is time (D-908), so a time-measured payload that still
/// carries a baseline is a shape the shipped service cannot emit — and it is the
/// only shape where the adapter's measure pass-through is observable at all.
/// Every other field, and both resistance figures, come from the real payload
/// unchanged.
///
/// Without this case the measure argument is inert: in every payload the service
/// can emit with `measure == time`, `liftUsualLoad` is 0 and the rule returns
/// null at its `liftUsualLoad <= 0` guard *before* it reads the measure, so an
/// adapter that passed `MixMeasure.load` instead of the payload's own measure
/// would be indistinguishable from the shipped line.
class _TimeMeasuredPayload extends StatsProgressService {
  // A super parameter is not available here: the super constructor's parameter
  // is a private field parameter, which another library cannot name.
  // ignore: use_super_parameters
  _TimeMeasuredPayload(WorkoutRepository repository) : super(repository);

  @override
  Future<MixLayerData?> computeMixPeriod({
    required DateTime fromMs,
    required DateTime toMs,
  }) async {
    final payload = await super.computeMixPeriod(fromMs: fromMs, toMs: toMs);
    if (payload == null) return null;
    return MixLayerData(
      measure: MixMeasure.time,
      segments: payload.segments,
      baselineSegments: payload.baselineSegments,
      unratedSessionCount: payload.unratedSessionCount,
      ratedBaselineWeeks: payload.ratedBaselineWeeks,
      weeks: payload.weeks,
    );
  }
}

// ─── the Sustained High Load fixture (S-2511's second caution) ──────────────

/// One completed session of [minutes] in the week [weeksAgo] weeks back, rated
/// [rating], with a segment and no efforts.
Future<void> _seedWeekSession(
  WorkoutRepository repo, {
  required String id,
  required int weeksAgo,
  required int minutes,
  required int rating,
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

/// F-9A (S-2401): seventeen completed calendar weeks, oldest first — ten at
/// `L = 240` (60 min × 4), two adjacent empty weeks, then five at `L = 230`
/// (46 min × 5).
///
/// The streak's baseline is `W1…W12`, summed 2400, so the usual is `200` and the
/// five streak weeks clear `230 × 100 >= 200 × 110`.
Future<void> _seedF9A(WorkoutRepository repo) async {
  for (var k = 1; k <= 17; k++) {
    final weeksAgo = 18 - k;
    if (k <= 10) {
      await _seedWeekSession(
        repo,
        id: 'w$k',
        weeksAgo: weeksAgo,
        minutes: 60,
        rating: 4,
      );
    } else if (k >= 13) {
      await _seedWeekSession(
        repo,
        id: 'w$k',
        weeksAgo: weeksAgo,
        minutes: 46,
        rating: 5,
      );
    }
  }
}

// ─── composed fixtures ──────────────────────────────────────────────────────

/// F-CARD (S-2501, S-2511): the cardio fixture, the rated baseline that carries
/// the layer's gate, the period-scoped window and an empty food log.
///
/// Every session is cardio and rated, so the window's measure is load, the
/// resistance figures are zero and no other signal qualifies.
Future<void> _seedFCard(WorkoutRepository repo) async {
  await _seedCardio(repo);
  await _seedRatedBaseline(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
}

/// F-LIFT (S-2509): F-CARD plus the resistance load that earns the second
/// sentence.
Future<void> _seedFLift(WorkoutRepository repo) async {
  await _seedFCard(repo);
  await _seedLiftLoad(repo);
}

/// F-TWO (S-2511, two cautions): F-9A's seventeen resistance weeks, the
/// period-scoped window, an empty food log and the cardio fixture.
///
/// Sustained High Load qualifies on the weeks; the cardio sessions add at most
/// 24 load to a streak week, so every week stays above 110% of the usual 200.
Future<void> _seedFTwo(WorkoutRepository repo) async {
  await _seedF9A(repo);
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
  await _clearConsumedFoods(repo);
  await _seedCardio(repo);
  await _seedRatedBaseline(repo);
}

/// The store as the repository reads it back.
Future<Map<String, int>> _readDismissals(WorkoutRepository repo) async =>
    parseSignalDismissals(await repo.getPreferenceString(kSignalDismissalsKey));

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Cardio Efficiency Drift signal — ${harness.name}', () {
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

      // ─── S-2501, the card on the layer ────────────────────────────────────

      group('S-2501 the card on the layer', () {
        setUp(() => _seedFCard(repo));

        testWidgets('the caution card shows with S-2501\'s copy, the caution '
            'label and its key, below the Mix layer', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kCautionLabel), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(find.text(_kObservation), findsOneWidget);
          expect(find.text(_kSuggestion), findsOneWidget);

          // No lifting rise in this fixture, so the second sentence is absent
          // (D-1814).
          expect(find.textContaining('Lifting load is'), findsNothing);

          // The history holds no resistance session and no `set` effort, so no
          // other signal can qualify: this fixture isolates the card.
          expect(find.byKey(const Key(_kSustainedCardKey)), findsNothing);

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

        test(
          'the service reads the eight efforts and the rule reports 7%',
          () async {
            final now = DateTime.now();
            final service = StatsProgressService(repo);

            final efforts = await service.cardioEfforts(
              fromMs: _day(42),
              toMs: now,
            );
            expect(efforts.length, 8); // the four recent + the four reference
            expect(efforts.first.exerciseName, 'Treadmill Run');

            final result = cardioEfficiencyDrift(
              efforts: efforts,
              now: now,
              liftRecentLoad: 0,
              liftUsualLoad: 0,
              liftMeasure: MixMeasure.time,
            );
            expect(result, isNotNull);
            expect(result!.driftPercent, 7);
            expect(result.exerciseName, 'Treadmill Run');
          },
        );
      });

      // ─── S-2509, the lifting sentence ─────────────────────────────────────

      group('S-2509 the lifting sentence', () {
        setUp(() => _seedFLift(repo));

        testWidgets('the card carries the second sentence at exactly +15%', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(find.text(_kObservation + _kLiftSentence), findsOneWidget);
          expect(find.text(_kSuggestion), findsOneWidget);
          expect(find.byKey(const Key(_kSustainedCardKey)), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── the payload's own measure (D-1807) ───────────────────────────────

      // The adapter hands the rule the period payload's own `measure` — never a
      // measure of its own choosing — and the rule refuses the lifting sentence
      // unless that measure is load. Two cases pin it.
      group('the payload\'s own measure', () {
        group('an all-unrated history', () {
          setUp(() => _seedUnratedPayload(repo));

          test('measures time and carries no baseline, so no sentence', () async {
            final now = DateTime.now();
            final fromMs = DateTime(
              now.year,
              now.month,
              now.day - (kCardioEfficiencyLiftLoadWindowDays - 1),
            );
            final service = StatsProgressService(repo);
            final payload = await service.computeMixPeriod(
              fromMs: fromMs,
              toMs: now,
            );

            // The real payload, read back: no session is rated, so it measures
            // time and carries no baseline at all — the twelve baseline
            // sessions' 720 minutes never reach the adapter, even though the
            // window itself holds 300 resistance minutes.
            expect(payload, isNotNull);
            expect(payload!.measure, MixMeasure.time);
            expect(payload.baselineSegments, isEmpty);
            expect(
              _sectionMeasure(payload.segments, ExerciseSection.resistance),
              300,
            );

            final card = await const CardioEfficiencyDriftSignal().evaluate(
              SignalContext(
                now: now,
                window: StatsWindow(
                  fromMs: fromMs,
                  toMs: now,
                  label: 'Test window',
                  isPeriodScoped: false,
                ),
                mix: null,
                progressService: service,
                repository: repo,
              ),
            );

            // The drift itself fires — ratings play no part in the eight
            // efforts — and the lifting sentence does not, whatever measure the
            // adapter passes: with no baseline there is nothing to compare
            // against.
            expect(card, isNotNull);
            expect(card!.observation, _kObservation);
            expect(card.observation, isNot(contains('Lifting load')));
            expect(card.suggestion, _kSuggestion);
          });
        });

        group('a time-measured payload that still carries a baseline', () {
          setUp(() => _seedFLift(repo));

          test('never earns the lifting sentence', () async {
            final now = DateTime.now();
            final fromMs = DateTime(
              now.year,
              now.month,
              now.day - (kCardioEfficiencyLiftLoadWindowDays - 1),
            );
            final service = _TimeMeasuredPayload(repo);
            final payload = await service.computeMixPeriod(
              fromMs: fromMs,
              toMs: now,
            );

            // F-LIFT's own figures: 1380 load minutes in the window against
            // 3600 usual, which clear the +15% test exactly. Labelled time, the
            // sentence must not fire; the same figures labelled load would earn
            // it (S-2509), which is what makes this case the one that can tell
            // the adapter's measure pass-through from a hard-coded `load`.
            expect(payload, isNotNull);
            expect(payload!.measure, MixMeasure.time);
            expect(
              _sectionMeasure(payload.segments, ExerciseSection.resistance),
              1380,
            );
            expect(
              _sectionMeasure(
                payload.baselineSegments,
                ExerciseSection.resistance,
              ),
              3600,
            );

            final card = await const CardioEfficiencyDriftSignal().evaluate(
              SignalContext(
                now: now,
                window: StatsWindow(
                  fromMs: fromMs,
                  toMs: now,
                  label: 'Test window',
                  isPeriodScoped: false,
                ),
                mix: null,
                progressService: service,
                repository: repo,
              ),
            );

            expect(card, isNotNull);
            expect(card!.observation, _kObservation);
            expect(card.observation, isNot(contains('Lifting load')));
            expect(card.suggestion, _kSuggestion);
          });
        });
      });

      // ─── the rule abstains ────────────────────────────────────────────────

      group('the rule abstains', () {
        group('two recent efforts', () {
          setUp(() async {
            await _seedCardio(repo, recentCount: 2);
            await _seedRatedBaseline(repo);
            await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
            await _clearConsumedFoods(repo);
          });

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(find.text(_kObservation), findsNothing);
            expect(tester.takeException(), isNull);
          });
        });

        group('an estimated distance drops the count below three', () {
          setUp(() async {
            await _seedCardio(
              repo,
              recentCount: 3,
              recentSource: EffortObservation.sourceEstimated,
            );
            await _seedRatedBaseline(repo);
            await _seedPeriod(repo, name: 'Test Block', daysAgo: 20);
            await _clearConsumedFoods(repo);
          });

          testWidgets('leaves the layer quiet', (tester) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('signals_layer')), findsOneWidget);
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
            expect(find.byKey(const Key(_kCardKey)), findsNothing);
            expect(tester.takeException(), isNull);
          });
        });
      });

      // ─── S-2511, two cautions qualifying ──────────────────────────────────

      group('S-2511 two cautions qualifying', () {
        setUp(() => _seedFTwo(repo));

        testWidgets('renders the higher-priority caution above the Cardio '
            'Efficiency Drift card', (tester) async {
          await pumpStats(tester);

          // Both cautions qualify. The framework sorts a kind by priority
          // descending, so the layer carries Sustained High Load (100) above
          // Cardio Efficiency Drift (50) — the plan's "ascending priority" text
          // is a defect, logged in the plan's Assumption Log.
          final sustained = find.byKey(const Key(_kSustainedCardKey));
          expect(sustained, findsOneWidget);
          expect(find.byKey(const Key(_kCardKey)), findsOneWidget);
          expect(
            tester.getTopLeft(sustained).dy,
            lessThan(tester.getTopLeft(find.byKey(const Key(_kCardKey))).dy),
          );
          expect(find.text(_kObservation), findsOneWidget);
          expect(find.byKey(const Key('signals_quiet_line')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-2511, the dismissal ────────────────────────────────────────────

      // Mock-only. A Hive write started by a tap inside a widget test's
      // fake-async zone cannot drain, so the Hive variant never completes at
      // teardown. The store write on Hive is covered by the service-level round
      // trip (S-1712 in `test/signals_service_test.dart`); the screen-level
      // behaviour asserted here — the card gone in the frame after the tap, and
      // still gone on the next open — is store-independent.
      if (harness.name == 'Mock') {
        group('S-2511 the card is dismissible', () {
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
    });
  }
}
