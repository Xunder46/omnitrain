// Stats PR 4b, Phase 2 — the change indicator's text.
//
// `formatNativeChange` is the one place the delta between an exercise's window
// value and its previous range's value becomes a string: an arrow and a signed
// magnitude, or an em dash when there is nothing to compare. The magnitude is
// formatted by the same per-metric rule `formatNativeMetric` uses, so a change
// and the figure above it read in one unit.
//
// The chip that renders this text is 4b2's; this file is the formatter's proof
// while the chip lands there. D-508 of
// `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/widgets/native_value_format.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';

Future<SettingsState> settingsWith({
  String weightUnit = 'kg',
  String distanceUnit = 'km',
}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setPreferredWeightUnit(weightUnit);
  await settings.setPreferredDistanceUnit(distanceUnit);
  return settings;
}

void main() {
  group('formatNativeChange', () {
    test('the three branches: up, down and nothing to compare', () async {
      final settings = await settingsWith();

      expect(formatNativeChange(NativeMetric.reps, 3, settings), '↑ +3 reps');
      expect(formatNativeChange(NativeMetric.reps, -3, settings), '↓ -3 reps');
      expect(formatNativeChange(NativeMetric.reps, 0, settings), '—');
    });

    test('a weight reads in the preferred weight unit', () async {
      final kg = await settingsWith();
      expect(
        formatNativeChange(NativeMetric.estimatedOneRepMax, 5, kg),
        '↑ +5 kg',
      );

      final lbs = await settingsWith(weightUnit: 'lbs');
      expect(
        formatNativeChange(NativeMetric.estimatedOneRepMax, 5, lbs),
        '↑ +11.0 lbs',
      );
    });

    test('a rep count is a whole number', () async {
      final settings = await settingsWith();
      expect(formatNativeChange(NativeMetric.reps, 2.4, settings), '↑ +2 reps');
    });

    test('a clock covers holds and durations', () async {
      final settings = await settingsWith();
      expect(formatNativeChange(NativeMetric.hold, 15, settings), '↑ +0:15');
      expect(
        formatNativeChange(NativeMetric.duration, -90, settings),
        '↓ -1:30',
      );
    });

    test('rounds and minutes are counts', () async {
      final settings = await settingsWith();
      expect(
        formatNativeChange(NativeMetric.rounds, 2, settings),
        '↑ +2 rounds',
      );
      expect(
        formatNativeChange(NativeMetric.roundMinutes, -3, settings),
        '↓ -3 min',
      );
    });

    test('a pace reads per the preferred distance unit', () async {
      final km = await settingsWith();
      expect(formatNativeChange(NativeMetric.pace, 30, km), '↑ +0:30 /km');

      final miles = await settingsWith(distanceUnit: 'miles');
      expect(
        formatNativeChange(NativeMetric.pace, 30, miles),
        '↑ +0:48 /mi',
        reason: 'the same conversion formatNativeMetric uses, not a second one',
      );
    });
  });

  // The Instruments rows' own table (D-4008): what the figure above the change
  // chip *is*. It is a second table over the primary metric, so the secondary
  // table's wording (`Total hold`, `Total time`) never moves.
  group('nativePrimaryLabel', () {
    test('every metric is pinned, including the three a row already labels '
        'elsewhere', () {
      const expected = <NativeMetric, String?>{
        NativeMetric.estimatedOneRepMax: 'Est. 1RM',
        NativeMetric.reps: 'Best set',
        NativeMetric.duration: 'Total time',
        NativeMetric.pace: 'Best pace',
        NativeMetric.hold: null,
        NativeMetric.rounds: null,
        NativeMetric.roundMinutes: null,
      };

      expect(
        expected.keys.toSet(),
        NativeMetric.values.toSet(),
        reason: 'a new metric must be given a label or an explicit null',
      );
      for (final entry in expected.entries) {
        expect(nativePrimaryLabel(entry.key), entry.value, reason: '${entry.key}');
      }
    });

    test('the nulls are the metrics whose row carries a labelled second '
        'figure', () {
      expect(nativePrimaryLabel(NativeMetric.hold), isNull);
      expect(nativePrimaryLabel(NativeMetric.rounds), isNull);
      expect(nativePrimaryLabel(NativeMetric.roundMinutes), isNull);

      // The secondary table is untouched: it still names the second figure.
      expect(nativeSecondaryLabel(NativeMetric.duration), 'Total hold');
      expect(nativeSecondaryLabel(NativeMetric.roundMinutes), 'Total time');
    });
  });
}
