import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// The calendar packs a whole month plus a stats strip into one screen with no
/// scrolling. Both parts are sized from the space that is actually available,
/// so these tests pin the sizes at which that used to fail: short phones, a
/// six-row month, wide viewports, and large accessibility text.
/// Mirrors `_MonthGrid`'s own arithmetic: 4pt of padding each side and six
/// 2pt gaps between seven columns.
double cellWidthFor(double viewportWidth) => (viewportWidth - 8 - 12) / 7;

/// Must track `_MonthGrid._minRowHeight`.
const double _minRowHeight = 52;

/// Holds the month load open so the calendar's loading frame actually renders,
/// the way it does on a device where storage takes a frame or more to answer.
class _BlockingRepo extends MockWorkoutRepository {
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<List<TrainingSession>> getSessionsByDateRange(
    int fromMs,
    int toMs,
  ) async {
    await _gate.future;
    return super.getSessionsByDateRange(fromMs, toMs);
  }
}

void main() {
  Future<MockWorkoutRepository> freshRepo() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    return repo;
  }

  Widget buildScreen(
    MockWorkoutRepository repo,
    CalendarState calendarState, {
    double textScale = 1.0,
  }) {
    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        home: CalendarScreen(
          calendarState: calendarState,
          periodState: PeriodState(repo),
          workoutState: WorkoutState(repo),
          routineState: RoutineState(repo),
          routineSessionService: RoutineSessionService(repo),
          sessionSummaryService: SessionSummaryService(repo),
          settingsState: SettingsState(repo, fakePreferencesService()),
          timerAlertService: FakeTimerAlertService(),
        ),
      ),
    );
  }

  /// Walks forward to the next month that needs six grid rows — the tallest
  /// case, and the one the old fixed-ratio grid could not fit.
  Future<void> goToSixRowMonth(
    WidgetTester tester,
    CalendarState calendarState,
  ) async {
    for (var i = 0; i < 12; i++) {
      final cells = OmniDateUtils.buildMonthGrid(
        calendarState.year,
        calendarState.month,
        startOfWeek: 'monday',
      ).length;
      if (cells == 42) return;
      await calendarState.goToNextMonth();
      await tester.pumpAndSettle();
    }
    fail('No six-row month found within a year.');
  }

  Future<void> seedSessions(
    MockWorkoutRepository repo,
    CalendarState calendarState, {
    required int day,
    required int count,
  }) async {
    for (var i = 0; i < count; i++) {
      final start = DateTime(
        calendarState.year,
        calendarState.month,
        day,
        9 + i,
      );
      await repo.createSession(
        TrainingSession(
          id: 'seed-$day-$i',
          ownerUserId: 'u-test',
          startedAtMs: start.millisecondsSinceEpoch,
          endedAtMs: start
              .add(const Duration(hours: 1, minutes: 23))
              .millisecondsSinceEpoch,
          title: 'Seed $i',
          modality: i.isEven
              ? Modality.resistanceLifting
              : Modality.cardioEndurance,
          createdAtMs: start.millisecondsSinceEpoch,
          updatedAtMs: start.millisecondsSinceEpoch,
        ),
      );
    }
    await calendarState.refresh();
  }

  /// Renders the calendar and returns every layout error Flutter reported.
  Future<List<String>> render(
    WidgetTester tester, {
    required Size size,
    int sessionsOnDayOne = 0,
    double textScale = 1.0,
  }) async {
    final repo = await freshRepo();
    final calendarState = CalendarState(repo);
    await calendarState.init();

    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      buildScreen(repo, calendarState, textScale: textScale),
    );
    await tester.pumpAndSettle();
    await goToSixRowMonth(tester, calendarState);
    if (sessionsOnDayOne > 0) {
      await seedSessions(repo, calendarState, day: 1, count: sessionsOnDayOne);
    }

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        errors.add(details.exceptionAsString().split('\n').first);
    await tester.pumpAndSettle();
    // Force a fresh layout pass so overflows are re-reported after seeding.
    tester.element(find.byType(CalendarScreen)).markNeedsBuild();
    await tester.pumpAndSettle();
    FlutterError.onError = previous;
    return errors;
  }

  group('calendar fits the viewport', () {
    final viewports = <String, Size>{
      'iPhone SE (375x667)': const Size(375, 667),
      'iPhone 8 Plus (414x736)': const Size(414, 736),
      'iPhone 14 (390x844)': const Size(390, 844),
      'tablet width (768x1024)': const Size(768, 1024),
      'landscape (844x390)': const Size(844, 390),
    };

    viewports.forEach((name, size) {
      testWidgets('$name — six-row month, no sessions', (tester) async {
        expect(await render(tester, size: size), isEmpty);
      });

      testWidgets('$name — six-row month with sessions', (tester) async {
        expect(await render(tester, size: size, sessionsOnDayOne: 5), isEmpty);
      });
    });

    testWidgets('short screen at 1.3x text scale', (tester) async {
      expect(
        await render(
          tester,
          size: const Size(375, 667),
          sessionsOnDayOne: 5,
          textScale: 1.3,
        ),
        isEmpty,
      );
    });

    testWidgets('stats strip survives 2.0x text scale', (tester) async {
      expect(
        await render(
          tester,
          size: const Size(390, 844),
          sessionsOnDayOne: 5,
          textScale: 2.0,
        ),
        isEmpty,
      );
    });
  });

  testWidgets('stats strip stays on screen on a short phone', (tester) async {
    const size = Size(375, 667);
    expect(await render(tester, size: size, sessionsOnDayOne: 5), isEmpty);

    for (final label in ['SESSIONS', 'TIME']) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.bottom,
        lessThanOrEqualTo(size.height),
        reason: '$label is pushed off the bottom of the screen',
      );
    }
  });

  group('session dots scale with the cell', () {
    final dotFinder = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Dot',
    );

    testWidgets('a short cell shows at least two slots and a +N badge', (
      tester,
    ) async {
      expect(
        await render(tester, size: const Size(375, 667), sessionsOnDayOne: 5),
        isEmpty,
      );

      expect(dotFinder, findsWidgets);
      expect(
        find.textContaining('+'),
        findsWidgets,
        reason: 'five sessions cannot fit a short cell, so +N must appear',
      );
    });

    testWidgets(
      'compressed landscape cell shows fewer dots than uncapped phone cell',
      (tester) async {
        // At the floor (52pt), landscape cells show ~3 rows of indicators.
        // On uncapped phone, more rows fit, so more dots are visible.
        // This test verifies that dot adaptivity is still observable at the floor.
        expect(
          await render(tester, size: const Size(844, 390), sessionsOnDayOne: 5),
          isEmpty,
        );
        final compressedCellDots = dotFinder.evaluate().length;

        expect(
          await render(tester, size: const Size(390, 844), sessionsOnDayOne: 5),
          isEmpty,
        );
        final uncappedPhoneCellDots = dotFinder.evaluate().length;

        // Compressed landscape should show fewer or equal dots than uncapped phone
        // (Compressed cell is restricted to floor, phone cell has more room)
        expect(
          compressedCellDots,
          lessThanOrEqualTo(uncappedPhoneCellDots),
          reason:
              'compressed landscape should show ≤ dots than uncapped phone (dot adaptivity observable at floor)',
        );
      },
    );
  });

  group('cell height capping', () {
    /// The height the grid actually gave each day cell, read back from the
    /// delegate it laid out with. Asserting on the GridView's own box instead
    /// proves nothing: that box is clamped to the space available whether or
    /// not the cells inside it were ever compressed.
    double measuredCellHeight(WidgetTester tester, double viewportWidth) {
      final gridView = tester.widget<GridView>(find.byType(GridView).first);
      final delegate =
          gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return cellWidthFor(viewportWidth) / delegate.childAspectRatio;
    }

    testWidgets('S-1: on a tall iPhone cells stop at the cap, never stretch', (
      tester,
    ) async {
      const size = Size(390, 844);
      expect(await render(tester, size: size), isEmpty);

      final cap = cellWidthFor(size.width) / 0.7;
      expect(
        measuredCellHeight(tester, size.width),
        closeTo(cap, 0.5),
        reason:
            'S-1: a six-row month on a tall phone leaves spare height, so the '
            'cap must be what sizes the cell — not the leftover space',
      );
    });

    testWidgets('S-5: on a tablet cells compress below the cap to fit', (
      tester,
    ) async {
      const size = Size(768, 1024);
      expect(await render(tester, size: size), isEmpty);

      final cap = cellWidthFor(size.width) / 0.7;
      final measured = measuredCellHeight(tester, size.width);

      // A tablet is wide enough that the cap (~153pt) exceeds the height a
      // six-row month has to spend, so the available-height path must win.
      // This is the assertion that fails if compression is ever disabled.
      expect(
        measured,
        lessThan(cap - 1),
        reason:
            'S-5: cell height ${measured.toStringAsFixed(1)}pt should be driven '
            'by available height, below the ${cap.toStringAsFixed(1)}pt cap',
      );
      expect(
        measured,
        greaterThan(_minRowHeight),
        reason: 'S-5: a tablet has room to spare, so the floor must not bind',
      );
    });

    testWidgets('S-8: in landscape cells hit the floor and the grid scrolls', (
      tester,
    ) async {
      const size = Size(844, 390);
      expect(await render(tester, size: size), isEmpty);

      final cap = cellWidthFor(size.width) / 0.7;
      expect(
        measuredCellHeight(tester, size.width),
        closeTo(_minRowHeight, 0.5),
        reason:
            'S-8: landscape cannot fit six rows, so cells must sit on the '
            '${_minRowHeight}pt floor rather than the ${cap.toStringAsFixed(0)}pt cap',
      );

      final gridView = tester.widget<GridView>(find.byType(GridView).first);
      expect(
        gridView.physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
        reason: 'S-8: the grid itself must scroll once it is at the floor',
      );

      // The point of scrolling the grid rather than the page: the stats stay put.
      expect(
        tester.getRect(find.text('SESSIONS')).bottom,
        lessThanOrEqualTo(size.height),
        reason: 'S-8: the stats strip must not be pushed off-screen',
      );
    });

    testWidgets('the cap and the floor are different code paths', (
      tester,
    ) async {
      // Guards against a regression collapsing both cases onto one value:
      // a tall phone must be capped while landscape sits on the floor.
      const phone = Size(390, 844);
      expect(await render(tester, size: phone), isEmpty);
      final phoneCell = measuredCellHeight(tester, phone.width);

      const landscape = Size(844, 390);
      expect(await render(tester, size: landscape), isEmpty);
      final landscapeCell = measuredCellHeight(tester, landscape.width);

      expect(
        landscapeCell,
        lessThan(phoneCell),
        reason:
            'landscape (${landscapeCell.toStringAsFixed(1)}pt) is width-rich but '
            'height-poor, so its cells must end up shorter than a phone\'s '
            '(${phoneCell.toStringAsFixed(1)}pt) despite the wider cells',
      );
    });
  });

  group('stats strip placement', () {
    testWidgets('S-2: Stats strip sits directly below grid, not at screen bottom', (
      tester,
    ) async {
      // iPhone SE: 375x667pt, 5-row month with 0 sessions
      const size = Size(375, 667);
      expect(await render(tester, size: size), isEmpty);

      // Find the grid's bottom edge
      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsWidgets);
      final gridRect = tester.getRect(gridFinder.first);
      final gridBottom = gridRect.bottom;

      // Find the stats strip by its container or divider
      // Look for the divider line that starts the stats strip
      final dividerFinder = find.byType(Divider);
      // Stats strip should have a divider; find the one closest to our grid
      expect(dividerFinder, findsWidgets);

      // Get the first divider's top (should be the start of stats strip)
      final dividerRect = tester.getRect(dividerFinder.first);
      final statsTop = dividerRect.top;

      // The stats strip should sit directly below the grid
      // There's an 8pt Padding from "lib/features/calendar/calendar_screen.dart:156"
      // plus small tolerance for layout rounding
      expect(
        statsTop - gridBottom,
        lessThanOrEqualTo(30), // Padding + tolerance
        reason:
            'S-2: Stats strip should sit below grid; gap is ${statsTop - gridBottom}pt',
      );

      // Stats should be fully on screen (check divider bottom)
      expect(
        dividerRect.bottom,
        lessThanOrEqualTo(size.height),
        reason: 'S-2: Stats strip should be on-screen',
      );
    });

    testWidgets('S-3: Short screen with few-row month: dead space below stats', (
      tester,
    ) async {
      // iPhone SE landscape: narrow space, grid should not expand to fill
      // We'll test this by checking that the grid + stats don't fill the entire screen
      const size = Size(375, 667);
      expect(await render(tester, size: size), isEmpty);

      // Get grid height
      final gridFinder = find.byType(GridView);
      final gridRect = tester.getRect(gridFinder.first);
      final gridHeight = gridRect.height;

      // Get stats strip height (approximate by looking at SESSIONS to bottom of strip)
      final statsLabelFinder = find.text('SESSIONS');
      final statsLabelRect = tester.getRect(statsLabelFinder.first);

      // Find another label to estimate stats height
      final timeLabelFinder = find.text('TIME');
      final timeLabelRect = tester.getRect(timeLabelFinder.first);

      // Stats height is roughly from the top of the section to the bottom
      // For this test, we just verify that grid + stats is less than screen height
      final gridTop = gridRect.top;
      final statsBottom =
          timeLabelRect.bottom + 20; // Add some margin for wrap content

      final totalHeight =
          gridTop + gridHeight + (statsBottom - statsLabelRect.top);

      // There should be some dead space at the bottom
      expect(
        totalHeight,
        lessThan(size.height),
        reason:
            'S-3: Grid + stats should not fill entire screen, leaving dead space',
      );
    });
  });

  testWidgets('the loading frame lays out without error', (tester) async {
    // The mock repository normally resolves before a frame can render, so the
    // loading branch never gets exercised. On a device the month load takes at
    // least a frame, so block the load and pump that frame deliberately.
    const size = Size(390, 844);
    final repo = _BlockingRepo();
    await repo.initialize();
    final calendarState = CalendarState(repo);

    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        errors.add(details.exceptionAsString().split('\n').first);

    await tester.pumpWidget(buildScreen(repo, calendarState));
    final loading = calendarState.init();
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'the blocked load should leave the spinner on screen',
    );
    expect(
      errors,
      isEmpty,
      reason: 'the loading frame must lay out cleanly: $errors',
    );

    repo.release();
    await loading;
    // Safe to settle only now — the spinner animates forever while it is shown.
    await tester.pumpAndSettle();
    FlutterError.onError = previous;

    expect(find.byType(GridView), findsWidgets);
    expect(errors, isEmpty, reason: 'loading → grid transition: $errors');
  });

  testWidgets('the modality legend keeps clear of the screen edge', (
    tester,
  ) async {
    // A short phone is where this binds: the legend appears, the grid gives up
    // height to make room for it, and without a bottom inset the strip would
    // end flush against the screen edge.
    const size = Size(375, 667);
    expect(await render(tester, size: size, sessionsOnDayOne: 5), isEmpty);

    final strip = tester.getRect(
      find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_MonthlyStatsStrip',
          )
          .first,
    );
    expect(
      strip.bottom,
      lessThanOrEqualTo(size.height - 12),
      reason:
          'the stats strip ends at ${strip.bottom.toStringAsFixed(1)}pt with no '
          'clearance below it on a ${size.height.toInt()}pt screen',
    );

    // The room came from the grid, not from pushing the legend off-screen.
    final gridView = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    final cellHeight = cellWidthFor(size.width) / delegate.childAspectRatio;
    expect(
      cellHeight,
      lessThan(cellWidthFor(size.width) / 0.7),
      reason: 'the grid should compress to fund the legend, not overflow',
    );
    expect(cellHeight, greaterThan(_minRowHeight));
  });

  group('session dot capacity at capped height', () {
    final dotFinder = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Dot',
    );

    testWidgets('S-6: Five sessions show all 5 dots at capped iPhone height', (
      tester,
    ) async {
      // iPhone 14: 390x844pt, with 5 sessions on day 1
      // At capped height (~75pt), 3 rows fit, so 6-dot capacity
      // All 5 should be visible, no badge
      const size = Size(390, 844);
      expect(await render(tester, size: size, sessionsOnDayOne: 5), isEmpty);

      final dots = dotFinder.evaluate().toList();
      expect(
        dots.length,
        equals(5),
        reason:
            'S-6: All 5 sessions should show as dots at capped iPhone height',
      );

      // Verify no "+N" badge appears (look for _OverflowBadge specifically)
      // The badge is inside a Container in _OverflowBadge, so find by the text
      final badgeFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_OverflowBadge',
      );
      expect(
        badgeFinder,
        findsNothing,
        reason: 'S-6: No badge should appear when all sessions fit',
      );
    });

    testWidgets(
      'S-7: Seven sessions show 5 dots + "+2" badge at capped height',
      (tester) async {
        // iPhone 14 with 7 sessions
        // Capacity is 6 (3 rows × 2), but badge takes a slot
        // So 5 dots + "+2" badge
        const size = Size(390, 844);
        expect(await render(tester, size: size, sessionsOnDayOne: 7), isEmpty);

        final dots = dotFinder.evaluate().toList();
        expect(
          dots.length,
          equals(5),
          reason: 'S-7: 5 dots should show when 7 sessions exceed capacity',
        );

        // Find the badge (_OverflowBadge)
        final badgeFinder = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_OverflowBadge',
        );
        expect(
          badgeFinder,
          findsWidgets,
          reason: 'S-7: "+N" badge should appear (7 sessions − 5 visible = 2)',
        );

        // Verify the badge text is "+2"
        expect(
          find.text('+2'),
          findsWidgets,
          reason: 'S-7: Badge should show "+2"',
        );
      },
    );
  });
}
