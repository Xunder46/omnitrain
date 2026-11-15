# Feature: 169 — the phone's own session row can be stamped from an injected clock

> Status: Iteration 1 active (owner unavailable — every derived default below is marked
> "owner to confirm" and listed in the Assumption Log)
> Next handoff: **@developer (Phase 1)**
> Binding conventions: `docs/global_conventions.md`
> Binding decisions from other plans, never relitigated here:
> - Owner rules **O-1..O-9** of plan 146 (`docs/plans/2026-11-11-146-ended-is-final-plan/2026-11-11-146-ended-is-final-plan.md:15-23`).
> - **D-15403 / D-15405** (plan 154): the 2 s end-skew tolerance between ends of different
>   status; within it the D-14601 tie-break decides (completed wins); only an end earlier by
>   MORE than the tolerance is the earlier end (`lib/core/sync_protocol/end_skew.dart`).
> - **D-16102/D-16103** (plan 161, `docs/plans/2026-11-14-161-harness-clock-and-entries-plan/…-plan.md`):
>   the mirror's frame clock seam (`frameClock`) and the harness pin; the pair's `TestClock`
>   does not stand still (D-16103's guard analysis).
> - **A-161-05** (plan 161 evidence): the phone's own row end is `DateTime.now()` in
>   `session_core_lifecycle.endSession`, so a phone end and a grid-stamped wrist end can never
>   tie — the residue this plan removes. **A-161-03**: the ratchet moves only down, to
>   measured + 2.
> - Plans 161/164's injection style: `DateTime Function()? clock` defaulting to the real clock
>   (`_clock = clock ?? DateTime.now`, e.g. `lib/state/watch/watch_session_adoption_bridge.dart:132-139`,
>   `lib/core/services/watch_session_importer.dart:78-88`).
> - Plan 167 (docs-only, not landed): a wrist-created session's row start comes from the
>   wrist's `at` via the adoption bridge's `_startSessionRow` — a different stamp site than
>   this plan's session core; no conflict (see Existing-Functionality Impact).
> - Plan 163 (`docs/plans/2026-11-14-163-kill-cases-in-the-sweep-plan/…-plan.md`): parked; its
>   Phase 1/2 stash `plan163-phone-kill-wip` holds `PhoneKilledAndRelaunched`. Not edited here
>   (see D-16907 and Notes).

## Overview

Plan 161 put the mirror's lifecycle frames on the harness pair clock, but the phone's OWN
persisted stamps still come from `DateTime.now()` inside the session core: the session row
(`TrainingSession.startedAtMs` / `endedAtMs` / `updatedAtMs` / `createdAtMs`), the effort and
observation rows, the rests and timed/round rows, and (through the row) the Health write and
re-write window, which is derived from `session.startedAtMs/endedAtMs`
(`lib/core/services/health_sync_service.dart:329-346` builds every window with
`DateTime.fromMillisecondsSinceEpoch` of the row's stamps — no wall-clock read of its own). In
the harness the phone's end is therefore ~4½ days ahead of the grid, D-15403 is applied to
stamps no alignment could tie, and the sweep's `status` class stays at 73–75 shipping seeds of
2000 and 5 of 200 (plan 161 evidence §Residue 1) — which blocks plan 163's re-measure (200
seeds now report 14 against a ratchet of 8, mostly `status`).

This plan adds the smallest seam: the **existing** optional
`DateTime Function()? clock` of `WorkoutState` (today documented as "the timer's clock seam",
`lib/state/workout/workout_state.dart:45,62,75`) is passed one level further into
`SessionCore`, which gains the same optional parameter defaulting to `DateTime.now`; every
wall-clock read in `lib/state/workout/session_core_*.dart` and the raw `DateTime.now()` reads
in `lib/state/workout/timer_manager.dart` that stamp persisted data go through it. Production
passes nothing (`lib/main.dart` has no `clock:` — grep proof below), so behaviour is
unchanged. The harness pins it to the pair's `TestClock` through a strictly-monotone wrapper.
Then the sweeps are re-measured, the ratchets move **down only**, and plan 163 resumes on the
new baseline.

Out of scope, explicitly: `SessionBlockManager`, `ExerciseLibrary`, `SessionSummaryBuilder`,
`ActiveEnergyService` and the Health body-weight window stay on the real clock (D-16902);
no model, schema or seed change (`lib/data/models/models.dart` untouched, so
`scripts/sqlite_schema.sql` is untouched); plan 163's stash is not pulled or edited; chasing
any NEW class the coherent stamps surface (listed as Residue instead).

## Resolved Decisions (Ledger)

- **D-16901 (the seam: SessionCore gains `clock`, every persisted stamp routes through it).**
  `SessionCore`'s constructor (`lib/state/workout/session_core.dart:105-131`) gains
  `DateTime Function()? clock` with field `final DateTime Function() _clock;` initialized
  `_clock = clock ?? DateTime.now` — exactly plans 161/164's injection style; no new pattern.
  Every `final now = DateTime.now().millisecondsSinceEpoch` in the session core's four part
  files that stamps a persisted row becomes `_clock().millisecondsSinceEpoch`:
  - `session_core_lifecycle.dart`: `endSession` :39 (row `endedAtMs` + `updatedAtMs` +
    `persistOpenRests(now)`), `resetSessionTimerStart` :161 (row `startedAtMs` +
    `updatedAtMs`), `updateSessionNote` :220, `updateSessionEndTime` :253 (row `updatedAtMs`;
    `endedAtMs` stays derived from `startedAtMs + durationSecs`), `catchUpEndedSession` :322
    (`updatedAtMs`; the moved end itself is the caller's `atMs` — D-14604), 
    `updateSessionFeeling` :365, `adoptSessionFeeling` :422, `updateSessionRpe` :451 — 8 sites.
  - `session_core_io.dart`: `createNewSession` :16 (id `session-$now`, `startedAtMs`,
    `createdAtMs`, `updatedAtMs`, default segment id/`atMs`), `populateSessionFromManifest`
    :315 (segment ids, `createdAtMs`/`updatedAtMs`) — 2 sites.
  - `session_core_entry.dart`: `addExerciseToSession` :21 (effort id, `createdAtMs`),
    `addEntry` :164 (observation rows — `atMs ?? now` keeps its parameter), 
    `updateEntryValue` :351, the extra-weight branch :359, `_writeEntryDistance` :531,
    `markSetSkipped` :633 — 6 sites.
  - `timer_manager.dart`: the 19 raw `DateTime.now()` reads — :602, :681, :707, :776, :816,
    :847, :881 (round rows), :1055, :1081, :1153, :1251, :1588, :1625 (timed rows), :1295,
    :1339, :1375, :1408, :1512 (rest rows) — become `_clock()`; `_clock` already exists
    (:133-152, fed from `WorkoutState`'s parameter) and already stamps 6 other sites (:419,
    :433, :479, :496, :644, :740, :968, :1014, :1112), so this closes the file's own
    inconsistency. The elapsed reads :1434 (`restElapsedSecs`) route through `_clock()` too
    (D-16903).
  D-153's clamp is untouched: `endSession` still stores
  `math.max(startedAtMs, now)`; only the source of `now` changes. **OWNER TO CONFIRM** (the
  inclusion of the round/timed sites and of `restElapsedSecs`; A-169-01).
- **D-16902 (what stays on the wall clock — the smallest seam's complement, each with the
  grep that proves the convergence path does not read it).** Left unseamed in this plan:
  - `session_block_manager.dart` :57, :187 — block rows and a display label ("9:14 AM");
    grep `SessionBlock` over `test/helpers/watch_pair_harness.dart` and
    `test/watch_convergence_random_test.dart`: zero hits — no check reads block rows.
  - `exercise_library.dart` :84, :174 — exercise-library rows, not session data.
  - `session_summary_builder.dart` :39 (`endedAt = session.endedAtMs ?? now`) — the open
    session's display duration; a DURATION read that stays real (D-16903's rule names it:
    production `now` is real and the harness never reads a summary — grep
    `computeSessionSummary` over `test/helpers/`: zero hits).
  - `active_energy_service.dart` :39, `session_summary_service.dart` :25/:334,
    `health_sync_service.dart` :362 + `health_platform_gateway_io.dart` :197 (the body-weight
    read window) — not session-row data; the workout's own write/re-write span is derived
    from the row's stamps, so it follows the seam with no change of its own.
  If a later sweep class ever names these rows, extending the seam to them is the follow-up —
  listed in Notes, not built here.
- **D-16903 (duration reads follow the persisted stamps).** `restElapsedSecs` (:1434) and any
  other read that subtracts a persisted stamp from "now" routes through `_clock()`: elapsed
  and completion state are derived from persisted wall-clock stamps per the global
  convention (`docs/global_conventions.md` rule "Timestamps are source data"), so the same
  clock must produce both sides of the subtraction. In production `_clock` IS the real clock,
  so every duration stays exactly what it is today; only a pinned-clock test would otherwise
  compute a nonsense elapsed from two different clocks. The genuinely display-only reads that
  stamp nothing and subtract nothing persisted stay real (D-16902's `SessionSummaryBuilder`
  :39).
- **D-16904 (WorkoutState passes its existing `clock` into SessionCore — no new parameter).**
  `lib/state/workout/workout_state.dart` · the `SessionCore(...)` call (:69-79) adds
  `clock: clock,`; the `[clock]` doc (:45) is rewritten: "the workout state's clock seam —
  the timer's stamps AND the session core's persisted stamps; the default is the real clock".
  **Production proof, by grep:** `clock` appears nowhere in `lib/main.dart` (grep over the
  file returns only `WorkoutState`/bind lines), so `main.dart:410-424` passes no clock and
  both consumers default to `DateTime.now` — production behaviour byte-identical. Of 172 test
  files constructing `WorkoutState` (grep `WorkoutState(` over `test/`), exactly one passes a
  clock: `test/watch_session_queue_test.dart:326` with `_tickingClock()` (:49-56, "real time,
  strictly increasing by at least a millisecond per read"). Analysis: its stamps remain
  real-time values (the wrapper reads `DateTime.now()`), strictly monotone, and the file
  asserts no absolute stamp — the seam makes that test MORE correct (monotone row stamps);
  the file is in Phase 1's Done Criteria. **OWNER TO CONFIRM** (reusing the parameter rather
  than adding a second seam à la `frameClock`; A-169-02).
- **D-16905 (the harness pin is a strictly monotone wrapper over the pair clock — supersedes
  the "equal instants" wording of plan 161's D-16103 for the phone half).**
  `WatchPairHarness.build` (`test/helpers/watch_pair_harness.dart:783`) becomes
  `final phone = WorkoutState(repository, clock: _gridClock(clock));` where `_gridClock` is a
  new top-level helper beside `build`: it keeps `lastMs` (the
  `watch_session_queue_test.dart:49-56` pattern) and returns
  `DateTime.fromMillisecondsSinceEpoch(max(gridMs, lastMs + 1))`. **Why not the bare
  `clock.call`:** with a standing clock, `PhoneStartsSession` after `PhoneDiscards` with no
  `TimeAdvances` between mints `session-$nowMs` with the SAME id the discarded row had, and
  `HarnessRunner`'s per-id bookkeeping (`phoneDiscardedSessions`, the plan 161
  `phoneEndAtMs`/`wristEndAtMs` maps) would misread the new session as the discarded one — a
  harness artifact this plan would otherwise mint. The wrapper makes two reads never equal
  while every stamp stays the grid instant or a few ms ABOVE it, never behind; the wrist half
  keeps the bare `clock.call` (`:835`, `:846` unchanged), and the replay corpus is unaffected
  because it records the wrist's input timeline only (plan 163 D-16303; phone-side stamps
  never enter a recording). Off-grid-by-a-few-ms stamps are D-15204's known alias. The
  wrapper's `lastMs` accumulates 1 ms per read between grid advances; every trace the suites
  play stays ≪ `kEndSkewToleranceMs` (2000) — plan 161's S-16103 same-instant tie becomes a
  1 ms-apart tie with the same verdict. **OWNER TO CONFIRM** (A-169-03).
- **D-16906 (re-measure and ratchet down only — A-161-03's policy applied to this plan).**
  After Phases 1–2 the 200-seed sweep runs TWICE and the 2000-seed soak once; the per-200
  constant in `shippingRatchet` (`test/watch_convergence_random_test.dart`, the
  `shippingRatchet` block at :216-226 as plan 163 cites it; currently 8) moves down to
  measured + 2 seeds of headroom, capped at the current 8 — never raised. `knownClasses`
  (:171-204): the `status` text is rewritten as fixed by plan 169 only if its kind-hits reach
  0 in both 200-seed runs and the soak; `entries`/`heal`/`absorbing`/`timers` texts keep
  their current meaning; a NEW class is entered as unclassified-with-owner and listed under
  **Residue** with its seeds and a shrunk trace (`ConvergenceRun.replayActions` +
  `Shrinker.shrink`) — not chased here. **OWNER TO CONFIRM** (A-169-04).
- **D-16907 (plan 163 resumes after this plan; one line, no edit to plan 163).** Plan 163's
  Phase 2 (the 200-seed re-measure with `PhoneKilledAndRelaunched` in the space) is re-run on
  this plan's landed baseline: the ratchet it inherits is plan 169's measured value, the
  standing rule "constants only go down" (D-16306) is unchanged, and the stash's
  `relaunchPhone` must construct `WorkoutState(repository, clock: _gridClock(clock))` — the
  same pin `build()` uses — or a phone kill would silently move the phone half back to the
  wall clock (a rebase note for plan 163's executor, not a change here).

## Feature Invariants

- Production's clock source is unchanged: `lib/main.dart` passes no `clock:` to `WorkoutState`
  or `createWatchSync`; both default to the real clock. Proved by grep in Phase 1 and guarded
  by S-16902.
- Implementation parity is untouched: the seam lives in the state layer above
  `WorkoutRepository`; `HiveWorkoutRepository` and `MockWorkoutRepository` see identical
  `TrainingSession`/observation writes for the same inputs (the same `_clock` value flows
  regardless of the repository behind it).
- An end the caller names explicitly (`endSession(atMs:)`, `catchUpEndedSession(atMs)`,
  `addEntry(atMs:)`, `seedFirstEntry`'s `atMs`) stores exactly that instant, as today — the
  seam only replaces the fallback.
- The D-153 clamp (`endedAtMs = max(startedAtMs, now)`) is preserved verbatim.
- In the harness, every phone-side persisted stamp comes from the one pair clock, monotone;
  the wrist side stays on the bare grid clock.
- No model, table, seed or shared constant changes: `lib/data/models/models.dart` and
  `scripts/sqlite_schema.sql` are untouched, so no regression test for dependent surfaces is
  owed beyond the suites below.
- The ratchet never rises; a class this plan does not name cannot arrive silently (the
  S-14509 `unknown` guard stays).

## Requirements

- **R-1**: the session-core seam (D-16901) with a red-first unit pin (S-16901) and the
  production no-op proof (S-16902).
- **R-2**: the harness pin (D-16905) with the grid-landing proof (S-16904), the same-ms
  mint guard (S-16905) and the timer-coherence proof (S-16906); the atMs paths unchanged
  (S-16907).
- **R-3**: S-14512 re-derived back to the standing rules (S-16908); every other red the pin
  turns up re-derived in the evidence file, never patched blind.
- **R-4**: re-measured 200- and 2000-seed sweeps; before/after class counts in the evidence
  file; ratchet tuned down only (D-16906); residue listed, not chased.
- **R-5**: docs delta per the table in Phase 4; plan 163's resume note recorded (D-16907).

## Acceptance Criteria (each maps to ≥ 1 scenario)

1. With a fixed injected clock, the phone's session row, effort and observation rows, and
   rest rows all carry that clock's stamps; with no clock, production stamps are unchanged →
   S-16901, S-16902, S-16903.
2. In the harness the phone's own end, rests and timer stamps land on the pair clock; a
   same-ms restart mints a distinct session id → S-16904, S-16905, S-16906.
3. Ends the caller names explicitly still store exactly that instant → S-16907.
4. S-14512 reads by the standing rules again; the sweeps are re-measured with before/after
   counts in the evidence file; the ratchet reflects the measurement, never above 8 per 200 →
   S-16908, S-16909.
5. The docs name the seam; the residue sweep shows zero unexplained wall-clock readers left
   in the session core → Phase 4.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect | Guarded by |
| --- | --- | --- | --- |
| `SessionCore` ctor (`session_core.dart:105`) | constructed only by `WorkoutState` (:69-79) — grep `SessionCore(` over `lib/` + `test/`: one production caller, zero test callers | new optional param; default keeps today's values | D-16901, S-16901 |
| The 8 lifecycle sites (`session_core_lifecycle.dart`) | `endSession` is called by the adoption bridge (:925) with `atMs` from the wrist's frame (already instant-parameterized — D-15402) and by screens/user finish with no `atMs`; `catchUpEndedSession` by the bridge (:899); the rest by screens only | stamp source becomes injectable; `atMs` paths byte-identical | D-16901, S-16901, S-16907 |
| `createNewSession` (`session_core_io.dart:16`) | screens (`HomeScreen:910`), the harness `_phoneStartsSession` (:1759) | the id `session-$now` and the start stamp follow the seam; in the harness ids become grid-stamped | D-16901, D-16905, S-16905 |
| The 6 entry sites (`session_core_entry.dart`) | screens, `seedFirstEntry` (harness `_phoneLogsSet`), the bridge's `appendSessionSlots` (no clock read there) | observation/effort stamps follow the seam | D-16901, S-16901 |
| TimerManager's 19 raw reads (`timer_manager.dart`) | `WorkoutState` is the only constructor (grep `TimerManager(` over `lib/`: one); its rows are read by the checks via the mirror's timer frames (`_timerDisagreements` compares `startedAt`) | stamps become coherent with the seams the tests already inject | D-16901, D-16903, S-16906 |
| `WorkoutState`'s `clock` param (`workout_state.dart:62`) | today flows to `TimerManager` only; 172 test files construct `WorkoutState`, exactly one passes a clock (`test/watch_session_queue_test.dart:326`, strictly-monotone real-time) | the same value now also feeds SessionCore; that one caller's stamps stay real-time and become monotone — its assertions read none | D-16904, S-16903 |
| `WatchPairHarness.build`'s `WorkoutState(repository)` (:783) | every harness/convergence test and the sweep | the pin; the phone half's stamps join the pair clock | D-16905, S-16904 |
| Plan 164's `_boundedEnd` / bridge clock | the bridge's `_clock` is wired from `createWatchSync(clock:)` — grid in the harness, unchanged here | with the row stamps on the grid, D-153's clamp and D-16401's five-minute bound compare coherent instants (today the clamp floors every grid end up to the wall-clock start) | S-16908's re-derivation records any shift |
| Plan 167 (docs-only) | the bridge's `_startSessionRow` start stamping — a different site, untouched here | none; if plan 167 lands first its wrist-`at` start is orthogonal to the session core's stamps | Notes |
| NOT touched — `lib/main.dart`, models, schema, plan 163's files | grep `clock` over `lib/main.dart`: zero hits; `PhoneKilledAndRelaunched` is stash-only | production no-op; no schema drift | S-16902, D-16907 |

## UI Standards Impact

None — no screen, widget or shared UI piece is touched. The docs delta touches
`docs/state_management/workout_state.md` (32.6 KB today, far under the 52 KB split band;
re-measure and record both figures in the evidence file per
`test/docs_indexing_contract_test.dart`) and
`docs/state_management/watch_surface_transport.md` ("### Convergence testing", ~274 lines /
~12 KB today).

## Scenarios

### S-16901: with a fixed injected clock, every persisted session stamp carries it
- Fixture: new `test/workout_state_clock_seam_test.dart`, plain `test()` (never
  `testWidgets`); `MockWorkoutRepository` initialized, one exercise seeded; a fixed clock
  `DateTime Function() f = () => DateTime.fromMillisecondsSinceEpoch(1794301200000)`;
  `WorkoutState(repo, clock: f)`.
- Trigger: `createNewSession()`; `addExerciseToSession(ex)`; `addEntry(effortId)`;
  `recordRestStart(...)`; then `endSession(writeToHealth: false)`.
- Flow: the state writes the session row, the effort, the observation and the rest row.
- Expected outcome: the session's id is `session-1794301200000`, `startedAtMs == createdAtMs
  == updatedAtMs == 1794301200000`; the effort's and observation's `createdAtMs/updatedAtMs`
  equal it; the rest's stamps equal it; `endedAtMs == 1794301200000`. At HEAD this is RED
  (the row id carries the wall clock).
- Edge case of: none (the seam's own pin).
- Note: `recordRestStart`'s exact signature is taken from `timer_manager.dart:1287-1295`
  (`addEntryRest`) — the executor adapts the call, not the assertion.

### S-16902: production is a no-op (the wiring proof)
- Fixture: the grep itself, run at Phase 1's close and pasted in the evidence file.
- Trigger: grep `clock` over `lib/main.dart` (expect zero hits), grep `WorkoutState(` over
  `test/` (172 hits, exactly one with `clock:` — `watch_session_queue_test.dart:326`), grep
  `SessionCore(` over `lib/ test/` (one caller, `workout_state.dart:69`).
- Expected outcome: the full suite runs green with the counts of the plan-161-era baseline
  (`+7577 ~5 -1` in plan 161's evidence, S-15207 the only red) — no new red anywhere; lint at
  the repo's pre-existing baseline (181 issues, 0 errors).
- Edge case of: S-16901.

### S-16903: the one existing clock caller keeps its meaning
- Fixture: `test/watch_session_queue_test.dart` as it is (its `_tickingClock`).
- Trigger: the file's suite after the seam.
- Expected outcome: green with no edit — its stamps remain strictly-monotone real-time
  values; no assertion reads an absolute stamp (checked by the executor before running;
  a red here is a finding recorded in the evidence file, not a silent fixture change).
- Edge case of: S-16901.

### S-16904: the phone's own end lands on the pair clock (harness E2E)
- Fixture: `WatchPairHarness.build()` (now pinned); `runner.phoneStartsSession()`, then
  `runner.phoneFinishes()`.
- Trigger: read `(await harness.repository.getSession(id))!.endedAtMs` and
  `harness.clock.now.millisecondsSinceEpoch`.
- Flow: the phone ends its own session; the row's end is stamped by the seam.
- Expected outcome: `endedAtMs` is within 100 ms of the pair clock's current instant (the
  wrapper's drift allowance); at HEAD it is ~4½ days ahead — RED before Phase 2's pin, GREEN
  after. Mutation proof: revert the pin to `WorkoutState(repository)`, the test reddens with
  the wall-clock gap; restore.
- Edge case of: S-16901.

### S-16905: a same-millisecond discard-and-restart mints a fresh session id
- Fixture: pinned harness; actions `[PhoneStartsSession, PhoneDiscards, PhoneStartsSession]`
  via `ConvergenceRun.replayActions` (or direct `runner.perform`s) with NO `TimeAdvances`.
- Trigger: the second start, same grid instant as the first mint.
- Flow: `createNewSession` mints `session-$nowMs` twice from a standing clock.
- Expected outcome: the two session ids differ (the wrapper's monotone reads);
  `runner.checkConvergence()` reports no status mismatch and `phoneDiscardedSessions`
  contains only the first id — the bookkeeping is not misread onto the second session.
- Edge case of: S-16904 (adversarial: the collision the wrapper exists to prevent).

### S-16906: rests and the mirror's timer `startedAt` land on the grid coherently
- Fixture: pinned harness; `runner.phoneStartsSession()`, then the rest action
  (`PhoneStartsRest` — `_options` :2060-2075's phone rest mint) or
  `phone.recordRestStart(...)` directly, then `runner.phoneFinishes()`.
- Trigger: read the rest row's stamps from the repository and the mirror state's rest timer
  `startedAt` (`harness.graph.mirror.state['timers']`).
- Flow: the rest row is stamped by TimerManager's `_clock`; the mirror's timer frame carries
  that stamp.
- Expected outcome: both read the same grid-coherent instant (within the wrapper's few-ms
  drift); at HEAD the row's stamp is the wall clock while the frame's is the grid. Before
  the seam `_timerDisagreements` counted such a pair by `startedAt` alone; after it the
  phone-side `startedAt` is grid-coherent.
- Edge case of: S-16904.

### S-16907: an end the caller names explicitly still stores exactly that instant
- Fixture: the existing fixtures — `test/watch_session_finish_test.dart` S-14609 (its
  `_phone(repository)` at :153-183 constructs `WorkoutState(repository)` with NO clock) and
  `test/watch_session_adoption_bridge_test.dart` S-15403 (its `_phone` at :184 constructs
  `WorkoutState(repository, healthSync: …)`, no clock).
- Trigger: `endSession(atMs: t1)` / the bridge's `endSession(atMs: _boundedEnd(atMs))`.
- Flow: the atMs path.
- Expected outcome: unchanged — the stored end is exactly the named instant (S-14609's and
  S-15403's existing expects stay green untouched). **These two plan-164 fixtures are NOT
  affected by the seam**: they pass no clock, so the phone's stamps stay wall-clock by
  default, and every instant they compare is derived from `startedAtMs` — grep proof in the
  impact table. They run in Phase 1's Done Criteria as the regression guard for the atMs
  paths.
- Edge case of: S-16901.

### S-16908: S-14512 returns to the standing rules
- Fixture: `test/watch_convergence_harness_test.dart` · `S-14512 a phone end against a wrist
  abandon while apart is recorded` (:821-891), unchanged trace
  `[PhoneStartsSession, LinkDrops, PhoneFinishes, WristDiscards, LinkRises]`.
- Trigger: run after Phase 2's pin.
- Flow: the phone's finish stamps the row on the grid; the wrist's discard is on the grid;
  plan 161's A-161-05 cause (the wall-clock row end) is gone.
- Expected outcome (derived, vetoable — A-169-05): the ends resolve per D-14630/D-15403 on
  comparable stamps — the wrist's discard is not earlier by MORE than the tolerance, so the
  finished row survives on the phone (`completed`), the wrist's own discard stands or the
  D-14601 tie-break resolves it, `statusMismatches` is empty or the disagreement is recorded
  as a `withinSkewEndTies` tie, and `absorbingViolations` stays empty; the test's asserts are
  re-written to that reading and the exact statuses observed are recorded in the evidence
  file. Whatever the exact reading, the test must no longer cite a ~4½-day stamp gap as the
  reason (the current comment at :856-866 goes).
- Edge case of: S-16904.

### S-16909: the sweeps re-measured, reproducible, ratchet down only
- Fixture: the sweep itself, `kShippingActions`.
- Trigger: the 200-seed sweep twice, then the 2000-seed soak
  (`--dart-define=CONVERGENCE_SEEDS=…`).
- Flow: after Phases 1–2 the `status` artifact is gone; whatever remains is named.
- Expected outcome: the two 200-seed runs report the same diverging seeds; the `status`
  kind-hits fall to 0 (or the residue is re-derived and recorded — plan 161's after-column,
  `{status 94/95, entries 0/2, heal 34, absorbing 4/5}`, is this plan's before-column); the
  S-14509 contract test green at both sizes with the ratchet at measured + 2, capped at 8;
  no unknown class.
- Edge case of: S-16105 (plan 161's measurement scenario).

## Iteration 1

### Phase 1: the session-core clock seam (@developer) — nothing depends on it except Phase 2

1. [ ] Red test first — `test/workout_state_clock_seam_test.dart` · new file, test
       `S-16901 with a fixed injected clock every persisted session stamp carries it`
       (the S-16901 fixture): expect the session id, row stamps, effort/observation stamps
       and rest stamps to equal the fixed clock's ms. Red at HEAD with a wall-clock id.
2. [ ] Add the seam — `lib/state/workout/session_core.dart` · `SessionCore` constructor
       (:105-131): parameter `DateTime Function()? clock`, field
       `final DateTime Function() _clock;`, `_clock = clock ?? DateTime.now`, one doc line
       naming the style's precedents (plans 161/164) and the default.
3. [ ] Route the lifecycle stamps — `lib/state/workout/session_core_lifecycle.dart`
       (`SessionCoreLifecycleMethods`): the 8 sites of D-16901 (:39, :161, :220, :253, :322,
       :365, :422, :451) become `_clock().millisecondsSinceEpoch`; leave `math.max(startedAtMs, now)`
       (:47-48) and every `atMs ??` fallback untouched.
4. [ ] Route the io stamps — `lib/state/workout/session_core_io.dart`
       (`SessionCoreIOMethods`): `createNewSession` :16 and `populateSessionFromManifest`
       :315.
5. [ ] Route the entry stamps — `lib/state/workout/session_core_entry.dart`
       (`SessionCoreEntryMethods`): the 6 sites of D-16901 (:21, :164, :351, :359, :531,
       :633); `addEntry`'s `atMs ?? now` keeps its parameter.
6. [ ] Route the timer stamps — `lib/state/workout/timer_manager.dart` (`TimerManager`): the
       19 raw `DateTime.now()` reads (:602, :681, :707, :776, :816, :847, :881, :1055, :1081,
       :1153, :1251, :1295, :1339, :1375, :1408, :1434, :1512, :1588, :1625) become
       `_clock()` — the field already exists (:133-152); a one-line comment at :133 noting
       the file no longer reads the wall clock directly (D-16903).
7. [ ] Pass it through — `lib/state/workout/workout_state.dart` · the `SessionCore(...)`
       call (:69-79): add `clock: clock,`; rewrite the `[clock]` doc (:45) to name both
       consumers (D-16904).
8. [ ] Green + proofs — run the focused suites, then the full suite once; run the S-16902
       greps and paste them in the evidence file.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (issue
count = the 181 baseline); `gateway.sh test test/workout_state_clock_seam_test.dart
test/watch_session_queue_test.dart test/watch_session_finish_test.dart
test/watch_session_adoption_bridge_test.dart`; `gateway.sh test` (full, 900 s timeout —
compare with plan 161's `+7577 ~5 -1` baseline: no new red; S-15207's known staleness is
pre-existing). `lib/main.dart` untouched (the production proof — D-16904).
**Predicted Files**: `lib/state/workout/session_core.dart`,
`lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/session_core_io.dart`,
`lib/state/workout/session_core_entry.dart`, `lib/state/workout/timer_manager.dart`,
`lib/state/workout/workout_state.dart`, `test/workout_state_clock_seam_test.dart` (new),
`…-169-…-plan.evidence.md`. Nothing else — any other `lib/` diff is a finding.
**Phase 1 verification notes (Conductor, date):** —
### Phase 1.Y: remediation — BLOCKS Phase 1 closure
(a red that shows a real ordering defect behind the seam — e.g. a stamp that must NOT move —
goes to the Assumption Log with file:line; never patched blind)

### Phase 2: pin the harness and re-derive (@developer) — BLOCKED by Phase 1

1. [ ] The wrapper — `test/helpers/watch_pair_harness.dart` · new top-level
       `DateTime Function() _gridClock(TestClock clock)` (beside `build`, :766): the
       `lastMs` monotone pattern of `test/watch_session_queue_test.dart:49-56`, doc citing
       D-16905 and the id-reuse hazard.
2. [ ] The pin — same file · `WatchPairHarness.build` :783:
       `final phone = WorkoutState(repository, clock: _gridClock(clock));` (the wrist-side
       `clock: clock.call` at :835/:846 and the `createWatchSync` pins stay bare).
3. [ ] S-16904 + mutation — `test/watch_convergence_harness_test.dart` · new test
       `S-16904 the phone's own end lands on the pair clock`; then the mutation proof (pin
       reverted → red with the wall-clock gap; restored → green), both runs in the evidence
       file.
4. [ ] S-16905 — same file · new test `S-16905 a same-millisecond discard-and-restart mints
       a fresh session id` (the S-16905 fixture).
5. [ ] S-16906 — same file · new test `S-16906 rest and timer stamps land on the grid`.
6. [ ] Re-derive the existing suite — run
       `gateway.sh test test/watch_convergence_harness_test.dart
       test/watch_convergence_random_test.dart test/live_mirroring_test.dart
       test/watch_session_auto_push_test.dart`: every red is re-derived against the coherent
       stamps and recorded red→green in the evidence file (the S-16101/S-16102/S-16103/
       S-16104 expectations of plan 161 must stay green — their ties survive the wrapper's
       few-ms drift); S-14512's re-derivation is item 7.
7. [ ] S-16908 — `test/watch_convergence_harness_test.dart` · the S-14512 test (:821-891):
       rewrite the asserts to the standing-rules reading (S-16908's derived expectation),
       replace the :856-866 comment with the seam citation; record the exact observed
       statuses in the evidence file (A-169-05, vetoable).
8. [ ] Owner question: record D-16905's statement (today's behaviour, the wrapper default,
       the flag) in the evidence file next to the mutation table.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`gateway.sh test test/watch_convergence_harness_test.dart
test/watch_convergence_random_test.dart` (200-seed default); the mutation table and the
S-14512 re-derivation in the evidence file; `gateway.sh git-diff --name-only` shows only the
two Phase-2 files plus the evidence file.
**Predicted Files**: `test/helpers/watch_pair_harness.dart`;
`test/watch_convergence_harness_test.dart`; `…-169-…-plan.evidence.md`.
**Phase 2 verification notes (Conductor, date):** —
### Phase 2.Y: remediation — BLOCKS Phase 2 closure
(a convergence test that reddens because a stamp the checks compare is now off by more than
the wrapper's drift: shrink it, classify, Residue — do not widen the tolerance)

### Phase 3: re-measure and ratchet (@developer) — BLOCKED by Phase 2

1. [ ] Baseline into the evidence file's before/after table — plan 161's measured after
       values (its evidence §Phase 4): 2000 seeds `{status 94/95, entries 0/2, heal 34,
       absorbing 4/5}` kind-hits, 73/75 shipping divergers; 200-seed ratchet constant 8.
2. [ ] Run the 200-seed sweep TWICE (`gateway.sh test
       test/watch_convergence_random_test.dart --dart-define=CONVERGENCE_SEEDS=200`); record
       both diverger lists; the two runs must agree (S-16909); disagreement → a Residue
       finding with the seeds, not silence.
3. [ ] Run the 2000-seed soak (`--dart-define=CONVERGENCE_SEEDS=2000`, 900 s timeout; on
       exit 124 diagnose, never re-run unchanged — record partial counts and scale the
       constant from a 1000-seed run, flagged owner to confirm).
4. [ ] Ratchet — `test/watch_convergence_random_test.dart` · `shippingRatchet` (the
       :216-226 block; the executor greps the symbol): lower the per-200 constant to
       measured + 2, capped at 8 (D-16906); record old (8) and new with the measurement that
       supports it.
5. [ ] `knownClasses` (:171-204): rewrite the `status` text as fixed by plan 169 if its
       kind-hits reach 0 in both 200-seed runs and the soak; keep `entries`/`heal`/
       `absorbing`/`timers`; a NEW class → entered as
       `unclassified — plan 169 residue (seeds: …), deferred` with its seeds and shrunk
       trace under Residue in the evidence file. Do NOT chase it here.
6. [ ] Residue section in the evidence file: any new class; plus the D-16907 note — plan
       163's Phase 2 re-measures on this baseline, its ratchet inherits this plan's measured
       value, and the stash's `relaunchPhone` must pass the same `clock:` pin.
**Done Criteria**: the S-14509 contract test green at 200 and 2000; the before/after table
and the Residue section present; no unknown class; `gateway.sh git-diff --name-only` shows
only `test/watch_convergence_random_test.dart` plus the evidence file.
**Predicted Files**: `test/watch_convergence_random_test.dart`; `…-169-…-plan.evidence.md`.
**Phase 3 verification notes (Conductor, date):** —
### Phase 3.Y: remediation — BLOCKS Phase 3 closure

### Phase 4: docs delta and residue sweep (@developer) — BLOCKED by Phase 3

1. [ ] Docs — `docs/state_management/workout_state.md`: extend the `WorkoutState`
       construction section (after the `wristRunsSession` paragraph, ~:31-40) with the clock
       seam — the parameter feeds `TimerManager` AND `SessionCore`, production passes none,
       the default is the real clock, tests pin it (plan 169 D-16904/D-16905); state the
       page's size before/after against the 52 KB band (32.6 KB today) in the evidence file.
2. [ ] Docs — `docs/state_management/watch_surface_transport.md` · the `### Convergence
       testing` section: add ~6 lines — the phone's own stamps join the pair clock via
       `WorkoutState(clock:)` pinned by `_gridClock` (strictly monotone over the grid, and
       why: the same-ms id-reuse hazard); the `status` class is fixed by plan 169; S-14512
       reads by the standing rules again; the ratchet values. Every behavioural sentence
       names its test (S-16904, S-16905, S-16908).
3. [ ] Residue sweep — grep proof that zero unexplained wall-clock readers remain in the
       seamed files: `DateTime.now` over `lib/state/workout/session_core.dart` +
       `session_core_io.dart` + `session_core_entry.dart` + `session_core_lifecycle.dart` +
       `timer_manager.dart` → only the `_clock = clock ?? DateTime.now` default and doc
       comments; the allowed remainder is exactly D-16902's list (`session_block_manager.dart`
       :57/:187, `exercise_library.dart` :84/:174, `session_summary_builder.dart` :39, plus
       `active_energy_service.dart` :39 / `session_summary_service.dart` :25/:334 outside
       the state folder). Paste the greps in the evidence file.
4. [ ] No-change records — `docs/watch_session_sync/what_does_not_sync.md`: no change (the
       product conflict rule is untouched; the seam changes which clock stamps, not who
       wins); `lib/data/models/models.dart` + `scripts/sqlite_schema.sql`: untouched (no
       schema drift) — both recorded in the delta table.
5. [ ] Close out — `gateway.sh lint` (baseline compare), `gateway.sh test
       test/docs_indexing_contract_test.dart`; tick Progress; mark each Assumption Log
       entry RATIFIED or REVERT; paste the S-16902 greps if not already there.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`gateway.sh test test/docs_indexing_contract_test.dart`; the greps and the size figures in
the evidence file.
**Predicted Files**: `docs/state_management/workout_state.md`;
`docs/state_management/watch_surface_transport.md`; this plan (Progress/Assumption Log
only); `…-169-…-plan.evidence.md`.
**Phase 4 verification notes (Conductor, date):** —
### Phase 4.Y: remediation — BLOCKS Phase 4 closure

## Files Affected (whole feature)

- `lib/state/workout/session_core.dart` — the seam parameter (Phase 1).
- `lib/state/workout/session_core_lifecycle.dart`, `session_core_io.dart`,
  `session_core_entry.dart` — the routed stamps (Phase 1).
- `lib/state/workout/timer_manager.dart` — the 19 routed reads (Phase 1).
- `lib/state/workout/workout_state.dart` — the pass-through + doc (Phase 1).
- `test/workout_state_clock_seam_test.dart` — NEW, the unit pin (Phase 1).
- `test/helpers/watch_pair_harness.dart` — `_gridClock` + the pin (Phase 2).
- `test/watch_convergence_harness_test.dart` — S-16904/S-16905/S-16906 tests, the S-14512
  re-derivation (Phase 2).
- `test/watch_convergence_random_test.dart` — ratchet + `knownClasses` (Phase 3).
- `docs/state_management/workout_state.md`,
  `docs/state_management/watch_surface_transport.md` — doc deltas (Phase 4).
- Read-only dependents: `lib/main.dart` (must not change — the production proof);
  `lib/state/watch/watch_session_adoption_bridge.dart` and
  `lib/core/services/watch_session_importer.dart` (their injected clocks are the style
  precedent, untouched); `lib/core/services/health_sync_service.dart` (reads the row's
  stamps, no edit); `test/watch_session_queue_test.dart` (the one clock caller, expected
  green untouched).

## Notes

- Dependency graph: Phase 1 → Phase 2 → Phase 3 → Phase 4. Phase 2 could technically split
  (pin, then re-derive), but one agent run keeps the red→green table coherent; if the run
  overflows 8 items, split into Phase 2A (items 1–5) and 2B (items 6–8) — 2B still before
  Phase 3.
- Intermediate state after Phase 1, before Phase 2: production is unchanged and the unit pin
  is green, but the harness still runs the phone half on the wall clock — S-16904 red, the
  sweep's `status` class unchanged. That is the designed seam, not a defect.
- Plan 163 resume (D-16907, one line): after this plan lands, plan 163's Phase 2 re-measures
  the 200-seed sweep with `PhoneKilledAndRelaunched` in the space on this plan's baseline —
  the ratchet it inherits is plan 169's measured constant (down-only, D-16306), and the
  stash's `relaunchPhone` must pass the same `clock:` pin `build()` uses, or a phone kill
  moves the phone half back to the wall clock. Plan 163's file is not edited here.
- The convergence checks read session statuses and end instants (`row.endedAtMs`), entry ids,
  and timer `state`/`startedAt` — none of the excluded D-16902 rows — which is why the
  smallest seam is complete for the sweep's purpose (each exclusion carries its grep).
- Legacy handling: none — no persisted field, table or shared constant changes; rows written
  before this plan keep their wall-clock stamps and are read exactly as before (the seam
  changes only future stamps; `catchUpEndedSession` still moves an old row's end when a later
  instant arrives, D-14604).
- Do NOT "fix" while here: the harness's `_sessionLabels`/`appliedAtMs` wall-clock reads
  (A-145-02/A-145-06 — labels only, outside the checks' arithmetic), and
  `WatchLoggingState`/`WatchNutritionLogBridge` (already seamed by their own `clock`
  parameters).

## Progress

- [x] Phase 1 — the session-core clock seam (@developer): landed; S-16901 red at HEAD
      (`Actual: 'session-1794704546325'`) → green; `DateTime.now` left only as the `_clock` default.
- [x] Phase 2 — pin the harness and re-derive (@developer): `_gridClock` pin + S-16904/S-16905/
      S-16906 green with three mutation proofs; S-14512 re-derived (both ends `completed`,
      `converged` true); harness file `+36` green. **One unplanned red**: the pin makes
      `watch/sync_protocol/fixtures/replay/seed-408.json` stale (its rest `startedAtMs` was a
      wall-clock value), so S-15207 fails — see Feedback; the fixture refresh was not applied.
- [x] Phase 3 — re-measure and ratchet (@developer): 200-seed sweep ×3 identical
      (`194` converge, `[94, 123, 145, 167]`); 2000-seed soak `1933` converge, 31 shipping,
      `{status 41, entries 9, heal 19}`, `absorbing 0`; ratchet 8 → 6.
- [x] Phase 4 — docs delta and residue sweep (@developer): both pages updated, residue greps show
      only the `_clock` default and D-16902's list, no schema/seed change.

## Assumption Log

Derived interpretations, offered for veto before the first handoff that depends on them
(Phase 1 depends on A-169-01/02; Phase 2 on A-169-03/05; Phase 3 on A-169-04):

- **A-169-01 (D-16901, owner to confirm)** The seam covers TimerManager's round and timed
  rows and the `restElapsedSecs` read, not only the rests the brief names. Options: rests
  only (leaves `_timerDisagreements`' `startedAt` comparison half-coherent); chosen: all 19
  sites, because the file already carries the `_clock` seam and partial routing would stamp
  one row from two clocks. Owner to confirm. — Landed as written; status awaiting ratification.
- **A-169-02 (D-16904, owner to confirm)** The existing `WorkoutState(clock:)` parameter is
  reused instead of adding a second seam (plan 161 added `frameClock` beside `clock` because
  the ledger's clock had to stay separate; here TimerManager and SessionCore have no such
  conflict — one clock for both is the coherent reading). Owner to confirm. — Landed as
  written; status awaiting ratification.
- **A-169-03 (D-16905, owner to confirm)** The harness pin is a strictly monotone wrapper
  rather than the bare `clock.call`, to prevent same-ms session-id reuse after a discard. Options:
  bare pin + an id-uniqueness guard in `createNewSession` (a product change for a harness
  need); chosen: the test-side wrapper. Owner to confirm. — Landed as written, proved by the
  S-16905 mutation; status awaiting ratification.
- **A-169-04 (D-16906, owner to confirm)** The ratchet cap is the current constant 8
  (measured + 2, never above 8) — A-161-03's policy carried to this plan. Owner to confirm. —
  Applied (8 → 6, from 4 measured on three runs); status awaiting ratification.
- **A-169-05 (S-16908, planner, vetoable before Phase 2's handoff)** The post-seam reading
  of S-14512 is derived, not observed: on coherent stamps the wrist's discard is not earlier
  by more than the tolerance, so the phone keeps its finished row and the pair resolves per
  D-14630/D-15403; the executor records the exact observed statuses in the evidence file and
  the owner vetoes the wording there if the engine's late-completed path resolves
  differently. — Observed `phone completed wrist completed, 0 mismatch(es)`, `converged`;
  status awaiting ratification.
- **A-169-06 (planner)** The brief's "rolling flag" inventory item: no wall-clock read writes
  `isRolling` anywhere — grep over `lib/` shows every writer copies the flag from an existing
  row or a caller's bool (`session_core_lifecycle.dart:57,176,235,272,320,380,437,466`;
  `hive_workout_repository.dart:1096`; `mock_workout_repository.dart:346,535`); nothing to
  seam. — Confirmed by grep; nothing needed.

- **A-169-07 (D-16904, developer)** The decision predicted exactly one pre-existing test that
  passes `WorkoutState(clock:)` (`test/watch_session_queue_test.dart`). There are three —
  `test/watch_session_auto_push_test.dart`, `test/watch_snapshot_focus_send_test.dart` and
  `watch_session_queue_test.dart`. All pass their own clocks and none asserts an absolute
  stamp; the suites stay green, so the seam is a no-op for them.
- **A-169-08 (phase 0, developer)** The scenario header names S-16901…S-16908 while the body also
  defines S-16909 (the two 200-seed runs agree). Both are implemented; the numbering gap is
  cosmetic.
- **A-169-09 (S-16901, developer)** The pin uses `createNewSession()`'s default modality so the
  `set` entry kind writes an observation row; the `sports`/`round` kind writes none, and the
  scenario asserts observation stamps.

## Feedback

- **D-16905's corpus claim is wrong (Phase 2, executor).** The decision says phone-side stamps
  never enter a replay recording; `watch/sync_protocol/fixtures/replay/seed-408.json` records a
  phone rest `startedAtMs` of `1795301201000` (wall clock), so the pin makes that fixture stale
  and S-15207 red — the one failure in the full suite (`+7626 ~4 -1`). Regenerating the corpus
  (`--dart-define=REPLAY_CORPUS_WRITE=true`) plus a `swift-test --filter WatchReplayTests` run is
  the remedy; both write/verify a checked-in fixture outside this phase's Predicted Files, so
  they were left to the governor. Evidence: `.evidence.md` §Plan-unpredicted red.
