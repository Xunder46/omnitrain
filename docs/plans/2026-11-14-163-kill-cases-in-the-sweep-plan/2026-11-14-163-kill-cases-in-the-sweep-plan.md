# Feature: kill cases in the randomized convergence sweep

> Status: Iteration 1 active (owner unavailable — every derived default below is marked
> "owner to confirm" and listed in the Assumption Log)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md; the sweep is documented at
> docs/state_management/watch_surface_transport.md ("Convergence testing", :144-181)

## Overview

The randomized convergence sweep (`test/watch_convergence_random_test.dart`, harness
`test/helpers/watch_pair_harness.dart`) plays 8–40 random actions over
`kShippingActions` with link drops and refused frames, then runs the heal and the four
checks (D-14507). A review (Fable, 2026-11-13) read it as not modelling the PHONE APP
being killed and the WATCH APP being killed mid-workout. Research says otherwise, and
this plan lands the half that is missing:

- **The wrist kill is already in the shipping action space.** `WristKilled`
  (`test/helpers/watch_pair_harness.dart:621-626`, `describe()` "wrist app killed and
  relaunched") is drawn by weight 3 (`_options`, harness:2069) and is a member of
  `kShippingActions` (`test/watch_convergence_random_test.dart:738-755`) and of
  `kNoSessionActions` (harness:1002-1011). `HarnessRunner.perform` case :1160-1162 calls
  `relaunchWrist()` (harness:859-862): a fresh `WatchSessionEngine` + paths +
  orchestrator over the SAME `InMemoryWatchSessionStore` and `_engine.restore()` —
  process death, not data death (the comment at :857-858; the real wrist keeps its
  append-only store, Dart twin `lib/watch/session/hive_watch_session_store.dart`, Swift
  simulation per D-15207). The replay corpus already carries it: `kill` events
  (`recordReplayKill`, harness:984; recorder format D-15203) in `seed-1.json`,
  `seed-408.json`, `seed-857.json` (plan 152 evidence :45-52), replayed on both engines
  (`ReplayReplayer.replay` case `kill`, `test/helpers/watch_replay_recorder.dart:540-543`;
  Swift `WatchReplayTests`).
- **The phone kill is not in the sweep — it was planned, never built.** Plan 152
  D-15210 (`docs/plans/2026-11-13-152-swift-replay-plan/2026-11-13-152-swift-replay-plan.md:75`)
  models it exactly: a phone action whose handler rebuilds the phone half over the same
  repository, "leaving the wrist and its store untouched; memory-only phone state
  (`_unconfirmedEnds`, `_fates` — `live_session_mirror_state.dart:130-135`) is what the
  kill destroys", "excluded from `kShippingActions` until built". `PhoneKilled` appears
  in no code (grep over `test/`, `lib/`, `watch/`: zero hits); S-15211 in plan 152:230-237
  is marked PLANNED.

**The smallest addition**: add `PhoneKilledAndRelaunched` beside the existing
`WristKilled` (one action class, one mint, one perform case, one relaunch), put it in
the shipping action set, re-measure the sweep under the standing ratchet policy, and
record one kill trace in the replay corpus so the Swift side stays in step. The
invariants the checks already enforce are asserted ACROSS a kill; no production code
changes; new divergence classes are Residue, not work.

## Resolved Decisions (Ledger)

- **D-16301 The action.** `final class PhoneKilledAndRelaunched extends PairAction`
  (actor `PairActor.phone`, `synthetic: false`, `describe() => 'phone app killed and
  relaunched'`), minted by `HarnessRunner.phoneKilledAndRelaunched()`, performed by a
  new `case PhoneKilledAndRelaunched(): await harness.relaunchPhone();` in
  `HarnessRunner.perform`. Kill and relaunch are ONE action — `WristKilled`'s shape
  (harness:621, performed at :1160); a kill without relaunch is a state the sweep cannot
  leave except through the heal's reconnect, and the app relaunches itself. Rides
  plan 152 D-15210's model; D-15210's name `PhoneKilled` is superseded by this entry
  (the paired name reads as what it does; plan 152 is not edited — see Notes).
- **D-16302 What the relaunch keeps and loses (fidelity rule: the harness may persist
  LESS than the app, never MORE).** `WatchPairHarness.relaunchPhone()` rebuilds, over
  the same `MockWorkoutRepository` (the phone's Hive-backed repository in production —
  `lib/main.dart` builds the `WorkoutRepository` once at :373-378 and every state reads
  it), the SAME objects the real launch builds: a new `WorkoutState(repository)` (the
  harness `build()` constructs it at :768 the same way) and a fresh `WatchSyncGraph`
  via the existing `createWatchSync` call, re-binding exactly what `build()` binds —
  `graph.adoption`/`autoPush`/`timerPush` `.bindWorkoutState(phone)` (harness:786-789;
  the real app additionally binds `timerAdoption`, `main.dart:433`, which the harness
  `build()` never did — the relaunch matches `build()`, not a new fidelity claim) — and
  re-registering the radio's one phone inbound slot (`PairRadio.onIncoming`,
  harness:436; the swap is part of the action's semantics, D-15210). What the fresh
  objects demonstrably lose (they are fields of the old objects):
  - the mirror's ledger: `_completedRecord`, `_newestSnapshotAt`, `_fates`,
    `_unconfirmedEnds`, `_retiredEnds` (`lib/state/watch/live_session_mirror_state.dart:127-141`
    — "a phone restart empties it and the stored row (D-3) takes over");
  - the adoption bridge's `_plansAwaitingEnd` ("Memory only (D-13034): a restart
    forgets it and the plan stays planned", `watch_session_adoption_bridge.dart:173-176`),
    `_everSeen`, `_projectedRevision`, `_skipped*` (:180-196);
  - `WatchSessionAutoPush`'s push baseline, `WatchTimerPush`'s `_adopted`
    (`watch_timer_push.dart:115`), `WatchLiveEnergy`'s last `energy_live` frame.
  What survives, because the real app keeps it: the repository contents — sessions,
  **staged watch-inbox rows** (`WatchSessionInbox` stages through
  `repository.stageWatchInboxEntry`, `watch_session_inbox.dart:267,323,368`), plan rows;
  the same `SettingsState`, `NutritionState`, `FoodLibraryState` instances (their
  observable values are repository/persisted-backed; the harness's fake preferences
  service is in-memory, so rebuilding `SettingsState` would lose settings the real app
  keeps — keeping the instance models "rebuilt from persistence lands on the same
  values", owner to confirm, Assumption P-2); the radio itself — its queues and link
  state model the OS layer, not the process (owner to confirm, Assumption P-3). The
  harness's bookkeeping — `phoneDiscardedSessions`, `_sessionLabels`, `phoneStatuses`,
  the trace — records what HAPPENED, not what the phone remembers, and stays.
- **D-16303 Recording and the corpus format.** A phone kill appends NO replay event:
  the recorder records the wrist's input timeline (D-15201), and a phone death's
  effects reach the wrist as recorded frames — the same treatment as `LinkDrops` /
  `LinkRises` (D-15202: "produce no event of their own; their effect arrives as
  recorded frames and clock stamps"). No new event type, `kReplayFormatVersion` stays 1,
  the Swift replayer needs no change. Wrist kills already record
  (`HarnessRunner.perform` :1160 → `recordReplayKill`, harness:984).
- **D-16304 The corpus gains one kill trace; the seed sources re-record.** New scripted
  source `trace-kills` (kind `trace`) in `kCorpusSources`
  (`test/watch_replay_corpus_test.dart:137-295`): steps
  `[wristStart, drop, wristLog, phoneKill, rise, wristFinish, wristKill, rise]` — the
  phone never hears the wrist's set (kill while the link is down), the finished session
  then survives the wrist's own death (its store persists), the heal converges; tags
  `['kill', 'phone-kill']` (a wrist `kill` event is in the file; `phone-kill` is
  run-only, like `refused-queued`, verified by the fresh re-recording S-15207).
  Adding the sweep option in Phase 2 changes every seed's draw stream, so the corpus's
  `seed-*` sources re-record to different stories under the standing regeneration rule
  (`--dart-define=REPLAY_CORPUS_WRITE=true`, D-15209); their tags are re-derived from
  what the fresh files cover (S-15207's tag verification catches a stale claim). The
  `kill` floor is then backed by the scripted trace, not by seed luck. Budgets
  (D-15208, asserted by S-15204, corpus test :691-742): each file ≤ 32 KB, whole corpus
  ≤ 300 KB — today 16 recordings + the manifest ≈ 74 KB total (plan 152 evidence :52),
  so one more file is well inside; **the 16-recording count is today's count, not a
  cap** — the standing rule is the two size bands.
- **D-16305 Membership and weight.** `PhoneKilledAndRelaunched` joins `_options` with
  weight 3 — the same as `WristKilled` (harness:2069), together 6/90 of draws, so
  roughly half of the 8–40-action traces carry some kill (owner to confirm, P-4) — and
  joins `kShippingActions` (`test/watch_convergence_random_test.dart:738-755`) and
  `kNoSessionActions` (harness:1002-1011). Adding an option changes every seed's trace
  (the `Random` stream is consumed per draw, `_mint` harness:2078-2105): the sweep
  re-measures everything; the per-kind counts inside the `knownClasses` comments
  (random_test:171-204) are measurements to re-take, not constants (D-14508: the
  report is the product).
- **D-16306 Ratchet policy (owner to confirm, P-5).** Re-measure, never relax:
  (a) a NEW divergence class found with the kills in the space is classified
  (`ConvergenceRun.replayActions` + `Shrinker.shrink`), listed as Residue in
  `<plan>.evidence.md` with its seeds and a shrunk trace, NOT fixed in this plan; it
  enters `knownClasses` (random_test:171-191) with the residue pointer, the way
  `status` and `absorbing` do.
  (b) The per-class budget lines are revised only DOWNWARD from a measurement. The
  total ratchet `shippingRatchet` (random_test:216-226, `(kSeedCount * 8 / 200).ceil()`,
  8 = measurement 5 + headroom, per 200 seeds) moves only through a NEW class's own
  measured line, which names the class and its seeds; the standing 8 is not raised to
  absorb a new class.
- **D-16307 No production change.** Nothing under `lib/` or `watch/watchos/Sources/`
  changes: the harness is test-only (grep `PairAction|kShippingActions|WristKilled` over
  `lib/` and `watch/`: zero files), and plan 152's precedent D-15213 applies — a defect
  the sweep finds across a kill is reported as Residue, not fixed here.

## Feature Invariants

- **Fidelity**: the harness persists exactly what the real app persists across a phone
  kill (D-16302's keep/lose list is the contract; a harness that carries the mirror's
  ledger or the bridge's flags over the kill would HIDE the bug this plan exists to
  find).
- **Non-synthetic**: the kill actions are actions the shipping app can perform
  (`synthetic: false`); every trace they produce is judged by the four checks like any
  other traffic — kills get no special reading in `_sample`, `checkConvergence` or
  `_kindsOf`.
- **Standing invariants hold across a kill**: every seed converges or diverges inside a
  named class (S-14509 contract); a finished workout never reopens (check 2; O-2);
  owner rules O-1..O-9 of plan 146
  (`docs/plans/2026-11-11-146-ended-is-final-plan/2026-11-11-146-ended-is-final-plan.md:15-23`)
  as read by the four checks; the D-15403 skew tolerance (`kEndSkewToleranceMs = 2000`,
  plan 154 :17 — same instant for D-14601/D-14630, completed wins ties) and D-15405
  (plan 154 :58 — the tolerance applies between ends of DIFFERENT status only;
  same-status ends compare exactly) hold across a kill: none of their owners (the phone
  bridge, the Dart engine, the Swift engine) is touched.
- **Ratchet**: constants only go down (D-16306).

## Requirements

1. The shipping action space contains both kill kinds, generable and described
   (`S-16301`).
2. A phone kill loses exactly the memory-only state of D-16302 and keeps the
   repository-backed state; convergence is reached through the stored-row path
   (`S-16302`–`S-16307`).
3. The sweep is re-measured with the kills in the space, at 200 seeds (twice) and 2000
   seeds (once); constants per D-16306 (`S-16308`, `S-16310`).
4. The replay corpus carries one kill trace, regenerated cleanly, replayed on the Dart
   wrist and on Swift (`S-16309`).
5. The docs page names both kill actions and the corpus's phone-kill coverage (Phase 5).

## Acceptance Criteria

- `PhoneKilledAndRelaunched` exists in the harness, `kShippingActions` and
  `kNoSessionActions`; the seam test proves the generator can produce both kill kinds.
- The scripted kill scenarios of Phase 3 pass (each maps to ≥ 1 scenario below).
- The 200-seed sweep is green twice and the 2000-seed soak once, with the ratchet and
  `knownClasses` updated per D-16306 and every measurement recorded in the evidence
  file.
- The corpus is regenerated, within budget, green on the Dart replay tests and on
  `swift test` (gateway `swift-test`).
- No file under `lib/` or `watch/watchos/Sources/` is modified (git-diff --name-only).

## Existing-Functionality Impact

Every symbol the change touches, its existing readers (grep-proven), and the effect:

| Touched surface | What already reads it (grep) | Effect | Guarded by |
| --- | --- | --- | --- |
| `kShippingActions` (`test/watch_convergence_random_test.dart:738`) | the sweep + contract test (:222, :388, :393), the S-14508 mutation test (:472, :477) — grep `kShippingActions` over `test/`: one file | new member; every seed's trace changes; all these tests re-measure | S-16310, D-16306 |
| `_options` (`test/helpers/watch_pair_harness.dart:2039-2075`) | `_mint` (:2078-2105) via `runSeed`/`replayActions` | new option changes every seeded draw stream | S-16301, S-16310 |
| `kNoSessionActions` (harness:1002-1011) | the seam test (`test/watch_convergence_random_test.dart:72-101`) | new member joins the no-session fixture space | S-16301 |
| `WristKilled` (harness:621-626) | perform case :1160-1162, `kNoSessionActions` :1009, `_options` :2069, `recordReplayKill` :984, corpus seed tags | unchanged; gains a sibling | S-16301 |
| `HarnessRunner.perform` switch (harness:1108-1168) | every harness test | one new case; recorder untouched (phone kill records nothing, D-16303) | Phase 1 Done Criteria |
| `WatchPairHarness` fields `phone`/`graph` (harness:695-701, ctor) | `HarnessRunner` getters (:1053-1055), `_sample`/`_observableState` (:1300-1400), the heal (:1443-1477) | made reassignable; every reader now reads the REBUILT half after a kill — which is the point | S-16302..S-16307 |
| Corpus `seed-*` sources (`watch/sync_protocol/fixtures/replay/`) | S-15202/S-15204/S-15207 (`test/watch_replay_corpus_test.dart:578-806`), Swift `WatchReplayTests.corpus()` (`WatchReplayTests.swift:46-56`) | re-recorded bytes after Phase 2 (draw stream); tags re-derived; freshness guard enforces it | S-16309 |
| `shippingRatchet` + `knownClasses` (random_test:171-226) | the contract test's expects | re-measured; revised per D-16306 | S-16310 |
| docs `watch_surface_transport.md` ("Convergence testing") | `docs/README.md` index | doc-only addition; 274 lines now, far under the 52 KB split band | Phase 5 |
| NOT touched — production | grep `PairAction|kShippingActions|watch_pair_harness|WristKilled` over `lib/`: zero files; `PhoneKilled|relaunchPhone` over `watch/`: zero files | none | D-16307 |

## UI Standards Impact

None — test-only change; no screen, widget or shared UI piece is touched.

## Scenarios

### S-16301: the sweep's fixture space carries both kill kinds
- Fixture: fresh `WatchPairHarness.build()`; allowed-actions set
  `{PhoneKilledAndRelaunched, WristKilled}`; seeds 1..5.
- Trigger: `ConvergenceRun.runSeed(seed, allowedActions: …)` per seed.
- Flow: the generator mints 8–40 actions; each is one of the two kinds.
- Expected outcome: every action's `runtimeType` is one of the two; `run.actions` is
  non-empty; `run.trace` lines read "phone app killed and relaunched" and "wrist app
  killed and relaunched"; the empty fixture space still throws `ArgumentError`
  (existing seam behaviour, random_test:88-92).
- Edge case of: none (new coverage seam).

### S-16302: the owed end survives a phone kill (the fidelity case)
- Fixture: pair; `wristStartsFreeWorkout`; `linkDrops`; `wristLogsSet`; **phone kill**
  (the rebuilt mirror's ledger is empty; the phone never saw the set);
  `linkRises`; then the heal (`HarnessRunner.heal`, harness:1443-1477 — the wrist's
  reconnect sync and `graph.sync()`, the real resume path).
- Trigger: the actions above via the runner; then heal + `checkConvergence`.
- Flow: the rebuilt mirror has no `_unconfirmedEnds` for the wrist's session; the
  stored-row path (plan 128 D-3) reads the wrist's rows at the snapshot request.
- Expected outcome: the heal converges; `run.report.statusMismatches` is empty (check 1
  agrees on the wrist's session); the set the wrist exposed is held on the phone side
  (check 3 union — staged in the inbox or imported) or the divergence is one of the
  plan's named classes; `entryDuplicates` empty (O-1).
- Edge case of: S-14511 (the wrist kill), plan 146's owed-end cases.

### S-16303: the first ending survives a phone kill (O-2, D-15403/D-15405)
- Fixture: `phoneStartsSession`; `linkDrops`; `phoneFinishes`; **phone kill** (the
  mirror's `_fates`/`_unconfirmedEnds` for the session are destroyed); `linkRises`.
- Trigger: heal + checks.
- Flow: the rebuilt phone asserts its own session from the repository row; the wrist's
  answer resolves by the standing rules.
- Expected outcome: the two ends resolve per D-15403 (within 2000 ms: the same instant —
  completed wins, then the smaller messageId; a discard wins only by MORE than the
  tolerance) and D-15405 (same-status ends compare exactly); check 2 holds: no side
  ever reports the finished session `active` again — `absorbingViolations` empty.
- Edge case of: S-16302; plan 146's F-2/F-4.

### S-16304: staged inbox rows survive the phone's death
- Fixture: a wrist session whose entries the phone STAGED (repository-backed) before
  their `session_end` was applied; **phone kill**; relaunch; heal.
- Trigger: the staging happens through the graph during the actions; the relaunch
  rebuilds the inbox fresh over the same repository.
- Expected outcome: after the heal the import pass completes (the inbox "resumes any
  import the phone had not run when it last stopped", `watch_sync_wiring.dart:26-28`);
  the entries reach history once; nothing staged resurfaces as a phantom workout or
  stray entry for a session the phone deleted (plan 146 owner confirmation, plan 146
  plan:470 watch-out).
- Edge case of: S-16302.

### S-16305: a kill on an idle pair is a convergence no-op (empty state)
- Fixture: fresh pair, no session ever started; **phone kill**; **wrist kill**;
  heal.
- Trigger: the two kill actions back to back on an idle pair.
- Expected outcome: the heal converges in one fixed point; the report is empty; no
  session, entry or timer state appears from nowhere.
- Edge case of: S-16302 (the empty-state sibling).

### S-16306: a phone kill while the link is down (queues untouched)
- Fixture: `wristStartsFreeWorkout`; `linkDrops`; `phoneLogsSet` (queued, undelivered);
  **phone kill**; `linkRises`.
- Trigger: heal + checks.
- Expected outcome: convergence as without the kill — the radio (queues, link state) is
  untouched by `relaunchPhone` (D-16302), so the queued frame's fate is unchanged; no
  new divergence class.
- Edge case of: S-16302, S-16303.

### S-16307: double kill is idempotent
- Fixture: active wrist session the phone mirrors; **phone kill**; **phone kill**;
  **wrist kill**; heal.
- Trigger: two consecutive phone kills (two rebuilds in a row), then a wrist kill.
- Expected outcome: the second relaunch is another fresh start (no accumulated state,
  no duplicated binding — `bindWorkoutState` on a fresh bridge only); the heal
  converges; `entryDuplicates` empty.
- Edge case of: S-16302, S-14511.

### S-16308: the sweep carries both kills at 200 seeds
- Fixture: seeds 1..200, `kShippingActions` including both kill kinds.
- Trigger: the S-14509 contract test, `--dart-define=CONVERGENCE_SEEDS=200`, twice.
- Expected outcome: both runs green; the printed per-kind counts include traces
  containing phone kills (a run where no seed ever killed the phone means the weight is
  wrong — a measurement finding, not a product one); the counts and the contract line
  are recorded in the evidence file.
- Edge case of: S-14509.

### S-16309: the corpus carries one kill trace and Swift replays it
- Fixture: the corpus with `trace-kills` (D-16304's steps) regenerated under
  `REPLAY_CORPUS_WRITE=true`; all sources re-recorded (D-16304).
- Trigger: `test/watch_replay_corpus_test.dart` default run; gateway `swift-test`.
- Expected outcome: S-15202 (every recording replays into a fresh Dart wrist and
  reproduces its expected summary), S-15204 (the manifest lists exactly the corpus; the
  `phone-kill` floor is declared; per-file ≤ 32 KB, total ≤ 300 KB — the new total
  recorded in the evidence file), S-15207 (fresh); Swift's `WatchReplayTests` picks the
  new file up via the manifest with NO Swift code change (D-16303) and replays it
  green (or its divergence is bucketed per D-15206 and reported).
- Edge case of: S-15204/S-15207.

### S-16310: the ratchet is re-measured and only tightened
- Fixture: the 200-seed runs of S-16308 plus the 2000-seed soak
  (`--dart-define=CONVERGENCE_SEEDS=2000`).
- Trigger: Phase 2 (200) and Phase 5 (2000) measurements.
- Expected outcome: every divergence class is named in `knownClasses` (the `unknown`
  expect, random_test:232-241, stays green); any new class is Residue with seeds and a
  shrunk trace in the evidence file (D-16306a); the per-class budget lines are revised
  only downward and the standing `8` is not raised (D-16306b); the measured counts are
  in the evidence file.
- Edge case of: plan 146 Phase 5.Y's ratchet.

## Iteration 1

### Phase 1: the phone-kill action in the harness (@developer)

1. [x] Add `final class PhoneKilledAndRelaunched extends PairAction` —
       `test/helpers/watch_pair_harness.dart` · `PhoneKilledAndRelaunched` (after
       `WristKilled`, :621-626): actor `PairActor.phone`, non-synthetic,
       `describe() => 'phone app killed and relaunched'`.
2. [x] Add the mint — `test/helpers/watch_pair_harness.dart` ·
       `HarnessRunner.phoneKilledAndRelaunched()` (beside `wristKilled`, :1080).
3. [x] Make the phone half reassignable and share one construction path —
       `test/helpers/watch_pair_harness.dart` · `WatchPairHarness` (`phone`/`graph`
       final fields :695-701 → backing fields + getters; extract the `createWatchSync`
       call and the three binds (:774-789) from `build()` :748-799 into a private
       `_launchPhone()` that `build()` calls once; the constructor no longer takes
       `phone`/`graph`).
4. [x] Add the relaunch — `test/helpers/watch_pair_harness.dart` ·
       `WatchPairHarness.relaunchPhone()` (beside `relaunchWrist` :859-862): a new
       `WorkoutState(repository)` over the SAME repository/settings/radio
       (D-16302), then `_launchPhone()`; `await settle()`.
5. [x] Wire the case — `test/helpers/watch_pair_harness.dart` ·
       `HarnessRunner.perform` (:1108-1168):
       `case PhoneKilledAndRelaunched(): await harness.relaunchPhone();`.
6. [x] Join the no-session fixture space —
       `test/helpers/watch_pair_harness.dart` · `kNoSessionActions` (:1002-1011); add a
       one-line comment at `recordReplayKill` (:984) that a phone kill records nothing
       (D-16303).
7. [x] Extend the seam test (structural guard for the fixture space) —
       `test/watch_convergence_random_test.dart` · test `the allowed-actions seam
       produces only the kinds it is given` (:69-101): add a pass over seeds 1..5 with
       `{PhoneKilledAndRelaunched, WristKilled}` asserting
       S-16301's outcomes; keep the empty-space `ArgumentError` expect.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test
test/watch_convergence_random_test.dart --plain-name "the allowed-actions seam"` and
`gateway.sh test test/watch_convergence_random_test.dart --plain-name "S-14502"` (the
same seed still reads the same twice — the draws stay deterministic); paste the pass
counts into the evidence file; `gateway.sh git-diff --name-only` shows no file outside
the two above.
**Predicted Files**: `test/helpers/watch_pair_harness.dart`;
`test/watch_convergence_random_test.dart`.
**Phase 1 verification notes (Conductor, date):** 2026-11-14, @developer — **Complete**.
Seam test RED before the option (`test/watch_convergence_random_test.dart:98:7`, "the
generator must be able to draw the phone kill"), green after Phase 2.1; `S-14502` green
(draw stream deterministic). `_gridClock` is held once per pair (`_phoneClock`) so a
relaunch keeps the phone's id monotonicity (plan 169 D-16905/D-16907). F-163-1's
dangling-session restore is in `_launchPhone()`. Evidence: the plan's evidence file.
### Phase 1.Y: remediation — BLOCKS Phase 1 closure
(any harness fault the seam test finds: fix before Phase 2; a structural guard is
S-16301 itself)

### Phase 2: the sweep carries the action; the 200-seed re-measurement (@developer)

1. [x] Add the weighted option — `test/helpers/watch_pair_harness.dart` ·
       `_options` (:2039-2075):
       `_ActionOption(PhoneKilledAndRelaunched, 3, runner.phoneKilledAndRelaunched)`
       directly after `WristKilled` (:2069).
2. [x] Join the shipping space — `test/watch_convergence_random_test.dart` ·
       `kShippingActions` (:738-755): add `PhoneKilledAndRelaunched`.
3. [x] Measure — run `.github/copilot/scripts/macos/gateway.sh test
       test/watch_convergence_random_test.dart --dart-define=CONVERGENCE_SEEDS=200`
       TWICE; record both runs' per-kind counts and the S-14509 contract line in
       `<plan>.evidence.md` (S-16308).
4. [x] Classify every new class — `ConvergenceRun.replayActions` +
       `Shrinker.shrink` on each unknown class; Residue R-163-2… in the evidence file
       with seeds and shrunk traces (D-16306a); enter `test/watch_convergence_random_test.dart`
       · `knownClasses` (:171-191) with the residue pointer. No fixes (D-16307).
5. [x] Revise the constants — resolved by the governor's 163c decision (P-9): the
       standing space is restored to its pre-plan 15 members with `kShippingActions`
       and its ratchet of 6 UNCHANGED, and the kill joins the new
       `kShippingActionsWithPhoneKill` with its own measured ratchet, 10 per 200 seeds.

**Done Criteria**: the sweep file green at 200 seeds twice (both runs' output in the
evidence file); `gateway.sh git-diff --name-only` shows only the two Phase-1/2 files
plus the evidence file; every `unknown` expect green.
**Predicted Files**: `test/helpers/watch_pair_harness.dart`;
`test/watch_convergence_random_test.dart`; `…-163-…-plan.evidence.md`.
**Phase 2 verification notes (Conductor, date):** 2026-11-14, @developer — **Complete**.
Measured ABOVE the standing ratchet of 6 (run 1: 8 shipping divergers, run 2: 7, by class
`{status: 6, entries: 1, heal: 1, absorbing: 3}` and `{status: 4, entries: 1, heal: 1,
absorbing: 3}`), which blocked the phase at the time. The governor's 163c decision
resolved it without raising anything: `kShippingActions` was restored to its pre-plan-163
15 members (ratchet 6, 4 divergers `[94, 123, 145, 167]` re-measured), and the phone kill
moved into the new `kShippingActionsWithPhoneKill` (ratchet 10, measured 8 and 7). No NEW
class either way — `status`, `entries`, `absorbing`, `heal` are all in `knownClasses`, so
item 4 is satisfied. Seeds and shrunk traces are in the evidence file.
### Phase 2.Y: remediation — BLOCKS Phase 2 closure
(a classified class that gets worse between the two runs: re-shrink before the soak)

### Phase 3: kill semantics, scripted (@developer)

New file `test/watch_convergence_kill_test.dart`, plain `test()` (never `testWidgets`:
FakeAsync never completes the graph's real awaits), one test per scenario, each
asserting `run.report` fields in the F-n style; every test's comment names its S-id.

1. [x] S-16302 — `test/watch_convergence_kill_test.dart` · test
       `S-16302 the owed end survives a phone kill`: replayActions over the scenario's
       action list; `statusMismatches`/`entryDuplicates` empty, heal converged.
2. [x] S-16303 — same file · test `S-16303 the first ending survives a phone kill`:
       `absorbingViolations` empty; the ends resolve per D-15403/D-15405 (a comment
       states which stamps the fixture uses).
3. [x] S-16304 — same file · test `S-16304 staged inbox rows survive the phone's
       death`: the staged entries reach history once; no phantom row (assert via the
       repository and `entryMismatches`).
4. [x] S-16305 — same file · test `S-16305 a kill on an idle pair is a no-op`.
5. [x] S-16306 — same file · test `S-16306 a phone kill while the link is down`.
6. [x] S-16307 — same file · test `S-16307 double kill is idempotent`.
7. [x] The clock pin — same file · test `S-16302 the relaunched phone's stamps stay on
       the pair clock` (P-6): the relaunch's stamps stay within the pair's
       `_gridClock`, so a relaunch cannot re-mint a used session id (D-16905/D-16907).

**Done Criteria**: `gateway.sh test test/watch_convergence_kill_test.dart` green (paste
counts); if any assertion is red, the divergence is classified per D-16306a — a RED
SCRIPTED TEST IS A FINDING, not a reason to weaken the assertion.
**Predicted Files**: `test/watch_convergence_kill_test.dart` (new);
`…-163-…-plan.evidence.md`.
**Phase 3 verification notes (Conductor, date):** 2026-11-14, @developer — **Complete**.
`gateway.sh test test/watch_convergence_kill_test.dart` → `+7: All tests passed!`.
Two guards were proven by mutation on the harness (originals restored exactly): dropping
`clock: _phoneClock` from the relaunched `WorkoutState` turns the pair-clock guard red
(406 s of skew), and commenting out the dangling-session restore turns S-16304 and the
clock guard red. S-16304's first assertion was wrong, not the code: inbox rows are never
deleted (applied tombstones), so it asserts "no row with `appliedAtMs == null`". Evidence:
the plan's evidence file.
### Phase 3.Y: remediation — BLOCKS Phase 3 closure

### Phase 4: the corpus gains the kill trace (@developer)

1. [x] Add the step — `test/watch_replay_corpus_test.dart` · `_Step.run` (:47-86):
       `case 'phoneKill': await runner.perform(runner.phoneKilledAndRelaunched());`.
2. [x] Add the source — same file · `kCorpusSources` (:137-295): `trace-kills`
       (kind `trace`) with D-16304's steps and tags `['kill', 'phone-kill']`.
3. [x] Declare the tag — same file: add `'phone-kill'` to the floor list (:735-752)
       and to `kRunOnlyTags` (it is invisible in the file, like `refused-queued`).
4. [ ] Regenerate — **governor action** (`REPLAY_CORPUS_WRITE=true` is denied to this
       mode): run `gateway.sh test test/watch_replay_corpus_test.dart
       --dart-define=REPLAY_CORPUS_WRITE=true`: every source re-recorded (the Phase 2
       option changed the seed streams, D-16304); tags re-derived; the floors stay
       backed by `trace-kills`.
5. [ ] Verify the budgets — same file's S-15204/S-15207 asserts; record the new total
       size in the evidence file (was ≈ 74 KB of 300 KB).
6. [ ] Swift stays in step — gateway `swift-test`: `WatchReplayTests.corpus()`
       (`watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift:46-56`)
       reads the regenerated manifest and replays `trace-kills` with NO Swift code
       change (D-16303). If Swift diverges on it, the difference is bucketed per
       D-15206 and reported as Residue — never normalized.

**Done Criteria**: `gateway.sh test test/watch_replay_corpus_test.dart` green (default
run: no files written); `gateway.sh swift-test` green (or its findings listed with
recordings named); S-15204's size asserts green; the regenerated files' diff is exactly
the corpus directory + the two test files.
**Predicted Files**: `test/watch_replay_corpus_test.dart`;
`watch/sync_protocol/fixtures/replay/trace-kills.json` (new, generated);
`watch/sync_protocol/fixtures/replay/*.json` + `manifest.json` (regenerated);
`…-163-…-plan.evidence.md`.
**Phase 4 verification notes (Conductor, date):** 2026-11-14, @developer — items 1-3
**done**; 4-6 **Blocked on the governor's regeneration** (`REPLAY_CORPUS_WRITE=true` is
denied to this mode). Red exactly as predicted at the pre-regeneration tree: S-15202
`the corpus is missing trace-kills.json — regenerate with ... REPLAY_CORPUS_WRITE=true`,
S-15204 (the manifest lists 16 sources, not 17) and S-15207 (`stale recordings:
['trace-kills.json']`) — `+4 ~1 -3` on this file. No other corpus test moved, so the
`phoneKill` step and the `phone-kill` tag are the only deltas.
### Phase 4.Y: remediation — BLOCKS Phase 4 closure

### Phase 5: the 2000-seed soak, docs, residue sweep (@developer)

1. [x] Soak — run `gateway.sh test test/watch_convergence_random_test.dart
       --dart-define=CONVERGENCE_SEEDS=2000` (900 s budget; if it times out — exit
       124 — diagnose, never re-run unchanged: record the partial counts and measure
       the constant on a 1000-seed run scaled to 200-seed units, flagged in the
       evidence file, owner to confirm).
2. [x] Finalize the constants per D-16306 with the soak's numbers;
       `<plan>.evidence.md` carries the full red→green table.
3. [x] Docs delta — `docs/state_management/watch_surface_transport.md` · the
       "Convergence testing" section (~:144-181): name both kill actions in the
       action space and the corpus's `phone-kill` coverage; the doc is 274 lines
       (~12 KB) — far under the 52 KB split band, no part page needed.
4. [x] Residue sweep — grep proving zero readers of any replaced representation:
       `PhoneKilled\b` (plan 152's unbuilt name) appears in no code, only in plan docs;
       `kShippingActions` contains both kill kinds; `WristKilled` readers unchanged;
       record the grep counts.
5. [ ] Close out — `gateway.sh lint` (compare the issue count with the repo's
       pre-existing baseline), `gateway.sh test test/watch_convergence_random_test.dart
       test/watch_convergence_kill_test.dart test/watch_replay_corpus_test.dart` green;
       Progress and Assumption Log updated. **Blocked on Phase 4.4**: lint is at the
       baseline 181, both sweeps and the kill tests are green, the corpus file is red
       until the governor regenerates.

**Done Criteria**: the soak's output in the evidence file; `git-diff --name-only` shows
NO file under `lib/` or `watch/watchos/Sources/` (D-16307); the docs page's new text
present; the three test files green.
**Predicted Files**: `test/watch_convergence_random_test.dart`;
`docs/state_management/watch_surface_transport.md`; `…-163-…-plan.evidence.md`;
`…-163-…-plan.md` (Progress/Assumption Log only).
**Phase 5 verification notes (Conductor, date):** 2026-11-14, @developer — items 1-4
**done**, item 5 **Blocked on Phase 4.4** (the regeneration). Soak: 2000 seeds in 5m43s,
all 17 tests in that file green — standing sweep 1933 converge / 31 shipping divergers
(ratchet 60), kill sweep 1894 converge / 76 shipping divergers (ratchet 100), 1086 of the
kill sweep's traces carrying a kill. Docs delta in the "Convergence testing" section of
`docs/state_management/watch_surface_transport.md`; residue sweep clean. Full suite
`+7632 ~4 -3`: the only reds are the three corpus tests Phase 4.4 fixes. Evidence: the
plan's evidence file.
### Phase 5.Y: remediation — BLOCKS Phase 5 closure

## Files Affected (whole feature)

- `test/helpers/watch_pair_harness.dart` — action, mint, relaunch, options, fixture
  space (Phases 1-2) — implements the seam the sweep reads.
- `test/watch_convergence_random_test.dart` — shipping space, seam test, constants,
  `knownClasses` (Phases 1, 2, 5).
- `test/watch_convergence_kill_test.dart` — NEW, scripted kill semantics (Phase 3).
- `test/watch_replay_corpus_test.dart` — step, source, tag floors (Phase 4).
- `watch/sync_protocol/fixtures/replay/` — `trace-kills.json` new; regenerated
  recordings + manifest (Phase 4).
- `docs/state_management/watch_surface_transport.md` — doc delta (Phase 5).
- `watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift` — READS the
  manifest only; **no edit**.
- No file under `lib/` changes.

## Notes

- **Dependency graph**: Phase 2 needs 1 (the action exists). Phase 3 needs 1 only — it
  may run before Phase 2 (the visible semantic wins land first; the sweep measurement
  then lands on a tree whose scripted tests are green). Phase 4 needs 1+2 (the corpus
  must be regenerated with the FINAL option space, or S-15207 goes stale twice).
  Phase 5 needs 2-4. Trade-off for reordering 3 before 2: none — the two files are
  disjoint.
- **Parallel work in this tree**: another run is editing tests. Phases 1-2 touch
  `watch_pair_harness.dart` and `watch_convergence_random_test.dart`, which that run
  may also touch — the executor rebases on the tree as it is and re-runs the Done
  Criteria; a conflict is resolved in favour of the standing behaviour (the seeded
  draw stream must stay deterministic).
- **Plan 152's D-15210/S-15211 name `PhoneKilled`**; this plan supersedes the name with
  D-16301 (`PhoneKilledAndRelaunched`). Plan 152 is NOT edited (this run's brief
  forbids it); the reviewer of this plan flags the pointer, not the text.
- **What the wrist-side rebuild keeps** (already shipped, restated for the reader): the
  same `InMemoryWatchSessionStore` — the model of the wrist's persisted append-only
  store — plus `_engine.restore()`; what it loses is the engine's in-memory projections
  and (on Swift) `WatchPlatformWorkout.adoptedBeforeRestore`
  (`WatchPlatformWorkout.swift:478`, plan 150 D-15004 — memory only; a Swift-side
  wrist-kill assertion is plan 150's and 152a's, not this plan's).
- **Legacy handling**: none — no persisted field, table or shared constant changes, so
  no regression test for dependent surfaces is owed beyond S-16310's re-measurement.
- **Intermediate state**: after Phase 1 and before Phase 2 the action exists but is not
  drawn by the sweep — the seam test still proves it; that state is green.

## Progress

- [x] Phase 1 — the phone-kill action in the harness — **Complete** (seam green;
      S-14502 green; harness file 36/36)
- [x] Phase 2 — the sweep carries the action; 200-seed re-measurement — **Complete**
      via the governor's 163c split: `kShippingActions` back to its pre-plan 15 members
      (ratchet 6, measured 4), `kShippingActionsWithPhoneKill` new (ratchet 10, measured
      8 and 7); no constant raised
- [x] Phase 3 — kill semantics, scripted — **Complete** (`+7`; two harness guards proven
      by mutation)
- [ ] Phase 4 — the corpus gains the kill trace — items 1-3 done (step, source, tag);
      **Blocked on the governor's regeneration** (`REPLAY_CORPUS_WRITE=true`); red until
      then: S-15202/S-15204/S-15207, exactly as predicted
- [ ] Phase 5 — the 2000-seed soak, docs, residue sweep — items 1-4 done (soak 2000
      seeds, docs delta, residue clean, lint at the 181 baseline); item 5 Blocked on the
      same regeneration

## Assumption Log

Derived interpretations, offered for veto before the first handoff that depends on
them (Phase 1 depends on P-1..P-3; Phase 2 on P-4..P-5):

- **P-1 (D-16301)** The action is named `PhoneKilledAndRelaunched`, one action for kill
  + relaunch. Options: D-15210's `PhoneKilled` (unpaired); the paired name chosen to
  read as what it does and to mirror `WristKilled`. Owner to confirm.
- **P-2 (D-16302)** `SettingsState`, `NutritionState`, `FoodLibraryState` instances
  survive the relaunch. Options: rebuild all (loses the fake preferences service's
  settings — a loss the real app does not suffer, breaking the fidelity rule in the
  other direction); chosen: keep the instances because their observable values are
  repository-backed. Owner to confirm.
- **P-3 (D-16302)** The radio's queues and link state survive the phone kill (they
  model the OS layer, not the process). Options: clear the queues (a real app's
  undelivered sends are lost with the process — but the radio is shared by both sides
  in the harness and D-15210's model leaves it untouched); chosen: untouched, per
  D-15210. Owner to confirm.
- **P-4 (D-16305)** Weight 3 (≈ 6/90 draws for both kills together, roughly half of all
  traces carrying some kill). Options: 2 (rarer); 3 matches `WristKilled` and maximizes
  the coverage this plan exists to get. Owner to confirm.
- **P-5 (D-16306)** The ratchet policy as written (per-class lines only downward; a new
  class gets its own measured line; the standing 8 not raised). Owner to confirm.
- **P-6 (D-16302/D-16907, @developer)** `_launchPhone()` builds the phone's
  `WorkoutState` with ONE `_phoneClock = _gridClock(clock)` held for the pair's lifetime,
  not a fresh closure per relaunch. Options: a fresh `_gridClock` per relaunch (literal
  reading of D-16907) — rejected because the grid counter would restart and could re-mint
  a session id the killed process already used (breaks D-16905's monotonicity). Owner to
  confirm.
- **P-7 (D-16302/F-163-1, @developer)** `_launchPhone()` runs the HomeScreen's first-frame
  restore (`checkForInProgressSession()` then `loadHistoricalSession(dangling.id)`) so a
  relaunch meets the row the app would. Proven load-bearing: removing the restore turns
  8/7 shipping divergers into 34 on the same 200 seeds (evidence file).
- **P-8 (D-16306b, @developer)** Measured 8 and 7 against the standing 6 is reported, not
  fixed: every diverging seed belongs to an already-known class (`status`, `entries`,
  `absorbing`), D-16307 forbids a production fix, and a constant may only go down. The
  plan stops here for the owner; no number was raised.
- **P-9 (D-16306b, 163c governor decision, @developer)** The constant conflict is resolved
  by SPLITTING the space, not by raising a number: `kShippingActions` returns to its
  pre-plan-163 15 members with its ratchet of 6 untouched, and the phone kill lives in the
  new `kShippingActionsWithPhoneKill` with its own measured ratchet of 10 per 200 seeds.
  Options: raise the standing 6 (forbidden by D-16306b); lower the kill's weight to 2
  (would have hidden the `status` class the plan exists to expose). Restoring the 15
  members also restores the pre-plan draw stream, so the `seed-*` recordings stay
  comparable and only the added source is new.
- **P-10 (S-16310, @developer)** The kill sweep gets a second chance on
  `kEveryAction` (`kShippingActionsWithPhoneKill` plus the harness-only
  `PhoneReassertsLive`), the same courtesy the standing sweep pays: a converged restricted
  run is re-run unrestricted, and a divergence that only the re-assert produces is tallied
  as `syntheticOnly` instead of a finding. Without it the 200-seed count reads 8 rather
  than 8 findings + 1 synthetic-only (seed 152). The kill sweep therefore also asserts
  `killedTraces > kSeedCount ~/ 4` so it cannot pass by never killing the phone.
- **P-11 (Phase 3/S-16304, @developer)** Inbox rows are put-if-absent and never deleted;
  `clearWatchInboxApplied` stamps `applied_at_ms` as a tombstone. S-16304 therefore
  asserts "no row with `appliedAtMs == null`" plus an `endedAtMs != null` terminal state,
  not "the inbox is empty" (the first assertion written was wrong, not the code).

## Feedback

**Phase 2's ratchet conflict is resolved (163c governor decision, P-9).** Adding the
phone kill to the shipping space took the 200-seed count from 6 to 8 (run 1) and 7
(run 2). Instead of raising 6, the standing space was restored to its pre-plan 15 members
(ratchet 6, measured 4) and the kill moved into `kShippingActionsWithPhoneKill` with its
own ratchet, 10, measured 8 and 7 at 200 seeds and 76 at 2000. No constant went up.
Phases 3 and 5 are done; Phase 4 items 1-3 are done and the corpus is red until the
governor runs the regeneration (`REPLAY_CORPUS_WRITE=true` is denied to this mode) — that,
and Phase 5 item 5, are the only things left in this plan.

## Open Items

- Corpus stale: `gateway.sh test test/watch_replay_corpus_test.dart
  --dart-define=REPLAY_CORPUS_WRITE=true`, then `gateway.sh swift-test` — governor only.
  Until it runs, S-15202/S-15204/S-15207 are red. Blocks Phase 4.4-6 and Phase 5.5.
- Sweep-vs-replay asymmetry: `status` seeds 46/76/105/152 need the full harness to
  reproduce, so a `replayActions` shrinker under-reports that class.
- `status` class flakes between runs (seed 76 diverged in run 1 and not in run 2 at 200
  seeds; at 2000 the `status`/`absorbing` split is 53/36) and so does the synthetic-only
  bucket (seed 4 in one of three runs), so neither can be per-run exact. The ratchets are
  set on totals, not per class.
- The two >52-seed sweeps now cost ~5m45s at 2000 seeds; the soak stays a manual run.
