// Plan 163 Phase 3: the phone kill's semantics, scripted.
//
// Plan: `docs/plans/2026-11-14-163-kill-cases-in-the-sweep-plan/2026-11-14-163-kill-cases-in-the-sweep-plan.md`
// (D-16301…D-16303; S-16302…S-16307).
// Harness: `test/helpers/watch_pair_harness.dart` (`phoneKilledAndRelaunched`).
//
// Every test scripts the actions the scenario names on a real pair and then
// reads the four checks, so a kill is judged by the same rules as any other
// traffic (the plan's Non-synthetic invariant): kills get no special reading.
// ignore_for_file: avoid_print
//
// Plain `test()` throughout: `testWidgets` runs inside FakeAsync, where the
// engine's and the graph's real awaits never complete.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/watch_pair_harness.dart';

void main() {
  // S-16302. The fidelity case: the phone dies before it ever hears the set
  // the wrist logged while the link was down, so the rebuilt mirror holds no
  // ledger for that session and has to find the rows through the stored-row
  // path (plan 128 D-3) after the heal's reconnect sync.
  test('S-16302 the owed end survives a phone kill', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.wristStartsFreeWorkout());
    final sessionId = harness.wristEngine.session!.sessionId;
    await runner.perform(runner.linkDrops());
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.phoneKilledAndRelaunched());
    await runner.perform(runner.linkRises());

    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(
      heal.converged,
      isTrue,
      reason:
          'the heal reaches a fixed point after the phone was replaced\n'
          '${runner.traceText()}',
    );
    expect(
      report.statusMismatches,
      isEmpty,
      reason:
          'check 1 agrees on the wrist\'s session $sessionId even though the '
          'mirror lost its ledger for it\n${runner.traceText()}',
    );
    expect(
      report.entryDuplicates,
      isEmpty,
      reason:
          'a set is exposed once per side (O-1), not once per mirror\n'
          '${runner.traceText()}',
    );
    expect(
      report.converged,
      isTrue,
      reason:
          'entries ${report.entryMismatches} from the stored-row path\n'
          '${runner.traceText()}',
    );
  });

  // S-16303. O-2 / D-15403 / D-15405: the phone's own finish happened while the
  // link was down, so both ends are stamped on the pair clock's instants. The
  // kill destroys the mirror's fates for the session; the rebuilt phone reads
  // its own finished row from the repository. Same-instant ends compare as a
  // terminal tie (completed wins), and a finished workout is never active again.
  test('S-16303 the first ending survives a phone kill', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.linkDrops());
    await runner.perform(runner.phoneFinishes());
    await runner.perform(runner.phoneKilledAndRelaunched());
    await runner.perform(runner.linkRises());

    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(
      heal.converged,
      isTrue,
      reason: 'the heal settles after the phone restart\n${runner.traceText()}',
    );
    expect(
      report.absorbingViolations,
      isEmpty,
      reason:
          'check 2: no side reports the finished session active again, and '
          'the ends resolve inside the D-15403 tolerance\n'
          '${runner.traceText()}',
    );
    expect(
      report.phoneStatus[harness.labelFor(sessionId)],
      WatchSessionStatus.completed,
      reason:
          'the rebuilt phone asserts the end its own row carries\n'
          '${runner.traceText()}',
    );
    expect(
      report.statusMismatches,
      isEmpty,
      reason: runner.traceText(),
    );
    expect(await harness.repository.getSession(sessionId), isNotNull);
  });

  // S-16304. The phone STAGED the wrist's entries (repository-backed rows) and
  // died before the session's end applied. The relaunched inbox is a fresh
  // object over the same repository, so the staged rows survive and the import
  // pass completes at the heal: each entry reaches history once, and nothing
  // staged resurfaces as a phantom workout (plan 146's watch-out).
  test('S-16304 staged inbox rows survive the phone\'s death', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.wristStartsFreeWorkout());
    final sessionId = harness.wristEngine.session!.sessionId;
    await runner.perform(runner.linkDrops());
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.wristLogsSet());
    await runner.perform(runner.linkRises());
    await runner.perform(runner.linkDrops());
    await runner.perform(runner.wristFinishes());

    final stagedBefore = await harness.repository
        .getWatchInboxEntriesForSession(sessionId);
    print('S-16304 staged before the kill: ${stagedBefore.length} rows');
    expect(
      stagedBefore,
      isNotEmpty,
      reason:
          'the fixture needs rows the phone staged but did not apply — a kill '
          'over an empty inbox proves nothing\n${runner.traceText()}',
    );

    await runner.perform(runner.phoneKilledAndRelaunched());
    final stagedAfter = await harness.repository.getWatchInboxEntriesForSession(
      sessionId,
    );
    expect(
      stagedAfter.map((row) => row.entryId).toList()..sort(),
      stagedBefore.map((row) => row.entryId).toList()..sort(),
      reason:
          'the staged rows live in the repository, so the kill keeps them '
          '(D-16302)\n${runner.traceText()}',
    );

    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(heal.converged, isTrue, reason: runner.traceText());
    expect(
      report.entryDuplicates,
      isEmpty,
      reason:
          'each staged entry reaches history once\n${runner.traceText()}',
    );
    expect(
      report.entryMismatches,
      isEmpty,
      reason:
          'the resumed import pass imports exactly the rows the wrist still '
          'exposes\n${runner.traceText()}',
    );
    final stagedAfterHeal = await harness.repository
        .getWatchInboxEntriesForSession(sessionId);
    expect(
      stagedAfterHeal.where((row) => row.appliedAtMs == null),
      isEmpty,
      reason:
          'the resumed import pass applied every staged row once; the rows '
          'stay as applied tombstones (a stored row is never deleted)\n'
          '${runner.traceText()}',
    );
    expect(
      await harness.repository.getWatchSessionIdsWithUnappliedEnd(),
      isNot(contains(sessionId)),
      reason:
          'the session\'s end was applied, not left queued for the next '
          'launch\n${runner.traceText()}',
    );
    expect(
      (await harness.repository.getAllSessions()).map((row) => row.id),
      [sessionId],
      reason:
          'the reused inbox produced no phantom workout\n'
          '${runner.traceText()}',
    );
    expect(
      (await harness.repository.getSession(sessionId))?.endedAtMs,
      isNotNull,
      reason:
          'the imported session is the one the wrist finished\n'
          '${runner.traceText()}',
    );
  });

  // S-16305. The empty-state sibling: both kills on a pair that never started a
  // session add nothing and lose nothing.
  test('S-16305 a kill on an idle pair is a no-op', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneKilledAndRelaunched());
    await runner.perform(runner.wristKilled());

    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(
      heal.converged,
      isTrue,
      reason: 'an idle pair is a fixed point\n${runner.traceText()}',
    );
    expect(
      report.failures,
      isEmpty,
      reason: 'no session, entry or timer appears from a kill\n'
          '${runner.traceText()}',
    );
    expect(harness.phone.currentSession, isNull);
    expect(await harness.repository.getAllSessions(), isEmpty);
    expect(
      harness.graph.timerPush.snapshotTimers(),
      isEmpty,
      reason: 'a restart pushes no timer it does not hold',
    );
  });

  // S-16306. A kill does not touch the radio (D-16302): the frame the phone
  // queued before the link dropped is still the same queued frame afterwards,
  // so its fate is the one it would have had without the kill.
  test('S-16306 a phone kill while the link is down', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.wristStartsFreeWorkout());
    await runner.perform(runner.linkDrops());
    await runner.perform(runner.phoneLogsSet());
    final queuedBefore = harness.radio.phoneQueue.toList();
    expect(
      queuedBefore,
      isNotEmpty,
      reason: 'the fixture needs a queued frame to carry over\n'
          '${runner.traceText()}',
    );

    await runner.perform(runner.phoneKilledAndRelaunched());
    expect(
      harness.radio.phoneQueue,
      containsAll(queuedBefore),
      reason:
          'the queues are the radio\'s, not the mirror\'s; the relaunch does '
          'not withdraw or rewrite them (D-16302)',
    );

    await runner.perform(runner.linkRises());
    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(heal.converged, isTrue, reason: runner.traceText());
    expect(
      report.statusMismatches,
      isEmpty,
      reason: runner.traceText(),
    );
    expect(
      report.entryDuplicates,
      isEmpty,
      reason: runner.traceText(),
    );
  });

  // S-16307. Two relaunches in a row: the second is another fresh start — a
  // fresh bridge over the repository, with the bindings of the first gone, not
  // doubled. Then the wrist dies as well and the heal still converges.
  test('S-16307 double kill is idempotent', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.phoneKilledAndRelaunched());
    await runner.perform(runner.phoneKilledAndRelaunched());
    await runner.perform(runner.wristKilled());

    final heal = await runner.heal();
    final report = await runner.checkConvergence();

    expect(heal.converged, isTrue, reason: runner.traceText());
    expect(
      report.absorbingViolations,
      isEmpty,
      reason:
          'the second relaunch did not resurrect an ending the first already '
          'applied\n${runner.traceText()}',
    );
    expect(
      report.entryDuplicates,
      isEmpty,
      reason:
          'one binding per push, so a set is not exposed twice\n'
          '${runner.traceText()}',
    );
    expect(report.phoneOnlySessions, isEmpty, reason: runner.traceText());
    expect(await harness.repository.getSession(sessionId), isNotNull);
  });

  // S-16302's other half, and the brief's focused guard: the relaunched phone
  // must keep the pair clock (`_gridClock`, plan 169 D-16904) rather than
  // stamping from the wall clock. A `DateTime.now()` here would put the end
  // days away from every other stamp in the run.
  test('S-16302 the relaunched phone\'s stamps stay on the pair clock', () async {
    final harness = await WatchPairHarness.build();
    final runner = harness.runner;

    await runner.perform(runner.phoneStartsSession());
    final sessionId = harness.phone.currentSession!.id;
    await runner.perform(runner.phoneLogsSet());
    await runner.perform(runner.phoneKilledAndRelaunched());
    await runner.perform(runner.phoneFinishes());

    final row = await harness.repository.getSession(sessionId);
    final endedAtMs = row!.endedAtMs;
    final nowMs = harness.clock.now.millisecondsSinceEpoch;
    expect(
      endedAtMs,
      isNotNull,
      reason:
          'the relaunched phone still owns the session its row carries\n'
          '${runner.traceText()}',
    );
    expect(
      (endedAtMs! - nowMs).abs(),
      lessThanOrEqualTo(100),
      reason:
          'the ended row is stamped by the pair clock the relaunch keeps '
          '(D-16904): ended at $endedAtMs, the clock holds $nowMs\n'
          '${runner.traceText()}',
    );
  });
}
