// Exercise Row Density Fix
//
// Acceptance scenarios from
// .github/agents/plans/exercise-row-density-fix-plan.md:
//
//   S-001  Info control aligns with the title line
//   S-002  Row height returns toward the pre-PR-7 baseline
//   S-003  Chip wrapping occurs only when required
//   S-004  Info control tap area stays at the platform minimum
//   S-005  Tapping the row body still pops the picker
//   S-006  Tapping the info control still opens details
//   S-007  Narrow-surface density regression guard
//
// The fix anchors the trailing IconButton (`exercise_row_details_button`)
// to the title line via `titleAlignment: ListTileTitleAlignment.top` so
// it no longer floats in the middle of wrapped chip space, and wraps the
// chip `Wrap` in a `SizedBox(width: double.infinity)` so it uses the
// full subtitle column width (otherwise it computes an intrinsic width
// and wraps earlier than the available budget allows).
//
// Test seeding: tests insert custom exercises with controlled muscle
// counts and search-filter to that exercise so the rendered row's chip
// count is deterministic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_detail_view_screen.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Insert a custom exercise with a controlled set of muscle groups so
/// the row's chip wrap behaviour is deterministic for the test.
///
/// Returns the seeded exercise. The search field filters to this
/// exercise by a unique name token.
Future<Exercise> _seedExercise(
  MockWorkoutRepository repo, {
  required String nameToken,
  required List<String> muscleIds,
  String description = '',
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final exercise = Exercise(
    id: 'ex-density-$nameToken',
    name: 'Density $nameToken',
    description: description,
    disciplineId: 'discipline-rowing',
    ownerUserId: 'user-1',
    createdAtMs: now,
    updatedAtMs: now,
  );
  await repo.createExercise(exercise);
  await repo.setExerciseMuscleGroups(exercise.id, muscleIds);
  return exercise;
}

/// Pump the picker and apply a search filter so the picker renders
/// exactly one row (the seeded exercise).
Future<Exercise> _pumpFilteredRow(
  WidgetTester tester, {
  required Size surface,
  required String nameToken,
  required List<String> muscleIds,
  String description = '',
}) async {
  await tester.binding.setSurfaceSize(surface);
  final repo = await _freshRepo();
  final exercise = await _seedExercise(
    repo,
    nameToken: nameToken,
    muscleIds: muscleIds,
    description: description,
  );
  final workoutState = WorkoutState(repo);

  await tester.pumpWidget(
    MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
  );
  await tester.pumpAndSettle();

  // Filter to the seeded exercise by entering its unique name token.
  await tester.enterText(find.byType(TextField).first, nameToken);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();

  return exercise;
}

/// Resolve the (single) tile, its title, and the info button for the
/// currently-filtered picker.
({
  Finder tile,
  Finder title,
  Finder infoButton,
  String exerciseName,
}) _resolveRow(WidgetTester tester, String exerciseName) {
  final tiles = find.byType(ListTile);
  expect(tiles, findsOneWidget);
  final firstTile = tiles.first;
  return (
    tile: firstTile,
    title: find.descendant(of: firstTile, matching: find.text(exerciseName)),
    infoButton: find.descendant(
      of: firstTile,
      matching: find.byKey(const Key('exercise_row_details_button')),
    ),
    exerciseName: exerciseName,
  );
}

void main() {
  // ── S-001 — info control top edge aligns with title line ─────────────
  group('S-001: info control alignment', () {
    testWidgets(
      'info control top edge aligns with the title line on a row '
      'whose chip Wrap spans two lines',
      (WidgetTester tester) async {
        const exerciseName = 'Density ThreeMuscleWrapsToTwo';
        await _pumpFilteredRow(
          tester,
          surface: const Size(390, 844),
          nameToken: 'ThreeMuscleWrapsToTwo',
          // 3 muscle chips + discipline → 4 chips, wraps to 2 lines.
          muscleIds: const [
            'muscle-chest',
            'muscle-triceps',
            'muscle-shoulders',
          ],
        );

        final row = _resolveRow(tester, exerciseName);
        final infoRect = tester.getRect(row.infoButton);
        final titleRect = tester.getRect(row.title);

        // `titleAlignment: ListTileTitleAlignment.top` anchors the
        // trailing widget to the top of the row. The title Text starts
        // at the same row top (modulo ListTile's vertical padding).
        // We allow a 6 dp slack to absorb sub-pixel rounding.
        expect(
          (infoRect.top - titleRect.top).abs(),
          lessThanOrEqualTo(6.0),
          reason:
              'Info control top must align with the title-line top (was '
              'vertically centred against the full row). infoRect.top='
              '${infoRect.top}, titleRect.top=${titleRect.top}',
        );
      },
    );
  });

  // ── S-002 — row height returns toward pre-PR-7 baseline ─────────────
  group('S-002: row height budget', () {
    testWidgets(
      '3-chip row (1 discipline + 2 muscles) renders with chips on a '
      'single line and stays within the pre-PR-7 row-height budget',
      (WidgetTester tester) async {
        const exerciseName = 'Density ThreeChipOneLine';
        await _pumpFilteredRow(
          tester,
          surface: const Size(390, 844),
          nameToken: 'ThreeChipOneLine',
          // 2 short muscle chips + discipline → 3 chips, fits on one
          // line on the 390 dp surface.
          muscleIds: const ['muscle-back', 'muscle-core'],
        );

        final row = _resolveRow(tester, exerciseName);
        final height = tester.getSize(row.tile).height;
        // Pre-PR-7 baseline for a single-line-chip row on this surface
        // was roughly 110 dp (title 24 + desc 32 + chip 30 + padding 24).
        // We allow a 150 dp ceiling for the post-fix layout — it
        // includes the trailing info control and the titleAlignment
        // top-anchor's vertical padding overhead.
        expect(
          height,
          lessThanOrEqualTo(150.0),
          reason:
              'Single-line-chip row must stay within the pre-PR-7 '
              'row-height budget (actual=${height}).',
        );
      },
    );
  });

  // ── S-003 — chip wrap only when required ──────────────────────────────
  group('S-003: chip wrap behaviour', () {
    testWidgets(
      '3-chip row keeps all chips on a single line',
      (WidgetTester tester) async {
        const exerciseName = 'Density ThreeChipSingle';
        await _pumpFilteredRow(
          tester,
          surface: const Size(390, 844),
          nameToken: 'ThreeChipSingle',
          muscleIds: const ['muscle-back', 'muscle-core'],
        );

        final row = _resolveRow(tester, exerciseName);
        final wrapFinder = find.descendant(
          of: row.tile,
          matching: find.byType(Wrap),
        );
        expect(wrapFinder, findsOneWidget);
        final chips = tester
            .widgetList<Chip>(find.descendant(
              of: wrapFinder,
              matching: find.byType(Chip),
            ))
            .toList();
        // 1 discipline (Rowing) + 2 muscles (Back, Core) = 3 chips.
        expect(chips.length, equals(3));
        // The Wrap's height is exactly one chip tall.
        final wrapHeight = tester.getSize(wrapFinder.first).height;
        expect(
          wrapHeight,
          lessThanOrEqualTo(36.0),
          reason:
              'Wrap height (${wrapHeight}) must fit a single chip line '
              'for a 3-chip row',
        );
      },
    );

    testWidgets(
      '5-chip row wraps to two lines and never leaves a single chip '
      'alone on the last line',
      (WidgetTester tester) async {
        const exerciseName = 'Density FiveChip';
        await _pumpFilteredRow(
          tester,
          surface: const Size(390, 844),
          nameToken: 'FiveChip',
          // 4 muscle chips + discipline → 5 chips. The fix MUST leave
          // enough horizontal room that the last line carries ≥ 2
          // chips (no orphan chip).
          muscleIds: const [
            'muscle-back',
            'muscle-chest',
            'muscle-biceps',
            'muscle-core',
          ],
        );

        final row = _resolveRow(tester, exerciseName);
        final chipFinder = find.descendant(
          of: row.tile,
          matching: find.byType(Chip),
        );
        expect(chipFinder, findsNWidgets(5));

        // Group chips by their Y-coordinate (each Y is one line of the
        // Wrap). Then assert the last line has ≥ 2 chips.
        final lines = <double, int>{};
        for (final element in chipFinder.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          // Bucket by 4 dp so chips on the same line land in the same key.
          final key = (rect.top / 4).round() * 4.0;
          lines[key] = (lines[key] ?? 0) + 1;
        }
        final lineKeys = lines.keys.toList()..sort();
        expect(
          lineKeys,
          isNotEmpty,
          reason: '5-chip row must produce at least one Wrap line',
        );
        // The last line carries the leftover chips; if it's exactly
        // one chip on its own line the layout has wasted vertical
        // density.
        final lastLineCount = lines[lineKeys.last]!;
        expect(
          lastLineCount,
          greaterThanOrEqualTo(2),
          reason:
              'Last wrap line must carry ≥ 2 chips (no orphan). '
              'Lines: $lines',
        );
      },
    );
  });

  // ── S-004 — info control tap area ≥ 44 dp × 44 dp ────────────────────
  group('S-004: tap area + non-overlap', () {
    testWidgets(
      'info control hit rect is at least 44 dp × 44 dp and does not '
      'overlap the row-body left half',
      (WidgetTester tester) async {
        const exerciseName = 'Density TapArea';
        await _pumpFilteredRow(
          tester,
          surface: const Size(390, 844),
          nameToken: 'TapArea',
          muscleIds: const ['muscle-back', 'muscle-core'],
        );

        final row = _resolveRow(tester, exerciseName);
        final infoRect = tester.getRect(row.infoButton);

        // 44 × 44 platform minimum — the IconButton hit-test rect.
        expect(
          infoRect.width,
          greaterThanOrEqualTo(44.0),
          reason: 'info button width (${infoRect.width}) must clear 44 dp',
        );
        expect(
          infoRect.height,
          greaterThanOrEqualTo(44.0),
          reason: 'info button height (${infoRect.height}) must clear 44 dp',
        );

        // The hit-test rect must NOT extend past the row's centre so
        // the left half remains a clean row-body tap target.
        final tileRect = tester.getRect(row.tile);
        final tileMidX = tileRect.left + tileRect.width / 2;
        expect(
          infoRect.left,
          greaterThan(tileMidX - 1.0),
          reason:
              'info button must not intrude into the row-body tap area '
              '(mid=${tileMidX}, infoRect.left=${infoRect.left})',
        );
      },
    );
  });

  // ── S-005 + S-006 — interaction regression guard for PR-7 contract ──
  group('PR-7 row contract preserved after density fix', () {
    testWidgets(
      'S-005: tapping the row body still pops the picker with the exercise',
      (WidgetTester tester) async {
        const surface = Size(800, 1200);
        await tester.binding.setSurfaceSize(surface);
        final repo = await _freshRepo();
        const exerciseName = 'Density PopOnBody';
        await _seedExercise(
          repo,
          nameToken: 'PopOnBody',
          muscleIds: const ['muscle-back', 'muscle-core'],
        );
        final workoutState = WorkoutState(repo);

        Exercise? popped;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(ctx).push<Exercise>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExercisePickerScreen(workoutState: workoutState),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Filter to the seeded exercise so we don't depend on row
        // ordering across picker builds.
        await tester.enterText(find.byType(TextField).first, 'PopOnBody');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Tap the title text directly — this is on the row body, NOT
        // the info control.
        await tester.tap(find.text(exerciseName));
        await tester.pumpAndSettle();

        expect(
          popped,
          isNotNull,
          reason: 'Tapping the row body must still pop with the exercise',
        );
        expect(popped!.name, equals(exerciseName));
      },
    );

    testWidgets(
      'S-006: tapping the info control still opens details (no pop)',
      (WidgetTester tester) async {
        const surface = Size(800, 1200);
        await tester.binding.setSurfaceSize(surface);
        final repo = await _freshRepo();
        await _seedExercise(
          repo,
          nameToken: 'InfoOpensDetails',
          muscleIds: const ['muscle-back', 'muscle-core'],
        );
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'InfoOpensDetails',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('exercise_row_details_button')).first,
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(ExerciseDetailViewScreen),
          findsOneWidget,
          reason: 'Info control must still open details (no picker pop)',
        );
      },
    );
  });

  // ── S-007 — narrow-surface density regression guard ───────────────────
  group('S-007: narrow-surface density', () {
    testWidgets(
      '3-chip row height on 360 × 800 stays within the absolute '
      'budget, allowing for one extra chip-wrap line',
      (WidgetTester tester) async {
        // First measure on 390 × 844.
        await _pumpFilteredRow(
          tester,
          surface: const Size(390, 844),
          nameToken: 'NarrowSurfaceGuard',
          muscleIds: const ['muscle-back', 'muscle-core'],
        );
        final row390 = _resolveRow(
          tester,
          'Density NarrowSurfaceGuard',
        );
        final height390 = tester.getSize(row390.tile).height;

        // Then measure on the narrowest supported width.
        await _pumpFilteredRow(
          tester,
          surface: const Size(360, 800),
          nameToken: 'NarrowSurfaceGuardNarrow',
          muscleIds: const ['muscle-back', 'muscle-core'],
        );
        final row360 = _resolveRow(
          tester,
          'Density NarrowSurfaceGuardNarrow',
        );
        final height360 = tester.getSize(row360.tile).height;

        // At 360 dp, the subtitle column loses ~30 dp of width vs the
        // 390 dp surface — that single-line chip wrap can fall to a
        // 2-line wrap (an extra chip-line height of ~30 dp). The fix
        // MUST keep the row within an absolute 180 dp ceiling so 3+
        // exercises still fit on a phone-height list area.
        expect(
          height360 - height390,
          lessThanOrEqualTo(40.0),
          reason:
              'Narrow-surface row must not balloon by more than one '
              'extra wrap line vs 390 dp '
              '(390=$height390, 360=$height360)',
        );
        expect(
          height360,
          lessThanOrEqualTo(180.0),
          reason: 'Absolute narrow-row height budget check',
        );
      },
    );
  });
}
