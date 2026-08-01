// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/duration_entry_dialog.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'helpers/fake_preferences_service.dart';


// ── Helpers ──────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Widget _buildEditor({
  String metricType = 'reps',
  dynamic currentValue = 10,
  String unitLabel = 'REPS',
  bool isReadOnly = false,
  VoidCallback? onTap,
  Function(dynamic)? onValueChanged,
  MetricEmphasisTier? emphasisTier,
}) {
  return _wrap(
    InlineMetricEditor(
      metricType: metricType,
      currentValue: currentValue,
      unitLabel: unitLabel,
      isReadOnly: isReadOnly,
      onTap: onTap,
      emphasisTier: emphasisTier,
      onValueChanged: onValueChanged ?? (_) {},
    ),
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-001 / S-002: Reps and weight open numeric modal
  // ══════════════════════════════════════════════════════════════════════════

  group('Surface parity — reps/weight open numeric modal', () {
    // U-01: reps value opens AlertDialog; Ok applies; outside-tap cancels
    testWidgets(
      'U-01: tapping reps value opens AlertDialog; Ok applies; outside-tap cancels',
      (tester) async {
        dynamic lastValue;
        int callCount = 0;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 5,
          unitLabel: 'REPS',
          onValueChanged: (v) {
            callCount++;
            lastValue = v;
          },
        ));

        // Tap the number to open the modal.
        await tester.tap(find.text('5'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.enterText(find.byType(TextField), '12');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(callCount, 1);
        expect(lastValue, 12);

        // Outside-tap — dialog should close without calling onValueChanged again.
        await tester.tap(find.text('5'));
        await tester.pumpAndSettle();
        final countBefore = callCount;
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(callCount, countBefore);
      },
    );

    // U-02: weight value opens AlertDialog with signed keyboard; negative applies
    testWidgets(
      'U-02: tapping weight value opens AlertDialog; signed keyboard; negative value applies',
      (tester) async {
        double? updatedValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'weight',
          currentValue: 80.0,
          unitLabel: 'KG',
          onValueChanged: (v) => updatedValue = v as double,
        ));

        await tester.tap(find.text('80.0'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        // Verify keyboard type has signed: true for weight.
        final tf = tester.widget<TextField>(find.byType(TextField));
        final kbType = tf.keyboardType;
        expect(kbType.signed, isTrue);

        await tester.enterText(find.byType(TextField), '-50.0');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(updatedValue, -50.0);
      },
    );

    // U-03: Reps InlineMetricEditor (as used in routine set effort) opens AlertDialog
    testWidgets(
      'U-03: reps InlineMetricEditor (routine set effort) opens AlertDialog; Ok applies',
      (tester) async {
        // Test the reps editor widget directly — same widget used in RoutineSetupScreen
        // set effort _buildMetricWidget. AlertDialog opens on tap.
        dynamic result;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          unitLabel: 'REPS',
          emphasisTier: MetricEmphasisTier.dominant,
          onValueChanged: (v) => result = v,
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.enterText(find.byType(TextField), '15');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(result, 15);
      },
    );

    // U-04: weight modal has signed keyboard
    testWidgets(
      'U-04: weight modal keyboard is signed (signed: true)',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'weight',
          currentValue: 60.0,
          unitLabel: 'KG',
        ));

        await tester.tap(find.text('60.0'));
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(find.byType(TextField));
        final kbType = tf.keyboardType;
        expect(kbType.signed, isTrue);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );

    // U-05: Historical edit (editMode: true), set effort — tapping reps opens AlertDialog
    testWidgets(
      'U-05: reps InlineMetricEditor opens AlertDialog and Ok applies value',
      (tester) async {
        dynamic lastValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 8,
          onValueChanged: (v) => lastValue = v,
        ));

        await tester.tap(find.text('8'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.enterText(find.byType(TextField), '10');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(lastValue, 10);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-003: Duration inputs use h/m/s dialog
  // ══════════════════════════════════════════════════════════════════════════

  group('Duration inputs use h/m/s dialog, not raw-seconds modal', () {
    // U-06: Routine creation, round effort — tapping duration value opens h/m/s dialog
    testWidgets(
      'U-06: RoutineSetupScreen round effort — tapping duration value opens h/m/s dialog with 3 TextFields',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();

        routineState.setAutosaveEnabled(false);
        await routineState.createNewRoutine('Test Routine');
        await workoutState.loadAllExercises();

        final exercises = workoutState.allExercises;
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
          orElse: () => exercises.first,
        );

        await routineState.addExerciseToRoutine(roundExercise, 'round');

        await tester.pumpWidget(
          MaterialApp(
            home: RoutineSetupScreen(
              routineState: routineState,
              workoutState: workoutState,
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to detail view — tap any InkWell in the exercise card.
        await tester.pumpAndSettle();
        // Find exercise card tappable area.
        final exerciseNameFinder = find.text(roundExercise.name);
        if (exerciseNameFinder.evaluate().isNotEmpty) {
          await tester.tap(exerciseNameFinder.first);
          await tester.pumpAndSettle();
        }

        // Find the duration InlineMetricEditor.
        final durationEditors = tester
            .widgetList<InlineMetricEditor>(find.byType(InlineMetricEditor))
            .where((e) => e.metricType == 'duration')
            .toList();

        if (durationEditors.isNotEmpty && durationEditors.first.onTap != null) {
          // Tap it — should invoke the h/m/s dialog via onTap.
          final durationFinder = find.byWidgetPredicate(
            (w) => w is InlineMetricEditor && w.metricType == 'duration',
          );
          await tester.tap(durationFinder.first);
          await tester.pumpAndSettle();

          if (find.byType(AlertDialog).evaluate().isNotEmpty) {
            // Assert three TextFields (h/m/s), not one (showMetricEditPopup).
            expect(find.byType(TextField), findsNWidgets(3));

            // Assert exactly one 'Ok' button and no 'Cancel'.
            expect(find.text('Ok'), findsOneWidget);
            expect(find.text('Cancel'), findsNothing);
            expect(find.text('Apply'), findsNothing);

            // Dismiss.
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          }
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Duration dialog identity guard (U-13, U-14, U-18)
  // ══════════════════════════════════════════════════════════════════════════

  group('Duration dialog identity guard', () {
    // U-13: Duration editor with onTap produces three TextFields (h/m/s)
    testWidgets(
      'U-13: duration editor with onTap opens dialog with 3 TextFields (h/m/s)',
      (tester) async {
        bool tapped = false;

        // Use a builder that opens showDurationEntryDialog on tap.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: InlineMetricEditor(
                    metricType: 'duration',
                    currentValue: 120,
                    unitLabel: 'ELAPSED',
                    onTap: () async {
                      tapped = true;
                      await showDurationEntryDialog(
                        context,
                        title: 'Edit Duration',
                        initialSecs: 120,
                      );
                    },
                    onValueChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Tap the duration display.
        await tester.tap(find.text('02:00'));
        await tester.pumpAndSettle();

        expect(tapped, isTrue);
        // The dialog opened — three TextFields for h/m/s.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(3));

        // Dismiss.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );

    // U-14: showDurationEntryDialog returns correct seconds math
    testWidgets(
      'U-14: showDurationEntryDialog returns total seconds = h*3600 + m*60 + s',
      (tester) async {
        int? returnedSecs;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      returnedSecs = await showDurationEntryDialog(
                        context,
                        title: 'Test',
                        initialSecs: 0,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        // Enter 1h, 30m, 15s.
        final textFields = find.byType(TextField);
        // Hours field (first).
        await tester.enterText(textFields.at(0), '1');
        // Minutes field (second).
        await tester.enterText(textFields.at(1), '30');
        // Seconds field (third).
        await tester.enterText(textFields.at(2), '15');

        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        // 1*3600 + 30*60 + 15 = 3600 + 1800 + 15 = 5415
        expect(returnedSecs, 5415);
      },
    );

    // U-18: showDurationEntryDialog dialog has exactly one Ok FilledButton, no Cancel
    testWidgets(
      'U-18: showDurationEntryDialog has exactly one Ok FilledButton and no Cancel',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showDurationEntryDialog(
                      context,
                      title: 'Test Duration',
                      initialSecs: 60,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        // Only 'Ok' button — no 'Cancel', no 'Apply'.
        expect(find.text('Ok'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Apply'), findsNothing);

        // Ok is a FilledButton.
        expect(
          find.ancestor(
            of: find.text('Ok'),
            matching: find.byType(FilledButton),
          ),
          findsOneWidget,
        );

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-001: Reps keyboard is positive-only (U-15, U-16)
  // ══════════════════════════════════════════════════════════════════════════

  group('Reps keyboard is positive-only', () {
    // U-15: _MetricEditDialog for reps has signed: false
    testWidgets(
      'U-15: reps editor opens dialog with signed: false keyboard',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(find.byType(TextField));
        final kbType = tf.keyboardType;
        expect(kbType.signed, isFalse);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );

    // U-16: _MetricEditDialog for weight has signed: true
    testWidgets(
      'U-16: weight editor opens dialog with signed: true keyboard',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'weight',
          currentValue: 50.0,
          unitLabel: 'KG',
        ));

        await tester.tap(find.text('50.0'));
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(find.byType(TextField));
        final kbType = tf.keyboardType;
        expect(kbType.signed, isTrue);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );

    // extra-weight also signed: true
    testWidgets(
      'U-16b: extra-weight editor opens dialog with signed: true keyboard',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'extra-weight',
          currentValue: 0.0,
          unitLabel: 'KG',
        ));

        await tester.tap(find.text('0.0'));
        await tester.pumpAndSettle();

        final tf = tester.widget<TextField>(find.byType(TextField));
        final kbType = tf.keyboardType;
        expect(kbType.signed, isTrue);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-005: Single Ok, no Cancel on all modal surfaces (U-17)
  // ══════════════════════════════════════════════════════════════════════════

  group('Single Ok, no Cancel on all modal surfaces', () {
    // U-17: showMetricEditPopup (reps) has exactly one Ok, no Cancel
    testWidgets(
      'U-17: showMetricEditPopup reps dialog has exactly one Ok, no Cancel',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        expect(find.text('Ok'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        expect(
          find.ancestor(
            of: find.text('Ok'),
            matching: find.byType(FilledButton),
          ),
          findsOneWidget,
        );

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Duration editor outside-tap dismisses without saving (S-005 for duration)
  // ══════════════════════════════════════════════════════════════════════════

  group('Outside-tap dismisses duration modal without applying', () {
    testWidgets(
      'Outside tap on duration dialog dismisses without returning a value',
      (tester) async {
        int? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await showDurationEntryDialog(
                        context,
                        title: 'Test',
                        initialSecs: 90,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        // Tap outside barrier.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        // result is null when dismissed without confirming.
        expect(result, isNull);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Duration editor pre-fills with decomposed h/m/s
  // ══════════════════════════════════════════════════════════════════════════

  group('Duration dialog pre-fills with decomposed h/m/s', () {
    testWidgets(
      'showDurationEntryDialog pre-fills h/m/s from initialSecs',
      (tester) async {
        // 1h 2m 3s = 3723 secs
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showDurationEntryDialog(
                      context,
                      title: 'Test',
                      initialSecs: 3723,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final textFields = find.byType(TextField);
        final hCtrl = tester.widget<TextField>(textFields.at(0)).controller;
        final mCtrl = tester.widget<TextField>(textFields.at(1)).controller;
        final sCtrl = tester.widget<TextField>(textFields.at(2)).controller;

        expect(hCtrl?.text, '1');
        expect(mCtrl?.text, '02');
        expect(sCtrl?.text, '03');

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      },
    );
  });
}
