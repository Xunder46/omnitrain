// filepath: test/stats_primer_screen_test.dart
//
// The Stats screen's first-use explanation surfaces: the header "?" and the
// richer empty card (see
// `docs/plans/2026-10-04-10b-stats-pr10b-primer-sheet-plan/`).
//
// Mock-only: these are widget tests, so the repository is the in-memory
// `MockWorkoutRepository`. Hive writes never drain under `FakeAsync`, and the
// screen does not persist anything anyway — it holds no primer state, so a
// tap here can never mark the flag seen (that is the point of S-2704/S-2707).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/stats_primer_sheet.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/stats/stats_primer_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Pumps the Stats screen. [showPrimerHelp] is omitted entirely when null, so
/// S-2703 exercises the constructor exactly as the 18 existing files do.
Future<void> _pumpStats(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  bool? showPrimerHelp,
}) async {
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();

  await tester.pumpWidget(
    MaterialApp(
      home: showPrimerHelp == null
          ? StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
            )
          : StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
              showPrimerHelp: showPrimerHelp,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group(
    'S-2703: with showPrimerHelp omitted the Stats primer feature is off',
    () {
      testWidgets(
        'no help action, no empty-state button and the chart action still renders',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repo = await _freshRepo();

          await _pumpStats(tester, repo);

          expect(find.byKey(const Key('stats_primer_help')), findsNothing);
          expect(find.byType(StatsPrimerSheet), findsNothing);
          expect(find.byKey(const Key('stats_primer_empty_cta')), findsNothing);
          expect(find.text('How Stats works'), findsNothing);
          expect(find.byTooltip('Records & Trends'), findsOneWidget);
        },
      );
    },
  );

  group('S-2704: the header "?" reopens the primer and never marks it', () {
    testWidgets('reopening with an unseen state leaves it unseen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepo();
      // Held by the test, never passed to the screen (D-2019).
      final state = StatsPrimerState(repo);
      await state.init();

      await _pumpStats(tester, repo, showPrimerHelp: true);

      await tester.tap(find.byKey(const Key('stats_primer_help')));
      await tester.pumpAndSettle();

      expect(find.byType(StatsPrimerSheet), findsOneWidget);
      expect(find.byKey(const Key('stats_primer_block_page')), findsOneWidget);
      expect(
        find.byKey(const Key('stats_primer_block_signals')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stats_primer_block_records')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('stats_primer_dismiss')));
      await tester.pumpAndSettle();

      expect(find.byType(StatsPrimerSheet), findsNothing);
      // The screen holds no reference, so the reopen could not have marked it.
      expect(state.hasSeen, isFalse);
      expect(state.shouldShowPrimer, isTrue);
    });

    testWidgets('reopening with a seen state still opens the sheet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepo();
      final state = StatsPrimerState(repo);
      await state.init();
      await state.markSeen();

      await _pumpStats(tester, repo, showPrimerHelp: true);

      await tester.tap(find.byKey(const Key('stats_primer_help')));
      await tester.pumpAndSettle();

      expect(find.byType(StatsPrimerSheet), findsOneWidget);

      await tester.tap(find.byKey(const Key('stats_primer_dismiss')));
      await tester.pumpAndSettle();

      expect(find.byType(StatsPrimerSheet), findsNothing);
      expect(state.hasSeen, isTrue);
    });
  });

  group('S-2707: the first-use card explains what will appear', () {
    testWidgets(
      'the empty state keeps its title and body and adds the explanation and the button',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = await _freshRepo();

        await _pumpStats(tester, repo, showPrimerHelp: true);

        // The kept title and body, each exactly once.
        expect(find.text('No sessions yet'), findsOneWidget);
        expect(
          find.text('Complete your first session to see stats here.'),
          findsOneWidget,
        );

        // The three new lines, in order.
        const line1 = 'Your training mix, by kind of work.';
        const line2 = 'Your records, and how each exercise changes over time.';
        const line3 =
            'How your eating lines up with your training, once you log food.';
        expect(find.text(line1), findsOneWidget);
        expect(find.text(line2), findsOneWidget);
        expect(find.text(line3), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(line1)).dy,
          lessThan(tester.getTopLeft(find.text(line2)).dy),
        );
        expect(
          tester.getTopLeft(find.text(line2)).dy,
          lessThan(tester.getTopLeft(find.text(line3)).dy),
        );

        // The button, below the lines.
        expect(find.byKey(const Key('stats_primer_empty_cta')), findsOneWidget);
        expect(find.text('How Stats works'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(line3)).dy,
          lessThan(tester.getTopLeft(find.text('How Stats works')).dy),
        );
      },
    );

    testWidgets(
      'the empty-state button opens the sheet without marking it seen',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = await _freshRepo();
        final state = StatsPrimerState(repo);
        await state.init();

        await _pumpStats(tester, repo, showPrimerHelp: true);

        await tester.tap(find.byKey(const Key('stats_primer_empty_cta')));
        await tester.pumpAndSettle();

        expect(find.byType(StatsPrimerSheet), findsOneWidget);
        expect(
          find.byKey(const Key('stats_primer_block_page')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('stats_primer_block_signals')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('stats_primer_block_records')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('stats_primer_dismiss')));
        await tester.pumpAndSettle();

        expect(find.byType(StatsPrimerSheet), findsNothing);
        expect(state.hasSeen, isFalse);
      },
    );
  });

  group('S-2708: the "?" and the chart icon coexist', () {
    testWidgets('the chart icon stays the only way into Records & Trends', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepo();

      await _pumpStats(tester, repo, showPrimerHelp: true);

      expect(find.byKey(const Key('stats_primer_help')), findsOneWidget);
      expect(find.byTooltip('Records & Trends'), findsOneWidget);
      expect(find.byTooltip('About Stats'), findsOneWidget);

      await tester.tap(find.byTooltip('Records & Trends'));
      await tester.pumpAndSettle();

      expect(find.byType(RecordsAndTrendsScreen), findsOneWidget);
    });
  });

  group('S-2714: the taller first-use card fits a small viewport', () {
    testWidgets('the card lays out at 320x568 without an overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = await _freshRepo();

      await _pumpStats(tester, repo, showPrimerHelp: true);

      expect(tester.takeException(), isNull);
      expect(find.text('No sessions yet'), findsOneWidget);
      expect(
        find.text('Complete your first session to see stats here.'),
        findsOneWidget,
      );
      expect(find.text('Your training mix, by kind of work.'), findsOneWidget);
      expect(
        find.text('Your records, and how each exercise changes over time.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'How your eating lines up with your training, once you log food.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stats_primer_empty_cta')), findsOneWidget);
    });
  });
}
