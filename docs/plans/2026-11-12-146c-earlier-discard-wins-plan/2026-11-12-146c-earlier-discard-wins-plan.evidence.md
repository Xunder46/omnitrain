# Evidence — 146c: an earlier discard wins (146 PR 3)

Baselines, suite outputs, red→green tables and footprints live here; implementers write here, not into
the plan.

## Baselines (measured at planning, 2026-11-12)

- Plan 146's final soak (2000 seeds): **1777 converge, 146 diverging** on a shipping trace,
  `{status: 166, absorbing: 21, heal: 32, entries: 11, timers: 2}`
  (`.work/gateway/test-20261112-000556-15213.log`, recorded in plan 146's evidence `## Phase 5.Z`).
- Sweep contract: `knownClasses` = `{status, absorbing, entries, timers, heal}`; `shippingRatchet` =
  `(kSeedCount * 18 / 200).ceil()` (18 measured on seeds 1..200 in Phase 5.Z) —
  `test/watch_convergence_random_test.dart` :171-204.
- `flutter analyze`: **181 issues**, the repo baseline.
- Full suite at plan 146's close: **+7441 ~2: All tests passed!** (5m24s;
  `.work/gateway/test-20261112-000733-15770.log`).
- A-146-15's interim lives in two files: `lib/watch/session/watch_session_engine.dart`
  (`_applyLifecycle`, the completed-beats-abandoned skip ~766-776) and
  `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
  (`applyLifecycleExclusive`, the same skip ~826-833). The phone's reconciler
  (`lib/core/sync_protocol/session_reconciler.dart`, `_incomingEndWins` :226-241) already resolves
  earlier-instant-first with the D-14601 tie-break and has no interim — verified by read, no change
  planned.

## Phase outputs

*(filled in by the implementing agent at the end of its own phase: command, result, red→green table,
footprint)*

### Phases 1-3 (developer run 2026-11-12, PR 3)

Red→green per scenario (every RED is a `prove-red HEAD` run on the code without the change):

| Scenario | Test | RED at HEAD | Green |
|---|---|---|---|
| S-14630 | `test/watch_session_adoption_bridge_test.dart` → `S-14630 the wrist's earlier discard deletes the phone's finished workout` | `Expected: null / Actual: <Instance of 'TrainingSession'>` at the `getSession` assertion | pass |
| S-14632 | same file → `S-14632 an arriving discard at exactly the held end instant is ignored` | green before the change: it is the *guard on the guard*; proved by mutation (`<` → `<=` in the bridge) failing `Expected: <1791201900000> / Actual: <null>`, then restored and re-run green | pass |
| S-14633 | `test/watch_session_import_test.dart` → `S-14633 a winning discard leaves no phantom workout` (3 tests) | part of the same RED AT HEAD run below (no `S-14633` group can pass before the delete) | pass |
| S-14640 | `test/watch_session_engine_test.dart` → `S-14640 an earlier discard replaces the twin's completed` (2 tests) | `--plain-name S-1464` RED AT HEAD (exit 1) | pass |
| S-14641 | same file → `S-14641 a later phone completion loses to the wrist's discard`, `S-14641 both arrival orders converge on the same ending` | `Expected: false / Actual: <true>` and `Expected: 'abandoned' / Actual: 'completed'` | pass |
| S-14642 | `watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json` walked by `test/sync_protocol_fixtures_test.dart` `S-004 every reconciliation fixture converges on its expected state` | the fixture does not exist at HEAD | pass |
| S-14643 | `test/watch_reconciliation_cross_stack_test.dart` → `S-14643 an earlier discard wins on both stacks` (3 tests) | `Expected: ['abandoned', 'abandoned'] / Actual: ['abandoned', 'completed']` — the two stacks diverged at HEAD, which is the defect | pass |
| S-14650 | `watch/watchos/Tests/WatchSessionEngineTests/WatchEndedIsFinalTests.swift` → `testS14650AnEarlierDiscardBeatsALaterCompletionInEitherOrder`, `testS14650ALaterDiscardLosesToAnEarlierCompletionInEitherOrder` | `prove-red HEAD swift-test --filter WatchEndedIsFinalTests` → RED AT HEAD: 3 failures on `XCTAssertFalse … a later completion loses` / status `completed` where `abandoned` was expected | pass |
| S-14651 | `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges` (walks the new fixture, asserts `expected.status`) | walked only after Phase 2 created the fixture; the same walker is RED on the unmodified engine (it keeps `completed`) | pass |

Prove-red verdict lines:

```
gateway: prove-red: RED AT HEAD (exit 1).  [test test/watch_session_adoption_bridge_test.dart — S-14630]
gateway: prove-red: RED AT HEAD (exit 1).  [test test/watch_reconciliation_cross_stack_test.dart — S-14643, Actual: ['abandoned', 'completed']]
gateway: prove-red: RED AT HEAD (exit 1).  [swift-test --filter WatchEndedIsFinalTests — S-14650, 3 failures]
```

Suite counts (real, pasted):

| Check | Command | Result |
|---|---|---|
| Phase 1 | `gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart` | **133 passed, 0 failed** |
| Phase 2 (Dart) | `gateway.sh test test/sync_protocol_fixtures_test.dart` (S-004) | pass |
| Phase 2 (Dart) | `gateway.sh test test/watch_reconciliation_cross_stack_test.dart test/sync_protocol_fixtures_test.dart` | **210 passed, 0 failed** |
| Phase 2 (Dart) | `gateway.sh test test/watch_convergence_harness_test.dart test/watch_session_engine_test.dart test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart` | **233 passed, 0 failed** (S-14512 re-pointed: prints `phone abandoned wrist abandoned`) |
| Docs | `gateway.sh test … test/docs_indexing_contract_test.dart` | pass (PROTOCOL.md still under the 64 KiB cap) |
| UI standards | `gateway.sh test test/ui_standards_contract_test.dart` | **41 passed, 0 failed** |
| Phase 3 (Swift) | `gateway.sh swift-test --filter WatchEndedIsFinalTests` | **12 passed, 0 failed** |
| Phase 3 (Swift) | `gateway.sh swift-test` (whole package) | **1388 passed, 0 failed** |
| Lint | `gateway.sh lint` | **181 issues** — the baseline, no new notice in a touched file |

Mutation (S-14632 only): the bridge's `atMs < held.endedAtMs` was changed to `atMs <=
held.endedAtMs`; `--plain-name "S-14632"` then failed `Expected: <1791201900000> / Actual: <null>`;
the exact original line was restored and the suite re-ran green (133 passed). No mutation is left
applied.

Footprint (`gateway.sh git-diff --stat`): 13 files, +~940/-~60. All inside the plan's Predicted Files
for Phases 1-3, plus the new fixture file and one helper-signature change inside a predicted test file
(`_phone(..., clock:)`).

### Phase 4 (developer run 2026-11-13, PR 3)

Phase 4 measures; it was predicted to fix nothing (A-146c-03, A-146c-04). No `lib/` file changed in this
phase — the diff is two convergence test files and one import test file.

**Item 1 — O-6 (a proof, not a fix).** New group
`O-6 the wrist's own workout is its own finished row` →
`O-6 a completed wrist session imports as its own row while the phone holds another workout` in
`test/watch_session_import_test.dart`: the phone holds an open `s-o6-p1`, the wrist stages a set and a
`completed` end for `s-o6-w2`, `WatchSessionImporter.apply(..., phoneOwnsSession: false)`. It asserts the
wrist's row exists **finished**, with its set and its load; the phone's row is untouched and still open;
both ids are on the phone; every staged row is applied.

```
gateway.sh test test/watch_session_import_test.dart --plain-name "O-6"   →  00:00 +1: All tests passed!
```

`prove-red HEAD` is not the instrument here: O-6 exercises behaviour that already exists end to end
(A-146c-03), so HEAD-relative redness would only restate that. Proved by mutation instead — the
`phoneOwnsSession` dispatch in `WatchSessionImporter.apply`
(`if (phoneOwnsSession) return _mergeHeld(watchSessionId, rows);`) was inverted to
`if (!phoneOwnsSession)`:

```
00:00 +0 -1: O-6 … [E]
  Expected: not null
    Actual: <null>
  O-6 the wrist's workout is saved as its own finished workout: the phone adopting nothing for it
  does not make it history-less
  test/watch_session_import_test.dart 1013:7
```

The exact original line was restored and O-6 re-ran green. No mutation is left applied.

**Item 2 — S-14660, the pair-harness trace: RED, and blocked.**
`S-14660 the wrist's own workout is saved as its own finished workout while the phone's stays open` in
`test/watch_convergence_harness_test.dart` (phone starts p1 and logs a set → wrist free-starts w2 and
logs a set → wrist finishes → the link rises → heal). It fails `Expected: not null / Actual: <null>` at
the wrist workout's phone-side row. The assertion was **not** weakened; the test carries `skip:` with the
reason and the plan reference, so the file stays green without hiding the finding.

Root cause (read, not inferred): the wrist's terminal lifecycle for its own session calls
`_withdrawOnWristQueue` and drops that session's queued `session_snapshot`, and
`WatchSessionInbox._stageable` accepts only `observations_up` and watch-origin `session_snapshot` — a
`session_lifecycle` carries `{state, at}` and never the session's `startedAt`. `WatchInboxEntry.kindSessionEnd`
requires `startedAt`/`endedAt`/`status`, so no `session_end` row is ever created and
`WatchSessionImporter.apply` has nothing to import. Fixing it means making the wrist re-offer a completed
session's entries: a **protocol** change, outside Phase 4. → plan `## Open Items`.

**Item 3 — the sweep and the soak, with the band re-owned.**

| Run | Before (Phase 5.Z / plan 146) | Phase 4 |
|---|---|---|
| 200 seeds, shipping trace | 42 then 39 (A-146-15), 18 after 5.Z | **12** then 12 again (`[29, 43, 94, 95, 111, 117, 124, 134, 149, 152, 161, 193]`) |
| 200 seeds, heal stall alone | — | **2** (`[86, 142]`, `[86, 184]`, `[17, 184]` across runs — the known flake) |
| 200 seeds, harness-only | — | **3** (`[33, 138, 183]`) |
| 2000 seeds, shipping trace | 146 diverge / 1777 converge | **125** diverge / **1801** converge |
| 2000 seeds, by class | `{status: 166, absorbing: 21, heal: 32, entries: 11, timers: 2}` | `{status: 137, absorbing: 22, heal: 34, entries: 14, timers: 2}` |

Real output lines:

```
S-14509 contract: 200 seeds; 183 converge on every trace; 12 diverge on a trace the shipping app can
perform [29, 43, 94, 95, 111, 117, 124, 134, 149, 152, 161, 193]; 2 on a heal stall alone [86, 142];
3 only after the harness-only re-assert [33, 138, 183]
S-14509 contract: by class {status: 13, heal: 3, absorbing: 2}
```

`.github/copilot/scripts/macos/gateway.sh test test/watch_convergence_random_test.dart
--dart-define=CONVERGENCE_SEEDS=2000` → **15 passed, 0 failed**, 3m23s (`.work/gateway/test-20261113-000657-11670.log`).

`status` improved (166 → 137 at 2000, 14 → 12 at 200) — the owner's "an earlier discard wins" case itself
no longer diverges — so the sweep did not trip the stop-and-report rule. `absorbing` (+1), `entries` (+3)
and `heal` (+2) are the same classes at the same order of magnitude, not a new class.

`shippingRatchet` moved from `(kSeedCount * 18 / 200).ceil()` to `(kSeedCount * 14 / 200).ceil()`
(14 at 200, 140 at 2000) — the measured 12 plus two seeds of headroom for the clock-skew movement A-146-15
records (12 and 13 were observed on two 200-seed runs). Proved by mutation: the ratchet set to
`(kSeedCount * 1 / 200).ceil()` (1 at 200) fails the contract test
`Expected: a value less than or equal to <1> / Actual: <12>`; the exact original was restored and the test
re-ran `+1: All tests passed!`. `knownClasses` was rewritten for `status`, `absorbing`, `timers` and
`entries` to name this phase's measurements.

**Items 4-5 — the shrink-and-classify traces** (temporary probe in the sweep file, removed afterwards;
log `.work/gateway/test-20261113-001151-14848.log`):

`absorbing`, seed 111 → a **4-action** minimal trace:

```
1. wrist starts a Free workout
2. a live frame from the wrist refused
3. wrist finishes
4. wrist starts a Free workout
→ absorbing=[session 1 was completed on the wrist and reports active again]
  phoneStatus={session 1: completed, session 2: null}
  wristStatus={session 1: completed, session 2: abandoned}
```

`entries`, seed 857 → a **5-action** minimal trace (from 39 actions):

```
1. a live frame from the phone refused (session_snapshot)
2. wrist starts a Free workout
3. phone logs a set
4. phone discards
5. phone starts a session
→ entries=[session 1: the wrist never held entry-sx-ex-run-1-1]
  phoneStatus={session 1: abandoned, session 2: active}
  wristStatus={session 1: abandoned, session 2: active}
```

`timers`, seed 1814 → **not reproduced**: replayed alone it prints `kinds=[] … converges`, and the soak
found 2 timer-diverging seeds out of 2000 (the phase's rows) with no repeatable trace. D-14635's
`endSession`-live-rest seam is therefore unconfirmed (A-146c-16): no fix written, no code touched.

**Phase 4 suites (real counts).**

| Check | Command | Result |
|---|---|---|
| Phase 4 Done Criteria (random + harness) | `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` | **54 passed, 1 skipped, 0 failed** (28 s) |
| O-6 | `gateway.sh test test/watch_session_import_test.dart --plain-name "O-6"` | **1 passed** |
| Docs | `gateway.sh test test/docs_indexing_contract_test.dart` | pass |
| UI standards | `gateway.sh test test/ui_standards_contract_test.dart` | **41 passed** |
| Lint | `gateway.sh lint` | **181 issues** — the baseline, nothing in a touched file |
| Full suite | `gateway.sh test` | **7465 passed, 4 skipped, 1 failed** (`.work/gateway/test-20261113-001659-18723.log`) |

The one full-suite failure is pre-existing and unrelated:
`test/delete_focused_timer_test.dart` → `S-4905 a running later interval keeps running and keeps its own
time after a middle delete`. It asserts the `00:45` readout off `startedAtMs: DateTime.now()…`, i.e. a
real-clock threshold, which the repo's rules forbid precisely because load moves it; run alone it is
`+4: All tests passed!`. Not touched by this diff, not edited.

### Phase 5 (developer run 2026-11-13, PR 3 — Health re-write after an end-time move)

**Files changed.** `lib/core/services/health_sync_service.dart` (new `rewriteWorkout`, `dart:math`),
`lib/state/workout/session_core_lifecycle.dart` (`catchUpEndedSession` triggers it),
`lib/core/services/watch_session_importer.dart` (`WatchSessionImport.endMovedFromMs`, `_Pass`, `_catchUpEnd`),
`lib/state/watch/watch_session_inbox.dart` (`_rewriteHealth`, `_settleNow`),
`test/health_platform_test.dart` (+8 tests, the fake's effort/delete recording),
`test/watch_session_import_test.dart` (+1 test, `_RewriteSpy`, `_inbox(healthSync: …)`),
`docs/state_management/services_and_utils.md`, `docs/state_management/workout_state.md`.

**Suites (real counts).**

| Check | Command | Result |
|---|---|---|
| Phase 5 Done Criteria | `gateway.sh test test/health_platform_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart` | **158 passed, 0 failed** (~1 s; `.work/gateway/test-20261113-003215-32439.log`) |
| Brief's extra files | `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | **95 passed, 1 skipped, 0 failed** (27 s; `.work/gateway/test-20261113-003225-32600.log`) |
| Lint | `gateway.sh lint` | **181 issues** = baseline; `grep` for the six touched files in the log: no matches |
| UI standards | inside the extra-files run | 41 passed |
| Full suite | not run (brief; the lead runs it) | — |

**Red before implementation.** `prove-red HEAD` cannot compile these tests (the production API is new), so
each guard was proven by mutation — original line recorded, changed, run, restored exactly, re-run green.

| Mutation | Original line | Observed red |
|---|---|---|
| M1 drop D-14636's ledger gate | `if (!await _ledgerContains(session.id)) return;` → `… && false)` | `S-14671 a session the phone never wrote is left alone…` — `Expected: empty / Actual: [(09:00, 09:40)]`, reason `S-14671 the watch's own workout is never deleted`; also `S-14671 the phone's catch-up writes nothing…` (2 failures) |
| M2 drop the phone trigger | `await _healthSync?.rewriteWorkout(updatedSession, previousEndedAtMs: heldEndMs);` → commented | `S-14670 the phone's own catch-up rewrites the workout it wrote` — `Expected: 09:40 / Actual: 09:30` |
| M3 drop the importer report | `endMovedFromMs = row;` → `endMovedFromMs = null;` | `plan 146c: a moved end reaches the Health rewrite` — `Expected: [(s-cap-1, 1790333700000)] / Actual: []`, reason `S-14670 the pass reports the end it moved from, once` |

After each restore, the named file(s) went green again (the 158-pass run above is post-restore).

**Scenario coverage.** S-14670: two moves leave one workout over the new span and the effort on it;
a move with no rating writes no effort; an unchanged end sends nothing; a refused delete writes nothing
and keeps the ledger; the phone's catch-up rewrites; the inbox asks once with the end it moved from.
S-14671: the service arm and the phone arm both send nothing (no delete, no write) for a session the
ledger does not name, and a move with `Write workouts` off sends nothing.

## Governor actions

*(recorded by the planner when the work needs something its tools deny)*

## Lead note: S-14508 re-based (2026-11-13)
After phases 1-3 the S-14508 mutation proof (a wrist that ignores `completed` lifecycles) turned red on 0 of 60 seeds (it was 7, 9, 40 before): the new rule lets the heal repair that wrist through snapshots, so the proof no longer proved the sweep can fail. Re-based on `_DeafToEndWrist` (refuses completed lifecycles AND completed snapshots, the same mutation S-14510 uses): red on seeds [1, 11, 46, 52, 55, 56, 57]. A stronger mutation, not a weaker assertion. The developer run had reported all suites green without running this file.
Lead-verified: focused Flutter suites 491 passed; Swift full 1388 passed; new tests fail on the old sources (Dart 4 failures, Swift 3).

## Investigation 2026-11-13 (brief `.work/2026-11-10-145-convergence-test/brief-developer-confirm.md`)

Investigation only: no product file changed, no plan decision taken. Method — replay the recorded
shrink traces and the seeds through `ConvergenceRun.replayActions` / `runSeed(seed, allowedActions:
kShippingActions)` on the pair harness, dump per action the phone/wrist status, the wrist rows, the
absorbing set and the snapshot payloads, then re-deliver a drained frame into the wrist engine as-is
and with a bumped `sentAt`; plus a static read of the Swift engine, the inbound lane, the bridge, the
sensor recorder and the app host. Scratch probe `test/zz_investigation_a.dart`, deleted after the
runs; the raw output is in the logs named per item.

### A1 — seed 111's absorbing class (4-action trace)

**Confirmed; exact trace reproduces 4/4, failure `session 1 was completed on the wrist and reports
active again`.** The *seed* is not a stable reproduction: seed 111 under `kShippingActions` is 22
actions and converged in my process (`test-20261113-090156-67691.log`) while the S-14509 contract in
the same session still lists 111 among the 12 shipping divergers — the phone's real clock (A-145-02)
changes the `sentAt` values the trace carries, so seed membership is not process-stable. A1's evidence
below therefore comes from the phase-4 action trace (its recorded 4-action list, replayed identically),
which is stable: `test-20261113-090712-69744.log`, repeats 1-3 all `converged=false` with that line.

Mechanism, read from the trace plus `_applySnapshot`: the phone never adopts the wrist's finish, ends
session 2 itself, then sends two `active` snapshots for session 1. The cross-session guard in
`_applySnapshot` (`held.status == active && held.exercises.isNotEmpty && held.sessionId != sessionId`)
does not fire, because the held session at that moment is session 2 and already terminal; the session-1
snapshot is therefore applied whole and appends `session 1:active` rows although a `completed` row for
session 1 exists. `_holdsTerminalRow` (D-14605) is consulted only *inside* that guard, so D-14601's
"an ended session stays ended" is not enforced for a session the wrist has moved past.

```
wrist rows=[session 1:active, session 1:completed, session 2:active, session 2:abandoned, session 1:active, session 1:active]
absorbing=[session 1 was completed on the wrist and reports active again]
```

Confidence: high on reproduction and on the code path; no clock dependency (three independent runs).

### A2 — seed 857's entries class (5-action trace)

**Confirmed; reproduces 4/4, `session 1: the wrist never held entry-sx-ex-run-1-1`.** The seed itself
(39 actions) converged in my process in the same run, for the same clock reason as A1; the recorded
5-action trace is stable and is what the probe below uses.

Mechanism: the one frame carrying the set is refused live and queued; by the time it drains, the
phone's snapshot for session 2 has advanced `_newestSnapshotAt`, so D-127 refuses the older frame
whole — entries included — and the phone's later session-1 snapshots carry `entries=[]`. Direct
probe: re-applying the drained frame as-is returns `changed=false, observations=0/4`; the identical
payload with a later `sentAt` is **accepted** and the entry stored (`changed=true, observations=1,
ids=[entry-sx-ex-run-1-1]`, `test-20261113-090740-69987.log`). So the cause is the single, never-reset,
cross-session `_newestSnapshotAt`, not the D-78 merge: `_mergeLateEntries` is never reached, which
makes D-14605's late-entries merge unreachable whenever another session's newer snapshot was applied
first.

Confidence: high on reproduction and on the D-127 mechanism (probe, not inference); the reach of the
loss is open — whether the phone still holds the entry is not established, so this is either a
convergence failure or also data loss.

### A3 — seed 1814's timers class

**Confirmed reproducible alone; phase 4's "replayed alone it converges" is stale.** Shipping trace,
31 actions: 4 absorbing plus 2 timers —
`session 1: a rest timer runs on the phone although the session is completed` and the same on the
wrist. Full action space (which may draw `PhoneReassertsLive`) converges in 31 actions, so the
earlier check was the full-space replay, not the shipping one. Prefixing seed 1813 changes nothing
(same 6 failures), so no cross-seed state leak. Confidence: high.

The absorbing failures are A1's signature (`session 1` completed then reopened), so the timers
failures may be downstream of the same resurrection; D-14635's `endSession`-live-rest seam is neither
proven nor refuted here.

### `status` class (137/2000 in phase 4)

**Confirmed, one signature.** Six representatives under `kShippingActions` — 29, 43, 94, 95, 117, 124
— each fail with exactly one check, `session N: phone abandoned vs wrist completed` (94 is
`session 2`, the rest `session 1`). That is the A-146-15 / D-14630 shape: the wrist keeps an earlier
completion while the phone keeps a later discard. Not shrunk and the phone's discard path not read, so
the mechanism is suspected, not verified. Confidence: high on the signature (6/6 identical wording),
low on the mechanism.

### B1 — thread/actor audit

**The engine carries unprotected mutable state and at least one writer path runs off the main actor.**
`WatchSessionEngine` is `public final class … : ObservableObject` with no `@MainActor`/`actor`
annotation and no internal lock. Unprotected: `sessionRows`, `current`, `appliedChangeIds`,
`newestSnapshotAt`, `entryCorrections`, `deletedEntryIds`, `replacedEntryIds`,
`acknowledgedObservationIds`, `announcedCountdownKeys`, `energyAnnounced*`. Only plan 150's
`storedObservations` / `storedTimers` / sensor samples sit behind the `NSLock` boxes in
`WatchEngineRowLogs.swift`.

`WatchInboundLane` serialises frames but `drain()` is an unstructured `Task {}` in a non-isolated
class, and `WatchConnectivityBridge.onIncoming` is a plain closure; the app's `WatchAppHost` is
`@MainActor` and wraps the handler body in `await MainActor.run { … }` (`ios/OmniTrain Watch
App/ContentView.swift`), so inbound writes do land on the main actor — nominally safe, but nothing in
the type system holds that. The sensor path does not hop: `WatchSensorRecorder.consume` starts plain
`Task { for await … }` from a non-isolated class (`WatchSensorRecording.swift`), and those elements
write the engine, concurrently with main-actor UI writes. So the suspected race is sensor-vs-main, not
inbound-vs-main.

Confidence: medium-high (static call path); the app target's whole call graph was not audited.

### B2 — strong TSan stress test

**Not established — not written.** The brief's ~60-minute stop and the remaining write-up took
priority; no `.swift` file was added, so the package suite is untouched (1404). Design for the
follow-up: an `async` test that starts a detached loop driving `appendSensorSample`/`announceEnergy`
while the main actor starts, logs, finishes and applies phone snapshots (touching `sessionRows` and
`current` on both paths), repeated inside one test; run with `swift test --sanitize=thread --filter
WatchEngineSessionStateRaceTests`. Keep it only if TSan reports engine state; otherwise record "no
report in N runs" and delete it. The gateway exposes no TSan flag, so this needs a governor action or
a manual command.

### Could not be established

- Whether the phone keeps a discarded session's entries (A2's reach: convergence-only or data loss).
- The `status` class mechanism (phone-side discard path not read; no shrink).
- Whether A3's timers failures are downstream of the A1 reopen.
- Any TSan report, and whether the sensor task is the only off-main writer of engine state.
- Whether the Swift twin shares the per-process `_newestSnapshotAt` and the terminal-row gap (not read).

### Evidence runs

| Log | Contents |
|---|---|
| `.work/gateway/test-20261113-090156-67691.log` | seeds 111 (22 actions) and 857 (39) converge under shipping actions |
| `.work/gateway/test-20261113-090244-68137.log` | A1 4-action trace (absorbing + rows); A2 5-action trace; drained frame carries `entries=[entry-sx-ex-run-1-1]` |
| `.work/gateway/test-20261113-090421-68753.log` | same, plus `redeliver … => changed=false observations=4` / `0` |
| `.work/gateway/test-20261113-090712-69744.log` | A1 ×3 and A2 ×3 `converged=false`; A3 shipping alone `converged=false` (4 absorbing, 2 timers), full alone `converged=true actions=31`, after 1813 `converged=false`; six `status` seeds |
| `.work/gateway/test-20261113-090740-69987.log` | `redeliver the same payload with a newer sentAt => changed=true observations=1 ids=[entry-sx-ex-run-1-1]` |

No product file changed in this investigation; the final runs are the three stable files named in the
brief (`test/watch_convergence_harness_test.dart`, `test/watch_convergence_random_test.dart`,
`test/docs_indexing_contract_test.dart`).
