// Plan 279 P2b — the routine editor opened from a finished session's draft.
//
// Scenarios S-27907, S-27908, S-27909, S-27911, S-27912 and the editor half
// of S-27910 of
// `docs/plans/2026-11-19-279-save-as-routine-opens-editor-plan/2026-11-19-279-save-as-routine-opens-editor-plan.md`.
// Mock repository only; everything is seeded before the first pump (no Hive,
// no `Future.delayed` inside `testWidgets`). Harness copied from
// `test/routine_unsaved_changes_guard_test.dart` (the header back arrow,
// the dialog assertions) and `test/capitalization_defaults_test.dart`
// (finding the name field by its labelText). The host pushes the editor
// the way the session summary will, so a back pops to the host page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/session_summary.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';

typedef _Deps = ({
  MockWorkoutRepository repo,
  RoutineState routineState,
  WorkoutState workoutState,
  SettingsState settingsState,
});

Future<_Deps> _buildDeps() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final routineState = RoutineState(repo)..setAutosaveEnabled(false);
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  return (
    repo: repo,
    routineState: routineState,
    workoutState: workoutState,
    settingsState: settingsState,
  );
}

// Finds the name TextField by its labelText (the label is not a descendant
// Text of the field, so `widgetWithText` is not reliable for it).
Finder _nameField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Routine Name',
);

Future<void> _tapHeaderBack(WidgetTester tester) async {
  // The OmniBackHeader always renders an IconButton with Icons.arrow_back.
  final backBtn = find
      .byWidgetPredicate(
        (w) =>
            w is IconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.arrow_back,
      )
      .first;
  await tester.tap(backBtn);
  await tester.pumpAndSettle();
}

/// The plan 279 draft: block `Upper` with the repo's first exercise
/// (3 sets: reps 8, weight 60 kg per set) and block `Legs` with the second
/// exercise (one set). Returns the draft and both exercises so the tests
/// find the rows by the exercises' own names.
Future<(SessionTemplateDraft, Exercise, Exercise)> _draft(
  MockWorkoutRepository repo,
) async {
  final exercises = await repo.getExercises();
  final upper = exercises.first;
  final legs = exercises[1];

  List<TemplateTargetDraft> setTargets(int setIndex) => [
    TemplateTargetDraft(
      metricId: MetricIds.reps,
      setIndex: setIndex,
      unitId: MetricIds.unitReps,
      valueReal: null,
      valueInt: 8,
      valueText: null,
    ),
    TemplateTargetDraft(
      metricId: MetricIds.weight,
      setIndex: setIndex,
      unitId: MetricIds.unitKg,
      valueReal: 60.0,
      valueInt: null,
      valueText: null,
    ),
  ];

  final draft = SessionTemplateDraft(
    name: 'Strength - Nov 19',
    focusModality: 'resistance_lifting',
    blocks: [
      SessionTemplateBlock(
        name: 'Upper',
        exercises: [
          SessionTemplateExercise(
            exerciseId: upper.id,
            name: upper.name,
            effortKind: 'set',
            targets: [...setTargets(0), ...setTargets(1), ...setTargets(2)],
          ),
        ],
      ),
      SessionTemplateBlock(
        name: 'Legs',
        exercises: [
          SessionTemplateExercise(
            exerciseId: legs.id,
            name: legs.name,
            effortKind: 'set',
            targets: setTargets(0),
          ),
        ],
      ),
    ],
  );
  return (draft, upper, legs);
}

Widget _host(_Deps deps, SessionTemplateDraft? draft) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RoutineSetupScreen(
                  routineState: deps.routineState,
                  workoutState: deps.workoutState,
                  settingsState: deps.settingsState,
                  fromSessionDraft: draft,
                ),
              ),
            );
          },
          child: const Text('Open editor'),
        ),
      ),
    ),
  );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _Deps deps,
  SessionTemplateDraft? draft,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(deps, draft));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  group('Plan 279 — the editor opened from a session draft', () {
    testWidgets(
      'S-27907 opening shows the draft name and blocks and stores nothing',
      (tester) async {
        final deps = await _buildDeps();
        final (draft, upper, legs) = await _draft(deps.repo);
        final beforeIds = (await deps.repo.getTemplates())
            .map((t) => t.id)
            .toList();

        await _pumpEditor(tester, deps, draft);

        final nameField = tester.widget<TextField>(_nameField());
        expect(
          nameField.controller!.text,
          'Strength - Nov 19',
          reason: 'S-27907 the name field holds the draft name',
        );
        expect(
          find.text('Upper'),
          findsOneWidget,
          reason: 'S-27907 the first block name shows in the list',
        );
        expect(
          find.text('Legs'),
          findsOneWidget,
          reason: 'S-27907 the second block name shows in the list',
        );
        expect(
          find.text(upper.name),
          findsOneWidget,
          reason: 'S-27907 the Upper block lists its exercise by name',
        );
        expect(
          find.text(legs.name),
          findsOneWidget,
          reason: 'S-27907 the Legs block lists its exercise by name',
        );
        expect(
          tester.getTopLeft(find.text(upper.name)).dy,
          lessThan(tester.getTopLeft(find.text(legs.name)).dy),
          reason: 'S-27907 the exercises render under their blocks in order',
        );

        final after = await deps.repo.getTemplates();
        expect(
          after.length,
          beforeIds.length,
          reason: 'S-27907 opening stores no template',
        );
        expect(
          after.map((t) => t.id),
          unorderedEquals(beforeIds),
          reason: 'S-27907 the stored template ids are unchanged',
        );
        expect(
          deps.routineState.hasUnsavedChanges,
          isFalse,
          reason: 'S-27907 the seeded editor starts from a clean baseline',
        );
      },
    );

    testWidgets(
      'S-27908 back with no edits pops without a dialog and stores nothing',
      (tester) async {
        final deps = await _buildDeps();
        final (draft, _, _) = await _draft(deps.repo);
        await _pumpEditor(tester, deps, draft);

        await _tapHeaderBack(tester);
        await tester.pumpAndSettle();

        expect(
          find.text('Open editor'),
          findsOneWidget,
          reason: 'S-27908 the editor popped back to the host',
        );
        expect(
          find.text('Unsaved changes'),
          findsNothing,
          reason: 'S-27908 a clean editor exits without the dialog',
        );
        expect(
          await deps.repo.getTemplates(),
          isEmpty,
          reason: 'S-27908 backing out stores nothing',
        );
      },
    );

    testWidgets(
      'S-27909 back after an edit asks, Keep editing stays, Discard pops '
      'without storing',
      (tester) async {
        final deps = await _buildDeps();
        final (draft, _, _) = await _draft(deps.repo);
        await _pumpEditor(tester, deps, draft);

        await tester.enterText(_nameField(), 'Renamed draft');
        await tester.pumpAndSettle();

        await _tapHeaderBack(tester);
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        expect(
          dialog,
          findsOneWidget,
          reason: 'S-27909 the unsaved-changes dialog shows after an edit',
        );
        expect(
          find.text('Unsaved changes'),
          findsOneWidget,
          reason: 'S-27909 the dialog is the unsaved-changes dialog',
        );
        expect(
          find.textContaining('return to the summary'),
          findsOneWidget,
          reason: 'S-27909 the body names the summary',
        );
        expect(
          find.textContaining('routines list'),
          findsNothing,
          reason: 'S-27909 the My Routines wording is not used',
        );

        await tester.tap(find.byKey(const Key('routine-edit-unsaved-keep')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27909 Keep editing closes the dialog',
        );
        expect(
          find.byType(RoutineSetupScreen),
          findsOneWidget,
          reason: 'S-27909 Keep editing stays on the editor',
        );
        expect(
          tester.widget<TextField>(_nameField()).controller!.text,
          'Renamed draft',
          reason: 'S-27909 the edit survived Keep editing',
        );

        await _tapHeaderBack(tester);
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'S-27909 backing out again asks again',
        );

        await tester.tap(find.byKey(const Key('routine-edit-unsaved-discard')));
        await tester.pumpAndSettle();
        expect(
          find.text('Open editor'),
          findsOneWidget,
          reason: 'S-27909 Discard pops back to the host',
        );
        expect(
          await deps.repo.getTemplates(),
          isEmpty,
          reason: 'S-27909 Discard stores nothing',
        );
      },
    );

    testWidgets(
      'S-27911 system back pops a clean editor and asks after an edit',
      (tester) async {
        final deps = await _buildDeps();
        final (draft, _, _) = await _draft(deps.repo);

        // Without an edit the PopScope lets the route go.
        await _pumpEditor(tester, deps, draft);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.text('Open editor'),
          findsOneWidget,
          reason: 'S-27911 a clean editor pops straight back on system back',
        );
        expect(
          find.text('Unsaved changes'),
          findsNothing,
          reason: 'S-27911 no dialog without edits',
        );

        // With an edit the system back shows the same dialog.
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.enterText(_nameField(), 'Renamed draft');
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'S-27911 system back raises the dialog after an edit',
        );
        expect(
          find.textContaining('return to the summary'),
          findsOneWidget,
          reason: 'S-27911 the dialog names the summary',
        );
        expect(
          find.textContaining('routines list'),
          findsNothing,
          reason: 'S-27911 the My Routines wording is not used',
        );

        await tester.tap(find.byKey(const Key('routine-edit-unsaved-discard')));
        await tester.pumpAndSettle();
        expect(
          find.text('Open editor'),
          findsOneWidget,
          reason: 'S-27911 Discard pops to the host',
        );
      },
    );

    testWidgets(
      'S-27912 My Routines entries stay blank and keep the routines-list '
      'wording',
      (tester) async {
        final deps = await _buildDeps();
        await _pumpEditor(tester, deps, null);

        expect(
          tester.widget<TextField>(_nameField()).controller!.text,
          '',
          reason: 'S-27912 the editor starts blank without a draft',
        );
        expect(
          find.text('Main Block'),
          findsOneWidget,
          reason: 'S-27912 the blank editor has the default Main Block',
        );

        await tester.enterText(_nameField(), 'My Own Routine');
        await tester.pumpAndSettle();
        await _tapHeaderBack(tester);
        await tester.pumpAndSettle();

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'S-27912 the dialog shows after an edit',
        );
        expect(
          find.textContaining('routines list'),
          findsOneWidget,
          reason: 'S-27912 the body names the routines list',
        );
        expect(
          find.textContaining('summary'),
          findsNothing,
          reason: 'S-27912 the summary wording is not used',
        );
      },
    );

    testWidgets(
      'S-27910 saving stores the routine with its blocks and pops to the '
      'host',
      (tester) async {
        final deps = await _buildDeps();
        final (draft, upper, legs) = await _draft(deps.repo);
        await _pumpEditor(tester, deps, draft);

        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(
          find.text('Routine saved successfully'),
          findsOneWidget,
          reason: 'S-27910 the save message was shown',
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Open editor'),
          findsOneWidget,
          reason: 'S-27910 the editor popped back to the host',
        );
        expect(
          find.byType(RoutineSetupScreen),
          findsNothing,
          reason: 'S-27910 the editor is gone after the save',
        );

        final templates = await deps.repo.getTemplates();
        expect(
          templates.length,
          1,
          reason: 'S-27910 exactly one routine was stored',
        );
        final template = templates.single;
        expect(
          template.name,
          'Strength - Nov 19',
          reason: 'S-27910 the stored name comes from the draft',
        );
        expect(
          template.focusModality,
          'resistance_lifting',
          reason: 'S-27910 the focus modality comes from the session',
        );

        final segments = await deps.repo.getTemplateSegments(template.id);
        expect(
          segments.length,
          2,
          reason: 'S-27910 one segment per draft block',
        );
        expect(
          segments[0].name,
          'Upper',
          reason: 'S-27910 the first segment is the Upper block',
        );
        expect(
          segments[0].orderIndex,
          0,
          reason: 'S-27910 the first segment is ordered 0',
        );
        expect(
          segments[1].name,
          'Legs',
          reason: 'S-27910 the second segment is the Legs block',
        );
        expect(
          segments[1].orderIndex,
          1,
          reason: 'S-27910 the second segment is ordered 1',
        );

        final upperEfforts = await deps.repo.getTemplateEfforts(segments[0].id);
        expect(
          upperEfforts.length,
          1,
          reason: 'S-27910 the Upper segment holds its exercise',
        );
        expect(
          upperEfforts[0].exerciseId,
          upper.id,
          reason: 'S-27910 the Upper effort is the draft exercise',
        );
        final upperTargets = await deps.repo.getTemplateTargets(
          upperEfforts[0].id,
        );
        final reps =
            upperTargets.where((t) => t.metricId == MetricIds.reps).toList()
              ..sort((a, b) => a.setIndex!.compareTo(b.setIndex!));
        expect(
          reps.length,
          3,
          reason: 'S-27910 the Upper effort carries 3 rep targets',
        );
        for (var i = 0; i < 3; i++) {
          expect(
            reps[i].setIndex,
            i,
            reason: 'S-27910 rep target $i has set index $i',
          );
          expect(
            reps[i].targetInt,
            8,
            reason: 'S-27910 rep target $i asks 8 reps',
          );
        }
        final weights =
            upperTargets.where((t) => t.metricId == MetricIds.weight).toList()
              ..sort((a, b) => a.setIndex!.compareTo(b.setIndex!));
        expect(
          weights.length,
          3,
          reason: 'S-27910 the Upper effort carries 3 weight targets',
        );
        for (var i = 0; i < 3; i++) {
          expect(
            weights[i].setIndex,
            i,
            reason: 'S-27910 weight target $i has set index $i',
          );
          expect(
            weights[i].targetMin,
            60.0,
            reason: 'S-27910 weight target $i is 60 kg canonical',
          );
        }

        final legsEfforts = await deps.repo.getTemplateEfforts(segments[1].id);
        expect(
          legsEfforts.length,
          1,
          reason: 'S-27910 the Legs segment holds its exercise',
        );
        expect(
          legsEfforts[0].exerciseId,
          legs.id,
          reason: 'S-27910 the Legs effort is the draft exercise',
        );
      },
    );

    testWidgets('S-27910 a rename before save names the stored routine', (
      tester,
    ) async {
      final deps = await _buildDeps();
      final (draft, _, _) = await _draft(deps.repo);
      await _pumpEditor(tester, deps, draft);

      await tester.enterText(_nameField(), 'My Push Day');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final templates = await deps.repo.getTemplates();
      expect(
        templates.single.name,
        'My Push Day',
        reason: 'S-27910 the rename stuck into the saved routine',
      );
    });
  });
}
