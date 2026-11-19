# Feature: 161 — the convergence harness stops reporting its own artifacts

> Status: Iteration 1 active
> Next handoff: **@developer (Phase 1)** — after Phase 1, Phase 2 may run in parallel; Phase 3 needs Phase 1; Phase 4 needs Phases 1–3; Phase 5 last.
> Binding conventions: `docs/global_conventions.md`
> Binding decisions from other plans, never relitigated here:
> - Owner rules **O-1..O-9** of plan 146 (`docs/plans/2026-11-11-146-ended-is-final-plan/2026-11-11-146-ended-is-final-plan.md:15-23`).
> - **D-15403 / D-15405** (`docs/plans/2026-11-13-154-series-review-fixes-plan/2026-11-13-154-series-review-fixes-plan.md:17,58`): the 2 s end-skew tolerance between ends of different status; within it the D-14601 tie-break decides (completed wins), only an end earlier by MORE than the tolerance is the earlier end.
> - Plan 158's findings (`docs/plans/2026-11-14-158-sweep-residue-investigation/2026-11-14-158-sweep-residue-investigation.findings.md` §1–§6) — the evidence base; every class below is a harness artifact per that document.
> - Plan 146c (`docs/plans/2026-11-12-146c-earlier-discard-wins-plan/2026-11-12-146c-earlier-discard-wins-plan.md`) and plan 153's finding 5 (`docs/plans/2026-11-13-153-series-review/2026-11-13-153-series-review.review.md:10`).

## Overview

The 2000-seed sweep's divergence classes are, per plan 158's investigation, artifacts of the harness
itself, not shipping defects:

- **`entries` (8 of 8 seeds, stable):** `HarnessRunner._sampleEntries`
  (`test/helpers/watch_pair_harness.dart:1290-1307`) unions **every** inbox `entryId` into the
  phone's entry set — including the phone's own deletion annotations
  (`WatchInboxEntry.phoneChangeId(changeId, index)` → `phone-change-…`,
  `lib/data/models/models.dart:2859-2860`, minted per vanished set by
  `lib/state/watch/watch_session_auto_push.dart`, D-110). Check 3 then demands the wrist hold them,
  which is unsatisfiable whenever the phone announces a deletion for a wrist session — ordinary
  product behaviour.
- **`status` (149 kind-hits / 112 diverging seeds) and `absorbing` (3, unreproducible):** the
  phone's lifecycle frames are stamped from the **real wall clock**
  (`LiveSessionMirrorState._clock = clock ?? _utcNow`, `lib/state/watch/live_session_mirror_state.dart:84,92`;
  `lib/state/watch/watch_sync_wiring.dart:290-296` passes only `ledgerClock: clock`) while the
  wrist's frames use the harness `TestClock` — a ~4½-day gap. D-15403 is then applied to numbers
  the harness, not the app, produced. The `absorbing` class inherits the same clock asymmetry and
  is expected to fall away with the fix; it gets no separate change.

This plan: (1) keeps phone-side annotations out of check 3's phone-entry set, (2) gives the mirror's
frame clock a seam and pins the harness to the pair's `TestClock`, (3) re-measures both sweeps and
tunes the ratchet **down** only, (4) implements the owner-question tie as a test-side check change
flagged **owner to confirm**, and (5) lists the `heal` residue for a later plan. Product code
changes **only** in the one clock seam (an optional parameter defaulting to today's behaviour).

Out of scope, explicitly: the `heal` class (42 seeds), any product change beyond the one seam, and
chasing any new class the coherent clock surfaces (listed under Residue instead).

## Resolved Decisions (Ledger)

- **D-16101 (check 3's phone-entry set excludes the phone's own annotations).** In
  `HarnessRunner._sampleEntries`'s inbox loop, a row whose `kind` is one of
  `WatchInboxEntry.phoneKinds` (`kindPhoneRating`, `kindPhoneCorrection`, `kindPhoneDeletion`,
  `lib/data/models/models.dart:2843-2850`) never joins `phoneEntryIds`. The rule keys on the row's
  **kind**, not the id prefix: the id prefix is `WatchInboxEntry`'s private detail
  (`_phoneChangeIdPrefix`, models.dart:2851) and D-132 already binds phone change ids to it
  (models.dart:2945-2951). Wrist-kind rows (`watchKinds`) are untouched — the filter is a
  subtraction from today's union, not a new allowlist, so no id that passes today's check is newly
  excluded. These rows are records the phone minted *about* a wrist session; they are not wrist
  entries and can never be held by the wrist.
- **D-16102 (the frame-clock seam; the smallest one).** `createWatchSync` gains an optional named
  parameter `DateTime Function()? frameClock` **defaulting to null**, passed to
  `LiveSessionMirrorState(clock: frameClock)` beside the unchanged `ledgerClock: clock`
  (`lib/state/watch/watch_sync_wiring.dart:290-296`). Production behaviour is provably unchanged:
  the only production caller, `lib/main.dart:387`, passes no clock at all, so `frameClock` is null
  and the mirror's `_clock` stays `clock ?? _utcNow` → `_utcNow`
  (`lib/state/watch/live_session_mirror_state.dart:84`). **Why not simply pass the existing `clock`
  through:** existing test callers pin a *standing-still* graph clock for the ledger —
  `test/watch_transport_test.dart:479` passes `clock: () => phoneNow`, a fixed instant — and tying
  the mirror's frame stamps to it is exactly what the wiring comment
  (watch_sync_wiring.dart:293-295) refuses: a graph clock that stands still would defeat plan 127's
  snapshot order. A separate optional parameter keeps those callers untouched. The harness passes
  `frameClock: clock.call` in `WatchPairHarness.build`
  (`test/helpers/watch_pair_harness.dart:789-798`), completing the pair: every frame both halves
  stamp now comes from the one `TestClock`.
- **D-16103 (why the harness's TestClock does not defeat plan 127's snapshot order).** The wiring
  comment's guard is about a graph clock that *stands still*. The harness's `TestClock` does not
  stand still: the sweep's action space contains `TimeAdvances` (weight 6, 1–90 s a step,
  `test/helpers/watch_pair_harness.dart` `_options`), the heal advances it 31 s before every round
  (`watch_pair_harness.dart:1425`), and every instant the clock holds is recorded on
  `clockGrid` via `noteClockGrid()` (D-15204) — so a timestamp off the grid is a *known* alias of
  the real clock. After D-16102 there are no mirror-stamped off-grid instants left: both halves
  stamp from one monotone clock whose every consumed instant is on the grid. What the harness does
  today to avoid collisions is exactly that grid (the D-15204 comment at
  `watch_pair_harness.dart:727-729`). Two consequences, both improvements: ordering between frames
  becomes a property of the trace (the `TimeAdvances` the trace performs), not of the run date; and
  a trace with no advance stamps equal instants, where plan 127 D-8's *strictly older* refusal
  declines to fire — the same outcome two real devices sharing one advancing wall clock produce.
  `_ledgerClock` keeps its own parameter, so plan 128's `since`/repeat-window/24 h bounds are
  untouched by the seam.
- **D-16104 (the pair's end instants, as the check reads them).** The harness records, per session
  id: the phone's discard instant (`phoneDiscardAtMs[sessionId] = clock.now.msSinceEpoch`, recorded
  in `_phoneDiscards` — after D-16102 the same instant the mirror stamps the abandonment); the
  phone's held-row end (`row.endedAtMs`); and the wrist's end (the stored row's `endedAtMs`). These
  are the two stamps D-15403 compares; the harness now holds both from one clock.
- **D-16105 (a discard and a finish within the tolerance — OWNER TO CONFIRM; test-side only).**
  **Needs the owner.** When a phone discard and a wrist finish really are less than 2 s apart,
  D-15403 keeps the finish (within the tolerance they are the same instant; the tie-break —
  completed wins — decides) while the phone holds nothing: the phone's own discard already deleted
  its row (`lib/state/workout/session_core_lifecycle.dart:117`) and nothing resurrects it
  (D-14632; `lib/core/services/watch_session_importer.dart:133-137` — an import with no effort rows
  is consumed without history, and the tie traces carry none). The pair therefore disagrees **by
  design**: check 1 today reports `phone abandoned vs wrist completed` forever
  (`HarnessRunner.checkConvergence`, the `shared && phoneStatus != wristStatus` branch), because
  `_phoneStatusOf` reads a discarded session as `abandoned` (via `phoneDiscardedSessions`,
  `watch_pair_harness.dart:1246-1260`). Proposed default: **count the pair as converged when both
  ends lie within the tolerance** — implemented ONLY as a check change, behind the named predicate
  `endsWithinSkewToleranceMs(int aMs, int bMs) => (aMs - bMs).abs() <= kEndSkewToleranceMs` (the ms
  twin of `areEndsWithinSkew`, `lib/core/sync_protocol/end_skew.dart`; symmetric, so both tie
  directions are covered), recorded in a new `withinSkewEndTies` report list that is **visible but
  never a failure** — the measurement stays observable, nothing is silently dropped. Same-status
  ends are untouched (D-15405: a status mismatch between two terminal statuses is
  different-status by construction, so the tolerance applies exactly where D-15403 says it does).
  Marked owner to confirm in the plan, in the tests' reason text, and in the docs delta.
- **D-16106 (the ratchet goes down only).** After Phases 1–3 the sweeps are re-measured; the
  per-200 constant in `shippingRatchet`
  (`test/watch_convergence_random_test.dart:216-226`, currently 14 → 140 at 2000) is lowered to
  what the measured run supports with headroom (measured + 2 seeds), never above 14, never raised.
  `knownClasses` texts are rewritten for the artifact classes as fixed by this plan; any NEW class
  the coherent clock surfaces is added to `knownClasses` as unclassified-with-owner and listed
  under **Residue** with its seeds and shrunk traces — not chased here.

## Feature Invariants

- Check 3's phone-entry set holds only ids in the wrist's entry-id space; the phone's own
  annotations never enter it, and a wrist entry the phone truly holds is still demanded of the
  wrist (the check keeps its teeth).
- In the harness, both halves stamp frames from the one `TestClock`; in production, the mirror's
  frame clock is exactly what it is today (`_utcNow`) — `lib/main.dart` passes no frame clock.
- `_ledgerClock` keeps its own seam; plan 128's bounds and plan 127's snapshot order are not
  re-plumbed by this plan.
- The product rule D-15403/D-15405 is untouched: the tie change is a test-side check change, and
  the seam's parameter defaults to today's behaviour.
- The ratchet never rises; a class the plan does not name cannot arrive silently (the existing
  S-14509 `unknown` guard stays).

## Requirements

- **R-1**: the entries filter (D-16101) with a red→green test, a mutation proof, and a teeth test.
- **R-2**: the frame-clock seam (D-16102, D-16103) with the harness pinned, and the watch/harness
  suites green against the coherent clock.
- **R-3**: the within-tolerance tie predicate (D-16105), test-side, named, flagged owner to
  confirm, with a test for the tie shape and one for the mirrored delete shape.
- **R-4**: re-measured 200- and 2000-seed sweeps; before/after class counts in the evidence file;
  ratchet tuned down only; residue listed, not chased.
- **R-5**: docs delta per the table below.

## Acceptance Criteria (each maps to ≥ 1 scenario)

1. The shrunk 4-action entries trace converges; removing the filter turns it red; a wrist that
   truly lacks a phone-held entry still fails check 3 → S-16101, S-16106, S-16102.
2. The shrunk 4-action status trace converges under the owner rule, and the mirrored trace with
   the discard stamped earlier by more than 2 s deletes on both sides → S-16103, S-16104.
3. The sweeps are re-measured with before/after class counts in the evidence file; the ratchet
   reflects the measured run, never above 14 per 200 → S-16105.
4. The owner question on the within-tolerance tie is stated with today's behaviour, the proposed
   default, and the flag → D-16105, S-16103.
5. The `heal` residue and any new classes are listed with first steps under Residue → Phase 4 item 6.

## Existing-Functionality Impact

- `createWatchSync` — callers found by grep: `lib/main.dart:387` (production, passes no clock) and
  18 test files (e.g. `test/watch_transport_test.dart:474-480`, which passes the fixed
  `clock: () => phoneNow`). Effect: a new optional `frameClock` none of them pass → production and
  all non-harness tests byte-identical in behaviour; only the harness's built graph changes →
  guarded by D-16102/D-16103, proved by S-16103/S-16104 and the full suite in Phase 1.
- `LiveSessionMirrorState._clock` — readers: frame stamps (`sentAt` :389, :946; lifecycle `at`
  :683, :716; rating `loggedAt` :433). Effect: stamp source becomes injectable, default unchanged →
  guarded by D-16102; the ledger's readers (`since`, windows) keep `_ledgerClock` → D-16103.
- `HarnessRunner._sampleEntries` — readers: `_sample` (:1213) after every action and
  `checkConvergence` (:1526); the phone set it builds feeds check 3 (:1566-1584) and nothing else
  (grep: `phoneEntryIds` appears only in `_sampleEntries`, `checkConvergence`, and
  `_observableState`). Effect: phone-side annotation kinds drop out of the union → guarded by
  D-16101, S-16101/S-16102/S-16106.
- `checkConvergence`'s status block — readers: `ConvergenceReport.converged`, `failures`,
  `toString`; `_kindsOf` (`test/watch_convergence_random_test.dart:682-695`) classifies from
  `statusMismatches`. Effect: some mismatches move to `withinSkewEndTies`, which is NOT in
  `failures` and NOT classified → no new sweep class; the tie stays visible in the report →
  guarded by D-16105, S-16103.
- `test/diagnostics_wiring_source_test.dart` (:23-47) source-scans `createWatchSync` and the
  wiring file for the diagnostics parameter — a canary for the Phase 1 edit; run it in Phase 1's
  Done Criteria.
- `absorbing` (3 seeds, unreproducible per findings §2) — no separate change; expected to fall
  away with the coherent clock; the sweeps re-measure it (S-16105).
- `timers` (0 this run; seed 1814 converges on replay) — nothing to do; the `knownClasses` text
  stays.

## UI Standards Impact

None — no UI change. The docs delta touches `docs/state_management/watch_surface_transport.md`
(its existing "### Convergence testing" section) only.

## Scenarios

### S-16101: the shrunk entries trace converges once phone annotations leave check 3
- Fixture: a fresh `WatchPairHarness` (seeded exercises only); actions replayed via
  `ConvergenceRun.replayActions`: `[WristStartsFreeWorkout, RefuseLiveFrame(from: PairActor.wrist,
  type: 'observations_up'), WristLogsSet, WristLogsSet]` — the findings' SHRUNK 1583 shape
  (§3): the phone stages two wrist sets and mints two `phone-change-del-…` deletion annotations.
- Trigger: run the trace, then the heal and `checkConvergence` (as `replayActions` does).
- Flow: the wrist holds `{w-entry-1, w-entry-2}`; the phone's set must be exactly the same two.
- Expected outcome: `report.converged` is true; the session's `phoneEntryIds` contains no id
  starting `phone-change-`. Before the fix this fails with
  `session 1: the wrist never held phone-change-del-…` (findings §3, quoted verbatim).
- Edge case of: none (new class).

### S-16106: the filter is load-bearing (mutation)
- Fixture: S-16101's.
- Trigger: comment out the kind filter, re-run S-16101, restore.
- Expected outcome: red with the `phone-change-` mismatch line; green again after restore.
  Recorded in the evidence file (red→green table).
- Edge case of: S-16101.

### S-16102: check 3 keeps its teeth — a wrist that truly lacks a phone-held entry still fails
- Fixture: a fresh harness; the seed-857 shape scripted (A-146c-15: "a phone set never reaches the
  wrist after the wrist refuses a phone snapshot"): `PhoneStartsSession` (the wrist adopts the
  shared session), then arm `runner.refuseNext(from: PairActor.phone, type: 'session_snapshot')`,
  then `PhoneLogsSet` (its push is refused), then `runner.checkConvergence()` directly.
- Trigger: the refused push.
- Flow: the phone holds the set (mirror state); the wrist never received it.
- Expected outcome: `entryMismatches` contains `session 1: the wrist never held <the phone set's
  entryId>` — a wrist-kind id, not a `phone-change-` id. This stays red-teeth after D-16101.
- Edge case of: S-16101.
- Note: if the set rides a frame type other than `session_snapshot` (check
  `WatchSessionAutoPush`'s push, `test/watch_session_auto_push_test.dart` S-71), arm that type and
  record which in the evidence file (A-161-02).

### S-16103: the shrunk status trace — a within-tolerance tie counts as converged (OWNER TO CONFIRM)
- Fixture: a fresh harness; actions `[WristStartsFreeWorkout, LinkDrops, PhoneDiscards,
  WristFinishes]` (the findings' SHRUNK 29/117/149/193 shape, §5). No `TimeAdvances`: the phone's
  discard and the wrist's finish stamp the **same** grid instant from the shared clock.
- Trigger: run the trace, heal, check.
- Flow: the phone announced `abandoned` at t0 and deleted its row; the wrist finished at t0. The
  wrist applies D-15403 to comparable stamps: equal instants, different statuses → within the
  tolerance → tied → the tie-break keeps `completed` on the wrist. The phone holds nothing
  (D-14632). The phone's abandonment may also reach the wrist via the heal's re-offer, stamped
  *after* the finish by the shared clock — later, so it deletes nothing either way.
- Expected outcome: `report.converged` is true; `phoneStatus` reads `abandoned` and `wristStatus`
  `completed`; the disagreement appears in `withinSkewEndTies` (both end instants within
  `kEndSkewToleranceMs`), not in `statusMismatches`. The tests' reason text carries
  "owner to confirm" (D-16105).
- Edge case of: S-16104 (the same trace with a time advance).
- Planner's derivation, vetoable (A-161-01): the brief's "both sides agree on completed" is read
  as *the finish wins and the tie counts as converged*. A literal phone-side `completed` is not
  reachable: the discard deletes the phone's row (`session_core_lifecycle.dart:117`) and nothing
  resurrects it (D-14632; `watch_session_importer.dart:133-137`), and `_routeLifecycleToHeld`
  early-returns when the phone holds nothing (`watch_session_adoption_bridge.dart:878-879`).

### S-16104: the mirrored trace — the discard stamped earlier by more than 2 s deletes on both sides
- Fixture: S-16103's actions with `TimeAdvances(3)` inserted between `PhoneDiscards` and
  `WristFinishes` (discard t0, finish t3).
- Trigger: run the trace, heal, check.
- Flow: the arriving `abandoned` is earlier than the held finish by 3000 ms > `kEndSkewToleranceMs`
  → D-14630's earlier end wins → the wrist deletes its copy; the phone already deleted its own.
- Expected outcome: both sides read `abandoned`; `report.converged` is true;
  `withinSkewEndTies` is EMPTY — no tie was needed.
- Edge case of: S-16103.

### S-16105: the sweeps re-measured, reproducible, and the ratchet holds
- Fixture: the sweep itself, `kShippingActions`.
- Trigger: the 200-seed sweep run twice, then the 2000-seed soak
  (`--dart-define=CONVERGENCE_SEEDS=…`).
- Flow: after Phases 1–3 the artifact classes are gone; whatever remains is named.
- Expected outcome: the two 200-seed runs report the **same** diverging seeds (the class-membership
  movement findings §1 documents was driven by the stamp gap and falls away; if they still
  disagree, that is a Residue finding, not silence); class counts before/after recorded in the
  evidence file; the contract test green at both sizes; no unknown class.
- Edge case of: none (measurement scenario).

## Iteration 1

### Phase 1: the frame-clock seam (@developer) — nothing depends on it except Phase 3
1. [ ] Add the seam parameter — `lib/state/watch/watch_sync_wiring.dart` · `createWatchSync`
       (:219): `DateTime Function()? frameClock` (after `clock`, with a one-line doc naming the
       default); pass `clock: frameClock,` into the `LiveSessionMirrorState(...)` call at :290,
       directly above the unchanged `ledgerClock: clock,` (:296).
2. [ ] Update the wiring comment (:293-295) to name the seam: production passes none so the
       mirror's frame clock stays `_utcNow`; tests pin the pair's clock; the still-clock guard now
       lives in the parameter's default and in `_ledgerClock`'s separate seam (D-16102, D-16103).
3. [ ] One-line doc — `lib/state/watch/live_session_mirror_state.dart` · the constructor
       (:73-88): `clock` is the frame-stamp clock (`sentAt`, lifecycle `at`, rating `loggedAt`);
       `ledgerClock` stays separate (plan 128 D-1/D-2a; plan 127 D-8).
4. [ ] Pin the harness — `test/helpers/watch_pair_harness.dart` · `WatchPairHarness.build`
       (:789-798): add `frameClock: clock.call,` beside `clock: clock.call,`.
5. [ ] Run the coherent-clock suites green; every red is re-derived against the coherent clock and
       recorded red→green in the evidence file (an expectation that relied on the real-clock gap —
       D-15204's aliased stamps — is re-read against the grid; a red that instead shows a genuine
       ordering question goes to the Assumption Log, never patched blind):
       `.github/copilot/scripts/macos/gateway.sh test test/diagnostics_wiring_source_test.dart test/watch_convergence_harness_test.dart test/live_mirroring_test.dart test/watch_session_auto_push_test.dart`, then the full suite once (900 s timeout).
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`gateway.sh test <the four files above>` then `gateway.sh test` (full, 900 s); `lib/main.dart` is
untouched (the proof production behaviour cannot change — D-16102).
**Predicted Files**: `lib/state/watch/watch_sync_wiring.dart`;
`lib/state/watch/live_session_mirror_state.dart`; `test/helpers/watch_pair_harness.dart`;
`…-161-…-plan.evidence.md`. Nothing else — any other `lib/` diff is a finding.

### Phase 2: the entries filter and its three proofs (@developer) — independent of Phase 1
1. [ ] Red test first — `test/watch_convergence_harness_test.dart` · new test `S-16101 the shrunk
       entries trace converges once the phone's own annotations leave check 3` (the S-16101
       trace). Expected red with the `phone-change-` mismatch; if the exact 4-action list does not
       fail before the filter, re-shrink from the sweep's `entries` class (`Shrinker`) and record
       the final list in the evidence file.
2. [ ] Apply the filter — `test/helpers/watch_pair_harness.dart` · `HarnessRunner._sampleEntries`
       (:1290-1307): in the inbox loop, keep only rows whose `kind` is not in
       `WatchInboxEntry.phoneKinds`; comment cites plan 158 §3 and D-132
       (`lib/data/models/models.dart:2843-2850,2945`).
3. [ ] Green — the S-16101 test passes.
4. [ ] Mutation proof — comment the filter out, re-run the S-16101 test (red with the
       `phone-change-` line), restore; record both runs in the evidence file (S-16106).
5. [ ] Teeth test — `test/watch_convergence_harness_test.dart` · new test `S-16102 check 3 keeps
       its teeth …` (the S-16102 trace): green WITH the filter, asserting the mismatch names a
       wrist-kind entry id.
6. [ ] Run both convergence test files green.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart`
(200-seed default); the mutation table in the evidence file.
**Predicted Files**: `test/helpers/watch_pair_harness.dart`;
`test/watch_convergence_harness_test.dart`; `…-plan.evidence.md`.

### Phase 3: the within-tolerance tie and the status proofs (@developer) — BLOCKED by Phase 1
1. [ ] Record end instants — `test/helpers/watch_pair_harness.dart`: `HarnessRunner` gains
       `final Map<String, int> phoneEndAtMs = {}` and `wristEndAtMs = {}`; the phone's is filled in
       `_phoneDiscards` (:1742-1752, `clock.now.msSinceEpoch`) and in `_phoneStatusOf`
       (:1246-1260, `row.endedAtMs!` when the row is ended); the wrist's in `_wristStatusOf`
       (:1262-1277, the held/stored row's `endedAtMs` when its status is terminal) (D-16104).
2. [ ] Named predicate — `test/helpers/watch_pair_harness.dart` · new top-level
       `endsWithinSkewToleranceMs(int aMs, int bMs) => (aMs - bMs).abs() <= kEndSkewToleranceMs`
       (import `package:omnitrain/core/sync_protocol/end_skew.dart`), doc: the ms twin of
       `areEndsWithinSkew`; OWNER TO CONFIRM (D-16105).
3. [ ] Check change — `HarnessRunner.checkConvergence` (:1524-1596): in the
       `shared && phoneStatus != wristStatus` branch, when both statuses are terminal (the
       `_endedStatus` pair), both end instants are known, and the predicate holds → add a
       description line to the new `withinSkewEndTies` list instead of `statusMismatches`;
       unknown instants → mismatch exactly as today. Same-status behaviour untouched (D-15405).
4. [ ] Report field — `ConvergenceReport` (:2023-…): `final List<String> withinSkewEndTies;` — NOT
       in `failures`, shown as a count in `toString`'s converged branch, so the measurement stays
       visible and classifies no new sweep kind (`_kindsOf` reads nothing new).
5. [ ] Test — `test/watch_convergence_harness_test.dart` · `S-16103 the shrunk status trace …`
       (the S-16103 trace): converged; `phoneStatus`/`wristStatus` read `abandoned`/`completed`;
       `withinSkewEndTies` names session 1; reason text carries "owner to confirm".
6. [ ] Test — same file · `S-16104 the mirrored trace …` (the S-16104 trace): both `abandoned`,
       converged, `withinSkewEndTies` empty.
7. [ ] Owner question: record D-16105's statement (today's behaviour, the proposed default, the
       flag) in the plan's Open-question note and in both tests' reason lines.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart`.
**Predicted Files**: `test/helpers/watch_pair_harness.dart`;
`test/watch_convergence_harness_test.dart`; `…-plan.evidence.md`.

### Phase 4: re-measure and ratchet (@developer) — BLOCKED by Phases 1–3
1. [ ] Baseline into the evidence file's before/after table — plan 158's measured 2000-seed counts
       (§1): `{status 149, entries 8, heal 42, absorbing 3}` kind-hits, 112 shipping divergers,
       200-seed ratchet constant 14.
2. [ ] Run the 200-seed sweep TWICE (`gateway.sh test test/watch_convergence_random_test.dart
       --dart-define=CONVERGENCE_SEEDS=200`), record both diverger lists; the two runs must agree
       (S-16105); disagreement → a Residue finding with the seeds, not silence.
3. [ ] Run the 2000-seed soak (`--dart-define=CONVERGENCE_SEEDS=2000`; 900 s timeout); record the
       class counts in the after column.
4. [ ] Ratchet — `test/watch_convergence_random_test.dart` · `shippingRatchet` (:216-226): lower
       the per-200 constant to measured + 2 seeds of headroom, never above 14 (D-16106); record
       old (14) and new with the measurement that supports it.
5. [ ] `knownClasses` (:198-207): rewrite the `status`/`absorbing`/`entries` texts as fixed by
       plan 161 (the artifact, the fix, the plan id); keep `timers` and `heal`; a NEW class → add
       as `unclassified — plan 161 residue (seeds: …), deferred` with its seeds and shrunk traces
       under Residue in the evidence file. Do NOT chase it here.
6. [ ] Residue section in the evidence file: the `heal` class (42 seeds at 2000, findings §1/§6) —
       follow-up, first step: a shrink whose predicate is `run.heal.converged == false`
       (`ConvergenceRun.replayActions` + `Shrinker.shrink`); plus any new classes from item 5.
**Done Criteria**: the S-14509 contract test green at 200 and 2000; the before/after table and the
Residue section present in the evidence file; no unknown class.
**Predicted Files**: `test/watch_convergence_random_test.dart`; `…-plan.evidence.md`.

### Phase 5: docs delta and residue sweep (@developer) — BLOCKED by Phase 4
1. [ ] Docs — `docs/state_management/watch_surface_transport.md` · the `### Convergence testing`
       section (:144): add ~8 lines — check 3 ignores the phone's own annotation kinds
       (`WatchInboxEntry.phoneKinds`); the pair's frame-clock seam (`createWatchSync(frameClock:)`,
       harness-pinned to the pair's clock, production passes none); the within-tolerance tie
       (`endsWithinSkewToleranceMs`, visible in `withinSkewEndTies`, **owner to confirm**). State
       the page's current size against the 52 KB band (188 lines today, far under; re-measure and
       record both byte sizes in the evidence file per `test/docs_indexing_contract_test.dart`).
2. [ ] Seam doc grep — `grep -rn "createWatchSync" docs/`: update the one page that documents the
       graph's construction with the `frameClock` parameter; if none names it, record the grep and
       "no doc names the construction" in the evidence file — nothing to edit.
3. [ ] `docs/watch_session_sync/what_does_not_sync.md`: **no change** — the product conflict rule
       is unchanged (D-15403 already governs; the tie change is test-side); record in the delta
       table.
4. [ ] Residue sweep — grep proof that zero readers of the replaced representations remain:
       `phone-change` under `test/helpers/` appears only in the filter's comment;
       `entry.entryId` in `_sampleEntries` has exactly one reader, filtered; `ledgerClock` is
       passed exactly once, unchanged. Paste the greps in the evidence file.
5. [ ] Plan bookkeeping: tick Progress; mark each Assumption Log entry RATIFIED or REVERT.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`gateway.sh test test/docs_indexing_contract_test.dart`.
**Predicted Files**: `docs/state_management/watch_surface_transport.md`; this plan;
`…-plan.evidence.md`.

## Files Affected (whole feature)

- `lib/state/watch/watch_sync_wiring.dart` — the seam (Phase 1; the ONLY product change).
- `lib/state/watch/live_session_mirror_state.dart` — a doc line (Phase 1).
- `test/helpers/watch_pair_harness.dart` — the harness pin, the filter, the end-instant maps, the
  predicate, the check change (Phases 1–3).
- `test/watch_convergence_harness_test.dart` — S-16101/S-16102/S-16103/S-16104 tests (Phases 2–3).
- `test/watch_convergence_random_test.dart` — ratchet + `knownClasses` (Phase 4).
- `docs/state_management/watch_surface_transport.md` — the convergence-testing section (Phase 5).
- Read-only dependents: `lib/main.dart` (must not change — the production proof);
  `lib/core/sync_protocol/end_skew.dart` (imported, not edited); `lib/data/models/models.dart`
  (constants imported, not edited).

## Notes

- Dependency graph: Phase 1 → Phase 3; Phase 2 independent of Phase 1 (its failure mode is the
  id set, not the clock); Phase 4 needs Phases 1–3; Phase 5 last. Phase 2 may run before or
  beside Phase 1 — running it first gives the entries class its visible win at no cost.
- Intermediate state after Phase 1, before Phase 3: the shrunk *status* trace still diverges
  (`phone abandoned vs wrist completed`) — that is the designed tie of D-16105, resolved by
  Phase 3's predicate, not a Phase 1 defect. The mirrored trace (with `TimeAdvances(3)`)
  converges from Phase 1 alone.
- The phone's own session ids still come from the real clock (A-145-02) and the inbox's
  `appliedAtMs` still reads the wall clock; the label mapping (A-145-06) and the annotation filter
  keep both out of the checks' arithmetic. Do not "fix" them here.
- Legacy handling: none — no persisted field, table, or shared constant changes; the SQLite
  contract and seed data are untouched.

## Progress

- [x] Phase 1: the frame-clock seam (@developer) — landed; one red (S-14512) re-derived under
      A-161-05; `lib/main.dart` untouched; the four named suites green, lint 181 (= baseline).
- [x] Phase 2: the entries filter and its three proofs (@developer) — S-16101 red with plan 158
      §3's two `phone-change-…` ids, green with the filter, red again under the disabled-filter
      mutation; S-16102 green with the teeth it asserts; `entries` 8 → 0 and 2 (two 2000-seed runs).
- [x] Phase 3: the within-tolerance tie and the status proofs (@developer) — S-16103 green,
      S-16104 re-derived (A-161-06); the inverted-predicate mutation reddens both.
- [x] Phase 4: re-measure and ratchet (@developer) — 2000 seeds: 73 then 75 shipping divergers
      (112), `{status 94/95, entries 0/2, heal 34, absorbing 4/5}` (was `{149, 8, 42, 3}`);
      ratchet 14 → 8, the lowest constant the soak allows.
- [x] Phase 5: docs delta and residue sweep (@developer) — `watch_surface_transport.md` delta,
      seam/residue greps in the evidence file, no other page needed a change.

## Assumption Log

- **A-161-01 (planner, vetoable before Phase 3's handoff):** S-16103's expected outcome is derived,
  not quoted: the brief's "both sides agree on completed" is read as *the finish wins on the wrist
  and the tie counts as converged*, because the phone's discard deletes its row
  (`lib/state/workout/session_core_lifecycle.dart:117`) and nothing resurrects it (D-14632;
  `watch_session_importer.dart:133-137`; `watch_session_adoption_bridge.dart:878-879` early-returns
  when the phone holds nothing). If the owner wants the phone to *hold* the finished workout after
  its own discard, that is new product scope — a new plan, not a check change.
- **A-161-02 (planner):** the teeth test arms the refusal on `session_snapshot` (the class text of
  A-146c-15 names a refused phone snapshot); if the phone set rides another frame type, the test
  arms that type and records it in the evidence file.
- **A-161-03 (planner):** the ratchet formula "measured + 2 seeds of headroom, capped at 14" is the
  planner's reading of "down only to what the measured run supports with margin".
- **A-161-04 (planner):** the tie is implemented as *recorded but not failing* (`withinSkewEndTies`)
  rather than dropped silently, so the owner can still see how often the design tie occurs.
- **A-161-05 (developer, Phase 1):** the mirror's frames are on the pinned `frameClock`, but the
  phone's own row end is `DateTime.now()` (`session_core_lifecycle.endSession`), so a phone end and
  a grid-stamped wrist end can never tie; S-14512 is re-derived as a permanent
  `phone abandoned vs wrist completed` mismatch. Product seam = new plan.
- **A-161-06 (developer, Phase 3):** S-16104's "both sides read abandoned" is unreachable — the
  wrist is `active` when the queued `abandoned at=t0` arrives, and the frame that lands is the
  mirror's re-offer stamped `at=t3` (plan 128 D-1), which D-14603 resolves to `completed`; the test
  asserts the measured 3 s gap as a reported mismatch instead.
- All four planner entries above stand (none was contradicted); `status` remains 94 kind-hits at
  2000 → Residue, not a fix, because it is A-161-05's mechanism.

## Feedback

[empty]
