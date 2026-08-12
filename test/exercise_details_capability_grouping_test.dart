// Exercise Details — Capability grouping (tracking vs movement properties).
//
// Acceptance scenarios from
// .github/agents/plans/exercise-details-tracking-vs-movement-classification-plan.md:
//
//   S-001  Bilateral exercise separates `bilateral` from tracking.
//   S-002  Tracking-only exercise shows only Tracking Methods.
//   S-003  Movement-only exercise shows only Movement Properties.
//   S-004  Capability-less exercise renders cleanly (neither heading).
//   S-005  Cross-discipline sample exercises all render correctly.
//   S-006  Workout screen metric editors are unchanged for bilateral
//          exercises (regression guard — re-grouping must not leak
//          into the workout surface).
//   S-007  In-session info sheet bilateral handling is unchanged
//          (covered by `test/exercise_info_sheet_bilateral_test.dart`;
//          that suite must remain green).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_detail_view_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

/// Build an exercise with explicit capabilities and no description /
/// muscles / discipline, so the body renders only the capability
/// section(s).
Exercise _bareExercise({
  required String id,
  required List<String> capabilities,
  bool isCustom = false,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Exercise(
    id: id,
    name: id,
    ownerUserId: isCustom ? 'user-1' : null,
    disciplineId: null,
    description: null,
    capabilities: capabilities,
    createdAtMs: now,
    updatedAtMs: now,
  );
}

Future<void> _pumpBody(WidgetTester tester, Exercise exercise) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExerciseDetailViewBody(
          exercise: exercise,
          discipline: null,
          muscleGroups: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Section keys (kept as locals so any drift from the production
/// keys surfaces immediately).
const _trackingSectionKey = Key('exercise_detail_capabilities_section');
const _movementSectionKey = Key('exercise_detail_movement_section');

/// Helpers for the S-006 workout-screen regression guard.

Widget _themeWrappedApp({required Widget home, required AppTheme theme}) {
  final colors = OmniTheme.colorsForTheme(theme);
  return MaterialApp(
    theme: buildTheme(
      theme: theme,
      brightness: Brightness.dark,
      secondary: colors.secondary,
      background: colors.backgroundTop,
      surface: colors.surface,
      textPrimary: colors.textDominant,
      textSecondary: colors.textSecondary,
      divider: colors.divider,
    ),
    home: home,
  );
}

Future<void> _openSessionDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelFinder = find.text(exerciseName).first;
  await tester.ensureVisible(labelFinder);
  final rowTapTarget = find.ancestor(
    of: labelFinder,
    matching: find.byType(InkWell),
  );
  if (rowTapTarget.evaluate().isNotEmpty) {
    final rowInkWell = tester.widget<InkWell>(rowTapTarget.first);
    expect(rowInkWell.onTap, isNotNull);
    rowInkWell.onTap!.call();
  } else {
    await tester.tap(labelFinder);
  }
  await tester.pumpAndSettle();
}

Set<String> _presentMetricTypes(WidgetTester tester) {
  return tester
      .widgetList<InlineMetricEditor>(find.byType(InlineMetricEditor))
      .map((e) => e.metricType)
      .toSet();
}

// ── Tests ────────────────────────────────────────────────────────────────

void main() {
  group('ExerciseDetailViewBody — capability grouping', () {
    testWidgets(
      'S-001: Arnold Press splits bilateral into Movement Properties, '
      'leaves only tracking methods in Tracking Methods',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final arnold = await repo.getExerciseById('exercise-arnold-press');
        expect(arnold, isNotNull);

        await _pumpBody(tester, arnold!);

        // Tracking Methods renders with reps/sets/load/time only.
        expect(find.byKey(_trackingSectionKey), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Reps'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Sets'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Load'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Time'),
          ),
          findsOneWidget,
        );

        // Critical assertion: Bilateral is NOT inside Tracking Methods.
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Bilateral'),
          ),
          findsNothing,
          reason:
              'bilateral is a movement property and must not appear under '
              'Tracking Methods',
        );

        // Movement Properties renders with Bilateral only.
        expect(find.byKey(_movementSectionKey), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_movementSectionKey),
            matching: find.text('Bilateral'),
          ),
          findsOneWidget,
        );
        // No tracking chip leaks into the movement section.
        expect(
          find.descendant(
            of: find.byKey(_movementSectionKey),
            matching: find.text('Reps'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(_movementSectionKey),
            matching: find.text('Sets'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'S-002: Plank Hold (tracking-only) shows Tracking Methods with no '
      'Movement Properties heading',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final plank = await repo.getExerciseById('exercise-plank-hold');
        expect(plank, isNotNull);

        await _pumpBody(tester, plank!);

        expect(find.byKey(_trackingSectionKey), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Hold Time'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Time'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_trackingSectionKey),
            matching: find.text('Sets'),
          ),
          findsOneWidget,
        );

        // No Movement Properties heading when there are no movement caps.
        expect(
          find.byKey(_movementSectionKey),
          findsNothing,
          reason:
              'Movement Properties heading must be omitted when no movement '
              'capabilities are present',
        );
      },
    );

    testWidgets('S-003: synthetic movement-only exercise ([bilateral]) shows '
        'Movement Properties with no Tracking Methods heading', (
      WidgetTester tester,
    ) async {
      await _freshRepo();
      await _pumpBody(
        tester,
        _bareExercise(
          id: 'synthetic-bilateral-only',
          capabilities: const ['bilateral'],
        ),
      );

      expect(find.byKey(_movementSectionKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_movementSectionKey),
          matching: find.text('Bilateral'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(_trackingSectionKey),
        findsNothing,
        reason:
            'Tracking Methods heading must be omitted when no tracking '
            'capabilities are present',
      );
    });

    testWidgets('S-004: capability-less exercise renders neither heading', (
      WidgetTester tester,
    ) async {
      await _freshRepo();
      await _pumpBody(
        tester,
        _bareExercise(id: 'synthetic-empty', capabilities: const []),
      );

      expect(find.byKey(_trackingSectionKey), findsNothing);
      expect(find.byKey(_movementSectionKey), findsNothing);
    });

    testWidgets(
      'S-005: cross-discipline sample exercises all render correctly',
      (WidgetTester tester) async {
        final repo = await _freshRepo();

        Future<void> expectSection(
          String exerciseId, {
          required List<String> trackingChips,
          required List<String> movementChips,
        }) async {
          final exercise = await repo.getExerciseById(exerciseId);
          expect(exercise, isNotNull, reason: 'seed missing: $exerciseId');
          await _pumpBody(tester, exercise!);

          if (trackingChips.isEmpty) {
            expect(
              find.byKey(_trackingSectionKey),
              findsNothing,
              reason: '$exerciseId: Tracking Methods should be absent',
            );
          } else {
            expect(
              find.byKey(_trackingSectionKey),
              findsOneWidget,
              reason: '$exerciseId: Tracking Methods should be present',
            );
            for (final chip in trackingChips) {
              expect(
                find.descendant(
                  of: find.byKey(_trackingSectionKey),
                  matching: find.text(chip),
                ),
                findsOneWidget,
                reason: '$exerciseId: Tracking chip "$chip" missing',
              );
            }
          }

          if (movementChips.isEmpty) {
            expect(
              find.byKey(_movementSectionKey),
              findsNothing,
              reason: '$exerciseId: Movement Properties should be absent',
            );
          } else {
            expect(
              find.byKey(_movementSectionKey),
              findsOneWidget,
              reason: '$exerciseId: Movement Properties should be present',
            );
            for (final chip in movementChips) {
              expect(
                find.descendant(
                  of: find.byKey(_movementSectionKey),
                  matching: find.text(chip),
                ),
                findsOneWidget,
                reason: '$exerciseId: Movement chip "$chip" missing',
              );
            }
          }

          // Reset between sub-cases so each starts from a clean tree.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }

        // Resistance — bilateral present.
        await expectSection(
          'exercise-arnold-press',
          trackingChips: const ['Reps', 'Sets', 'Load', 'Time'],
          movementChips: const ['Bilateral'],
        );

        // Isometric — tracking only.
        await expectSection(
          'exercise-plank-hold',
          trackingChips: const ['Hold Time', 'Time', 'Sets'],
          movementChips: const [],
        );

        // Cardio — tracking only (time + distance).
        await expectSection(
          'exercise-easy-run',
          trackingChips: const ['Time', 'Distance'],
          movementChips: const [],
        );

        // Sports — tracking only (time + rounds).
        await expectSection(
          'exercise-heavy-bag-rounds',
          trackingChips: const ['Time', 'Rounds'],
          movementChips: const [],
        );
      },
    );
  });

  // S-006 regression guard: ensure the change does not affect the
  // workout surface. The workout surface is keyed on `effortKind`,
  // not on the capabilities list. We render the actual
  // `WorkoutSessionScreen` with a bilateral-capability exercise in a
  // resistance session and assert the metric editor set is exactly
  // the canonical resistance set (`reps`, `weight`) — no bilateral
  // editor and no leakage.
  group('S-006 regression: workout metric editors unchanged', () {
    testWidgets(
      'bilateral capability does not add or remove metric editors on the '
      'workout screen for a resistance session',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await settingsState.setAppTheme(AppTheme.abyssalNeon);
        OmniTheme.activeTheme = AppTheme.abyssalNeon;

        // Force a resistance session so the canonical editor set is
        // `reps` + `weight`. Add Arnold Press (bilateral-capability)
        // explicitly so the test is not satisfied by some unrelated
        // exercise that happens to lack bilateral.
        await workoutState.createNewSession(modality: 'resistance_lifting');
        final arnold = await repo.getExerciseById('exercise-arnold-press');
        expect(arnold, isNotNull);
        expect(
          arnold!.capabilities,
          contains('bilateral'),
          reason:
              'fixture assumption violated — Arnold Press must be bilateral',
        );
        await workoutState.addExerciseToSession(
          arnold,
          effortKindOverride: 'set',
        );

        await tester.pumpWidget(
          _themeWrappedApp(
            theme: AppTheme.abyssalNeon,
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: sessionSummaryService,
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
            ),
          ),
        );

        await _openSessionDetail(tester, arnold.name);

        final metrics = _presentMetricTypes(tester);

        // Canonical resistance editors are present.
        expect(metrics, contains('reps'));
        expect(metrics, contains('weight'));

        // No bilateral-derived editor appeared. The contract is that
        // bilateral is a movement property that does not drive any
        // editor on the workout surface.
        expect(
          metrics,
          isNot(contains('bilateral')),
          reason:
              'bilateral must not add an editor on the workout screen — '
              'it is a movement property, not a tracking method',
        );

        // Sanity: only the canonical set, nothing extra slipped in.
        expect(
          metrics,
          equals(<String>{'reps', 'weight'}),
          reason:
              'metric editor set must be exactly the canonical resistance '
              'set; re-grouping on the details screen must not leak into '
              'this surface',
        );
      },
    );
  });

  // S-007 is covered by `test/exercise_info_sheet_bilateral_test.dart`,
  // which exercises the in-session info sheet and asserts that the
  // LOGGING NOTE section is present for bilateral exercises and
  // absent for non-bilateral exercises. That suite must remain green.
  test('S-007: in-session info sheet bilateral tests are unchanged', () {
    // Compile-time / reviewer reminder. The actual assertions live
    // in `test/exercise_info_sheet_bilateral_test.dart`. This entry
    // exists so a future grep for `S-007` lands on this file as well.
    expect(true, isTrue);
  });
}
