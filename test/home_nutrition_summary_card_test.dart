// filepath: test/home_nutrition_summary_card_test.dart
//
// Widget tests for the home nutrition summary card (Iteration 5
// / S-100..S-106).
//
// Phase 5 supersedes Phase 4.1 (D-8) `NutritionStripBar` with a
// self-contained `NutritionSummaryCard` that visually belongs to
// the same instrument-panel family as the training tiles:
// rounded corners, raised/lit look, inset margins, and a single
// large tap target. The calorie figure is the headline; the
// macro percentages live in a caption row below a single
// horizontal gauge. The card uses MUTED macro colors
// (terracotta / steel-blue / amber) so it reads as a lit panel
// rather than a status light.
//
// The card is a small, pure widget: no state access, no
// business logic. The caller (HomeScreen) pre-computes
// consumed/target calories and the per-macro calorie
// contributions via `NutritionState` getters. Tests below
// exercise:
//
//   S-100 — happy state: headline + gauge + caption render
//           correctly with a known (P, C, F) macro split.
//   S-101 — body tap opens the nutrition feature (the WHOLE
//           card is the tap target — not just the chevron).
//   S-102 — gauge fill proportion equals consumed / goal.
//   S-103 — macro segment proportions equal each macro's
//           share of CONSUMED calories (not share of the
//           full bar).
//   S-104 — empty state: nothing logged → empty gauge, 0
//           against the goal, and DASHES (`—`) in the caption
//           row, NOT `0%`.
//   S-105 — over-budget: consumed > goal → full gauge, calorie
//           figure in warning tone, no overflow.
//   S-106 — training tiles above the card are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/preferences_service.dart'
    show PreferencesService;
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/home/widgets/nutrition_summary_card.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Variant of [_freshRepo] that wipes the seeded consumed-foods
/// after initialization. The S-055-style integration tests
/// log a food and assert on the exact "consumed / target cal"
/// label; the `SeedData.sampleConsumedFoods()` seed preloads
/// three today-dated rows which would inflate the total and
/// break the assertion.
Future<MockWorkoutRepository> _freshRepoCleanConsumed() async {
  final repo = await _freshRepo();
  repo.clearConsumedFoodsForTest();
  return repo;
}

class _FakePreferencesService implements PreferencesService {
  int _hubOpenCount = 0;

  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => _hubOpenCount;

  @override
  Future<void> incrementHubOpenCount() async {
    _hubOpenCount += 1;
  }
}

/// Per-100g chicken breast: 31P / 0C / 3F = 151 kcal, 0 fiber, 0 sodium.
Food _chicken() => Food(
      id: 'card-chicken',
      name: 'Chicken Breast',
      unitType: FoodUnitType.grams,
      referenceAmount: 100.0,
      referenceLabel: '100 g',
      protein: 31,
      carbs: 0,
      fat: 3,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    );

Future<HomeScreen> _buildHomeScreen(MockWorkoutRepository repo) async {
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
  final prefs = _FakePreferencesService();
  await prefs.init();
  final settingsState = SettingsState(repo, prefs);
  await settingsState.initialize();
  final nutritionState = NutritionState(repo);
  final foodLibraryState = FoodLibraryState(repo);
  final nutritionPrimerState = await buildNutritionPrimerState(repo);

  return HomeScreen(
    workoutState: workoutState,
    homeState: homeState,
    routineState: routineState,
    routineSessionService: routineSessionService,
    sessionSummaryService: sessionSummaryService,
    calendarState: calendarState,
    periodState: periodState,
    profileState: profileState,
    settingsState: settingsState,
    timerAlertService: FakeTimerAlertService(),
    nutritionState: nutritionState,
    foodLibraryState: foodLibraryState,
    nutritionPrimerState: nutritionPrimerState,
  );
}

/// Pumps a `MaterialApp` whose home is a `Scaffold` containing a
/// single `NutritionSummaryCard` centered in the available
/// space. The surface size is tunable so the geometry-proportion
/// tests can assert exact pixel widths.
Future<void> _pumpCard(
  WidgetTester tester, {
  required int consumed,
  required int? target,
  required int proteinKcal,
  required int carbsKcal,
  required int fatKcal,
  required VoidCallback onTap,
  double surfaceWidth = 360,
  double surfaceHeight = 600,
  double bottomPadding = 0,
}) async {
  await tester.binding.setSurfaceSize(
    Size(surfaceWidth, surfaceHeight),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // The card sits inside a `Scaffold` body that fills the
  // surface. The card itself owns its 16 px horizontal inset
  // padding (matching the training-tile grid's side margin).
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(surfaceWidth, surfaceHeight),
            padding: EdgeInsets.only(bottom: bottomPadding),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: NutritionSummaryCard(
                consumedCalories: consumed,
                targetCalories: target,
                proteinKcal: proteinKcal,
                carbsKcal: carbsKcal,
                fatKcal: fatKcal,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // S-100 — Happy state
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — happy state (S-100)', () {
    testWidgets('renders the headline "consumed / target Cal" with '
        'comma-grouped thousands', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
      );

      // The headline text is the largest and brightest text on
      // the card. We assert on the headline text directly.
      expect(
        find.byKey(const Key('nutrition_card_headline_text')),
        findsOneWidget,
      );
      expect(find.text('643 / 2,000 Cal'), findsOneWidget);
    });

    testWidgets('the card is rendered with rounded corners and is NOT '
        'full-bleed (it is inset from the screen edges)', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
      );

      final cardRect = tester.getRect(
        find.byKey(const Key('nutrition_card')),
      );
      // The card width is strictly less than the surface width
      // — the 16 px inset on each side narrows the card from
      // 360 px to 328 px.
      expect(cardRect.width, lessThan(360));
      expect(cardRect.width, 360 - 32);
      // The card's left edge is at 16 px from the screen edge
      // (the inset).
      expect(cardRect.left, 16);
    });

    testWidgets('macro caption row shows P, C, F percentages with the '
        'known split', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
      );

      // P = 270/643 = 41.99% → 42%; C = 211/643 = 32.81% → 33%;
      // F = 162/643 = 25.19% → 25%. Sum = 100%.
      expect(
        find.byKey(const Key('nutrition_card_caption_protein')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition_card_caption_carbs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition_card_caption_fat')),
        findsOneWidget,
      );
      expect(find.textContaining('P 42%'), findsOneWidget);
      expect(find.textContaining('C 33%'), findsOneWidget);
      expect(find.textContaining('F 25%'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-101 — Body tap opens nutrition feature
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — body tap opens nutrition feature '
      '(S-101)', () {
    testWidgets('tapping the card body (not the chevron) invokes onTap',
        (tester) async {
      var taps = 0;
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () => taps++,
      );

      // Tap on the card body — NOT the chevron. We use the
      // outer card key, which wraps the entire surface in
      // a single InkWell.
      await tester.tap(find.byKey(const Key('nutrition_card')));
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason: 'S-101: tap on the card body must invoke onTap, not just '
            'on the chevron.',
      );
    });

    testWidgets('tapping the headline text also invokes onTap '
        '(the headline is part of the card body, not a separate '
        'non-tappable control)', (tester) async {
      var taps = 0;
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () => taps++,
      );

      await tester.tap(
        find.byKey(const Key('nutrition_card_headline_text')),
      );
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('tapping the gauge track also invokes onTap', (tester) async {
      var taps = 0;
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () => taps++,
      );

      // Find a point on the gauge track that is NOT inside
      // the fill (i.e. the unfilled remainder, which lives
      // to the right of the fill). We use the chevron key
      // as a probe on the right side of the card, then tap
      // a point to the LEFT of the chevron so we hit the
      // gauge track (or fill) but not the chevron.
      final chevronRect = tester.getRect(
        find.byKey(const Key('nutrition_card_chevron')),
      );
      // Tap just to the left of the chevron, in the gauge row.
      final tapPoint = Offset(
        chevronRect.left - 30,
        chevronRect.center.dy,
      );
      await tester.tapAt(tapPoint);
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason: 'S-101: tap on the gauge row (left of the chevron) must '
            'invoke onTap.',
      );
    });

    testWidgets('the empty-state card is still tappable', (tester) async {
      var taps = 0;
      await _pumpCard(
        tester,
        consumed: 0,
        target: 2000,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () => taps++,
      );

      await tester.tap(find.byKey(const Key('nutrition_card')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-102 — Gauge fill proportion equals consumed / goal
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — gauge fill proportion (S-102)', () {
    testWidgets('fill width / track width = consumed / goal (60% case)',
        (tester) async {
      await _pumpCard(
        tester,
        consumed: 1200,
        target: 2000,
        proteinKcal: 400,
        carbsKcal: 400,
        fatKcal: 400,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final trackWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_track')),
      ).width;
      final fillWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_fill')),
      ).width;
      // 1200 / 2000 = 0.6 (within sub-pixel rounding).
      expect(fillWidth / trackWidth, closeTo(0.6, 0.01));
    });

    testWidgets('fill width / track width = consumed / goal (32% case)',
        (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final trackWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_track')),
      ).width;
      final fillWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_fill')),
      ).width;
      expect(fillWidth / trackWidth, closeTo(643 / 2000, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-103 — Macro segments are share of CONSUMED calories
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — macro segments are share of CONSUMED '
      '(S-103)', () {
    testWidgets('equal 400/400/400 split → three equal segment widths',
        (tester) async {
      await _pumpCard(
        tester,
        consumed: 1200,
        target: 2000,
        proteinKcal: 400,
        carbsKcal: 400,
        fatKcal: 400,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final s0 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_0')),
      ).width;
      final s1 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_1')),
      ).width;
      final s2 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_2')),
      ).width;
      // Each segment is 1/3 of the fill. Allow a 1 px drift for
      // rounding when the fill is clamped to 100% of the track.
      expect((s0 - s1).abs(), lessThanOrEqualTo(1));
      expect((s1 - s2).abs(), lessThanOrEqualTo(1));
      expect((s0 - s2).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('segments sum to the fill width and not to the track '
        'width (i.e. they live INSIDE the fill, not across the full '
        'bar)', (tester) async {
      await _pumpCard(
        tester,
        consumed: 600,
        target: 2000,
        proteinKcal: 200,
        carbsKcal: 200,
        fatKcal: 200,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final trackWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_track')),
      ).width;
      final fillWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_fill')),
      ).width;
      final s0 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_0')),
      ).width;
      final s1 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_1')),
      ).width;
      final s2 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_2')),
      ).width;
      // Sum of segments ≈ fill width (the segments are sized
      // within the fill, not the track).
      expect((s0 + s1 + s2) - fillWidth, lessThanOrEqualTo(1));
      // Sum of segments is strictly LESS than the track width
      // (because the fill is only 30% of the track — the
      // segments are a 30% slice of the track, not a 100% slice).
      expect(
        s0 + s1 + s2,
        lessThan(trackWidth),
        reason: 'S-103: the macro segments must be sized within the '
            'fill, not across the full bar. A wrong implementation '
            'that sizes the segments as a share of the full bar '
            'would sum to trackWidth here.',
      );
    });

    testWidgets('42 / 33 / 25 macro split → segments proportional to '
        'consumed', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: 2000,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final s0 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_0')),
      ).width;
      final s1 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_1')),
      ).width;
      final s2 = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_segment_2')),
      ).width;
      final total = s0 + s1 + s2;
      // Each segment is the macro's share of consumed. Allow a
      // 2% drift for rounding.
      expect(s0 / total, closeTo(0.42, 0.02));
      expect(s1 / total, closeTo(0.33, 0.02));
      expect(s2 / total, closeTo(0.25, 0.02));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-104 — Empty state: nothing logged
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — empty state (S-104)', () {
    testWidgets('calorie figure shows "0 / 2,000 Cal" (not blank)',
        (tester) async {
      await _pumpCard(
        tester,
        consumed: 0,
        target: 2000,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () {},
      );

      // The figure DOES render — it just reads 0 against the
      // target. The card is tappable, not invisible.
      expect(find.text('0 / 2,000 Cal'), findsOneWidget);
    });

    testWidgets('gauge is empty (no fill width) when nothing is logged',
        (tester) async {
      await _pumpCard(
        tester,
        consumed: 0,
        target: 2000,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () {},
      );

      final trackWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_track')),
      ).width;
      // The fill is either absent or has zero width when
      // consumed == 0.
      if (find
          .byKey(const Key('nutrition_card_gauge_fill'))
          .evaluate()
          .isNotEmpty) {
        final fillWidth = tester.getSize(
          find.byKey(const Key('nutrition_card_gauge_fill')),
        ).width;
        expect(fillWidth, 0);
      }
      // The track still renders at full width so the user
      // can see the budget.
      expect(trackWidth, greaterThan(0));
    });

    testWidgets('caption row shows DASHES (—), not 0%', (tester) async {
      await _pumpCard(
        tester,
        consumed: 0,
        target: 2000,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () {},
      );

      // The captions render the dash placeholder, NOT a
      // `0%` percentage. The mockup specifies that we
      // don't imply a real split when there's no data.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('P 0%'), findsNothing);
      expect(find.text('C 0%'), findsNothing);
      expect(find.text('F 0%'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-105 — Over-budget: consumed > goal
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — over-budget state (S-105)', () {
    testWidgets('gauge fill is clamped to 100% of the track width',
        (tester) async {
      await _pumpCard(
        tester,
        consumed: 2450,
        target: 2000,
        proteinKcal: 1200,
        carbsKcal: 800,
        fatKcal: 450,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final trackWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_track')),
      ).width;
      final fillWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_fill')),
      ).width;
      // The fill clamps to trackWidth (no overflow past the
      // track).
      expect(fillWidth, lessThanOrEqualTo(trackWidth));
      expect(
        fillWidth,
        trackWidth,
        reason: 'S-105: fill must clamp to 100% of the track when '
            'consumed > goal.',
      );
    });

    testWidgets('calorie figure is rendered in the warning tone '
        '(theme.colorScheme.error)', (tester) async {
      await _pumpCard(
        tester,
        consumed: 2450,
        target: 2000,
        proteinKcal: 1200,
        carbsKcal: 800,
        fatKcal: 450,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      final headlineWidget = tester.widget<Text>(
        find.byKey(const Key('nutrition_card_headline_text')),
      );
      final errorColor = Theme.of(
        tester.element(
          find.byKey(const Key('nutrition_card_headline_text')),
        ),
      ).colorScheme.error;
      expect(
        headlineWidget.style?.color,
        errorColor,
        reason: 'S-105: the headline text color must switch to the '
            'theme\'s warning tone when consumed > goal.',
      );
    });

    testWidgets('no RenderFlex overflow is logged', (tester) async {
      await _pumpCard(
        tester,
        consumed: 2450,
        target: 2000,
        proteinKcal: 1200,
        carbsKcal: 800,
        fatKcal: 450,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      // tester.takeException() returns the first uncaught
      // exception. The over-budget case must not throw a
      // RenderFlex overflow.
      expect(tester.takeException(), isNull);
    });

    testWidgets('caption percentages are real (not dashes) when over '
        'budget', (tester) async {
      await _pumpCard(
        tester,
        consumed: 2450,
        target: 2000,
        proteinKcal: 1200,
        carbsKcal: 800,
        fatKcal: 450,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      // The data is real, so the captions show actual %s.
      // 1200 / 2450 = 48.98% → 49%; 800/2450 = 32.65% → 33%;
      // 450/2450 = 18.37% → 18%.
      expect(find.textContaining('P 49%'), findsOneWidget);
      expect(find.textContaining('C 33%'), findsOneWidget);
      expect(find.textContaining('F 18%'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-106 — Training tiles above the card are unchanged
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — training tiles unchanged (S-106)', () {
    testWidgets('HomeScreen mounts six EnergyTile widgets and the new '
        'card sits below them as a peer with a 16 px top gap',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Use a tall surface so the three-row tile grid lays
      // out fully and all six EnergyTile widgets are
      // mounted. The production layout on a typical iPhone
      // fits all six on screen; the test surface mirrors
      // that.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepoCleanConsumed();
      final homeScreen = await _buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: homeScreen));
      await tester.pump();
      await tester.pumpAndSettle();

      // Six training tiles (Cardio, Resistance, Sports,
      // Isometric, Free Training, My Routines).
      expect(find.byType(EnergyTile), findsNWidgets(6));

      // The new card sits below the tiles as a peer.
      expect(find.byType(NutritionSummaryCard), findsOneWidget);

      // The top gap between the tile grid and the card is
      // exactly the same as the inter-row gap (16 px). The
      // card is a peer in the body `Column` — NOT a docked
      // bottom bar — so it sits directly below the grid with
      // the same spacing the grid uses between its own rows.
      final cardRect = tester.getRect(
        find.byKey(const Key('nutrition_card')),
      );
      final lastTileRect = tester.getRect(
        find.byType(EnergyTile).last,
      );
      expect(
        cardRect.top,
        greaterThan(lastTileRect.bottom),
        reason: 'S-106: the card must sit below the tile grid, '
            'not on top of it.',
      );
      expect(
        cardRect.top - lastTileRect.bottom,
        greaterThanOrEqualTo(16),
        reason: 'S-106: the SizedBox(16) peer gap between the '
            'grid and the card is the design contract — it '
            'must never be collapsed below 16 px.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-200 — No target + consumed data: caption shows real percentages,
  //         gauge is hidden. This is the user's requested behavior:
  //         the progress bar disappears when no goal is set, but the
  //         macro percentages stay live whenever food is logged.
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — no target + consumed data (S-200)', () {
    testWidgets('caption row shows real P/C/F percentages when there is '
        'no target but food has been logged', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: null,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
      );

      // Same macro split as the S-100 happy-state assertions:
      // P = 270/643 = 42%; C = 211/643 = 33%; F = 162/643 = 25%.
      // The percentages must surface even though the target is null.
      expect(find.textContaining('P 42%'), findsOneWidget);
      expect(find.textContaining('C 33%'), findsOneWidget);
      expect(find.textContaining('F 25%'), findsOneWidget);
      // The dashes from the S-104 empty state must NOT appear in
      // the caption row.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('gauge fill is absent (no progress bar) when no target '
        'is set, even with consumed data', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: null,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
        surfaceWidth: 360,
        surfaceHeight: 600,
      );

      // The fill is either absent or has zero width — there is no
      // goal to measure progress against, so the bar is hidden.
      if (find
          .byKey(const Key('nutrition_card_gauge_fill'))
          .evaluate()
          .isNotEmpty) {
        final fillWidth = tester.getSize(
          find.byKey(const Key('nutrition_card_gauge_fill')),
        ).width;
        expect(
          fillWidth,
          0,
          reason: 'S-200: with no target set the gauge fill must '
              'have zero width — there is no goal to fill against.',
        );
      }
      // The track still renders at full width so the card layout
      // stays stable.
      final trackWidth = tester.getSize(
        find.byKey(const Key('nutrition_card_gauge_track')),
      ).width;
      expect(trackWidth, greaterThan(0));
    });

    testWidgets('headline reads "{consumed} / — Cal" when no target '
        'is set', (tester) async {
      await _pumpCard(
        tester,
        consumed: 643,
        target: null,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () {},
      );

      // The headline format already handles `target == null` —
      // it renders the consumed figure followed by an em-dash
      // for the target slot, so the user sees their real intake
      // even without a goal.
      expect(find.text('643 / — Cal'), findsOneWidget);
    });

    testWidgets('the card is still tappable when no target is set but '
        'food is logged (the empty-state is for the gauge, not for '
        'the surface)', (tester) async {
      var taps = 0;
      await _pumpCard(
        tester,
        consumed: 643,
        target: null,
        proteinKcal: 270,
        carbsKcal: 211,
        fatKcal: 162,
        onTap: () => taps++,
      );

      await tester.tap(find.byKey(const Key('nutrition_card')));
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason: 'S-200: the card surface remains tappable even when '
            'the gauge is hidden — the "no target" state is not a '
            'disabled state.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-201 — No target + no consumed data: dashes in the caption row
  //         (parity with the existing target-set + no-data case).
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — no target + no data (S-201)', () {
    testWidgets('caption row shows dashes (—) when no target is set '
        'AND nothing is logged', (tester) async {
      await _pumpCard(
        tester,
        consumed: 0,
        target: null,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () {},
      );

      // Both axes (no target, no data) trigger the caption-empty
      // branch — we render dashes, NOT a real (zero) split.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('P 0%'), findsNothing);
      expect(find.text('C 0%'), findsNothing);
      expect(find.text('F 0%'), findsNothing);
    });

    testWidgets('headline reads "0 / — Cal" (real figure, em-dash '
        'target slot)', (tester) async {
      await _pumpCard(
        tester,
        consumed: 0,
        target: null,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () {},
      );

      expect(find.text('0 / — Cal'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-202 — No target + consumed but all macros zero: dashes still
  //         win over "P 0% / C 0% / F 0%" because there is no
  //         meaningful split to show.
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — no target + zero-macro data (S-202)', () {
    testWidgets('caption row shows dashes when consumed > 0 but all '
        'macro contributions are zero', (tester) async {
      await _pumpCard(
        tester,
        consumed: 100,
        target: null,
        proteinKcal: 0,
        carbsKcal: 0,
        fatKcal: 0,
        onTap: () {},
      );

      // No macro data → dashes, NOT a fake "0% / 0% / 0%" split.
      // We do not imply a real split when there is no data.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('P 0%'), findsNothing);
      expect(find.text('C 0%'), findsNothing);
      expect(find.text('F 0%'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Live update — card rebuilds when NutritionState notifies
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionSummaryCard — live update', () {
    testWidgets('logging a food via NutritionState rebuilds the card '
        'without a manual refresh', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = await _freshRepoCleanConsumed();
      final homeScreen = await _buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: homeScreen));
      await tester.pump();
      await tester.pumpAndSettle();

      final nutrition = homeScreen.nutritionState;
      await nutrition.saveNutritionTarget(
        NutritionTarget(calories: 2000),
      );
      await tester.pumpAndSettle();

      // Cold start with a target but no logs: still empty.
      expect(find.text('0 / 2,000 Cal'), findsOneWidget);

      // Log a food — the card should rebuild with the new
      // consumed value.
      final library = FoodLibraryState(repo);
      await library.createFood(_chicken());
      final food = await _seedChicken(repo, nutrition);
      await nutrition.logConsumedFoodAt(food, 200.0);
      await tester.pumpAndSettle();

      // 151 kcal × 2 = 302 consumed.
      expect(find.text('302 / 2,000 Cal'), findsOneWidget);
    });
  });
}

/// Seed a per-100g chicken into the food library so
/// `nutritionState.logConsumedFoodAt(food, 200.0)` works.
Future<Food> _seedChicken(
  MockWorkoutRepository repo,
  NutritionState nutrition,
) async {
  final food = _chicken();
  final library = FoodLibraryState(repo);
  await library.createFood(food);
  await nutrition.loadConsumedToday();
  return food;
}
