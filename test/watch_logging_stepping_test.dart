// Watch logging surfaces — metric stepping.
//
// Plan: `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
// Scenario mapping:
//   S-007 metric stepping matches metric semantics → `S-007 ...`
//
// A step is a property of the metric and the saved unit preference, never of
// the surface: one table, consulted by the Wear OS surface and mirrored by the
// watchOS one, so a crown detent means the same thing on both wrists.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';

import 'helpers/fake_preferences_service.dart';

/// The values both watch clients are held to. The watchOS suite reads this same
/// file, so a change to the table on either platform fails on both.
Map<String, Object?> _contract() =>
    (jsonDecode(
              File(
                '${Directory.current.path}/watch/contract/'
                'watch_logging_contract.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

Map<String, double> _numeric(Object? value) => (value! as Map)
    .cast<String, Object?>()
    .map((key, entry) => MapEntry(key, (entry! as num).toDouble()));

void main() {
  group('S-007 metric stepping matches metric semantics', () {
    test('S-007 the metric keys are the app\'s metric key vocabulary', () {
      expect(
        MetricIds.keyToMetricId.keys,
        containsAll(WatchMetricKey.all),
        reason:
            'the wrist may offer fewer metrics than the phone, never others',
      );
    });

    test('S-007 counts step by one', () {
      expect(WatchMetricStepping.stepFor(WatchMetricKey.reps), 1);
      expect(WatchMetricStepping.stepFor(WatchMetricKey.rounds), 1);
    });

    test('S-007 load steps by the saved increment', () {
      expect(WatchMetricStepping.stepFor(WatchMetricKey.weight), 2.5);
      expect(WatchMetricStepping.stepFor(WatchMetricKey.extraWeight), 2.5);
    });

    test('S-007 a pound preference steps in pounds, stored in kilograms', () {
      const pounds = WatchUnitPreferences(weightUnit: 'lbs');
      final step = WatchMetricStepping.stepFor(
        WatchMetricKey.weight,
        units: pounds,
      );

      expect(step, moreOrLessEquals(UnitFormatter.toKilograms(5, 'lbs')));
      expect(
        UnitFormatter.fromKilograms(80 + step, 'lbs') -
            UnitFormatter.fromKilograms(80, 'lbs'),
        moreOrLessEquals(5.0, epsilon: 0.001),
        reason: 'one detent is five pounds on the wrist, whatever it is in kg',
      );
    });

    test('S-007 duration steps by five seconds', () {
      expect(WatchMetricStepping.stepFor(WatchMetricKey.duration), 5);
      expect(WatchMetricStepping.stepFor(WatchMetricKey.roundDuration), 5);
    });

    test('S-007 distance steps by the unit-appropriate increment', () {
      expect(WatchMetricStepping.stepFor(WatchMetricKey.distance), 100);

      const miles = WatchUnitPreferences(distanceUnit: 'miles');
      expect(
        WatchMetricStepping.stepFor(WatchMetricKey.distance, units: miles),
        moreOrLessEquals(0.1 * UnitFormatter.metresPerUnit('miles')),
      );
    });

    test('S-007 an unknown metric does not move', () {
      expect(WatchMetricStepping.stepFor('metric-nonsense'), 0);
      expect(
        WatchMetricStepping.adjust(
          80,
          metricKey: 'metric-nonsense',
          detents: 3,
        ),
        80,
      );
    });

    test('S-007 the units come from the preference owner', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final settings = SettingsState(repository, fakePreferencesService());
      await settings.initialize();
      await settings.setPreferredWeightUnit('lbs');
      await settings.setPreferredDistanceUnit('miles');

      final units = WatchUnitPreferences.fromSettings(settings);

      expect(units.weightUnit, 'lbs');
      expect(units.distanceUnit, 'miles');
      expect(
        WatchMetricStepping.stepFor(WatchMetricKey.weight, units: units),
        moreOrLessEquals(UnitFormatter.toKilograms(5, 'lbs')),
        reason: 'a pound preference steps the wrist in pounds too',
      );
    });
  });

  group('S-007 rotary detents move the value', () {
    test('S-007 turning forward and back is symmetric and drift-free', () {
      var value = 80.0;
      for (var i = 0; i < 3; i++) {
        value = WatchMetricStepping.adjust(
          value,
          metricKey: WatchMetricKey.weight,
          detents: 1,
        );
      }
      expect(value, 87.5);
      for (var i = 0; i < 3; i++) {
        value = WatchMetricStepping.adjust(
          value,
          metricKey: WatchMetricKey.weight,
          detents: -1,
        );
      }
      expect(value, 80.0);
    });

    test('S-007 fractional detents move proportionally', () {
      expect(
        WatchMetricStepping.adjust(
          10,
          metricKey: WatchMetricKey.reps,
          detents: 2.5,
        ),
        12.5,
      );
    });

    test('S-007 a count never falls below one', () {
      expect(
        WatchMetricStepping.adjust(
          1,
          metricKey: WatchMetricKey.reps,
          detents: -5,
        ),
        1,
      );
      expect(
        WatchMetricStepping.adjust(
          2,
          metricKey: WatchMetricKey.rounds,
          detents: -9,
        ),
        1,
      );
    });

    test('S-007 load and distance never go negative', () {
      expect(
        WatchMetricStepping.adjust(
          0,
          metricKey: WatchMetricKey.weight,
          detents: -1,
        ),
        0,
      );
      expect(
        WatchMetricStepping.adjust(
          0,
          metricKey: WatchMetricKey.duration,
          detents: -1,
        ),
        0,
      );
      expect(
        WatchMetricStepping.adjust(
          0,
          metricKey: WatchMetricKey.distance,
          detents: -1,
        ),
        0,
      );
    });

    test('S-007 extra load is signed, because band assist is a load', () {
      expect(
        WatchMetricStepping.adjust(
          0,
          metricKey: WatchMetricKey.extraWeight,
          detents: -4,
        ),
        -10,
        reason: 'negative extra load is band assist (EffortDefaults, drill)',
      );
    });
  });

  group('Shared contract', () {
    final contract = _contract();
    final stepping = _numeric(contract['stepping']);
    final conversion = _numeric(contract['unitConversion']);

    test('S-007 the stepping table is the shared one', () {
      expect(
        WatchMetricStepping.kilogramsPerDetent,
        stepping['kilogramsPerDetent'],
      );
      expect(WatchMetricStepping.poundsPerDetent, stepping['poundsPerDetent']);
      expect(
        WatchMetricStepping.secondsPerDetent,
        stepping['secondsPerDetent'],
      );
      expect(
        WatchMetricStepping.tenthsOfDistanceUnitPerDetent,
        stepping['tenthsOfDistanceUnitPerDetent'],
      );
      expect(WatchMetricStepping.countPerDetent, stepping['countPerDetent']);
    });

    test('S-007 the metric keys are the shared ones', () {
      expect(
        WatchMetricKey.all,
        (contract['metricKeys']! as List).cast<String>(),
        reason: 'the watchOS mirror enumerates the same keys, in this order',
      );
    });

    test('S-007 UnitFormatter converts with the shared constants', () {
      // The constants are private to UnitFormatter, so the canonical owner is
      // pinned by what it computes with them.
      expect(
        UnitFormatter.toKilograms(1, 'lbs'),
        closeTo(1 / conversion['kilogramsPerPound']!, 1e-9),
      );
      expect(
        UnitFormatter.fromKilograms(1, 'lbs'),
        closeTo(conversion['kilogramsPerPound']!, 1e-9),
      );
      expect(
        UnitFormatter.metresPerUnit('miles'),
        closeTo(1000 / conversion['kilometresPerMile']!, 1e-6),
      );
    });
  });
}
