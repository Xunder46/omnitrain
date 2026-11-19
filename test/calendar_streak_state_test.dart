// The training streak on the days it is read: two sessions on one day, the days
// after a clock change, a lapsed streak, the first of a month, and the best run
// of a past month. The clock is injected, so no case depends on today's date.
//
// The clock-change cases find the days of 2026 whose local length is not 24 h
// (the pattern of test/nutrition_target_dst_walk_test.dart) and are skipped in
// a time zone without DST. To force one, run
// `TZ=America/New_York flutter test test/calendar_streak_state_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// One completed session starting at [at].
Future<void> _session(
  MockWorkoutRepository repo,
  String id,
  DateTime at,
) async {
  final ms = at.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'u-1',
      startedAtMs: ms,
      endedAtMs: ms + 3600000,
      createdAtMs: ms,
      updatedAtMs: ms,
    ),
  );
}

/// A calendar state whose clock stands on [now], already loaded.
Future<CalendarState> _stateAt(MockWorkoutRepository repo, DateTime now) async {
  final state = CalendarState(repo, now: () => now);
  await state.init();
  return state;
}

/// [offset] calendar days from [base] (a local midnight), at [hour].
DateTime _day(DateTime base, int offset, [int hour = 12]) =>
    DateTime(base.year, base.month, base.day + offset, hour);

/// Local midnights of every day of 2026 whose length is not 24 h.
List<DateTime> _clockChangeDays() {
  final found = <DateTime>[];
  for (
    var d = DateTime(2026, 1, 1);
    d.year == 2026;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final next = DateTime(d.year, d.month, d.day + 1);
    if (next.difference(d) != const Duration(hours: 24)) found.add(d);
  }
  return found;
}

void main() {
  final clockChanges = _clockChangeDays();

  group('S-17401 two sessions on one day count as one day', () {
    test('a streak over three sessions on two days is 2', () async {
      final repo = await _freshRepo();
      await _session(repo, 'a', DateTime(2026, 6, 1, 12));
      await _session(repo, 'b1', DateTime(2026, 6, 2, 9));
      await _session(repo, 'b2', DateTime(2026, 6, 2, 18));

      final state = await _stateAt(repo, DateTime(2026, 6, 3, 9));

      expect(state.completedSessionCount, 3);
      expect(state.streakDays, 2);
      expect(state.isActiveStreak, isTrue);
      expect(state.liveStreakDays, 2);
    });
  });

  group('S-17402 the streak across a clock change', () {
    test(
      'local zone has a clock change in 2026',
      () => expect(clockChanges, isNotEmpty),
      skip: clockChanges.isEmpty ? 'time zone without DST' : null,
    );

    for (final change in clockChanges) {
      final label = change.toIso8601String();

      test('$label: a session today, the change day and the day before', () async {
        final repo = await _freshRepo();
        for (var i = -1; i <= 2; i++) {
          await _session(repo, 'd$i', _day(change, i));
        }

        final state = await _stateAt(repo, _day(change, 2, 18));

        expect(state.streakDays, 4);
        expect(state.isActiveStreak, isTrue);
      });

      test('$label: none today, one yesterday', () async {
        final repo = await _freshRepo();
        for (var i = -1; i <= 2; i++) {
          await _session(repo, 'd$i', _day(change, i));
        }

        final state = await _stateAt(repo, _day(change, 3, 9));

        expect(state.streakDays, 4);
        expect(state.isActiveStreak, isTrue);
      });

      test('$label: the day after the change, trained the two days before', () async {
        final repo = await _freshRepo();
        await _session(repo, 'before', _day(change, -1));
        await _session(repo, 'on', _day(change, 0));

        final state = await _stateAt(repo, _day(change, 1, 9));

        expect(state.streakDays, 2);
        expect(state.isActiveStreak, isTrue);
      });
    }
  });

  group('S-17403 to S-17405 a live streak, a lapsed one, none', () {
    test('S-17403 a session yesterday and the day before is a live streak', () async {
      final repo = await _freshRepo();
      await _session(repo, 'a', DateTime(2026, 6, 3, 12));
      await _session(repo, 'b', DateTime(2026, 6, 4, 12));

      final state = await _stateAt(repo, DateTime(2026, 6, 5, 9));

      expect(state.streakDays, 2);
      expect(state.isActiveStreak, isTrue);
      expect(state.liveStreakDays, 2);
    });

    test('S-17404 none today or yesterday: the best run is not a streak', () async {
      final repo = await _freshRepo();
      await _session(repo, 'a', DateTime(2026, 6, 1, 12));
      await _session(repo, 'b', DateTime(2026, 6, 2, 12));

      final state = await _stateAt(repo, DateTime(2026, 6, 5, 9));

      expect(state.streakDays, 2, reason: 'the month\'s best run');
      expect(state.isActiveStreak, isFalse);
      expect(state.liveStreakDays, 0);
    });

    test('S-17405 no sessions at all', () async {
      final repo = await _freshRepo();

      final state = await _stateAt(repo, DateTime(2026, 6, 5, 9));

      expect(state.streakDays, 0);
      expect(state.isActiveStreak, isFalse);
      expect(state.liveStreakDays, 0);
    });
  });

  group('S-17406 a live streak before the first session of the month', () {
    test('trained the last two days of May, now the morning of June 1', () async {
      final repo = await _freshRepo();
      await _session(repo, 'a', DateTime(2026, 5, 30, 12));
      await _session(repo, 'b', DateTime(2026, 5, 31, 12));

      final state = await _stateAt(repo, DateTime(2026, 6, 1, 9));

      expect(state.completedSessionCount, 0, reason: 'June has no session yet');
      expect(state.streakDays, 2);
      expect(state.isActiveStreak, isTrue);
      expect(state.liveStreakDays, 2);
    });
  });

  group('S-17409 the best run of a past month across a clock change', () {
    for (final change in clockChanges) {
      test('${change.toIso8601String()}: three days in a row from the change day', () async {
        final repo = await _freshRepo();
        for (var i = 0; i <= 2; i++) {
          await _session(repo, 'd$i', _day(change, i));
        }

        // The clock stands in the next month; look back at the month with the
        // change.
        final state = await _stateAt(
          repo,
          DateTime(change.year, change.month + 1, 5, 9),
        );
        await state.goToPreviousMonth();

        expect(state.month, change.month);
        expect(state.isActiveStreak, isFalse);
        expect(state.streakDays, 3);
      });
    }
  });
}
