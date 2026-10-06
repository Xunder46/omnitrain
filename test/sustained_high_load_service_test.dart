// Stats PR 9a Phase 2 — `StatsProgressService.weeklyLoads` and
// `StatsProgressService.startOfWeekSetting`, over both repository harnesses.
//
// The service read is the rule's only history walker: each completed session is
// bucketed by the week of its own start, its load is the shared session split's
// load (never a second formula), and the week containing `now` is never
// returned (D-1702, D-1703, D-1714). The weeks are the user's calendar weeks,
// so the saved start-of-week setting moves their boundaries (D-1704).
//
// Plan: `docs/plans/2026-10-04-09a-stats-pr9a-sustained-high-load-plan/2026-10-04-09a-stats-pr9a-sustained-high-load-plan.md`
// (D-1702…D-1704, D-1714; S-2401, S-2411, S-2413, S-2414).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/sustained_high_load.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

// ─── The plan's clock and weeks ─────────────────────────────────────────────

/// The plan's `now`: a fixed anchor, so every fixture week is a calendar week
/// and nothing moves with the real clock.
final DateTime _now = DateTime(2026, 5, 13, 10);

/// The local-midnight start of the week [weeksAgo] weeks before `now`'s week,
/// for the given start-of-week setting.
DateTime _weekStart(int weeksAgo, {String startOfWeek = 'monday'}) {
  final current = OmniDateUtils.startOfWeek(_now, startOfWeek: startOfWeek);
  return DateTime(current.year, current.month, current.day - 7 * weeksAgo);
}

/// `hour` o'clock on the first day of the week [weeksAgo] weeks back.
DateTime _atWeek(int weeksAgo, int hour) {
  final start = _weekStart(weeksAgo);
  return DateTime(start.year, start.month, start.day, hour);
}

// ─── Sessions ───────────────────────────────────────────────────────────────

/// One session of [minutes], rated [rating], starting at [start].
///
/// The shared `seedSession` cannot express a rating or an incomplete session.
/// With no efforts the whole duration is Resistance time, so the shared split's
/// load is exactly `minutes × rating` — the figure the plan's fixtures state.
/// An [incomplete] session has no end and is skipped by every read.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required int minutes,
  required int? rating,
  bool incomplete = false,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: incomplete ? null : startMs + minutes * 60000,
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

/// F-9A: S-2401's seventeen completed weeks, oldest first — ten weeks at
/// `L = 240` (60 min × 4), two adjacent empty weeks, then five weeks at
/// `L = 230` (46 min × 5) — plus a current, incomplete week whose rated session
/// alone would be `L = 300`. [currentWeekRating] null leaves the current week
/// with no session at all.
Future<void> _seedF9A(
  WorkoutRepository repo, {
  int? currentWeekRating = 5,
}) async {
  for (var k = 1; k <= 17; k++) {
    final weeksAgo = 18 - k;
    if (k <= 10) {
      await _seedSession(
        repo,
        id: 'w$k',
        start: _atWeek(weeksAgo, 9),
        minutes: 60,
        rating: 4,
      );
    } else if (k >= 13) {
      await _seedSession(
        repo,
        id: 'w$k',
        start: _atWeek(weeksAgo, 9),
        minutes: 46,
        rating: 5,
      );
    }
  }
  if (currentWeekRating != null) {
    await _seedSession(
      repo,
      id: 'current',
      start: _atWeek(0, 9),
      minutes: 60,
      rating: currentWeekRating,
      incomplete: true,
    );
  }
}

/// S-2401's seventeen completed weeks as the service must return them: the
/// load of the week `i` (0-based, oldest first) and its rated flag.
void _expectF9AWeeks(List<WeeklyLoad> weeks) {
  expect(weeks, hasLength(17));
  for (var i = 0; i < weeks.length; i++) {
    expect(weeks[i].weekStart, _weekStart(17 - i), reason: 'week ${i + 1}');
    final expectedLoad = i < 10
        ? 240.0
        : i < 12
        ? 0.0
        : 230.0;
    expect(weeks[i].loadMinutes, expectedLoad, reason: 'week ${i + 1}');
    expect(
      weeks[i].hasRatedSession,
      i < 10 || i >= 12,
      reason: 'week ${i + 1}',
    );
  }
}

/// A week list as `start|load|rated` rows, so two stores' lists compare whole.
List<String> _describe(List<WeeklyLoad> weeks) => [
  for (final week in weeks)
    '${week.weekStart.millisecondsSinceEpoch}|${week.loadMinutes}|'
        '${week.hasRatedSession}',
];

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — weeklyLoads', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('D-1703 no completed session yields an empty list', () async {
        expect(
          await StatsProgressService(repo).weeklyLoads(now: _now),
          isEmpty,
        );
      });

      test('D-1702 an empty week between sessions is present', () async {
        await _seedSession(
          repo,
          id: 'w3',
          start: _atWeek(3, 9),
          minutes: 60,
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 'w1',
          start: _atWeek(1, 9),
          minutes: 46,
          rating: 5,
        );

        final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);

        expect(_describe(weeks), [
          '${_weekStart(3).millisecondsSinceEpoch}|240.0|true',
          '${_weekStart(2).millisecondsSinceEpoch}|0.0|false',
          '${_weekStart(1).millisecondsSinceEpoch}|230.0|true',
        ]);
      });

      test(
        'S-2401 the service returns the seventeen completed weeks',
        () async {
          await _seedF9A(repo);

          final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);

          _expectF9AWeeks(weeks);
          // The last element is the week before `now`'s week.
          expect(weeks.last.weekStart, _weekStart(1));
        },
      );

      test(
        'S-2401 the service\'s weeks feed the rule the pack\'s figures',
        () async {
          await _seedF9A(repo);

          final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);
          final streak = sustainedHighLoadStreak(weeks: weeks);

          expect(streak.weekCount, 5);
          expect(streak.usualLoadMinutes, 200.0);
          expect(streak.firstWeekStart, _weekStart(5));
          expect(streak.ratedBaselineWeeks, 10);

          final result = sustainedHighLoad(weeks: weeks, mixShowsLoad: true);
          expect(result, isNotNull);
          expect(result!.streakWeeks, 5);
          expect(result.easierGapWeeks, isNull);
          expect(
            sustainedHighLoadCopy(result).observation,
            "You've had 5 consecutive weeks above your usual training load, with "
            'no easier week.',
          );
        },
      );

      test('S-2411 the incomplete current week is never counted', () async {
        await _seedF9A(repo);

        final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);

        _expectF9AWeeks(weeks);
        expect(weeks.last.weekStart, _weekStart(1));
        expect(sustainedHighLoadStreak(weeks: weeks).weekCount, 5);
      });

      test('S-2411 the current week holding nothing changes nothing', () async {
        await _seedF9A(repo, currentWeekRating: null);

        final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);

        _expectF9AWeeks(weeks);
        expect(sustainedHighLoadStreak(weeks: weeks).weekCount, 5);
      });

      test('S-2413 the saved start-of-week moves the boundaries', () async {
        // The Sunday and the Monday either side of the boundary between the
        // week before `now`'s week and that week itself, on a Monday calendar.
        await _seedSession(
          repo,
          id: 'sunday',
          start: DateTime(2026, 5, 3, 9),
          minutes: 30,
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 'monday',
          start: DateTime(2026, 5, 4, 9),
          minutes: 40,
          rating: 5,
        );

        final service = StatsProgressService(repo);

        await repo.setPreferenceString('preferred_start_of_week', 'monday');
        expect(await service.startOfWeekSetting(), 'monday');
        final monday = await service.weeklyLoads(now: _now);
        expect(_describe(monday), [
          '${_weekStart(2).millisecondsSinceEpoch}|120.0|true',
          '${_weekStart(1).millisecondsSinceEpoch}|200.0|true',
        ]);

        await repo.setPreferenceString('preferred_start_of_week', 'sunday');
        expect(await service.startOfWeekSetting(), 'sunday');
        final sunday = await service.weeklyLoads(now: _now);
        expect(_describe(sunday), [
          '${_weekStart(1, startOfWeek: 'sunday').millisecondsSinceEpoch}'
              '|320.0|true',
        ]);

        // `'sun'` normalizes to Sunday, so it agrees with `'sunday'`.
        await repo.setPreferenceString('preferred_start_of_week', 'sun');
        expect(await service.startOfWeekSetting(), 'sunday');
        expect(
          _describe(await service.weeklyLoads(now: _now)),
          _describe(sunday),
        );

        // The Sunday session's week moved; the two settings disagree.
        expect(monday.first.weekStart, isNot(sunday.first.weekStart));
      });

      test('S-2413 SettingsState writes the value the service reads', () async {
        final settings = SettingsState(repo, fakePreferencesService());
        final service = StatsProgressService(repo);

        await settings.setStartOfWeek('sunday');
        expect(settings.startOfWeek, 'sunday');
        expect(await service.startOfWeekSetting(), 'sunday');

        await settings.setStartOfWeek('Monday');
        expect(settings.startOfWeek, 'monday');
        expect(await service.startOfWeekSetting(), 'monday');
      });
    });
  }

  test('S-2414 Hive and Mock return identical week lists', () async {
    Future<List<String>> read(RepositoryHarness harness) async {
      final repo = await harness.open();
      await _seedF9A(repo);
      final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);
      final result = sustainedHighLoad(weeks: weeks, mixShowsLoad: true);
      await harness.close();
      return [
        ..._describe(weeks),
        'card|${result?.streakWeeks}|${result?.easierGapWeeks}|'
            '${result == null ? '' : sustainedHighLoadCopy(result).observation}',
      ];
    }

    final mock = await read(MockRepositoryHarness());
    final hive = await read(HiveRepositoryHarness());

    expect(mock, hive);
    expect(mock, hasLength(18));
  });
}
