# Feature: 152 — replay the pair harness's wrist traces against the real Swift engine

> Status: Iteration 1 active (product-level defaults applied; owner confirmations under Open questions)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md (Phase 4 doc work);
> brief: `.work/2026-11-10-145-convergence-test/brief-plan-152.md`

## What the owner gains (plain language)

Today the randomized convergence test proves that the **Dart copy** of the wrist agrees with the
phone. The engine that actually ships on the wrist is the **Swift** one
(`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`), and it is only checked against
shared reconciliation fixtures and unit tests — not against the 200-seed stories the pair harness
runs. The two engines already differ in at least one shipped behaviour (the stale-snapshot defect of
146c's A1 was reproduced on Swift by the lead), and nothing catches the next one before a device does.

After this plan: the harness records, for a fixed set of stories (named minimal traces and seeds),
everything the **wrist** saw and did — every frame delivered to it in order, every wrist user action,
every kill — with a deterministic clock. A Swift test replays each recording into a real
`WatchSessionEngine` over an in-memory store and compares the wrist's final observable state with what
the Dart wrist ended with. Any difference is a Dart-vs-Swift divergence **found without a device**,
named by a class, and reproducible from a checked-in file a person can read.

Cost: one harness hook, one recorder helper, one corpus of ~15 small JSON files, one staleness test,
one Swift test file, one docs subsection. No `lib/` and no `Sources/` change. Runtime: a few seconds
on each side.

What it **cannot** catch (D-15211, so the owner does not over-trust it): thread races (the Swift
engine's unprotected mutable state — 146c evidence "B1"), the layers above the engine (inbound lane,
bridge queue, coordinator, UI), HealthKit and real relaunch behaviour, radio concurrency, clock skew.
It also never exercises the phone side of Swift (there is none — the phone is Dart and already
covered by the pair harness).

## Overview

Plan 145 built the pair harness (`test/helpers/watch_pair_harness.dart`: `PairRadio`,
`WatchPairHarness`, `HarnessRunner`, `ConvergenceRun`, `Shrinker`; tests
`test/watch_convergence_harness_test.dart`, `test/watch_convergence_random_test.dart`). It runs the
Dart wrist twin (`lib/watch/session/watch_session_engine.dart`). Plan 146 and 146c fixed the pair's
known divergences on **both** engines (146c evidence "Investigation 2026-11-13" reproduced A1 on
Swift by static read; the lead reproduced it live). Parity today rests on the shared reconciliation
fixtures (`watch/sync_protocol/fixtures/reconciliation/*`, walked by `WatchLiveMirroringTests` and
`SyncProtocolFixturesTests`) — 17 hand-written scenarios, not the randomized space.

This plan adds the missing leg: **record once (Dart), replay everywhere (Dart and Swift), compare**.
It is test-and-fixture only: `test/`, `watch/sync_protocol/fixtures/replay/`,
`watch/watchos/Tests/`, and one docs page. The wrist-kill case rides in PR 152a (the harness already
models it — `WristKilled` / S-14511); the phone-kill case is planned here and built later (PR 152c).

**PR series** (recommended split; the Swift replay stays in PR 152a because it is the plan's payoff —
landing only the recorder would ship infrastructure with no consumer; every hard budget limit is met,
and the soft signals are accepted and recorded here: 4 phases, plan about 550 lines, fixtures under
`watch/sync_protocol/` ride with their first consumer):

- **PR 152a (this plan):** the recorder, the corpus (including wrist-kill traces), the Dart
  round-trip and staleness guards, the Swift replay test, the asymmetry allowlist, docs.
- **PR 152b:** alignment of whatever divergences 152a finds, one class per PR, each with its own
  fixtures and a structural guard.
- **PR 152c:** the phone-kill model in the pair harness (modelled in D-15210, built then).
- **Later, owner decision only:** retiring the Dart wrist twin as a reference model (D-15212).

## Resolved Decisions (Ledger)

| ID | Decision | Backing |
|---|---|---|
| D-15201 | **Shape.** A recording is the wrist's input timeline: the ordered frames delivered to the wrist (deep-copied envelopes with their wire fields), the wrist's own user actions, and wrist kills — each stamped with the run's clock instant. The radio, the link state and all phone-side state are NOT recorded: the recorded delivery order and instants already encode what the faults produced. Replay applies the timeline to a fresh engine and compares final state | brief item 1; the harness's fault model D-14504/D-14512/D-14515 is upstream of delivery |
| D-15202 | **Recording points.** Frames: in `WatchPairHarness._receiveOnWrist`, before dispatch — that is the one place every phone→wrist delivery (live, drained, refused-then-queued) passes. Actions and kills: in `HarnessRunner.perform`, at the wrist-side cases. `TimeAdvances`, `LinkDrops`, `LinkRises`, `RefuseLiveFrame` and `PhoneReassertsLive` produce no event of their own; their effect arrives as recorded frames and clock stamps. Pure request frames and `routines_down`/`foods_down` are not recorded: they change no session state (`watch_sync_orchestrator.dart:129-160` routes the session types straight to `applyMessage`) | `test/helpers/watch_pair_harness.dart` `_receiveOnWrist` :835, `_deliver` :407; `lib/watch/start/watch_sync_orchestrator.dart:129-160` |
| D-15203 | **Format, versioned and closed.** `{"formatVersion": 1, "source": {"kind": "seed"\|"trace", "name": …}, "gridStartMs": …, "events": […], "expected": …}`. Events are closed objects: `frame` = `{t, clockMs, envelope}` (envelope verbatim wire JSON: `protocolVersion, messageId, sessionId, type, origin, sentAt, payload`); `action` = `{t, clockMs, name: start\|logSet\|finish\|discard\|restStart, modality?, exercises?, event?}` carrying exactly the arguments the harness passed the engine; `kill` = `{t, clockMs}`. One line per event (compact JSON). Dart `DateTime` round-trips as the epoch-ms integers `clockMs`/`startedAtMs` and the ISO strings already inside envelopes — Swift reads both with `Date(timeIntervalSince1970:)` and the existing `parseUtcIso`. A no-op action is not recorded (only events that happened) | envelope shape per `watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json`; `WristEngineArgs` counter factories (`watch_pair_harness.dart:642-671`) |
| D-15204 | **Determinism: the phone's real clock never reaches the corpus.** The phone mints ids and stamps from `DateTime.now()` (`lib/state/workout/session_core_io.dart:16`, `live_session_mirror_state.dart:86-94` UUIDs) while both halves' clocks are the injected `TestClock` — 146c A1/A2 showed seeds are not process-stable because of it. The recorder rewrites every unstable value through alias tables keyed by exact value, minted in first-appearance order: an **id** (a string containing a digit run ≥ 10, or a UUID) becomes `x-<n>`; an off-grid **timestamp** (epoch/ISO not on the TestClock grid) becomes `gridStartMs + 1_000_000_000 + n × 1000` ms — above the grid span, preserving the real run's "phone stamps are later than grid stamps" ordering; same value → same alias, so equality classes survive, and real-now reads are monotone within a run, so first appearance = time order. Guards: S-15202 (round-trip), S-15203 (no unstable value survives) | 146c evidence "Investigation 2026-11-13" A1/A2 (seed instability); `watch_pair_harness.dart` `labelFor` :897 for the same idea on session ids |
| D-15205 | **The wrist observable state** (the only thing compared), computed by ONE reading rule on both sides, from the append-only store, never from a projection: per session id — `status` (the newest session row's status, the rule `HarnessRunner._wristStatusOf` uses, `watch_pair_harness.dart:1180-1191`); `entries` (the set of observation `entryId`s stored for that session, minus the allowlisted session-end ids, sorted); `timers` (per kind, the newest timer row for that session → `{state, startedAtMs}` where state = stopped if `stoppedAt` set, else paused if `pausedAt` set, else running); plus `current` (the engine's held session id or null). `currentExerciseIndex` is deliberately NOT read (allowlist A-152b). `entryDuplicates` is a pair-harness concept about exposure order and is not part of the replay summary | `InMemoryWatchSessionStore.readAll()` (`watch_pair_harness.dart:1186, 1219`); Swift twin `store.readAll()` (`WatchSessionEngineTests.swift:104`, `SyncProtocolFixturesTests.swift:132`) |
| D-15206 | **Comparison rule.** (1) *Recorder fidelity*: replaying a recording into a fresh Dart wrist-only rig must reproduce the recorded `expected` block and the store's row multiset — a mismatch is a recorder defect, never an engine finding. (2) *Parity*: the Swift replay of the same recording must reproduce the same `expected`. A mismatch is bucketed into the manifest's classes `status / entries / timers / current`; a mismatch that fits no class fails the test (never silently normalized). Class names deliberately match the pair harness's checks (D-14507) so a Swift finding maps onto the same plan-146 vocabulary | D-14507's four checks; `_kindsOf` (`test/watch_convergence_random_test.dart:712-728`) |
| D-15207 | **Swift rig.** A fresh `WatchSessionEngine(store: InMemoryWatchSessionStore(), clock: TestClock, idFactory/sessionIdFactory: counters)` built exactly like `Harness.newEngine()` (`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift:46-66`), then `restore()`. Frames go to `applyMessage(_:)` (:512) — the session types the orchestrator routes there (`watch_sync_orchestrator.dart:152`), so no orchestrator is needed. Actions call the engine API (`createSession(modality:exercises:)` :335, `appendObservation` :1622, `finishSession` :413, `abandonSession` :422, `startTimer` :2096). A `kill` event = new engine over the same store + `restore()` — the same simulation of process death the Swift tests use | `WatchSessionEngineTests.swift:24-27` ("Process death is simulated…"); S-14511 for the Dart side |
| D-15208 | **Corpus.** Lives checked-in at `watch/sync_protocol/fixtures/replay/` (loaded by Swift via `Fixtures.json("fixtures/replay/<file>")`, `Fixtures.swift:113-121`, and by Dart via the `_protocolRoot` file reader, `test/sync_protocol_fixtures_test.dart:32-33`) with `manifest.json` listing every source, its class-coverage tags, the allowlist block and the comparison classes. Sources: the named traces — S-14503/F-1, F-2..F-7 (the scripted lists in `test/watch_convergence_random_test.dart:500-655` and `test/watch_convergence_harness_test.dart`), and the phase-4 minimal traces of seeds 111 (A1) and 857 (A2) if recoverable from plan 146's evidence, else the full seed recordings stand in (Assumption Log) — plus full seed recordings for **1** (green baseline), **7**, **50**, **111**, **857**, **1814** and one kill-bearing seed chosen at build time. Each file ≤ 32 KB, whole corpus ≤ 300 KB, both asserted in the corpus test; a source that overflows is replaced by a shorter seed, recorded in the manifest | brief item 3; the docs-contract pattern of a test that fails when data drifts; `Fixtures.json` path base `watch/sync_protocol/` |
| D-15209 | **Staleness and regeneration.** `test/watch_replay_corpus_test.dart` re-records every source through `ConvergenceRun.runSeed` / `replayActions` with the recorder on and compares bytes with the checked-in file, naming the stale file — the same "fail when data drifts" contract as the docs indexing test. Regeneration is the same test run with `--dart-define=REPLAY_CORPUS_WRITE=true` rewriting the corpus files (the `kSeedCount`/`kVerbose` `fromEnvironment` pattern, `test/watch_convergence_random_test.dart:29-37`; mirrors `--update-goldens`). The define is never set in CI; the default run only compares | docs contract precedent; standing rule "a check must not create files" holds for default runs |
| D-15210 | **The two kill cases.** Wrist kill: already modelled (`WristKilled` → `relaunchWrist`, a fresh engine over the same `InMemoryWatchSessionStore` + `restore()`, `watch_pair_harness.dart:828-833`); its recordings ride in PR 152a and the Swift replay reproduces the kill (D-15207). Phone kill: **planned here, built in PR 152c** — model: a `PhoneKilled` `PairAction` (actor phone) whose handler `WatchPairHarness.relaunchPhone()` rebuilds the phone half over the same `MockWorkoutRepository` (a new `WorkoutState` + `SettingsState` + `createWatchSync` wired to the same radio, clock and validator, re-binding adoption/autoPush/timerPush and re-registering the radio's phone inbound — the radio holds one phone handler, so the swap is part of the action's semantics), leaving the wrist and its store untouched; memory-only phone state (`_unconfirmedEnds`, `_fates` — `live_session_mirror_state.dart:130-135` "a phone restart empties it") is what the kill destroys, and the scenarios assert the stored-row path (plan 128 D-3) still converges an owed end. Home: `test/helpers/watch_pair_harness.dart` + guards in `test/watch_convergence_harness_test.dart`; excluded from `kShippingActions` until built | brief item 4; `WristKilled` :619-624; `WatchPairHarness.build` :738-799 |
| D-15211 | **Known asymmetries, decided per entry — never silently normalized.** A-152a: Swift stores a session-end **observation** (`captureSessionEnd`/`sessionEndEvent`, `WatchSessionEngine.swift:1946, 1968`, id `WatchSessionCapture.sessionEndId(sessionId)`) that the Dart twin does not; the summary excludes exactly those ids on both sides (D-15205); owner: the Swift row-logs owner (plan 150). A-152b: Swift's timer adoption can move the wrist to another exercise (`jumpTarget`, `WatchSessionEngine.swift:1077`, applied from `adoptTimer` :1024-1041); Dart `_adoptTimer` (`watch_session_engine.dart:927-977`) never moves — the summary does not read `currentExerciseIndex`, so this is out of the comparison by construction, documented in the manifest; owner: the D-2 timer owner; aligning the Dart twin is a PR 152b candidate. A-152c: Swift-only surfaces (water `logWaterGlass` :1686, `announceEnergy` :1812, effort rating :2038-2067) are unreachable from the corpus action set; owner: watch app owner. A-152d: Swift falls back to `newId()`/`clock()` on a missing/invalid id or stamp (:817-818) where Dart requires the field — unreachable because the corpus carries closed envelopes; owner: replay owner. **Verified aligned, contrary to the brief's example:** "Swift synthesizes timer stops at a lifecycle end, the Dart reconciler does not" was true before plan 146; since D-14603a both stop every timer at an end (Dart `watch_session_engine.dart:789-796` and :1403-1409; Swift `WatchSessionEngine.swift:866-874` and :1486) — the corpus's F-3 recording asserts it on both engines | brief item 5; 146c evidence Investigation B1 |
| D-15212 | **The Dart twin stays.** The recorder needs it (only it can run the pair and produce recordings), and it remains the reference model the convergence sweeps run against. Retiring it — replaying hand-edited recordings only — is a later owner decision, after the Swift replay has run long enough to be trusted | brief item 6 |
| D-15213 | **No production change.** Nothing under `lib/` or `watch/watchos/Sources/` changes in PR 152a: the recording hooks are additive harness code behind a default-off switch, existing tests are unchanged (recorder off), and the Swift side only gains a test file. Any defect this plan finds is reported, not fixed | plan-145 precedent (test-only plan); plan 146 owns the fixes |

## Feature Invariants

- The recording is the wrist's input timeline only. Phone-side state, the radio's queues and link
  state never appear in a corpus file (D-15201).
- Both summary readers compute the same fields from the append-only store by the same rule (D-15205);
  a projection-only reading is a defect, not a finding.
- No unstable phone value survives canonicalization into a corpus file (D-15204, S-15203).
- Every difference the comparison ignores is a manifest allowlist entry with an owner (D-15211). A
  mismatch outside the named classes fails the run (D-15206).
- `lib/` and `watch/watchos/Sources/` are untouched by this plan (D-15213).

## Requirements

R1. The harness can record a run to the D-15203 format; default off; no existing test changes.
R2. The corpus (D-15208) is checked in with its manifest, regenerated by one define-gated command
    (D-15209), and asserted fresh by a test that runs in the default suite.
R3. A Dart replay of any recording reproduces its `expected` (D-15206 rule 1).
R4. A Swift replay of the whole corpus compares against `expected`; every divergence is bucketed or
    fails (D-15206 rule 2, D-15207 rig).
R5. The wrist kill is recorded and replayed on both sides (D-15210).
R6. Docs name the corpus, the replay command and how to read a divergence (Phase 4).

## Acceptance Criteria

- AC-1 → S-15201, S-15202, S-15203 (recording faithful, deterministic, canonical).
- AC-2 → S-15204, S-15207 (corpus complete, fresh, sized).
- AC-3 → S-15205, S-15206, S-15208 (Swift replay parity, finding reproduction, whole-corpus sweep).
- AC-4 → S-15209 (the 146c investigations replay on Swift as findings).
- AC-5 → S-15210 (the allowlist is structural, proved by mutation).

## Existing-Functionality Impact

| Touched surface | What already reads it (the grep that found it) | Effect of this plan | Guarded by |
|---|---|---|---|
| `WatchPairHarness` / `HarnessRunner` (`test/helpers/watch_pair_harness.dart`) | `test/watch_convergence_harness_test.dart`, `test/watch_convergence_random_test.dart` (grep `WatchPairHarness` in `test/` → those two + the helper itself) | Additive: a default-off `recordReplay` switch, event capture in `_receiveOnWrist`/`perform`, no signature change; every existing run behaves identically with the recorder off | full suite green UNCHANGED; S-15201 |
| `PairRadio._deliver` (`watch_pair_harness.dart:407`) | only the harness (grep `_deliver` in `test/` → that file) | Untouched — the hook sits at `_receiveOnWrist`, one level above; the radio is not edited | S-15201 |
| `ConvergenceRun.runSeed` / `replayActions` (`watch_pair_harness.dart:1788, 1815`) | the random test's sweep and F-traces | Read as-is by the corpus builder; no seam added | S-15204 |
| `watch/sync_protocol/fixtures/` tree | `test/sync_protocol_fixtures_test.dart` (walks `fixtures/valid` + `fixtures/reconciliation` by fixed directory list, :60-66) and Swift `Fixtures.entries("valid"/"invalid")` (manifest-driven) | `fixtures/replay/` is a new sibling directory; neither walker enumerates the fixtures root, so nothing existing can see it | S-15204; `test/sync_protocol_fixtures_test.dart` green unchanged |
| `Fixtures.json` (`Fixtures.swift:113`) | `SyncProtocolFixturesTests`, `WatchLiveMirroringTests`, `WatchEndedIsFinalTests` (grep `Fixtures.json` in `watch/watchos/Tests/`) | Additive loads of `fixtures/replay/…`; no existing path changes | `gateway.sh swift-test` green unchanged |
| `docs/state_management/watch_surface_transport.md` | `docs/state_management.md` index; `test/docs_indexing_contract_test.dart` | One subsection (~18 lines) after "Convergence testing" (:144); the page is 198 lines, far under the 52 KB band; the implementer re-measures and records both sizes | `gateway.sh test test/docs_indexing_contract_test.dart` |
| Suite runtime | the convergence sweep (200 seeds, 18–33 s) | The corpus test re-records ~15 sources (≈ 2–5 s) and replays ~15 recordings; the Swift package gains ~15 short replays; both negligible against the 900 s budgets | Done Criteria counts |

## UI Standards Impact

None — no screens, no shared pieces, no new widgets.

## Scenarios

### S-15201: a run records to a stable, complete file
- Fixture: `WatchPairHarness` built with `recordReplay: true`; the F-2 action list
  (`wristStartsFreeWorkout, linkDrops, wristFinishes, phoneStartsRest, linkRises`) performed, then
  heal + `checkConvergence` (the recorder's normal close).
- Trigger: record the run twice in one process; also record the S-14503 list (with the synthetic
  re-assert) and a seed-1 run.
- Flow: serialize each recording; compare bytes across the two runs; walk the events.
- Expected: the two serializations are byte-identical; the event list contains every frame the wrist
  received (asserted against `radio.frames` filtered to phone→wrist session types, including the
  drained ones), the wrist actions in order, and an `expected` block with one session whose status
  and entries match the report.
- Edge case of: none (base recording scenario).

### S-15202: a recording replays into a fresh Dart wrist and reproduces the expected
- Fixture: every corpus recording (Phase 2), plus S-15201's F-2 recording alone at first.
- Trigger: `ReplayReplayer.replay(recording)` — a fresh engine + store + TestClock + counter
  factories, events applied in order.
- Flow: compute the D-15205 summary from the replayed store; compare with `expected`; compare the
  store's session/observation/timer row multisets (ids canonicalized the same way).
- Expected: identical summary and identical row multiset — for the whole corpus. A mismatch here is
  a recorder defect (D-15206 rule 1) and blocks Phase 3.
- Edge case of: S-15201.

### S-15203: no unstable value survives canonicalization
- Fixture: the F-2 recording, recorded with the canonicalizer ON; a mutation build with the
  canonicalizer bypassed (raw values pass through).
- Trigger: scan every string/number in the canonical recording for an unstable shape (a digit run
  ≥ 10 not on the grid, or a UUID); run the same scan on the mutated build's output.
- Expected: the canonical scan is clean; the mutated scan finds the phone-minted values (red),
  proving the scan can see them; the mutation is restored byte-identically.
- Edge case of: S-15201 (determinism).

### S-15204: the corpus is complete and matches its manifest
- Fixture: the checked-in `watch/sync_protocol/fixtures/replay/` with its `manifest.json`.
- Trigger: the corpus test lists the directory and reads the manifest.
- Flow: every manifest source has its file; every file is in the manifest; every source's
  class-coverage tags are true of its recording; the class-coverage floor holds — ≥ 1 recording with
  a `kill` event, ≥ 1 with a refused-then-queued frame, ≥ 1 multi-session recording, ≥ 1
  timer-bearing end (F-3), ≥ 1 entry-loss shape (F-6); every named trace (S-14503/F-1, F-2..F-7) is
  present; the size band holds (each file ≤ 32 KB, total ≤ 300 KB).
- Expected: all assertions pass; any gap names the missing source. Empty-fixture edge: the corpus
  contains at least one action-free prefix recording (a `seed-1` run whose early events are only
  frames) — the replay handles an event stream that starts with no session.
- Edge case of: none.

### S-15205: the no-fault story replays green on Swift
- Fixture: the recording of S-14501's story (phone starts, wrist logs two sets, phone logs one,
  phone finishes, heal — recorded as a named trace `trace-s14501`), whose `expected` says one
  `completed` session, three entries, no timers.
- Trigger: the Swift replay test applies it to a fresh `WatchSessionEngine`.
- Flow: D-15206 rule 2.
- Expected: the Swift summary equals `expected` exactly (status, entry set, timers, current). Red
  today only if the engines already diverge on the plain path — which would itself be a finding.
- Edge case of: none (Swift baseline).

### S-15206: F-2 reproduces its finding on Swift
- Fixture: the `trace-f2` recording, whose `expected` carries the Dart wrist's absorbing signature
  (`wrist` reports the `completed` session `active` again — the summary's status for that session is
  what the Dart engine actually held, not what the invariant wishes).
- Trigger: Swift replay of `trace-f2`.
- Flow: compare; bucket the mismatch.
- Expected: the Swift engine shows the same divergence the Dart twin shows (the stale-snapshot
  revival — 146c reproduced this shape on Swift), reported under the `status` class. If Swift does
  NOT reproduce it, that is a genuine Dart-vs-Swift difference and is reported as such — either way
  the test states the comparison result, not a wish.
- Edge case of: S-15205.

### S-15207: the corpus is fresh (staleness contract)
- Fixture: the checked-in corpus; a mutation that edits one byte of `trace-f2.json`.
- Trigger: run the corpus test; run it again after the mutation.
- Expected: green on the checked-in corpus; red after the mutation, naming the stale file and the
  regeneration command; the mutation is reverted. Structural guard for the whole corpus (D-15209).
- Edge case of: S-15204.

### S-15208: the whole corpus replays on Swift with named outcomes
- Fixture: the whole corpus (~15 recordings).
- Trigger: the Swift sweep test replays every recording.
- Flow: per recording, compare; bucket; print `name classes=…` lines like the Dart sweep.
- Expected: every recording's outcome is stated; every mismatch belongs to a manifest class; a
  class-less mismatch fails the test. The class counts are the PR's measurement output.
- Edge case of: S-15205, S-15206 (instances of the sweep).

### S-15209: the 146c investigations replay on Swift
- Fixture: the recordings of the A1 (seed 111, stale-snapshot) and A2 (seed 857, entry-loss) traces
  and the seed-1814 timers trace (A3).
- Trigger: Swift replay of each.
- Expected: A1 reproduces the absorbing signature on Swift (the lead's reproduction, now a
  checked-in file); A2 reproduces the entry-loss signature (or states that Swift holds the entry —
  itself a finding); A3's timer signature is stated. Recorded in the evidence file as findings; no
  fix in this plan.
- Edge case of: S-15208.

### S-15210: the allowlist is structural, not a silent normalization
- Fixture: a corpus recording whose Swift store holds a session-end observation (any `completed`
  session — A-152a fires on most endings); a mutation that drops the session-end filter from the
  Swift summary reader.
- Trigger: the Swift replay with and without the filter.
- Expected: with the filter, `entries` matches the Dart `expected`; without it, the entry sets
  differ and the test goes red naming A-152a — proving the comparison would surface the difference
  if the allowlist were wrong. The mutation is restored.
- Edge case of: D-15211.

### S-15211: the phone is killed mid-workout (PLANNED, PR 152c — not built here)
- Fixture: one session active on both sides, the wrist logged a set, the link down.
- Trigger: `PhoneKilled` → `WatchPairHarness.relaunchPhone()` (the phone half rebuilt over the same
  `MockWorkoutRepository`, the radio's phone inbound re-registered); then heal.
- Expected: the wrist's end still reaches the rebuilt phone through the stored-row path (plan 128
  D-3 — the memory-only `_unconfirmedEnds`/`_fates` are gone, the row is not), and the four checks
  pass or name a real class. Companion: phone killed while it owed a wrist confirmation.
- Edge case of: S-14511 (the wrist kill, its mirror).

## Iteration 1

### Phase 1: the recorder (@developer)

1. [x] `WatchPairHarness` gains the recording switch and event store: `bool recordReplay` (default
       false) + `final List<Map<String, Object?>> replayEvents` + `int gridStartMs` captured from the
       TestClock at build; every recorded event is appended with `clockMs = clock.now.millisecondsSinceEpoch` —
       `test/helpers/watch_pair_harness.dart` · `WatchPairHarness.recordReplay`, `.replayEvents`, `._`
2. [x] Frame capture at the wrist's inbound: when `recordReplay`, `_receiveOnWrist` appends a
       `frame` event (deep-copied envelope verbatim + `clockMs`) before dispatch, for exactly the
       session-surface types D-15202 lists; requests and `routines_down`/`foods_down` are skipped —
       `test/helpers/watch_pair_harness.dart` · `WatchPairHarness._receiveOnWrist`
3. [x] Action and kill capture in the runner: the wrist cases of `perform` append `action` events
       (`start` with `modality` + `exercises`; `logSet` with the exact observation map; `finish`;
       `discard`; `restStart` with the kind) and `WristKilled` appends `kill` — recorded only when the
       action actually ran (no-ops are not events, D-15203) —
       `test/helpers/watch_pair_harness.dart` · `HarnessRunner.perform`
4. [x] The recorder module with the canonicalizer: the alias tables of D-15204 (id shapes: digit run
       ≥ 10 or UUID; off-grid timestamps → `gridStartMs + 1_000_000_000 + n × 1000`), applied to
       every string/number inside recorded envelopes and action arguments, keyed by exact value —
       `test/helpers/watch_replay_recorder.dart` · `ReplayCanonicalizer` (new file)
5. [x] The summary reader, one rule both sides mirror (D-15205): `WristSummary.fromStore(store,
       heldSessionId)` — statuses from the newest session row per id, entry sets from stored
       observations minus A-152a's session-end ids, timers as newest-row-per-kind → `{state,
       startedAtMs}`, `current` — `test/helpers/watch_replay_recorder.dart` · `WristSummary`
6. [x] The writer and the loader: `ReplayRecording.toJson` (D-15203 closed schema, compact one-line
       events, `source`/`gridStartMs`/`expected` filled at close) and `ReplayRecording.fromJson` —
       `test/helpers/watch_replay_recorder.dart` · `ReplayRecording`
7. [x] The Dart replayer: `ReplayReplayer.replay(recording)` — a wrist-only rig (`WatchSessionEngine`
       over a fresh `InMemoryWatchSessionStore` with a `TestClock` set per event and the
       `WristEngineArgs` counter factories, `watch_pair_harness.dart:642-671`): frame →
       `applyMessage` (guarding exactly `perform`'s no-op guards), action → the engine API, kill →
       new engine over the same store + `restore()`; returns the `WristSummary` of the end state —
       `test/helpers/watch_replay_recorder.dart` · `ReplayReplayer`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` (existing behaviour unchanged with the recorder off — counts pasted into the evidence file); a scratch probe or a new S-15201 test red→green for F-2 (recorder on: two recordings byte-identical; `ReplayReplayer` reproduces `expected`); `.github/copilot/scripts/macos/gateway.sh lint` (compare with the 181-issue baseline); `gateway.sh git-diff --stat` shows no `lib/` or `watch/watchos/Sources/` file.
**Predicted Files**: `test/helpers/watch_pair_harness.dart` (recording switch + capture); `test/helpers/watch_replay_recorder.dart` (new); `docs/plans/2026-11-13-152-swift-replay-plan/2026-11-13-152-swift-replay-plan.evidence.md`.
**Phase 1 verification notes (Conductor, date):** *(added at verification)*

### Phase 2: the corpus and its guards (@developer)

1. [x] The corpus source list: `kCorpusSources` — the named traces `trace-s14501`, `trace-s14503`
       (=F-1, includes the synthetic re-assert), `trace-f2`..`trace-f7` (the scripted lists of
       `test/watch_convergence_random_test.dart:500-655`), `trace-a1`/`trace-a2` (the phase-4 lists
       in plan 146's evidence; if unrecoverable, the seed recordings stand in — Assumption Log), and
       the seed recordings `seed-1`, `seed-7`, `seed-50`, `seed-111`, `seed-857`, `seed-1814` plus
       one kill-bearing seed chosen by running the sweep (recorded in the manifest) — built via
       `ConvergenceRun.runSeed` / `replayActions` with the recorder on —
       `test/watch_replay_corpus_test.dart` · `kCorpusSources` (new file)
2. [x] S-15201 as a test: record `trace-f2` and `trace-s14503` twice, assert byte-identical
       serializations — `test/watch_replay_corpus_test.dart` · `test('S-15201 …')`
3. [x] S-15202 as a test: for every corpus source, replay the canonical recording through
       `ReplayReplayer` and assert summary + store-row multiset equal `expected` —
       `test/watch_replay_corpus_test.dart` · `test('S-15202 …')`
4. [x] S-15203 as a test: the unstable-value scan over the canonical output is clean, proved
       red by bypassing the canonicalizer (mutation, restored byte-identically) —
       `test/watch_replay_corpus_test.dart` · `test('S-15203 …')`
5. [x] S-15204 as a test: manifest ↔ directory ↔ class-coverage ↔ size band (D-15208's floors,
       including the kill and refused-frame floors and the empty-prefix edge) —
       `test/watch_replay_corpus_test.dart` · `test('S-15204 …')`
6. [x] The manifest: `watch/sync_protocol/fixtures/replay/manifest.json` — `formatVersion`, every
       source with its file, kind, seed/trace name and coverage tags; the `allowlist` block (A-152a
       with its id rule and owner; A-152b documented as out-of-comparison; A-152c, A-152d one line
       each); the comparison `classes` list (`status, entries, timers, current`) — written by the
       regeneration mode, validated byte-for-byte by the default run —
       `watch/sync_protocol/fixtures/replay/manifest.json` (new)
7. [x] S-15207 as a test: re-record every source and compare bytes with the checked-in files,
       naming the stale file and printing the regeneration command
       (`--dart-define=REPLAY_CORPUS_WRITE=true`); the same test, when that define is set, rewrites
       the corpus files instead (D-15209) — `test/watch_replay_corpus_test.dart` · `test('S-15207 …')`
8. [x] Regenerate the corpus and land it: every source recorded through the real pipeline, the
       manifest filled, the files reviewed in the PR (each ≤ 32 KB, total ≤ 300 KB) —
       `watch/sync_protocol/fixtures/replay/*.json` (~15 new files)

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/watch_replay_corpus_test.dart` (default run: compare-only, green; wall time recorded); one `prove-red` or mutation per structural guard (S-15203 bypass, S-15207 byte edit) shown red and restored, pasted in the evidence file; S-15202's table (source → replay verdict) in the evidence file; `gateway.sh lint` count vs baseline.
**Predicted Files**: `test/watch_replay_corpus_test.dart` (new); `watch/sync_protocol/fixtures/replay/manifest.json` + the ~15 recording JSON files (new); the evidence file.
**Phase 2 verification notes (Conductor, date):** *(added at verification)*

### Phase 3: the Swift replay (@developer — watch track)

1. [ ] `watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift`: load the corpus via
       `Fixtures.json("fixtures/replay/…")` + `Fixtures.json("fixtures/replay/manifest.json")`
       (`Fixtures.swift:113`), decode events into typed values —
       `WatchReplayTests.loadCorpus` (new file)
2. [ ] The applier (D-15207 rig): a `TestClock` set per event, counter id/session factories
       (`Harness.newEngine()` pattern, `WatchSessionEngineTests.swift:46-66`); `frame` →
       `try await engine.applyMessage(envelope)`; `action` → `createSession(modality:exercises:)` /
       `appendObservation` / `finishSession` / `abandonSession` / `startTimer`; `kill` → new engine
       over the same store + `restore()` — `WatchReplayTests.apply(_:to:)`
3. [ ] The Swift summary reader: the same store-based rule as `WristSummary` (D-15205) from
       `store.readAll()` + the held session, with A-152a's session-end ids excluded —
       `WatchReplayTests.summary(engine:store:)`
4. [ ] The comparator and bucketing: Swift summary vs `expected` per session, bucketed into the
       manifest's `classes`; a class-less mismatch `XCTFail`s with the recording name and the diff —
       `WatchReplayTests.compare(_:expected:recording:)`
5. [ ] S-15205 as a test: `trace-s14501` replays green (identical summary) —
       `testS15205TheNoFaultStoryReplaysGreen`
6. [ ] S-15206 as a test: `trace-f2` replays and the outcome is stated and bucketed (the absorbing
       signature reproduced on Swift, or a genuine Dart-vs-Swift difference reported) —
       `testS15206F2ReproducesItsFinding`
7. [ ] S-15210 as a test: the session-end filter is structural — mutation (drop the filter) goes red
       naming A-152a, then restored — `testS15210TheAllowlistIsStructural`
8. [ ] S-15208 as the sweep: every corpus recording replays; per-recording `name classes=…` lines;
       a class-less mismatch fails — `testS15208EveryRecordingReplaysWithNamedOutcome`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchReplayTests`, then the whole package `.github/copilot/scripts/macos/gateway.sh swift-test` (existing 1388 tests green unchanged — counts pasted); the S-15210 mutation shown red and restored in the evidence file; the sweep's class-count lines pasted.
**Predicted Files**: `watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift` (new); the evidence file. Nothing under `watch/watchos/Sources/`.
**Phase 3 verification notes (Conductor, date):** *(added at verification)*

### Phase 4: run, findings, docs (@developer + lead)

1. [ ] Full Dart suite `.github/copilot/scripts/macos/gateway.sh test` (expect the plan-146 close
       baseline `+7441 ~2` plus the new tests; any red is triaged, never weakened) and
       `.github/copilot/scripts/macos/gateway.sh lint` (baseline 181 issues) — counts pasted into
       the evidence file
2. [ ] S-15209: replay the A1/A2/A3 recordings on Swift, state each outcome, and write the findings
       (with the recording names and the diff lines) into the evidence file — no fix in this plan —
       `docs/plans/2026-11-13-152-swift-replay-plan/2026-11-13-152-swift-replay-plan.evidence.md` · findings section
3. [ ] Any NEW divergence class the corpus surfaced (beyond the manifest's list) is written to the
       evidence file with its recording and added to the manifest's classes with the PR-152b pointer —
       `watch/sync_protocol/fixtures/replay/manifest.json` · classes
4. [ ] Docs: a "Differential Swift replay" subsection in
       `docs/state_management/watch_surface_transport.md` directly after "Convergence testing"
       (:144) — what the corpus is, the regeneration define, how to run the Swift replay, how to
       read a class line, and the cannot-catch list of D-15211 (~18 lines; page 198 lines → the
       implementer re-measures before and after and records both sizes) —
       `docs/state_management/watch_surface_transport.md` · "Differential Swift replay"
5. [ ] Residue sweep: grep the touched test files and docs for any reader of a representation this
       plan replaced (there is none — the plan adds, it does not replace) and verify the footprint:
       `gateway.sh git-diff --stat` equals the union of all phases' Predicted Files; anything
       out-of-bounds is a finding — evidence file · footprint section

**Done Criteria** (run until green): full `gateway.sh test` and `gateway.sh swift-test` counts pasted; `gateway.sh lint` = 181 issues or the delta explained file-by-file; the docs page under the 64 KiB cap (`gateway.sh test test/docs_indexing_contract_test.dart`); footprint == Predicted Files.
**Predicted Files**: the evidence file; `docs/state_management/watch_surface_transport.md`; `watch/sync_protocol/fixtures/replay/manifest.json` (classes, only if item 3 fired).
**Phase 4 verification notes (Conductor, date):** *(added at verification)*

## Files Affected (whole feature)

| File | Change | Reader impact |
|---|---|---|
| `test/helpers/watch_pair_harness.dart` | +recording switch, capture points (Phase 1) | read by both convergence tests — additive, default off |
| `test/helpers/watch_replay_recorder.dart` | new — canonicalizer, summary, writer, replayer | none yet (Phase 2 consumes) |
| `test/watch_replay_corpus_test.dart` | new — S-15201..S-15204, S-15207 | suite |
| `watch/sync_protocol/fixtures/replay/*` (~15 + manifest) | new — the corpus | Dart corpus test; Swift `WatchReplayTests` |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift` | new — S-15205, S-15206, S-15208, S-15210 | swift-test |
| `docs/state_management/watch_surface_transport.md` | +~18 lines | index page; docs contract test |
| evidence file | created in Phase 1 | reviewer |

PR 152c (planned, D-15210): `test/helpers/watch_pair_harness.dart` (`PhoneKilled`, `relaunchPhone`),
`test/watch_convergence_harness_test.dart` (S-15211 guards), corpus additions.

## Notes

- **Phase dependency graph:** 1 → 2 → 3 → 4. Phase 3 could start after Phase 1's item 6 (the
  format) if the corpus shape is agreed, at the cost of replaying hand-made recordings before the
  real ones exist — not recommended. Phase 4 needs 3.
- **Intermediate states:** after Phase 1 the recorder exists but nothing consumes it; after Phase 2
  the corpus is checked in and self-verifying on Dart alone; after Phase 3 the differential replay is
  live. The Swift test must not land before the corpus it reads (it would fail on a missing
  directory).
- **Residual determinism risk:** the alias epoch (`gridStartMs + 1e9 + …`) preserves the real run's
  two-class timestamp ordering but not the exact gaps. If a replay outcome flips against the raw
  recording, S-15202 catches it; the fallback is recording the raw recording alongside the canonical
  one for the affected source only. Assumption Log entry required if the fallback is used.
- **Regeneration writes from a test** (D-15209) only under the define; the default run compares and
  never writes. If the owner prefers, the writer can move to a `tool/` script later without changing
  the contract.
- **What the Swift replay does not drive:** the wrist's own emissions are not compared (a later
  extension could diff emission streams too — cheap to add, not needed to find state divergences);
  `replaySessionEnd`/`sync`-side effects are captured only through the frames they cause.
- **Dart twin's future:** kept (D-15212). Retirement is an owner decision, not this plan's.
- **Test-suite hygiene:** plain `test()` only (FakeAsync hangs); the corpus test's runtime is
  bounded by the sweep's measured cost (200 seeds ≈ 18–33 s → ~15 sources ≈ 2–5 s).

## Progress

- [x] Phase 1 — the recorder (@developer) — complete: recorder + canonicalizer + replayer in
      `test/helpers/watch_replay_recorder.dart`, hooks in the harness default off; see evidence.
- [x] Phase 2 — the corpus and its guards (@developer) — complete: 16 sources checked in; S-15201…
      S-15204, S-15207 green; one orphan file needs a governor delete (see Feedback).
- [ ] Phase 3 — the Swift replay (@developer)
- [ ] Phase 4 — run, findings, docs (@developer + lead)

## Assumption Log

*(executors append: decision made, options considered, choice + why. Conductor marks RATIFIED or
REVERT.)*

- A-152-01 (planner, 2026-11-13): the brief's example asymmetry ("Swift synthesizes timer stops at a
  lifecycle end, the Dart reconciler does not") reads as already aligned by 146's D-14603a on both
  engines (file:line in D-15211). Treated as stale; the F-3 recording asserts it. Owner to confirm.
- A-152-02 (planner, 2026-11-13): the phase-4 minimal traces of seeds 111/857 (A1/A2) are assumed
  recoverable from plan 146's evidence file. If not, the full seed recordings stand in and the
  corpus manifest records the substitution.
- A-152-03 (planner, 2026-11-13): the kill-bearing seed is chosen at Phase 2 build time by one sweep
  run; the corpus test's coverage floor (S-15204) is what binds the choice, not a named seed.
- A-152-04 (executor, 2026-11-13, phases 1–2): off-grid stamps are aliased by ranking the distinct
  instants in **value** order, not by D-15204's first-appearance `n × 1000`. A frame that waited in
  the queue is delivered after a later-sent frame, so appearance order inverts exactly the comparisons
  the engine makes (`at` vs `recordedAt`, `sentAt` vs newest snapshot): with appearance ranking
  `trace-a2` replayed an `abandoned` session as `active`. Occurrence-counter aliases re-aliased ids
  mid-canonicalisation and diverged on `trace-a2`/`seed-857`. Value order keeps order *and* equality,
  which is what the engine compares.
- A-152-05 (executor, 2026-11-13, phases 1–2): S-15201 and S-15207 compare with alias-band instants
  masked (`_maskInstants`). The phone mints its stamps from the real clock, so how many distinct
  instants a run mints varies per process (two reads in one millisecond collapse). The mask leaves
  every promise the corpus makes — ids, clock grid, event order, expected summary — under test.
- A-152-06 (executor, 2026-11-13, phase 2): `seed-1814` is **not** in the corpus. Its random run
  re-pushes a snapshot whose acceptance depends on the phone's real-clock spacing, so it is not
  reproducible: the checked-in file had 541 serialised lines against 701 fresh, with a session's
  `entries` empty on one side and populated on the other. Options were: ship it and let S-15207 flake,
  re-script the story under a new name, or drop it — dropped, because the `kill` floor is still met by
  `seed-1`, `seed-408` and `seed-857`. The corpus file it had written is listed in `## Feedback` for
  deletion.
- A-152-07 (executor, 2026-11-13, phase 2): `refused-queued` cannot be read off a file, so S-15207's
  re-recording is the only check it survives; S-15204's floor asserts the *declared* coverage only.

## Feedback

Phases 1–2 are complete except one governor action: delete
`watch/sync_protocol/fixtures/replay/seed-1814.json` — the recording A-152-06 retires. Until it is
gone, S-15204's "every file is in the manifest" assertion reports it as an extra file; every other
assertion in the file is green.
