// Plan 157c P1 — unrated weeks leave the Sustained High Load baseline.
//
// Scenarios S-15901…S-15906 of
// `docs/plans/2026-11-14-157c-stats-unrated-weeks-plan/2026-11-14-157c-stats-unrated-weeks-plan.md`:
// a week that held sessions but no rated one is an UNRATED week — its load is
// unknown, not zero — so it is left out of the baseline divisor and is not an
// easier week. A week with no session at all still counts as zero (D-1705).
//
// S-15901…S-15905 are plain Dart over the pure rule; S-15906 runs
// `StatsProgressService.weeklyLoads` over both repository harnesses.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/sustained_high_load.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// Week `i` starts `DateTime(2026, 1, 5 + 7 * i)`; Jan 5 2026 is a Monday.
WeeklyLoad _week(
  int i,
  double load, {
  bool rated = false,
  bool sessions = false,
}) => WeeklyLoad(
  weekStart: DateTime(2026, 1, 5 + 7 * i),
  loadMinutes: load,
  hasRatedSession: rated,
  hasSessions: sessions,
);

/// The plan's `now`: a fixed anchor, so every fixture week is a calendar week
/// and nothing moves with the real clock.
final DateTime _now = DateTime(2026, 5, 13, 10);

/// The local-midnight start of the week [weeksAgo] weeks before `now`'s week.
DateTime _weekStart(int weeksAgo) {
  final current = OmniDateUtils.startOfWeek(_now, startOfWeek: 'monday');
  return DateTime(current.year, current.month, current.day - 7 * weeksAgo);
}

/// `hour` o'clock on the first day of the week [weeksAgo] weeks back.
DateTime _atWeek(int weeksAgo, int hour) {
  final start = _weekStart(weeksAgo);
  return DateTime(start.year, start.month, start.day, hour);
}

/// One session of [minutes], rated [rating], starting at [start].
///
/// With no efforts the whole duration is Resistance time, so the shared split's
/// load is exactly `minutes × rating` — a null rating has load 0.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required int minutes,
  required int? rating,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: startMs + minutes * 60000,
      sessionFeeling: rating,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
}

void main() {
  test(
    'S-15901 unrated weeks are left out of the baseline divisor',
    () {
      final weeks = [
        for (var i = 0; i < 8; i++) _week(i, 100, rated: true, sessions: true),
        _week(8, 0, sessions: true),
        _week(9, 0, sessions: true),
        _week(10, 0),
        _week(11, 0),
        _week(12, 100, rated: true, sessions: true),
      ];

      final baseline = sustainedHighLoadBaseline(weeks: weeks, beforeIndex: 12);

      expect(baseline!.usualLoadMinutes, closeTo(80.0, 1e-9));
      expect(baseline.ratedWeeks, 8);
    },
  );

  test(
    'S-15902 an empty week still counts as zero in the baseline',
    () {
      final weeks = [
        for (var i = 0; i < 10; i++) _week(i, 100, rated: true, sessions: true),
        _week(10, 0),
        _week(11, 0),
      ];

      final baseline = sustainedHighLoadBaseline(weeks: weeks, beforeIndex: 12);

      expect(baseline!.usualLoadMinutes, closeTo(1000 / 12, 1e-9));
    },
  );

  test(
    'S-15902b a window of twelve unrated weeks has no usual and no rated week',
    () {
      final weeks = [for (var i = 0; i < 13; i++) _week(i, 0, sessions: true)];

      final baseline = sustainedHighLoadBaseline(weeks: weeks, beforeIndex: 12);

      expect(baseline!.usualLoadMinutes, 0.0);
      expect(baseline.usualLoadMinutes.isNaN, isFalse);
      expect(baseline.ratedWeeks, 0);
    },
  );

  test(
    'S-15903 starting to rate late no longer fires the card',
    () {
      final weeks = [
        _week(0, 0, sessions: true),
        _week(1, 0, sessions: true),
        _week(2, 0, sessions: true),
        _week(3, 0, sessions: true),
        for (var i = 4; i < 17; i++)
          _week(i, 100, rated: true, sessions: true),
      ];

      expect(sustainedHighLoad(weeks: weeks, mixShowsLoad: true), isNull);
    },
  );

  test(
    'S-15904 an unrated week is not an easier week',
    () {
      final weeks = [
        for (var i = 0; i < 20; i++)
          i == 2 || i == 5 || i == 8
              ? _week(i, 0, sessions: true)
              : _week(i, 100, rated: true, sessions: true),
      ];

      expect(
        sustainedHighLoadEasierGapWeeks(
          weeks: weeks,
          beforeIndex: 12,
          usual: 100,
        ),
        isNull,
      );
    },
  );

  test(
    'S-15905 an unrated week breaks a higher-load run',
    () {
      final weeks = [
        for (var i = 0; i < 12; i++) _week(i, 100, rated: true, sessions: true),
        _week(12, 200, rated: true, sessions: true),
        _week(13, 200, rated: true, sessions: true),
        _week(14, 0, sessions: true),
        _week(15, 200, rated: true, sessions: true),
        _week(16, 200, rated: true, sessions: true),
      ];

      expect(sustainedHighLoadStreak(weeks: weeks).weekCount, lessThanOrEqualTo(2));
      expect(sustainedHighLoad(weeks: weeks, mixShowsLoad: true), isNull);
    },
  );

  for (final factory in harnessFactories) {
    final harness = factory();

    test('S-15906 ${harness.name}: weeklyLoads marks which weeks held sessions',
        () async {
      final repo = await harness.open();
      await _seedSession(
        repo,
        id: 'rated-3w',
        start: _atWeek(3, 9),
        minutes: 30,
        rating: 4,
      );
      await _seedSession(
        repo,
        id: 'unrated-2w',
        start: _atWeek(2, 9),
        minutes: 30,
        rating: null,
      );

      final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);
      await harness.close();

      final rated = weeks.singleWhere(
        (week) => week.weekStart == _weekStart(3),
      );
      expect(rated.hasSessions, isTrue);
      expect(rated.hasRatedSession, isTrue);
      expect(rated.isUnrated, isFalse);

      final unrated = weeks.singleWhere(
        (week) => week.weekStart == _weekStart(2),
      );
      expect(unrated.hasSessions, isTrue);
      expect(unrated.hasRatedSession, isFalse);
      expect(unrated.isUnrated, isTrue);

      final empty = weeks.singleWhere(
        (week) => week.weekStart == _weekStart(1),
      );
      expect(empty.hasSessions, isFalse);
      expect(empty.hasRatedSession, isFalse);
      expect(empty.isUnrated, isFalse);
    });
  }
}
