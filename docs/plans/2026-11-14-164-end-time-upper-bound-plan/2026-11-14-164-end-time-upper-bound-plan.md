# Feature: Plan 164 — a later end time can no longer stretch a workout into the future

> Status: DRAFT (owner unavailable this run — every defaulted choice is marked **owner to confirm**)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
> Source: series review finding 6, `docs/plans/2026-11-13-153-series-review/2026-11-13-153-series-review.review.md`
> ("A later end time is applied with no upper bound (`catchUpEndedSession`, `_catchUpEnd`): a wrong
> watch clock or bad frame stretches the phone's workout into the future. Fix: clamp to now plus a
> tolerance. OPEN (lead).")
> Scope guard: `.github/copilot/pr-scope-budget.md` — one track (the phone app `lib/` + docs), 3 phases.

## Overview

The owner's rule O-5 (plan 146) made an ended workout's end time **the latest instant either side
has** (D-14604): the phone's `catchUpEndedSession` and the importer's `_catchUpEnd` move a stored end
forward to any later instant a wrist frame claims. Neither has an upper bound, so a wrong watch clock
or a corrupt frame can end the phone's workout tomorrow — an inflated duration, an inflated
active-energy estimate, and a Health re-write span (plan 154/155) that follows the bad end. The
lifecycle path the bridge routes to `endSession(writeToHealth: false, atMs:)` for an open held
session (D-15402) has the same exposure: a future `at` is stored verbatim.

This plan bounds every incoming end at the phone's three application points to the **receiving
device's own clock plus a tolerance**, clamps-and-keeps (a workout is never refused or lost), leaves
past ends untouched (a workout ending a day ago is a legitimate late sync, not an error), and keeps
the 2 s end-skew rules (D-15403/D-15405) exactly as they are. The Dart twin, the reconciler and the
Swift engine are analysed and deliberately **not** changed — see D-16404 for why that preserves
parity, and Notes for the site-by-site table.

## Resolved Decisions (Ledger)

- **D-16401 The bound and its semantics.** An end instant the phone receives from the wrist is
  bounded by the receiver's clock at decision time: `bounded = min(endMs, nowMs + kFutureEndClampMs)`.
  (a) **No lower bound**: an end in the past by any margin — a day, a month — is a legitimate late
  sync and is never clamped or refused. (b) **Clamp and keep**: a frame beyond the bound is clamped
  and still applied in full — the workout, its entries, its rating and its receipt are exactly what
  they would have been with an honest clock; only the end instant is bounded. Nothing is discarded,
  nothing is re-requested, no frame is refused. (c) **Never backward**: a clamp must not drag an end
  earlier than the end already stored — where the stored end is already later than the bounded value,
  nothing is written (the D-14604 move is forward-only). (S-16401..S-16407, S-16409)
- **D-16402 The tolerance: `kFutureEndClampMs = 300_000` (5 minutes), beside
  `kEndSkewToleranceMs` in `lib/core/sync_protocol/end_skew.dart`.** **Owner to confirm.** Reasons:
  (i) *different axis*: the 2 s skew tolerance compares two stamps of the same instant; the clamp
  bounds one stamp against the receiver's clock, so it must sit far above 2 s — an end a few seconds
  ahead of the phone's clock must never be clamped, or the two rules would fight; (ii) *legitimate
  drift*: an un-synced consumer clock drifts ~50 ppm ≈ 4.3 s/day, so a wrist that has not refreshed
  its time in weeks can legitimately be minutes ahead — 5 minutes covers that; (iii) *bounded
  damage*: the worst a bad frame can do is stretch duration, calories and the Health re-write span
  by 5 minutes, instead of unbounded. 2 s would clamp honest frames; an hour would allow a whole
  fake workout into the future. (S-16403)
- **D-16403 Where the clamp lives: the phone's three application points, at the frame boundary.**
  (1) `WatchSessionAdoptionBridge._routeLifecycleToHeld` clamps the lifecycle `at` once and routes
  the bounded value to `catchUpEndedSession` (an ended held row) and to
  `endSession(writeToHealth: false, atMs:)` (an open held row). (2) `WatchSessionImporter` clamps the
  wrist's end at parse (`_End.parse` takes the receiver's now) and the catch-up's `latest` in
  `_catchUpEnd` (the set-stamp vector). `catchUpEndedSession` and `endSession` keep their own
  contracts (D-14604 latest-instant; D-153 end ≥ start): `SessionCore` has no injected clock while
  the bridge and the importer do, and the frame boundary is where the receiver's clock is
  authoritative. The phone's own Finish (no `atMs`) never passes through a clamp. (S-16401, S-16402,
  S-16404..S-16407)
- **D-16404 Parity: the Dart twin, the reconciler and the Swift engine are not changed, and parity
  holds by construction.** Today all three already make the same decision on the same frame: a
  terminal-vs-terminal end replaces the held one only when it is EARLIER (D-14601/D-14630 as
  amended), so a later end can never stretch a held end on any of them; a future end into a
  **non-terminal** row is accepted by all three identically (`orderEnds`/`_incomingEndReplaces` in
  `lib/watch/session/watch_session_engine.dart`, `WatchSessionEngine.orderEnds` in
  `WatchSessionEngine.swift`, `_incomingEndWins` in `lib/core/sync_protocol/session_reconciler.dart`).
  The clamp is a receiver-clock rule, not a frame-ordering rule: the pure reconciler has no clock and
  `SyncSessionReconciler.convergedState()` exposes no end instant (its keys are `sessionId`, `status`,
  `revision`, `currentExerciseIndex`, `exercises`, `entries`, `timers` — cited), so no reconciliation
  rule changes and the cross-stack contract is untouched. `sentAt` stays untouched everywhere: it is
  the ordering clock (D-120 snapshot watermark), and clamping it would reorder frames. The wrist's
  residual exposure (a future phone `at` written into a wrist row and a captured session end) reaches
  the phone's history only through the importer, which D-16403 now bounds — the damage is contained
  at the phone boundary. **Owner to confirm** that containment-via-importer is preferred over a
  wrist-side clamp in this PR.
- **D-16405 No new reconciliation fixture, no version change.** The fixtures under
  `watch/sync_protocol/fixtures/reconciliation/` pin frame-ordering convergence between the
  reconciler and both engines (`test/sync_protocol_fixtures_test.dart` S-004 walks all 20);
  no reconciliation decision changes (D-16404), the fixture harness has no receiver-clock control,
  and the replay corpus (`fixtures/replay/`, 16 sources — regenerated by plan 160 Phase 2) compares
  end ids between the twin and the Swift engine, which this plan does not touch. (S-16410)
- **D-16406 PROTOCOL.md: one sentence, one amendment row, no version bump.** The end rules in
  "Idempotency and reconciliation (normative)" (~:690) gain one sentence: the phone additionally
  bounds an arriving end to its own clock plus 5 minutes at application time — application policy of
  the receiving device, not a reconciliation rule; a past end is never touched. One row in the
  amendment table (the 2026-11-13 pattern): no wire shape, schema, validator, rejection-code or
  version change. (S-16410)
- **D-16407 Logging: no new diagnostics plumbing.** `DiagnosticsLog` is not wired into the bridge or
  the importer: `createWatchSync` passes it only to `createPlatformWatchTransport`
  (`lib/state/watch/watch_sync_wiring.dart` ~:243-248), and the transport already records a
  `frame_received` line for every arriving frame (`lib/core/platform/watch_transport.dart`
  `_noteReceived`, ~:505) — so the offending frame is already visible in the copyable log. The clamp
  itself is reported by the bridge through its existing debug-report precedent (`_reportSkipped`,
  ~:118, `debugPrint`), once per clamp, naming the claimed and bounded instants; the importer clamps
  silently (test-observable through the stored end). **Owner to confirm** — a follow-up plan could
  wire `DiagnosticsLog` into the bridge if the clamp should appear in the copyable log.
- **D-16408 The clamp never stores an end before the row's own start.** When the bound lands before
  `startedAtMs` (a start in the phone's future — corrupt data), the bounded end is floored at the
  start: a zero-length session, never a negative duration. This mirrors `endSession`'s D-153 floor
  and applies at the importer's parse clamp, the only site where a stored end could otherwise end up
  before its start because of this plan. (S-16408)

## Feature Invariants

Only the ones that bite here; project-wide rules stay in `docs/global_conventions.md`.

- **A clamp only bounds; it never decides between two ends.** `orderEnds` and
  `kEndSkewToleranceMs` (D-15403/D-15405) are untouched: two end stamps still compare through the
  skew tolerance exactly as before; the clamp compares one stamp against the receiver's clock, at a
  bound two orders of magnitude above the skew tolerance, so the rules cannot interact. (S-16409)
- **A past end is data, never an error.** No lower clamp, no rejection, no report for an end behind
  the receiver's clock by any margin. (S-16409)
- **Every implementation of `WorkoutRepository` sees the same bounded value.** The clamp runs before
  any repository write (`_routeLifecycleToHeld`, `_End.parse`, `_catchUpEnd`), so
  `HiveWorkoutRepository` and `MockWorkoutRepository` cannot diverge on it. (S-16401, S-16404)

## Requirements

1. Every end instant the phone applies from a wrist frame — the lifecycle `at` (ended and open held
   rows), the wrist's `session_end` (`endedAt`), and any set stamp the importer's catch-up would
   move the end to — is bounded by the phone's clock at decision time plus the tolerance.
2. A bounded frame still applies in full (clamp-and-keep); nothing user-visible is lost.
3. A past end applies exactly as today.
4. The bound is injected for tests: the bridge's `clock:` and the importer's `clock:` are the only
   sources of `now`; no site reads `DateTime.now()` for the bound directly except through those
   seams (`_clock = clock ?? DateTime.now`).
5. The 2 s end-skew behaviour (D-15403/D-15405) is regression-pinned: the S-15405..S-15407 groups and
   the reconciliation fixture suite run green unchanged.
6. PROTOCOL.md and the state docs state the rule in one sentence each (docs delta below).

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC-1 A wrist end far in the phone's future is clamped to now + 5 min at all three application
  points → S-16401, S-16402, S-16404, S-16405, S-16406.
- AC-2 A wrist end inside the bound applies untouched → S-16403.
- AC-3 A past end applies untouched, at any distance behind the clock → S-16409.
- AC-4 A clamp never moves an end backward and never stores an end before its start → S-16407,
  S-16408.
- AC-5 The skew rules and the cross-stack parity are unchanged → S-16410.
- AC-6 The docs state the rule → Phase 3 items.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect of this change | Guarded by |
|---|---|---|---|
| `SessionCoreLifecycleMethods.catchUpEndedSession` (`lib/state/workout/session_core_lifecycle.dart:295`); facade `WorkoutState.catchUpEndedSession` (`workout_state.dart:233`) | Sole production caller: `watch_session_adoption_bridge.dart:898` (grep `catchUpEndedSession`); tests `health_platform_test.dart:814,830` | Unchanged code; the bridge now feeds it a bounded `atMs`. Direct test calls pass past instants — unaffected (no lower bound) | S-16401, S-16403 |
| `SessionCoreLifecycleMethods.endSession({writeToHealth, atMs})` (`session_core_lifecycle.dart:11`) | Callers: bridge `:919` (with `atMs`), phone's own Finish `workout_session_finish.dart:88` and `session_summary_screen.dart:492` (no `atMs`) (grep `endSession(`) | Unchanged code; the bridge feeds a bounded `atMs`; the phone's own Finish never clamps | S-16402 |
| `WatchSessionImporter._catchUpEnd` (`watch_session_importer.dart:672`), reported via `WatchSessionImport.endMovedFromMs` (:68) → `WatchSessionInbox` `_rewriteHealth` (`watch_session_inbox.dart:520`) | grep `endMovedFromMs` → inbox :520-523; Health re-write follows the moved end (plan 146c/154) | `latest` bounded before the move; a bounded value not later than the row writes nothing; the Health re-write span inherits the bound | S-16405, S-16406, S-16407 |
| `_End.parse` (`watch_session_importer.dart:2306`) and its two call sites (`apply` :167, `_mergeHeld` :321) | Consumers of `_End`: `_createSession` (:602, `endedAtMs`/`updatedAtMs`), `_attachSessionSummary`, `_applyFollowedEnd` (:251), `_Pass` (:222/:257/:323) (grep `_End.parse`) | `endedAtMs` bounded at parse with the start floor; every consumer sees the bounded value; `startedAtMs`, `loggedAtMs` and `_SetBlock` windows untouched (A-164-01) | S-16404, S-16408, S-16409 |
| `orderEnds` / `kEndSkewToleranceMs` (`lib/core/sync_protocol/end_skew.dart`), bridge `_routeLifecycleToHeld` abandoned branch (:900-905), twin `_incomingEndReplaces` (:739), reconciler `_incomingEndWins`, Swift `orderEnds` | Existing groups S-15405..S-15407 (`test/watch_session_adoption_bridge_test.dart`), `test/sync_protocol_fixtures_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`, Swift `WatchEndedIsFinalTests` | Untouched; regression-pinned | S-16409, S-16410 |
| Plan 160's active run (Iteration 1, uncommitted: `lib/watch/session/watch_session_engine.dart`, `test/watch_session_engine_test.dart`, `test/watch_session_import_test.dart`, `docs/watch_session_capture.md`) | `gateway.sh git-status` (2026-11-14) | This plan touches **none** of those files; the importer clamp tests go in a NEW file; Phase 3 does not touch `docs/watch_session_capture.md` | Notes |

## UI Standards Impact

None — no screen, widget or shared UI piece is touched (`docs/design_system.md` not read into this
plan; grep for the three touched symbols returns no `lib/features/` reader except the two Finish
calls with no `atMs`, listed above).

## Scenarios

Clock arithmetic: `T` is the phone's clock at decision time (injected through the bridge's `clock:`
or the importer's `clock:`). `kFutureEndClampMs = 300_000`.

### S-16401: the bridge clamps a completed end far in the future (ended held row)
- Fixture: the bridge test rig's adopted session `s-cap-1` held by the phone,
  `startedAtMs = T − 1_800_000`, `endedAtMs = T − 5_000` (the phone finished it); phone clock = T;
  active-energy service and `HealthSyncService` injected as the rig already does.
- Trigger: a wrist `session_lifecycle` frame `{state: completed, sessionId: s-cap-1,
  at: T + 86_400_000}` (a day ahead — a wrong watch clock).
- Flow: `_routeLifecycleToHeld` → clamp `at` to `T + 300_000` → `catchUpEndedSession(T + 300_000)`.
- Expected outcome: the held row's `endedAtMs = T + 300_000` (not `T + 86_400_000`); status stays
  `completed`; the active-energy settle re-runs; `HealthSyncService.rewriteWorkout` is called with
  the new row and `previousEndedAtMs = T − 5_000`. One debug report names the clamp.
- Edge case of: none.

### S-16402: the bridge clamps the end of an OPEN held row
- Fixture: `s-cap-1` held and active, `startedAtMs = T − 600_000`, no end; phone clock = T.
- Trigger: wrist `completed` with `at = T + 3_600_000` (an hour ahead).
- Flow: `_routeLifecycleToHeld` (not-ended switch) → clamp →
  `endSession(writeToHealth: false, atMs: T + 300_000)`.
- Expected outcome: `endedAtMs = T + 300_000` (D-153's `max(startedAtMs, …)` keeps it after the
  start); no Health write (`writeToHealth: false`). Edge case of: S-16401.

### S-16403: an end inside the bound applies untouched
- Fixture: `s-cap-1` held, `startedAtMs = T − 1_800_000`, `endedAtMs = T − 600_000`; phone clock = T.
- Trigger: wrist `completed` with `at = T + 120_000` (2 min ahead of the phone's clock, inside 5
  min, later than the held end).
- Flow: clamp is a no-op → `catchUpEndedSession(T + 120_000)`.
- Expected outcome: `endedAtMs = T + 120_000` exactly; no clamp report. Edge case of: S-16401.

### S-16404: the importer clamps a future wrist end at creation
- Fixture: one watch `session_end` inbox row for session `w-cap-1`: `startedAt = T − 600_000`,
  `endedAt = T + 86_400_000`, `status: completed`, `loggedAt = T + 86_400_000`; one watch `set` row
  `loggedAt = T + 400_000`; importer clock = T; nothing in history for `w-cap-1`.
- Trigger: `WatchSessionImporter.apply`.
- Expected outcome: the session is created with `endedAtMs = T + 300_000` and
  `updatedAtMs = T + 300_000`; the set and every effort row import normally (nothing refused, the
  frame's rows are marked applied — clamp-and-keep); `historyChanged` true.
- Edge case of: none.

### S-16405: the importer clamps the catch-up on an ended row
- Fixture: `w-cap-1` already in history with `endedAtMs = T − 1_800_000`; watch `session_end` row
  `endedAt = T + 86_400_000`; set rows all `loggedAt ≤ T + 400_000`; importer clock = T.
- Trigger: `apply` → `_Pass.run` → `_catchUpEnd`.
- Expected outcome: the end moves to `T + 300_000` (the bounded latest, not `T + 86_400_000`);
  `endMovedFromMs = T − 1_800_000`; the inbox calls `_rewriteHealth(previousEndedAtMs: T − 1_800_000)`.
- Edge case of: S-16404.

### S-16406: a future set stamp cannot stretch the end past the bound
- Fixture: `w-cap-1` in history with `endedAtMs = T − 1_800_000`; watch `session_end` row
  `endedAt = T − 1_800_000`; one live `set` row `loggedAt = T + 86_400_000`; importer clock = T.
- Trigger: `apply` → `_catchUpEnd` (the D-14604 latest-over-sets rule).
- Expected outcome: the end moves to `T + 300_000` (bounded), not `T + 86_400_000`;
  `endMovedFromMs = T − 1_800_000`. Edge case of: S-16405.

### S-16407: a clamp never drags an end backward
- Fixture: `w-cap-1` in history with `endedAtMs = T + 600_000` (the phone's own clock was behind
  when it stored this end); watch `session_end` row `endedAt = T + 86_400_000`; importer clock = T.
- Trigger: `apply` → `_catchUpEnd`.
- Expected outcome: the bounded latest (`T + 300_000`) is not later than the row's end, so nothing
  is written: `endedAtMs` stays `T + 600_000`, `endMovedFromMs` is null, no `_rewriteHealth`. The
  wrist's later claim loses to the phone's own stored end. Edge case of: S-16405.

### S-16408: the start floor — a future start yields zero length, never negative
- Fixture: watch `session_end` row for `w-cap-1`: `startedAt = T + 86_400_000`,
  `endedAt = T + 86_400_000 + 600_000` (a whole workout a day ahead); importer clock = T.
- Trigger: `apply` (creation path).
- Expected outcome: created with `endedAtMs = startedAt = T + 86_400_000` (D-16408 floor — a
  zero-length row, no negative duration). Edge case of: S-16404.

### S-16409: a past end is a legitimate late sync — and the skew rules stand
- Fixture (a): importer creation for `w-cap-1`: `startedAt = T − 90_000_000`,
  `endedAt = T − 86_400_000` (started ~25 h ago, finished a day ago, syncing now);
  importer clock = T. Expected: created with `endedAtMs = T − 86_400_000` unchanged; no clamp, no
  report.
- Fixture (b): `s-cap-1` held and finished at `endedAtMs = T − 600_000`; phone clock = T; wrist
  `abandoned` with `at = T + 30_000` (30 s ahead — inside the clamp bound, later than the held end).
  Expected: `endsBeforeHeldMsByMoreThanSkew` is false (it is later, not earlier), so the finish
  stands — exactly the pre-plan behaviour, re-pinned so the clamp cannot be read as ever enabling a
  deletion. Edge case of: S-16401 (b), none (a).

### S-16410: parity and skew regression — nothing outside the three sites moved
- Fixture: the existing shared reconciliation fixtures (`watch/sync_protocol/fixtures/reconciliation/`,
  20 files, unchanged), the replay corpus (`fixtures/replay/`, 16 sources, unchanged), the bridge
  skew groups S-15405..S-15407, the twin's S-15408 group, and the importer groups `S-14610 the
  imported end catches up` (`test/watch_session_import_test.dart`) and `S-14670` (`
  test/health_platform_test.dart`).
- Trigger: run the suite selections named in the phases' Done Criteria.
- Expected outcome: all green with no fixture or engine edit (D-16404, D-16405); the twin, the
  reconciler and the Swift engine keep converging on the same structure for every frame.
- Edge case of: none.

## Iteration 1

### Phase 1: the clamp primitive and the adoption bridge (@developer)
Independent of Phase 2 only through the primitive (Phase 2 imports it); nothing else blocks.

1. [ ] Add the bound to `lib/core/sync_protocol/end_skew.dart` — new top-level
       `const int kFutureEndClampMs = 300000;`, `const Duration kFutureEndClamp`, and
       `int clampFutureEndMs(int endMs, int nowMs) => math.min(endMs, nowMs + kFutureEndClampMs);`
       with a library-doc paragraph: different axis from `kEndSkewToleranceMs` (D-16402), no lower
       bound (D-16401a), clamp-and-keep (D-16401b) — `lib/core/sync_protocol/end_skew.dart` ·
       `kFutureEndClampMs`, `clampFutureEndMs`
2. [ ] Clamp in `lib/state/watch/watch_session_adoption_bridge.dart` `_routeLifecycleToHeld`
       (:883-923): after each `_instantMs(...)` (:897, :900, :916) compute
       `final boundedMs = clampFutureEndMs(atMs, _clock().millisecondsSinceEpoch);` and route
       `boundedMs` to `target.catchUpEndedSession` (:898) and to
       `target.endSession(writeToHealth: false, atMs:)` (:919) —
       `lib/state/watch/watch_session_adoption_bridge.dart` · `_routeLifecycleToHeld`
3. [ ] Report a clamped end through the bridge's debug precedent: new static
       `_reportClampedEnd(int claimedMs, int boundedMs)` mirroring `_reportSkipped` (:118, one
       `debugPrint`, called from `_routeLifecycleToHeld` only when `boundedMs != atMs`) —
       `lib/state/watch/watch_session_adoption_bridge.dart` · `_reportClampedEnd`
4. [ ] Add the group `S-164 end-time upper bound` to `test/watch_session_adoption_bridge_test.dart`
       (clock injected through the bridge's `clock:` seam): S-16401, S-16402, S-16403, S-16409(b);
       plus one assertion inside S-16402 that no clamp report fires for an in-bound end —
       `test/watch_session_adoption_bridge_test.dart` · `S-164 end-time upper bound`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (compare with
the plan's baseline count — the repo carries pre-existing info notices);
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart`
(group 4 red before item 2, green after — `gateway.sh prove-red HEAD test test/watch_session_adoption_bridge_test.dart` fails there);
the pre-existing skew groups S-15405..S-15407 in the same file stay green (S-16410's bridge half).
**Predicted Files**: `lib/core/sync_protocol/end_skew.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`,
`test/watch_session_adoption_bridge_test.dart`.
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: the importer's clamp (@developer)
BLOCKS on Phase 1 (imports `clampFutureEndMs`).

1. [ ] `_End.parse` takes the receiver's now: add `required int nowMs` to
       `static _End? parse(WatchInboxEntry row, {required int nowMs})` and build `endedAtMs` as
       `math.max(startedAtMs, math.min(endedAtMs, nowMs + kFutureEndClampMs))` (the D-16401 bound
       with the D-16408 start floor) — `lib/core/services/watch_session_importer.dart` ·
       `_End.parse`
2. [ ] Feed the clock at both call sites: `apply` (:167) and `_mergeHeld` (:321) pass
       `nowMs: _clock().toUtc().millisecondsSinceEpoch` (the importer's `_clock` field, :82) —
       `lib/core/services/watch_session_importer.dart` · `apply`, `_mergeHeld`
3. [ ] Bound the catch-up: `_Pass` (:464) gains `final int nowMs` (set by all three constructors at
       :222, :257, :323); `_catchUpEnd` (:672) computes
       `final bounded = clampFutureEndMs(latest, nowMs);` and (a) writes nothing when
       `bounded <= row` (never backward, D-16401c), (b) otherwise stores `bounded` in
       `ended_at_ms`/`updated_at_ms` and reports `endMovedFromMs = row` as today —
       `lib/core/services/watch_session_importer.dart` · `_Pass`, `_catchUpEnd`
4. [ ] New test file `test/watch_session_import_end_clamp_test.dart` (Mock-first, importer `clock:`
       injected): S-16404, S-16405, S-16406, S-16407, S-16408, S-16409(a). New file, not
       `test/watch_session_import_test.dart`, because plan 160's run is editing that file right now
       (see Notes) — `test/watch_session_import_end_clamp_test.dart` · all six scenarios
5. [ ] Regression, no edit: the groups `S-14610 the imported end catches up`
       (`test/watch_session_import_test.dart`) and `S-14670 the phone's own catch-up rewrites the
       workout it wrote` (`test/health_platform_test.dart`) run green — their fixtures use past
       instants, so the clamp is invisible to them (S-16410)

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_end_clamp_test.dart test/health_platform_test.dart`
(item 4 red before items 1-3, green after); do not re-run `test/watch_session_import_test.dart`'s
Hive group if its Mock group is red from the concurrent plan-160 edits — record and move on.
**Predicted Files**: `lib/core/services/watch_session_importer.dart`,
`test/watch_session_import_end_clamp_test.dart` (new).
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: docs delta and residue sweep (@developer)
BLOCKS on Phases 1-2 (documents shipped behaviour).

1. [ ] `docs/state_management/workout_state.md` — `catchUpEndedSession` row (:137): append one
       clause — the adoption bridge clamps the arriving end to the phone's clock + 5 min
       (`kFutureEndClampMs`, D-16401/D-16402) before this call; the facade itself stays unclamped
       and a past end is never clamped — `docs/state_management/workout_state.md` ·
       `catchUpEndedSession` row
2. [ ] `docs/watch_session_sync.md` — the invariant "A later wrist end moves the phone's end
       forward (D-14604)" (~:523): one sentence — both catch-up points (the bridge's lifecycle path
       and the importer's `_catchUpEnd`, whose `endMovedFromMs` drives the inbox's `_rewriteHealth`)
       bound the latest instant to the phone's clock plus 5 minutes; a clamp never moves an end
       backward — `docs/watch_session_sync.md` · the D-14604 invariant bullet
3. [ ] `watch/sync_protocol/PROTOCOL.md` — end rules in "Idempotency and reconciliation
       (normative)" (~:690): one sentence per D-16406, and one amendment-table row in the
       2026-11-13 row's format (:929-931 block), stating no wire, schema, validator,
       rejection-code or version change — `watch/sync_protocol/PROTOCOL.md` · end-rules paragraph,
       amendments table
4. [ ] Residue sweep, recorded in the evidence file: grep
       `catchUpEndedSession|_catchUpEnd|atMs: atMs|endsBeforeHeldMsByMoreThanSkew` over `lib/` and
       prove every later-end application site is either bounded (bridge `:898`/`:919` via
       `clampFutureEndMs`; importer `_catchUpEnd` via the bounded `latest`) or fed by the phone's
       own clock with no incoming claim (`endSession`'s `atMs ?? DateTime.now()`,
       `updateSessionEndTime`) — zero unbounded readers of a wrist-claimed end may remain —
       evidence file · residue sweep section

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (every
touched doc stays under the 64 KiB cap; these are sentence-level edits to existing rows/paragraphs,
no new sections — the 52 KiB split band is not approached);
`.github/copilot/scripts/macos/gateway.sh test` full suite once at the end of the plan (several
minutes — 900 s timeout; Mock-first habits apply).
**Predicted Files**: `docs/state_management/workout_state.md`, `docs/watch_session_sync.md`,
`watch/sync_protocol/PROTOCOL.md`, `<plan>.evidence.md`.
**Phase 3 verification notes (Conductor, date):** —

## Files Affected (whole feature)

- `lib/core/sync_protocol/end_skew.dart` — the bound (Phase 1)
- `lib/state/watch/watch_session_adoption_bridge.dart` — boundary clamp + report (Phase 1)
- `lib/core/services/watch_session_importer.dart` — parse + catch-up clamp (Phase 2)
- `test/watch_session_adoption_bridge_test.dart` — Phase 1 tests
- `test/watch_session_import_end_clamp_test.dart` — NEW (Phase 2)
- `docs/state_management/workout_state.md`, `docs/watch_session_sync.md`,
  `watch/sync_protocol/PROTOCOL.md` (Phase 3)
- Readers that only observe a touched surface (no edit expected): `lib/state/workout/session_core_lifecycle.dart`
  (`catchUpEndedSession`, `endSession` — unchanged), `lib/state/workout/workout_state.dart` (facade),
  `lib/state/watch/watch_session_inbox.dart` (`_rewriteHealth` consumer), `lib/state/watch/watch_sync_wiring.dart`
  (no signature change), `lib/features/session/workout_session_finish.dart`,
  `lib/features/session/session_summary_screen.dart`, `lib/core/sync_protocol/session_reconciler.dart`,
  `lib/watch/session/watch_session_engine.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
  (all three explicitly unchanged, D-16404).

## Notes

**Which sites can accept a future instant today (the brief's survey).**

| Site | File · symbol | Accepts a future instant? | This plan |
|---|---|---|---|
| Phone, ended held row | `watch_session_adoption_bridge.dart:898` → `catchUpEndedSession` (`session_core_lifecycle.dart:295`, `math.max(heldEndMs, atMs)`) | YES — unbounded | Bounded at the bridge (D-16403) |
| Phone, open held row | `watch_session_adoption_bridge.dart:919` → `endSession(writeToHealth: false, atMs:)` (`session_core_lifecycle.dart:39-47`, D-153 floors only at the start) | YES — unbounded above | Bounded at the bridge (D-16403) |
| Phone, importer catch-up | `watch_session_importer.dart:672` `_catchUpEnd` (latest of row end, wrist end, every live set's `loggedAtMs`) | YES — unbounded | Bounded at parse + in `_catchUpEnd` (D-16403) |
| Phone, importer creation | `_End.parse` (:2306) → `_createSession` (:602, `endedAtMs`/`updatedAtMs` verbatim) | YES — unbounded | Bounded at parse (D-16403) |
| Dart twin | `lib/watch/session/watch_session_engine.dart` `_incomingEndReplaces` (:739), snapshot path (:586) | Terminal-vs-terminal: NO (earlier-only replaces). Non-terminal row: YES (row `recordedAt`, captured session end) | Unchanged — contained by the importer clamp (D-16404) |
| Swift engine | `WatchSessionEngine.swift` `orderEnds` (:782), `applyLifecycleExclusive` (~:884), snapshot path (~:660), `captureSessionEnd` | Same as the twin | Unchanged (D-16404) |
| Reconciler (reference) | `lib/core/sync_protocol/session_reconciler.dart` `_applySnapshot`/`_applyLifecycle` → `_endedAt` | Internal `_endedAt` can be future, but `convergedState()` exposes no end instant — no observable output | Unchanged, pure by design (D-16404) |

**Phase dependency graph.** 1 → 2 → 3. No re-ordering is useful: Phase 2 needs Phase 1's primitive,
Phase 3 documents both. Predicted intermediate state after Phase 1: the live bridge path is bounded;
a cold import can still stretch an end until Phase 2 lands — do not ship Phase 1 alone.

**Coordination with plan 160** (`docs/plans/2026-11-14-160-watch-own-workout-reaches-phone-plan/`,
Iteration 1 active, uncommitted edits to the twin and `test/watch_session_import_test.dart`): this
plan shares no file with it; the twin's end-capture work (`_captureSessionEnd`, D-16002) is
untouched. If both plans are in flight, land them independently; the full-suite run at the end of
Phase 3 is the integration check.

**Health re-write interplay (plan 154/155).** The re-write follows the end by design:
`catchUpEndedSession` → `rewriteWorkout(previousEndedAtMs:)` (D-14634/D-14636), the importer's
`endMovedFromMs` → `WatchSessionInbox._rewriteHealth` (:520). Bounding the end bounds both re-write
spans for free; `rewriteWorkout` itself is untouched (finding 4's restore lives in plan 154).

**Skew interplay (D-15403/D-15405).** Untouched: `orderEnds` keeps comparing two stamps through the
2 s tolerance (different statuses) and exactly (same status); the clamp compares one stamp against
the receiver's clock at `nowMs + 300_000`, far above the tolerance, so a clamped value can never
flip a skew decision (S-16409b). The discarded alternative — clamping by refusing the frame — is
rejected in D-16401b (a refused end frame would strand its session's entries behind an unapplied
row and re-send forever).

## Progress

- [ ] Phase 1 — clamp primitive + adoption bridge (@developer)
- [ ] Phase 2 — importer clamp (@developer)
- [ ] Phase 3 — docs delta + residue sweep (@developer)

## Assumption Log

*(executors append: decision made, options considered, choice + why. Conductor marks RATIFIED or
REVERT.)*

- A-164-01 Scope of the bound: `endedAtMs` only. A future `startedAtMs` is not corrected (no safe
  repair exists; the D-16408 floor degrades it to a zero-length row), `loggedAtMs` and `_SetBlock`
  windows are untouched (a future set stamp is already bounded by the `_catchUpEnd` clamp). Options:
  correct the start too / bound every wrist stamp. Choice: end-only, the finding's actual damage
  surface.
- A-164-02 Tolerance 5 minutes (D-16402) — **owner to confirm**.
- A-164-03 Logging via the bridge's debug precedent, no new DiagnosticsLog plumbing (D-16407) —
  **owner to confirm**.
- A-164-04 Wrist-side future ends are contained via the importer clamp rather than clamped on the
  wrist (D-16404) — **owner to confirm**; a wrist-side clamp in the twin + Swift engine would also
  require reconciler/harness work to keep the cross-stack contract provable, which is a separate
  plan if wanted.
- A-164-05 `_End.parse` receives the apply-time clock (when the inbox drains), not the arrival
  clock: the receiver's clock at decision time is what the rule names, and apply time is when the
  decision is made. No veto expected.

## Open questions

*(none — the owner was unavailable; every defaulted choice is marked **owner to confirm** in the
Ledger and the Assumption Log above: D-16402 tolerance, D-16404 wrist containment, D-16407 logging.)*

## Feedback

[empty]
