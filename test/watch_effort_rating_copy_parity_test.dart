// Both devices ask the same question about a session: the phone's rating sheet
// (PR 1's, shared by every phone surface that asks) is held to the same
// contract the wrist's copy is.
//
// Plan: `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), Phase 5 — D-102, D-143.
// Scenario mapping:
//   S-287 copy parity → `S-287 ...`
//
// The wrist's half is watchOS `WatchEffortRatingTests` (`S-211`), which holds
// `WatchEffortRatingCopy` to the same file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/effort_rating_sheet.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// `watch/contract/watch_effort_rating_contract.json`, parsed.
Map<String, Object?> _contract() =>
    (jsonDecode(
              File(
                '${Directory.current.path}/watch/contract/'
                'watch_effort_rating_contract.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

/// Every text the open sheet draws, in paint order.
List<String> _sheetTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(EffortRatingSheet),
      matching: find.byType(Text),
    ),
  ))
    ?text.data,
];

void main() {
  group('S-287 the phone asks the contract’s question', () {
    testWidgets('S-287 the sheet’s title, scale and end labels are the '
        'contract’s', (tester) async {
      final contract = _contract();
      final scale = (contract['scale']! as Map).cast<String, Object?>();
      final min = scale['min']! as int;
      final max = scale['max']! as int;
      final labels = (contract['labels']! as Map).cast<String, Object?>();

      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EffortRatingSheet(
              startedAt: DateTime(2026, 9, 25, 10),
              onRated: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final texts = _sheetTexts(tester);
      expect(
        texts.first,
        contract['title'],
        reason: 'S-287 the sheet asks the contract’s question',
      );
      expect(
        [for (final text in texts) ?int.tryParse(text)],
        [for (var n = min; n <= max; n++) n],
        reason: 'S-287 one tile per point of the contract’s scale, in order',
      );

      final low = labels['$min']! as String;
      final high = labels['$max']! as String;
      expect(labels.keys.toSet(), {
        '$min',
        '$max',
      }, reason: 'S-287 the contract labels the two ends only');
      expect(
        texts.sublist(texts.length - 2),
        [low, high],
        reason: 'S-287 the end labels are the contract’s, and the last words',
      );
      expect(
        tester.getCenter(find.text(low)).dx,
        lessThan(tester.getCenter(find.text(high)).dx),
        reason: 'S-287 the scale’s low end is on the left, its high end right',
      );
      expect(
        tester.getTopLeft(find.text(low)).dx,
        lessThanOrEqualTo(tester.getCenter(find.text('$min')).dx),
        reason: 'S-287 the low end’s label sits under the lowest tile',
      );
      expect(
        tester.getTopRight(find.text(high)).dx,
        greaterThanOrEqualTo(tester.getCenter(find.text('$max')).dx),
        reason: 'S-287 the high end’s label sits under the highest tile',
      );
    });

    testWidgets('S-287 the Session Summary asks through that same sheet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final workoutState = WorkoutState(repository);
      await workoutState.createNewSession();

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: RoutineState(repository),
            sessionSummaryService: SessionSummaryService(repository),
            settingsState: SettingsState(repository, fakePreferencesService()),
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(EffortRatingSheet),
        findsOneWidget,
        reason:
            'S-287 PR 1’s automatic prompt is the shared sheet, so the '
            'contract holds for it too',
      );
      expect(_sheetTexts(tester).first, _contract()['title'], reason: 'S-287');
    });
  });
}
