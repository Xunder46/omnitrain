import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/recurrence_rule.dart';

DateTime _d(int year, int month, int day) => DateTime(year, month, day);

void _expectDates(
  List<DateTime> actual,
  List<DateTime> expected,
  String reason,
) {
  expect(actual.length, expected.length, reason: '$reason — date count broke');
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(
      '${a.year}-${a.month}-${a.day}',
      '${e.year}-${e.month}-${e.day}',
      reason: '$reason — date $i broke',
    );
  }
}

void _expectSameRule(RecurrenceRule a, RecurrenceRule b, String reason) {
  expect(b.series, a.series, reason: '$reason — series broke');
  expect(b.unit, a.unit, reason: '$reason — unit broke');
  expect(b.every, a.every, reason: '$reason — every broke');
  expect(b.weekdays, a.weekdays, reason: '$reason — weekdays broke');
  expect(b.end, a.end, reason: '$reason — end broke');
  expect(b.count, a.count, reason: '$reason — count broke');
  expect(b.until?.year, a.until?.year, reason: '$reason — until year broke');
  expect(b.until?.month, a.until?.month, reason: '$reason — until month broke');
  expect(b.until?.day, a.until?.day, reason: '$reason — until day broke');
}

void main() {
  group('RecurrenceRule', () {
    test('S-27701 daily every 1 count 3 starts at the first date', () {
      final rule = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.day,
        every: 1,
        count: 3,
      );
      final dates = rule.dates(_d(2026, 11, 19));
      _expectDates(dates, [
        _d(2026, 11, 19),
        _d(2026, 11, 20),
        _d(2026, 11, 21),
      ], 'S-27701 daily every 1 count 3');
    });

    test('S-27702 weekly every 1 on Thu and Mon count 4', () {
      final rule = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.week,
        every: 1,
        weekdays: const [1, 4],
        count: 4,
      );
      final dates = rule.dates(_d(2026, 11, 19));
      _expectDates(dates, [
        _d(2026, 11, 19),
        _d(2026, 11, 23),
        _d(2026, 11, 26),
        _d(2026, 11, 30),
      ], 'S-27702 weekly every 1 {Mon, Thu} count 4');
    });

    test('S-27703 weekly every 2 on Thu count 3 skips the odd week', () {
      final rule = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.week,
        every: 2,
        weekdays: const [4],
        count: 3,
      );
      final dates = rule.dates(_d(2026, 11, 19));
      _expectDates(dates, [
        _d(2026, 11, 19),
        _d(2026, 12, 3),
        _d(2026, 12, 17),
      ], 'S-27703 weekly every 2 {Thu} count 3');
    });

    test(
      'S-27704 weekly every 2 Thu and Mon skips week 1 and the pre-first Monday',
      () {
        final rule = RecurrenceRule(
          series: 's1',
          unit: RecurrenceUnit.week,
          every: 2,
          weekdays: const [1, 4],
          count: 3,
        );
        final dates = rule.dates(_d(2026, 11, 19));
        _expectDates(dates, [
          _d(2026, 11, 19),
          _d(2026, 11, 30),
          _d(2026, 12, 3),
        ], 'S-27704 weekly every 2 {Mon, Thu} count 3');
      },
    );

    test(
      'S-27705 monthly from the 31st clamps each step from the first date',
      () {
        final rule = RecurrenceRule(
          series: 's1',
          unit: RecurrenceUnit.month,
          every: 1,
          count: 4,
        );
        final dates = rule.dates(_d(2027, 1, 31));
        _expectDates(dates, [
          _d(2027, 1, 31),
          _d(2027, 2, 28),
          _d(2027, 3, 31),
          _d(2027, 4, 30),
        ], 'S-27705 monthly from 2027-01-31 count 4');
      },
    );

    test(
      'S-27706 until bounds the list inclusively, past until keeps the first',
      () {
        final after = RecurrenceRule(
          series: 's1',
          unit: RecurrenceUnit.day,
          end: RecurrenceEnd.date,
          until: _d(2026, 11, 21),
        );
        _expectDates(after.dates(_d(2026, 11, 19)), [
          _d(2026, 11, 19),
          _d(2026, 11, 20),
          _d(2026, 11, 21),
        ], 'S-27706 until 2026-11-21 daily');

        final before = RecurrenceRule(
          series: 's1',
          unit: RecurrenceUnit.day,
          end: RecurrenceEnd.date,
          until: _d(2026, 11, 10),
        );
        _expectDates(
          before.dates(_d(2026, 11, 19)),
          [_d(2026, 11, 19)],
          'S-27706 until 2026-11-10 before the first date',
        );
      },
    );

    test('S-27707 the one-year cap beats a large count', () {
      final daily = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.day,
        every: 1,
        count: 500,
      );
      final dailyDates = daily.dates(_d(2026, 11, 19));
      expect(
        dailyDates.length,
        366,
        reason: 'S-27707 daily count 500 must stop at the one-year cap',
      );
      expect(
        '${dailyDates.last.year}-${dailyDates.last.month}-${dailyDates.last.day}',
        '2027-11-19',
        reason: 'S-27707 daily last date must be the cap day itself',
      );

      final monthly = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.month,
        every: 1,
        count: 24,
      );
      final monthlyDates = monthly.dates(_d(2026, 11, 19));
      expect(
        monthlyDates.length,
        13,
        reason: 'S-27707 monthly count 24 must stop at the one-year cap',
      );
      expect(
        '${monthlyDates.last.year}-${monthlyDates.last.month}-${monthlyDates.last.day}',
        '2027-11-19',
        reason: 'S-27707 monthly last date must be the cap day itself',
      );
    });

    test(
      'S-27708 the first date is always in the list even when its weekday is not ticked',
      () {
        final rule = RecurrenceRule(
          series: 's1',
          unit: RecurrenceUnit.week,
          every: 1,
          weekdays: const [1],
          count: 3,
        );
        final dates = rule.dates(_d(2026, 11, 19));
        _expectDates(dates, [
          _d(2026, 11, 19),
          _d(2026, 11, 23),
          _d(2026, 11, 30),
        ], 'S-27708 weekly {Mon only} from Thu count 3');
      },
    );

    test('S-27709 dates keep local midnight across clock-change days', () {
      final source = File(
        'lib/core/utils/recurrence_rule.dart',
      ).readAsStringSync();
      expect(
        source.contains('Duration(days'),
        isFalse,
        reason:
            'S-27709 guard: RecurrenceRule must not build dates with '
            'Duration(days:) day arithmetic — a clock-change day would drift '
            'an hour',
      );
      expect(
        source.contains('.add('),
        isFalse,
        reason:
            'S-27709 guard: RecurrenceRule must not build dates with '
            '.add(Duration) — a clock-change day would drift an hour',
      );

      for (final start in <DateTime>[_d(2026, 10, 23), _d(2027, 3, 26)]) {
        final rule = RecurrenceRule(
          series: 's1',
          unit: RecurrenceUnit.day,
          every: 1,
          count: 5,
        );
        final dates = rule.dates(start);
        expect(dates.length, 5, reason: 'S-27709 daily count 5 from $start');
        for (var i = 0; i < dates.length; i++) {
          expect(
            dates[i].hour,
            0,
            reason: 'S-27709 date $i from $start must be local midnight (hour)',
          );
          expect(
            dates[i].minute,
            0,
            reason:
                'S-27709 date $i from $start must be local midnight (minute)',
          );
          if (i > 0) {
            final prev = dates[i - 1];
            final nextDay = DateTime(prev.year, prev.month, prev.day + 1);
            expect(
              '${dates[i].year}-${dates[i].month}-${dates[i].day}',
              '${nextDay.year}-${nextDay.month}-${nextDay.day}',
              reason:
                  'S-27709 date $i from $start must be the next calendar day',
            );
          }
        }
      }
    });

    test(
      'S-27710 encode/tryParse round trip is lossless and forgeries are null',
      () {
        final rules = <RecurrenceRule>[
          RecurrenceRule(
            series: 'a',
            unit: RecurrenceUnit.day,
            every: 2,
            count: 9,
          ),
          RecurrenceRule(
            series: 'b',
            unit: RecurrenceUnit.week,
            every: 2,
            weekdays: [1, 4],
            count: 8,
          ),
          RecurrenceRule(
            series: 'c',
            unit: RecurrenceUnit.month,
            every: 3,
            count: 5,
          ),
          RecurrenceRule(
            series: 'd',
            unit: RecurrenceUnit.week,
            every: 1,
            weekdays: [1, 4],
            end: RecurrenceEnd.date,
            until: _d(2027, 1, 14),
          ),
        ];
        for (final rule in rules) {
          final parsed = RecurrenceRule.tryParse(rule.encode());
          expect(
            parsed,
            isNotNull,
            reason: 'S-27710 round trip of ${rule.encode()} must parse',
          );
          _expectSameRule(
            rule,
            parsed!,
            'S-27710 round trip of ${rule.encode()}',
          );
        }

        // Each forged text below is a COMPLETE valid rule with exactly one
        // defect, so a rejection proves the guard for that defect ran.
        Map<String, Object?> validMap() => {
          'v': 1,
          'series': 'a',
          'unit': 'week',
          'every': 1,
          'weekdays': [4],
          'end': 'count',
          'count': 3,
        };
        String forged(String key, Object? value) =>
            jsonEncode({...validMap(), key: value});

        expect(
          RecurrenceRule.tryParse(jsonEncode(validMap())),
          isNotNull,
          reason:
              'S-27710 the unforged valid map must parse — a null result for '
              'a forged text then proves its one defect',
        );

        const forgeries = <String?>[null, '', '{', '[]'];
        for (final forgery in forgeries) {
          expect(
            RecurrenceRule.tryParse(forgery),
            isNull,
            reason:
                'S-27710 forgery must decode to null without throwing: $forgery',
          );
        }

        expect(
          RecurrenceRule.tryParse(forged('v', 2)),
          isNull,
          reason:
              'S-27710 v:2 — the version guard must reject a rule text whose '
              'v is not 1',
        );
        expect(
          RecurrenceRule.tryParse(forged('every', 0)),
          isNull,
          reason: 'S-27710 every:0 — the interval guard must reject every < 1',
        );
        expect(
          RecurrenceRule.tryParse(forged('every', -1)),
          isNull,
          reason: 'S-27710 every:-1 — the interval guard must reject every < 1',
        );
        expect(
          RecurrenceRule.tryParse(forged('every', 1.5)),
          isNull,
          reason:
              'S-27710 every:1.5 — the interval guard must reject a non-int '
              'every',
        );
        expect(
          RecurrenceRule.tryParse(forged('series', '')),
          isNull,
          reason:
              'S-27710 empty series — the series guard must reject an empty '
              'series',
        );
        expect(
          RecurrenceRule.tryParse(forged('unit', 'year')),
          isNull,
          reason:
              'S-27710 unit:year — the unit guard must reject an unknown unit',
        );
        expect(
          RecurrenceRule.tryParse(forged('end', 'never')),
          isNull,
          reason:
              'S-27710 end:never — the end guard must reject an unknown end '
              'mode',
        );
        expect(
          RecurrenceRule.tryParse(forged('count', 'x')),
          isNull,
          reason:
              'S-27710 count:x — the count guard must reject a non-int count',
        );
        expect(
          RecurrenceRule.tryParse(jsonEncode({...validMap(), 'end': 'date'})),
          isNull,
          reason:
              'S-27710 end:date with until missing — the until guard must '
              'reject a date-ended rule without until',
        );
        expect(
          RecurrenceRule.tryParse(
            jsonEncode({...validMap(), 'end': 'date', 'until': '2026-02-30'}),
          ),
          isNull,
          reason:
              'S-27710 until:2026-02-30 — the until guard must reject an '
              'impossible calendar day',
        );
      },
    );

    test('P1.3 summary renders one plain-words line', () {
      final thu = _d(2026, 11, 19);
      final weekly = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.week,
        every: 2,
        weekdays: const [1, 4],
        count: 4,
      );
      expect(
        weekly.summary(thu, 4),
        'Every 2 weeks on Mon, Thu · 4 sessions',
        reason: 'S-27710 summary of the weekly rule',
      );
      final daily = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.day,
        every: 1,
        count: 3,
      );
      expect(
        daily.summary(thu, 3),
        'Every day · 3 sessions',
        reason: 'S-27710 summary of the daily rule',
      );
      final monthly = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.month,
        every: 1,
        count: 4,
      );
      expect(
        monthly.summary(thu, 4),
        'Every month · 4 sessions',
        reason: 'S-27710 summary of the monthly rule',
      );
      expect(
        daily.summary(thu, 1),
        'Every day · 1 session',
        reason: 'S-27710 singular session count',
      );
      final untilDate = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.week,
        every: 2,
        weekdays: const [1, 4],
        count: 4,
        end: RecurrenceEnd.date,
        until: _d(2027, 1, 14),
      );
      expect(
        untilDate.summary(thu, 4),
        'Every 2 weeks on Mon, Thu · 4 sessions · until 14 Jan',
        reason: 'S-27710 summary with an until date',
      );
    });

    test('S-27725b describe states the whole series', () {
      final thu = _d(2026, 11, 19);
      final weekly = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.week,
        every: 1,
        weekdays: const [1, 4],
        count: 8,
      );
      expect(
        weekly.describe(thu),
        'Every week on Mon, Thu · 8 sessions',
        reason:
            'S-27725b: a count-ended weekly rule states the pattern and the '
            'session count',
      );
      final untilDate = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.week,
        every: 2,
        weekdays: const [1, 4],
        end: RecurrenceEnd.date,
        until: _d(2027, 1, 14),
      );
      expect(
        untilDate.describe(thu),
        'Every 2 weeks on Mon, Thu · until 14 Jan',
        reason:
            'S-27725b: a date-ended rule states the until date instead of a '
            'session count',
      );
      final single = RecurrenceRule(
        series: 's1',
        unit: RecurrenceUnit.day,
        every: 1,
        count: 1,
      );
      expect(
        single.describe(thu),
        'Every day · 1 session',
        reason: 'S-27725b: a count of 1 reads as one session',
      );
    });
  });
}
