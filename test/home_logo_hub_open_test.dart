import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/timer_alert_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';
import 'package:omnitrain/widgets/cards/maintenance_tile.dart';
import 'package:omnitrain/widgets/common/home_logo_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_nutrition_primer_state.dart';

class FakeTimerAlertService extends TimerAlertService {
  // No-op stubs for test injection. The base class does not declare these
  // methods directly (they are exercised through other service contracts), so
  // they are intentionally not marked `@override`.
  void scheduleTimerAlert(int seconds, String message) {}
  void cancelTimerAlert(String id) {}
}

class FakePreferencesService implements PreferencesService {
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

Future<HomeScreen> buildHomeScreen(MockWorkoutRepository repo) async {
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
  final preferencesService = FakePreferencesService();
  await preferencesService.init();
  final settingsState = SettingsState(repo, preferencesService);
  await settingsState.initialize();
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
    nutritionState: NutritionState(repo),
    foodLibraryState: FoodLibraryState(repo),
    nutritionPrimerState: nutritionPrimerState,
    exerciseLibraryState: ExerciseLibraryState(
      service: ExerciseLibraryService(repo),
      workoutState: workoutState,
    ),
  );
}

void main() {
  group('HomeScreen Hub Sheet Opening', () {
    late MockWorkoutRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = MockWorkoutRepository();
    });

    testWidgets('tapping the logo opens the Hub sheet', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Find the logo in the AppBar
      final logoFinder = find.byType(Image);
      expect(logoFinder, findsOneWidget);

      // Sheet is at rest: HUB label inside the sheet is not yet visible.
      expect(find.text('HUB'), findsNothing);

      // Tap the logo to open the Hub.
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();

      // Hub sheet is now open: the HUB label inside the sheet is visible.
      expect(find.text('HUB'), findsOneWidget);
    });

    testWidgets('peek handle still works after logo tap', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // The handle lives inside the sheet. With the sheet at rest
      // (minChildSize: 0.0), the handle is off-screen and not findable.
      final handleFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints != null &&
            widget.constraints!.maxWidth == 50 &&
            widget.constraints!.maxHeight == 6,
      );
      expect(handleFinder, findsNothing);

      // The logo should still be present and tappable.
      final logoFinder = find.byType(Image);
      expect(logoFinder, findsOneWidget);
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();

      // Sheet is now open: the 50x6 handle pill at the top of the sheet
      // is visible, signaling the swipe-down-to-close affordance.
      expect(handleFinder, findsOneWidget);
    });

    testWidgets(
      'home screen at rest shows no Hub peek handle or visible sheet sliver',
      (WidgetTester tester) async {
        final screen = await buildHomeScreen(repo);

        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        // The handle lives inside the sheet. With the sheet at rest
        // (minChildSize: 0.0), the handle is off-screen.
        final handleFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints != null &&
              widget.constraints!.maxWidth == 50 &&
              widget.constraints!.maxHeight == 6,
        );
        expect(handleFinder, findsNothing);

        // The HUB label is also inside the sheet content and must not be
        // visible while the sheet is at rest.
        expect(find.text('HUB'), findsNothing);
      },
    );

    testWidgets(
      'tapping the logo opens the Hub (handle is part of the sheet)',
      (WidgetTester tester) async {
        final screen = await buildHomeScreen(repo);

        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        // Confirm the sheet is at rest (no HUB label visible, no handle).
        expect(find.text('HUB'), findsNothing);

        // Tap the logo to open the Hub.
        final logoFinder = find.byType(Image);
        expect(logoFinder, findsOneWidget);
        await tester.tap(logoFinder);
        await tester.pumpAndSettle();

        // The HUB label should now be visible inside the expanded sheet.
        expect(find.text('HUB'), findsOneWidget);
      },
    );

    testWidgets('tapping logo when sheet is already open', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Find the logo in the AppBar
      final logoFinder = find.byType(Image);
      expect(logoFinder, findsOneWidget);

      // Tap the logo twice to ensure it works when already open
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();
      await tester.tap(logoFinder);
      await tester.pumpAndSettle();

      // Verify the tap doesn't crash
      expect(true, isTrue);
    });

    testWidgets('logo tile is not in the training grid', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // The home-screen training grid is a non-scrolling layout: a
      // `Column` of three `Row`s, each row holding two `Expanded`
      // `EnergyTile`s. The grid is NOT a `SliverGrid` / `GridView`
      // / `CustomScrollView` (the Train screen never scrolls).
      // The logo tile must NOT be a descendant of any of those
      // `Row`s — it lives in the AppBar header.
      final gridRows = find
          .descendant(of: find.byType(Column), matching: find.byType(Row))
          .evaluate()
          .where((element) {
            // Filter to rows that contain at least one
            // EnergyTile — those are the grid rows.
            return find
                .descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byType(EnergyTile),
                )
                .evaluate()
                .isNotEmpty;
          })
          .map((e) => find.byWidget(e.widget));

      for (final gridRow in gridRows) {
        expect(
          find.descendant(of: gridRow, matching: find.byType(HomeLogoButton)),
          findsNothing,
          reason:
              'The HomeLogoButton must not live inside any '
              'training-tile row.',
        );
      }

      // The logo tile IS present in the tree, exactly once, hosted in the
      // AppBar header — not in the training grid.
      expect(find.byType(HomeLogoButton), findsOneWidget);

      // All six training tiles are mounted in the body.
      expect(find.byType(EnergyTile), findsNWidgets(6));
    });

    testWidgets(
      'logo tile has correct asymmetric margin from the AppBar edges',
      (WidgetTester tester) async {
        final screen = await buildHomeScreen(repo);

        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        // Tolerance for sub-pixel rounding when Flutter lays out
        // `EdgeInsets.only(top: 8, right: 8, bottom: 8)` around a
        // `tileSize: 55` circle.
        const tolerancePx = 0.5;

        // The widget's bounding box is the 55×55 visible circle wrapped in
        // an ASYMMETRIC `Padding` (0 left, 8 right, 8 top, 8 bottom).
        // The width is therefore the visible circle (55) plus only the
        // right padding (8) = 63 px, while the height is the visible
        // circle (55) plus top + bottom padding (8 + 8) = 71 px.
        //
        // The 0 left padding is what makes the visible circle's left
        // edge land at exactly `AppBar.titleSpacing` (16) from the
        // AppBar's content-start — the same x-coordinate the home-screen
        // training tiles start at (their outer
        // `Padding(fromLTRB(16, 0, 16, 0))`). An 8 px left padding would
        // shift the visible circle to x=24, visibly offset from the
        // leftmost tile edge.
        final size = tester.getSize(find.byType(HomeLogoButton));

        // Width: 55 (visible circle) + 0 (left padding) + 8 (right padding)
        // ≈ 63 px.
        expect(
          size.width,
          closeTo(63.0, tolerancePx),
          reason:
              'Logo button width must be ≈63 px (55 visible circle + 8 px '
              'right padding); any larger value means a left padding has '
              'been re-introduced and the visible circle is no longer flush '
              'with the home-screen training tiles.',
        );
        // Height: 55 (visible circle) + 8 (top) + 8 (bottom) = 71 px.
        expect(
          size.height,
          closeTo(71.0, tolerancePx),
          reason:
              'Logo button height must be ≈71 px (55 visible circle + 8 px '
              'top + 8 px bottom padding); changes here affect vertical '
              'centering inside the AppBar toolbar and shadow room.',
        );
        // The visible circle's left edge sits at x=0 within the widget
        // bounding box (no left padding). Width < height is the asymmetry
        // signature.
        expect(
          size.width,
          lessThan(size.height - 1.0),
          reason:
              'Width must be at least 1 px less than height to confirm the '
              'left padding is 0. A symmetric bounding box indicates the '
              'old `EdgeInsets.all(8)` shape has crept back.',
        );
      },
    );

    testWidgets('Hub sheet grid exposes 5 tiles in a 2-column grid', (
      WidgetTester tester,
    ) async {
      final screen = await buildHomeScreen(repo);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Open the Hub sheet by tapping the logo.
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      // Five tiles, in the order `_buildMaintenanceGrid` declares them. The
      // grid in lib/ is the source of truth for this order; if it changes
      // deliberately, update this expectation to match. A 2-column grid over
      // 5 tiles leaves the last row with a single tile alone; that is
      // expected and asserted here so a layout change cannot silently alter
      // the count or the order.
      final tiles = tester
          .widgetList<MaintenanceTile>(find.byType(MaintenanceTile))
          .toList(growable: false);
      expect(tiles.length, 5, reason: 'Hub sheet exposes exactly 5 tiles.');
      expect(
        tiles.map((t) => t.title).toList(growable: false),
        <String>[
          'Profile',
          'Stats',
          'Calendar',
          'Settings',
          'Exercise Library',
        ],
        reason: 'Maintenance tile order must match _buildMaintenanceGrid.',
      );
    });

    testWidgets('Hub sheet tile dimensions are unchanged by gap adjustment', (
      WidgetTester tester,
    ) async {
      // Pin the test surface to a phone-shaped size so the grid math is
      // deterministic across CI machines. The expected tile dimensions
      // are derived from the grid delegate config below so changing the
      // surface size keeps the regression guard correct.
      const surfaceSize = Size(432, 900);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final screen = await buildHomeScreen(repo);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      final tiles = find.byType(MaintenanceTile);
      expect(tiles, findsNWidgets(5));

      final sizes = <Size>[
        for (var i = 0; i < 5; i++)
          tester.getSize(find.byType(MaintenanceTile).at(i)),
      ];
      // All tiles must be the same size (grid delegate enforces it).
      for (final s in sizes) {
        expect(
          s,
          sizes.first,
          reason: 'All Hub tiles must have identical dimensions.',
        );
      }

      // Derive the expected tile dimensions from the grid delegate
      // config in `_buildMaintenanceGrid`. The delegate is:
      //   crossAxisCount: 2
      //   childAspectRatio: 1.1  (width / height)
      //   crossAxisSpacing: 16
      // The grid sits inside a `SliverPadding(fromLTRB(16, 0, 16, 24))`
      // (left+right = 32) and below the HUB header, so the grid width is
      // `surfaceSize.width − 32`. With one crossAxisSpacing between the
      // two columns:
      //   tileWidth  = (gridWidth − crossAxisSpacing) / crossAxisCount
      //   tileHeight = tileWidth / childAspectRatio
      // Keeping the expected values derived (not hard-coded) means a
      // future change to the surface size, the padding, or the grid
      // delegate updates the assertion automatically instead of silently
      // breaking the regression guard.
      const gridDelegate = _HubGridDelegateSpec(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
        horizontalPadding: 32, // 16 on each side of the grid
      );
      final gridWidth = surfaceSize.width - gridDelegate.horizontalPadding;
      final expectedTileWidth =
          (gridWidth - gridDelegate.crossAxisSpacing) /
          gridDelegate.crossAxisCount;
      final expectedTileHeight =
          expectedTileWidth / gridDelegate.childAspectRatio;

      final first = sizes.first;
      final ratio = first.width / first.height;
      expect(
        (ratio - gridDelegate.childAspectRatio).abs() < 0.01,
        isTrue,
        reason:
            'Tile aspect ratio must stay at '
            '\${gridDelegate.childAspectRatio} (width / height); the gap '
            'adjustment must not change tile size.',
      );

      expect(first.width, expectedTileWidth);
      expect(first.height, closeTo(expectedTileHeight, 0.5));
    });

    testWidgets(
      'Hub sheet grid renders without clip or overlap at largest text scale',
      (WidgetTester tester) async {
        // Largest supported system text scale per `MyApp`'s
        // `MediaQueryData.textScaler` clamp (1.1–1.6).
        await tester.binding.setSurfaceSize(const Size(432, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final screen = await buildHomeScreen(repo);
        await tester.pumpWidget(MediaAppWithScale(scale: 1.6, child: screen));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();

        final tiles = find.byType(MaintenanceTile);
        expect(tiles, findsNWidgets(5));

        final rects = <Rect>[
          for (var i = 0; i < 5; i++)
            tester.getRect(find.byType(MaintenanceTile).at(i)),
        ];
        // Each tile must be fully on-screen (no overflow past the bottom
        // edge of the test surface). The test surface is intentionally
        // taller than a typical phone so the Hub sheet is the only
        // overflow risk, not the layout behind it.
        for (final rect in rects) {
          expect(
            rect.bottom,
            lessThanOrEqualTo(900.0 + 0.5),
            reason:
                'Tile ${rect.topLeft} bottom (${rect.bottom}) must not '
                'overflow the test surface bottom (900 px).',
          );
        }

        // No two tiles overlap. For 2 columns, only vertically adjacent
        // tiles share an x-band; assert none of those overlap on y.
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            final a = rects[i];
            final b = rects[j];
            final overlapsX =
                a.left < b.right && b.left < a.right; // shared x-band
            final overlapsY = a.top < b.bottom && b.top < a.bottom;
            expect(
              !(overlapsX && overlapsY),
              isTrue,
              reason:
                  'Tiles $i and $j overlap on both axes (a=$a, b=$b). '
                  'The gap adjustment must not cause tiles to overlap.',
            );
          }
        }
      },
    );

    testWidgets('Hub sheet snap positions resolve correctly', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final screen = await buildHomeScreen(repo);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Capture the DraggableScrollableSheet configuration before any
      // user interaction. The sheet is configured with exactly two snap
      // points (collapsed peek + fully open) per
      // `hub-bottom-sheet-single-step-open-plan.md`. There is no
      // half-open intermediate snap.
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      expect(sheet.minChildSize, 0.0);
      expect(sheet.maxChildSize, greaterThanOrEqualTo(0.5));
      expect(
        sheet.maxChildSize,
        lessThanOrEqualTo(0.95),
        reason:
            'Sheet max extent is clamped to 0.95 by '
            '`hubSheetMaxExtent` so the sheet opens close to the '
            'screen bottom (natural extent ≈ 0.88) and is never '
            'capped shorter by the clamp.',
      );
      expect(sheet.snap, isTrue);
      expect(
        sheet.snapSizes,
        hasLength(2),
        reason:
            'Hub sheet must expose exactly two snap positions '
            '(collapsed + expanded); no half-open intermediate snap.',
      );
      final snapSizes = sheet.snapSizes!;
      expect(snapSizes[0], 0.0);
      expect(snapSizes[1], sheet.maxChildSize);

      // Sheet starts collapsed: the HUB label and the 5 tiles are
      // mounted inside a SliverList at extent 0, so they are off-screen
      // and not findable.
      expect(find.text('HUB'), findsNothing);

      // Tap the logo to open the sheet — the handle is the documented
      // tap target on the home-screen AppBar that snaps to maxChildSize.
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      // Sheet is now fully open.
      expect(find.text('HUB'), findsOneWidget);
      expect(find.byType(MaintenanceTile), findsNWidgets(5));
    });

    testWidgets(
      'HUB header sits a fixed gap above the first tile row (anchored to top)',
      (WidgetTester tester) async {
        // The content group — `HUB` header + maintenance grid — must
        // anchor to the top of the sheet, directly below the handle,
        // with an intentional gap between the header and the first
        // tile row. The gap is owned by the `SizedBox(height: 60)` in
        // `_buildMaintenanceSheet`'s content `Column` (no sliver
        // wrapper, no MediaQuery padding, no GridView top inset — so
        // the rendered gap equals the SizedBox height). The test pins
        // both the upper bound (so a 60+ px floating band can never
        // creep in again — that was the original bug this iteration
        // fixed) AND the lower bound (so the SizedBox never silently
        // drops to zero, which would make the grid feel jammed
        // against the header).
        await tester.binding.setSurfaceSize(const Size(432, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final screen = await buildHomeScreen(repo);
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();

        const gapMinPx = 50.0; // SizedBox is 60; allow 10 px tolerance
        const gapMaxPx = 70.0; // SizedBox is 60; allow 10 px tolerance
        final hubRect = tester.getRect(find.text('HUB'));
        final firstTileRect = tester.getRect(
          find.byType(MaintenanceTile).first,
        );
        final gap = firstTileRect.top - hubRect.bottom;
        expect(
          gap,
          greaterThanOrEqualTo(gapMinPx),
          reason:
              'HUB header must sit a deliberate gap above the first '
              'tile row — gap was ${gap.toStringAsFixed(2)} px, lower '
              'bound $gapMinPx px. A smaller gap means the '
              'SizedBox(height: 60) was removed and the grid is '
              'jammed against the header.',
        );
        expect(
          gap,
          lessThanOrEqualTo(gapMaxPx),
          reason:
              'HUB header must sit flush above the first tile row — '
              'gap was ${gap.toStringAsFixed(2)} px, upper bound '
              '$gapMaxPx px. A larger gap means the content group is '
              'floating inside the sheet instead of anchoring to the '
              'top directly below the drag handle.',
        );
      },
    );

    testWidgets('HUB-to-grid gap stays in range across screen heights', (
      WidgetTester tester,
    ) async {
      // Two viewports: the minimum supported (360 × 640) and a tall
      // phone-class surface. The gap should be the SAME constant
      // (the SizedBox is height-agnostic) on both surfaces — proves
      // the content does not drift with screen height.
      const viewports = <Size>[
        Size(360, 640), // minimum supported
        Size(432, 900), // tall phone-class
      ];

      for (final size in viewports) {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final screen = await buildHomeScreen(repo);
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();

        const gapMinPx = 50.0;
        const gapMaxPx = 70.0;
        final hubRect = tester.getRect(find.text('HUB'));
        final firstTileRect = tester.getRect(
          find.byType(MaintenanceTile).first,
        );
        final gap = firstTileRect.top - hubRect.bottom;
        expect(
          gap,
          inInclusiveRange(gapMinPx, gapMaxPx),
          reason:
              'At ${size.width.toInt()}×${size.height.toInt()} px, '
              'the HUB-to-grid gap must stay in '
              '[$gapMinPx, $gapMaxPx] px — was '
              '${gap.toStringAsFixed(2)} px. The SizedBox is '
              'height-agnostic so the gap must not drift with '
              'screen height.',
        );

        // Reset surface between iterations.
        await tester.binding.setSurfaceSize(null);
      }
    });

    testWidgets(
      'last tile row sits above the sheet content bottom (leftover space below)',
      (WidgetTester tester) async {
        // On a viewport that gives the sheet more vertical room than
        // the HUB + 5-tile grid needs, the leftover space must collect
        // BELOW the last row of tiles — never above it. This pins the
        // "content anchored to top" guarantee from the other side: the
        // bottom row cannot overflow the sheet, and there is always
        // empty space below it.
        await tester.binding.setSurfaceSize(const Size(432, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final screen = await buildHomeScreen(repo);
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();

        // The sheet's visible content area is the rounded-top
        // `Container` returned by the `DraggableScrollableSheet`
        // builder. Its decoration carries `BorderRadius.only(topLeft,
        // topRight: Radius.circular(24))` — that distinguishes it from
        // every other rounded-corner Container in the tree (handle,
        // tile surfaces).
        final sheetContainer = find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final d = w.decoration;
          if (d is! BoxDecoration) return false;
          final br = d.borderRadius;
          return br is BorderRadius &&
              br.topLeft == const Radius.circular(24) &&
              br.topRight == const Radius.circular(24);
        });
        expect(
          sheetContainer,
          findsOneWidget,
          reason:
              'The sheet container (24 px top-only border radius) '
              'must be present once the sheet is open.',
        );
        final sheetRect = tester.getRect(sheetContainer);

        final lastTileRect = tester.getRect(find.byType(MaintenanceTile).last);
        expect(
          lastTileRect.bottom,
          lessThanOrEqualTo(sheetRect.bottom + 0.5),
          reason:
              'Last tile row bottom (${lastTileRect.bottom}) must not '
              'exceed the sheet content area bottom '
              '(${sheetRect.bottom}). The grid must anchor to the top '
              'of the sheet, with leftover space landing BELOW the '
              'grid, not above or between rows.',
        );
      },
    );
  });
}

/// Tiny wrapper that pins the text scaler to a specific value for a
/// single test. Used by the largest-text-scale render check.
class MediaAppWithScale extends StatelessWidget {
  final double scale;
  final Widget child;

  const MediaAppWithScale({
    super.key,
    required this.scale,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(home: child),
    );
  }
}

/// Mirrors the `SliverGridDelegateWithFixedCrossAxisCount` config used
/// by `_buildMaintenanceGrid` in `home_screen.dart`. Keeps the
/// tile-dimension regression test in sync with the production grid
/// without hard-coding expected pixel values — changing any of these
/// fields here must also be reflected in the production grid delegate
/// (a comment callout in the test names the surface-to-pixel math, so
/// a future change to the grid delegate is caught here automatically).
class _HubGridDelegateSpec {
  final double crossAxisCount;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final double horizontalPadding;

  const _HubGridDelegateSpec({
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.childAspectRatio,
    required this.horizontalPadding,
  });
}
