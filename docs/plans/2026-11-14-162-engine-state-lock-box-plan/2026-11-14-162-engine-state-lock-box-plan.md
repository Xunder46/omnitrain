# Feature: the watch engine's session state gets a lock (plan 162)

> Status: Iteration 1 active (planned from 159's findings; owner pre-approved building before launch)
> Next handoff: @code-reviewer (Phase 1 implemented — slice 1 green)
> Binding conventions: docs/global_conventions.md

## Overview

Plan 159 proved one data race in `WatchSessionEngine` with Thread Sanitizer — the three
energy-announce marks (`energyAnnouncedSession`, `energyAnnouncedKcal`, `energyAnnouncedAt`,
`WatchSessionEngine.swift:1856-1858`) are read at `:1879-1883` and written at `:1901-1903` from
`announceEnergy`, which the sensor stream calls off the main actor while a second stream task can
call it again. The same investigation classified `current`, `sessionRows`, `appliedChangeIds` and
`newestSnapshotAt` as crash-capable by construction (a torn copy damages refcounts, which TSan does
not instrument — three instrumented attempts produced zero reports on them, which is **not**
evidence of safety).

This plan lands the findings' **Option A** in **two slices = two commits = two PRs**, because only
the first slice is proven:

- **Slice 1 (commit 1):** the three energy marks read-compare-write atomically in `announceEnergy`.
- **Slice 2 (commit 2):** `current`, `sessionRows`, `appliedChangeIds`, `newestSnapshotAt` behind
  one synchronous lock holder, new file `WatchEngineSessionState.swift`.

Swift only under `watch/watchos`, plus the plan/evidence and one doc paragraph. No protocol or frame
change, no change to emitted ordering, replay corpus and full Swift suite stay green unchanged.

Pattern to follow: plan 150's lock boxes (`WatchEngineRowLogs.swift`, `WatchSensorSampleLog.swift`,
`WatchEntryLensLog.swift`) — one `NSLock` per box, only the memory operation inside it, **never held
across an `await`**. `WatchAsyncMutex.swift`'s header is the complementary rule: the async mutex is
**non-reentrant, never nest `exclusive` inside `exclusive`**.

## Resolved Decisions (Ledger)

- **D-16201 (slice 1)** The three energy marks sit behind one synchronous `NSLock` declared in
  `WatchSessionEngine.swift` (no new file; ~15 changed lines, no reader changes — the marks have
  exactly one reader and one writer, both inside `announceEnergy`). **One critical section spans
  the guard evaluation, the envelope assembly, the validator check and the three writes**;
  `emit` (and `noteRefused`) run after the lock is released. Rationale: the check (`:1879-1883`)
  and the writes (`:1901-1903`) must be one section so two callers cannot both pass the guard, and
  excluding the envelope/validate step from it would either reopen the race or — if the marks were
  recorded before validation — change behaviour (a refused frame must write no mark, so a later
  caller can retry; that is today's behaviour and it is preserved). `storedSensorSamples.samples(forSession:)`
  and `WatchSensorSummaries.activeEnergy` stay **outside** the section (they take the sensor log's
  lock; the section takes no other lock), and computing `total` there is unchanged. `announceEnergy`'s
  read of `current` at `:1870` stays unlocked until slice 2.
- **D-16202 (slice 2)** One box, `WatchEngineSessionState` in new file
  `watch/watchos/Sources/WatchSessionEngine/WatchEngineSessionState.swift` — same style as
  `WatchObservationLog`/`WatchTimerLog`/`WatchSensorSampleLog`: one `NSLock`, every accessor takes
  the lock and returns a copy, **no accessor awaits**. It holds exactly four values: `current`
  (`WatchSessionRecord?`), `sessionRows` (`[WatchSessionRecord]`), `appliedChangeIds`
  (`Set<String>`), `newestSnapshotAt` (`Date?`). Suggested members (names are mechanics, the
  append-only naming rule of `testS004NoMutatingOperationExistsAnywhereInTheModule` is not):
  `record() -> WatchSessionRecord?`; `mirror(_ row:) -> WatchSessionRecord` (append-if-not-held +
  set current, one acquisition — replaces `mirrored(_:)`'s body); `rows() -> [WatchSessionRecord]`;
  `rowCount` (internal, for S-16203's monotonicity assertion); `fill(rows:current:appliedChangeIds:newestSnapshotAt:)`
  (restore's four writes under one acquisition); `firstApply(changeId:) -> Bool` (true when the id
  was new — replaces `appliedChangeIds.insert(changeId).inserted` at `:818`);
  `advanceSnapshot(sentAt:) -> Date` (the `max(newestSnapshotAt ?? sentAt, sentAt)` at `:690` under
  the lock — "advance" is not a mutation verb in the S-004 list), and `snapshotWatermark() -> Date?`
  (the read side of `newestSnapshotAt`, used by `applySnapshotExclusive`'s `:593` gate).
- **D-16203 `restore()` does not take `mutex`.** Call sites (grep: `restore()` is called from
  `WatchAppHost.restore()` and `WatchAppHost.recoverStrandedWorkout()` in
  `ios/OmniTrain Watch App/ContentView.swift`, and from tests): `restore()` first `await store.readAll()`,
  then writes the four values with no lock (`:177-186`). A mutex taken for the writes would be
  legal (no await inside them) but would **change behaviour**: today a gated writer's `mirrored`
  row appended between `readAll()` and `restore()`'s whole-array assignment is clobbered by the
  fill, and the mirror ends up on `restore()`'s row; under the mutex the writer's row would win.
  Keep behaviour identical: the four writes become **one `fill` acquisition** in the state box —
  atomic to readers (no torn read of a half-restore), same interleaving-with-writers semantics as
  today (the last `fill` wins, exactly as today's last assignment wins). Whether a frame arriving
  during restore should adopt or defer stays the existing logic question around
  `adoptedBeforeRestore` (`WatchWorkoutLifecycle`, plan 150 D-15004) and its tests — this plan does
  not touch it.
- **D-16204 Lock order: `mutex → state lock`, never the reverse.** Every gated writer body
  (`createSessionExclusive`, `applySnapshotExclusive`, `applyStructureChangeExclusive`,
  `applyLifecycleExclusive`, `transitionToExclusive`, `pruneSettledSensorSamplesLocked`) takes the
  state lock only inside synchronous spans; `restore()` takes only the state lock; no state-lock
  section ever awaits. The energy-marks lock (D-16201) is a third lock: `announceEnergy` reads the
  state (state lock acquired and released) **before** entering the marks section — the two are
  never held at the same time, so no cycle exists on any path. The sensor-sample, observation,
  timer, lens and acknowledgement locks keep their existing independence; no box accessor takes a
  second box's lock, so no new nesting is introduced anywhere.
- **D-16205 Coherent reads.** The derived accessors `entries`, `observations`, `sensorSamples`,
  `newestSensorSamples()` and `timerRows(_:)` read `current?.sessionId` **once per call** (into a
  local) and filter the log snapshot against that value. Today `observations` (`:209`) and
  `timerRows` (`:262`) re-read `current?.sessionId` inside the filter closure — an interleaved
  writer can make the same call answer the previous session's rows or an empty list. Reading once
  is the tightening the brief pins (c); it also matches `entries`/`sensorSamples`, which already
  read once (`:274`, `:219`).
- **D-16206 Source-scan guard.** A test scans `WatchSessionEngine.swift` (comment lines stripped)
  for plain mutable stored property declarations at class-member indent — lines matching
  `^    (?:private |internal |public |fileprivate )*var \w+: [^{=]*$` (stored, no initializer) and
  `^    (?:private |internal |public |fileprivate )*var \w+ =` (stored, initialized). After slice 2
  the allowed set is exactly `{announcedCountdownKeys}` (written after init by
  `WatchTimerHaptics.swift:72`; boxing it is out of scope here — see Open questions). A new plain
  mutable stored property fails the test with a message pointing at the state box. Computed
  properties are excluded because every computed `var` in this file opens its brace on the
  declaration line; a stored property whose initializer is written on a following line would be
  missed — accepted (the file's convention is one-line declarations, and this is a guard against
  the drift class, not a parser). The box's own file is deliberately not scanned: holding `var`
  state behind its lock is its whole job. Feasible — the repo already has this pattern
  (`testS004NoMutatingOperationExistsAnywhereInTheModule` scans `Fixtures.sourcesRoot`;
  `Fixtures.swift:17-29` gives the paths).
- **D-16207 No protocol, frame, ordering or Dart change.** Nothing in `lib/`, `watch/contract/`,
  `watch/sync_protocol/` or the emitted frame sequence moves. The state lock only replaces
  unsynchronised reads and writes of the same values. Regression surface: the replay corpus
  (`WatchReplayTests`, 16/16) and the full Swift suite (baseline **1430 tests, 0 failures**;
  159's 1434 included the 4 parked scratch tests the governor deletes) stay green **unchanged**.

## Feature Invariants

- The state lock is synchronous and is never held across an `await` (D-16202, D-16204).
- The marks section contains no `await`, takes no second lock, and calls neither `emit` nor
  `noteRefused` (D-16201).
- `restore()` stays outside `mutex` and its four writes are one acquisition (D-16203).
- Every implementation-observable value is unchanged: same frames, same order, same refusals, same
  retry-after-refusal behaviour (D-16201, D-16207).

## Requirements

1. Slice 1: two concurrent `announceEnergy` callers cannot both pass the announce guard; a refused
   frame writes no mark; the announce rule (first for the session, a fallen total, or a rise of
   ≥ 0.5 kcal with ≥ 5 s since the last announcement) is evaluated against the marks as they stand
   at the moment of the decision.
2. Slice 2: the four named properties are never read or written outside the box; each access is
   one acquisition; the derived accessors read the session id once per call (D-16205).
3. Both slices: TSan race tests per the scenarios below; the source-scan guard of D-16206; docs
   updated by zero phases behind the code.

## Acceptance Criteria (each maps to ≥ 1 scenario)

- Two simultaneous announcements for the same total emit exactly one `energy_live` frame (S-16202).
- Under TSan, no report names the energy marks or any of the four boxed values (S-16201, S-16203,
  S-16204).
- A reader copying the engine's session during `restore()` + `advanceExercise` writers never sees a
  torn or shrinking mirror: no trap, `sessionRows` non-decreasing, every copied row internally
  coherent (S-16203).
- The shipping writer mix (taps, phone frames, restore, sensor stream) against every read accessor
  produces no trap and a still-coherent mirror (S-16204).
- `WatchSessionEngine.swift` declares no plain mutable stored property outside the allowed set
  (S-16205).
- Replay corpus 16/16 and full suite 1430/0 green after each phase that touches source (D-16207).

## Existing-Functionality Impact

Grep evidence from 159's findings (§2, §4), re-verified at planning:

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `energyAnnounced*` marks (`:1856-1858`) | only `announceEnergy` (`:1879-1883`, `:1901-1903`) — grep `energyAnnounced` | slice 1 makes its one read-compare-write atomic; no reader changes | S-16201, S-16202 |
| `current` (`:143`) | ~28 sites — `session`, `currentExercise`, `observations`, `sensorSamples`, `newestSensorSample(s)`, `timerRows`, `entries`, `sessionSnapshot`, `createSessionExclusive`, `selectExercise`, `applyMessage`'s `exercise_push` branch (`:539-541`), `applySnapshotExclusive`, `applyStructureChangeExclusive`, `applyLifecycleExclusive`, `applyTimerState`, `jumpTarget`, `storeSessionRow`, `mirrored`, `logNutrition`, `announceEnergy`, `adoptTimers`, `applyReceipt`, `requireSession` — grep `\bcurrent\b` (45 hits, incl. comments) | slice 2 routes every one through `state.record()`; writers through `state.mirror`/`fill`; behaviour per-site identical | S-16203, S-16204, D-16203/04/05 |
| `sessionRows` (`:76`) | `restore():177`, `mirrored():1579`, `holdsTerminalRow():733`, `newestSessionRows():1974`, `creationRow():2152` — grep `sessionRows` | same routing via `state.rows()`/`mirror`/`fill` | S-16203 |
| `appliedChangeIds` (`:92`) | `restore():178`, `applyStructureChangeExclusive:818` — grep `appliedChangeIds` | routed via `state.fill`/`firstApply` | S-16204 (mix), D-16204 |
| `newestSnapshotAt` (`:97`) | `restore():183-186`, `applySnapshotExclusive:593` (read) + `:690` (write) — grep `newestSnapshotAt` | routed via `state.fill`/`advanceSnapshot`; the read→write gap stays the mutex's job (the pair is inside one gated body; no await inside the state-lock spans) | D-16204 |
| Sensor/observation/timer/lens/acknowledgement logs | plan 150's boxes | untouched; D-16204 pins that no new nesting is introduced | S-16204 (runs over all accessors) |
| `restore()`'s clobber semantics | `WatchAppHost.restore()`, `recoverStrandedWorkout()`; plan 150's `WatchWorkoutAdoptBeforeRestoreTests` | unchanged (D-16203); `adoptedBeforeRestore` logic untouched | D-16203, existing tests |
| Flutter app, sync contract, watch Dart mirror | grep: no reader of these Swift symbols outside `watch/watchos/Sources/WatchSessionEngine` and the app target's call sites, which use public API only | unaffected — public API surface unchanged | D-16207 (full suite green) |

## UI Standards Impact

None — no screen, widget or navigation change. `docs/design_system.md` untouched.

## Scenarios

- **S-16201: the energy marks under two announcing callers (TSan, S-zz2's shape)**
  - Fixture: engine over `SerialSessionStore` + `LockedFrameSink`, `validator: Harness.validator()`,
    `clock: { testInstant() }`, `sessionIdFactory: { "s-race" }`; `restore()`; one active
    `cardio_endurance` session via `createSession(modality:exercises: [exercise("sx-run")])`; **no
    stored sensor samples**, so `announceEnergy`'s total is the raw `kilocalories` argument (the
    no-stored-sample branch of `WatchSensorSummaries.activeEnergy ?? kilocalories`). Two writer
    tasks (detached, off the main actor, the sensor stream's layout) announce the **same rising
    sequence**: round *r* announces `Double(r) * 0.5` at `testInstant().addingTimeInterval(Double(r) * 10)`
    (rise ≥ 0.5 and spacing ≥ 5 s, so every accepted round would emit). Eight GCD reader threads
    loop over the read accessors (`session`, `currentExercise`, `observations`, `sensorSamples`,
    `newestSensorSamples()`, `timerRows`, `entries`, `sessionSnapshot()`) for the whole window
    (1.5 s, the S-zz2 reader set).
  - Trigger: both writers loop `announceEnergy` concurrently for the window.
  - Flow: each caller reads the marks, evaluates the rule, writes the marks.
  - Expected outcome: **red at HEAD under TSan with reports naming `WatchSessionEngine.swift`
    `announceEnergy` at `:1901-1903` (and the `:1879-1883` reads) — the 159 attempt-1/2 shape;
    green after slice 1 with zero reports naming the marks.** Without TSan: no trap, and every
    emitted `energy_live` frame's `activeEnergyKcal` is pairwise distinct (a total is announced at
    most once across both callers).
  - Edge case of: none.
- **S-16202: two simultaneous announcements for the same total emit ONE frame (behaviour pin)**
  - Fixture: same engine fixture as S-16201; **no other writers**; one round: two detached tasks
    each call `announceEnergy(kilocalories: 12.0, at: testInstant())` once, started together in a
    task group.
  - Trigger: the two calls overlap.
  - Flow: the first caller's section records the marks; the second's compare sees them and
    suppresses (same total, rise 0 < 0.5).
  - Expected outcome: exactly **one** `energy_live` frame in the sink, `activeEnergyKcal == 12.0`.
    Red at HEAD is not guaranteed (the race window is narrow and probabilistic) — this is a pin,
    green-after required; S-16201's TSan run is the red evidence.
  - Edge case of: S-16201.
- **S-16203: `current`/`sessionRows` under restore + taps (TSan, S-zz4's shape)**
  - Fixture: engine as S-16201; one active `strength` session with two exercises
    (`exercise("sx-bench")`, `exercise("sx-row")`) created before the window. Writers: one task
    looping `restore()` and one task looping `advanceExercise()` — the narrowest `current` probe
    (159 §5), both writing `current`/`sessionRows` (restore via `fill`, taps via `mirror`). Eight
    GCD reader threads copy `session`, `currentExercise`, `entries`, `sessionSnapshot()` for the
    window (1.5 s).
  - Trigger: both writers loop for the window while readers copy.
  - Flow: readers take copies of the box's values.
  - Expected outcome: no trap; `engine.session?.sessionId == "s-race"` and status `.active` at
    window end (restore always finds the session's rows in the store; `advanceExercise` never ends
    it); every copied row is internally coherent — its `sessionId` is `s-race`, its
    `currentExerciseIndex` < `exercises.count` while active; `engine.sessionRowCountForTesting`
    never decreases within one reader's sequence (the fixture prunes nothing, so the store only
    grows and every `fill` is a superset). **Honest note (repeated from the brief): green at HEAD
    by design — TSan could not see these races before (refcount damage is not instrumented), so
    this test proves no regression and exercises the lock; the by-construction argument in 159 §6
    is the justification, not this test.**
  - Edge case of: none.
- **S-16204: the full writer mix against every accessor (TSan, S-zz1's mix)**
  - Fixture: engine as S-16201; one active `strength` session with two exercises. Writers, all live
    for the window (1.5 s), each in its own detached task: taps (`advanceExercise` +
    `appendObservation(setEvent(clock, entryId: "e-tap-\(r)"))`), phone frames
    (`applyMessage` of a conformant `structure_change` with `add_exercise`, the shape plan 150's
    S-15031 used — that shape **applies**; the scratch fixtures 159 tried were refused), `restore()`,
    and the sensor pair (`appendSensorSample(kind: .activeEnergy, value: Double(r) * 0.5, recordedAt: …)`
    then `announceEnergy`). Eight GCD reader threads loop over **all** accessors: `session`,
    `currentExercise`, `observations`, `sensorSamples`, `newestSensorSamples()`, `timerRows("work")`,
    `entries`, `sessionSnapshot()`, `pendingObservations()`, `unconfirmedObservations`,
    `nutritionLog`, `waterLog`, `hasEffortRating(Self.sessionId)`.
  - Trigger: all four writers loop for the window.
  - Flow: readers exercise every accessor while all four boxed values change.
  - Expected outcome: no trap; `engine.session?.sessionId == Self.sessionId` at window end; TSan
    reports nothing on the engine's state (test doubles may warn, as in plan 150's runs — none in
    `Sources/`). Do **not** assert "every logged set survived": `restore()`'s concurrent `fill`
    legitimately replaces the log mid-window (today's behaviour, D-16203).
  - Edge case of: S-16203.
- **S-16205: the engine declares no un-boxed plain mutable stored property (source scan)**
  - Fixture: `WatchSessionEngine.swift` read from `Fixtures.sourcesRoot`, comment lines stripped
    (the `WatchHostHopSourceTests` stripping pattern).
  - Trigger: the scan matches stored declarations per D-16206's two patterns.
  - Expected outcome: the matched names are exactly `{announcedCountdownKeys}` — each allowed name
    carries a reason in the test's comment. Red at HEAD is not applicable (the test lands **after**
    slice 2 removed `current`/`sessionRows`/`appliedChangeIds`/`newestSnapshotAt`); its guard value
    is a mutation test: re-adding `private var probe: Int = 0` to the engine must turn it red
    (prove that once, then revert).
  - Edge case of: none.

## Iteration 1

### Phase 1: slice 1 — the energy marks get one critical section (@developer) — **commit 1 / PR 1**
1. [x] In `WatchSessionEngine.swift`, add `private let energyMarksLock = NSLock()` beside the marks
   (replacing the three `private var energyAnnounced*` declarations' plain access with locked
   access) and rewrite `announceEnergy(kilocalories:at:)` so that **one synchronous section** spans
   the rule check (`:1879-1883`), the envelope assembly, the `validator.validateEnvelope` check,
   and the three mark writes (`:1901-1903`); `emit(envelope)` and `noteRefused(...)` run after the
   lock is released; `storedSensorSamples.samples(forSession:)` +
   `WatchSensorSummaries.activeEnergy` stay outside (D-16201). Symbol: `announceEnergy(kilocalories:at:)`.
2. [x] Same file, symbol `announceEnergy(kilocalories:at:)`: the section returns the envelope (or a
   suppression/refusal outcome); a refused frame writes no mark and reports via `noteRefused`
   exactly as today; a suppressed call writes nothing and returns — no behaviour change in any
   single-threaded path (plan 135's energy tests stay green unchanged).
3. [x] New test file `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift`:
   `testS16201EnergyMarksSurviveTwoAnnouncingCallers` — S-16201's fixture, 8 readers, 2 writers,
   1.5 s window; asserts pairwise-distinct `energy_live` totals and ≥ 1 frame without TSan.
4. [x] Same file: `testS16202TwoSimultaneousAnnouncementsEmitOneFrame` — S-16202's one-shot pin.
5. [x] Prove red at HEAD: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --sanitize=thread --filter WatchEngineStateBoxRaceTests` — TSan must report races naming
   `WatchSessionEngine.swift` `announceEnergy` (the 159 attempt-1/2 shape). Record the report
   counts and lines in the evidence file. If TSan reports nothing naming `announceEnergy`'s marks in one attempt, widen the window
   to 3 s and retry once; a second empty run stops the phase for review.
6. [x] Green: `.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread --filter "WatchSensorSampleRaceTests|WatchEngineListRaceTests|WatchEngineSessionStateRaceTests|WatchStoreGrowthTests|WatchEngineStateBoxRaceTests"` — zero reports naming the marks; pre-existing test-double warnings may remain.
7. [x] Full suite: `.github/copilot/scripts/macos/gateway.sh swift-test` — 1432 tests, 0 failures
   (baseline 1430 + 2 new), replay corpus `WatchReplayTests` 16/16 within it.
8. [x] One sentence in `docs/state_management/watch_sensors.md`'s "One writer." paragraph
   (~line 317-334): the energy marks announce under one synchronous lock
   (`WatchEngineStateBoxRaceTests.testS16201EnergyMarksSurviveTwoAnnouncingCallers`). Doc is
   38.7 KB — far under the 52 KB split band; one sentence keeps it there.

**Phase 1 results** (one line per item):
1. Marks + `energyMarksLock` added; `announceEnergy` keeps `samples`/`total` outside and switches on the section's outcome — `emit`/`noteRefused` run unlocked.
2. Section is `energyAnnouncement(row:total:at:)` returning `EnergyAnnouncement` (`.suppressed` / `.send` / `.refused`); refusal writes no mark; plan 135's energy tests green unchanged in the full run.
3. `WatchEngineStateBoxRaceTests.testS16201EnergyMarksSurviveTwoAnnouncingCallers` — 8 readers, 2 detached announcers, shared round counter, pairwise-distinct totals asserted.
4. `…testS16202TwoSimultaneousAnnouncementsEmitOneFrame` — one frame, `12.0`.
5. `prove-red HEAD … --sanitize=thread --filter WatchEngineStateBoxRaceTests` → **RED AT HEAD (exit 1)**, 10 TSan warnings, all on `announceEnergy` `:1901`/`:1902` vs `:1879`; S-16202 also red (2 frames).
6. TSan filter ×3: 21 tests, 0 failures each (29.9 s / 27.8 s / 29.6 s), zero reports naming the marks or any engine state.
7. Full suite: **1432 tests, 0 failures** (baseline 1430 + 2; the plan's 1431 was an arithmetic slip); `WatchReplayTests` 4/4 inside it.
8. `docs/state_management/watch_sensors.md` "One writer." gains two sentences naming both new tests; file still well under the 52 KB band.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` full
green; the TSan filter command of item 6 green with zero engine-state reports; the prove-red run of
item 5 recorded red at HEAD in `docs/plans/2026-11-14-162-engine-state-lock-box-plan/2026-11-14-162-engine-state-lock-box-plan.evidence.md`;
Progress and Assumption Log updated.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`;
`watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift` (new);
`docs/state_management/watch_sensors.md`; the plan's `.evidence.md`.
**Phase 1 verification notes (Conductor, date):** *(added at verification)*

### Phase 2: slice 2a — `current` and `sessionRows` move into the box (@developer) — starts commit 2 / PR 2
1. [x] Create `watch/watchos/Sources/WatchSessionEngine/WatchEngineSessionState.swift` — symbol
   `WatchEngineSessionState`, per D-16202's member list (`record`, `mirror`, `rows`, `rowCount`,
   `fill(rows:current:)` for this phase — the appliedChangeIds/newestSnapshotAt parameters come in
   Phase 3). Header comment states the lock discipline (never across an `await`) and the lock order
   (D-16204), mirroring `WatchEngineRowLogs.swift`'s header.
2. [x] `WatchSessionEngine.swift`: delete the `private var sessionRows` (`:76`) and
   `private var current` (`:143`) declarations; add `private let state = WatchEngineSessionState()`;
   rewrite `restore()`'s writes (`:177`, and `:190`'s `lensLog.fill(hidden: Set(current?.deletedEntryIds ?? []))`
   — use the local row the fill set, not a second read) through one `state.fill(rows:current:)`
   (D-16203). Symbol: `restore()`.
3. [x] Rewrite the writers to the box, symbols `mirrored(_:)` (`:1577-1582`) and
   `storeSessionRow(_:)` (`:1324-1328`): the append-if-not-held + set becomes one `state.mirror(row)`
   acquisition; `mirrored` becomes a thin wrapper (or is inlined — mechanic) so
   `createSessionExclusive`, `transitionToExclusive`, `applySnapshotExclusive` and
   `applyStructureChangeExclusive` keep their call shapes.
4. [x] Rewrite the public accessors, symbols `session` (`:203`), `currentExercise` (`:205`),
   `sessionSnapshot(messageId:)` (`:307-308`), `requireSession()` (`:2584-2590` — read **once** into
   a local, then guard and return it, so the guard and the return cannot see different values).
5. [x] Rewrite the session-id accessors reading the id **once per call** (D-16205), symbols
   `observations` (`:209`), `sensorSamples` (`:219`), `newestSensorSample(_:)` (`:235`),
   `newestSensorSamples()` (`:247`), `timerRows(_:)` (`:262`), `entries` (`:274`).
6. [x] Rewrite the message-path reads, symbols `applyMessage(_:)`'s `exercise_push` branch
   (`:539-541` — two separate box reads, the same gap as today), `applySnapshotExclusive(_:)`
   (`:597`, `:620`), `applyStructureChangeExclusive(_:)` (`:815` — the `appliedChangeIds` at `:818`
   stays plain until Phase 3), `applyLifecycleExclusive(_:)` (`:861`), `applyTimerState(_:)`
   (`:992`).
7. [x] Rewrite the remaining readers, symbols `createSessionExclusive(_:)` (`:367`),
   `selectExercise(slotId:)` (`:411`), `jumpTarget(_:)` (`:1151`), `logNutrition(_:at:)` (`:1721`),
   `announceEnergy(kilocalories:at:)`'s guard (`:1870`), `adoptTimers(_:)` (`:2373`, `:2385`),
   `applyReceipt`'s fallback (`:2434`), `holdsTerminalRow(_:)` (`:733`), `newestSessionRows()`
   (`:1974`), `creationRow(_:)` (`:2152`) — the three `sessionRows` scanners read `state.rows()`
   (an O(n) copy per read; the row lists are small, and it matches the other boxes' `snapshot()`
   style).
8. [x] Compile and run: `.github/copilot/scripts/macos/gateway.sh swift-test` — full suite green
   (1432/0), `WatchReplayTests` 4/4, no test file changed in this phase (the migration is
   behaviour-preserving; the race tests come in Phase 4). Focused run of the box's race file after
   the migration: `Executed 4 tests, with 0 failures`.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` full
green unchanged; a grep-tool sweep (recorded in evidence): `grep -n "state\.\|sessionRows\|\bcurrent\b"`
over `WatchSessionEngine.swift` shows zero plain reads/writes of the two moved values outside the
box — every remaining hit is `state.` access or comment; Progress + Assumption Log updated.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchEngineSessionState.swift` (new);
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`. Nothing else.
**Phase 2 results** (one line per item):
1. `WatchEngineSessionState.swift` created with `record`/`mirror`/`rows`/`rowCount`/`fill`; header states `mutex → state lock` and no await across the lock.
2. Both declarations gone; `private let state` added; `restore()` writes once via `state.fill(rows:current:)` and takes `lensLog`'s hidden set from the local.
3. `mirrored(_:)` is a thin wrapper over `state.mirror(row)`; `storeSessionRow` calls it without assigning; the four callers unchanged.
4. `session`, `currentExercise`, `sessionSnapshot(messageId:)` and `requireSession()` read the box; `requireSession()` reads once into a local.
5. The six session-id accessors read `state.record()` once per call.
6. The message-path reads (`exercise_push`, `applySnapshotExclusive`, `applyStructureChangeExclusive`, `applyLifecycleExclusive`, `applyTimerState`) go through the box; the payload local was renamed `lifecycleState` (A-16212).
7. The remaining readers routed, the three `sessionRows` scanners through `state.rows()`.
8. Focused `WatchEngineStateBoxRaceTests` run: 4/4, 0 failures (`.work/gateway/swift-test-20261114-170955-52191.log`); full suite green (§15 of evidence).

**Phase 2 verification notes (Conductor, date):** *(added at verification)*

### Phase 3: slice 2b — `appliedChangeIds` and `newestSnapshotAt` move in; restore writes all four at once (@developer)
1. [x] `WatchEngineSessionState.swift`, symbol `WatchEngineSessionState`: add the `appliedChangeIds`
   and `newestSnapshotAt` members (`firstApply(changeId:)`, `advanceSnapshot(sentAt:)`, and widen
   `fill` to take all four values — restore's writes become one acquisition over the full state,
   D-16203).
2. [x] `WatchSessionEngine.swift`: delete `private var appliedChangeIds` (`:92`) and
   `private var newestSnapshotAt` (`:97`); rewrite `restore()` (`:178-186`) to the widened `fill`.
   Symbol: `restore()`.
3. [x] `WatchSessionEngine.swift`, symbol `applyStructureChangeExclusive(_:)` (`:818`): the guard
   becomes `state.firstApply(changeId)` — the check and the insert are one acquisition, replacing
   today's `insert(...).inserted` (which was already atomic on the plain `Set`, so no behaviour
   change; the box makes it race-free against `restore()`'s fill).
4. [x] `WatchSessionEngine.swift`, symbol `applySnapshotExclusive(_:)`: `:593` becomes
   `state.snapshotWatermark()`-style read and `:690` becomes `state.advanceSnapshot(sentAt:)`. The
   read→write gap keeps its today shape: both sites sit inside one `mutex.exclusive` body, and the
   awaited store writes between them mean the state lock must NOT span them (D-16204) — writer
   serialisation is the mutex's job (brief point (b)).
5. [x] Run: `.github/copilot/scripts/macos/gateway.sh swift-test` — full suite green (1432/0),
   replay 4/4. Confirm by grep (evidence): `appliedChangeIds` and `newestSnapshotAt` appear in
   `WatchSessionEngine.swift` only as the `state.fill` argument labels, `restore()`'s locals, the
   watermark local's scanned guard line, or comments.

**Done Criteria** (run until green): full `swift-test` green unchanged; the grep sweep above clean;
Progress + Assumption Log updated.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchEngineSessionState.swift`;
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`. Nothing else.
**Phase 3 results** (one line per item):
1. `firstApply(changeId:)`, `snapshotWatermark()`, `advanceSnapshot(sentAt:)` added and `fill` widened to all four values.
2. Both declarations gone; `restore()` fills the whole state in one acquisition.
3. The structure guard is `state.firstApply(changeId)` — one atomic test-and-insert.
4. The snapshot gate reads `state.snapshotWatermark()` into a local named `newestSnapshotAt` (so S-9315's scanned line stays verbatim, A-16213) and the write calls `state.advanceSnapshot(sentAt:)`; neither state-lock section spans an await.
5. Full suite 1435/0 (§15 of evidence) after one unplanned red — `WatchInboundLaneWiringSourceTests.testS9315…` scanned the rewritten guard literal; fixed by the local binding, no existing test edited.

**Phase 3 verification notes (Conductor, date):** *(added at verification)*

### Phase 4: slice 2 tests — race, mix, source scan (@developer)
1. [x] `WatchEngineStateBoxRaceTests.swift`: `testS16203MirrorSurvivesRestoreAndTaps` — S-16203's
   fixture (restore + advanceExercise writers, 8 readers copying `current`), coherent-read and
   non-shrinking assertions, using the engine's internal `sessionRowCountForTesting`
   (`@testable import` sees internal members; the accessor is added to `WatchSessionEngine.swift`
   beside `sensorRowsVisitedForTesting`, `:232`).
2. [x] Same file: `testS16204FullWriterMixSurvivesAllAccessors` — S-16204's fixture (taps, phone
   `structure_change` frames in the S-15031 shape, restore, sensor pair; 8 readers over all 13
   accessors).
3. [x] New file `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxSourceTests.swift`:
   `testS16205EngineDeclaresNoUnboxedMutableState` — D-16206's scan, allowed set
   `{announcedCountdownKeys}` with the reason in the comment; mutation-proof it once (add
   `private var probe: Int = 0` to the engine, see the test red, revert) and record the red in the
   evidence file.
4. [x] TSan: `.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread --filter "WatchSensorSampleRaceTests|WatchEngineListRaceTests|WatchEngineSessionStateRaceTests|WatchStoreGrowthTests|WatchEngineStateBoxRaceTests"` — green, zero engine-state reports. **Recorded limit of the proof (state it in
   the evidence file verbatim): TSan cannot see the refcount/`memcpy` damage these races cause, so
   S-16203/S-16204 were also green at HEAD before the box; the tests prove no regression and
   exercise the lock; the by-construction argument (159 §6) is the justification.**
5. [x] Full suite: `.github/copilot/scripts/macos/gateway.sh swift-test` — 1435 tests, 0 failures
   (1432 + 3 new), `WatchReplayTests` 4/4.

**Done Criteria** (run until green): full `swift-test` green; TSan filter green; the source-scan
mutation proof recorded; Progress + Assumption Log updated.
**Predicted Files**: `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift`;
`watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxSourceTests.swift` (new);
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (only the
`sessionRowCountForTesting` accessor); the plan's `.evidence.md`. Nothing else.
**Phase 4 results** (one line per item):
1. `testS16203MirrorSurvivesRestoreAndTaps` — restore + tap writers, 8 readers, coherence notes plus "never zero rows while a session is held" (the non-shrinking assertion contradicted D-16203, A-16211).
2. `testS16204FullWriterMixSurvivesAllAccessors` — four writers, 8 readers over all 13 accessors.
3. `testS16205EngineDeclaresNoUnboxedMutableState` — drift guard; allowed set is four names because slice 1 kept the energy marks plain (A-16210); mutation proof RED then reverted green (evidence §12).
4. TSan filter 27 tests, 0 failures, no `ThreadSanitizer` line in the log; the test block's honest limit is recorded verbatim in evidence §12.
5. Full suite 1435/0 with the box's 4 tests and `WatchReplayTests` 4/4 inside it.

**Phase 4 verification notes (Conductor, date):** *(added at verification)*

### Phase 5: docs, residue sweep, consolidated verification (@developer)
1. [x] Extend the `docs/state_management/watch_sensors.md` paragraph (~38.8 KB, still far under the
   52 KB band): the session mirror (`current`), the row list, the applied-change set and the
   snapshot watermark sit behind one synchronous lock (`WatchEngineSessionState`), `restore()`'s
   four writes are one acquisition, the lock order is `mutex → state lock` and no state-lock
   section awaits (`WatchEngineStateBoxRaceTests.testS16203MirrorSurvivesRestoreAndTaps`,
   `…testS16204FullWriterMixSurvivesAllAccessors`). Name the test file the doc rule requires.
2. [x] Residue sweep (record the grep in evidence): `grep -n "sessionRows\|appliedChangeIds\|newestSnapshotAt"`
   and `grep -n "\bcurrent\b"` over `watch/watchos/Sources/WatchSessionEngine/` — zero readers of
   the replaced plain representations remain outside `WatchEngineSessionState.swift` (S-16205's
   scan is the permanent structural guard for this class).
3. [x] Consolidated verification: `.github/copilot/scripts/macos/gateway.sh swift-test` (1435/0) and
   the TSan filter command of Phase 4 item 4, both recorded in the evidence file with pasted
   counts; `.github/copilot/scripts/macos/gateway.sh git-diff --name-only` to confirm the footprint
   is exactly the predicted files plus docs/plans and watch_sensors.md — no Dart, no contract, no
   `ios/` file.
4. [x] Update Progress and the Assumption Log (adjudication-ready), and the two-commit statement:
   commit 1 = Phase 1's files; commit 2 = Phases 2-5's files (the governor commits; do not commit
   yourself).

**Done Criteria**: both gateway commands green with pasted counts; residue grep clean; Progress +
Assumption Log complete.
**Predicted Files**: `docs/state_management/watch_sensors.md`; the plan's `.evidence.md`.
**Phase 5 results** (one line per item):
1. `docs/state_management/watch_sensors.md` "One writer." gains the box paragraph naming all three tests; ~39 KB, still under the band.
2. Residue sweep clean: the four names survive only inside `WatchEngineSessionState.swift`, as `state.fill` argument labels, as `restore()`'s locals and as the watermark local bound for S-9315's scanned line (evidence §17).
3. Full suite 1435/0 and TSan filter 27/0 with no `ThreadSanitizer` line; footprint is the two Swift files, the two new test files, `watch_sensors.md` and the plan pair — no Dart, no contract, no `ios/` file (evidence §18).
4. Progress and Assumption Log updated; commit 1 = Phase 1's files, commit 2 = Phases 2-5's files (governor commits).

**Phase 5 verification notes (Conductor, date):** *(added at verification)*

## Files Affected (whole feature; dependents that only read a touched surface marked)

- `watch/watchos/Sources/WatchSessionEngine/WatchEngineSessionState.swift` (new, Phase 2/3)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (Phases 1-4)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift` (new, Phases 1/4)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxSourceTests.swift` (new, Phase 4)
- `docs/state_management/watch_sensors.md` (Phases 1, 5)
- `docs/plans/2026-11-14-162-engine-state-lock-box-plan/` (plan, evidence)
- Read-only dependents (public API unchanged, no edit): `ios/OmniTrain Watch App/ContentView.swift`
  and every other app-target caller of the engine; `watch/watchos/Sources/WatchSessionEngine/WatchTimerHaptics.swift`
  (`announcedCountdownKeys`, untouched).

## Notes

- **Phase dependency graph:** 1 → 2 → 3 → 4 → 5, strictly linear: each phase edits the same two
  source files and Phase 4's tests assert Phase 2/3's end state. Re-ordering: Phase 4's S-16201/
  S-16202 tests belong to Phase 1 (they are its red proof); nothing else is movable without
  breaking compilation — Phase 2 without Phase 3 leaves two plain properties, which the Phase 4
  source scan would red-flag, so Phase 4 must follow Phase 3.
- **Intermediate state after Phase 2:** `appliedChangeIds`/`newestSnapshotAt` are still plain in the
  engine. That is a known intermediate, resolved by Phase 3 — do not "fix" it in Phase 2.
- **Why two commits:** only slice 1 is TSan-proven (159's three attempts, 20 reports, all on the
  marks). Slice 2's justification is by construction. Landing them separately lets slice 1 ship
  with its own red→green evidence even if slice 2's review raises questions. The slices share the
  plan but not a commit; the governor makes the two commits at the phase boundaries above.
- **Names are mechanics except where pinned:** the S-004 test (`WatchSessionEngineTests.swift:322`)
  scans every file under `Fixtures.sourcesRoot` for member funcs named with mutation verbs — the
  box's methods must not be named `set`/`update`/`replace`/`clear`/… (A-15001/A-15033's rule). The
  names suggested in D-16202 avoid the list; any substitute must too.
- **Test-double rules from plan 150 (reuse them):** race engines are built over `SerialSessionStore`
  (a plain store would race on its own rows and hide the engine's race), the shared sink is
  `LockedFrameSink`, readers run on real GCD threads (`DispatchQueue.global().async`) and writers
  as detached tasks for the whole window; the group wait is `awaitGroup` (never block a
  cooperative-pool thread the writers need).
- **Stale-comment risk:** the `mutex`'s doc comment (`:40-43`) says the gate serialises "the five
  session-row writers"; `pruneSettledSensorSamples` is the sixth and `restore()` never takes it —
  Phase 2 may correct that comment to match the box's reality (one line, no behaviour).

## Progress

- [x] Phase 1 — slice 1, the energy marks (commit 1) — **Complete**: 2 new tests, prove-red TSan red at HEAD, TSan filter ×3 clean, full suite 1432/0
- [x] Phase 2 — `current`/`sessionRows` into the box (commit 2) — **Complete**: box created, ~35 call sites routed, `restore()` writes once, focused race run 4/4
- [x] Phase 3 — `appliedChangeIds`/`newestSnapshotAt` into the box (commit 2) — **Complete**: wider `fill`, `firstApply`/`advanceSnapshot` gates; S-9315's scanned line kept verbatim
- [x] Phase 4 — slice 2 tests: race, mix, source scan (commit 2) — **Complete**: 3 new tests, 2 mutation proofs red then reverted, TSan filter 27/0
- [x] Phase 5 — docs, residue sweep, consolidated verification (commit 2) — **Complete**: doc paragraph names all three tests, residue sweep clean, full suite 1435/0

## Assumption Log

- **A-16201 (derived, vetoable)** The marks' critical section includes envelope assembly and
  validation, so a refused frame writes no mark (D-16201). Options: (a) record marks at decision
  time, validate after — smaller section, but a refused frame would poison the retry, a behaviour
  change; (b) record marks after validation outside the section — reopens the two-callers race.
  Chose (a-inverted): decision + validate + record in one synchronous section. Owner to confirm.
- **A-16202 (derived, vetoable)** S-16203's non-shrinking assertion uses an internal test-only
  accessor `sessionRowCountForTesting` on the engine (precedent:
  `sensorRowsVisitedForTesting`, `:232`). Options: public API (no — public surface must not grow
  for a test), internal accessor (chosen), or assert only post-window state (weaker). Owner to
  confirm.
- **A-16203 (derived, vetoable)** New race tests live in a new file `WatchEngineStateBoxRaceTests.swift`
  rather than appended to plan 150's `WatchEngineSessionStateRaceTests.swift` — one plan per test
  file's scenario mapping, matching how plan 150 split its own files. The TSan filter's `<new>` is
  therefore `WatchEngineStateBoxRaceTests`. Owner to confirm.
- **A-16204 (derived)** S-16202's red-at-HEAD is not guaranteed (the two-callers window is
  probabilistic); S-16201's TSan run is the red evidence for slice 1, and the brief's "red at HEAD
  with the reports on the marks" is satisfied by S-16201. Owner to confirm.
- **A-16205 (derived)** `announceEnergy`'s read of `current` at `:1870` is not inside the marks
  section (D-16201): the marks lock takes no second lock, and `current`'s own boxing is slice 2's
  business; after slice 2 the read is a state-lock acquisition released before the marks section
  (D-16204). Owner to confirm.
- **A-16206 (Phase 1, mechanics)** The section is a private method `energyAnnouncement(row:total:at:)`
  returning a three-case `EnergyAnnouncement` (.suppressed / .send / .refused), not an inline block
  with `defer`: Swift has no scoped unlock, and `emit`/`noteRefused` must run after release. 43
  added lines, not D-16201's ~15; behaviour identical. Owner to confirm.
- **A-16207 (Phase 1, test mechanics)** S-16201's two announcers take rounds from an `NSLock`-held
  counter (`AnnouncedRounds` in the test file) instead of both looping 0,1,2,…: a laggard re-taking
  an already-announced round would announce a fallen total and make the pairwise-distinct assertion
  flaky without proving anything about the marks. Owner to confirm.
- **A-16208 (Phase 1, observed)** S-16202 was red at HEAD without TSan (2 frames) and every TSan
  warning named `announceEnergy`; A-16204's "not guaranteed" held only as possibility, not in this
  run. No scope change.
- **A-16209 (Phase 1, plan arithmetic)** The full suite is **1432** tests (baseline 1430 + 2), not
  item 7's 1431 — 1430 + 2 = 1432. Recorded in evidence §4; D-16207's 1430 baseline stands.
  **Extended (slice 2):** 1432 + 3 new tests = **1435**, not Phases 2-5's 1431/1434. Evidence §15/§16.
- **A-16210 (Phase 2, slice 1's residue)** S-16205's allowed set is **four** names
  (`announcedCountdownKeys`, `energyAnnouncedSession`, `energyAnnouncedKcal`, `energyAnnouncedAt`),
  not D-16206's single `announcedCountdownKeys`: slice 1 kept the three marks as plain `var`s and
  made their accesses atomic with `energyMarksLock` (A-16206), so the scan would otherwise flag the
  accepted slice-1 design. Owner to adjudicate: boxing the marks is a separate slice.
- **A-16211 (Phase 4, scenario text)** S-16203's non-shrinking row-count assertion contradicted
  D-16203: `restore()`'s `readAll` snapshot can predate a tap's append, so its `fill` legitimately
  shrinks the mirror. The test asserts the property that must hold instead — the mirror never held
  zero rows while a session was held — and the scenario line was written before this was observed.
- **A-16212 (Phase 2, mechanics)** `applyLifecycleExclusive`'s local `let state = payload["state"]`
  collided with the engine's new `state` property and was renamed `lifecycleState` (three sites, no
  behaviour change). No public name changed.
- **A-16213 (Phase 3, existing-test constraint)** `WatchInboundLaneWiringSourceTests.testS9315…`
  scans for the literal `if let newest = newestSnapshotAt, sentAt < newest { return nil }`, so the
  snapshot gate binds the box value to a local named `newestSnapshotAt` directly above that
  unchanged line rather than inlining `state.snapshotWatermark()` into it. The plan predicted no
  existing test would move; this one did, and the fix keeps its scanned text intact instead of
  editing the test.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]

**Handoff: @code-reviewer — review Phases 2-5 (slice 2, the state lock box); commit 2 is the
governor's. Slice 2 is verified green (full suite 1435/0, TSan filter 27/0) but its red evidence is
two mutation proofs, not a TSan report — §12 of the evidence file states that limit.**
