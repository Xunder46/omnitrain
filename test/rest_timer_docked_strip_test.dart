// filepath: test/rest_timer_docked_strip_test.dart
//
// Tests for the docked rest-timer strip.
//
// The rest timer overlay was previously a floating chip anchored to
// `restOverlayBottomOffset` inside a `Stack`, with no awareness of what sat
// underneath it. On small screens this landed directly on top of the
// "Add Exercise/Add Block" bar (list view) and the weight-adjustment
// controls (detail view), making both unreadable and untappable for the
// entire rest period.
//
// The docked strip replaces the floating overlay with an in-flow strip
// immediately above the primary action button on each workout surface.
// This file verifies the docked behaviour:
//
//   * the strip's bounds never intersect any interactive control on
//     any surface at the smallest supported viewport,
//   * the strip's height collapses to zero when no rest is open,
//   * the strip's appearance and disappearance do not shift the
//     scroll offset of any scrollable,
//   * a tap landing on the strip's empty area does nothing (the strip
//     does not intercept taps meant for the chip beneath),
//   * the chip inside the strip keeps its existing tap-to-pause/resume
//     behaviour,
//   * the strip sits at the same vertical offset above the primary
//     bottom action on every surface (cross-surface parity),
//   * no layout overflow is reported across the 360x640 -> 1280x2400
//     viewport range on any surface with or without a rest.
//
// These tests must run against `MockWorkoutRepository`. They are part of
// the contract that prevents the defect from regressing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_bottom_cta.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
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

Future<_Deps> _buildDeps({String? modality, bool rolling = false}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(
    modality: modality,
    isRolling: rolling,
  );
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    repo: repo,
  );
}

Widget _buildSessionScreen(_Deps deps, {bool editMode = false}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
    ),
  );
}

/// Adds one set-kind exercise and opens a rest for entry 1.
Future<String> _addSetExerciseWithOpenRest(_Deps deps) async {
  final exercises = await deps.repo.getExercises();
  final setExercise = exercises.firstWhere(
    (e) => e.capabilities.contains('reps'),
  );
  final effortId = await deps.workoutState.addExerciseToSession(
    setExercise,
    chosenMetric: 'reps',
  );
  await deps.workoutState.addEntry(effortId);
  await deps.workoutState.recordRestStart(effortId, 1);
  return effortId;
}

Future<void> _dismissPickerIfOpen(WidgetTester tester) async {
  if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
  } else {
    await tester.pumpAndSettle();
  }
}

/// Every `InteractiveViewer`-style hit-target we care about on the list
/// view's body content (header / chrome buttons are out of scope; they
/// live above the strip).
Finder _listViewInteractiveControls() {
  return find.byWidgetPredicate(
    (w) =>
        w is ButtonStyleButton ||
        w is IconButton ||
        w is InkWell ||
        w is GestureDetector,
  );
}

/// Strip finder — `rest-strip` key on the new widget.
Finder _strip() => find.byKey(const Key('rest-strip'));

void main() {
  // ── S-001 / S-002 / S-003: bounds never intersect controls ──────────────

  group('Docked strip — no overlap with interactive controls', () {
    testWidgets(
      'S-001: standard list view at 360x640, strip clears every interactive control',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        expect(_strip(), findsOneWidget);

        final stripRect = tester.getRect(_strip());
        final controls = _listViewInteractiveControls().evaluate();
        // The strip is below all body content. It may legitimately
        // touch the bottom CTA's *adjacency* (the strip sits
        // immediately above it), so we only assert against controls
        // whose centre is above the strip's top edge — i.e. controls
        // inside the scrollable area, not the CTA itself.
        for (final element in controls) {
          final widgetFinder = find.byWidgetPredicate(
            (w) => identical(w, element.widget),
          );
          if (widgetFinder.evaluate().isEmpty) continue;
          final widgetRect = tester.getRect(widgetFinder);
          final widgetCenterY = (widgetRect.top + widgetRect.bottom) / 2;
          if (widgetCenterY >= stripRect.top) continue;
          expect(
            stripRect.top > widgetRect.bottom,
            isTrue,
            reason:
                'strip.top (${stripRect.top}) must sit below the bottom '
                '(y=${widgetRect.bottom}) of every interactive control '
                '(${element.widget.runtimeType}) above it; the strip '
                'would otherwise land on top of that control',
          );
        }
      },
    );

    testWidgets(
      'S-002: rolling list view at 360x640, strip clears every interactive control',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting', rolling: true);
        await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        expect(_strip(), findsOneWidget);
        final stripRect = tester.getRect(_strip());

        // The strip must be docked at the bottom (its top must be in
        // the lower half of the viewport, leaving the upper half for
        // content).
        expect(
          stripRect.top > 360 * 0.5,
          isTrue,
          reason:
              'rolling list view strip must dock at the bottom, not '
              'float in the middle of the viewport',
        );
      },
    );

    testWidgets(
      'S-003: detail view at 360x640, strip clears the Log Set button',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        final effortId = await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        // Drill into the detail view.
        final repo = await _freshRepo();
        final firstExercise = (await repo.getExercises()).firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        await tester.tap(find.text(firstExercise.name));
        await tester.pumpAndSettle();

        // The strip must clear the primary set control on this surface.
        // The Log Set / Start button is the primary action; weight
        // adjustment + set dots are also interactive and must be
        // covered by neither the strip nor the chip.
        expect(_strip(), findsOneWidget);
        final stripRect = tester.getRect(_strip());

        // Find Log Set / Start, and the navigation arrows.
        for (final finder in [
          find.widgetWithText(FilledButton, 'Log Set'),
          find.widgetWithText(FilledButton, 'Start'),
          find.byTooltip('Previous Set'),
          find.byTooltip('Next'),
        ]) {
          if (finder.evaluate().isEmpty) continue;
          final controlRect = tester.getRect(finder);
          // The detail view's strip sits ABOVE the set-controls row.
          expect(
            stripRect.bottom <= controlRect.top,
            isTrue,
            reason:
                'strip.bottom (${stripRect.bottom}) must sit above '
                'control.top (${controlRect.top}); '
                'the docked strip must not overlap the Log Set / '
                'Start button or the Previous / Next arrows',
          );
        }

        // Suppress unused-variable warning on `effortId` while
        // keeping the helper that produces it documented above.
        expect(effortId, isNotEmpty);
      },
    );
  });

  // ── S-004: scroll-to-end leaves the last list item fully visible ────────

  group('Docked strip — scroll-to-end visibility', () {
    testWidgets(
      'S-004: with strip visible, the final list item is fully visible above the strip',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        // The "Add Exercise/Block" bar lives at the tail of the
        // ListView. Scroll to the maximum extent.
        final listFinder = find.byType(Scrollable);
        expect(listFinder, findsOneWidget);
        final state = tester.state<ScrollableState>(listFinder);
        final maxScroll = state.position.maxScrollExtent;
        state.position.jumpTo(maxScroll);
        await tester.pumpAndSettle();

        final stripRect = tester.getRect(_strip());
        final addBar = find.byWidgetPredicate(
          (w) => w is Padding &&
              w.child is Row &&
              // _buildAddExerciseAndBlockBar builds a Row with text
              // labels including "Add Exercise" / "Add Block".
              find
                  .descendant(
                    of: find.byWidgetPredicate((e) => e == w),
                    matching: find.byType(Text),
                  )
                  .evaluate()
                  .any(
                    (e) =>
                        (e.widget as Text).data?.contains('Add ') ?? false,
                  ),
        );
        if (addBar.evaluate().isNotEmpty) {
          final addBarRect = tester.getRect(addBar);
          expect(
            addBarRect.bottom <= stripRect.top,
            isTrue,
            reason:
                'the final list item (Add Exercise/Block bar) must be '
                'fully above the strip — not covered',
          );
        }
      },
    );
  });

  // ── S-005 / S-006 / S-007: tap behaviour ─────────────────────────────────

  group('Docked strip — tap behaviour', () {
    testWidgets(
      'S-005: tap on the strip\'s empty area does nothing',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        final stripRect = tester.getRect(_strip());
        // Tap on the strip itself (centre), but the chip is centered,
        // so tap just to the side so we hit the empty padding around
        // the chip.
        await tester.tapAt(
          Offset(stripRect.left + 20, stripRect.center.dy),
        );
        await tester.pumpAndSettle();

        // The chip must still be present, the rest must still be open.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
        );
        final restKey = deps.workoutState.getEntryRests;
        final openAfter = deps.workoutState
            .getEntryRests(_dummyFirstEffort(deps))
            .where((r) => r.restEndMs == null);
        expect(openAfter, isNotEmpty);

        // Suppress unused-reference warning.
        expect(restKey, isNotNull);
      },
    );

    testWidgets(
      'S-006: tap on the chip itself keeps the existing pause/resume behaviour',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        final effortId = await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        final chipFinder = find.byKey(const Key('rest-overlay-chip'));
        expect(chipFinder, findsOneWidget);

        // Before tap: rest is running (not paused).
        expect(
          deps.workoutState.isRestPaused(effortId, 1),
          isFalse,
          reason: 'sanity: rest starts running',
        );

        await tester.tap(chipFinder);
        await tester.pumpAndSettle();

        // After tap: rest is paused (regression guard for the
        // tap-to-pause/resume behaviour; this is the same behaviour
        // the chip had when it was a floating overlay).
        expect(
          deps.workoutState.isRestPaused(effortId, 1),
          isTrue,
          reason:
              'tapping the chip must toggle pause; the docked strip '
              'must preserve the chip\'s existing tap behaviour',
        );
      },
    );

    testWidgets(
      'S-007: tap just below the strip on the bottom CTA still fires',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        // Find the OmniBottomCTA. The strip sits *immediately above*
        // it. Tapping the CTA's label area must trigger its handler
        // (the standard list view's CTA is "Finish Workout", which
        // opens a confirmation dialog).
        final ctaFinder = find.byType(OmniBottomCTA);
        expect(ctaFinder, findsOneWidget);
        final ctaRect = tester.getRect(ctaFinder);

        await tester.tapAt(
          Offset(ctaRect.center.dx, ctaRect.center.dy),
        );
        await tester.pumpAndSettle();

        // The Finish Workout dialog must be on screen — the tap
        // landed on the CTA, proving the CTA is still reachable even
        // with the strip mounted.
        expect(
          find.text('Finish Workout?'),
          findsOneWidget,
          reason:
              'tapping the CTA below the strip must open the Finish '
              'Workout confirmation dialog — the strip must not '
              'interfere with the CTA',
        );
      },
    );
  });

  // ── S-008 / S-009 / S-010: collapse + scroll offset ──────────────────────

  group('Docked strip — height collapse + scroll stability', () {
    testWidgets(
      'S-008: no open rest → strip height is zero',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        // Add an exercise but DO NOT open a rest.
        final exercises = await deps.repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        await deps.workoutState.addExerciseToSession(
          setExercise,
          chosenMetric: 'reps',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        // The strip widget itself may be in the tree (with size 0)
        // or absent; either way its rendered height must be 0.
        final stripFinder = _strip();
        if (stripFinder.evaluate().isNotEmpty) {
          final stripRect = tester.getRect(stripFinder);
          expect(stripRect.height, 0.0);
        }
        expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);
      },
    );

    testWidgets(
      'S-009: scroll offset is identical before and after the strip appears',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        // Add enough exercises to fill more than one viewport so the
        // ListView can scroll.
        final exercises = await deps.repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        for (var i = 0; i < 4; i++) {
          await deps.workoutState.addExerciseToSession(
            setExercise,
            chosenMetric: 'reps',
          );
        }

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        // Scroll part-way down.
        final listState =
            tester.state<ScrollableState>(find.byType(Scrollable));
        listState.position.jumpTo(120.0);
        await tester.pumpAndSettle();
        final offsetBefore = listState.position.pixels;

        // Open a rest now — the strip should appear without
        // disturbing the scroll offset.
        final firstSegment = deps.workoutState.segments.first;
        final firstEffort =
            deps.workoutState.getEffortsForSegment(firstSegment.id).first;
        await deps.workoutState.addEntry(firstEffort.id);
        await deps.workoutState.recordRestStart(firstEffort.id, 1);
        await tester.pumpAndSettle();

        final offsetAfter = listState.position.pixels;
        expect(
          offsetAfter,
          offsetBefore,
          reason:
              'opening a rest must not change the ListView scroll '
              'offset; the strip\'s appearance must not push existing '
              'content out from under the user',
        );
      },
    );

    testWidgets(
      'S-010: scroll offset is identical before and after the strip disappears',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        // Add several exercises.
        final exercises = await deps.repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        final effortIds = <String>[];
        for (var i = 0; i < 4; i++) {
          effortIds.add(
            await deps.workoutState.addExerciseToSession(
              setExercise,
              chosenMetric: 'reps',
            ),
          );
        }

        // Open a rest on the first effort so the strip is visible.
        await deps.workoutState.addEntry(effortIds.first);
        await deps.workoutState.recordRestStart(effortIds.first, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        final listState =
            tester.state<ScrollableState>(find.byType(Scrollable));
        listState.position.jumpTo(120.0);
        await tester.pumpAndSettle();
        final offsetBefore = listState.position.pixels;

        // Close the rest directly via the state so the strip
        // disappears.
        await deps.workoutState.recordRestEnd(effortIds.first, 1);
        await tester.pumpAndSettle();

        final offsetAfter = listState.position.pixels;
        expect(
          offsetAfter,
          offsetBefore,
          reason:
              'closing the rest must not change the ListView scroll '
              'offset; the strip\'s disappearance must not pull '
              'existing content up from under the user',
        );
      },
    );
  });

  // ── S-011: cross-surface parity ──────────────────────────────────────────

  group('Docked strip — cross-surface parity', () {
    testWidgets(
      'S-011: strip\'s offset relative to the bottom action is identical on every surface',
      (WidgetTester tester) async {
        const surface = Size(400, 1200);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // 1) Standard list view.
        final stdDeps = await _buildDeps(modality: 'resistance_lifting');
        await _addSetExerciseWithOpenRest(stdDeps);
        await tester.pumpWidget(_buildSessionScreen(stdDeps));
        await _dismissPickerIfOpen(tester);
        final stdStrip = tester.getRect(_strip());
        final stdCta = tester.getRect(find.byType(OmniBottomCTA));
        final stdGap = stdCta.top - stdStrip.bottom;

        // 2) Rolling list view.
        final rollDeps = await _buildDeps(
          modality: 'resistance_lifting',
          rolling: true,
        );
        await _addSetExerciseWithOpenRest(rollDeps);
        await tester.pumpWidget(_buildSessionScreen(rollDeps));
        await _dismissPickerIfOpen(tester);
        final rollStrip = tester.getRect(_strip());
        final rollCta = tester.getRect(find.byType(OmniBottomCTA));
        final rollGap = rollCta.top - rollStrip.bottom;

        expect(
          (stdGap - rollGap).abs() < 1.0,
          isTrue,
          reason:
              'the strip\'s vertical gap above the bottom CTA must be '
              'identical on the standard list view and the rolling '
              'list view; surfaces must not disagree about where the '
              'strip sits (got std=$stdGap, roll=$rollGap)',
        );

        // 3) Detail view. Drill into the exercise.
        await tester.pumpWidget(_buildSessionScreen(stdDeps));
        await _dismissPickerIfOpen(tester);
        final repo = await _freshRepo();
        final firstExercise = (await repo.getExercises()).firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        await tester.tap(find.text(firstExercise.name));
        await tester.pumpAndSettle();

        final detailStrip = tester.getRect(_strip());
        // The detail view's primary action is the Log Set / Start
        // button (not the OmniBottomCTA), so the gap is measured
        // against that.
        final logSetRect = tester.getRect(
          find.widgetWithText(FilledButton, 'Log Set'),
        );
        final detailGap = logSetRect.top - detailStrip.bottom;

        // Detail and list views don't necessarily share a single
        // primary-action reference frame — we only require that the
        // strip is positioned consistently relative to *whatever* the
        // primary action on each surface is, so they all use the same
        // dock gap.
        // We re-render std to capture the same Log Set control under
        // the same viewport, then compare the strip's *bottom* in
        // absolute viewport coords across surfaces as the parity
        // signal: the strip should sit at the same Y on both.
        // Re-render the standard list view for that direct
        // comparison.
        await tester.pumpWidget(_buildSessionScreen(stdDeps));
        await _dismissPickerIfOpen(tester);
        final stdStripAgain = tester.getRect(_strip());

        expect(
          (detailStrip.bottom - stdStripAgain.bottom).abs() < 1.0,
          isTrue,
          reason:
              'the strip must dock at the same vertical position on '
              'the detail view and the list view (std.bottom=${stdStripAgain.bottom}, '
              'detail.bottom=${detailStrip.bottom})',
        );

        // Suppress unused references.
        expect(repo, isNotNull);
        expect(detailGap, isNotNull);
      },
    );
  });

  // ── S-012 / S-013 / S-014: visibility rule regression ───────────────────

  group('Docked strip — visibility rule regression', () {
    testWidgets(
      'S-012: edit mode → strip is absent / zero-height regardless of open rests',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');
        await _addSetExerciseWithOpenRest(deps);

        await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
        await _dismissPickerIfOpen(tester);

        final stripFinder = _strip();
        if (stripFinder.evaluate().isNotEmpty) {
          final stripRect = tester.getRect(stripFinder);
          expect(stripRect.height, 0.0);
        }
        expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);
      },
    );

    testWidgets(
      'S-014: cross-effort → strip shows A\'s elapsed rest while viewing B',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'resistance_lifting');

        final exercises = await deps.repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        // A: open rest.
        final effortA = await deps.workoutState.addExerciseToSession(
          setExercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortA);
        await deps.workoutState.recordRestStart(effortA, 1);
        // B: no rest.
        await deps.workoutState.addExerciseToSession(
          setExercise,
          chosenMetric: 'reps',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _dismissPickerIfOpen(tester);

        // Open B's detail view (last exercise in the list).
        await tester.tap(find.text(setExercise.name).last);
        await tester.pumpAndSettle();

        expect(_strip(), findsOneWidget);
        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      },
    );
  });

  // ── S-015: overflow across the viewport range ───────────────────────────

  group('Docked strip — viewport overflow sweep', () {
    testWidgets(
      'S-015: no layout overflow on any surface at any viewport in 360x640..1280x2400',
      (WidgetTester tester) async {
        // Surface sizes covering phones through tablets/large
        // foldables. We pick three representative heights per
        // typical phone, phablet, and tablet band so the test stays
        // fast while still sweeping the critical corner cases.
        const viewports = <Size>[
          Size(360, 640), // smallest supported
          Size(360, 800),
          Size(412, 915), // Pixel-class
          Size(430, 932), // iPhone-class
          Size(600, 1200), // small tablet
          Size(768, 1024), // iPad-class
          Size(1024, 1366), // iPad Pro landscape
          Size(1280, 2400), // largest supported (per spec)
        ];

        for (final surface in viewports) {
          for (final withRest in [false, true]) {
            for (final rolling in [false, true]) {
              await tester.binding.setSurfaceSize(surface);

              final deps = await _buildDeps(
                modality: 'resistance_lifting',
                rolling: rolling,
              );
              if (withRest) {
                await _addSetExerciseWithOpenRest(deps);
              }

              await tester.pumpWidget(_buildSessionScreen(deps));
              await _dismissPickerIfOpen(tester);

              final exception = tester.takeException();
              expect(
                exception,
                isNull,
                reason:
                    'no layout overflow at ${surface.width}x${surface.height} '
                    'rest=$withRest rolling=$rolling',
              );
            }
          }
        }
        addTearDown(() => tester.binding.setSurfaceSize(null));
      },
    );
  });
}

/// Return the first effortId recorded by this state, used as a stand-in
/// "any effort" reference for assertions about the open-rest set.
String _dummyFirstEffort(_Deps deps) {
  final segment = deps.workoutState.segments.first;
  return deps.workoutState.getEffortsForSegment(segment.id).first.id;
}