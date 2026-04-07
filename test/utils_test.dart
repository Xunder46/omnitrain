import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/effort_defaults.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality_config.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/core/utils/observation_grouper.dart';
import 'package:omnitrain/data/models/models.dart';

// ── Minimal observation stub for ObservationGrouper tests ─────────────────
// ObservationGrouper accesses .metricId, .valueInt, .valueReal, .valueBool
// directly on the dynamic list elements, so we use the actual model.

EffortObservation _obs({
  required String metricId,
  int? valueInt,
  double? valueReal,
  bool? valueBool,
}) =>
    EffortObservation(
      id: 'obs-${metricId.hashCode}',
      effortId: 'e-1',
      metricId: metricId,
      valueInt: valueInt,
      valueReal: valueReal,
      valueBool: valueBool,
      createdAtMs: 0,
      updatedAtMs: 0,
    );

Exercise _exercise({
  List<String> capabilities = const [],
  String disciplineId = 'cat-unknown',
}) =>
    Exercise(
      id: 'ex-1',
      ownerUserId: 'u-1',
      disciplineId: disciplineId,
      name: 'Test Exercise',
      description: '',
      movementPattern: 'push',
      isArchived: false,
      createdAtMs: 0,
      updatedAtMs: 0,
      capabilities: capabilities,
    );

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // ObservationGrouper
  // ══════════════════════════════════════════════════════════════════════════

  group('ObservationGrouper', () {
    // ── set grouping ─────────────────────────────────────────────────────
    group('set grouping', () {
      test('groups reps+weight pair (reps first)', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-reps', valueInt: 10),
          _obs(metricId: 'metric-weight', valueReal: 50.0),
        ]);
        expect(result, hasLength(1));
        expect(result[0]['reps'], 10);
        expect(result[0]['weight'], 50.0);
        expect(result[0]['skipped'], false);
      });

      test('groups reps+weight pair (weight first)', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-weight', valueReal: 80.0),
          _obs(metricId: 'metric-reps', valueInt: 5),
        ]);
        expect(result, hasLength(1));
        expect(result[0]['reps'], 5);
        expect(result[0]['weight'], 80.0);
      });

      test('extracts skipped flag from reps observation', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-reps', valueInt: 0, valueBool: true),
          _obs(metricId: 'metric-weight', valueReal: 60.0),
        ]);
        expect(result[0]['skipped'], true);
      });

      test('multiple pairs produce multiple entries', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-reps', valueInt: 10),
          _obs(metricId: 'metric-weight', valueReal: 50.0),
          _obs(metricId: 'metric-reps', valueInt: 8),
          _obs(metricId: 'metric-weight', valueReal: 55.0),
        ]);
        expect(result, hasLength(2));
        expect(result[1]['reps'], 8);
        expect(result[1]['weight'], 55.0);
      });

      test('odd number of observations drops the trailing one', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-reps', valueInt: 10),
          _obs(metricId: 'metric-weight', valueReal: 50.0),
          _obs(metricId: 'metric-reps', valueInt: 8), // unpaired
        ]);
        expect(result, hasLength(1));
      });

      test('empty observations returns empty list', () {
        final result = ObservationGrouper.groupByEffortKind('set', []);
        expect(result, isEmpty);
      });

      test('null valueInt defaults to 0 for reps', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-reps'), // valueInt is null
          _obs(metricId: 'metric-weight', valueReal: 40.0),
        ]);
        expect(result[0]['reps'], 0);
      });

      test('null valueReal defaults to 0.0 for weight', () {
        final result = ObservationGrouper.groupByEffortKind('set', [
          _obs(metricId: 'metric-reps', valueInt: 5),
          _obs(metricId: 'metric-weight'), // valueReal is null
        ]);
        expect(result[0]['weight'], 0.0);
      });
    });

    // ── timed grouping ───────────────────────────────────────────────────
    group('timed grouping', () {
      test('groups duration+distance pair', () {
        final result = ObservationGrouper.groupByEffortKind('timed', [
          _obs(metricId: 'metric-duration', valueInt: 300),
          _obs(metricId: 'metric-distance', valueReal: 1.5),
        ]);
        expect(result, hasLength(1));
        expect(result[0]['duration'], 300);
        expect(result[0]['distance'], 1.5);
      });

      test('handles reversed order (distance first)', () {
        final result = ObservationGrouper.groupByEffortKind('timed', [
          _obs(metricId: 'metric-distance', valueReal: 2.0),
          _obs(metricId: 'metric-duration', valueInt: 600),
        ]);
        expect(result[0]['duration'], 600);
        expect(result[0]['distance'], 2.0);
      });

      test('null values default to 0 / 0.0', () {
        final result = ObservationGrouper.groupByEffortKind('timed', [
          _obs(metricId: 'metric-duration'),
          _obs(metricId: 'metric-distance'),
        ]);
        expect(result[0]['duration'], 0);
        expect(result[0]['distance'], 0.0);
      });
    });

    // ── round grouping (legacy) ──────────────────────────────────────────
    group('round grouping (legacy)', () {
      test('groups rounds+round-duration pair', () {
        final result = ObservationGrouper.groupByEffortKind('round', [
          _obs(metricId: 'metric-rounds', valueInt: 3),
          _obs(metricId: 'metric-round-duration', valueInt: 120),
        ]);
        expect(result, hasLength(1));
        expect(result[0]['rounds'], 3);
        expect(result[0]['round-duration'], 120);
      });

      test('null rounds defaults to 1, null duration defaults to 180', () {
        final result = ObservationGrouper.groupByEffortKind('round', [
          _obs(metricId: 'metric-rounds'),
          _obs(metricId: 'metric-round-duration'),
        ]);
        expect(result[0]['rounds'], 1);
        expect(result[0]['round-duration'], 180);
      });

      test('handles reversed order (round-duration first)', () {
        final result = ObservationGrouper.groupByEffortKind('round', [
          _obs(metricId: 'metric-round-duration', valueInt: 90),
          _obs(metricId: 'metric-rounds', valueInt: 5),
        ]);
        expect(result[0]['rounds'], 5);
        expect(result[0]['round-duration'], 90);
      });
    });

    // ── drill grouping ───────────────────────────────────────────────────
    group('drill grouping', () {
      test('groups duration+extra-weight pair', () {
        final result = ObservationGrouper.groupByEffortKind('drill', [
          _obs(metricId: 'metric-duration', valueInt: 60),
          _obs(metricId: 'metric-extra-weight', valueReal: 10.0),
        ]);
        expect(result, hasLength(1));
        expect(result[0]['duration'], 60);
        expect(result[0]['extra-weight'], 10.0);
      });

      test('handles reversed order', () {
        final result = ObservationGrouper.groupByEffortKind('drill', [
          _obs(metricId: 'metric-extra-weight', valueReal: 5.0),
          _obs(metricId: 'metric-duration', valueInt: 45),
        ]);
        expect(result[0]['duration'], 45);
        expect(result[0]['extra-weight'], 5.0);
      });
    });

    // ── fallback ─────────────────────────────────────────────────────────
    test('unknown effortKind falls back to set grouping', () {
      final result = ObservationGrouper.groupByEffortKind('unknown_kind', [
        _obs(metricId: 'metric-reps', valueInt: 12),
        _obs(metricId: 'metric-weight', valueReal: 30.0),
      ]);
      expect(result, hasLength(1));
      expect(result[0]['reps'], 12);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OmniDateUtils
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniDateUtils', () {
    test('startOfDayMs returns midnight epoch ms', () {
      final date = DateTime(2025, 6, 15, 14, 30);
      final ms = OmniDateUtils.startOfDayMs(date);
      final midnight = DateTime(2025, 6, 15).millisecondsSinceEpoch;
      expect(ms, midnight);
    });

    test('endOfDayMs returns 23:59:59.999 epoch ms', () {
      final date = DateTime(2025, 6, 15, 8);
      final ms = OmniDateUtils.endOfDayMs(date);
      final endOfDay =
          DateTime(2025, 6, 15, 23, 59, 59, 999).millisecondsSinceEpoch;
      expect(ms, endOfDay);
    });

    test('isPastDay returns true for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(OmniDateUtils.isPastDay(yesterday), true);
    });

    test('isPastDay returns false for today', () {
      expect(OmniDateUtils.isPastDay(DateTime.now()), false);
    });

    test('isPastDay returns false for tomorrow', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(OmniDateUtils.isPastDay(tomorrow), false);
    });

    test('isToday returns true for now', () {
      expect(OmniDateUtils.isToday(DateTime.now()), true);
    });

    test('isToday returns false for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(OmniDateUtils.isToday(yesterday), false);
    });

    test('isTodayOrFuture is inverse of isPastDay', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(OmniDateUtils.isTodayOrFuture(yesterday), false);
      expect(OmniDateUtils.isTodayOrFuture(DateTime.now()), true);
      expect(OmniDateUtils.isTodayOrFuture(tomorrow), true);
    });

    test('fromMs converts epoch-ms to local DateTime', () {
      final dt = DateTime(2025, 3, 15, 10, 30);
      final ms = dt.millisecondsSinceEpoch;
      final result = OmniDateUtils.fromMs(ms);
      expect(result.year, 2025);
      expect(result.month, 3);
      expect(result.day, 15);
      expect(result.isUtc, false);
    });

    group('buildMonthGrid', () {
      test('always produces a multiple of 7 cells', () {
        for (int month = 1; month <= 12; month++) {
          final grid = OmniDateUtils.buildMonthGrid(2025, month);
          expect(grid.length % 7, 0,
              reason: 'Month $month grid length ${grid.length} not multiple of 7');
        }
      });

      test('starts with correct leading nulls for a Monday-anchored week', () {
        // January 2025 starts on Wednesday → 2 leading nulls
        final grid = OmniDateUtils.buildMonthGrid(2025, 1);
        expect(grid[0], isNull); // Mon placeholder
        expect(grid[1], isNull); // Tue placeholder
        expect(grid[2], isNotNull); // Wed = Jan 1
        expect(grid[2]!.day, 1);
      });

      test('month starting on Monday has no leading nulls', () {
        // September 2025 starts on Monday
        final grid = OmniDateUtils.buildMonthGrid(2025, 9);
        expect(grid[0], isNotNull);
        expect(grid[0]!.day, 1);
      });

      test('contains 28/29/30/31 non-null days correctly', () {
        // Feb 2025 = 28 days
        final feb = OmniDateUtils.buildMonthGrid(2025, 2);
        final febDays = feb.where((d) => d != null).length;
        expect(febDays, 28);

        // Feb 2024 = leap year = 29 days
        final febLeap = OmniDateUtils.buildMonthGrid(2024, 2);
        final febLeapDays = febLeap.where((d) => d != null).length;
        expect(febLeapDays, 29);

        // April 2025 = 30 days
        final apr = OmniDateUtils.buildMonthGrid(2025, 4);
        final aprDays = apr.where((d) => d != null).length;
        expect(aprDays, 30);

        // January 2025 = 31 days
        final jan = OmniDateUtils.buildMonthGrid(2025, 1);
        final janDays = jan.where((d) => d != null).length;
        expect(janDays, 31);
      });

      test('trailing cells are null', () {
        // Jan 2025: 31 days, starts Wed. 2 leading + 31 = 33, ceil(33/7)*7 = 35
        final grid = OmniDateUtils.buildMonthGrid(2025, 1);
        expect(grid.last, isNull); // trailing null
        expect(grid[grid.length - 2], isNull); // also trailing
      });
    });

    group('month names', () {
      test('shortMonthName returns 3-letter abbreviation', () {
        expect(OmniDateUtils.shortMonthName(1), 'Jan');
        expect(OmniDateUtils.shortMonthName(6), 'Jun');
        expect(OmniDateUtils.shortMonthName(12), 'Dec');
      });

      test('fullMonthName returns full name', () {
        expect(OmniDateUtils.fullMonthName(1), 'January');
        expect(OmniDateUtils.fullMonthName(7), 'July');
        expect(OmniDateUtils.fullMonthName(12), 'December');
      });

      test('shortMonthName clamps out-of-range to valid names', () {
        expect(OmniDateUtils.shortMonthName(0), 'Jan'); // clamp to 0 index
        expect(OmniDateUtils.shortMonthName(13), 'Dec'); // clamp to 11 index
      });
    });

    test('formatShort returns "Mon DD" format', () {
      expect(OmniDateUtils.formatShort(DateTime(2025, 3, 8)), 'Mar 08');
      expect(OmniDateUtils.formatShort(DateTime(2025, 12, 25)), 'Dec 25');
      expect(OmniDateUtils.formatShort(DateTime(2025, 1, 1)), 'Jan 01');
    });

    group('formatRange', () {
      test('same-year range omits year from start', () {
        final start = DateTime(2025, 3, 1).millisecondsSinceEpoch;
        final end = DateTime(2025, 6, 15).millisecondsSinceEpoch;
        expect(
          OmniDateUtils.formatRange(start, end),
          'Mar 1 – Jun 15, 2025',
        );
      });

      test('cross-year range includes year on start', () {
        final start = DateTime(2024, 11, 15).millisecondsSinceEpoch;
        final end = DateTime(2025, 2, 28).millisecondsSinceEpoch;
        expect(
          OmniDateUtils.formatRange(start, end),
          'Nov 15, 2024 – Feb 28, 2025',
        );
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ModalityConfig
  // ══════════════════════════════════════════════════════════════════════════

  group('ModalityConfig', () {
    test('configs map has 6 entries (5 modalities + null)', () {
      expect(ModalityConfig.configs.length, 6);
      expect(ModalityConfig.configs.containsKey(null), true);
    });

    group('forModality', () {
      test('returns config for known modality', () {
        final config = ModalityConfig.forModality('resistance_lifting');
        expect(config, isNotNull);
        expect(config!.effortKind, 'set');
      });

      test('returns config for null (Free Training)', () {
        final config = ModalityConfig.forModality(null);
        expect(config, isNotNull);
        expect(config!.primaryMetric, isNull);
        expect(config.structure, 'chooser');
      });

      test('returns null for unknown modality', () {
        expect(ModalityConfig.forModality('nonexistent'), isNull);
      });
    });

    group('getRequiredMetrics', () {
      test('returns primary + secondary for normal modality', () {
        final config = ModalityConfig.forModality('cardio_endurance')!;
        final required = config.getRequiredMetrics();
        expect(required, ['time', 'distance', 'rounds']);
      });

      test('returns empty for Free Training (null primary)', () {
        final config = ModalityConfig.forModality(null)!;
        expect(config.getRequiredMetrics(), isEmpty);
      });
    });

    group('getAllMetrics', () {
      test('returns primary + secondary + optional', () {
        final config = ModalityConfig.forModality('resistance_lifting')!;
        final all = config.getAllMetrics();
        expect(all, ['reps', 'sets', 'load']);
      });

      test('returns empty for Free Training', () {
        final config = ModalityConfig.forModality(null)!;
        expect(config.getAllMetrics(), isEmpty);
      });
    });

    group('effortKindFromMetric', () {
      test('time → timed', () {
        expect(ModalityConfig.effortKindFromMetric('time'), 'timed');
      });

      test('hold → drill', () {
        expect(ModalityConfig.effortKindFromMetric('hold'), 'drill');
      });

      test('reps → set', () {
        expect(ModalityConfig.effortKindFromMetric('reps'), 'set');
      });

      test('sets → set', () {
        expect(ModalityConfig.effortKindFromMetric('sets'), 'set');
      });

      test('load → set', () {
        expect(ModalityConfig.effortKindFromMetric('load'), 'set');
      });

      test('rounds → round', () {
        expect(ModalityConfig.effortKindFromMetric('rounds'), 'round');
      });

      test('distance → timed', () {
        expect(ModalityConfig.effortKindFromMetric('distance'), 'timed');
      });

      test('unknown metric falls back to set', () {
        expect(ModalityConfig.effortKindFromMetric('unknown'), 'set');
      });
    });

    group('getRoundsLabel', () {
      test('sports → Periods', () {
        expect(ModalityConfig.getRoundsLabel('sports'), 'Periods');
      });

      test('martial_arts → Rounds', () {
        expect(ModalityConfig.getRoundsLabel('martial_arts'), 'Rounds');
      });

      test('cardio_endurance → Intervals', () {
        expect(ModalityConfig.getRoundsLabel('cardio_endurance'), 'Intervals');
      });

      test('null (Free Training) → Rounds', () {
        expect(ModalityConfig.getRoundsLabel(null), 'Rounds');
      });

      test('unknown modality → Rounds', () {
        expect(ModalityConfig.getRoundsLabel('unknown'), 'Rounds');
      });
    });

    group('calculateRelevanceScore', () {
      test('perfect match: same category + all primary caps → high score', () {
        final config = ModalityConfig.forModality('resistance_lifting')!;
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['reps', 'sets', 'load'],
          exerciseCategoryId: 'category-resistance',
        );
        // 40 (category) + 30 (3/3 primary) + 0 (no secondary match) = 70
        expect(score, 70.0);
      });

      test('category match only → 40 minus no-overlap penalty', () {
        // Category matches but zero primary caps match
        // Wait — if category matches, no-overlap penalty doesn't apply
        final config = ModalityConfig.forModality('resistance_lifting')!;
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['unknown'],
          exerciseCategoryId: 'category-resistance',
        );
        // 40 (category) + 0 (primary) + 0 (secondary) + 0 (isometric) + 0 (anti) + 0 (no-overlap: cat matches)
        expect(score, 40.0);
      });

      test('no category match + no primary overlap → low score with penalty', () {
        final config = ModalityConfig.forModality('resistance_lifting')!;
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['unknown'],
          exerciseCategoryId: 'different-category',
        );
        // 0 + 0 + 0 + 0 + 0 - 10 (no-overlap) = -10, clamped to 0
        expect(score, 0.0);
      });

      test('anti-capability penalty reduces score', () {
        final config = ModalityConfig.forModality('resistance_lifting')!;
        // resistance has anti: distance, rounds, hold (3 items)
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['reps', 'sets', 'load', 'distance', 'rounds'],
          exerciseCategoryId: 'category-resistance',
        );
        // 40 (category) + 30 (3/3 primary) + 0 (secondary) - (2/3)*20 anti
        // = 70 - 13.33 = 56.67
        expect(score, closeTo(56.67, 0.1));
      });

      test('isometric bonus for hold+time exercise in isometric modality', () {
        final config = ModalityConfig.forModality('isometric_stretching')!;
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['hold', 'time'],
          exerciseCategoryId: 'category-isometric',
        );
        // 40 (category) + 30 (2/2 primary: hold + time) + 0 (secondary) + 15 (isometric bonus) = 85
        expect(score, 85.0);
      });

      test('isometric bonus does NOT apply to non-isometric modality', () {
        final config = ModalityConfig.forModality('cardio_endurance')!;
        // Cardio primary caps: time, distance — does NOT contain 'hold'
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['hold', 'time'],
          exerciseCategoryId: 'category-cardio',
        );
        // 40 (category) + 15 (1/2 primary: time matches) + 0 - (1/2)*20 anti (hold is anti)
        // = 40 + 15 - 10 = 45
        expect(score, 45.0);
      });

      test('secondary capability bonus', () {
        final config = ModalityConfig.forModality('cardio_endurance')!;
        // cardio secondary: ['rounds']
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['time', 'distance', 'rounds'],
          exerciseCategoryId: 'category-cardio',
        );
        // 40 + 30 (2/2 primary) + 10 (1/1 secondary) = 80
        expect(score, 80.0);
      });

      test('score is clamped to 0 minimum', () {
        final config = ModalityConfig.forModality('martial_arts')!;
        // martial_arts anti: load, hold, distance (3 items)
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['load', 'hold', 'distance'],
          exerciseCategoryId: 'other-category',
        );
        // 0 + 0 + 0 - 20 (3/3 anti) - 10 (no-overlap) = -30, clamped to 0
        expect(score, 0.0);
      });

      test('score is clamped to 100 maximum', () {
        // Even if somehow all bonuses stacked, can't exceed 100
        // max theoretical: 40 + 30 + 10 + 15 = 95 (under 100 anyway)
        final config = ModalityConfig.forModality('isometric_stretching')!;
        final score = config.calculateRelevanceScore(
          exerciseCapabilities: ['hold', 'time', 'sets'],
          exerciseCategoryId: 'category-isometric',
        );
        // 40 + 30 + 10 + 15 = 95
        expect(score, 95.0);
        expect(score, lessThanOrEqualTo(100.0));
      });
    });

    group('isRecommended', () {
      test('true when score >= 50', () {
        final config = ModalityConfig.forModality('resistance_lifting')!;
        expect(
          config.isRecommended(
            exerciseCapabilities: ['reps', 'sets', 'load'],
            exerciseCategoryId: 'category-resistance',
          ),
          true,
        );
      });

      test('false when score < 50', () {
        final config = ModalityConfig.forModality('resistance_lifting')!;
        expect(
          config.isRecommended(
            exerciseCapabilities: ['time'],
            exerciseCategoryId: 'other',
          ),
          false,
        );
      });

      test('threshold constant is 50.0', () {
        expect(RECOMMENDED_SCORE_THRESHOLD, 50.0);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ExerciseCapabilities extension
  // ══════════════════════════════════════════════════════════════════════════

  group('ExerciseCapabilities extension', () {
    test('supports returns true when capability exists', () {
      final ex = _exercise(capabilities: ['reps', 'load', 'time']);
      expect(ex.supports('reps'), true);
      expect(ex.supports('load'), true);
    });

    test('supports returns false when capability missing', () {
      final ex = _exercise(capabilities: ['reps']);
      expect(ex.supports('hold'), false);
    });

    test('supportsAny returns true if any capability matches', () {
      final ex = _exercise(capabilities: ['reps', 'load']);
      expect(ex.supportsAny(['hold', 'load']), true);
    });

    test('supportsAny returns false if no capabilities match', () {
      final ex = _exercise(capabilities: ['reps']);
      expect(ex.supportsAny(['hold', 'distance']), false);
    });

    group('copyWith', () {
      test('preserves all fields when no overrides given', () {
        final original = _exercise(capabilities: ['reps', 'load']);
        final copy = original.copyWith();
        expect(copy.id, original.id);
        expect(copy.name, original.name);
        expect(copy.capabilities, original.capabilities);
        expect(copy.isArchived, original.isArchived);
      });

      test('overrides provided fields', () {
        final original = _exercise();
        final copy = original.copyWith(
          name: 'New Name',
          isArchived: true,
          relevanceScore: 75.0,
        );
        expect(copy.name, 'New Name');
        expect(copy.isArchived, true);
        expect(copy.relevanceScore, 75.0);
        expect(copy.id, original.id); // unchanged
      });

      test('sentinel allows setting howToSteps to null', () {
        final original = Exercise(
          id: 'ex-1',
          ownerUserId: 'u-1',
          disciplineId: 'd-1',
          name: 'Test',
          description: '',
          movementPattern: 'push',
          isArchived: false,
          createdAtMs: 0,
          updatedAtMs: 0,
          capabilities: [],
          howToSteps: ['Step 1', 'Step 2'],
        );
        final copy = original.copyWith(howToSteps: null);
        expect(copy.howToSteps, isNull);
      });

      test('sentinel preserves howToSteps when not provided', () {
        final original = Exercise(
          id: 'ex-1',
          ownerUserId: 'u-1',
          disciplineId: 'd-1',
          name: 'Test',
          description: '',
          movementPattern: 'push',
          isArchived: false,
          createdAtMs: 0,
          updatedAtMs: 0,
          capabilities: [],
          howToSteps: ['Step 1'],
        );
        final copy = original.copyWith(name: 'Other');
        expect(copy.howToSteps, ['Step 1']);
      });

      test('sentinel allows setting imageAssetPath to null', () {
        final original = Exercise(
          id: 'ex-1',
          ownerUserId: 'u-1',
          disciplineId: 'd-1',
          name: 'Test',
          description: '',
          movementPattern: 'push',
          isArchived: false,
          createdAtMs: 0,
          updatedAtMs: 0,
          capabilities: [],
          imageAssetPath: 'path/to/image.png',
        );
        final copy = original.copyWith(imageAssetPath: null);
        expect(copy.imageAssetPath, isNull);
      });

      test('updates capabilities list', () {
        final original = _exercise(capabilities: ['reps']);
        final copy = original.copyWith(capabilities: ['reps', 'load', 'time']);
        expect(copy.capabilities, ['reps', 'load', 'time']);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // EffortDefaults
  // ══════════════════════════════════════════════════════════════════════════

  group('EffortDefaults', () {
    test('timed defaults include duration, distance, and extraWeight', () {
      final defaults = EffortDefaults.getDefaultTargets('timed');
      expect(defaults[MetricIds.duration], 0);
      expect(defaults[MetricIds.distance], 0.0);
      expect(defaults[MetricIds.extraWeight], 0.0);
    });

    test('drill defaults include extraWeight and duration but not distance', () {
      final defaults = EffortDefaults.getDefaultTargets('drill');
      expect(defaults.containsKey(MetricIds.extraWeight), true);
      expect(defaults.containsKey(MetricIds.distance), false);
    });

    test('set defaults do not include extraWeight', () {
      final defaults = EffortDefaults.getDefaultTargets('set');
      expect(defaults.containsKey(MetricIds.extraWeight), false);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OmniDateUtils.formatDurationHoursMins
  // ══════════════════════════════════════════════════════════════════════════

  group('OmniDateUtils.formatDurationHoursMins', () {
    test('zero ms returns "0m"', () {
      expect(OmniDateUtils.formatDurationHoursMins(0), '0m');
    });

    test('sub-minute ms rounds to "0m"', () {
      expect(OmniDateUtils.formatDurationHoursMins(29000), '0m');
    });

    test('exactly 1 minute returns "1m"', () {
      expect(OmniDateUtils.formatDurationHoursMins(60000), '1m');
    });

    test('59 minutes returns "59m"', () {
      expect(OmniDateUtils.formatDurationHoursMins(59 * 60000), '59m');
    });

    test('exactly 1 hour returns "1h 0m"', () {
      expect(OmniDateUtils.formatDurationHoursMins(3600000), '1h 0m');
    });

    test('1 hour 30 minutes returns "1h 30m"', () {
      expect(OmniDateUtils.formatDurationHoursMins(5400000), '1h 30m');
    });

    test('large duration returns correct hours and minutes', () {
      // 2h 45m = 9900 seconds = 9_900_000 ms
      expect(OmniDateUtils.formatDurationHoursMins(9900000), '2h 45m');
    });

    test('rounds to nearest minute (29 seconds -> rounds down)', () {
      // 1 min 29 sec -> rounds to 1 min
      expect(OmniDateUtils.formatDurationHoursMins(89000), '1m');
    });

    test('rounds to nearest minute (30 seconds -> rounds up)', () {
      // 1 min 30 sec -> rounds to 2 min
      expect(OmniDateUtils.formatDurationHoursMins(90000), '2m');
    });
  });
}
