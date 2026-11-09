// The Consistency and Training Gap rules (plan 105), pure: no repository, no
// widget, no clock. Scenarios S-17801 … S-17808 of
// `docs/plans/2026-11-03-105-consistency-plan/`.
//
// `now` is Wednesday 2026-03-18 12:00 local. Monday weeks: W1 = Mar 9-15,
// W2 = Mar 2-8, W3 = Feb 23-Mar 1, W4 = Feb 16-22, W5 = Feb 9-15,
// W6 = Feb 2-8, W7 = Jan 26-Feb 1, W8 = Jan 19-25.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/consistency.dart';

DateTime _d(int month, int day) => DateTime(2026, month, day, 12);

final DateTime _now = DateTime(2026, 3, 18, 12);

/// Fixture A: 20 sessions in W8..W1 (W8 4, W7 2, W6 2, W5 2, W4 2, W3 2, W2 2,
/// W1 4 with a Sunday, Mar 15, in it).
final List<DateTime> _fixtureA = [
  _d(1, 20), _d(1, 21), _d(1, 22), _d(1, 23), // W8
  _d(1, 27), _d(1, 29), // W7
  _d(2, 3), _d(2, 5), // W6
  _d(2, 10), _d(2, 12), // W5
  _d(2, 17), _d(2, 19), // W4
  _d(2, 24), _d(2, 26), // W3
  _d(3, 3), _d(3, 5), // W2
  _d(3, 10), _d(3, 11), _d(3, 13), _d(3, 15), // W1
];

/// W8 4, W7 4, W6 3, W5 3, W4 2, W3 2, W2 2, W1 4: 24 sessions, 4 * 8 = 32 =
/// 24 + 8, exactly one above the average.
final List<DateTime> _fixtureEqual = [
  _d(1, 19), _d(1, 20), _d(1, 21), _d(1, 22), // W8
  _d(1, 26), _d(1, 27), _d(1, 28), _d(1, 29), // W7
  _d(2, 2), _d(2, 4), _d(2, 6), // W6
  _d(2, 9), _d(2, 11), _d(2, 13), // W5
  _d(2, 17), _d(2, 19), // W4
  _d(2, 24), _d(2, 26), // W3
  _d(3, 3), _d(3, 5), // W2
  _d(3, 9), _d(3, 10), _d(3, 12), _d(3, 13), // W1
];

/// One session a week in W8..W2 and two in W1 (below the floor of three).
final List<DateTime> _fixtureLow = [
  _d(1, 20), _d(1, 27), _d(2, 3), _d(2, 10), _d(2, 17), _d(2, 24), _d(3, 3), // W8..W2
  _d(3, 10), _d(3, 12), // W1
];

/// Fixture G: 22 session days, every 2 or 3 days, the last on Mar 12.
final List<DateTime> _fixtureG = [
  _d(1, 19), _d(1, 21), _d(1, 24), _d(1, 26), _d(1, 29), _d(1, 31),
  _d(2, 3), _d(2, 5), _d(2, 8), _d(2, 10), _d(2, 13), _d(2, 15),
  _d(2, 18), _d(2, 20), _d(2, 23), _d(2, 25), _d(2, 28),
  _d(3, 2), _d(3, 5), _d(3, 7), _d(3, 10), _d(3, 12),
];

ConsistencyResult? _consistency(List<DateTime> sessions, String sow) =>
    consistency(sessionStarts: sessions, now: _now, startOfWeek: sow);

TrainingGapResult? _gap(List<DateTime> sessions, DateTime now) =>
    trainingGap(sessionStarts: sessions, now: now, startOfWeek: 'monday');

DateTime _at(int month, int day, int hour, int minute) => DateTime(2026, month, day, hour, minute);

TrainingGapResult? _gapOn(List<DateTime> sessions, String sow) =>
    trainingGap(sessionStarts: sessions, now: _now, startOfWeek: sow);

/// Fixture A without its last week (W1): 16 sessions in W8..W2.
final List<DateTime> _baseM = [
  _d(1, 20), _d(1, 21), _d(1, 22), _d(1, 23), // W8
  _d(1, 27), _d(1, 29), // W7
  _d(2, 3), _d(2, 5), // W6
  _d(2, 10), _d(2, 12), // W5
  _d(2, 17), _d(2, 19), // W4
  _d(2, 24), _d(2, 26), // W3
  _d(3, 3), _d(3, 5), // W2
];

/// The same weeks for the Sunday setting: 14 sessions in W8..W2.
final List<DateTime> _baseS = [
  _d(1, 20), _d(1, 22), // W8
  _d(1, 27), _d(1, 29), // W7
  _d(2, 3), _d(2, 5), // W6
  _d(2, 10), _d(2, 12), // W5
  _d(2, 17), _d(2, 19), // W4
  _d(2, 24), _d(2, 26), // W3
  _d(3, 3), _d(3, 5), // W2
];

void main() {
  test('the constants the rules are built from are the ones the plan names', () {
    expect(kConsistencyWeeks, 8);
    expect(kConsistencyMinHistoryWeeks, 6);
    expect(kConsistencyMinWeekSessions, 3);
    expect(kTrainingGapWindowDays, 56);
    expect(kTrainingGapMinDays, 5);
    expect(kTrainingGapMinSessionDays, 4);
    expect(kConsistencyPriority, 50);
    expect(kTrainingGapPriority, 25);
  });

  group('S-17801 consistency, a Monday week', () {
    test('four sessions last week against 20 in eight weeks', () {
      final result = _consistency(_fixtureA, 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.weeks, 8);
      expect(result.totalSessions, 20);
      expect(result.average, 2.5);
    });

    test('nothing at all is no result', () {
      expect(_consistency(const [], 'monday'), isNull);
    });
  });

  group('S-17802 the week ends on the day the setting says', () {
    test('a Sunday start ends the week on Saturday: Sunday Mar 15 opens the '
        'running week and the last week falls short', () {
      expect(_consistency(_fixtureA, 'sunday'), isNull);
    });
  });

  group('S-17803 the running week is never counted', () {
    test('three sessions on Mon, Tue and Wed of the running week change nothing', () {
      final result = _consistency([
        ..._fixtureA,
        _d(3, 16),
        _d(3, 17),
        _d(3, 18),
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.totalSessions, 20);
    });
  });

  group('S-17804 six completed weeks of history', () {
    test('five completed weeks of history is too little', () {
      expect(
        _consistency([..._fixtureA.where((d) => !d.isBefore(_d(2, 9)))], 'monday'),
        isNull,
      );
    });

    test('exactly six completed weeks is enough, averaged over six', () {
      final result = _consistency([
        ..._fixtureA.where((d) => !d.isBefore(_d(2, 3))),
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.weeks, 6);
      expect(result.totalSessions, 14);
      expect(result.lastWeekSessions, 4);
      expect(consistencyObservation(result), contains('usual 2.3 a week over the last 6 weeks'));
    });
  });

  group('S-17805 exactly one above the average is enough', () {
    test('24 sessions, four last week: 4 * 8 = 24 + 8', () {
      final result = _consistency(_fixtureEqual, 'monday');
      expect(result, isNotNull);
      expect(result!.totalSessions, 24);
      expect(result.average, 3);
    });

    test('one more session in W2 (25): below the line', () {
      expect(_consistency([..._fixtureEqual, _d(3, 7)], 'monday'), isNull);
    });
  });

  group('S-17806 at least three sessions last week', () {
    test('two sessions against an average of about one is not enough', () {
      expect(_consistency(_fixtureLow, 'monday'), isNull);
    });

    test('two sessions that clear the average alone are still not enough', () {
      // W8..W3 one session each, W2 none, W1 two: 8 sessions in 8 weeks, and
      // 2 * 8 = 16 = 8 + 8, so only the floor of three rejects it.
      final sessions = [
        _d(1, 20), _d(1, 27), _d(2, 3), _d(2, 10), _d(2, 17), _d(2, 24), // W8..W3
        _d(3, 10), _d(3, 12), // W1
      ];
      expect(_consistency(sessions, 'monday'), isNull);
    });

    test('exactly three sessions last week is enough when the average allows it', () {
      // Six completed weeks, 12 sessions, three last week: 3 * 6 = 18 =
      // 12 + 6, so the average clause passes exactly.
      final result = _consistency([
        _d(2, 3), _d(2, 4), // W6
        _d(2, 10), _d(2, 11), // W5
        _d(2, 17), _d(2, 18), // W4
        _d(2, 24), _d(2, 25), // W3
        _d(3, 3), // W2
        _d(3, 10), _d(3, 11), _d(3, 13), // W1
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 3);
      expect(result.weeks, 6);
      expect(result.totalSessions, 12);
    });
  });

  group('S-17807 the training gap', () {
    test('six days since the last session, the longest earlier gap was three', () {
      final result = _gap(_fixtureG, _now);
      expect(result, isNotNull);
      expect(result!.days, 6);
      expect(result.longestBefore, 3);
    });

    test('five days is the floor, inclusive', () {
      final result = _gap(_fixtureG, DateTime(2026, 3, 17, 12));
      expect(result, isNotNull);
      expect(result!.days, 5);
    });

    test('four days is too soon', () {
      expect(_gap(_fixtureG, DateTime(2026, 3, 16, 12)), isNull);
    });

    test('a gap that only equals the longest earlier one is not longer', () {
      final withoutFeb20 = [..._fixtureG.where((d) => d != _d(2, 20))];
      expect(_gap(withoutFeb20, DateTime(2026, 3, 17, 12)), isNull);
      final longer = _gap(withoutFeb20, _now);
      expect(longer, isNotNull);
      expect(longer!.days, 6);
      expect(longer.longestBefore, 5);
    });

    test('an earlier 12-day hole is a longer gap than six days', () {
      final withHole = [
        ..._fixtureG.where(
          (d) => !(d.isAfter(_d(2, 19)) && d.isBefore(_d(3, 1))),
        ),
      ];
      expect(_gap(withHole, _now), isNull);
    });

    test('fewer than four session days in the window is no pattern', () {
      expect(_gap([_d(1, 19), _d(1, 21), _d(3, 1), _d(3, 2)], _now), isNull);
    });

    test('five completed weeks of history is too little', () {
      expect(_gap([..._fixtureG.where((d) => !d.isBefore(_d(2, 10)))], _now), isNull);
    });

    test('no session in the last 56 days is nothing to compare', () {
      expect(
        _gap([_d(1, 5), _d(1, 7), _d(1, 9), _d(1, 12), _d(1, 14)], _now),
        isNull,
      );
    });

    test('several sessions on one day are one day, and none is a gap', () {
      expect(_gap(const [], _now), isNull);
      final doubled = [..._fixtureG, _d(3, 12).add(const Duration(hours: 3))];
      final result = _gap(doubled, _now);
      expect(result!.days, 6);
      expect(result.longestBefore, 3);
    });

    test('exactly four session days in the window is enough', () {
      // Jan 19 is before the 56-day window, which starts Jan 21, so the
      // window holds exactly the four days Feb 20, 23, 26 and Mar 1; Jan 19
      // only gives the history floor.
      final result = _gap([_d(1, 19), _d(2, 20), _d(2, 23), _d(2, 26), _d(3, 1)], _now);
      expect(result, isNotNull);
      expect(result!.days, 17);
      expect(result.longestBefore, 3);
    });
  });

  group('S-17808 the copy', () {
    test('the gap sentence, plural and singular', () {
      expect(
        trainingGapObservation(const TrainingGapResult(days: 6, longestBefore: 3)),
        'No session in 6 days, longer than any gap in your last 8 weeks (the '
        'longest was 3 days).',
      );
      expect(
        trainingGapObservation(const TrainingGapResult(days: 6, longestBefore: 1)),
        'No session in 6 days, longer than any gap in your last 8 weeks (the '
        'longest was 1 day).',
      );
    });

    test('the consistency sentence, a decimal and a whole average', () {
      expect(
        consistencyObservation(
          const ConsistencyResult(lastWeekSessions: 4, weeks: 8, totalSessions: 20),
        ),
        'Last week you logged 4 sessions, above your usual 2.5 a week over the '
        'last 8 weeks.',
      );
      expect(
        consistencyObservation(
          const ConsistencyResult(lastWeekSessions: 4, weeks: 8, totalSessions: 24),
        ),
        'Last week you logged 4 sessions, above your usual 3 a week over the '
        'last 8 weeks.',
      );
    });
  });

  group('S-18301 a session at midnight belongs to its own Monday week', () {
    test("midnight on the first day of the last week counts in it; midnight "
        "on the running week's first day does not", () {
      final result = _consistency([
        ..._baseM,
        _at(3, 9, 0, 0),
        _d(3, 11),
        _d(3, 13),
        _at(3, 15, 23, 59),
        _at(3, 16, 0, 0),
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.weeks, 8);
      expect(result.totalSessions, 20);
    });

    test('without the midnight session the last week falls short', () {
      expect(
        _consistency([
          ..._baseM,
          _d(3, 11),
          _d(3, 13),
          _at(3, 15, 23, 59),
          _at(3, 16, 0, 0),
        ], 'monday'),
        isNull,
      );
    });

    test('23:59 the day before belongs to the week before', () {
      final result = _consistency([
        ..._baseM,
        _at(3, 8, 23, 59),
        _d(3, 10),
        _d(3, 11),
        _d(3, 13),
        _at(3, 15, 23, 59),
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.totalSessions, 21);
    });
  });

  group('S-18302 a session at midnight belongs to its own Sunday week', () {
    test("midnight on the first day of the last week counts in it; midnight "
        "on the running week's first day does not", () {
      final result = _consistency([
        ..._baseS,
        _at(3, 8, 0, 0),
        _d(3, 10),
        _d(3, 12),
        _at(3, 14, 23, 59),
        _at(3, 15, 0, 0),
      ], 'sunday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.weeks, 8);
      expect(result.totalSessions, 18);
    });

    test('without the midnight session the last week falls short', () {
      expect(
        _consistency([
          ..._baseS,
          _d(3, 10),
          _d(3, 12),
          _at(3, 14, 23, 59),
          _at(3, 15, 0, 0),
        ], 'sunday'),
        isNull,
      );
    });

    test('23:59 the day before belongs to the week before', () {
      final result = _consistency([
        ..._baseS,
        _at(3, 7, 23, 59),
        _d(3, 10),
        _d(3, 11),
        _d(3, 12),
        _at(3, 14, 23, 59),
      ], 'sunday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.totalSessions, 19);
    });

    test('the same sessions as A read as Monday weeks give another total', () {
      final result = _consistency([
        ..._baseS,
        _at(3, 8, 0, 0),
        _d(3, 10),
        _d(3, 12),
        _at(3, 14, 23, 59),
        _at(3, 15, 0, 0),
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.totalSessions, 19);
    });
  });

  group('S-18303 the Training Gap history floor follows Start of Week', () {
    // Feb 8 is a Sunday; the last is Mar 10.
    final sundayStart = [
      for (var i = 0; i < 11; i++) DateTime(2026, 2, 8 + 3 * i, 12),
    ];

    test('a first session on a Sunday opens a new Sunday week but ends a '
        'Monday week', () {
      final monday = _gapOn(sundayStart, 'monday');
      expect(monday, isNotNull);
      expect(monday!.days, 8);
      expect(monday.longestBefore, 3);
      expect(_gapOn(sundayStart, 'sunday'), isNull);
    });

    // Feb 1 is a Sunday; the last is Mar 3.
    final earlier = [
      for (var i = 0; i < 11; i++) DateTime(2026, 2, 1 + 3 * i, 12),
    ];

    test('enough history under either start', () {
      for (final sow in const ['monday', 'sunday']) {
        final result = _gapOn(earlier, sow);
        expect(result, isNotNull);
        expect(result!.days, 15);
        expect(result.longestBefore, 3);
      }
    });

    // Feb 7 is a Saturday; the last is Mar 9.
    final saturdayStart = [
      for (var i = 0; i < 11; i++) DateTime(2026, 2, 7 + 3 * i, 12),
    ];

    test('a first session on a Saturday counts six Sunday weeks, which a '
        'Monday-anchored first week would count as five', () {
      // A first week anchored on Monday while the running week starts on
      // Sunday would count 41 days, five weeks.
      final sunday = _gapOn(saturdayStart, 'sunday');
      expect(sunday, isNotNull);
      expect(sunday!.days, 9);
      expect(sunday.longestBefore, 3);
      final monday = _gapOn(saturdayStart, 'monday');
      expect(monday, isNotNull);
      expect(monday!.days, 9);
      expect(monday.longestBefore, 3);
    });
  });

  group('S-18304 a session dated after now changes neither rule', () {
    test('the gap ignores sessions after now', () {
      final without = _gapOn(_fixtureG, 'monday');
      final withFuture = _gapOn([..._fixtureG, _d(3, 19), _d(3, 20)], 'monday');
      expect(without, isNotNull);
      expect(withFuture!.days, without!.days);
      expect(withFuture.longestBefore, without.longestBefore);
      expect(withFuture.days, 6);
      expect(withFuture.longestBefore, 3);
    });

    test('the consistency figures ignore sessions after now', () {
      final result = _consistency([
        ..._fixtureA,
        _d(3, 19),
        _d(3, 20),
        _d(3, 21),
      ], 'monday');
      expect(result, isNotNull);
      expect(result!.lastWeekSessions, 4);
      expect(result.weeks, 8);
      expect(result.totalSessions, 20);
    });
  });
}
