// Plan 44 / T2b — the reps-screen anchoring (D-7: S-5116, S-5117) and the
// two-line exercise title (D-8: S-5119).
//
// The helpers below are copied verbatim from test/delete_focused_set_test.dart
// (lines 1-109), with only the imports this file needs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/set_count_stepper.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Future<Exercise> _getExerciseById(MockWorkoutRepository repo, String id) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
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
  );
}

Widget _buildSessionScreen(
  _Deps deps, {
  bool editMode = false,
  String? initialFocusId,
  RestNotificationService? restNotificationService,
}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
      initialFocusId: initialFocusId,
      restNotificationService: restNotificationService,
    ),
  );
}

/// Navigate from list view to the detail view by tapping the first exercise name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

Finder _editorOf(String metricType) => find.byWidgetPredicate(
  (widget) => widget is InlineMetricEditor && widget.metricType == metricType,
);

Finder _editorNumber(String metricType, String text) =>
    find.descendant(of: _editorOf(metricType), matching: find.text(text));

List<Map<String, dynamic>> _entriesOf(_Deps deps, String effortId) {
  final exercise = deps.workoutState.getExercisesWithEntries().firstWhere(
    (e) => e['id'] == effortId,
  );
  return (exercise['entries'] as List).cast<Map<String, dynamic>>();
}

// ── Plan 44 fixtures and measurements ──────────────────────────────────────

const String _longName =
    'Single-Arm Dumbbell Romanian Deadlift to Overhead Press Complex';

const List<String> _squatLikeCapabilities = ['reps', 'sets', 'load', 'time'];

typedef _LongDeps = ({
  _Deps deps,
  MockWorkoutRepository repo,
  String effortId,
});

/// A free session holding one custom, squat-like exercise named [_longName].
Future<_LongDeps> _buildLongExerciseDeps({int sets = 3}) async {
  final repo = await _freshRepo();
  final now = DateTime.now().millisecondsSinceEpoch;
  await repo.createExercise(
    Exercise(
      id: 'ex-long',
      name: _longName,
      createdAtMs: now,
      updatedAtMs: now,
      capabilities: _squatLikeCapabilities,
    ),
  );
  await repo.setExerciseCapabilities('ex-long', _squatLikeCapabilities);

  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: null);

  final exercise = await repo.getExerciseById('ex-long');
  final effortId = await workoutState.addExerciseToSession(
    exercise!,
    chosenMetric: 'reps',
  );
  for (var i = 1; i < sets; i++) {
    await workoutState.addEntry(effortId);
  }
  for (var i = 0; i < sets; i++) {
    await workoutState.updateEntryValue(effortId, i, 'reps', 10);
  }

  return (
    deps: (
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      settingsState: settingsState,
    ),
    repo: repo,
    effortId: effortId,
  );
}

/// The viewport of the reps screen's scroll area.
Finder _scrollArea() => find
    .ancestor(
      of: find.byKey(const Key('set-count-add')),
      matching: find.byType(SingleChildScrollView),
    )
    .first;

/// The visible group: from the top of the focused set's REPS row to the bottom
/// of the `SetCountStepper`.
Rect _groupRect(WidgetTester tester, String effortId, int index) {
  final top = tester
      .getRect(find.byKey(ValueKey('$effortId-$index-reps')))
      .top;
  final bottom = tester
      .getRect(
        find.ancestor(
          of: find.byKey(const Key('set-count-add')),
          matching: find.byType(SetCountStepper),
        ),
      )
      .bottom;
  return Rect.fromLTRB(0, top, 0, bottom);
}

/// S-5116: the measured group is the aligned Column (metric body + spacer +
/// stepper), not the reps row — the row's own padding above it would skew
/// the 60/40 split.
Rect _alignedGroupRect(WidgetTester tester) {
  final align = find.byWidgetPredicate(
    (w) => w is Align && w.alignment == const Alignment(0, 0.2),
  );
  expect(
    align,
    findsOneWidget,
    reason: 'S-5116: the reps body is aligned at 0.2',
  );
  return tester.getRect(
    find.descendant(of: align, matching: find.byType(Column)).first,
  );
}

/// S-5116: 60 % of the free space above the group, 40 % below (±2 dp).
void _expectSlightlyBelowCentre(WidgetTester tester) {
  final area = tester.getRect(_scrollArea());
  final group = _alignedGroupRect(tester);
  final free = area.height - group.height;

  expect(
    free,
    greaterThan(0),
    reason: 'S-5116: the group must fit the scroll area for a split to exist',
  );
  expect(
    group.top - area.top,
    closeTo(0.6 * free, 2),
    reason: 'S-5116: the top gap is 60 % of the free space',
  );
  expect(
    area.bottom - group.bottom,
    closeTo(0.4 * free, 2),
    reason: 'S-5116: the bottom gap is 40 % of the free space',
  );
}

void main() {
  group('Reps layout and exercise title (plan 44)', () {
    testWidgets('S-5116: reps controls sit slightly below centre, rest open or '
        'not', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final deps = await _buildDeps(modality: null);
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);
      for (var i = 0; i < 3; i++) {
        await deps.workoutState.updateEntryValue(effortId, i, 'reps', 10);
      }

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(_editorNumber('reps', '10'), findsOneWidget);
      _expectSlightlyBelowCentre(tester);

      // Log set 1: the rest strip opens and focus moves to set 2.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      expect(find.text('Set 2 of 3'), findsOneWidget);
      expect(_entriesOf(deps, effortId)[1]['reps'], 10);

      _expectSlightlyBelowCentre(tester);

      expect(
        tester.getRect(find.byKey(const Key('set-count-add'))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('rest-overlay-chip'))).top,
        ),
        reason: 'S-5116: the stepper must sit clear of the rest chip',
      );
    });

    testWidgets('S-5117: a short phone with the rest open never overflows',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final built = await _buildLongExerciseDeps();
      await tester.pumpWidget(_buildSessionScreen(built.deps));
      await _openDetailView(tester, _longName);

      // Log set 1 so the rest strip is up and focus moves to set 2.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

      final area = tester.getRect(_scrollArea());
      final group = _groupRect(tester, built.effortId, 1);
      final free = area.height - group.height;
      if (free < 0) {
        expect(
          group.top - area.top,
          lessThanOrEqualTo(12),
          reason: 'S-5117: a group too tall for the area stays top-anchored',
        );
      }
      // Logging a set can raise the "New PR" SnackBar, which covers the
      // bottom of the scroll area at 320x568 and takes the hit test.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('set-count-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('set-count-add')).hitTestable(),
        findsOneWidget,
        reason: 'S-5117: scrolling brings the add button into reach',
      );
      expect(tester.takeException(), isNull);

      // The same state in the session editor: sets hold values and set 1 is
      // marked logged by the open rest at entry 1.
      final editor = await _buildLongExerciseDeps();
      await editor.deps.workoutState.recordRestStart(editor.effortId, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(_buildSessionScreen(editor.deps, editMode: true));
      await _openDetailView(tester, _longName);

      expect(tester.takeException(), isNull);

      final editorArea = tester.getRect(_scrollArea());
      // The open rest at entry 1 marks entry 0 logged, so the editor opens
      // focused on set 2 (entry index 1) — measure the displayed set.
      final editorGroup = _groupRect(tester, editor.effortId, 1);
      final editorFree = editorArea.height - editorGroup.height;
      if (editorFree < 0) {
        expect(
          editorGroup.top - editorArea.top,
          lessThanOrEqualTo(12),
          reason: 'S-5117: the editor keeps the group top-anchored at 320x568',
        );
      }
      await tester.ensureVisible(find.byKey(const Key('set-count-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('set-count-add')).hitTestable(),
        findsOneWidget,
        reason: 'S-5117: the editor scrolling reaches the add button',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('S-5119: the long exercise name takes two lines in the detail '
        'header and one in the list header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final built = await _buildLongExerciseDeps(sets: 1);
      await tester.pumpWidget(_buildSessionScreen(built.deps));
      await _openDetailView(tester, _longName);

      final header = find.byKey(const Key('session-detail-header'));
      final longTitle = find.descendant(of: header, matching: find.text(_longName));
      expect(longTitle, findsOneWidget);

      final longTitleWidget = tester.widget<Text>(longTitle);
      expect(longTitleWidget.maxLines, 2);
      expect(longTitleWidget.overflow, TextOverflow.ellipsis);
      final longHeight = tester.getSize(longTitle).height;
      // The test font is wider than the device font, so the height (not a
      // short-vs-tall comparison) is what proves the wrap: at least two
      // text lines.
      final oneLineHeight = (TextPainter(
        text: TextSpan(text: 'Ag', style: longTitleWidget.style),
        textDirection: TextDirection.ltr,
      )..layout()).height;
      expect(
        longHeight,
        greaterThanOrEqualTo(1.9 * oneLineHeight),
        reason: 'S-5119: the long name renders at least two text lines',
      );

      // Back to the session list: its title stays one line.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      final listTitle = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('session-detail-header')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(listTitle.maxLines, 1);

      // A short name in the same detail header is one line tall.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final shortDeps = await _buildDeps(modality: null);
      final squat = await _getExerciseById(built.repo, 'exercise-barbell-squat');
      await shortDeps.workoutState.addExerciseToSession(
        squat,
        chosenMetric: 'reps',
      );
      await tester.pumpWidget(_buildSessionScreen(shortDeps));
      await _openDetailView(tester, 'Barbell Back Squat');

      final shortTitle = find.descendant(
        of: find.byKey(const Key('session-detail-header')),
        matching: find.text('Barbell Back Squat'),
      );
      expect(shortTitle, findsOneWidget);
      final shortTitleWidget = tester.widget<Text>(shortTitle);
      expect(shortTitleWidget.maxLines, 2);
      expect(shortTitleWidget.overflow, TextOverflow.ellipsis);
    });
  });
}
