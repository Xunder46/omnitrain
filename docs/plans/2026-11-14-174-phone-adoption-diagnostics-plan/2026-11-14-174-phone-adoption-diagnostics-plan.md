# Feature: 174 — the phone's diagnostics log records what it decided about a watch session

> Status: Iteration 1 active (owner unavailable; defaulted choices marked **owner to confirm**)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
> One-PR plan. Scope guard: `.github/copilot/pr-scope-budget.md` — one track (the phone app `lib/`), 4 phases.

## Overview

The owner's 2026-11-14 walk could only be explained by reading code, because the copyable
"OmniTrain phone diagnostics" text records *frames* but not *decisions*: `frame_received`
(`lib/core/platform/watch_transport.dart:459,514-525`, via `_noteReceived`) says which frame types
arrived and when, and nothing about what the phone then did with them. Three prior plans deferred
exactly this: plan 165's findings (Q5,
`docs/plans/2026-11-14-165-walk-duration-zero-investigation/2026-11-14-165-walk-duration-zero-investigation.findings.md:199-223`)
propose three one-line notes; plan 164 deferred the end-time-clamp note (D-16407, **owner to
confirm** there); plan 167 grep-proved `DiagnosticsLog` is wired into the transport only and
excluded the notes as follow-up (D-16708). The watch side already notes its session decisions
(`workout_begin`/`workout_adopted`/`workout_end`/`workout_saved`, plan 168 D-16804; see
`docs/state_management/watch_diagnostics.md`, "What is recorded").

This plan wires the existing `DiagnosticsLog` (`lib/core/services/diagnostics_log.dart`) into the
adoption bridge and the importer behind the established nullable-collaborator seam and adds six
short, fixed-vocabulary notes at the decision sites. No decision logic changes; a build without the
log behaves exactly as today (D-14302: "a collaborator holding null records nothing").

Ground truth for the seam, with citations:

- The log is built once in `lib/main.dart:372`, given the watch's received log at `:374`, noted at
  launch `:375`, given the lifecycle observer `:376`, and already passed into `createWatchSync`
  (`:400`, parameter at `lib/state/watch/watch_sync_wiring.dart:240`). Inside `createWatchSync` it
  reaches `createPlatformWatchTransport` only (`watch_sync_wiring.dart:253-256`). The adoption
  bridge is built at `:253-262` and the inbox at `:266-289` — neither receives it. The inbox builds
  the importer itself (`lib/state/watch/watch_session_inbox.dart:135-138`), so the log must ride the
  inbox's constructor to reach the importer.
- The transport holds the log as a nullable field and notes behind a null check
  (`watch_transport.dart:514-525`), never throwing: `DiagnosticsLog.note` swallows every failure
  (`diagnostics_log.dart:83-110`) and never changes control flow.
- Existing seams of the same shape in the bridge: `onFailure` / `onSkipped` / `onPlanStarted`
  (`watch_session_adoption_bridge.dart:130-142`), defaulted to null-safe debug reporters
  (`:114-126`).
- Volume: the log keeps the newest `capacity` (3000 default, `diagnostics_log.dart:41-43`) and
  rewrites the file down to capacity once the line count reaches `capacity + slack` (3300;
  `_compact`, `diagnostics_log.dart:213-232`); a failed rewrite or empty read backs the count off
  instead of hammering. Coalescing (`coalesce` key, 60 s window, `diagnostics_log.dart:47,86-99`)
  exists for chatty live frames (`energy_live`, `watch_transport.dart:498,505,523`) — the decision
  notes below are NOT chatty and must not use it; their volume is capped by deduping at the source
  (D-17403).
- The log is read back by `events()` and rendered by `shareText` /
  `shareTextWithWatch` (`diagnostics_log.dart:140-152,155-196`) — any new kind prints as
  `<time> <kind> s:<session> <detail>` with no per-kind code, so Settings' Diagnostics Copy row shows
  the new notes with no change there (`test/settings_diagnostics_test.dart`,
  `test/settings_diagnostics_watch_log_test.dart` pin that rendering).

## Resolved Decisions (Ledger)

- **D-17401 Seam: an optional `DiagnosticsLog? diagnostics` constructor parameter, not a callback.**
  `WatchSessionImporter` (`lib/core/services/watch_session_importer.dart:75-79`),
  `WatchSessionInbox` (constructor `lib/state/watch/watch_session_inbox.dart:107-142`, which
  forwards it to the importer it builds at `:135-138`), and `WatchSessionAdoptionBridge`
  (`lib/state/watch/watch_session_adoption_bridge.dart:129-142`) each gain a trailing optional
  `DiagnosticsLog? diagnostics` parameter; `createWatchSync` forwards its existing `diagnostics:`
  (`watch_sync_wiring.dart:240`) into `_WiringAdoptionBridge` (`:175-179`, add `super.diagnostics`)
  and `WatchSessionInbox` (`:266`). Production wiring is the only caller that passes it; every test
  graph and the default construction keep `null` = records nothing (the transport precedent:
  `watch_transport.dart:514-516`; D-14302). A rejected alternative was an `onNote` callback styled
  after `onSkipped`/`onFailure` — that would introduce a second seam style for the same job the
  transport already settles by holding the log object itself, and every call site would grow a
  lambda instead of an optional field. **Owner to confirm.**
- **D-17402 Note vocabulary: six kinds, fixed short details, no personal data.** The wrist session
  id always rides the log's `session:` field (the same string `frame_received` already carries,
  `watch_transport.dart:518-522`) — session ids are already in the copyable log. Instants are
  ISO-8601 UTC (the bridge's `_isoUtc` shape, `watch_session_adoption_bridge.dart:1550-1551`). One
  line per event, detail cut to 120 chars by the log itself (`diagnostics_log.dart:47,195-198`):
  - `adoption_decision` — detail `adopted status=active start=<iso>` (a fresh adoption; the status
    is `active` by `consider`'s gate, `watch_session_adoption_bridge.dart:731-734`, and the start is
    the arrival instant `_adopt` stamps, `:1131-1133`); `skipped reason=held_session held=<heldId>`
    (D-10 refusal, `:773`); `skipped reason=already_history` (G1, `:745`). `alreadyHeld`, `unbound`
    and `notRunning` are **not** recorded: they are the mirror's steady state, repeat on every
    frame, and decide nothing user-visible. This refines plan 165 Q5's sketch, which put the session
    id inside the detail: here the id rides `session:`, matching every existing line. **Owner to
    confirm; derived from an unavailable owner's prior answer — vetoable.**
  - `session_row_created` — detail `path=<snapshot|started|import> start=<iso> end=<iso|none>`:
    `path=snapshot` in `_adopt` (`:1124-1131`), `path=started` in `_startSessionRow`
    (`:1055-1063`, the start is the report's own `at`, D-16703), `path=import` in the importer's
    history-row creation `_createSession` (`watch_session_importer.dart:661`; the end instant when
    the end row carried one).
  - `session_start_corrected` — detail `from=<iso> to=<iso> path=<merge|import>`: where
    `_carryWristStart` moves a row's start down (`watch_session_importer.dart:454-473`,
    D-16701/D-16705), noted only when it actually rewrote the row (non-null return and a changed
    start): `path=merge` at the held-session call site (`:350-353`), `path=import` at the
    existing-row pass (`:579-584`).
  - `end_clamped` — detail `from=<iso> to=<iso> who=<lifecycle|import>`: the plan-164 future-end
    bound. `who=lifecycle` in the bridge's `_boundedEnd` (`:1531-1537`); `who=import` where
    `_End.parse` clamps to `nowMs + kFutureEndClampMs` (`watch_session_importer.dart:2384-2390`) and
    where `_catchUpEnd` bounds a catch-up end (`:731-747`). This supersedes plan 164's D-16407
    choice ("no new diagnostics plumbing; the importer clamps silently") — the clamp now appears in
    the copyable log; the existing `debugPrint` (`_reportClampedEnd`, `:1542-1548`) stays.
    **Owner to confirm** (D-16407 was explicitly deferred for owner confirmation).
  - `end_applied` — detail `who=<catchup|end_session|import> instant=<iso|none>
    status=<completed|the end row's status>`: the phone applied a session end. `who=catchup`
    (`catchUpEndedSession`, `watch_session_adoption_bridge.dart:895`), `who=end_session`
    (`endSession(writeToHealth: false, ...)`, `:924-928`; `instant=none` when the frame named no
    instant and the phone's clock stays), `who=import` at the importer's three end-writing sites
    (`_applyFollowedEnd` `:258`, `_catchUpEnd` `:731`, and the end written with the history row in
    `_createSession` `:661` — the last two share the kind; a site notes only when it actually wrote
    or moved an end).
  - `discard_applied` — detail `who=<held|finished>`: `who=held` discards the live held session
    (`watch_session_adoption_bridge.dart:929`), `who=finished` reverts a finished row under the
    earlier-end rule (`:908`, D-14630).
- **D-17403 Volume rule: dedupe at the source; never `coalesce`.** `adoption_decision` is the one
  kind a repeated frame can fire many times, so the bridge dedupes it per `(session, detail)` — a
  small memory map beside the existing `_skippedHeldSessionId`/`_skippedOfferedSessionId` pair
  (`watch_session_adoption_bridge.dart:704-716`, same precedent, same per-process lifetime). Every
  other kind fires at most once per decision in its flow by construction (a row is created once per
  session; a start correction rewrites once per end row; a clamp fires once per bounded end; an end
  or discard applies once per lifecycle state change). The 3300-line compaction
  (`diagnostics_log.dart:213-232`) is the backstop, not the guarantee: a burst like the owner saw
  (repeated snapshots within seconds) must not evict the useful lines, which dedupe achieves —
  S-17412 pins it. `coalesce` is reserved for chatty live frames and would print a misleading
  `x<n>` on a decision. If a future site proves repetitive, it dedupes per `(session, detail)` the
  same way rather than coalescing. **Owner to confirm.**
- **D-17404 Privacy: fixed outcome words, instants, ids — nothing a user typed.** A note detail may
  contain: the fixed words above, wire status strings (`active`, `completed`, …), ISO-8601 instants
  (wrist stamps or the phone's clock), and at most two session ids (`session:` plus `held=`). It
  must never contain an exercise name, a weight, reps, a rating, a note, heart-rate or energy
  values, or an error message (messages can quote offending values — the same rule the watch log
  applies, `docs/state_management/watch_diagnostics.md` "Privacy", plan 142 D-14211). All reason
  strings are fixed literals from D-17402, never interpolated error text. **Owner to confirm.**
- **D-17405 Notes are observation only and null-safe.** Nothing reads a note to decide anything
  (D-14302, `diagnostics_log.dart:63-66`); a `null` log must not change one branch of any decision —
  every note call is a nullable-field `note(...)` whose failure is swallowed inside the log. No
  persisted field, no wire change, no schema change; `scripts/sqlite_schema.sql` is untouched
  (exercised by `test/db_seed_test.dart`, unaffected).
- **D-17406 Docs: the note-kind table lives in `docs/state_management/watch_diagnostics.md`.** The
  "The phone." paragraph's file ends with "Not yet recorded: the phone's own validation refusals."
  — a short "The phone's decisions." block follows it (the six kinds, the dedupe rule, the privacy
  sentence, and the verified-by test names), and the "Verified by" list gains the new tests. The
  doc is < 20 KiB (read whole, untruncated), far below the 52 KB split line.

## Feature Invariants

Only the invariants that bite here; project-wide rules stay in docs/global_conventions.md.

- **A null log changes nothing.** A bridge/importer/inbox built without `diagnostics` produces byte
  for byte the same decisions and rows as today (D-17401, D-17405). Guarded by S-17411 (existing
  suites pass unchanged).
- **Notes never block, never throw, never decide.** `note()` swallows its own failures
  (`diagnostics_log.dart:85,109-110`); callers do not await it and do not branch on it.
- **No personal data in a note** (D-17404). Guarded by every scenario's expected detail being a
  fixed literal plus ids and instants.
- **The ring bound and coalescing stay as they are** — no new machinery inside `DiagnosticsLog`
  (D-17403). `lib/core/services/diagnostics_log.dart` is not edited by this plan.

## Requirements

- R-1 The same `DiagnosticsLog` instance main.dart already builds reaches the adoption bridge and
  the importer through `createWatchSync`'s existing `diagnostics:` parameter (D-17401).
- R-2 The six decision notes of D-17402 are recorded at exactly the sites D-17402 names, one line
  each, with the pinned detail format.
- R-3 Repeated frames cannot flood the log: `adoption_decision` dedupes per `(session, detail)`
  (D-17403).
- R-4 A build without the log is behaviourally identical to today (S-17411).
- R-5 `docs/state_management/watch_diagnostics.md` documents the six kinds and names the tests that
  pin each (D-17406).

## Acceptance Criteria

Each maps to ≥ 1 scenario:

- AC-1 A fresh adoption produces `adoption_decision adopted` and `session_row_created
  path=snapshot` for the adopted session (S-17401).
- AC-2 A D-10 refusal and a G1 already-ended snapshot each produce one `skipped` line, deduped
  across repeats (S-17402, S-17403).
- AC-3 Every row-creation path (snapshot / started / import) notes `session_row_created` with its
  path and the start/end the row carries (S-17401, S-17404, S-17405).
- AC-4 A start correction on the merge and the import path notes `session_start_corrected` with
  from/to (S-17406).
- AC-5 A clamped end — lifecycle or import — notes `end_clamped` with from/to, and the stored end is
  still the bounded instant (S-17407, S-17408).
- AC-6 An applied end and an applied discard note `end_applied` / `discard_applied` with who,
  instant and status (S-17409, S-17410).
- AC-7 A 300-repeat burst of the same decision leaves one line per `(session, detail)` and every
  other note intact (S-17412).
- AC-8 With no log attached, all existing suites pass unchanged (S-17411).
- AC-9 The wiring source test proves the log reaches bridge and inbox (Phase 1 structural guard).
- AC-10 The doc names each kind and its test (S-17413).

## Existing-Functionality Impact

- `DiagnosticsLog.note` / `shareText` (`lib/core/services/diagnostics_log.dart`) → read by Settings'
  Diagnostics Copy row (`test/settings_diagnostics_test.dart`,
  `test/settings_diagnostics_watch_log_test.dart`) and by the merged phone+watch text
  (`test/diagnostics_merged_text_test.dart`). Effect: new kinds appear in the copyable text through
  the existing generic renderer — no code change; the renderer prints any kind. Guarded by
  S-17411 (those suites run in the full suite) and the scenario tests' expected line shapes.
- `WatchSessionAdoptionBridge.consider` / `_adopt` / `_startSessionRow` / `_routeLifecycleToHeld` /
  `_boundedEnd` → driven by the router (`lib/state/watch/watch_incoming_router.dart`) and pinned by
  `test/watch_session_adoption_bridge_test.dart` (plan-164 clamp tests there) and plan-167's
  D-8977 groups in `test/watch_session_import_test.dart:3290+`. Effect: decisions unchanged, notes
  added after the decision is made. Guarded by S-17401..S-17404, S-17407, S-17409, S-17410, S-17412.
- `WatchSessionImporter.apply` / `_Pass` → driven by the inbox's settle chain
  (`lib/state/watch/watch_session_inbox.dart:432-530`), pinned by `test/watch_session_import_test.dart`
  and plan-164's importer clamp tests. Effect: passes unchanged, notes added at write sites.
  Guarded by S-17405, S-17406, S-17408.
- `createWatchSync` / `_WiringAdoptionBridge` (`lib/state/watch/watch_sync_wiring.dart`) → the
  transport's `onIncoming` closure (`:298+`) and `WatchSyncGraph` consumers. Effect: two more
  constructor arguments receive an already-present value. Guarded by the extended
  `test/diagnostics_wiring_source_test.dart` and the full suite.
- `WatchSessionInbox` → built in `createWatchSync` only (grep `WatchSessionInbox(` over `lib/` →
  `watch_sync_wiring.dart:266`). Effect: one optional parameter forwarded to the importer. Guarded
  by S-17411 and the source test.
- main.dart's construction (`:372-376,400`) → unchanged; it already passes `diagnostics: diagnostics`
  into `createWatchSync`.

## UI Standards Impact

None — no screen, widget or shared UI piece is touched. Settings' Diagnostics row renders the new
kinds through its existing generic line renderer (`diagnostics_log.dart:140-152`); the row's label
and Copy flow are untouched, so `docs/design_system.md` needs nothing.

## Scenarios

Fixtures: the log under test is `DiagnosticsLog(storage: InMemoryDiagnosticsStorage(), clock: pinned)`
— `InMemoryDiagnosticsStorage` (`lib/core/services/diagnostics_storage.dart:30`) is what
`test/diagnostics_log_test.dart` already builds. Bridge tests extend the rig in
`test/watch_session_adoption_bridge_test.dart`; importer tests extend the fixture groups in
`test/watch_session_import_test.dart`. ISO instants below are read from the pinned clock. `<iso>`
denotes the ISO-8601 UTC form of the instant named.

### S-17401: a fresh adoption is decided and rows are written, both noted
- Fixture: bound `WorkoutState` with no current session; empty repository; wrist converged snapshot
  `{sessionId: 'w-1', status: active, exercises: [one set slot]}`; diagnostics attached.
- Trigger: `consider(snapshot)`.
- Flow: gates pass → `_adopt` writes row + segment → state loads → `adopted`.
- Expected: two new events for `w-1`: `adoption_decision` detail
  `adopted status=active start=<iso of _adopt's atMs>` and `session_row_created` detail
  `path=snapshot start=<same iso> end=none`; the row's `started_at_ms` equals the noted instant.
- Edge case of: none.

### S-17402: a D-10 refusal is noted once per (held, offered) pair
- Fixture: `WorkoutState` holding active phone session `p-1` (one effort); wrist snapshot
  `{sessionId: 'w-1', status: active}`; diagnostics attached.
- Trigger: `consider(snapshot)`, then 50 further `consider` calls with the same snapshot.
- Flow: refusedConflict (D-10) at `watch_session_adoption_bridge.dart:773`; dedupe map holds.
- Expected: exactly one `adoption_decision` for `w-1`, detail `skipped reason=held_session
  held=p-1`; no row written; no second line after the repeats.
- Edge case of: none.

### S-17403: an already-ended session's snapshot is refused once
- Fixture: repository holds row `w-1` with `endedAtMs != null` and no held session; snapshot
  `{sessionId: 'w-1', status: active}` repeated 10×; diagnostics attached.
- Trigger: `consider(snapshot)` ×10.
- Flow: G1 return at `:745`.
- Expected: one `adoption_decision`, detail `skipped reason=already_history`; nothing loaded back.
- Edge case of: none.

### S-17404: a started report's row is noted with the report's own start
- Fixture: bound `WorkoutState`, no held session; a `session_started` report for `w-2` whose
  payload `at` reads as `T_wrist`; diagnostics attached.
- Trigger: the router path that opens the row (`onSessionStarted` → `_startSessionRow`).
- Flow: `_startSessionRow` (`:1055-1063`) stamps `startedAtMs = T_wrist` (D-16703).
- Expected: `session_row_created` detail `path=started start=<iso of T_wrist> end=none`.
- Edge case of: none.

### S-17405: an imported history row is noted with both stamps
- Fixture: staged inbox rows for `w-3`: one set entry row and a `session_end` row (completed,
  `startedAt`/`endedAt` both in the past, window valid); diagnostics attached.
- Trigger: `apply('w-3')`.
- Flow: end parses, pass writes the history row via `_createSession` (`:661`).
- Expected: `session_row_created` detail `path=import start=<iso of startedAt> end=<iso of
  endedAt>`.
- Edge case of: none.

### S-17406: a start correction is noted on both paths
- Fixture A (merge): the phone holds an adopted session whose row has `started_at_ms ==
  ended_at_ms` (a D-153 floor); a `!followed` end row whose start is earlier arrives and merges
  (`phoneOwnsSession: true`). Fixture B (import): the same row-shape but the phone no longer holds
  the session; the end row applies through the ordinary import (D-16705). Diagnostics attached.
- Trigger: `apply(...)` per fixture.
- Flow: `_carryWristStart` (`:454-473`) rewrites the start at the `:350-353` / `:579-584` call
  sites.
- Expected: one `session_start_corrected` per fixture, detail `from=<iso of the old start> to=<iso
  of the wrist's start> path=merge` (A) / `path=import` (B); the row's start is the wrist's.
- Edge case of: none.

### S-17407: the bridge clamps a future end and notes it
- Fixture: `WorkoutState` holding an open session; a `completed` lifecycle frame whose `at` is
  now + 6 h; diagnostics attached; clock pinned.
- Trigger: `_routeLifecycleToHeld` → `endSession(atMs: _boundedEnd(atMs))` (`:924-928`).
- Flow: `_boundedEnd` (`:1531-1537`) clamps to now + 5 min (D-16402) and keeps the debugPrint.
- Expected: `end_clamped` detail `from=<iso of +6 h> to=<iso of +5 min> who=lifecycle`; `end_applied`
  detail `who=end_session instant=<iso of +5 min> status=completed`; the stored end is the bounded
  instant.
- Edge case of: none.

### S-17408: the importer clamps a future end and notes it
- Fixture: staged rows for `w-4`: one set entry row and a completed end row whose `endedAt` is
  now + 6 h; clock pinned; diagnostics attached.
- Trigger: `apply('w-4')`.
- Flow: `_End.parse` clamps to `nowMs + kFutureEndClampMs` (`:2384-2390`).
- Expected: `end_clamped` detail `from=<iso of +6 h> to=<iso of +5 min> who=import`; the history
  row's end is the bounded instant.
- Edge case of: none.

### S-17409: an applied end is noted with who, instant and status
- Fixture: `WorkoutState` holding an open session; a `completed` frame with a sane past `at` T
  (same harness as S-17407 minus the clamp); second variant: a finished row + a later `completed`
  frame (the catch-up branch, `:895`).
- Trigger: the lifecycle frame.
- Flow: `endSession` / `catchUpEndedSession`.
- Expected: `end_applied` detail `who=end_session instant=<iso of T> status=completed` (first
  variant); `who=catchup instant=<iso> status=completed` (second). A frame with no readable `at`
  notes `instant=none` and keeps the phone's clock.
- Edge case of: S-17407 (the clamped variant notes both kinds).

### S-17410: an applied discard is noted with who
- Fixture: `WorkoutState` holding an open session; an `abandoned` frame (variant 1); a finished row
  plus a wrist discard stamped earlier by more than the skew tolerance (variant 2, `:908`).
- Trigger: the lifecycle frame.
- Expected: `discard_applied` detail `who=held` (variant 1), `who=finished` (variant 2); the session
  state is discarded exactly as today.
- Edge case of: none.

### S-17411: a build without the log is unchanged
- Fixture: the existing bridge and importer rigs with no `diagnostics` argument (every test in
  `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`,
  `test/settings_diagnostics_test.dart`, `test/diagnostics_log_test.dart`).
- Trigger: the whole focused set runs.
- Expected: all pass unchanged; no new kinds anywhere; no crash. (No dedicated new test — the
  suites are the check; the reviewer re-runs them.)
- Edge case of: none.

### S-17412: a decision burst does not evict the useful lines
- Fixture: S-17401's adoption, then 300 repeated `consider` calls each triggering one of the
  deduped outcomes (S-17402's, S-17403's), then the S-17404 start report; diagnostics attached.
- Trigger: the burst, then `events()`.
- Flow: dedupe holds; compaction never reached (well under 3300 lines).
- Expected: `adoption_decision` appears once per distinct (session, detail); every kind's line from
  S-17401 and S-17404 is still present and in order.
- Edge case of: S-17401, S-17402, S-17403.

### S-17413: the doc names the kinds and their tests
- Fixture: none (doc check).
- Trigger: reading `docs/state_management/watch_diagnostics.md` after Phase 4.
- Expected: a "The phone's decisions." block lists the six kinds, the dedupe rule, the privacy
  sentence and the verified-by test names from Phases 2–3; no other doc sentence is made false.
- Edge case of: none.

## Iteration 1

### Phase 1: the seam (@developer)
1. [ ] Add a trailing optional `DiagnosticsLog? diagnostics` parameter and field to
  `WatchSessionImporter` — `lib/core/services/watch_session_importer.dart` · `WatchSessionImporter`
  constructor `:75-79`
2. [ ] Add the same optional parameter to `WatchSessionInbox` and forward it to the importer it
  builds — `lib/state/watch/watch_session_inbox.dart` · `WatchSessionInbox` constructor `:107-142`
  (importer build `:135-138`)
3. [ ] Add the same optional parameter and field to `WatchSessionAdoptionBridge` —
  `lib/state/watch/watch_session_adoption_bridge.dart` · `WatchSessionAdoptionBridge` constructor
  `:129-142`
4. [ ] Forward the log through the wiring subclass — `lib/state/watch/watch_sync_wiring.dart` ·
  `_WiringAdoptionBridge` constructor `:175-179` (add `super.diagnostics`)
5. [ ] Pass `diagnostics: diagnostics` into `_WiringAdoptionBridge` (`:253`) and `WatchSessionInbox`
  (`:266`) from `createWatchSync`'s existing parameter (`:240`) —
  `lib/state/watch/watch_sync_wiring.dart` · `createWatchSync`
6. [ ] Structural guard: extend the wiring source test — `test/diagnostics_wiring_source_test.dart` ·
  new test `the wiring passes diagnostics to the adoption bridge and the inbox` (same
  read-and-contains style as the existing S-14316 tests)
7. [ ] Run the focused set and paste counts into the evidence file
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (compare the
issue count with the repo's pre-existing baseline — analyze exits non-zero on old notices);
`.github/copilot/scripts/macos/gateway.sh test test/diagnostics_wiring_source_test.dart
test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart
test/diagnostics_log_test.dart`; existing suites green unchanged (S-17411 first evidence).
**Predicted Files**: `lib/core/services/watch_session_importer.dart`,
`lib/state/watch/watch_session_inbox.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`,
`lib/state/watch/watch_sync_wiring.dart`, `test/diagnostics_wiring_source_test.dart`,
`docs/plans/2026-11-14-174-phone-adoption-diagnostics-plan/2026-11-14-174-phone-adoption-diagnostics-plan.evidence.md`

### Phase 2: the bridge's notes (@developer)
1. [ ] Red tests first — a diagnostics group in the bridge rig: S-17401, S-17402 (with the 50×
  repeat), S-17403, S-17412 — `test/watch_session_adoption_bridge_test.dart` · new group
  `adoption diagnostics notes` (DiagnosticsLog over `InMemoryDiagnosticsStorage`, pinned clock)
2. [ ] Implement `adoption_decision` in `consider` — at the `adopted` return (`:835`), the
  `alreadyEnded` return (`:745`) and the refusal (`:773`), with the per-`(session, detail)` dedupe
  map beside `_reportSkipOnce` (`:704-716`) — `lib/state/watch/watch_session_adoption_bridge.dart` ·
  `consider`, new `_noteAdoption`
3. [ ] Green the S-17401/02/03/12 group; paste red→green into evidence
4. [ ] Red tests: S-17404 (started path) and the `session_row_created` half of S-17401 —
  `test/watch_session_adoption_bridge_test.dart` · same group
5. [ ] Implement `session_row_created` in `_adopt` (`:1124-1131`) and `_startSessionRow`
  (`:1055-1063`) — `lib/state/watch/watch_session_adoption_bridge.dart` · `_adopt`, `_startSessionRow`
6. [ ] Red tests: S-17407, S-17409, S-17410 — `test/watch_session_adoption_bridge_test.dart` · same
  group (clamp fixture: end claimed now + 6 h against a pinned clock)
7. [ ] Implement `end_clamped` in `_boundedEnd` (`:1531-1537`, keep `_reportClampedEnd`),
  `end_applied` in `_routeLifecycleToHeld` (catch-up `:895`, `endSession` `:924-928`), and
  `discard_applied` (`:908`, `:929`) — `lib/state/watch/watch_session_adoption_bridge.dart` ·
  `_boundedEnd`, `_routeLifecycleToHeld`, new `_noteEnd`, `_noteDiscard`
8. [ ] Green the full bridge group; run the bridge suite; paste counts
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test
test/watch_session_adoption_bridge_test.dart` green; the plan-164 clamp tests in that file still
green; `.github/copilot/scripts/macos/gateway.sh lint` at baseline.
**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`,
`test/watch_session_adoption_bridge_test.dart`, the evidence file

### Phase 3: the importer's notes (@developer)
1. [ ] Red tests first — a diagnostics group in the importer suites: S-17405, S-17406 (fixtures A
  and B), S-17408, and the `who=import` end-applied half of S-17409 —
  `test/watch_session_import_test.dart` · new group `import diagnostics notes`
2. [ ] Implement `session_row_created` (`path=import`) and the history-row end half of
  `end_applied` in `_createSession` — `lib/core/services/watch_session_importer.dart` ·
  `_createSession` `:661`
3. [ ] Implement `session_start_corrected` at the two `_carryWristStart` call sites, noting only a
  rewrite that moved the start — `lib/core/services/watch_session_importer.dart` · `_mergeHeld`
  `:350-353`, `_Pass.run` `:579-584` (mechanic: hand the log to `_Pass` beside `nowMs`)
4. [ ] Implement `end_clamped` (`who=import`): `_End.parse` (`:2384-2390`) reports its clamp
  (mechanic: a `clampedFromMs` on `_End`), noted by the pass owner; `_catchUpEnd`'s bound
  (`:745-747`) noted the same way — `lib/core/services/watch_session_importer.dart` · `_End.parse`,
  `_catchUpEnd`
5. [ ] Implement `end_applied` (`who=import`) in `_applyFollowedEnd` and `_catchUpEnd`, noting only
  a written or moved end — `lib/core/services/watch_session_importer.dart` · `_applyFollowedEnd`
  `:258`, `_catchUpEnd` `:731`
6. [ ] Green the group; run the importer suite; paste counts into evidence
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test
test/watch_session_import_test.dart` green (plan-164 and plan-167 groups included);
`.github/copilot/scripts/macos/gateway.sh lint` at baseline.
**Predicted Files**: `lib/core/services/watch_session_importer.dart`,
`test/watch_session_import_test.dart`, the evidence file

### Phase 4: docs and the full suite (@developer)
1. [ ] Add "The phone's decisions." to `docs/state_management/watch_diagnostics.md` after the
  "The phone." paragraph: the six kinds with one-line meanings, the dedupe rule, the privacy
  sentence, and the verified-by test names — and add those tests to the doc's "Verified by" list
  (D-17406, S-17413)
2. [ ] Verify-no-change on the neighbouring docs: grep `docs/watch_session_sync.md`,
  `docs/watch_session_capture.md` and `docs/state_management/workout_state.md` for a sentence the
  change makes false (none expected — decisions unchanged)
3. [ ] Residue sweep: grep the six kind strings (`adoption_decision`, `session_row_created`,
  `session_start_corrected`, `end_clamped`, `end_applied`, `discard_applied`) over `lib/` — every
  hit is at a site D-17402 names and nowhere else
4. [ ] Run the full suite once with the 900 s timeout (`gateway.sh test` with no file list) and
  `gateway.sh lint`; paste both counts into the evidence file
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test` (no file list, 900 s) green;
`.github/copilot/scripts/macos/gateway.sh lint` at the recorded baseline; the sweep grep proves
the site list.
**Predicted Files**: `docs/state_management/watch_diagnostics.md`, the evidence file

## Files Affected (whole feature)

- `lib/core/services/watch_session_importer.dart` — parameter + notes (Phases 1, 3)
- `lib/state/watch/watch_session_inbox.dart` — parameter forwarding (Phase 1)
- `lib/state/watch/watch_session_adoption_bridge.dart` — parameter + notes (Phases 1, 2)
- `lib/state/watch/watch_sync_wiring.dart` — forwarding (Phase 1)
- `test/diagnostics_wiring_source_test.dart` — structural guard (Phase 1)
- `test/watch_session_adoption_bridge_test.dart` — S-17401..S-17404, S-17407, S-17409, S-17410,
  S-17412 (Phase 2)
- `test/watch_session_import_test.dart` — S-17405, S-17406, S-17408 (Phase 3)
- `docs/state_management/watch_diagnostics.md` — the kinds table (Phase 4)
- NOT touched: `lib/core/services/diagnostics_log.dart` (no new machinery, D-17403),
  `lib/core/platform/watch_transport.dart`, `lib/main.dart`, any schema or wire file, the watch
  package, Settings code.

## Notes

- Phase graph: Phase 1 → {2, 3} (both need the seam) → 4. Phases 2 and 3 are independent and may
  run in either order; running 2 first gives the adoption decision — the walk's actual question —
  at no cost.
- Intermediate state after Phase 1 only: the log is threaded but silent; nothing user-visible.
- Legacy handling: sessions already in history get no retroactive notes (the log is append-only
  from here); rows already stored with a zero span keep it (plan 167 D-16706 — no repair, out of
  scope).
- The importer's `end_applied who=import` covers three sites (followed end, catch-up, row
  creation); if a pass applies more than one of these for one end row, each site notes its own
  write — that is at most a handful of lines per session, well inside the ring.
- `_carryWristStart` is static; the notes live at its call sites (both hold the importer or pass
  instance that carries the log), keeping the static pure.

## Progress

- [x] Phase 1: the seam (@developer) — optional `DiagnosticsLog?` threaded through importer, inbox, bridge (`super.diagnostics`), `createWatchSync`; structural guard green, proven RED at HEAD.
- [x] Phase 2: the bridge's notes (@developer) — 11 tests (S-17401..S-17404, S-17407, S-17409/09b/09c, S-17410/10b, S-17412) green; three mutations proved them; group +11.
- [x] Phase 3: the importer's notes (@developer) — 6 tests (S-17405, S-17406 A/B, S-17408/08b, S-17409) written red (`+0 -6`) then green; file `+91`, three mutations proved them.
- [x] Phase 4: docs and the full suite (@developer) — "The phone's decisions." block + verified-by names in `watch_diagnostics.md`; sweep 14 hits at the D-17402 sites only; full suite `+7653 ~4`, lint 181 (baseline).

## Assumption Log

*(empty at handoff — the owner was unavailable; every defaulted choice is marked **owner to
confirm** in the Ledger: D-17401 seam, D-17402 vocabulary, D-17403 dedupe, D-17404 privacy,
D-17405 supersedes D-16407. Executors append here (≤3 lines each); the reviewer adjudicates.)*

- **`_catchUpEnd` reads `status=none` when no `_End` is in scope.** Options: thread the `_End` through, or note
  `none`. Chose `none` (the importer's catch-up has no end to name); the fixture path always has one, so tests read
  `completed`. Reviewer may prefer threading.
- **Both new test groups were proved by mutation, not `prove-red HEAD`.** The tests name a `diagnostics:` parameter
  that does not exist at HEAD, so they cannot compile there; original lines recorded in the evidence file instead.
- **`_applyFollowedEnd` notes nothing itself.** It builds a `_Pass`, so the row and end notes come from
  `_createSession`/`_catchUpEnd` exactly once; noting in both would double-count the end.
- **Instants are `.000Z` UTC, second precision at most.** `DateTime.toIso8601String()` on UTC millis; chosen for
  exactness over brevity, so the doc shows `<UTC>` rather than a format string.

## Feedback

[empty]
