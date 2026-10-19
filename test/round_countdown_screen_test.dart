// Round countdown screen tests (plan 38d, phase P3c).
//
// Scenarios S-4401..S-4403, S-4407..S-4411 and S-4413 of
// `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.md`,
// driven against the built round branch of
// `lib/features/session/workout_session_detail_view.dart`.
//
// Instances the screen restores from are seeded through the repository, never
// through a real `Future.delayed`: a paused round's 45 s on the clock comes
// from `startedAtMs = pausedAtMs - 45 s`, which the restore path reads back
// exactly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Shared helpers (copied from test/logger_shell_screen_test.dart) ──────────

/// The phone every scenario is measured at: a tall 390 x 844.
const Size _phone = Size(390, 844);

/// The round length the scenarios assume unless they say otherwise.
const int _roundSecs = 180;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Suppress first-run coach-mark sheets that interfere with finder assertions.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  MockWorkoutRepository repo,
});

Future<_Deps> _buildDeps({String? modality}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: modality);
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    repo: repo,
  );
}

Widget _buildSessionScreen(
  _Deps deps, {
  bool editMode = false,
  FakeTimerAlertService? alert,
}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: alert ?? FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
    ),
  );
}

/// Navigate from list view to the detail view by tapping the exercise name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

/// Mounts the session screen at [surfaceSize] and lands on [exerciseName]'s
/// detail. A null [surfaceSize] clears the surface override, so the surface is
/// whatever `tester.view` is set to (physical size and device pixel ratio).
Future<void> _pumpDetail(
  WidgetTester tester,
  _Deps deps,
  String exerciseName, {
  bool editMode = false,
  FakeTimerAlertService? alert,
  Size? surfaceSize = _phone,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  await tester.pumpWidget(
    _buildSessionScreen(deps, editMode: editMode, alert: alert),
  );
  await _openDetailView(tester, exerciseName);
}

// ── Seeding ─────────────────────────────────────────────────────────────────

/// Adds the catalog's round-capable exercise with [rounds] rounds of
/// [durationSecs] each, and returns the effort id and the name to tap.
///
/// Round lengths are written before any round is started: the state refuses a
/// length change on a finished round.
Future<({String effortId, String name})> _seedRounds(
  _Deps deps, {
  int rounds = 1,
  int durationSecs = _roundSecs,
}) async {
  final exercises = await deps.repo.getExercises();
  final exercise = exercises.firstWhere(
    (e) => e.capabilities.contains('rounds'),
  );
  final effortId = await deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'round',
  );
  for (var i = 1; i < rounds; i++) {
    await deps.workoutState.addEntry(effortId);
  }
  for (var i = 0; i < rounds; i++) {
    await deps.workoutState.updateRoundPlannedDuration(
      effortId,
      i,
      durationSecs,
    );
  }
  return (effortId: effortId, name: exercise.name);
}

/// Puts [elapsed] on the round's clock by moving `startedAtMs` back from its
/// pause instant (or from now, for a round that is still active) and reloading
/// the session, so the screen restores an exact elapsed time.
Future<void> _backdateRound(
  _Deps deps, {
  required String effortId,
  required int roundIndex,
  required Duration elapsed,
}) async {
  final round = deps.workoutState.getRoundsForEffort(effortId)[roundIndex];
  final referenceMs = round.pausedAtMs ?? DateTime.now().millisecondsSinceEpoch;
  await deps.repo.updateRoundInstance(
    round.copyWith(startedAtMs: referenceMs - elapsed.inMilliseconds),
  );
  await deps.workoutState.loadSessionData();
}

// ── Finders ─────────────────────────────────────────────────────────────────

/// The round-length row for one entry (`ValueKey('<effortId>-<i>-round-length')`).
Finder _lengthRow(String effortId, [int entryIndex = 0]) =>
    find.byKey(ValueKey('$effortId-$entryIndex-round-length'));

Finder _inRing(String text) =>
    find.descendant(of: find.byType(TimerRing), matching: find.text(text));

Finder _inRow(Finder row, String text) =>
    find.descendant(of: row, matching: find.text(text));

/// The ring's own paint: the `CustomPaint` whose painter is a [TimerRingPainter].
Finder _ringPaint() => find.descendant(
  of: find.byType(TimerRing),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is TimerRingPainter,
  ),
);

double _ringProgress(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(_ringPaint());
  return (paint.painter! as TimerRingPainter).progress;
}

int _plannedSecs(_Deps deps, String effortId, [int roundIndex = 0]) => deps
    .workoutState
    .getRoundsForEffort(effortId)[roundIndex]
    .plannedDurationSecs;

/// Labels the round screen replaced: none of them may be on screen any more.
const List<String> _removedChrome = [
  'DURATION',
  'RUNNING',
  'STOPPED',
  'PAUSED',
  'ROUND 1',
  'PERIOD 1',
];

void _expectNoRemovedChrome() {
  for (final label in _removedChrome) {
    expect(find.text(label), findsNothing, reason: 'no "$label" on the screen');
  }
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('Round countdown — ring (S-4401)', () {
    testWidgets('S-4401: a fresh 180 s round draws a full ring', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await _pumpDetail(tester, deps, seeded.name);

      expect(find.byType(TimerRing), findsOneWidget);
      expect(_ringProgress(tester), 1.0);
      expect(
        deps.workoutState.getRoundsForEffort(seeded.effortId).first.state,
        RoundState.notStarted,
      );
    });

    testWidgets('S-4401: an active round 45 s in shows a 0.75 ring', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await deps.workoutState.startRound(seeded.effortId, 0);
      await _backdateRound(
        deps,
        effortId: seeded.effortId,
        roundIndex: 0,
        elapsed: const Duration(seconds: 45),
      );
      await _pumpDetail(tester, deps, seeded.name);

      expect(
        deps.workoutState.getRoundsForEffort(seeded.effortId).first.state,
        RoundState.active,
      );
      // An active round keeps its own wall clock, so the fraction is asserted
      // with a 1 % tolerance; the exact 0.75 is pinned by S-4410's paused seed.
      expect(_ringProgress(tester), closeTo(0.75, 0.01));
    });
  });

  group('Round countdown — digits and caption (S-4402)', () {
    for (final (label, modality) in const [
      ('martial arts', 'cardio_endurance'),
      ('sports', 'sports'),
    ]) {
      testWidgets('S-4402: $label reads 03:00 + REMAINING with no old chrome', (
        tester,
      ) async {
        final deps = await _buildDeps(modality: modality);
        final seeded = await _seedRounds(deps);
        await _pumpDetail(tester, deps, seeded.name);

        expect(_inRing('03:00'), findsOneWidget);
        expect(_inRing('REMAINING'), findsOneWidget);

        // The digits scale down inside the ring instead of overflowing it.
        final digitsBox = tester.widget<FittedBox>(
          find.descendant(
            of: find.byType(TimerRing),
            matching: find.byType(FittedBox),
          ),
        );
        expect(digitsBox.fit, BoxFit.scaleDown);

        _expectNoRemovedChrome();
      });
    }
  });

  group('Round countdown — length row (S-4403, S-4413)', () {
    testWidgets('S-4403: + adds 15 s to the round length (03:15)', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await _pumpDetail(tester, deps, seeded.name);

      final row = _lengthRow(seeded.effortId);
      expect(_inRow(row, '03:00'), findsOneWidget);
      expect(_inRow(row, 'ROUND LENGTH'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-plus-duration')));
      await tester.pumpAndSettle();

      expect(_inRow(row, '03:15'), findsOneWidget);
      expect(_plannedSecs(deps, seeded.effortId), 195);
    });

    testWidgets('S-4403: − removes 15 s from the round length (02:45)', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await _pumpDetail(tester, deps, seeded.name);

      final row = _lengthRow(seeded.effortId);
      await tester.tap(find.byKey(const Key('value-stepper-minus-duration')));
      await tester.pumpAndSettle();

      expect(_inRow(row, '02:45'), findsOneWidget);
      expect(_plannedSecs(deps, seeded.effortId), 165);
    });

    testWidgets('S-4413: − at 00:15 stays at 00:15', (tester) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps, durationSecs: 15);
      await _pumpDetail(tester, deps, seeded.name);

      final row = _lengthRow(seeded.effortId);
      expect(_inRow(row, '00:15'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-minus-duration')));
      await tester.pumpAndSettle();

      expect(_inRow(row, '00:15'), findsOneWidget);
      expect(_plannedSecs(deps, seeded.effortId), 15);
    });

    testWidgets('S-4413/S-4704: + at 1:00:00 steps to 1:00:15', (tester) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps, durationSecs: 3600);
      await _pumpDetail(tester, deps, seeded.name);

      final row = _lengthRow(seeded.effortId);
      expect(_inRow(row, '1:00:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-plus-duration')));
      await tester.pumpAndSettle();

      expect(_inRow(row, '1:00:15'), findsOneWidget);
      expect(_plannedSecs(deps, seeded.effortId), 3615);
    });

    testWidgets('S-4704: + at the 10-hour ceiling stays at 10:00:00', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps, durationSecs: 36000);
      await _pumpDetail(tester, deps, seeded.name);

      final row = _lengthRow(seeded.effortId);
      expect(_inRow(row, '10:00:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-plus-duration')));
      await tester.pumpAndSettle();

      expect(_inRow(row, '10:00:00'), findsOneWidget);
      expect(_plannedSecs(deps, seeded.effortId), 36000);
    });

    testWidgets('S-4403: the row number opens the duration dialog', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await _pumpDetail(tester, deps, seeded.name);

      expect(
        find.byKey(const Key('tap-hint')),
        findsOneWidget,
        reason: 'S-4712: the editable round length row carries the hint',
      );

      await tester.tap(
        find.descendant(
          of: _lengthRow(seeded.effortId),
          matching: find.byType(InlineMetricEditor),
        ),
      );
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.text('Edit Round Duration'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        findsNWidgets(3),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      // Drain the dialog's deferred (300 ms) controller disposal.
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('S-4403: the row is read-only while the round runs', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await _pumpDetail(tester, deps, seeded.name);

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pumpAndSettle();

      final row = _lengthRow(seeded.effortId);
      expect(tester.widget<ValueStepperRow>(row).isReadOnly, isTrue);

      await tester.tap(
        find.byKey(const Key('value-stepper-plus-duration')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(_inRow(row, '03:00'), findsOneWidget);
      expect(_plannedSecs(deps, seeded.effortId), 180);

      await tester.tap(
        find.descendant(of: row, matching: find.byType(InlineMetricEditor)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Round countdown — sets control wording (S-4407)', () {
    for (final (label, modality, noun, button) in const [
      ('sports', 'sports', 'Period', 'Log Period'),
      ('martial arts', 'cardio_endurance', 'Round', 'Log Round'),
    ]) {
      testWidgets('S-4407: $label reads $noun 2 of 3 and $button', (
        tester,
      ) async {
        final deps = await _buildDeps(modality: modality);
        final seeded = await _seedRounds(deps, rounds: 3);
        // Round 1 logged, round 2 in progress: focus lands on round 2.
        await deps.workoutState.startRound(seeded.effortId, 0);
        await deps.workoutState.endRoundEarly(seeded.effortId, 0);
        await deps.workoutState.startRound(seeded.effortId, 1);

        await _pumpDetail(tester, deps, seeded.name);

        expect(find.text('$noun 2 of 3'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, button), findsOneWidget);
      });
    }
  });

  group('Round countdown — layout and edit mode (S-4408, S-4409)', () {
    testWidgets(
      'S-4408: at 390x844 with the rest strip up everything is hittable',
      (tester) async {
        final deps = await _buildDeps(modality: 'cardio_endurance');
        final seeded = await _seedRounds(deps, rounds: 2);
        // Round 1 logged, round 2 running with its rest open: the strip shows
        // while the surface keeps its ring, row and sets control reachable.
        await deps.workoutState.startRound(seeded.effortId, 0);
        await deps.workoutState.endRoundEarly(seeded.effortId, 0);
        await deps.workoutState.startRound(seeded.effortId, 1);
        await deps.workoutState.recordRestStart(seeded.effortId, 1);

        await _pumpDetail(tester, deps, seeded.name);

        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

        final ring = find.byType(TimerRing);
        expect(ring.hitTestable(), findsOneWidget);
        final ringRect = tester.getRect(ring);
        expect(
          ringRect.width,
          greaterThan(0),
          reason: 'the ring must have a measurable box',
        );
        expect(ringRect.left, greaterThanOrEqualTo(0));
        expect(ringRect.right, lessThanOrEqualTo(390.0 + 0.5));

        expect(_lengthRow(seeded.effortId, 1).hitTestable(), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Log Round').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Round 2 of 2'), findsOneWidget);
      },
    );

    for (final (label, modality, noun) in const [
      ('martial arts', 'cardio_endurance', 'Round'),
      ('sports', 'sports', 'Period'),
    ]) {
      testWidgets(
        'S-4416: at 402x874 with the rest strip up the sets control is on '
        'screen ($label)',
        (tester) async {
          final deps = await _buildDeps(modality: modality);
          final seeded = await _seedRounds(deps, rounds: 1);

          // The device the defect was seen on: an iPhone 17 simulator, 402 x
          // 874 pt at dpr 3, with a 62 pt status bar and a 34 pt
          // home-indicator inset. The test view has no insets by default, so
          // without them the surface is ~96 dp roomier than the phone and the
          // control fits anyway. View metrics are in physical pixels.
          tester.view.physicalSize = const Size(402 * 3, 874 * 3);
          tester.view.devicePixelRatio = 3;
          tester.view.padding = const FakeViewPadding(
            top: 62 * 3,
            bottom: 34 * 3,
          );
          tester.view.viewPadding = const FakeViewPadding(
            top: 62 * 3,
            bottom: 34 * 3,
          );
          addTearDown(tester.view.reset);

          // The seeded session: one round of one, not logged, its rest open —
          // the state the lead's screenshot was taken in. The rest strip is up
          // while the sets control (the boxed "$noun 1 of 1" with its − and +)
          // still has to be visible in full without scrolling.
          await deps.workoutState.recordRestStart(seeded.effortId, 0);

          // No surface-size override: the view metrics above are the surface.
          await _pumpDetail(tester, deps, seeded.name, surfaceSize: null);

          expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
          expect(
            find.byKey(const Key('set-count-add')).hitTestable(),
            findsOneWidget,
            reason: 'the $noun control must be hittable without scrolling',
          );

          // Hittable is not enough: a control can be clipped by the bottom edge
          // of the scroll area and still answer a hit test at its centre. Both
          // halves of the control have to sit inside the scroll area's visible
          // box — the `−`, the count and the `+` are one row, so the `+` is the
          // taller box and the `−` sets the left edge.
          final scrollArea = find.byType(SingleChildScrollView);
          expect(scrollArea, findsOneWidget);
          final scrollRect = tester.getRect(scrollArea);
          final surface = tester
              .widget<MediaQuery>(find.byType(MediaQuery).first)
              .data
              .size;
          expect(
            surface,
            const Size(402, 874),
            reason: 'the harness must measure the phone, not a wider surface',
          );

          for (final key in const ['set-count-remove', 'set-count-add']) {
            final controlRect = tester.getRect(find.byKey(Key(key)));
            expect(
              controlRect.bottom,
              lessThanOrEqualTo(scrollRect.bottom),
              reason:
                  'the $noun control ($key) must be visible in full, not '
                  'clipped: control bottom '
                  '${controlRect.bottom.toStringAsFixed(1)}, scroll bottom '
                  '${scrollRect.bottom.toStringAsFixed(1)}',
            );
          }
        },
      );
    }

    testWidgets('S-4409: edit mode shows the length row and no ring', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await _pumpDetail(tester, deps, seeded.name, editMode: true);

      final row = _lengthRow(seeded.effortId);
      expect(row, findsOneWidget);
      expect(_inRow(row, '03:00'), findsOneWidget);
      expect(_inRow(row, 'ROUND LENGTH'), findsOneWidget);

      expect(find.byType(TimerRing), findsNothing);
      expect(_inRing('REMAINING'), findsNothing);
      _expectNoRemovedChrome();
    });

    testWidgets('S-4413: edit mode − on a logged 15 s round stays at 00:15', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps, durationSecs: 15);
      // Round 1 is over: it was logged at its 15 s, which is what edit mode
      // shows and edits.
      await deps.workoutState.setRoundDuration(seeded.effortId, 0, 15);

      await _pumpDetail(tester, deps, seeded.name, editMode: true);

      final row = _lengthRow(seeded.effortId);
      expect(_inRow(row, '00:15'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-minus-duration')));
      await tester.pumpAndSettle();

      expect(_inRow(row, '00:15'), findsOneWidget);
      expect(_inRow(row, '00:00'), findsNothing);
      expect(_plannedSecs(deps, seeded.effortId), 15);
    });
  });

  group('Round countdown — a later round expires on its edited length', () {
    // The row steps 15 s, so 15 s is the shortest length the `+` can write: the
    // round then really has to run that length out on the wall clock, the way
    // `round_auto_expiry_test.dart` expires a 2 s round (a real wait inside
    // `runAsync`, then `pump` to fire the tick). That is why the round here is
    // 15 s and not the 195 s the brief's `03:15` literals name — a 195 s wait
    // is not a test.
    testWidgets(
      'S-4415: the round expires on the length the later-round edit wrote',
      (tester) async {
        final deps = await _buildDeps(modality: 'cardio_endurance');
        // Three rounds of 0 s: one tap of `+` puts 15 s on them.
        final seeded = await _seedRounds(deps, rounds: 3, durationSecs: 0);
        final alert = FakeTimerAlertService();
        await _pumpDetail(tester, deps, seeded.name, alert: alert);

        // Round 1's length is the row on screen: the change reaches round 2 too.
        await tester.tap(find.byKey(const Key('value-stepper-plus-duration')));
        await tester.pumpAndSettle();
        expect(_plannedSecs(deps, seeded.effortId, 0), 15);
        expect(_plannedSecs(deps, seeded.effortId, 1), 15);
        expect(_plannedSecs(deps, seeded.effortId, 2), 15);

        // Jump to round 2 and start it: its countdown must aim at the 15 s the
        // edit wrote, not at what the round was created with.
        await tester.tap(find.byKey(const Key('set-segment-1')));
        await tester.pumpAndSettle();
        expect(find.text('Round 2 of 3'), findsOneWidget);
        expect(_inRing('00:15'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();
        expect(_inRing('REMAINING'), findsOneWidget);

        // Real time past the 15 s, then the tick: the round expires.
        await tester.runAsync(() async {
          await Future.delayed(const Duration(seconds: 16));
        });
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(
          _inRing('COMPLETED'),
          findsOneWidget,
          reason: 'round 2 must expire on the 15 s the later-round edit wrote',
        );
        expect(_inRing('00:15'), findsOneWidget);
        expect(_ringProgress(tester), 0.0);
        // The state agrees: round 2 is finished, not still counting.
        expect(
          deps.workoutState.getRoundsForEffort(seeded.effortId)[1].state,
          RoundState.finished,
        );
        // The expiry alert fires, exactly once: a reset flag is what lets the
        // edited round alert at all instead of being treated as already done.
        expect(alert.effortAlertSoundIds.length, 1);
      },
    );
  });

  group('Round countdown — restored instances (S-4410, S-4411)', () {
    testWidgets('S-4410: a paused round 45 s in reads 02:15, frozen at 0.75', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final seeded = await _seedRounds(deps);
      await deps.workoutState.startRound(seeded.effortId, 0);
      await deps.workoutState.pauseRound(seeded.effortId, 0);
      await _backdateRound(
        deps,
        effortId: seeded.effortId,
        roundIndex: 0,
        elapsed: const Duration(seconds: 45),
      );

      await _pumpDetail(tester, deps, seeded.name);

      expect(
        deps.workoutState.getRoundsForEffort(seeded.effortId).first.state,
        RoundState.paused,
      );
      expect(_inRing('02:15'), findsOneWidget);
      expect(_inRing('REMAINING'), findsOneWidget);

      // A stopped ring does not animate: two more frames paint the same value.
      final frozen = _ringProgress(tester);
      expect(frozen, 0.75);
      await tester.pump();
      await tester.pump();
      expect(_ringProgress(tester), frozen);
      expect(_inRing('02:15'), findsOneWidget);

      // A restored paused round is mid-round: its length is locked.
      expect(
        tester.widget<ValueStepperRow>(_lengthRow(seeded.effortId)).isReadOnly,
        isTrue,
      );
    });

    testWidgets(
      'S-4411: a round logged early reads 01:00 + COMPLETED, ring empty',
      (tester) async {
        final deps = await _buildDeps(modality: 'cardio_endurance');
        final seeded = await _seedRounds(deps);
        // Log early at 60 s of 180: pausing first freezes the clock, so the
        // recorded duration is exactly 60 s.
        await deps.workoutState.startRound(seeded.effortId, 0);
        await deps.workoutState.pauseRound(seeded.effortId, 0);
        await _backdateRound(
          deps,
          effortId: seeded.effortId,
          roundIndex: 0,
          elapsed: const Duration(seconds: 60),
        );
        await deps.workoutState.endRoundEarly(seeded.effortId, 0);
        await deps.workoutState.loadSessionData();

        final finished = deps.workoutState
            .getRoundsForEffort(seeded.effortId)
            .first;
        expect(finished.state, RoundState.finished);
        expect(finished.actualDurationSecs, 60);

        await _pumpDetail(tester, deps, seeded.name);

        expect(_inRing('01:00'), findsOneWidget);
        expect(_inRing('COMPLETED'), findsOneWidget);
        expect(_ringProgress(tester), 0.0);

        final row = _lengthRow(seeded.effortId);
        expect(tester.widget<ValueStepperRow>(row).isReadOnly, isTrue);
        expect(_inRow(row, '03:00'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('value-stepper-minus-duration')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(_plannedSecs(deps, seeded.effortId), 180);
        expect(_inRow(row, '03:00'), findsOneWidget);
      },
    );
  });
}
