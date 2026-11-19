// Widget-level tests for the active-session list progress (plan 255,
// `2026-11-19-255-active-session-list-progress-plan.md`).
//
// The exercise list tile of the live workout screen reads how far a
// `set` or hold (`drill`) exercise is (`N of M sets` / `N of M holds`)
// and carries a done mark once every entry is logged. "Logged" is the
// app's own rule (`_isSetLogged`): a set when a rest exists for the
// NEXT entry (`recordRestStart(effortId, nextEntryIndex)`), a hold
// when its TimedInstance reached `TimedState.finished`.
//
// Harness copied from `test/exercise_set_last_value_test.dart`
// (`_freshRepo`, `_buildSessionDeps`, the screen pump). The pump stops
// on the LIST: the tile is the `ListTile` whose title is the exercise
// name, so its subtitle is read straight from the tile. Timed (`timed`)
// and round exercises are pinned unchanged in S-25507.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A [MockWorkoutRepository] whose `updateTimedInstance` write can be parked
/// behind a [Completer] gate — the stand-in for a slow store (Hive on a
/// device). While `gate` is set and uncompleted the write never resolves, so
/// `TimerManager.finishTimedEntry`'s
/// `await _repository.updateTimedInstance(updated); list[i] = updated;
/// _notify();` stays parked and the in-memory instance remains `active`
/// (S-25509's device timing).
class _GatedTimedRepo extends MockWorkoutRepository {
  Completer<void>? gate;

  @override
  Future<void> updateTimedInstance(TimedInstance instance) async {
    final g = gate;
    if (g != null) await g.future;
    return super.updateTimedInstance(instance);
  }
}

typedef _SessionDeps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  String exerciseName,
  String effortId,
  MockWorkoutRepository repo,
});

Future<_SessionDeps> _buildSessionDeps({
  required String effortKind,
  int entryCount = 1,
  bool suppressHints = false,
  bool gatedRepo = false,
}) async {
  final repo = gatedRepo ? _GatedTimedRepo() : MockWorkoutRepository();
  await repo.initialize();
  // Same suppression `test/round_auto_expiry_test.dart` applies: first-run
  // coach-mark sheets interfere with finder assertions in the detail view.
  if (suppressHints) {
    await repo.setPreferenceBool('hint_seen_exercise_info', true);
    await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  }
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, FakePreferencesService());
  await settingsState.initialize();

  await workoutState.createNewSession(modality: 'resistance_lifting');
  final exercises = await repo.getExercises();
  final exercise = exercises.firstWhere(
    (e) =>
        e.capabilities.contains('sets') &&
        e.capabilities.contains('load') &&
        e.capabilities.contains('reps'),
    orElse: () => exercises.first,
  );
  final effortId = await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: effortKind,
  );
  expect(effortId, isNotEmpty);

  // addExerciseToSession seeds the first entry; grow to the requested count.
  for (var i = 1; i < entryCount; i++) {
    await workoutState.addEntry(effortId);
  }
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exerciseName: exercise.name,
    effortId: effortId,
    repo: repo,
  );
}

/// Same fixture as [_buildSessionDeps], but the effort is written straight
/// into the repository and carries NO entries (S-25508): the live session's
/// segment takes a `set` effort whose observations list stays empty, and the
/// next screen load (`loadSessionData` re-reads the repository) must show it
/// as 0 sets with no done mark.
Future<_SessionDeps> _buildEmptyEntrySessionDeps() async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, FakePreferencesService());
  await settingsState.initialize();

  await workoutState.createNewSession(modality: 'resistance_lifting');
  final exercises = await repo.getExercises();
  final exercise = exercises.firstWhere(
    (e) =>
        e.capabilities.contains('sets') &&
        e.capabilities.contains('load') &&
        e.capabilities.contains('reps'),
    orElse: () => exercises.first,
  );

  final effortId = 'e-empty';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: workoutState.segments.first.id,
      orderIndex: 5,
      effortKind: 'set',
      exerciseId: exercise.id,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exerciseName: exercise.name,
    effortId: effortId,
    repo: repo,
  );
}

/// Pumps the screen and waits until the exercise list is showing.
///
/// Plain `pump()` calls only: the screen holds a 1 s periodic ticker
/// whenever it is not in edit mode, so `pumpAndSettle` would chase it
/// forever, and any open rest (a logged set) can keep animation frames
/// scheduled too. The exercise list loads in a post-frame callback, so
/// the loop pumps until the tile title is on stage.
Future<void> _pumpSessionList(
  WidgetTester tester,
  _SessionDeps deps, {
  bool editMode = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // A unique root key per fixture: pumpWidget updates (not unmounts) a root
  // whose runtimeType and key match, so a second fixture in the same test
  // would otherwise reuse the first screen's element and its cached
  // exercises. The key forces a fresh mount.
  await tester.pumpWidget(
    KeyedSubtree(
      key: ValueKey('p255-${deps.effortId}-${editMode ? 'edit' : 'live'}'),
      child: MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: deps.workoutState,
          routineState: deps.routineState,
          sessionSummaryService: deps.sessionSummaryService,
          timerAlertService: FakeTimerAlertService(),
          settingsState: deps.settingsState,
          editMode: editMode,
        ),
      ),
    ),
  );

  for (var i = 0; i < 10; i++) {
    await tester.pump();
    if (find.text(deps.exerciseName).evaluate().isNotEmpty) return;
  }
  fail('exercise list did not render ${deps.exerciseName} within 10 pumps');
}

void main() {
  group(
    'WorkoutSessionScreen list — exercise progress and done mark (255)',
    () {
      testWidgets(
        'S-25501: set exercise, 3 entries, none logged reads 0 of 3 sets '
        'and carries no done mark',
        (tester) async {
          final deps = await _buildSessionDeps(
            effortKind: 'set',
            entryCount: 3,
          );
          await _pumpSessionList(tester, deps);

          expect(find.text('0 of 3 sets'), findsOneWidget);
          expect(
            find.byKey(Key('exercise_tile_done_${deps.effortId}')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'S-25502: two of three sets logged reads 2 of 3 sets, no done mark',
        (tester) async {
          final deps = await _buildSessionDeps(
            effortKind: 'set',
            entryCount: 3,
          );
          final effortId = deps.effortId;
          final workoutState = deps.workoutState;

          // Log sets 1 and 2: a rest at the NEXT entry index (1 and 2).
          await workoutState.recordRestStart(effortId, 1);
          await workoutState.recordRestStart(effortId, 2);

          await _pumpSessionList(tester, deps);

          expect(find.text('2 of 3 sets'), findsOneWidget);
          expect(find.byKey(Key('exercise_tile_done_$effortId')), findsNothing);
        },
      );

      testWidgets(
        'S-25503: all three sets logged reads 3 of 3 sets and carries the '
        'done mark labelled Done',
        (tester) async {
          final deps = await _buildSessionDeps(
            effortKind: 'set',
            entryCount: 3,
          );
          final effortId = deps.effortId;
          final workoutState = deps.workoutState;

          // The last set logs the same way the screen's Log Set does: a rest
          // at the next entry index, which for the final set is entries.length.
          await workoutState.recordRestStart(effortId, 1);
          await workoutState.recordRestStart(effortId, 2);
          await workoutState.recordRestStart(effortId, 3);

          await _pumpSessionList(tester, deps);

          expect(find.text('3 of 3 sets'), findsOneWidget);
          final tile = tester.widget<ListTile>(
            find
                .ancestor(
                  of: find.text(deps.exerciseName),
                  matching: find.byType(ListTile),
                )
                .first,
          );
          expect((tile.subtitle! as Text).data, '3 of 3 sets');

          final done = tester.widget<Icon>(
            find.byKey(Key('exercise_tile_done_$effortId')),
          );
          expect(done.semanticLabel, 'Done');
        },
      );

      testWidgets(
        'S-25504: one logged entry reads 1 of 1 set (singular) and the mark',
        (tester) async {
          final deps = await _buildSessionDeps(effortKind: 'set');
          final effortId = deps.effortId;

          await deps.workoutState.recordRestStart(effortId, 1);
          await _pumpSessionList(tester, deps);

          expect(find.text('1 of 1 set'), findsOneWidget);
          expect(
            find.byKey(Key('exercise_tile_done_$effortId')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'S-25505: hold exercise counts finished holds, 1 of 3 then 3 of 3 '
        'with the mark',
        (tester) async {
          final deps = await _buildSessionDeps(
            effortKind: 'drill',
            entryCount: 3,
          );
          final effortId = deps.effortId;
          final workoutState = deps.workoutState;

          // Finish hold 1 before the pump (start then finish, as the detail
          // view's timer buttons do).
          await workoutState.startTimedEntry(effortId, 0);
          await workoutState.finishTimedEntry(effortId, 0);

          await _pumpSessionList(tester, deps);

          expect(find.text('1 of 3 holds'), findsOneWidget);
          expect(find.byKey(Key('exercise_tile_done_$effortId')), findsNothing);

          // Finish the remaining holds; the state change rebuilds the list.
          await workoutState.startTimedEntry(effortId, 1);
          await workoutState.finishTimedEntry(effortId, 1);
          await workoutState.startTimedEntry(effortId, 2);
          await workoutState.finishTimedEntry(effortId, 2);

          // A direct state write does not itself rebuild the list (the screen
          // only reloads on navigation and watch revisions); a state change the
          // list is showing mid-session rebuilds the same widgets this way.
          tester.element(find.byType(WorkoutSessionScreen)).markNeedsBuild();
          await tester.pump();

          expect(find.text('3 of 3 holds'), findsOneWidget);
          final done = tester.widget<Icon>(
            find.byKey(Key('exercise_tile_done_$effortId')),
          );
          expect(done.semanticLabel, 'Done');
        },
      );

      testWidgets(
        'S-25506: edit mode keeps the old 3 sets text and shows no mark even '
        'when every set is logged',
        (tester) async {
          final deps = await _buildSessionDeps(
            effortKind: 'set',
            entryCount: 3,
          );
          final effortId = deps.effortId;
          final workoutState = deps.workoutState;

          await workoutState.recordRestStart(effortId, 1);
          await workoutState.recordRestStart(effortId, 2);
          await workoutState.recordRestStart(effortId, 3);

          await _pumpSessionList(tester, deps, editMode: true);

          expect(find.text('3 sets'), findsOneWidget);
          expect(find.text('3 of 3 sets'), findsNothing);
          expect(find.byKey(Key('exercise_tile_done_$effortId')), findsNothing);
        },
      );

      testWidgets(
        'S-25507: timed shows its total and round shows the round count; '
        'neither carries a mark or an of-count',
        (tester) async {
          // Interval (timed): fresh entry, nothing timed yet — 00:00 total.
          final timed = await _buildSessionDeps(effortKind: 'timed');
          await _pumpSessionList(tester, timed);
          expect(find.text('00:00 total'), findsOneWidget);
          expect(
            find.byKey(Key('exercise_tile_done_${timed.effortId}')),
            findsNothing,
          );

          // Round: the seeded entry is one round instance (never started), so
          // the base behaviour reads the singular round count, no mark.
          final round = await _buildSessionDeps(effortKind: 'round');
          await _pumpSessionList(tester, round);
          final roundTile = tester.widget<ListTile>(
            find
                .ancestor(
                  of: find.text(round.exerciseName),
                  matching: find.byType(ListTile),
                )
                .first,
          );
          final roundSubtitle = (roundTile.subtitle! as Text).data;
          expect(roundSubtitle, '1 round');
          expect(
            find.byKey(Key('exercise_tile_done_${round.effortId}')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'S-25507b: timed with every entry finished still shows only the '
        'total subtitle and carries no done mark',
        (tester) async {
          final deps = await _buildSessionDeps(effortKind: 'timed');
          final effortId = deps.effortId;

          // Finish the single entry the same way S-25505 finishes holds.
          await deps.workoutState.startTimedEntry(effortId, 0);
          await deps.workoutState.finishTimedEntry(effortId, 0);

          await _pumpSessionList(tester, deps);

          expect(find.text('00:00 total'), findsOneWidget);
          expect(
            find.byKey(Key('exercise_tile_done_$effortId')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'S-25508: an exercise with zero entries reads 0 sets and carries '
        'no done mark',
        (tester) async {
          final deps = await _buildEmptyEntrySessionDeps();
          await _pumpSessionList(tester, deps);

          expect(find.text('0 sets'), findsOneWidget);
          expect(
            find.byKey(Key('exercise_tile_done_${deps.effortId}')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'S-25509: a hold that finishes itself while the list is on stage '
        'updates its tile even when the store write is slow',
        (tester) async {
          // Auto-expiry harness copied from `test/round_auto_expiry_test.dart`
          // (S-BUG-001): a short target, Start tapped in the detail view, real
          // wall-clock time passes, then one fake-clock pump fires the
          // Timer.periodic tick whose callback derives elapsed from
          // `DateTime.now()` (see `TimedInstance.elapsedMs`). The comments in
          // the round test explain what must be pumped and why.
          //
          // The repository is gated (`_GatedTimedRepo`): from the moment
          // `repo.gate` is set, every `updateTimedInstance` write parks until
          // the gate opens — the stand-in for Hive on a device, where
          // `TimerManager.finishTimedEntry`'s
          // `await _repository.updateTimedInstance(updated);
          // list[entryIndex] = updated; _notify();` stays parked and the
          // in-memory instance stays `active` until the write finishes.
          final deps = await _buildSessionDeps(
            effortKind: 'drill',
            suppressHints: true,
            gatedRepo: true,
          );
          final effortId = deps.effortId;
          final workoutState = deps.workoutState;
          final repo = deps.repo as _GatedTimedRepo;

          // One seeded entry, target duration 2 s. A hold's target is the
          // entry's `duration` metric (`_getEffortTargetDuration`, 'drill'
          // case) — the same key the detail view's duration dial writes.
          await workoutState.updateEntryValue(effortId, 0, 'duration', 2);

          await _pumpSessionList(tester, deps);

          expect(find.text('0 of 1 hold'), findsOneWidget);
          expect(find.byKey(Key('exercise_tile_done_$effortId')), findsNothing);

          // Open the hold's detail view (plain pumps: the screen holds a 1 s
          // ticker whenever it is not in edit mode, so `pumpAndSettle` would
          // chase it forever — see [_pumpSessionList]).
          await tester.tap(find.text(deps.exerciseName));
          await tester.pump();
          await tester.pump();
          await tester.pump();

          // Start with the gate still null: the start's own timed-instance
          // write goes through.
          expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Start'));
          await tester.pump();
          await tester.pump();
          await tester.pump();

          // Let the wall clock pass the 2 s target in real time WITHOUT
          // pumping a tick: the fake-async timers only run on the next
          // `pump(Duration)`, so the tile keeps its old count after the user
          // goes back while the timer is still running.
          await tester.runAsync(() async {
            await Future.delayed(const Duration(seconds: 3));
          });

          // Back to the list via the header back arrow (the detail view's own
          // arrows are InkWells, not IconButtons, so this finder is unambiguous).
          final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
          expect(back, findsOneWidget);
          await tester.tap(back);
          await tester.pump();
          await tester.pump();
          await tester.pump();

          // Still on stage with the old count: no tick has fired yet.
          expect(find.text('0 of 1 hold'), findsOneWidget);
          expect(find.byKey(Key('exercise_tile_done_$effortId')), findsNothing);

          // NOW park the store. Every following updateTimedInstance write
          // waits on the gate.
          repo.gate = Completer<void>();

          // Fire the periodic tick (the effort timer and the screen ticker
          // both live in fake-async): elapsed is wall-clock past the target,
          // so _handleEffortTimerExpired runs. Its early `setState` marks the
          // tile dirty, but the finish write is parked on the gate, so the
          // in-memory instance is still `active` when the frame builds.
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          await tester.pump();

          // The write is parked: the tile still reads the old count and has
          // no mark.
          expect(find.text('0 of 1 hold'), findsOneWidget);
          expect(find.byKey(Key('exercise_tile_done_$effortId')), findsNothing);

          // Open the gate: the write resolves, TimerManager swaps the finished
          // instance into the in-memory list and notifies, and the finish
          // future's `.then` `setState` (the lead edit, plan 255 finding 2)
          // rebuilds the tile — no markNeedsBuild and no reopening here.
          repo.gate!.complete();
          await tester.pump();
          await tester.pump();

          expect(find.text('1 of 1 hold'), findsOneWidget);
          final done = tester.widget<Icon>(
            find.byKey(Key('exercise_tile_done_$effortId')),
          );
          expect(done.semanticLabel, 'Done');
        },
      );
    },
  );
}
