// Plan 236 P1 — planned sessions and training periods stay on their calendar
// days across a time-zone change.
//
// A planned session's `scheduledDateMs` and a period's `startDateMs` /
// `endDateMs` are held as local instants everywhere above the repository, but
// stored as that local wall-clock time read as UTC
// (`OmniDateUtils.wallClockKeyMs`), so the stored number is the same in every
// zone. The conversion lives only in the models' `toMap`/`fromMap`.
//
// Scenarios S-23601..S-23606 of
// `docs/plans/2026-11-18-236-plans-and-periods-survive-a-time-zone-change-plan/2026-11-18-236-plans-and-periods-survive-a-time-zone-change-plan.md`.
// Plain `test()` throughout: a Hive write inside `testWidgets` never completes
// (FakeAsync never advances real time).

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// The app's currency: local instants of the calendar days under test.
final int d14 = DateTime(2026, 6, 14).millisecondsSinceEpoch;
final int d15 = DateTime(2026, 6, 15).millisecondsSinceEpoch;
final int d15End = DateTime(
  2026,
  6,
  15,
  23,
  59,
  59,
  999,
).millisecondsSinceEpoch;
final int d16 = DateTime(2026, 6, 16).millisecondsSinceEpoch;
final int d17 = DateTime(2026, 6, 17).millisecondsSinceEpoch;
final int d17End = DateTime(
  2026,
  6,
  17,
  23,
  59,
  59,
  999,
).millisecondsSinceEpoch;
final int d18 = DateTime(2026, 6, 18).millisecondsSinceEpoch;
final int d18End = DateTime(
  2026,
  6,
  18,
  23,
  59,
  59,
  999,
).millisecondsSinceEpoch;

// The stored keys: the local wall-clock time read as UTC, the same number in
// every zone.
const int key15 = 1781481600000;
const int key15End = 1781567999999;
const int key17End = 1781740799999;

PlannedSession _plan(String id, int scheduledDateMs) => PlannedSession(
  id: id,
  ownerUserId: 'user-1',
  scheduledDateMs: scheduledDateMs,
  modality: 'resistance_lifting',
  title: 'Plan $id',
  note: 'note $id',
  createdAtMs: 1700000000000,
  updatedAtMs: 1700000001000,
);

/// The fixture period of S-23603/S-23605: 15 June 00:00 to 17 June 23:59:59.999
/// local.
TrainingPeriod _periodFixture() => TrainingPeriod(
  id: 'period-236',
  ownerUserId: 'user-1',
  name: 'Block 236',
  startDateMs: d15,
  endDateMs: d17End,
  focusModalities: const ['resistance_lifting'],
  notes: 'note 236',
  colorHex: '#4CAF50',
  createdAtMs: 1700000000000,
  updatedAtMs: 1700000001000,
);

void main() {
  // ─── S-23601: the two helpers ─────────────────────────────────────────
  test('S-23601 wallClockKeyMs reads the wall-clock time as UTC', () {
    expect(
      OmniDateUtils.wallClockKeyMs(
        DateTime(2026, 6, 15).millisecondsSinceEpoch,
      ),
      key15,
    );
    expect(
      OmniDateUtils.wallClockKeyMs(
        DateTime(2026, 6, 15, 23, 59, 59, 999).millisecondsSinceEpoch,
      ),
      key15End,
    );
    expect(
      OmniDateUtils.wallClockKeyMs(
        DateTime(2026, 6, 15, 13, 45, 10, 250).millisecondsSinceEpoch,
      ),
      1781531110250,
    );

    for (final d in [
      DateTime(2026, 6, 15),
      DateTime(2026, 6, 15, 23, 59, 59, 999),
      DateTime(2026, 6, 15, 13, 45, 10, 250),
    ]) {
      final localMs = d.millisecondsSinceEpoch;
      expect(
        OmniDateUtils.localMsOfWallClockKeyMs(
          OmniDateUtils.wallClockKeyMs(localMs),
        ),
        localMs,
        reason: 'the round trip returns the original local instant ($d)',
      );
    }
  });

  // ─── S-23602: PlannedSession converts at its map boundary ─────────────
  test('S-23602 a planned session stores its wall-clock key', () {
    final plan = _plan('plan-23602', d15);
    final map = plan.toMap();
    expect(map['scheduled_date_ms'], key15);

    final back = PlannedSession.fromMap(map);
    expect(back.scheduledDateMs, d15);
    expect(back.id, plan.id);
    expect(back.ownerUserId, plan.ownerUserId);
    expect(back.modality, plan.modality);
    expect(back.title, plan.title);
    expect(back.note, plan.note);
    expect(back.isCompleted, plan.isCompleted);
    expect(back.linkedSessionId, plan.linkedSessionId);
    expect(back.routineTemplateId, plan.routineTemplateId);
    expect(back.recurrenceRule, plan.recurrenceRule);
    expect(back.createdAtMs, plan.createdAtMs);
    expect(back.updatedAtMs, plan.updatedAtMs);
  });

  // ─── S-23603: TrainingPeriod converts both bounds ─────────────────────
  test('S-23603 a training period stores its wall-clock bounds', () {
    final period = _periodFixture();
    final map = period.toMap();
    expect(map['start_date_ms'], key15);
    expect(map['end_date_ms'], key17End);

    final back = TrainingPeriod.fromMap(map);
    expect(back.startDateMs, d15);
    expect(back.endDateMs, d17End);
  });

  // ─── S-23604..S-23606: both stores ────────────────────────────────────
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — plans and periods survive a zone change '
        '(plan 236)', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-23604 planned sessions are read back on their calendar days',
        () async {
          await repo.createPlannedSession(_plan('plan-14', d14));
          await repo.createPlannedSession(_plan('plan-15', d15));
          await repo.createPlannedSession(_plan('plan-16', d16));

          final oneDay = await repo.getPlannedSessionsForDateRange(d15, d15End);
          expect(oneDay, hasLength(1));
          expect(oneDay.single.id, 'plan-15');
          expect(oneDay.single.scheduledDateMs, d15);

          final wide = await repo.getPlannedSessionsForDateRange(d14, d16);
          expect(wide.map((s) => s.id).toList(), [
            'plan-14',
            'plan-15',
            'plan-16',
          ]);
          expect(wide.map((s) => s.scheduledDateMs).toList(), [d14, d15, d16]);

          final all = await repo.getPlannedSessions();
          expect(all.map((s) => s.id).toList(), [
            'plan-14',
            'plan-15',
            'plan-16',
          ]);
          expect(all.map((s) => s.scheduledDateMs).toList(), [d14, d15, d16]);

          if (harness.name == 'Hive') {
            final row = Hive.box<Map>('planned_sessions').get('plan-15')!;
            expect(row['scheduled_date_ms'], key15);
          }
        },
      );

      test(
        'S-23605 a training period is read back with its own bounds',
        () async {
          final period = _periodFixture();
          await repo.createPeriod(period);

          expect(await repo.hasPeriodOverlap(d17, d17End), isTrue);
          expect(await repo.hasPeriodOverlap(d18, d18End), isFalse);
          expect(
            await repo.hasPeriodOverlap(
              period.startDateMs,
              period.endDateMs,
              excludeId: period.id,
            ),
            isFalse,
          );

          final byId = await repo.getPeriodById(period.id);
          expect(byId, isNotNull);
          expect(byId!.startDateMs, d15);
          expect(byId.endDateMs, d17End);

          final all = await repo.getPeriods();
          expect(all, hasLength(1));
          expect(all.single.startDateMs, d15);
          expect(all.single.endDateMs, d17End);

          if (harness.name == 'Hive') {
            final row = Hive.box<Map>('training_periods').get(period.id)!;
            expect(row['start_date_ms'], key15);
            expect(row['end_date_ms'], key17End);
          }
        },
      );

      test('S-23606 the stored plans and period survive a restart', () async {
        await repo.createPlannedSession(_plan('plan-14', d14));
        await repo.createPlannedSession(_plan('plan-15', d15));
        await repo.createPlannedSession(_plan('plan-16', d16));
        await repo.createPeriod(_periodFixture());

        repo = await harness.restart();

        final plans = await repo.getPlannedSessions();
        expect(plans.map((s) => s.id).toList(), [
          'plan-14',
          'plan-15',
          'plan-16',
        ]);
        expect(plans.map((s) => s.scheduledDateMs).toList(), [d14, d15, d16]);

        final periods = await repo.getPeriods();
        expect(periods, hasLength(1));
        expect(periods.single.startDateMs, d15);
        expect(periods.single.endDateMs, d17End);
      });
    });
  }
}
