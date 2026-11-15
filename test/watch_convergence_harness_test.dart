// Plan 145 Phase A, part 2: the heal, the four checks and the scripted
// scenarios that read them.
//
// Plan: `docs/plans/2026-11-10-145-convergence-test-plan/2026-11-10-145-convergence-test-plan.md`
// (D-14505…D-14508, D-14512…D-14515; S-14501, S-14502, S-14503, S-14505).
// Harness: `test/helpers/watch_pair_harness.dart`.
//
// S-14501 and S-14502 are guards; S-14505 is a guard for plan 140/141's store
// surviving a kill; S-14503 is a finding (D-14508), kept as a skipped replay of
// the defect `_applyLifecycle` carries today.
//
// S-14504/06/07 are Phase B's measurements: the four checks plus the scenario's
// own expected outcome. S-14507's timer tally is its product, so the file
// prints it.
// ignore_for_file: avoid_print
//
// Plain `test()` throughout: `testWidgets` runs inside FakeAsync, where the
// engine's and the graph's real awaits never complete.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/sync_protocol/end_skew.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/watch_pair_harness.dart';

void main() {
  _triageFaultTests();
  _b2Tests();
  _plan161Tests();
  _plan167Tests();
  test(
    'D-14512 a live frame withdraws the older queued copy it replaces',
    () async {
      // Phone lane: the shipping transport withdraws the queued copy a frame
      // supersedes on the live path too (`watch_transport.dart:384`), not only
      // when it queues. A harness that did not would drain a stale snapshot after
      // a newer live one — a late frame the OS never delivers.
      final phonePair = await WatchPairHarness.build();
      final phoneRunner = phonePair.runner;
      await phoneRunner.perform(phoneRunner.phoneStartsSession());
      final sessionId = phonePair.phone.currentSession!.id;
      await phoneRunner.perform(phoneRunner.linkDrops());
      await phoneRunner.perform(phoneRunner.phoneLogsSet());

      bool phoneSnapshotQueued() => phonePair.radio.phoneQueue.any(
        (frame) =>
            frame['type'] == 'session_snapshot' &&
            frame['sessionId'] == sessionId,
      );

      expect(
        phoneSnapshotQueued(),
        isTrue,
        reason: 'the snapshot logged while apart waits in the OS queue',
      );

      phonePair.radio.setReachable(true);
      await phoneRunner.perform(phoneRunner.phoneLogsSet());
      expect(
        phoneSnapshotQueued(),
        isFalse,
        reason: 'the live snapshot withdraws the queued copy it replaces',
      );

      // Wrist lane, snapshot: the same rule on the wrist's own queue.
      final wristPair = await WatchPairHarness.build();
      final wristRunner = wristPair.runner;
      await wristRunner.perform(wristRunner.phoneStartsSession());
      await wristRunner.perform(wristRunner.linkDrops());
      await wristPair.wristOrchestrator.sync();
      await wristPair.settle();

      bool wristSnapshotQueued() => wristPair.radio.wristQueue.any(
        (frame) => frame['type'] == 'session_snapshot',
      );

      expect(
        wristSnapshotQueued(),
        isTrue,
        reason: 'the snapshot the wrist sent while apart waits in the OS queue',
      );

      wristPair.radio.setReachable(true);
      await wristPair.wristOrchestrator.sync();
      await wristPair.settle();
      expect(
        wristSnapshotQueued(),
        isFalse,
        reason: 'the live wrist snapshot withdraws the queued copy it replaces',
      );

      // Wrist lane, terminal lifecycle: a `completed` sent live withdraws that
      // session's queued snapshot (PROTOCOL.md 2026-10-24 row).
      final finishPair = await WatchPairHarness.build();
      final finishRunner = finishPair.runner;
      await finishRunner.perform(finishRunner.phoneStartsSession());
      await finishRunner.perform(finishRunner.linkDrops());
      await finishPair.wristOrchestrator.sync();
      await finishPair.settle();
      expect(
        finishPair.radio.wristQueue.any(
          (frame) => frame['type'] == 'session_snapshot',
        ),
        isTrue,
        reason: 'the snapshot the wrist sent while apart waits in the queue',
      );

      finishPair.radio.setReachable(true);
      await finishPair.wristEngine.finishSession();
      await finishPair.settle();
      expect(
        finishPair.radio.wristQueue.any(
          (frame) => frame['type'] == 'session_snapshot',
        ),
        isFalse,
        reason: 'the live terminal lifecycle withdraws the queued snapshot',
      );
    },
  );

  test('S-14501 no faults: both sides finish the same workout with its '
      'three entries', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.phoneLogsSet());
    await runner.perform(runner.phoneFinishes());

    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(heal.converged, isTrue, reason: runner.traceText());
    expect(report.failures, isEmpty, reason: runner.traceText());
    expect(report.converged, isTrue);

    final sessionIds = harness.sessionIds;
    expect(sessionIds, hasLength(1), reason: 'one workout, one session id');
    final sessionId = sessionIds.single;
    final label = harness.labelFor(sessionId);
    expect(report.phoneStatus[label], WatchSessionStatus.completed);
    expect(report.wristStatus[label], WatchSessionStatus.completed);

    // Plan 160 D-16003: the wrist records and announces its own end as an
    // entry of its own (`end-<sessionId>`), so the two id sets the pair counts
    // as logged work exclude it.
    final phoneEntries = {
      for (final id in runner.phoneEntryIds[sessionId] ?? const <String>{})
        if (id != 'end-$sessionId') id,
    };
    final wristEntries = {
      for (final id in runner.wristEntryIds[sessionId] ?? const <String>{})
        if (id != 'end-$sessionId') id,
    };
    expect(
      phoneEntries,
      hasLength(3),
      reason:
          'the two wrist sets and the one phone set: $phoneEntries\n'
          '${runner.traceText()}',
    );
    expect(
      wristEntries,
      hasLength(3),
      reason: 'the two wrist sets and the one phone set: $wristEntries',
    );
    expect(phoneEntries, wristEntries);
    expect(runner.phoneEntryIds[sessionId], runner.wristEntryIds[sessionId]);
  });

  test(
    'S-14502 the same actions twice read the same trace and the same result',
    () async {
      Future<(String, String)> run() async {
        final harness = await WatchPairHarness.build();
        final runner = harness.runner;
        await runner.perform(runner.phoneStartsSession());
        await runner.perform(runner.wristLogsSet());
        await runner.perform(runner.phoneLogsSet());
        await runner.perform(runner.linkDrops());
        await runner.perform(runner.wristLogsSet());
        await runner.perform(runner.phoneFinishes());
        await runner.perform(runner.linkRises());
        await runner.heal();
        final report = await runner.checkConvergence();
        return (runner.traceText(), report.toString());
      }

      final (firstTrace, firstResult) = await run();
      final (secondTrace, secondResult) = await run();

      expect(secondTrace, firstTrace, reason: 'the trace is the same twice');
      expect(secondResult, firstResult, reason: 'the result is the same twice');
    },
  );

  test(
    'S-14503 a finished workout is never reopened by a queued started',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.wristStartsFreeWorkout());
      final sessionId = harness.wristEngine.session!.sessionId;

      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneReassertsLive());
      await runner.perform(runner.wristFinishes());
      await runner.perform(runner.linkRises());

      expect(
        harness.radio.phoneQueue.where(
          (frame) => frame['type'] == 'session_lifecycle',
        ),
        isEmpty,
        reason: 'the queued started lifecycle drained on link up',
      );
      expect(harness.labelFor(sessionId), 'session 1');
      expect(
        harness.wristEngine.session?.status,
        WatchSessionStatus.completed,
        reason:
            'a started lifecycle that arrives after completed changes '
            'nothing (plan 145 D-14511, plan 146)',
      );
    },
  );

  test(
    'S-14505 a wrist killed after the phone finished still hears the end',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      await runner.perform(runner.wristLogsSet());
      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneFinishes());
      await runner.perform(runner.wristKilled());

      final heal = await runner.heal();
      final report = await runner.checkConvergence();

      expect(heal.converged, isTrue, reason: runner.traceText());
      expect(report.failures, isEmpty, reason: runner.traceText());
      expect(harness.sessionIds, [sessionId], reason: 'no second session id');
      final label = harness.labelFor(sessionId);
      expect(report.phoneStatus[label], WatchSessionStatus.completed);
      expect(report.wristStatus[label], WatchSessionStatus.completed);
      expect(runner.phoneEntryIds[sessionId], runner.wristEntryIds[sessionId]);
      // Plan 160 D-16003: the end the wrist recorded for itself is one entry
      // among the pair's, and the one set a `hasLength(1)` set.
      expect(
        {
          for (final id in runner.wristEntryIds[sessionId] ?? const <String>{})
            if (id != 'end-$sessionId') id,
        },
        hasLength(1),
        reason: 'the wrist set the phone never lost, and not its own end',
      );
    },
  );

  test(
    'B1 the injected wrist engine factory builds the engine the pair runs',
    () async {
      _CountingWristEngine? injected;
      final harness = await WatchPairHarness.build(
        engineFactory: (args) => injected = _CountingWristEngine(args),
      );
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      await runner.perform(runner.wristLogsSet());
      await runner.perform(runner.phoneFinishes());
      await runner.heal();

      expect(
        harness.wristEngine,
        same(injected),
        reason: 'the factory builds the engine the pair actually runs',
      );
      expect(
        injected!.applied,
        greaterThanOrEqualTo(1),
        reason: 'the injected engine sees the phone frames of the run',
      );
    },
  );

  test('B1 drainOnlyHeal makes the heal one drain and nothing else', () async {
    Future<(HealReport, String?)> healOf({required bool drainOnly}) async {
      final harness = await WatchPairHarness.build();
      harness.drainOnlyHeal = drainOnly;
      final runner = harness.runner;
      await runner.perform(runner.phoneStartsSession());
      await runner.perform(runner.wristLogsSet());
      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneFinishes());
      await runner.perform(runner.wristKilled());
      final heal = await runner.heal();
      return (heal, harness.wristEngine.session?.status);
    }

    List<PairFrame> framesOf(HealReport report) => [
      for (final round in report.rounds) ...round.frames,
    ];

    final (full, fullStatus) = await healOf(drainOnly: false);
    final (drained, drainedStatus) = await healOf(drainOnly: true);

    expect(
      framesOf(full).any((frame) => frame.type == 'energy_live'),
      isTrue,
      reason:
          'the production heal sends the wrist frame that re-offers '
          'an owed end',
    );
    expect(
      framesOf(full).any((frame) => frame.type.startsWith('request:')),
      isTrue,
      reason: 'the production heal asks the wrist for its session',
    );

    expect(
      drained.rounds,
      hasLength(1),
      reason: 'the seam runs no rounds: one drain is the whole heal',
    );
    expect(
      framesOf(drained).any((frame) => frame.type == 'energy_live'),
      isFalse,
      reason: 'the seam sends no wrist frame',
    );
    // Plan 160 D-16002: the drained end makes the wrist record its own end and
    // announce it, and every frame after that is an answer to the drained ones
    // — the end observation, the phone's receipt for it, and the phone's
    // lifecycle answers. What the seam must never carry is a trigger of its own.
    expect(
      [for (final frame in framesOf(drained)) if (!frame.drained) frame.type],
      everyElement(isIn(const <String>[
        'observations_up',
        'receipt',
        'session_lifecycle',
      ])),
      reason: 'the seam sends nothing; every other frame answers the drain',
    );

    expect(fullStatus, WatchSessionStatus.completed);
    expect(
      drainedStatus,
      WatchSessionStatus.completed,
      reason:
          'evidence F-seam: an end travels as a durable lifecycle, so the '
          'OS queue alone carries it to the wrist. The S-14509 mutation '
          'therefore cannot turn this shape red; what it removes is the '
          'heal\'s sync, resume and re-offer triggers, not the queue',
    );
  });
  test('H1 a wrist discard ends the phone side too (S-14514 abandon trace) '
      '— A-14516', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.wristStartsFreeWorkout());
    final sessionId = harness.wristEngine.session!.sessionId;
    await runner.perform(runner.wristDiscards());
    await runner.heal();
    final report = await runner.checkConvergence();

    final label = harness.labelFor(sessionId);
    expect(report.statusMismatches, isEmpty, reason: runner.traceText());
    expect(report.phoneStatus[label], WatchSessionStatus.abandoned);
    expect(report.wristStatus[label], WatchSessionStatus.abandoned);
  });

  test(
    'H2 the heal settles on unchanged state, not on silence — A-14517',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.wristStartsFreeWorkout());
      await runner.perform(runner.phoneStartsRest());
      await runner.perform(runner.wristDiscards());

      final heal = await runner.heal();

      expect(heal.converged, isTrue, reason: runner.traceText());
      expect(
        heal.rounds.length,
        lessThanOrEqualTo(HarnessRunner.healRoundLimit),
        reason: 'the heal is bounded',
      );
    },
  );

  test('H3 an entry the phone received counts as held after the wrist '
      'moves on — A-14518', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.wristFinishes());
    await runner.perform(runner.wristStartsFreeWorkout());
    await runner.heal();
    final report = await runner.checkConvergence();

    const wristEntry = 'w-entry-1';
    expect(
      runner.wristEntryIds[sessionId],
      contains(wristEntry),
      reason: 'the wrist logged the set: ${runner.traceText()}',
    );
    expect(
      runner.phoneEntryIds[sessionId],
      contains(wristEntry),
      reason: 'the phone received it: ${runner.traceText()}',
    );
    expect(
      report.entryMismatches,
      isEmpty,
      reason:
          'the wrist moved on to a second workout, the phone still '
          'holds what it received: ${runner.traceText()}',
    );
  });

  test('H4 a second phone Start while a session is open keeps the session '
      '— A-14519', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.phoneStartsSession());

    expect(
      harness.phone.currentSession?.id,
      sessionId,
      reason: 'the home screen offers Resume, not a second Start',
    );
    expect(harness.sessionIds, [sessionId], reason: 'one session id');
  });

  test(
    'H4 a second wrist Start while a workout runs keeps it — A-14519',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.wristStartsFreeWorkout());
      final sessionId = harness.wristEngine.session!.sessionId;
      await runner.perform(runner.wristLogsSet());
      await runner.perform(runner.wristStartsFreeWorkout());

      expect(harness.wristEngine.session?.sessionId, sessionId);
      expect(
        harness.wristEngine.entries,
        hasLength(1),
        reason: 'the second Start does not restart the workout',
      );
    },
  );

  test('H5 a session the phone holds but has moved on from reads active, '
      'not missing — A-14520', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    // The wrist starts a workout and the phone adopts it, so the phone opens a
    // row for it. The phone then starts its own session, which replaces the
    // session on screen but leaves the adopted row un-ended: a session the
    // phone still holds and is not showing.
    await runner.perform(runner.wristStartsFreeWorkout());
    final wristId = harness.wristEngine.session!.sessionId;
    await harness.phone.createNewSession();
    final phoneId = harness.phone.currentSession!.id;
    await harness.settle();

    final row = await harness.repository.getSession(wristId);
    expect(row, isNotNull, reason: runner.traceText());
    expect(row!.endedAtMs, isNull, reason: 'the phone never ended it');
    expect(harness.phone.currentSession?.id, phoneId);

    final report = await runner.checkConvergence();
    expect(
      report.phoneStatus[harness.labelFor(wristId)],
      WatchSessionStatus.active,
      reason:
          'an un-ended row the phone is not on screen with is a session it '
          'still holds: ${runner.traceText()}',
    );
    expect(report.statusMismatches, isEmpty, reason: runner.traceText());
  });

  test('A-14521 a session only one side ever held is counted, not a '
      'disagreement', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.linkDrops());
    await runner.perform(runner.wristStartsFreeWorkout());
    final wristId = harness.wristEngine.session!.sessionId;
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.phoneStartsSession());
    final phoneId = harness.phone.currentSession!.id;

    final report = await runner.checkConvergence();
    final wristLabel = harness.labelFor(wristId);
    final phoneLabel = harness.labelFor(phoneId);

    expect(
      report.phoneStatus[wristLabel],
      isNull,
      reason:
          'the phone never heard of the wrist workout: ${runner.traceText()}',
    );
    expect(report.wristOnlySessions, contains(wristLabel));
    expect(report.phoneOnlySessions, contains(phoneLabel));
    expect(
      report.statusMismatches,
      isEmpty,
      reason:
          'a session one side never held is not a disagreement: '
          '${runner.traceText()}',
    );
    expect(report.unsharedSummary, contains('wrist-only 1'));
  });

  test('S-14504 a wrist finish while apart is final against the phone\'s later '
      'set', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.linkDrops());
    await runner.perform(runner.wristFinishes());
    await runner.perform(runner.phoneLogsSet());
    final phoneSet = Set<String>.of(
      runner.phoneEntryIds[sessionId] ?? const <String>{},
    );
    expect(
      phoneSet,
      hasLength(1),
      reason: 'the phone logged its set: ${runner.traceText()}',
    );
    expect(
      harness.radio.phoneQueue.where(
        (frame) =>
            frame['type'] == 'session_snapshot' &&
            frame['sessionId'] == sessionId,
      ),
      isNotEmpty,
      reason:
          'the phone, unaware of the end, sends an active snapshot while '
          'apart: ${runner.traceText()}',
    );
    await runner.perform(runner.linkRises());

    final heal = await runner.heal();
    final report = await runner.checkConvergence();
    final label = harness.labelFor(sessionId);

    expect(
      report.phoneStatus[label],
      WatchSessionStatus.completed,
      reason: runner.traceText(),
    );
    expect(
      report.wristStatus[label],
      WatchSessionStatus.completed,
      reason:
          'a finished workout is final: the phone\'s later active snapshot '
          'does not reopen it (S-14504)\n${runner.traceText()}',
    );
    expect(report.statusMismatches, isEmpty, reason: runner.traceText());
    expect(report.absorbingViolations, isEmpty, reason: runner.traceText());
    expect(heal.converged, isTrue, reason: runner.traceText());
    expect(
      runner.wristEntryIds[sessionId],
      containsAll(phoneSet),
      reason:
          'the phone\'s set is on both sides (S-14504)\n'
          '${runner.traceText()}',
    );
    expect(report.entryMismatches, isEmpty, reason: runner.traceText());
  });

  test(
    'S-14506 a phone discard is final against the wrist\'s later set',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      await runner.perform(runner.phoneDiscards());
      await runner.perform(runner.wristLogsSet());
      const wristSet = 'w-entry-1';
      await runner.perform(runner.linkRises());

      final heal = await runner.heal();
      final report = await runner.checkConvergence();
      final label = harness.labelFor(sessionId);

      expect(
        report.phoneStatus[label],
        WatchSessionStatus.abandoned,
        reason: runner.traceText(),
      );
      expect(
        report.wristStatus[label],
        WatchSessionStatus.abandoned,
        reason:
            'the later set does not revive the discarded workout (S-14506)\n'
            '${runner.traceText()}',
      );
      expect(report.statusMismatches, isEmpty, reason: runner.traceText());
      expect(report.absorbingViolations, isEmpty, reason: runner.traceText());
      expect(report.entryMismatches, isEmpty, reason: runner.traceText());
      expect(report.entryDuplicates, isEmpty, reason: runner.traceText());
      expect(report.timerViolations, isEmpty, reason: runner.traceText());
      expect(heal.converged, isTrue, reason: runner.traceText());
      expect(
        runner.wristEntryIds[sessionId],
        contains(wristSet),
        reason:
            'the set stays in the wrist\'s own record (S-14506)\n'
            '${runner.traceText()}',
      );
    },
  );

  test('S-14507 both sides start a rest within the same second: the tally is '
      'measured, not asserted', () async {
    // The gap between the two starts is the measurement's variable: the same
    // instant (the phone and the wrist agree for free), 700 ms apart (the same
    // second, two different start instants) and 20 s apart (A-145-30).
    for (final gap in const [
      Duration.zero,
      Duration(milliseconds: 700),
      Duration(seconds: 20),
    ]) {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneStartsRest());
      harness.clock.advance(gap);
      await runner.perform(runner.wristStartsRest());
      await runner.perform(runner.linkRises());

      await runner.heal();
      final report = await runner.checkConvergence();
      final label = harness.labelFor(sessionId);

      final phoneTimers = _timersOf(harness.graph.mirror.state['timers']);
      final snapshot = harness.wristEngine.sessionSnapshot();
      final payload = snapshot?['payload'];
      final wristTimers = _timersOf(payload is Map ? payload['timers'] : null);

      // The count is the measurement that decides the timer-owner question
      // (D-14507): recorded, never asserted as agreement.
      print(
        'S-14507 gap ${gap.inMilliseconds} ms: timer tally '
        '${report.timerDisagreements} disagreement(s) on $label\n'
        '  phone timers: $phoneTimers\n  wrist timers: $wristTimers',
      );

      expect(
        report.timerDisagreements,
        isNonNegative,
        reason: 'the tally is reported:\n${runner.traceText()}',
      );
      expect(
        report.phoneStatus[label],
        WatchSessionStatus.active,
        reason: 'the session stays live (S-14507)\n${runner.traceText()}',
      );
      expect(
        report.wristStatus[label],
        WatchSessionStatus.active,
        reason: 'the session stays live (S-14507)\n${runner.traceText()}',
      );
    }
  });
}

/// A side's timer map by kind: the phone's mirror state's `timers`, the wrist's
/// session-snapshot payload's `timers` (D-14514).
Map<String, Object?> _timersOf(Object? timers) =>
    timers is Map ? timers.cast<String, Object?>() : const {};

/// The engine a factory seam test injects: a real `WatchSessionEngine` that

// A-145-22 and A-145-23 are logged in the plan.
void _triageFaultTests() {
  test('H6 a phone discard after the end is not an action the app offers '
      '— A-14522', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.wristFinishes());
    await runner.perform(runner.phoneDiscards());
    await runner.heal();
    final report = await runner.checkConvergence();

    final label = harness.labelFor(sessionId);
    expect(report.statusMismatches, isEmpty, reason: runner.traceText());
    expect(report.phoneStatus[label], WatchSessionStatus.completed);
    expect(await harness.repository.getSession(sessionId), isNotNull);
  });

  test('H7 two wrist workouts never share a slot id — A-14523', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.wristStartsFreeWorkout());
    final first = harness.wristEngine.session!.exercises.first;
    await runner.perform(runner.wristFinishes());
    await runner.perform(runner.wristStartsFreeWorkout());
    final second = harness.wristEngine.session!.exercises.first;
    expect(second['sessionExerciseId'], isNot(first['sessionExerciseId']));

    await runner.perform(runner.phoneLogsSet());
    await runner.heal();
    final report = await runner.checkConvergence();
    expect(report.entryMismatches, isEmpty, reason: runner.traceText());
  });
}

// Plan 145 Phase B2: the scripted convergence scenarios S-14511…S-14517.
// Guards assert; the two measurements (S-14512, S-14513) record what the pair
// does. Every guard is proven by a deliberate break recorded in the plan's
// evidence file.
void _b2Tests() {
  test(
    'S-14511 a queued observation survives the wrist app being killed',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.wristStartsFreeWorkout());
      final sessionId = harness.wristEngine.session!.sessionId;
      expect(
        harness.phone.currentSession?.id,
        sessionId,
        reason: 'the phone adopted the wrist workout\n${runner.traceText()}',
      );

      await runner.perform(runner.linkDrops());
      await runner.perform(runner.wristLogsSet());
      final entryId = harness.wristEngine.entries.single.entryId;
      expect(
        harness.radio.wristQueue.any((f) => f['type'] == 'observations_up'),
        isTrue,
        reason:
            'the set is queued for the phone while the link is down\n'
            '${runner.traceText()}',
      );

      await runner.perform(runner.wristFinishes());
      await runner.perform(runner.wristKilled());

      await runner.heal();
      final report = await runner.checkConvergence();
      final label = harness.labelFor(sessionId);

      expect(report.healConverged, isTrue, reason: runner.traceText());
      expect(report.statusMismatches, isEmpty, reason: runner.traceText());
      expect(
        report.absorbingViolations,
        isEmpty,
        reason: 'the end stays final\n${runner.traceText()}',
      );
      expect(
        report.phoneStatus[label],
        WatchSessionStatus.completed,
        reason: runner.traceText(),
      );
      expect(
        report.wristStatus[label],
        WatchSessionStatus.completed,
        reason: runner.traceText(),
      );
      expect(report.phoneOnlySessions, isEmpty, reason: runner.traceText());
      expect(report.wristOnlySessions, isEmpty, reason: runner.traceText());
      expect(
        report.sessionCount,
        1,
        reason: 'one workout, one session\n${runner.traceText()}',
      );
      expect(report.entryMismatches, isEmpty, reason: runner.traceText());
      final inbox = await harness.repository.getWatchInboxEntriesForSession(
        sessionId,
      );
      expect(
        inbox.map((entry) => entry.entryId),
        contains(entryId),
        reason:
            'the queued observation reached the phone after the kill\n'
            '${runner.traceText()}',
      );
      expect(runner.wristEntryIds[sessionId], contains(entryId));
    },
  );

  test(
    'S-14512 a phone end against a wrist abandon while apart is recorded',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      expect(
        harness.wristEngine.session?.sessionId,
        sessionId,
        reason: 'the wrist holds the phone workout\n${runner.traceText()}',
      );

      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneFinishes());
      await runner.perform(runner.wristDiscards());
      await runner.perform(runner.linkRises());

      await runner.heal();
      final report = await runner.checkConvergence();
      final label = harness.labelFor(sessionId);

      // The product of this measurement: the pair's own last word per side.
      print(
        'S-14512 final statuses: phone ${report.phoneStatus[label]} '
        'wrist ${report.wristStatus[label]}, '
        '${report.statusMismatches.length} mismatch(es), '
        '${report.entryMismatches.length} entry mismatch(es)',
      );

      expect(
        report.absorbingViolations,
        isEmpty,
        reason: 'an end is final on each side\n${runner.traceText()}',
      );
      // Plan 161 (D-16102) put the wrist and the phone's frames on the pair's
      // one clock; the phone's own session row is still stamped by
      // `WorkoutState`'s wall clock, which no seam reaches (A-161-05). Re-read
      // on the grid the ends are therefore ordered as follows:
      // - the wrist's discard is on the pair's grid, the finished row's end is
      //   the wall clock, so D-14630 still reads the discard as the earlier end
      //   and the finished row goes — the phone reads `abandoned`;
      // - the phone's `completed` frame carries the same grid instant as the
      //   wrist's discard, so D-14601's tie-break keeps the finish on the wrist.
      // The check reports that disagreement; it is not a within-tolerance tie
      // (the two stamps are nearly four days apart). Recorded as residue.
      expect(
        report.phoneStatus[label],
        WatchSessionStatus.abandoned,
        reason: 'the wrist\'s earlier discard wins\n${runner.traceText()}',
      );
      expect(
        report.wristStatus[label],
        WatchSessionStatus.completed,
        reason:
            'the phone\'s finish and the wrist\'s discard are one instant, '
            'so the finish wins\n${runner.traceText()}',
      );
      expect(
        report.statusMismatches,
        hasLength(1),
        reason: 'the pair disagrees, and the check says so: '
            '${runner.traceText()}',
      );
      expect(report.converged, isFalse, reason: runner.traceText());
      expect(
        await harness.repository.getSession(sessionId),
        isNull,
        reason: 'a winning discard deletes the finished workout (D-14632)',
      );
    },
  );

  test(
    'S-14660 the wrist\'s own workout is saved as its own finished workout '
    'while the phone\'s stays open',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      // Two workouts open at once, one per device (O-6): the link is down while
      // each side starts its own, so neither start reaches the other.
      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneStartsSession());
      final p1 = harness.phone.currentSession!.id;
      await runner.perform(runner.phoneLogsSet());
      await runner.perform(runner.wristStartsFreeWorkout());
      final w2 = harness.wristEngine.session!.sessionId;
      expect(
        w2,
        isNot(p1),
        reason: 'the wrist started its own workout\n${runner.traceText()}',
      );
      const wristSet = 'w-entry-1';
      await runner.perform(runner.wristLogsSet());
      await runner.perform(runner.wristFinishes());
      await runner.perform(runner.linkRises());

      final heal = await runner.heal();
      final report = await runner.checkConvergence();
      final phoneLabel = harness.labelFor(p1);
      final wristLabel = harness.labelFor(w2);

      expect(
        harness.phone.currentSession?.id,
        p1,
        reason:
            'O-6 the phone keeps its own open workout, still on screen\n'
            '${runner.traceText()}',
      );
      expect(
        (await harness.repository.getSession(p1))?.endedAtMs,
        isNull,
        reason:
            'O-6 nothing adopted the wrist\'s workout, and the phone\'s own '
            'was never ended\n${runner.traceText()}',
      );
      expect(
        report.phoneStatus[phoneLabel],
        WatchSessionStatus.active,
        reason:
            'O-6 the phone\'s own workout is still the open one\n'
            '${runner.traceText()}',
      );

      final saved = await harness.repository.getSession(w2);
      expect(
        saved,
        isNotNull,
        reason:
            'O-6 the wrist\'s workout is saved as its own finished workout\n'
            '${runner.traceText()}',
      );
      expect(
        saved!.endedAtMs,
        isNotNull,
        reason: 'O-6 with the wrist\'s own end\n${runner.traceText()}',
      );
      expect(
        report.phoneStatus[wristLabel],
        WatchSessionStatus.completed,
        reason: 'O-6 finished on the phone\n${runner.traceText()}',
      );
      expect(
        report.wristStatus[wristLabel],
        WatchSessionStatus.completed,
        reason: 'O-6 finished on the wrist\n${runner.traceText()}',
      );
      expect(
        runner.phoneEntryIds[w2],
        contains(wristSet),
        reason:
            'O-6 the set the wrist logged reaches the imported workout\n'
            '${runner.traceText()}',
      );
      expect(
        runner.wristEntryIds[w2],
        contains(wristSet),
        reason: 'O-6 and stays in the wrist\'s own record',
      );
      expect(
        report.entryMismatches,
        isEmpty,
        reason: 'O-6 no set is missing on either side\n${runner.traceText()}',
      );
      expect(
        report.absorbingViolations,
        isEmpty,
        reason:
            'O-6 nothing is deleted and nothing reopens\n${runner.traceText()}',
      );
      expect(
        report.statusMismatches,
        isEmpty,
        reason: 'O-6 the two sides agree\n${runner.traceText()}',
      );
      expect(heal.converged, isTrue, reason: runner.traceText());
    },
  );

  test('S-14513 an owed W1 end survives W2 starting on the wrist', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.wristStartsFreeWorkout());
    final w1 = harness.wristEngine.session!.sessionId;
    await runner.perform(runner.wristLogsSet());
    expect(
      harness.phone.currentSession?.id,
      w1,
      reason: 'the phone holds W1\n${runner.traceText()}',
    );

    await runner.perform(runner.linkDrops());
    await runner.perform(runner.wristFinishes());
    await runner.perform(runner.wristStartsFreeWorkout());
    final w2 = harness.wristEngine.session!.sessionId;
    expect(w2, isNot(w1));
    await runner.perform(runner.linkRises());

    await runner.heal();
    final report = await runner.checkConvergence();
    final l1 = harness.labelFor(w1);
    final l2 = harness.labelFor(w2);

    expect(
      report.phoneStatus[l1],
      WatchSessionStatus.completed,
      reason: 'W1\'s end arrived after W2 started\n${runner.traceText()}',
    );
    expect(
      report.wristStatus[l1],
      WatchSessionStatus.completed,
      reason: runner.traceText(),
    );
    expect(
      report.phoneStatus[l2],
      WatchSessionStatus.active,
      reason: 'W2 is live on the phone\n${runner.traceText()}',
    );
    expect(
      report.wristStatus[l2],
      WatchSessionStatus.active,
      reason: runner.traceText(),
    );
    expect(
      report.absorbingViolations,
      isEmpty,
      reason: 'W1 is never active again\n${runner.traceText()}',
    );
    expect(report.statusMismatches, isEmpty, reason: runner.traceText());
    expect(report.entryMismatches, isEmpty, reason: runner.traceText());
    expect(report.healConverged, isTrue, reason: runner.traceText());
  });

  test(
    'S-14514 the phone re-offers an owed end once per 30 s window',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      // The wrist never holds this session: it is started while the link is
      // down, so the wrist cannot answer the re-offer with an end of its own
      // (plan 160 D-16002), which would drive a second offer in the very window
      // this scenario measures. What is timed here is the ledger's pacing.
      await runner.perform(runner.linkDrops());
      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      expect(
        harness.wristEngine.session?.sessionId,
        isNull,
        reason: 'the wrist never saw the session\n${runner.traceText()}',
      );

      await runner.perform(runner.phoneFinishes());
      expect(
        harness.radio.phoneQueue.any((f) => f['type'] == 'session_lifecycle'),
        isTrue,
        reason:
            'the end is owed while the wrist is unreachable\n'
            '${runner.traceText()}',
      );
      // The owed end's own send stamped the 30 s window, so the first wrist
      // frame that can be answered comes one window later (plan 128 D-1 iv).
      await runner.perform(runner.advanceTime(31));
      // Reachable without the LinkRises drain: the queued copy is withdrawn by
      // the first live re-offer (D-14512), so every delivered end below is a
      // re-offer and not the queue.
      harness.radio.reachable = true;
      await harness.settle();

      final beforeFirst = harness.radio.frames.length;
      await _wristEnergyFrame(harness, sessionId);
      final firstWindow = _completedEndsSince(harness, beforeFirst);
      await runner.perform(runner.advanceTime(31));
      final beforeSecond = harness.radio.frames.length;
      await _wristEnergyFrame(harness, sessionId);
      final secondWindow = _completedEndsSince(harness, beforeSecond);

      expect(
        firstWindow,
        hasLength(1),
        reason:
            'one owed end re-offered for the first window\n'
            '${runner.traceText()}',
      );
      expect(
        secondWindow,
        hasLength(1),
        reason:
            'one owed end re-offered after the next 30 s window\n'
            '${runner.traceText()}',
      );

      await runner.heal();
      final report = await runner.checkConvergence();
      final label = harness.labelFor(sessionId);
      expect(
        report.phoneStatus[label],
        WatchSessionStatus.completed,
        reason: runner.traceText(),
      );
      expect(
        report.wristStatus[label],
        WatchSessionStatus.completed,
        reason: runner.traceText(),
      );
      expect(
        report.absorbingViolations,
        isEmpty,
        reason: 'the re-offer never reopens the end\n${runner.traceText()}',
      );
      expect(report.entryMismatches, isEmpty, reason: runner.traceText());
    },
  );

  test('S-14515 a run over the empty fixture space holds nothing and breaks '
      'nothing', () async {
    final run = await ConvergenceRun.runSeed(
      7,
      allowedActions: kNoSessionActions,
      length: 40,
    );

    expect(run.actions, hasLength(40));
    expect(run.pair.failures, isEmpty, reason: run.trace);
    expect(run.report.failures, isEmpty, reason: run.trace);
    expect(
      run.report.sessionCount,
      0,
      reason: 'no action starts a session\n${run.trace}',
    );
    expect(run.report.phoneStatus, isEmpty, reason: run.trace);
    expect(run.report.wristStatus, isEmpty, reason: run.trace);
    expect(run.heal.converged, isTrue, reason: run.trace);
  });

  test(
    'S-14516 a refused durable snapshot is queued and still arrives',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      expect(
        harness.wristEngine.session?.sessionId,
        sessionId,
        reason: 'the wrist holds the session\n${runner.traceText()}',
      );

      await runner.perform(
        runner.refuseNext(from: PairActor.phone, type: 'session_snapshot'),
      );
      await runner.perform(runner.phoneLogsSet());

      final refused = harness.radio.frames
          .where(
            (f) =>
                f.lane == PairLane.phoneToWrist &&
                f.type == 'session_snapshot' &&
                f.refused,
          )
          .toList();
      expect(
        refused,
        isNotEmpty,
        reason: 'the refusal fired\n${runner.traceText()}',
      );
      expect(
        refused.first.outcome,
        WatchDelivery.queued,
        reason:
            'a durable frame the radio refuses is still owed (D-14515)\n'
            '${runner.traceText()}',
      );
      expect(
        harness.radio.phoneQueue.any((f) => f['type'] == 'session_snapshot'),
        isTrue,
        reason:
            'the refused snapshot waits in the queue\n${runner.traceText()}',
      );

      final phoneIds = runner.phoneEntryIds[sessionId] ?? const <String>{};
      expect(phoneIds, isNotEmpty, reason: runner.traceText());

      await runner.heal();
      final report = await runner.checkConvergence();
      expect(report.converged, isTrue, reason: runner.traceText());
      expect(report.entryMismatches, isEmpty, reason: runner.traceText());
      expect(
        runner.wristEntryIds[sessionId] ?? const <String>{},
        containsAll(phoneIds),
        reason:
            'the refused snapshot reached the wrist after the heal\n'
            '${runner.traceText()}',
      );
    },
  );

  test(
    'S-14517 a refused non-durable timer push is undelivered and lost',
    () async {
      final harness = await WatchPairHarness.build();
      final runner = harness.runner;

      await runner.perform(runner.phoneStartsSession());
      final sessionId = harness.phone.currentSession!.id;
      expect(
        harness.wristEngine.session?.sessionId,
        sessionId,
        reason: 'the wrist holds the session\n${runner.traceText()}',
      );

      await runner.perform(
        runner.refuseNext(from: PairActor.wrist, type: 'timer_state'),
      );
      await runner.perform(runner.wristStartsRest());

      final refused = harness.radio.frames
          .where(
            (f) =>
                f.lane == PairLane.wristToPhone &&
                f.type == 'timer_state' &&
                f.refused,
          )
          .toList();
      expect(
        refused,
        isNotEmpty,
        reason: 'the wrist started a rest\n${runner.traceText()}',
      );
      expect(
        refused.first.outcome,
        WatchDelivery.undelivered,
        reason:
            'a non-durable frame the radio refuses is not owed (D-14515)\n'
            '${runner.traceText()}',
      );
      expect(
        harness.radio.wristQueue.where((f) => f['type'] == 'timer_state'),
        isEmpty,
        reason: 'nothing keeps a refused timer push\n${runner.traceText()}',
      );
      expect(
        harness.radio.phoneQueue.where((f) => f['type'] == 'timer_state'),
        isEmpty,
        reason: 'nothing re-queues a refused timer push\n${runner.traceText()}',
      );
      // The loss itself: the phone never heard the rest start.
      expect(
        _isRunning(
          _timersOf(harness.graph.mirror.state['timers']),
          WatchTimerKind.rest,
        ),
        isFalse,
        reason:
            'the refused push never reached the phone\n${runner.traceText()}',
      );

      await runner.heal();
      final report = await runner.checkConvergence();
      final phoneTimers = _timersOf(harness.graph.mirror.state['timers']);
      final wristSnapshot = harness.wristEngine.sessionSnapshot();
      final wristTimers = _timersOf(
        wristSnapshot == null ? null : _payloadOf(wristSnapshot)['timers'],
      );
      print(
        'S-14517 timer tally ${report.timerDisagreements}: '
        'phone timers $phoneTimers, wrist timers $wristTimers',
      );
      // The tally reads 0 because the heal's reconnect snapshot carried the
      // rest the refused push lost: the pair ends up agreeing on it, so this
      // loss is invisible to the checks and is recorded here instead.
      expect(
        report.timerDisagreements,
        0,
        reason:
            'the reconnect snapshot repaired the loss\n${runner.traceText()}',
      );
      expect(
        _isRunning(phoneTimers, WatchTimerKind.rest),
        isTrue,
        reason:
            'the phone holds the rest after the heal\n${runner.traceText()}',
      );
      expect(
        _isRunning(wristTimers, WatchTimerKind.rest),
        isTrue,
        reason: 'the wrist holds the rest it started\n${runner.traceText()}',
      );
      expect(report.entryMismatches, isEmpty, reason: runner.traceText());
      expect(
        report.timerViolations,
        isEmpty,
        reason: 'no rest runs on an ended session\n${runner.traceText()}',
      );
    },
  );
}

// Plan 161 Phase 2 (D-16101): check 3 compares wrist entries with wrist entries.
// The phone records every deletion it announces in its own inbox under
// `phone-change-<changeId>-<index>`, and the harness unioned every inbox id into
// the phone's entry set — so a deletion the phone announced for a wrist session
// made check 3 unsatisfiable (plan 158 §3).
void _plan161Tests() {
  group('S-16101 check 3 compares wrist entries with wrist entries', () {
    test(
      'S-16101 a phone deletion annotation for a wrist set is not a wrist '
      'entry the wrist owes',
      () async {
        // Plan 158 §3's shrunk trace: the wrist starts a workout, one live
        // frame of its is refused, and it logs two sets.
        final run = await ConvergenceRun.replayActions([
          WristStartsFreeWorkout(serial: 1),
          RefuseLiveFrame(
            serial: 2,
            from: PairActor.wrist,
            type: 'observations_up',
          ),
          WristLogsSet(serial: 3),
          WristLogsSet(serial: 4),
        ]);
        final sessionId = run.pair.wristEngine.session!.sessionId;
        final label = run.pair.labelFor(sessionId);
        final inbox = await run.pair.repository.getWatchInboxEntriesForSession(
          sessionId,
        );
        expect(
          inbox.map((entry) => entry.entryId),
          anyElement(startsWith('phone-change-')),
          reason:
              'the phone really did announce a deletion for the wrist '
              'session, so the filter has an id to keep out\n${run.trace}',
        );

        final phoneIds = run.runner.phoneEntryIds[sessionId] ?? const <String>{};
        final wristIds = run.runner.wristEntryIds[sessionId] ?? const <String>{};
        print('S-16101 $label phone=$phoneIds wrist=$wristIds');
        expect(
          phoneIds.where((id) => id.startsWith('phone-change-')),
          isEmpty,
          reason:
              'D-16101: a phone record about a wrist entry is not a wrist '
              'entry\n${run.trace}',
        );
        expect(
          phoneIds,
          containsAll(wristIds),
          reason:
              'the sets the wrist logged still reached the phone\n${run.trace}',
        );
        expect(run.report.entryMismatches, isEmpty, reason: '${run.failures}');
        expect(run.converged, isTrue, reason: run.trace);
      },
    );
  });

  group('S-16102 the filter hides no wrist entry the phone lost', () {
    test(
      'S-16102 a wrist set whose live frame is refused after the heal is '
      'still owed to the phone',
      () async {
        final harness = await WatchPairHarness.build();
        final runner = harness.runner;

        await runner.perform(runner.wristStartsFreeWorkout());
        await runner.heal();
        await runner.perform(
          runner.refuseNext(from: PairActor.wrist, type: 'observations_up'),
        );
        await runner.perform(runner.wristLogsSet());
        final entryId = harness.wristEngine.entries.last.entryId;

        final report = await runner.checkConvergence();
        print('S-16102 entry mismatches: ${report.entryMismatches}');
        expect(
          report.entryMismatches,
          contains(
            contains('the phone never held $entryId'),
          ),
          reason:
              'a wrist entry the phone never received is still a mismatch '
              '(D-16101 keeps only the phone\'s own annotation ids out)\n'
              '${runner.traceText()}',
        );
        expect(
          report.entryMismatches.any(
            (line) => line.contains('phone-change-'),
          ),
          isFalse,
          reason:
              'no phone annotation is reported as a wrist entry\n'
              '${runner.traceText()}',
        );
      },
    );
  });

  group('S-16103 two ends within the skew tolerance are a tie', () {
    test(
      'S-16103 the phone discards and the wrist finishes at the same instant: '
      'the ends tie, they do not disagree (owner to confirm)',
      () async {
        // Plan 158 §5's shrunk status trace, with no time advance: the phone's
        // discard and the wrist's finish are stamped from the same clock, so
        // D-15403 cannot tell the two orders apart — the tie-break keeps the
        // wrist's finish, and the phone's row is gone (D-14632).
        final run = await ConvergenceRun.replayActions([
          WristStartsFreeWorkout(serial: 1),
          LinkDrops(serial: 2),
          PhoneDiscards(serial: 3),
          WristFinishes(serial: 4),
        ]);
        final sessionId = run.pair.sessionIds.single;
        final label = run.pair.labelFor(sessionId);
        final phoneEnd = run.runner.phoneEndAtMs[sessionId];
        final wristEnd = run.runner.wristEndAtMs[sessionId];
        print('S-16103 $label phoneEnd=$phoneEnd wristEnd=$wristEnd');
        expect(
          phoneEnd,
          isNotNull,
          reason: 'the phone stamps the discard it performed\n${run.trace}',
        );
        expect(
          wristEnd,
          isNotNull,
          reason: 'the wrist stamps the row it ended\n${run.trace}',
        );
        expect(
          endsWithinSkewToleranceMs(phoneEnd!, wristEnd!),
          isTrue,
          reason:
              'the two ends are inside kEndSkewToleranceMs, which is what '
              'makes this a tie rather than a disagreement (owner to '
              'confirm)\n${run.trace}',
        );
        expect(
          run.report.phoneStatus[label],
          WatchSessionStatus.abandoned,
          reason: 'the discarded row is gone\n${run.trace}',
        );
        expect(
          run.report.wristStatus[label],
          WatchSessionStatus.completed,
          reason:
              'D-15403\'s tie-break keeps the finish on the wrist\n'
              '${run.trace}',
        );
        expect(
          run.report.withinSkewEndTies,
          [label],
          reason:
              'the disagreement is reported as an end tie, not as a status '
              'mismatch (owner to confirm: is a tie convergence?)',
        );
        expect(run.report.statusMismatches, isEmpty, reason: run.trace);
        expect(run.converged, isTrue, reason: run.trace);
      },
    );

    test(
      'S-16104 a discard three seconds before the finish is outside the '
      'tolerance: the tie does not swallow it, the mismatch is reported',
      () async {
        // S-16103's trace with the wrist's finish three seconds later. Both ends
        // are known and 3000 ms apart, so D-16105's tie does not apply and the
        // disagreement stays in `statusMismatches`.
        //
        // Observed, and not what the plan derived (A-161-06): the link is down
        // when the phone discards, so the abandonment reaches the wrist only as
        // the mirror's **re-offer**, which plan 128 D-1 stamps with the mirror's
        // own clock at offer time — 09:00:03 here, the wrist's finish instant.
        // The wrist therefore sees a product-level tie and D-14603's tie-break
        // keeps its finish, while the harness compares the instants the two ends
        // were performed at (t0 vs t3). That gap is a residue of this plan, not
        // of the harness: it is reported, never swallowed.
        final run = await ConvergenceRun.replayActions([
          WristStartsFreeWorkout(serial: 1),
          LinkDrops(serial: 2),
          PhoneDiscards(serial: 3),
          TimeAdvances(serial: 4, seconds: 3),
          WristFinishes(serial: 5),
        ]);
        final sessionId = run.pair.sessionIds.single;
        final label = run.pair.labelFor(sessionId);
        final phoneEnd = run.runner.phoneEndAtMs[sessionId];
        final wristEnd = run.runner.wristEndAtMs[sessionId];
        print('S-16104 $label phoneEnd=$phoneEnd wristEnd=$wristEnd');
        for (final frame in run.pair.radio.frames) {
          if (frame.lane != PairLane.phoneToWrist) continue;
          if (frame.type != 'session_lifecycle') continue;
          final payload = frame.frame['payload'];
          print(
            'S-16104 phone→wrist lifecycle '
            '${payload is Map ? payload['state'] : null} '
            'at=${payload is Map ? payload['at'] : null} '
            '${frame.outcome}',
          );
        }
        expect(
          phoneEnd,
          isNotNull,
          reason: 'the phone stamps the discard\n${run.trace}',
        );
        expect(
          wristEnd,
          isNotNull,
          reason: 'the wrist stamps the finish it took\n${run.trace}',
        );
        expect(
          wristEnd! - phoneEnd!,
          greaterThan(kEndSkewToleranceMs),
          reason:
              'this trace is the outside-the-tolerance case\n${run.trace}',
        );
        expect(
          endsWithinSkewToleranceMs(phoneEnd, wristEnd),
          isFalse,
          reason: 'a three-second gap is not a tie\n${run.trace}',
        );
        expect(
          run.report.withinSkewEndTies,
          isEmpty,
          reason:
              'the tie only absorbs ends within kEndSkewToleranceMs: '
              '${run.report.withinSkewEndTies}',
        );
        expect(
          run.report.statusMismatches,
          hasLength(1),
          reason: 'the disagreement is reported\n${run.trace}',
        );
        expect(
          run.report.statusMismatches.single,
          '$label: phone ${WatchSessionStatus.abandoned} '
          'vs wrist ${WatchSessionStatus.completed}',
          reason:
              'the phone deleted its row and the wrist kept its finish '
              '(A-161-06)\n${run.trace}',
        );
        expect(
          run.converged,
          isFalse,
          reason:
              'a real disagreement outside the tolerance is never converged\n'
              '${run.trace}',
        );
      },
    );
  });
}

// Plan 167 (D-16701/D-16702/D-16704): a wrist-only workout keeps the wrist's
// own start. The phone opens the row when it hears of it (the adoption stamps
// the arrival), so the row's span is zero until the wrist's own end arrives;
// one merge rule then moves the start down to the wrist's start and drops a
// floored end (== the arrival start) to the wrist's end. Two delivery orders,
// one rule.
void _plan167Tests() {
  group('plan 167 the wrist’s own start on the phone', () {
    // The owner's walk (S-16701's fixture).
    final wristStart = DateTime.utc(2026, 11, 14, 22, 17, 21);
    final wristEnd = wristStart.add(const Duration(minutes: 40, seconds: 12));
    int ms(DateTime at) => at.millisecondsSinceEpoch;

    // advanceTime takes 1–90 s (D-14505); the walk needs minutes.
    Future<void> advance(HarnessRunner runner, int seconds) async {
      var left = seconds;
      while (left > 0) {
        final step = left > 90 ? 90 : left;
        await runner.perform(runner.advanceTime(step));
        left -= step;
      }
    }

    test(
      'S-16701 the device’s order: the drained end corrects the adopted start',
      () async {
        final harness = await WatchPairHarness.build(start: wristStart);
        final runner = harness.runner;

        // The wrist runs the whole walk with no link: the phone hears of the
        // workout only when the link comes back, minutes after the wrist ended.
        await runner.perform(runner.linkDrops());
        await runner.perform(runner.wristStartsFreeWorkout());
        final sessionId = harness.wristEngine.session!.sessionId;
        await advance(runner, 1200);
        await runner.perform(runner.wristLogsSet());
        final entryId = harness.wristEngine.entries.single.entryId;
        await advance(runner, 1212);
        await runner.perform(runner.wristFinishes());
        await advance(runner, 562);
        await runner.perform(runner.linkRises());

        final row = await harness.repository.getSession(sessionId);
        expect(
          row,
          isNotNull,
          reason:
              'the wrist’s workout is saved when its end drains\n'
              '${runner.traceText()}',
        );
        expect(
          row!.startedAtMs,
          ms(wristStart),
          reason:
              'S-16701 the row carries the wrist’s own start, not the instant '
              'the phone adopted it\n${runner.traceText()}',
        );
        expect(
          row.endedAtMs,
          ms(wristEnd),
          reason: 'S-16701 with the wrist’s own end\n${runner.traceText()}',
        );
        expect(
          row.endedAtMs! - row.startedAtMs,
          2412000,
          reason:
              'S-16701 the span is the wrist’s 40 m 12 s\n'
              '${runner.traceText()}',
        );
        expect(
          row.isRolling,
          isFalse,
          reason: 'S-16701 the walk is finished\n${runner.traceText()}',
        );
        expect(
          runner.phoneEntryIds[sessionId],
          contains(entryId),
          reason:
              'S-16701 the set the wrist logged merges into the row\n'
              '${runner.traceText()}',
        );
      },
    );

    test(
      'S-16702 the reversed order: the terminal lifecycle first, then the '
      'end’s merge repairs the row',
      () async {
        final harness = await WatchPairHarness.build(start: wristStart);
        final runner = harness.runner;

        await runner.perform(runner.linkDrops());
        await runner.perform(runner.wristStartsFreeWorkout());
        final sessionId = harness.wristEngine.session!.sessionId;
        await advance(runner, 1200);
        await runner.perform(runner.wristLogsSet());
        await advance(runner, 1);
        // The adoption opens the row at 22:37:22.
        await runner.perform(runner.linkRises());
        expect(
          await harness.repository.getSession(sessionId),
          isNotNull,
          reason:
              'the adoption opened the row while the wrist ran\n'
              '${runner.traceText()}',
        );

        // 22:37:22 + 1211 s = 22:57:33, the owner's end (the plan's 1201 is a
        // ten-second slip; see the Assumption Log).
        await advance(runner, 1211);
        // The end's `observations_up` is refused live and queues; the terminal
        // lifecycle is delivered first.
        await runner.perform(
          runner.refuseNext(from: PairActor.wrist, type: 'observations_up'),
        );
        await runner.perform(runner.wristFinishes());
        await advance(runner, 540);
        await runner.perform(runner.linkRises());

        final row = await harness.repository.getSession(sessionId);
        expect(
          row,
          isNotNull,
          reason: 'the row the adoption opened stays\n${runner.traceText()}',
        );
        expect(
          row!.startedAtMs,
          ms(wristStart),
          reason:
              'S-16702 the end’s merge corrects the arrival start however the '
              'lifecycle landed\n${runner.traceText()}',
        );
        expect(
          row.endedAtMs,
          ms(wristEnd),
          reason:
              'S-16702 a floored end (== the arrival start) drops to the '
              'wrist’s end\n${runner.traceText()}',
        );
        expect(
          row.endedAtMs! - row.startedAtMs,
          2412000,
          reason: 'S-16702 the span is the wrist’s\n${runner.traceText()}',
        );
        expect(
          row.isRolling,
          isFalse,
          reason: 'S-16702 the walk is finished\n${runner.traceText()}',
        );
      },
    );
  });
}

/// One wrist `energy_live` frame: the live holder's frame that makes the phone
/// re-offer an owed end (plan 128 D-1 iv), shaped as the harness's heal sends
/// it.
Future<void> _wristEnergyFrame(
  WatchPairHarness harness,
  String sessionId,
) async {
  final stamp = utcIso(harness.clock.now);
  await harness.radio.deliverFromWrist({
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': harness.nextMessageId(),
    'sessionId': sessionId,
    'type': 'energy_live',
    'origin': 'watch',
    'sentAt': stamp,
    'payload': <String, Object?>{'activeEnergyKcal': 12.5, 'at': stamp},
  });
  await harness.settle();
}

Map<String, Object?> _payloadOf(Map<String, Object?> frame) {
  final payload = frame['payload'];
  return payload is Map ? payload.cast<String, Object?>() : const {};
}

/// The delivered `completed` lifetime frames on the phone→wrist lane since
/// [from], i.e. the end the phone re-offered.
List<PairFrame> _completedEndsSince(WatchPairHarness harness, int from) =>
    harness.radio.frames
        .sublist(from)
        .where(
          (f) =>
              f.lane == PairLane.phoneToWrist &&
              f.type == 'session_lifecycle' &&
              f.outcome == WatchDelivery.delivered &&
              _payloadOf(f.frame)['state'] == 'completed',
        )
        .toList();

bool _isRunning(Map<String, Object?> timers, String kind) {
  final timer = timers[kind];
  return timer is Map && timer['state'] == WatchTimerState.running;
}

/// counts the messages it was asked to apply.
class _CountingWristEngine extends WatchSessionEngine {
  _CountingWristEngine(WristEngineArgs args)
    : super(
        args.store,
        onEmit: args.onEmit,
        validator: args.validator,
        clock: args.clock,
        idFactory: args.idFactory,
        sessionIdFactory: args.sessionIdFactory,
      );

  int applied = 0;

  @override
  Future<bool> applyMessage(Map<String, Object?> envelope) {
    applied++;
    return super.applyMessage(envelope);
  }
}
