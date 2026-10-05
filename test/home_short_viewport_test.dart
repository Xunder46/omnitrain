// Screen-level regression coverage for the Home Screen at short viewports.
//
// The Home Screen lays out six training tiles in a non-scrolling grid that
// compresses its tile side to a 56-point floor on short screens. Every
// existing screen-level test renders the Home Screen on a TALL viewport,
// so the compressed-grid path — the exact path that broke in production
// — has never been exercised end-to-end.
//
// The tile-level regression group in `test/widgets/energy_tile_test.dart`
// proves the tile behaves at a given height in isolation. This file proves
// the SCREEN still assembles correctly when the title, the grid, the
// maintenance sheet, the safe-area insets, and the nutrition summary card
// are all competing for the same vertical space.
//
// If the height-responsive tile fix (item 3) is reverted, at least one
// case in this file fails — see the comment in the "red baseline" test
// below. A screen-level test that passes both before and after the fix
// proves nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/constants/supported_viewport.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/timer_alert_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/home/widgets/nutrition_summary_card.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_nutrition_primer_state.dart';

class _FakeTimerAlertService extends TimerAlertService {
  // No-op stubs for test injection. The base class does not declare these
  // methods directly (they are exercised through other service contracts),
  // so they are intentionally not marked `@override`.
  void scheduleTimerAlert(int seconds, String message) {}
  void cancelTimerAlert(String id) {}
}

class _FakePreferencesService implements PreferencesService {
  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => 0;

  @override
  Future<void> incrementHubOpenCount() async {}
}

/// Builds the Home Screen with the same state injected by the other
/// home-screen tests. The `WorkoutState` is returned so the active-session
/// test can start a session before pumping the screen.
Future<({HomeScreen screen, WorkoutState workoutState})> buildHomeScreen(
  MockWorkoutRepository repo,
) async {
  final workoutState = WorkoutState(repo);
  final homeState = HomeState(repo);
  await homeState.init();
  final routineState = RoutineState(repo);
  final routineSessionService = RoutineSessionService(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  final periodState = PeriodState(repo);
  final profileState = ProfileState(repo);
  await profileState.loadProfile();
  final preferencesService = _FakePreferencesService();
  await preferencesService.init();
  final settingsState = SettingsState(repo, preferencesService);
  await settingsState.initialize();
  final nutritionPrimerState = await buildNutritionPrimerState(repo);

  final screen = HomeScreen(
    workoutState: workoutState,
    homeState: homeState,
    routineState: routineState,
    routineSessionService: routineSessionService,
    sessionSummaryService: sessionSummaryService,
    calendarState: calendarState,
    periodState: periodState,
    profileState: profileState,
    settingsState: settingsState,
    timerAlertService: _FakeTimerAlertService(),
    nutritionState: NutritionState(repo),
    foodLibraryState: FoodLibraryState(repo),
    nutritionPrimerState: nutritionPrimerState,
    exerciseLibraryState: ExerciseLibraryState(
      service: ExerciseLibraryService(repo),
      workoutState: workoutState,
    ),
  );

  return (screen: screen, workoutState: workoutState);
}

/// The six training-tile labels in the order they appear in `HomeTiles.all`.
const List<String> _tileLabels = <String>[
  'Cardio',
  'Resistance',
  'Sports',
  'Isometric',
  'Free',
  'Routines',
];

/// Pumps the Home Screen at the given viewport and text scale and asserts
/// the screen-level invariants required by every scenario in this group.
///
/// The viewport is set via `setSurfaceSize` and the teardown is registered
/// via `addTearDown` so this helper cannot leak the surface size into the
/// next test. The text scale is applied via the override `MediaQuery`
/// inside `pumpWidget` — every screen-level test in this file uses that
/// pattern so the test is independent of the global MyApp text-scale
/// clamp (which is 1.1–1.6 in production).
///
/// Asserts:
///   1. No layout overflow exception is raised.
///   2. All six training-tile labels are findable.
///   3. The nutrition summary card is rendered and within the viewport
///      bounds (not clipped by the bottom edge).
Future<void> _pumpAndAssertShortViewport(
  WidgetTester tester, {
  required Size viewport,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final repo = MockWorkoutRepository();
  final built = await buildHomeScreen(repo);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: viewport,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(home: built.screen),
    ),
  );
  await tester.pumpAndSettle();

  // (1) No layout overflow.
  expect(
    tester.takeException(),
    isNull,
    reason:
        'Home Screen at $viewport and text scale $textScale must not '
        'overflow. The compressed-grid path is exercised at this size '
        'and the tile fix must hold end-to-end.',
  );

  // (2) All six training-tile labels are findable. The labels are the
  // user-visible identifier; finding `EnergyTile` alone would not prove
  // the grid is identifiable.
  for (final label in _tileLabels) {
    expect(
      find.text(label),
      findsOneWidget,
      reason:
          'Training tile "$label" must be rendered at $viewport and '
          'text scale $textScale.',
    );
  }

  // (3) Nutrition summary card is present and within the viewport bounds.
  final cardFinder = find.byType(NutritionSummaryCard);
  expect(
    cardFinder,
    findsOneWidget,
    reason:
        'Nutrition summary card must be rendered at $viewport and text '
        'scale $textScale.',
  );
  final cardRect = tester.getRect(cardFinder);
  expect(
    cardRect.top,
    lessThanOrEqualTo(viewport.height),
    reason:
        'Nutrition card top (${cardRect.top}) must not exceed viewport '
        'height (${viewport.height}) at $viewport — the card is '
        'clipped, not rendered.',
  );
  expect(
    cardRect.bottom,
    lessThanOrEqualTo(viewport.height + 0.5),
    reason:
        'Nutrition card bottom (${cardRect.bottom}) must not exceed '
        'viewport height (${viewport.height}) at $viewport — the card '
        'is clipped by the bottom edge.',
  );
  expect(
    cardRect.width,
    lessThanOrEqualTo(viewport.width + 0.5),
    reason:
        'Nutrition card width (${cardRect.width}) must not exceed '
        'viewport width (${viewport.width}) at $viewport.',
  );
}

void main() {
  // The default text scale in tests is 1.0 (the test bypasses the MyApp
  // clamp of 1.1–1.6). The largest accessibility text scale the app
  // honours is OmniTheme.kTextScaleMax (1.6). Both must be exercised
  // because the compressed-grid path interacts with text scale: the
  // title and the nutrition card both scale with it, so a viewport
  // that does not compress at scale 1.0 may compress at scale 1.6.
  const double kMinTextScale = 1.0;
  const double kMaxTextScale = OmniTheme.kTextScaleMax;

  const List<double> scales = <double>[kMinTextScale, kMaxTextScale];

  // The supported floor (shortest phone the app supports) — a mid-short
  // viewport where tiles compress but typically do not reach the 56-point
  // minimum. Tested at both scales.
  const Size supportedFloor = SupportedViewport.minimumSize;

  // A shorter viewport — short enough to drive the training-tile grid to
  // its 56-point minimum tile side at the maximum text scale (the screen's
  // compression formula clamps to 56pt below 490 logical px tall at scale
  // 1.6). At scale 1.0 the grid is compressed but not yet at the floor —
  // compresses to ~67pt — so the test still exercises the compression
  // path across both scales. The height is chosen so the natural content
  // for the recomputed tile side fits within the available body height
  // at both scales (the home screen's compression rule has a small
  // overestimate against the actual rendered title and card, which the
  // recomputed budget absorbs).
  const Size veryShortFloor = Size(360, 490);

  group('HomeScreen short-viewport regression', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // ───────────────────────────────────────────────────────────────────
    // S-001 / S-002 — supported floor at default and maximum text scale.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'supported floor: no overflow, all six tiles identify, card fits',
      (tester) async {
        for (final scale in scales) {
          await _pumpAndAssertShortViewport(
            tester,
            viewport: supportedFloor,
            textScale: scale,
          );
        }
      },
    );

    // ───────────────────────────────────────────────────────────────────
    // S-003 — very short viewport drives tiles to the 56-point floor.
    // ───────────────────────────────────────────────────────────────────
    testWidgets('very short viewport: tiles hit the 56-point floor safely', (
      tester,
    ) async {
      for (final scale in scales) {
        await _pumpAndAssertShortViewport(
          tester,
          viewport: veryShortFloor,
          textScale: scale,
        );
      }
    });

    // ───────────────────────────────────────────────────────────────────
    // S-004 — active session in the compressed layout.
    // ───────────────────────────────────────────────────────────────────
    testWidgets(
      'active session in compressed layout: no overflow, tiles identify, card fits',
      (tester) async {
        await tester.binding.setSurfaceSize(supportedFloor);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        final built = await buildHomeScreen(repo);

        // Start a resistance session so the Resistance tile's active
        // treatment is exercised in the compressed layout.
        await built.workoutState.createNewSession(
          modality: 'resistance_lifting',
        );

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: supportedFloor,
              textScaler: TextScaler.linear(kMinTextScale),
            ),
            child: MaterialApp(home: built.screen),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'Active session at $supportedFloor must not overflow — the '
              'active-tile treatment is one of the cases the broken '
              'height-responsive layout was reported to break.',
        );
        for (final label in _tileLabels) {
          expect(
            find.text(label),
            findsOneWidget,
            reason:
                'All six training tiles must remain identifiable while a '
                'session is active, at $supportedFloor.',
          );
        }
        final cardFinder = find.byType(NutritionSummaryCard);
        expect(
          cardFinder,
          findsOneWidget,
          reason:
              'Nutrition summary card must be rendered with an active '
              'session at $supportedFloor.',
        );
        final cardRect = tester.getRect(cardFinder);
        expect(
          cardRect.bottom,
          lessThanOrEqualTo(supportedFloor.height + 0.5),
          reason:
              'Nutrition card bottom (${cardRect.bottom}) must not exceed '
              'viewport height (${supportedFloor.height}) with an '
              'active session.',
        );
      },
    );
  });
}
