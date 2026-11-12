// The sweep's report is its product: every print is a finding (D-14508).
// ignore_for_file: avoid_print
// Plan 145 Phase B, part 1: the seeded random run, the shrinker, and the seams
// the mutation proofs use.
//
// Plan: `docs/plans/2026-11-10-145-convergence-test-plan/2026-11-10-145-convergence-test-plan.md`
// (D-14503, D-14508, D-14509, D-14510; S-14510).
// Harness: `test/helpers/watch_pair_harness.dart` (`ConvergenceRun`).
//
// The sweep is the measurement; the contract is the second test. Since plan 146
// Phase 5.Y the contract is asserted: every seed converges, or every divergence
// it reports belongs to a class the plan names with the fix that owns it, and a
// seed that only diverges after D-14513's harness-only re-assert is listed by
// seed instead of hidden.
//
// Plain `test()` throughout: `testWidgets` runs inside FakeAsync, where the
// engine's and the graph's real awaits never complete.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/session/watch_records.dart'
    show WatchLifecycleState;
import 'package:omnitrain/watch/session/watch_session_engine.dart'
    show WatchEmissionRejected, WatchSessionEngine;

import 'helpers/watch_pair_harness.dart';

/// How many seeds the sweep runs (D-14510). More for a soak:
/// `flutter test test/watch_convergence_random_test.dart
/// --dart-define=CONVERGENCE_SEEDS=2000`.
const int kSeedCount = int.fromEnvironment(
  'CONVERGENCE_SEEDS',
  defaultValue: 200,
);

/// Prints one line per seed (`seed=N kinds=...`) so two processes can be
/// diffed line by line (D-14503):
/// `--dart-define=CONVERGENCE_VERBOSE=true`.
const bool kVerbose = bool.fromEnvironment('CONVERGENCE_VERBOSE');

/// Re-runs one seed exactly as the sweep does, so a failing seed can be
/// reproduced on its own.
Future<ConvergenceRun> replay(int seed) => ConvergenceRun.runSeed(seed);

void main() {
  test(
    'the allowed-actions seam produces only the kinds it is given',
    () async {
      for (final seed in [1, 2, 3, 4, 5]) {
        final run = await ConvergenceRun.runSeed(
          seed,
          allowedActions: kNoSessionActions,
        );
        final outside = run.actions
            .where((action) => !kNoSessionActions.contains(action.runtimeType))
            .map((action) => action.describe())
            .toList();
        expect(outside, isEmpty, reason: 'seed=$seed\n${run.trace}');
        expect(run.actions, isNotEmpty, reason: 'seed=$seed generated nothing');
      }
      expect(
        () => ConvergenceRun.runSeed(1, allowedActions: const {}),
        throwsArgumentError,
        reason: 'an empty fixture space is a mistake, not a run of nothing',
      );
    },
  );

  test('S-14502 a seeded run reads the same twice', () async {
    final first = await replay(11);
    final second = await replay(11);

    expect(second.trace, first.trace, reason: 'the same seed reads the same');
    expect(
      second.report.toString(),
      first.report.toString(),
      reason: 'the same seed converges, or diverges, the same way',
    );
    expect(second.actions.length, first.actions.length);
    expect(second.heal.converged, first.heal.converged);
  });

  test('S-14509 the random seeds: the harness is healthy and every seed is '
      'accounted for', () async {
    final diverging = <String>[];
    final kinds = <String, int>{};
    final healStalls = <int>[];
    final harnessFaults = <String>[];
    final rejections = <String>[];
    final rejectionCounts = <int, int>{};
    final runaways = <int>[];
    for (var seed = 1; seed <= kSeedCount; seed++) {
      final ConvergenceRun run;
      try {
        run = await replay(seed);
      } catch (error) {
        harnessFaults.add('seed=$seed the run threw $error');
        continue;
      }
      if (run.pair.radio.runaway) runaways.add(seed);

      final runKinds = _kindsOf(run);
      if (kVerbose) print('seed=$seed kinds=${runKinds.join(',')}');
      for (final kind in runKinds) {
        kinds[kind] = (kinds[kind] ?? 0) + 1;
      }
      if (!run.converged) {
        diverging.add(
          'seed=$seed ${runKinds.join(',')}\n'
          '${run.trace}\n'
          '${run.failures.join('\n')}',
        );
      }
      // A heal that never settles is a finding about the pair, not a harness
      // fault: it means the two sides keep answering each other and never
      // agree (D-14508 ships both kinds the same way). Reported, not asserted.
      if (!run.heal.converged && !run.usedSyntheticAction) {
        healStalls.add(seed);
      }
      // A failure the pair's own error hook reported is a harness fault unless
      // it is a frame the other side refused as non-conformant: that is the
      // pair composing or emitting a bad payload, which is a finding (D-14508).
      for (final failure in run.pair.failures) {
        if (failure is WatchEmissionRejected) {
          rejections.add('seed=$seed ${failure.message}');
          rejectionCounts[seed] = (rejectionCounts[seed] ?? 0) + 1;
        } else {
          harnessFaults.add('seed=$seed $failure');
        }
      }
      if (run.pair.failures.any(
        (failure) => failure is WatchEmissionRejected,
      )) {
        kinds['rejected'] = (kinds['rejected'] ?? 0) + 1;
      }
    }
    print(
      'convergence sweep: ${kSeedCount - diverging.length} of $kSeedCount '
      'seeds converge, ${diverging.length} diverge '
      '(${kinds.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')})',
    );
    print('convergence sweep: heal never settles on seeds $healStalls');
    print(
      'convergence sweep: the pair never stopped answering itself on seeds '
      '$runaways (refusals there: '
      '${[for (final seed in runaways) rejectionCounts[seed] ?? 0].join(', ')})',
    );
    print(
      'convergence sweep: ${rejections.length} non-conformant frames refused '
      'on seeds ${rejectionCounts.keys.toList()}; first: '
      '${rejections.take(3).join(' | ')}',
    );
    for (final entry in diverging.take(5)) {
      print(entry);
    }
    expect(
      harnessFaults,
      isEmpty,
      reason:
          'no seed may make the pair throw or time out: an exception or a '
          '10 s push timeout is a harness fault, not a finding',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'S-14509 every random seed converges, or diverges inside a class the plan '
    'names',
    () async {
      // Plan 146 Phase 5.Y. Every class the 200- and 2000-seed sweeps still find,
      // with the fix it waits on. A seed whose kinds are all in here is a known
      // divergence and is printed; any other kind fails this test, so a new class
      // cannot arrive silently (D-14508: the report is the product).
      const knownClasses = <String, String>{
        'status':
            'PR 3 — the owner\'s "an earlier discard wins over a later finish" '
            'needs the phone to delete a finished workout (A-146-15, A-146-20)',
        'absorbing':
            'open — the wrist keeps work a session the phone ended handed it on '
            'a handful of seeds (24 of 2000 in the Phase 5.Z soak, seed 111 '
            'first; it does not reproduce under kShippingActions, so no minimal '
            'trace isolates it — A-146-25)',
        'timers':
            'D-14603 residue — 1 of 2000 seeds (1814) still shows a rest running '
            'after an end on both sides: the end arrives at the phone from the '
            'wrist, and the phone\'s own session keeps the rest it started '
            '(A-146-29)',
        'entries':
            'open — a late-merged entry (D-14605) is still missed on 4 of 2000 '
            'seeds after the harness reads the wrist store (A-146-24)',
        'heal':
            'flake class — the heal exchange never settles on a handful of '
            'seeds (the same class test/watch_convergence_harness_test.dart '
            'records)',
      };
      // Measured on seed 1..200 during Phase 5.Y: 42 seeds diverge on a trace
      // the shipping app can perform, and 39 on a second run of the same seeds —
      // the phone reads the device clock, so a divergence near the skew boundary
      // moves (A-146-15). Phase 5.Z fixed `duplicates` and almost all of
      // `timers` (33 seeds at 1..200, 1 at 1..2000), and re-measured 18
      // (A-146-27). The ratchet catches a class getting much worse; a new
      // *kind* is caught by `unknown` below. Heal stalls are excluded: they are
      // not deterministic.
      // Per 200 seeds, so the 2000-seed soak measures instead of failing on a
      // count that only grows with the seed total: 18 measured on 1..200 in
      // Phase 5.Z, which is 180 at 2000 (this run: 147).
      final shippingRatchet = (kSeedCount * 18 / 200).ceil();

      final shippingKinds = <int, List<String>>{};
      final syntheticOnly = <int>[];
      final unknown = <String>{};
      final byClass = <String, int>{};
      for (var seed = 1; seed <= kSeedCount; seed++) {
        var run = await ConvergenceRun.runSeed(
          seed,
          allowedActions: kShippingActions,
        );
        if (run.report.converged) {
          run = await replay(seed);
          if (run.report.converged) continue;
          if (run.usedSyntheticAction) {
            syntheticOnly.add(seed);
            _tally(_kindsOf(run), byClass, unknown, knownClasses.keys);
            continue;
          }
        }
        final kinds = _kindsOf(run);
        shippingKinds[seed] = kinds;
        _tally(kinds, byClass, unknown, knownClasses.keys);
        print(
          'seed=$seed diverges on a trace the shipping app can perform: '
          '${kinds.join(',')}\n${run.trace}\n${run.failures.join('\n')}',
        );
      }
      final shippingFinding = shippingKinds.entries
          .where((entry) => entry.value.any((kind) => kind != 'heal'))
          .map((entry) => entry.key)
          .toList();
      final shippingFlake = shippingKinds.keys
          .where((seed) => !shippingFinding.contains(seed))
          .toList();
      final converged = kSeedCount - shippingKinds.length - syntheticOnly.length;
      print(
        'S-14509 contract: $kSeedCount seeds; $converged converge on every '
        'trace; ${shippingFinding.length} diverge on a trace the shipping app '
        'can perform $shippingFinding; ${shippingFlake.length} on a heal stall '
        'alone $shippingFlake; ${syntheticOnly.length} only after the '
        'harness-only re-assert $syntheticOnly',
      );
      print('S-14509 contract: by class $byClass');
      expect(
        knownClasses.keys.toSet(),
        {'heal', 'status', 'absorbing', 'entries', 'timers'},
        reason:
            'the list above must name every kind `_kindsOf` can report, or a '
            'class could arrive with no owner',
      );
      expect(
        unknown,
        isEmpty,
        reason:
            'these divergence classes are not in the plan\'s list, so they are '
            'new and unclassified: $unknown. Classify one with '
            'ConvergenceRun.replayActions and Shrinker, then fix it or name the '
            'PR that owns it in `knownClasses`.',
      );
      expect(
        shippingFinding.length,
        lessThanOrEqualTo(shippingRatchet),
        reason:
            'Phase 5.Y measured 39 and 42 shipping-action divergences on the '
            'same 200 seeds, Phase 5.Z 18 ($kSeedCount seeds at the same rate: '
            '$shippingRatchet); this run has ${shippingFinding.length}: '
            '$shippingFinding. The pair disagrees about a workout the user can '
            'have — traffic above the band means a class got much worse.',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'S-14510 the shrinker reduces a padded failing trace with 20 unrelated actions',
    () async {
      final actions = await _paddedS14503();
      // The failure is built in, not a product defect that a later plan fixes:
      // the wrist that never hears an end (`_DeafToEndWrist`) never converges on a
      // finished workout (plan 146 re-based this test on it).
      Future<bool> stillFails(List<PairAction> candidate) async {
        final run = await ConvergenceRun.replayActions(
          candidate,
          engineFactory: _DeafToEndWrist.new,
        );
        return run.report.statusMismatches.isNotEmpty ||
            run.report.absorbingViolations.isNotEmpty;
      }

      expect(
        await stillFails(actions),
        isTrue,
        reason:
            'the padded trace still fails check 1 or 2 (the mutation wrist): '
            '${Shrinker.describeTrace(actions)}',
      );

      final shrunk = await Shrinker.shrink(actions, stillFails);
      expect(
        shrunk.length,
        lessThanOrEqualTo(6),
        reason:
            'a minimal trace is readable at a glance:\n'
            '${Shrinker.describeTrace(shrunk)}',
      );
      expect(
        await stillFails(shrunk),
        isTrue,
        reason:
            'the shrunk trace still fails for the same reason:\n'
            '${Shrinker.describeTrace(shrunk)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'B2 runSeed takes the wrist engine factory and the drain-only heal',
    () async {
      _MutationWrist? injected;
      final run = await ConvergenceRun.runSeed(
        7,
        allowedActions: kNoSessionActions,
        engineFactory: (args) => injected = _MutationWrist(args),
        drainOnlyHeal: true,
      );

      expect(
        run.pair.wristEngine,
        same(injected),
        reason: 'the seed run built its wrist from the injected factory',
      );
      expect(run.pair.drainOnlyHeal, isTrue);
      expect(
        run.heal.rounds,
        hasLength(1),
        reason: 'a drain-only heal is one round, not a request/answer exchange',
      );
    },
  );

  test('B2 replayActions takes the wrist engine factory and the drain-only '
      'heal', () async {
    final harness = await WatchPairHarness.build();
    _MutationWrist? injected;
    final run = await ConvergenceRun.replayActions(
      [harness.runner.phoneStartsSession()],
      engineFactory: (args) => injected = _MutationWrist(args),
      drainOnlyHeal: true,
    );

    expect(run.pair.wristEngine, same(injected));
    expect(run.pair.drainOnlyHeal, isTrue);
    expect(run.heal.rounds, hasLength(1));
    expect(
      injected!.applied,
      greaterThan(0),
      reason:
          'the injected engine is the one that served the frames '
          '${run.trace}',
    );
  });

  test('S-14508 the sweep can be made red: a wrist that ignores a completed '
      'lifecycle diverges seeds that converge', () async {
    const lastSeed = 60;
    final redSeeds = <int>[];
    final unmatched = <int>[];
    var ignoredCompleted = 0;
    ConvergenceRun? firstClean;

    for (var seed = 1; seed <= lastSeed; seed++) {
      final clean = await ConvergenceRun.runSeed(
        seed,
        allowedActions: kShippingActions,
      );
      final engines = <_MutationWrist>[];
      final mutated = await ConvergenceRun.runSeed(
        seed,
        allowedActions: kShippingActions,
        engineFactory: (args) {
          final engine = _MutationWrist(args);
          engines.add(engine);
          return engine;
        },
      );
      for (final engine in engines) {
        ignoredCompleted += engine.ignoredCompleted;
      }
      if (!clean.report.converged) continue;
      if (mutated.report.statusMismatches.isEmpty &&
          mutated.report.absorbingViolations.isEmpty) {
        // Not a harness failure: the seed simply never depends on the wrist
        // hearing that the session ended. Recorded, so a sweep where every
        // seed goes quiet is visible instead of passing as "no red".
        unmatched.add(seed);
        continue;
      }
      redSeeds.add(seed);
      firstClean ??= clean;
    }

    print(
      'S-14508 mutation red on seeds $redSeeds of 1..$lastSeed '
      '($ignoredCompleted completed lifecycles ignored; '
      '${unmatched.length} converging seeds never depended on one)',
    );
    expect(
      redSeeds,
      isNotEmpty,
      reason:
          'at least one clean-converging seed fails check 1 or 2 once the '
          'wrist drops the completed lifecycle: if none does, the checks '
          'cannot see a lost end and the harness must not be trusted',
    );
    expect(
      ignoredCompleted,
      greaterThan(0),
      reason: 'the mutation was reached: it ignored nothing at all',
    );

    final seed = firstClean!.seed;
    Future<bool> redUnderMutation(List<PairAction> actions) async {
      final clean = await ConvergenceRun.replayActions(actions);
      if (!clean.report.converged) return false;
      final mutated = await ConvergenceRun.replayActions(
        actions,
        engineFactory: _MutationWrist.new,
      );
      return mutated.report.statusMismatches.isNotEmpty ||
          mutated.report.absorbingViolations.isNotEmpty;
    }

    final shrunk = await Shrinker.shrink(firstClean.actions, redUnderMutation);
    print(
      'S-14508 seed=$seed minimal trace under the mutation:\n'
      '${Shrinker.describeTrace(shrunk)}',
    );
    expect(
      await redUnderMutation(shrunk),
      isTrue,
      reason:
          'seed=$seed diverges under the mutation after shrinking, and '
          'converges without it',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('S-14509 a drain-only heal: the mutation is the heal that carries nothing '
      'back', () async {
    final redSeeds = <int>[];
    final divergedSomewhere = <int>[];
    for (var seed = 1; seed <= kSeedCount; seed++) {
      final full = await ConvergenceRun.runSeed(
        seed,
        allowedActions: kShippingActions,
      );
      final drained = await ConvergenceRun.runSeed(
        seed,
        allowedActions: kShippingActions,
        drainOnlyHeal: true,
      );
      if (!drained.report.converged) divergedSomewhere.add(seed);
      if (!full.report.converged) continue;
      if (drained.report.statusMismatches.isEmpty &&
          drained.report.absorbingViolations.isEmpty) {
        continue;
      }
      redSeeds.add(seed);
    }

    print(
      'S-14509 drain-only heal: red seeds $redSeeds of 1..$kSeedCount; '
      'drain-only runs that diverge at all: '
      '${divergedSomewhere.take(20).toList()}'
      '${divergedSomewhere.length > 20 ? ' … (${divergedSomewhere.length})' : ''}',
    );
    expect(
      redSeeds,
      isNotEmpty,
      reason:
          'measured: ${redSeeds.length} of $kSeedCount seeds converge with '
          'the full heal and fail check 1 or 2 on the drain alone, so the '
          're-offer is load-bearing and not a redundant extra round. Seeds: '
          '$redSeeds. If this ever comes back empty, the finding has moved: '
          're-read this reason and record why in the evidence file.',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  // ---------------------------------------------------------------------
  // The findings of the 200-seed sweep and the 2000-seed soak, one skipped
  // replay each (D-14508). Every trace below is a shrunk, explicit action list
  // made only of actions the shipping app can perform (no synthetic re-assert),
  // so the tests do not depend on how the seeded runner draws its actions. Each
  // fails today and was proved by running it once with the `skip` removed (see
  // the evidence file); after the fix each must pass unchanged.
  // F-1 — the wrist reopens a finished workout with a queued `started` — is
  // S-14503 in `test/watch_convergence_harness_test.dart`, already skipped.

  Future<ConvergenceRun> script(
    List<PairAction> Function(HarnessRunner runner) actions,
  ) async {
    // The runner only numbers the actions; replayActions builds its own pair.
    final numbering = (await WatchPairHarness.build()).runner;
    return ConvergenceRun.replayActions(actions(numbering));
  }

  // F-2 (seed 50 of the triage; the shipping flavour of S-14503/F-1):
  //   1. wrist starts a Free workout  2. link drops  3. wrist finishes
  //   4. phone starts a rest timer    5. link rises
  //   -> the phone, unaware of the end, sends a NEWER active snapshot; the
  //      wrist reports the finished workout active again. "Ignore older by
  //      sentAt" cannot catch it; only "ended is final" can.
  test('F-2 a completed workout never reports active again', () async {
    final run = await script(
      (r) => [
        r.wristStartsFreeWorkout(),
        r.linkDrops(),
        r.wristFinishes(),
        r.phoneStartsRest(),
        r.linkRises(),
      ],
    );
    expect(
      run.report.absorbingViolations,
      isEmpty,
      reason: '${run.failures.join('\n')}\n${run.trace}',
    );
  });

  // F-3 (seed 2): 1. phone starts a session  2. phone starts a rest timer
  //   3. phone discards
  //   -> a rest timer runs on the phone and on the wrist although the session
  //      is abandoned. An end does not clear the rest timer on either side.
  test('F-3 an ended session runs no rest timer', () async {
    final run = await script(
      (r) => [r.phoneStartsSession(), r.phoneStartsRest(), r.phoneDiscards()],
    );
    expect(
      run.report.timerViolations,
      isEmpty,
      reason: '${run.failures.join('\n')}\n${run.trace}',
    );
  });

  // F-4 (seed 4): 1. phone starts a session  2. wrist discards
  //   3. link drops  4. phone starts a session  5. wrist finishes
  //   -> session 1: phone abandoned vs wrist completed. The wrist turned a
  //      session that had ended into `completed`: the end is not final inside
  //      the engine.
  test('F-4 an abandoned session is never reported completed', () async {
    final run = await script(
      (r) => [
        r.phoneStartsSession(),
        r.wristDiscards(),
        r.linkDrops(),
        r.phoneStartsSession(),
        r.wristFinishes(),
      ],
    );
    expect(
      run.report.statusMismatches,
      isEmpty,
      reason: '${run.failures.join('\n')}\n${run.trace}',
    );
  });

  // F-5 turned out to be a harness reading fault, not a product defect (plan
  // 146 phase 4): the wrist did apply the owed abandon after it moved on, but
  // the harness only read the HELD session's status, so the applied end read as a
  // stale active. The harness now reads the newest stored row for a session the
  // wrist has left, and this guard runs unskipped.
  // F-5 (seed 104, shrunk 25 -> 4): 1. wrist starts a Free workout
  //   2. link drops  3. phone discards  4. phone starts a session
  //   -> at the end of the heal: session 1: phone abandoned vs wrist active.
  //      The wrist does end it — the owed end arrives, exactly once (S-14606)
  //      — and the mismatch is the pair harness, which samples only the
  //      session the wrist still holds and leaves the earlier sample in place.
  test(
    'F-5 an abandon reaches a wrist session that is still running',
    () async {
      final run = await script(
        (r) => [
          r.wristStartsFreeWorkout(),
          r.linkDrops(),
          r.phoneDiscards(),
          r.phoneStartsSession(),
        ],
      );
      expect(
        run.report.statusMismatches,
        isEmpty,
        reason: '${run.failures.join('\n')}\n${run.trace}',
      );
    },
  );

  // F-6 (seed 14): 1. phone starts a session  2. link drops
  //   3. wrist discards  4. wrist starts a Free workout  5. phone logs a set
  //   -> the wrist never held that set: it had already ended the workout and
  //      moved on, and it holds one session at a time.
  // Open design question (owner): does check 3 apply once the wrist has left
  // the workout? The set is not lost — it is on the phone — but it is never on
  // both sides. Plan 146 decides; then this test passes or the check learns
  // the exception.
  test('F-6 a set the phone logs reaches the wrist or check 3 is relaxed',
      () async {
      final run = await script(
        (r) => [
          r.phoneStartsSession(),
          r.linkDrops(),
          r.wristDiscards(),
          r.wristStartsFreeWorkout(),
          r.phoneLogsSet(),
        ],
      );
      expect(
        run.report.entryMismatches,
        isEmpty,
        reason: '${run.failures.join('\n')}\n${run.trace}',
      );
    },
  );

  // F-7 (soak-only, seed 408, shrunk 24 -> 8): 1. wrist starts a Free workout
  //   2. link drops  3. phone discards  4. phone starts a session
  //   5. wrist discards  6. wrist starts a Free workout
  //   7. a live frame from the wrist refused  8. phone logs a set
  //   -> session 2: the wrist exposed the set twice. The 200-seed sweep never
  //      produced an entry duplicate; the 2000-seed soak did (seeds 408, 660).
  test(
    'F-7 a set is never held twice',
    () async {
      final run = await script(
        (r) => [
          r.wristStartsFreeWorkout(),
          r.linkDrops(),
          r.phoneDiscards(),
          r.phoneStartsSession(),
          r.wristDiscards(),
          r.wristStartsFreeWorkout(),
          r.refuseNext(from: PairActor.wrist),
          r.phoneLogsSet(),
        ],
      );
      expect(
        run.report.entryDuplicates,
        isEmpty,
        reason: '${run.failures.join('\n')}\n${run.trace}',
      );
    },
  );
}

/// Counts each kind of a diverging run, and records the kinds the plan's known
/// list does not name.
void _tally(
  List<String> kinds,
  Map<String, int> byClass,
  Set<String> unknown,
  Iterable<String> known,
) {
  for (final kind in kinds) {
    byClass[kind] = (byClass[kind] ?? 0) + 1;
    if (!known.contains(kind)) unknown.add(kind);
  }
}

/// Which of D-14507's checks a run failed, as report categories.
List<String> _kindsOf(ConvergenceRun run) {
  final report = run.report;
  return [
    if (!report.healConverged) 'heal',
    if (report.statusMismatches.isNotEmpty) 'status',
    if (report.absorbingViolations.isNotEmpty) 'absorbing',
    if (report.entryMismatches.isNotEmpty) 'entries',
    if (report.entryDuplicates.isNotEmpty) 'duplicates',
    if (report.timerViolations.isNotEmpty) 'timers',
  ];
}

/// S-14503's five actions, preceded by twenty that touch nothing: link flaps,
/// a refusal the trace never reaches, time steps, and the phone and wrist
/// actions a pair holding no session ignores.
Future<List<PairAction>> _paddedS14503() async {
  final harness = await WatchPairHarness.build();
  final runner = harness.runner;
  return [
    runner.linkDrops(),
    runner.linkRises(),
    runner.advanceTime(3),
    runner.advanceTime(7),
    runner.linkDrops(),
    runner.linkRises(),
    runner.advanceTime(11),
    runner.refuseNext(from: PairActor.phone, type: 'timer_state'),
    runner.phoneStartsRest(),
    runner.phoneLogsSet(),
    runner.wristLogsSet(),
    runner.wristStartsRest(),
    runner.wristFinishes(),
    runner.wristDiscards(),
    runner.advanceTime(29),
    runner.linkDrops(),
    runner.linkRises(),
    runner.advanceTime(30),
    runner.linkDrops(),
    runner.linkRises(),
    // The core: the phone starts and finishes a session. Run against the wrist
    // that ignores `completed` (S-14508's mutation), the wrist never hears the
    // end, so the pair disagrees (check 1). The padding around it does not matter.
    runner.phoneStartsSession(),
    runner.phoneFinishes(),
  ];
}

/// Every action the shipping app can perform: the sweep's action space minus
/// S-14503's synthetic re-assert, which no build can send (D-14513).
const Set<Type> kShippingActions = {
  PhoneStartsSession,
  PhoneLogsSet,
  PhoneFinishes,
  PhoneDiscards,
  PhoneStartsRest,
  WristStartsFreeWorkout,
  WristLogsSet,
  WristFinishes,
  WristDiscards,
  WristStartsRest,
  LinkDrops,
  LinkRises,
  RefuseLiveFrame,
  WristKilled,
  TimeAdvances,
};

/// S-14508's mutation: a wrist that never hears that a session ended.
///
/// `_applyLifecycle` is private, so the message is refused before the engine
/// sees it — the wrist behaves exactly as one whose inbox dropped that frame.
class _MutationWrist extends WatchSessionEngine {
  _MutationWrist(WristEngineArgs args)
    : super(
        args.store,
        onEmit: args.onEmit,
        validator: args.validator,
        clock: args.clock,
        idFactory: args.idFactory,
        sessionIdFactory: args.sessionIdFactory,
      );

  /// Frames the engine was handed, so a test can tell it served the run.
  int applied = 0;

  /// Completed lifecycles the mutation swallowed.
  int ignoredCompleted = 0;

  @override
  Future<bool> applyMessage(Map<String, Object?> envelope) async {
    applied++;
    if (envelope['type'] == 'session_lifecycle') {
      final payload = envelope['payload'];
      if (payload is Map && payload['state'] == WatchLifecycleState.completed) {
        ignoredCompleted++;
        return false;
      }
    }
    return super.applyMessage(envelope);
  }
}

/// A wrist that never hears an end: it refuses every `completed` lifecycle
/// and every snapshot that reports `completed`. Unlike [_MutationWrist] the
/// heal cannot repair it, so any trace in which the phone finishes a session
/// fails check 1 — a failure that is built in and does not depend on a defect
/// a later plan fixes (S-14510 uses it as the shrinker's subject).
class _DeafToEndWrist extends _MutationWrist {
  _DeafToEndWrist(super.args);

  @override
  Future<bool> applyMessage(Map<String, Object?> envelope) async {
    final payload = envelope['payload'];
    if (payload is Map &&
        envelope['type'] == 'session_snapshot' &&
        payload['status'] == 'completed') {
      ignoredCompleted++;
      return false;
    }
    return super.applyMessage(envelope);
  }
}

/// The shrinker of D-14509: a greedy pass that removes one action at a time and
/// keeps the removal when the named condition still fails on the shorter trace.
class Shrinker {
  /// Removes actions until no single removal leaves [stillFails] true.
  ///
  /// The predicate replays the candidate trace in full — the heal and the four
  /// checks need the whole list, not a pair state — and answers whether the
  /// named condition still fails.
  static Future<List<PairAction>> shrink(
    List<PairAction> actions,
    Future<bool> Function(List<PairAction>) stillFails,
  ) async {
    var current = List<PairAction>.of(actions);
    var removedSomething = true;
    while (removedSomething) {
      removedSomething = false;
      var index = 0;
      while (index < current.length) {
        final candidate = List<PairAction>.of(current)..removeAt(index);
        if (await stillFails(candidate)) {
          current = candidate;
          removedSomething = true;
          // The action that followed the removed one now sits at [index].
        } else {
          index++;
        }
      }
    }
    return current;
  }

  /// The trace as numbered plain sentences, each synthetic action flagged.
  static String describeTrace(List<PairAction> actions) => [
    for (var index = 0; index < actions.length; index++)
      '${index + 1}. ${actions[index].describe()}'
          '${actions[index].synthetic ? ' [synthetic]' : ''}',
  ].join('\n');
}
