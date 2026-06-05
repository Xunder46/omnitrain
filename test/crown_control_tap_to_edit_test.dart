import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/metric_crown_widget.dart';

import 'helpers/fake_timer_alert_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

// Build an InlineMetricEditor under test with the given parameters.
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
  // Crown presence tests (T-01 – T-04)
  // Crown is now dormant: all editable editors render NO crown.
  // ══════════════════════════════════════════════════════════════════════════

  group('Crown presence (crown is dormant — findsNothing for all editors)', () {
    // T-01
    testWidgets(
      'T-01: InlineMetricEditor (reps, not read-only) does NOT render MetricCrownWidget',
      (tester) async {
        await tester.pumpWidget(_buildEditor(metricType: 'reps', currentValue: 10));
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );

    // T-02
    testWidgets(
      'T-02: InlineMetricEditor (weight, not read-only) does NOT render MetricCrownWidget',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'weight',
          currentValue: 80.0,
          unitLabel: 'KG',
        ));
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );

    // T-03
    testWidgets(
      'T-03: neither reps nor weight editor in same tree renders MetricCrownWidget',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  InlineMetricEditor(
                    metricType: 'reps',
                    currentValue: 10,
                    unitLabel: 'REPS',
                    emphasisTier: MetricEmphasisTier.dominant,
                    onValueChanged: (_) {},
                  ),
                  InlineMetricEditor(
                    metricType: 'weight',
                    currentValue: 80.0,
                    unitLabel: 'KG',
                    emphasisTier: MetricEmphasisTier.secondary,
                    onValueChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        // Crown is dormant — both editors render no crown.
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );

    // T-04
    testWidgets(
      'T-04: InlineMetricEditor with isReadOnly:true does NOT render MetricCrownWidget',
      (tester) async {
        await tester.pumpWidget(_buildEditor(isReadOnly: true));
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Tap-to-edit behaviour tests (T-05 – T-06, rewritten from crown drag)
  // ══════════════════════════════════════════════════════════════════════════

  group('Tap-to-edit value entry (replaces crown drag)', () {
    // T-05: tapping reps number opens modal; confirm calls onValueChanged
    testWidgets(
      'T-05: tapping reps number opens modal; confirming new value calls onValueChanged',
      (tester) async {
        dynamic lastValue;
        int callCount = 0;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          onValueChanged: (v) {
            callCount++;
            lastValue = v;
          },
        ));

        // Tap the number text to open the modal.
        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.enterText(find.byType(TextField), '11');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(callCount, 1);
        expect(lastValue, 11);

        // Dragging the number text does NOT fire additional calls (no vertical
        // drag handler on the text itself — drag on number was removed).
        final countAfterConfirm = callCount;
        // The widget still shows '10' (stateless test widget, value not rebuilt).
        await tester.drag(find.text('10'), const Offset(0, -10));
        await tester.pump();
        expect(callCount, countAfterConfirm);
      },
    );

    // T-06: tapping weight number opens modal; confirm applies value
    testWidgets(
      'T-06: tapping weight number opens modal; entering 10.5 and confirming calls onValueChanged(10.5)',
      (tester) async {
        double? updatedValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'weight',
          currentValue: 10.0,
          unitLabel: 'KG',
          onValueChanged: (v) => updatedValue = v as double,
        ));

        await tester.tap(find.text('10.0'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.enterText(find.byType(TextField), '10.5');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(updatedValue, 10.5);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Crown widget mechanics (T-07 – T-09)
  // These test MetricCrownWidget directly (dormant in InlineMetricEditor but
  // still constructible and must not be deleted from the codebase).
  // ══════════════════════════════════════════════════════════════════════════

  group('Crown widget rotation mechanics (dormant widget, tested directly)', () {
    // T-07
    testWidgets(
      'T-07: rotation angle changes during drag and does not change after drag ends',
      (tester) async {
        final crownKey = GlobalKey<MetricCrownWidgetState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MetricCrownWidget(
                key: crownKey,
                metricType: 'reps',
                currentValue: 10,
                onValueChanged: (_) {},
              ),
            ),
          ),
        );

        expect(crownKey.currentState!.rotationAngle, 0.0);

        // Perform drag.
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(MetricCrownWidget)),
        );
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();

        final midAngle = crownKey.currentState!.rotationAngle;
        expect(midAngle, isNot(0.0));

        // End drag.
        await gesture.up();
        await tester.pump();

        // Pump several more frames; angle must not change further.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(crownKey.currentState!.rotationAngle, midAngle);
      },
    );

    // T-08
    testWidgets(
      'T-08: after drag ends, subsequent pump calls produce no further value changes',
      (tester) async {
        int callCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MetricCrownWidget(
                metricType: 'reps',
                currentValue: 10,
                onValueChanged: (_) => callCount++,
              ),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(MetricCrownWidget)),
        );
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump();

        await gesture.up();
        await tester.pump();

        final countAfterRelease = callCount;

        // More pump calls: no extra value changes expected.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 200));

        expect(callCount, countAfterRelease);
      },
    );

    // T-09
    testWidgets(
      'T-09: rotation magnitude is ~2× drag distance '
      '(drag 60px → rotation ≈ π radians)',
      (tester) async {
        final crownKey = GlobalKey<MetricCrownWidgetState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MetricCrownWidget(
                key: crownKey,
                metricType: 'reps',
                currentValue: 10,
                onValueChanged: (_) {},
              ),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(MetricCrownWidget)),
        );
        // Drag exactly 60 logical pixels downward.
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final angle = crownKey.currentState!.rotationAngle;
        // Expected: 60 * (2π / 120) = π  (positive = downward).
        const expected = 60 * 2 * math.pi / 120;
        expect(angle, closeTo(expected, 0.05));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Tap-to-edit popup tests (T-10 – T-13)
  // ══════════════════════════════════════════════════════════════════════════

  group('Tap-to-edit popup', () {
    // T-10
    testWidgets(
      'T-10: tapping the number Text opens dialog pre-filled with current value',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          unitLabel: 'REPS',
        ));

        // Tap the number text.
        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        // A dialog should be open.
        expect(find.byType(AlertDialog), findsOneWidget);
        // The text field should be pre-filled with '10'.
        final tf = tester.widget<TextField>(find.byType(TextField));
        expect(tf.controller?.text, '10');
      },
    );

    // T-11
    testWidgets(
      'T-11: confirming popup with valid number calls onValueChanged with parsed value',
      (tester) async {
        dynamic lastValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          unitLabel: 'REPS',
          onValueChanged: (v) => lastValue = v,
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '15');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(lastValue, 15);
      },
    );

    // T-12
    testWidgets(
      'T-12: dismissing popup via barrier tap does NOT call onValueChanged',
      (tester) async {
        int callCount = 0;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          unitLabel: 'REPS',
          onValueChanged: (_) => callCount++,
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        // Tap outside the dialog (barrier dismiss) — no Cancel button exists.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(callCount, 0);
      },
    );

    // T-13
    testWidgets(
      'T-13: popup dialog has exactly one Ok FilledButton and no Cancel button',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          unitLabel: 'REPS',
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        // Only "Ok" is present — no "Cancel".
        expect(find.text('Ok'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Confirm'), findsNothing);

        // Ok is a FilledButton.
        expect(
          find.ancestor(
            of: find.text('Ok'),
            matching: find.byType(FilledButton),
          ),
          findsOneWidget,
        );
      },
    );

    // T-10b: duration editor with custom onTap does NOT open generic popup
    testWidgets(
      'T-10b: duration editor with custom onTap calls onTap on number tap, not popup',
      (tester) async {
        bool customTapFired = false;
        bool valueChangedCalled = false;

        await tester.pumpWidget(_buildEditor(
          metricType: 'duration',
          currentValue: 120,
          unitLabel: 'ELAPSED',
          onTap: () => customTapFired = true,
          onValueChanged: (_) => valueChangedCalled = true,
        ));

        // Tap the number — should call onTap, not open popup.
        await tester.tap(find.text('02:00'));
        await tester.pumpAndSettle();

        expect(customTapFired, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        expect(valueChangedCalled, isFalse);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MetricStepCalc — value math and boundary tests (unchanged logic)
  // ══════════════════════════════════════════════════════════════════════════

  group('MetricStepCalc', () {
    test('reps: +10px drag = +1 rep', () {
      final result = MetricStepCalc.apply('reps', 5, -10.0);
      expect(result, 6);
    });

    test('reps: clamps at 0 from below', () {
      final result = MetricStepCalc.apply('reps', 0, 20.0);
      expect(result, 0);
    });

    test('reps: clamps at 999', () {
      final result = MetricStepCalc.apply('reps', 999, -20.0);
      expect(result, 999);
    });

    test('weight: 10px drag = +0.5', () {
      final result = MetricStepCalc.apply('weight', 10.0, -10.0);
      expect(result, 10.5);
    });

    test('weight: clamps at 0 (drag-step lower bound unchanged)', () {
      final result = MetricStepCalc.apply('weight', 0.0, 20.0);
      expect(result, 0.0);
    });

    test('extra-weight: supports negative values (20px down = -1.0)', () {
      // deltaY = +20.0 → change = -20 → steps = truncate(-20/10) = -2
      // newValue = 0 + (-2 * 0.5) = -1.0
      final result = MetricStepCalc.apply('extra-weight', 0.0, 20.0);
      expect(result, -1.0);
    });

    test('extra-weight: clamps at -100', () {
      final result = MetricStepCalc.apply('extra-weight', -100.0, 20.0);
      expect(result, -100.0);
    });

    test('extra-weight: clamps at 200', () {
      final result = MetricStepCalc.apply('extra-weight', 200.0, -20.0);
      expect(result, 200.0);
    });

    test('parseAndClamp: reps parses to int', () {
      final result = MetricStepCalc.parseAndClamp('reps', '15');
      expect(result, 15);
      expect(result, isA<int>());
    });

    test('parseAndClamp: weight parses to double', () {
      final result = MetricStepCalc.parseAndClamp('weight', '80.5');
      expect(result, 80.5);
      expect(result, isA<double>());
    });

    test('parseAndClamp: extra-weight accepts leading +', () {
      final result = MetricStepCalc.parseAndClamp('extra-weight', '+10.0');
      expect(result, 10.0);
    });

    test('parseAndClamp: extra-weight accepts leading -', () {
      final result = MetricStepCalc.parseAndClamp('extra-weight', '-5.0');
      expect(result, -5.0);
    });

    test('parseAndClamp: -0 normalises to 0', () {
      final result = MetricStepCalc.parseAndClamp('extra-weight', '-0');
      expect(result, 0.0);
    });

    test('parseAndClamp: empty string returns null', () {
      expect(MetricStepCalc.parseAndClamp('reps', ''), isNull);
    });

    test('parseAndClamp: non-numeric returns null', () {
      expect(MetricStepCalc.parseAndClamp('weight', 'abc'), isNull);
    });

    test('parseAndClamp: extra-weight clamps to -100', () {
      final result = MetricStepCalc.parseAndClamp('extra-weight', '-999');
      expect(result, -100.0);
    });

    test('parseAndClamp: extra-weight clamps to 200', () {
      final result = MetricStepCalc.parseAndClamp('extra-weight', '999');
      expect(result, 200.0);
    });

    // ── Negative weight entry (T-W01 – T-W04) ────────────────────────────────

    test('T-W01: parseAndClamp weight accepts -50.0', () {
      final result = MetricStepCalc.parseAndClamp('weight', '-50.0');
      expect(result, -50.0);
      expect(result, isA<double>());
    });

    test('T-W02: parseAndClamp weight accepts -200.0 (lower bound)', () {
      final result = MetricStepCalc.parseAndClamp('weight', '-200.0');
      expect(result, -200.0);
    });

    test('T-W03: parseAndClamp weight clamps -999 to -200.0', () {
      final result = MetricStepCalc.parseAndClamp('weight', '-999');
      expect(result, -200.0);
    });

    // ── Non-load metric negative clamping (T-NW01 – T-NW02) ─────────────────

    test('T-NW01: parseAndClamp reps clamps -5 to 0', () {
      final result = MetricStepCalc.parseAndClamp('reps', '-5');
      expect(result, 0);
    });

    test('T-NW02: parseAndClamp duration clamps -10 to 0', () {
      final result = MetricStepCalc.parseAndClamp('duration', '-10');
      expect(result, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Negative weight entry via modal (T-W04, T-NW03)
  // ══════════════════════════════════════════════════════════════════════════

  group('Negative weight / reps modal entry', () {
    testWidgets(
      'T-W04: tapping weight editor, entering -25.5, confirming calls onValueChanged(-25.5)',
      (tester) async {
        double? updatedValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'weight',
          currentValue: 0.0,
          unitLabel: 'KG',
          onValueChanged: (v) => updatedValue = v as double,
        ));

        await tester.tap(find.text('0.0'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '-25.5');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(updatedValue, -25.5);
      },
    );

    testWidgets(
      'T-NW03: tapping reps editor, entering -5, confirming calls onValueChanged(0) (clamped)',
      (tester) async {
        dynamic updatedValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'reps',
          currentValue: 10,
          onValueChanged: (v) => updatedValue = v,
        ));

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '-5');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(updatedValue, 0);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Codebase guard (T-G01)
  // ══════════════════════════════════════════════════════════════════════════

  group('Codebase guard', () {
    test(
      'T-G01: MetricCrownWidget is constructible (not deleted from codebase)',
      () {
        expect(
          () => MetricCrownWidget(
            metricType: 'reps',
            currentValue: 0,
            onValueChanged: (_) {},
          ),
          returnsNormally,
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Surface verification (T-14 – T-16)
  // ══════════════════════════════════════════════════════════════════════════

  group('Surface verification', () {
    Future<void> navigateToSetDetail(WidgetTester tester, String exerciseName) async {
      await tester.pumpAndSettle();
      final labelFinder = find.text(exerciseName).first;
      await tester.ensureVisible(labelFinder);
      final rowTapTarget = find.ancestor(
        of: labelFinder,
        matching: find.byType(InkWell),
      );
      if (rowTapTarget.evaluate().isNotEmpty) {
        final inkWell = tester.widget<InkWell>(rowTapTarget.first);
        if (inkWell.onTap != null) {
          inkWell.onTap!.call();
        } else {
          await tester.tap(labelFinder);
        }
      } else {
        await tester.tap(labelFinder);
      }
      await tester.pumpAndSettle();
    }

    // T-14
    testWidgets(
      'T-14: WorkoutSessionScreen live mode (free session, effortKind==set) '
      'does NOT render MetricCrownWidget; tapping reps value opens AlertDialog',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = SettingsState(repo);
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
        await workoutState.addExerciseToSession(
          exercise,
          effortKindOverride: 'set',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: sessionSummaryService,
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );

        await navigateToSetDetail(tester, exercise.name);
        // Crown is dormant.
        expect(find.byType(MetricCrownWidget), findsNothing);

        // Tap-to-edit: tapping an InlineMetricEditor opens the modal.
        final editors = find.byType(InlineMetricEditor);
        if (editors.evaluate().isNotEmpty) {
          // Find the first editable (non-read-only) editor.
          final editableEditor = tester
              .widgetList<InlineMetricEditor>(editors)
              .firstWhere((e) => !e.isReadOnly, orElse: () => tester.widget<InlineMetricEditor>(editors.first));
          if (!editableEditor.isReadOnly && editableEditor.onTap == null) {
            await tester.tap(find.byWidget(editableEditor));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            // Dismiss the dialog via barrier tap (no Cancel button).
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          }
        }
      },
    );

    // T-15
    testWidgets(
      'T-15: WorkoutSessionScreen live mode (routine session, intent=routine, '
      'effortKind==set) does NOT render MetricCrownWidget',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = SettingsState(repo);
        await settingsState.initialize();

        await workoutState.createNewSession(
          modality: 'resistance_lifting',
          intent: 'routine',
        );
        final exercises = await repo.getExercises();
        final exercise = exercises.firstWhere(
          (e) =>
              e.capabilities.contains('sets') &&
              e.capabilities.contains('load') &&
              e.capabilities.contains('reps'),
          orElse: () => exercises.first,
        );
        await workoutState.addExerciseToSession(
          exercise,
          effortKindOverride: 'set',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: sessionSummaryService,
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );

        await navigateToSetDetail(tester, exercise.name);
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );

    // T-16
    testWidgets(
      'T-16: RoutineSetupScreen (effortKind==set) exercise detail '
      'does NOT render MetricCrownWidget',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final routineState = RoutineState(repo);
        final workoutState = WorkoutState(repo);
        final settingsState = SettingsState(repo);
        await settingsState.initialize();

        routineState.setAutosaveEnabled(false);
        await routineState.createNewRoutine('Test Routine');
        await workoutState.loadAllExercises();

        final exercises = await repo.getExercises();
        final exercise = exercises.firstWhere(
          (e) =>
              e.capabilities.contains('sets') &&
              e.capabilities.contains('load') &&
              e.capabilities.contains('reps'),
          orElse: () => exercises.first,
        );
        await routineState.addExerciseToRoutine(exercise, 'set');
        await routineState.saveRoutine();
        final templateId = routineState.currentTemplate!.id;

        await tester.pumpWidget(
          MaterialApp(
            home: RoutineSetupScreen(
              routineState: routineState,
              workoutState: workoutState,
              templateId: templateId,
              settingsState: settingsState,
            ),
          ),
        );

        await navigateToSetDetail(tester, exercise.name);
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );

    // T-17: read-only timer display in live mode has no crown
    testWidgets(
      'T-17: live-mode timed editor (isReadOnly:true) does NOT render a crown',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'duration',
          currentValue: 120,
          unitLabel: 'ELAPSED',
          isReadOnly: true,
        ));
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Duration editor (crown dormant — tap-to-edit is the interaction path)
  // ══════════════════════════════════════════════════════════════════════════

  group('Duration editor in routine setup (crown dormant)', () {
    testWidgets(
      'duration editor (not read-only, no onTap) does NOT render MetricCrownWidget',
      (tester) async {
        await tester.pumpWidget(_buildEditor(
          metricType: 'duration',
          currentValue: 180,
          unitLabel: 'DURATION',
          isReadOnly: false,
        ));
        expect(find.byType(MetricCrownWidget), findsNothing);
      },
    );

    testWidgets(
      'duration editor tap-to-edit: tapping number, entering 120, confirming calls onValueChanged(120)',
      (tester) async {
        int? updatedValue;

        await tester.pumpWidget(_buildEditor(
          metricType: 'duration',
          currentValue: 60,
          unitLabel: 'DURATION',
          onValueChanged: (v) => updatedValue = v as int,
        ));

        // The formatted display is MM:SS.
        await tester.tap(find.text('01:00'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.enterText(find.byType(TextField), '120');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();

        expect(updatedValue, 120);
      },
    );
  });
}
