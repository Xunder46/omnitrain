// Plan 277 P2 — the state tests for the recurring planned-session series
// (S-27711..S-27716, S-27727, S-27729 plus the single-row degrade).
//
// `CalendarState.createRecurringPlannedSessions` / `updateSeriesFrom` /
// `deleteSeriesFrom` over the Mock and Hive harnesses. Plain `test()` only;
// dates are relative to today so the suite never goes stale.
//
// Plan: `docs/plans/2026-11-19-277-recurring-planned-sessions-plan/2026-11-19-277-recurring-planned-sessions-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/recurrence_rule.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';

import 'helpers/repository_harness.dart';

// ─── Fixtures (relative to today) ───────────────────────────────────────────

final _today = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
);
final _first = DateTime(_today.year, _today.month, _today.day + 2);
final _pastDay = DateTime(_today.year, _today.month, _today.day - 3);

RecurrenceRule rule(String series, {int count = 4}) => RecurrenceRule(
  series: series,
  unit: RecurrenceUnit.week,
  every: 1,
  weekdays: [_first.weekday, (_first.weekday % 7) + 1],
  end: RecurrenceEnd.count,
  count: count,
);

final _dates = rule('series-a').dates(_first);

PlannedSession _edited(PlannedSession row, {String? title, String? modality}) =>
    PlannedSession(
      id: row.id,
      ownerUserId: row.ownerUserId,
      scheduledDateMs: row.scheduledDateMs,
      modality: modality ?? row.modality,
      routineTemplateId: row.routineTemplateId,
      title: title ?? row.title,
      note: row.note,
      isCompleted: row.isCompleted,
      linkedSessionId: row.linkedSessionId,
      recurrenceRule: row.recurrenceRule,
      createdAtMs: row.createdAtMs,
      updatedAtMs: row.updatedAtMs,
    );

Future<List<PlannedSession>> rowsSorted(WorkoutRepository repo) async =>
    (await repo.getPlannedSessions()).toList()
      ..sort((a, b) => a.scheduledDateMs.compareTo(b.scheduledDateMs));

/// Creates the 4-row fixture series through [CalendarState] and returns the
/// stored rows sorted by day. A row `n` sits on `_dates[n]`.
Future<List<PlannedSession>> seedSeries(
  WorkoutRepository repo, {
  String series = 'series-a',
  String? routineTemplateId,
  int count = 4,
}) async {
  final calendar = CalendarState(repo);
  await calendar.createRecurringPlannedSessions(
    first: _first,
    rule: rule(series, count: count),
    modality: 'resistance_lifting',
    routineTemplateId: routineTemplateId,
    title: 'Upper',
    note: 'n',
  );
  return rowsSorted(repo);
}

Future<void> seedTemplate(WorkoutRepository repo) async {
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-push',
      name: 'Push',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
  );
}

/// Counts the month-range reads so the one-reload-per-series rule is guarded.
class _CountingRepo extends MockWorkoutRepository {
  int rangeReads = 0;

  @override
  Future<List<PlannedSession>> getPlannedSessionsForDateRange(
    int fromMs,
    int toMs,
  ) async {
    rangeReads++;
    return super.getPlannedSessionsForDateRange(fromMs, toMs);
  }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: recurring planned-session series state', () {
      late RepositoryHarness harness;
      setUp(() => harness = make());
      tearDown(() => harness.close());

      test('S-27711 createRecurringPlannedSessions writes 4 rows with the '
          'rule text and reloads the month once', () async {
        final repo = await harness.open();
        final rows = await seedSeries(repo);

        expect(rows.length, 4, reason: 'S-27711 the rule yields 4 dates');
        final ids = <String>{};
        for (var i = 0; i < 4; i++) {
          final row = rows[i];
          expect(
            row.recurrenceRule,
            rule('series-a').encode(),
            reason: 'S-27711 every row carries the same rule text',
          );
          expect(row.modality, 'resistance_lifting');
          expect(row.title, 'Upper');
          expect(row.note, 'n');
          expect(row.isCompleted, isFalse);
          expect(row.linkedSessionId, isNull);
          expect(
            row.scheduledDateMs,
            OmniDateUtils.startOfDayMs(_dates[i]),
            reason: 'S-27711 row $i sits on date $i',
          );
          ids.add(row.id);
        }
        expect(ids.length, 4, reason: 'S-27711 four different ids');

        // The one-reload rule (D-27704): a per-row reload would make 4 calls.
        if (harness.name == 'Mock') {
          final countingRepo = _CountingRepo();
          await countingRepo.initialize();
          final calendar = CalendarState(countingRepo);
          countingRepo.rangeReads = 0;
          await calendar.createRecurringPlannedSessions(
            first: _first,
            rule: rule('series-b'),
            modality: 'resistance_lifting',
            title: 'Upper',
            note: 'n',
          );
          expect(
            countingRepo.rangeReads,
            1,
            reason: 'S-27711 one create means one month reload',
          );
        }
      });

      test('S-27712 a rule that yields one date creates one row that still '
          'carries the rule text', () async {
        final repo = await harness.open();
        final calendar = CalendarState(repo);
        final oneDateRule = RecurrenceRule(
          series: 'series-one',
          unit: RecurrenceUnit.week,
          every: 1,
          weekdays: [_first.weekday, (_first.weekday % 7) + 1],
          end: RecurrenceEnd.date,
          until: _first,
        );
        await calendar.createRecurringPlannedSessions(
          first: _first,
          rule: oneDateRule,
          modality: 'resistance_lifting',
          title: 'Upper',
          note: 'n',
        );

        final rows = await rowsSorted(repo);
        expect(rows.length, 1, reason: 'S-27712 until == first yields 1 date');
        expect(
          rows.single.recurrenceRule,
          oneDateRule.encode(),
          reason: 'S-27712 a series of one still carries the rule text',
        );
        expect(rows.single.scheduledDateMs, OmniDateUtils.startOfDayMs(_first));
      });

      test('S-27713 deleteSeriesFrom keeps the completed row, the earlier row '
          'and the past-day row', () async {
        final repo = await harness.open();
        final rows = await seedSeries(repo);
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-past',
            ownerUserId: 'user-1',
            scheduledDateMs: OmniDateUtils.startOfDayMs(_pastDay),
            modality: 'resistance_lifting',
            title: 'Upper',
            note: 'n',
            isCompleted: false,
            recurrenceRule: rule('series-a').encode(),
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        final calendar = CalendarState(repo);
        await calendar.completePlannedSession(rows[2].id, 'session-x');

        await calendar.deleteSeriesFrom(rows[1]);

        final after = await rowsSorted(repo);
        final ids = after.map((r) => r.id).toSet();
        expect(
          ids,
          {rows[0].id, rows[2].id, 'p-past'},
          reason:
              'S-27713 rows 2 and 4 are gone; row 1, the completed row 3 '
              'and the past-day row remain',
        );
        expect(
          after.firstWhere((r) => r.id == rows[2].id).isCompleted,
          isTrue,
          reason: 'S-27713 the completed row stays completed',
        );
      });

      test('S-27730 deleting a missed plan from a series removes it and the '
          'later upcoming rows, not past rows after it', () async {
        final repo = await harness.open();
        final ruleText = rule('series-m', count: 5).encode();
        DateTime day(int offset) =>
            DateTime(_today.year, _today.month, _today.day + offset);
        for (final entry in {
          'm-a': -3,
          'm-b': -2,
          'm-c': -1,
          'm-d': 1,
          'm-e': 2,
        }.entries) {
          await repo.createPlannedSession(
            PlannedSession(
              id: entry.key,
              ownerUserId: 'user-1',
              scheduledDateMs: OmniDateUtils.startOfDayMs(day(entry.value)),
              modality: 'resistance_lifting',
              title: 'Upper',
              note: 'n',
              isCompleted: false,
              recurrenceRule: ruleText,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
        }
        final calendar = CalendarState(repo);

        await calendar.deleteSeriesFrom(
          (await repo.getPlannedSessions()).firstWhere((r) => r.id == 'm-a'),
        );

        final after = await rowsSorted(repo);
        final ids = after.map((r) => r.id).toSet();
        expect(
          ids,
          {'m-b', 'm-c'},
          reason:
              'S-27730 the missed plan m-a the user pointed at and the '
              'upcoming rows m-d, m-e go; the past rows m-b, m-c after it '
              'stay',
        );
      });

      test('S-27729 the series scope includes the first row itself', () async {
        final repo = await harness.open();
        final rows = await seedSeries(repo);
        final calendar = CalendarState(repo);

        await calendar.deleteSeriesFrom(rows[0]);
        expect(
          (await repo.getPlannedSessions()).isEmpty,
          isTrue,
          reason: 'S-27729 deleteSeriesFrom(row1) removes all 4',
        );

        // A fresh series: editing from row 1 changes every row (>= boundary).
        final second = await seedSeries(repo, series: 'series-b');
        await calendar.updateSeriesFrom(_edited(second[0], title: 'Changed'));
        final after = await rowsSorted(repo);
        expect(
          after.map((r) => r.title),
          everyElement('Changed'),
          reason: 'S-27729 updateSeriesFrom(row1) changes all 4 titles',
        );
        expect(after.length, 4);
      });

      test('S-27714 updateSeriesFrom copies title and modality to rows 2..4 '
          'only, untouched fields stay put', () async {
        final repo = await harness.open();
        final rows = await seedSeries(repo);
        final calendar = CalendarState(repo);
        await calendar.completePlannedSession(rows[2].id, 'session-x');

        final before = await rowsSorted(repo);
        await calendar.updateSeriesFrom(
          _edited(before[1], title: 'Lower', modality: 'cardio_endurance'),
        );
        final after = await rowsSorted(repo);

        expect(after.length, 4, reason: 'S-27714 no row is created or lost');
        for (var i = 0; i < 4; i++) {
          final row = after[i];
          final old = before[i];
          expect(row.id, old.id, reason: 'S-27714 id unchanged on row $i');
          expect(
            row.scheduledDateMs,
            old.scheduledDateMs,
            reason: 'S-27714 date unchanged on row $i',
          );
          expect(
            row.recurrenceRule,
            old.recurrenceRule,
            reason: 'S-27714 rule text unchanged on row $i',
          );
          expect(
            row.createdAtMs,
            old.createdAtMs,
            reason: 'S-27714 createdAtMs unchanged on row $i',
          );
          expect(row.isCompleted, old.isCompleted);
        }
        expect(
          after[0].title,
          'Upper',
          reason: 'S-27714 row 1 is before the boundary and keeps its title',
        );
        expect(after[0].modality, 'resistance_lifting');
        for (var i = 1; i < 4; i++) {
          if (i == 2) {
            expect(
              after[i].title,
              'Upper',
              reason: 'S-27714 the completed row 3 keeps its old title',
            );
            expect(after[i].modality, 'resistance_lifting');
            continue;
          }
          expect(after[i].title, 'Lower');
          expect(after[i].modality, 'cardio_endurance');
        }
      });

      test('S-27715 completing one occurrence keeps its rule text and leaves '
          'the others planned', () async {
        final repo = await harness.open();
        final rows = await seedSeries(repo);
        final calendar = CalendarState(repo);
        final ruleText = rows[1].recurrenceRule;

        await calendar.completePlannedSession(rows[1].id, 'session-x');

        final after = await rowsSorted(repo);
        final completed = after.firstWhere((r) => r.id == rows[1].id);
        expect(completed.isCompleted, isTrue, reason: 'S-27715 row 2 is done');
        expect(
          completed.linkedSessionId,
          'session-x',
          reason: 'S-27715 row 2 links the session',
        );
        expect(
          completed.recurrenceRule,
          ruleText,
          reason: 'S-27715 the rule text survives the completion copy',
        );
        for (var i = 0; i < 4; i++) {
          if (i == 1) continue;
          expect(after[i].isCompleted, isFalse);
          expect(after[i].linkedSessionId, isNull);
        }
      });

      test('S-27716 the routine delete cascade removes every occurrence and '
          'leaves an unrelated row', () async {
        final repo = await harness.open();
        await seedTemplate(repo);
        await seedSeries(
          repo,
          series: 'series-c',
          routineTemplateId: 'tpl-push',
          count: 3,
        );
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-free',
            ownerUserId: 'user-1',
            scheduledDateMs: OmniDateUtils.startOfDayMs(_pastDay),
            modality: 'resistance_lifting',
            isCompleted: false,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        await repo.deletePlannedSessionsByTemplateId('tpl-push');

        final after = await rowsSorted(repo);
        expect(
          after.map((r) => r.id),
          ['p-free'],
          reason: 'S-27716 the three occurrences are gone, the free row stays',
        );
      });

      test('S-27727 the wall-clock day key of every series row reads back as '
          'the same local day with the rule text unchanged', () async {
        final repo = await harness.open();
        final rows = await seedSeries(repo);
        final ruleText = rule('series-a').encode();

        for (var i = 0; i < 4; i++) {
          expect(
            rows[i].toMap()['scheduled_date_ms'],
            DateTime.utc(
              _dates[i].year,
              _dates[i].month,
              _dates[i].day,
            ).millisecondsSinceEpoch,
            reason: 'S-27727 row $i stores the wall-clock day key',
          );
        }

        final reread = await repo.getPlannedSessions();
        expect(reread.length, 4);
        for (var i = 0; i < 4; i++) {
          expect(
            reread[i].scheduledDateMs,
            DateTime(
              _dates[i].year,
              _dates[i].month,
              _dates[i].day,
            ).millisecondsSinceEpoch,
            reason: 'S-27727 row $i reads back as the same local day',
          );
          expect(
            reread[i].recurrenceRule,
            ruleText,
            reason: 'S-27727 the rule text is unchanged',
          );
        }
      });

      test('S-27711b a row outside any series is handled alone', () async {
        final repo = await harness.open();
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-solo-a',
            ownerUserId: 'user-1',
            scheduledDateMs: OmniDateUtils.startOfDayMs(_dates[0]),
            modality: 'resistance_lifting',
            title: 'Solo A',
            isCompleted: false,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-solo-b',
            ownerUserId: 'user-1',
            scheduledDateMs: OmniDateUtils.startOfDayMs(_dates[1]),
            modality: 'resistance_lifting',
            title: 'Solo B',
            isCompleted: false,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        final calendar = CalendarState(repo);

        final soloA = (await rowsSorted(repo)).first;
        await calendar.updateSeriesFrom(_edited(soloA, title: 'A changed'));

        var after = await rowsSorted(repo);
        expect(
          after.firstWhere((r) => r.id == 'p-solo-a').title,
          'A changed',
          reason: 'S-27711b the non-series row degrades to a single update',
        );
        expect(
          after.firstWhere((r) => r.id == 'p-solo-b').title,
          'Solo B',
          reason: 'S-27711b the other row is untouched',
        );

        final soloB = after.firstWhere((r) => r.id == 'p-solo-b');
        await calendar.deleteSeriesFrom(soloB);
        after = await rowsSorted(repo);
        expect(
          after.map((r) => r.id),
          ['p-solo-a'],
          reason: 'S-27711b a non-series delete removes just that row',
        );
      });
    });
  }
}
