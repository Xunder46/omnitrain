# Feature: plan 167 — a wrist-only walk shows its real start and duration on the phone

> Status: Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
> Owner rules: docs/plans/2026-11-14-146-watch-twin-pipeline-plan/2026-11-14-146-watch-twin-pipeline-plan.md (O-1..O-9)
> Owner unavailable: every defaulted decision is marked **owner to confirm** (Assumption Log).

## Overview

A wrist-only workout the phone adopts from a stale ACTIVE snapshot writes its row with the
**adoption instant** as the start, because `_adopt` (`lib/state/watch/watch_session_adoption_bridge.dart:1116`)
stamps `startedAtMs: atMs` and the snapshot carries no start. When the wrist's terminal lifecycle
then ends the row at the wrist's own end instant — **earlier** than the adoption instant —
`endSession`'s ordered-window floor (D-153, `lib/state/workout/session_core_lifecycle.dart:48`,
`math.max(startedAtMs, now)`) clamps the end UP to the start: a zero-length span. The owner saw
Duration 0s and a 6:06 PM header for a 40 m 12 s walk.

The wrist's own start reaches the phone exactly once: in its `session_end` (`startedAt`, required
by the schema, emitted since plan 160). So the fix is a **start correction at the point that end
meets a row the phone holds** — one rule in `WatchSessionImporter` applied at two call sites — plus
stamping the report-opened row with the `session_started` report's `at`, which the schema already
requires. The summary builder is untouched (it reads the row's span, which becomes correct); rows
already stored keep their zero span (no migration — the brief forbids one).

Investigation: docs/plans/2026-11-14-165-walk-duration-zero-investigation/2026-11-14-165-walk-duration-zero-investigation.findings.md
(verdicts V-1..V-6, Q1..Q5, prove-red at HEAD). Device log:
docs/plans/2026-11-14-165-walk-duration-zero-investigation/2026-11-14-walk-device-log-excerpt.txt.

## Resolved Decisions (Ledger)

The O-1..O-9 owner rules (plan 146) and the clock/Ledger decisions of plans 154, 160, 161 and 164
stay binding exactly as written. Nothing below supersedes any of them; each new decision states how
it composes.

- **D-16701 — a row for a wrist-created session carries the wrist's own start.** The wrist's start
  arrives only inside its own `session_end` (plan 160 D-16001: `startedAt`/`endedAt` required;
  `watch/sync_protocol/schemas/messages/observations_up.schema.json:81-89`). When that end —
  `followed` false (`_End.parse`, `lib/core/services/watch_session_importer.dart:2322`) — meets a
  row whose `startedAtMs` is **later** than `end.startedAtMs`, the row's `started_at_ms` moves
  **down** to `end.startedAtMs`. The row's `endedAtMs`, status, rating, entries and summary are
  untouched by the correction itself; the end and status stay under G2/D-5 and O-2, and the existing
  comment "The session's own end is never touched (G2/D-5)" in `_mergeHeld` remains true for them.
  The correction only ever moves a start **earlier** — never later, and never across the row's end
  (the parse clamp, D-16408, guarantees `end.endedAtMs >= end.startedAtMs`, :2341-2346), so the row
  never gains an inverted window and no end needs re-flooring (D-153 stays untouched).
  Writes go through the row's own map, the way `_topUpRating` (:657) writes, and bump the row's
  revision so the open session screen re-reads it.
- **D-16702 — the floor artifact drops with the start (owner to confirm).** In the order where the
  terminal lifecycle is applied BEFORE the wrist's end (Order B below), `endSession` has already
  floored the row's end at the arrival-stamped start (D-153): the row then reads
  `endedAtMs == startedAtMs == adoption instant`. That equality is not "an end anyone knows"
  (O-5's subject is real end stamps); it is the phone's arithmetic placeholder for "no end known".
  So when D-16701's correction moves the start earlier **and** the row's `endedAtMs` equals its
  (pre-correction) `startedAtMs`, the end drops to the wrist's own `endedAtMs`. A row whose end is
  NOT equal to its pre-correction start keeps its end untouched — a phone-real end, and O-5's
  later-of-two-ends rule stands (S-16704 fixture C). Derived interpretation of O-5; **owner to
  confirm** (Assumption Log A-167-01).
- **D-16703 — the report-opened row is born with the wrist's `at`.** `_startSessionRow`
  (`watch_session_adoption_bridge.dart:1049`) stamps `startedAtMs` with the phone clock under the
  comment "The report carries no instant the phone trusts for a history row" — stale:
  `session_started.schema.json:14,22-24` REQUIRES payload `at`. The method takes the report payload's
  `at` and stamps the row's `startedAtMs` with it; `createdAtMs`/`updatedAtMs` and the segment's
  `atMs` stay the phone's arrival stamps (they mark when the phone learned it — mechanic). An
  `at` that is absent or unparseable (a non-conformant report; `evaluateOrAccept` already refuses a
  required-field miss, so this is belt-and-braces) falls back to today's phone clock. The adoption
  path's `_adopt` stamp is NOT changed: a snapshot carries no start, its comment is accurate — the
  merge correction (D-16701) is its repair.
- **D-16704 — both delivery orders land the wrist's span through one merge rule.** After the
  terminal lifecycle, `endSession` keeps the ended row as `currentSession`
  (`session_core_lifecycle.dart:63`), so `WatchSessionAdoptionBridge.holdsSession` (:215-218) still
  answers true and the inbox still settles held (`watch_session_inbox.dart:503`,
  `lib/watch/watch_sync_wiring.dart:274`). Hence:
  - **Order A** (the device's order, log excerpt 23:06:55Z burst): the drained `observations_up`
    delivers the end while the row is open → the merge corrects the start (no end to touch) → the
    terminal lifecycle then ends the row at the wrist's `at`, which is ≥ the corrected start → the
    span is the wrist's.
  - **Order B** (the lifecycle first — e.g. the phone reads it live before the link's inbox
    settles): `endSession` floors the end at the arrival start → the end's merge then corrects the
    start and drops the floored end (D-16702) → the span is the wrist's.
  One rule covers both; no lifecycle-side change is needed.
- **D-16705 — the import path's existing-row branch is a second application point for the same
  rule.** If the phone stops holding the row before the end's merge (the user starts another phone
  workout; the app restarts), the end's rows apply through the import path
  (`apply` with `phoneOwnsSession` false, `phoneRunsWorkout` false), whose existing-row branch
  (`_Pass.run`, `watch_session_importer.dart:528-531`) tops up rating and catches up the end but
  never corrects the start. The D-16701/D-16702 rule applies there too: an existing row with an
  arrival-stamped start is exactly the row D-16701 repairs. `_createSession` already writes the
  wrist's start (:632), so a freshly created row needs nothing. The branch is reached only with
  `end != null`, `!end.followed`, `status completed` (apply dispatch :167-177), so a `followed` end
  never carries a correction (`_applyFollowedEnd` :251).
- **D-16706 — rows already written are not repaired.** The end's `entryId` is deterministic
  (`end-<sessionId>`), the inbox stages put-if-absent, applied ids are tombstoned
  (`appliedAtMs`), and `_mergeHeld` early-returns when nothing is unapplied (:305-309): an end
  already applied at the old build never re-merges. No migration (the brief forbids one). Already
  stored rows keep start = end = the adoption instant — Duration 0s, the header at the adoption
  instant, the walk's real data (round, distance, HR summary, rating) around it. The user's remedy
  is what the app already offers (delete the workout from the workout detail screen).
- **D-16707 — the summary is untouched.** `SessionSummaryBuilder.buildSessionSummary`
  (`lib/state/workout/session_summary_builder.dart:40-41,200`) reads the row's span
  (`endedAt - startedAtMs`); with D-16701/D-16702 the span becomes the wrist's. The zero-length
  fallback for historical rows (D-16706) is an owner product decision (findings Q4), excluded here.
  TOTAL TIME — the round effort's own elapsed (`effortDurationMs`) — is unaffected and was already
  correct on the device.
- **D-16708 — diagnostics notes are follow-up, not in this plan.** `DiagnosticsLog` is wired into
  the transport only (`lib/watch/watch_sync_wiring.dart:240,243-248`); grep over `lib/` shows no
  reference in the adoption bridge or the importer (plan 164 D-16407 records the same). The three
  one-line notes the findings propose (adoption decision, row-created path, start corrected) have
  no seam in this change's files; they are listed under Notes as a follow-up plan, excluded here.

## Feature Invariants

Only the invariants that bite in this feature; project-wide rules stay in
docs/global_conventions.md.

- **A row for a wrist-created session carries the wrist's own start, whatever path created it** —
  adoption (corrected at merge, D-16701), the started report (born right, D-16703), or the import
  path (created right, D-16705). (S-16701, S-16702, S-16705, S-16706)
- **The correction only moves a start earlier, and only from the wrist's own end** (`followed`
  false). A `followed` end (the wrist describing a session the phone started) never moves the
  phone's start. (S-16703, S-16704 fixture A)
- **A row never gains an inverted window**: the corrected start stays ≤ the row's end (floored or
  wrist's — D-16702 never sets an end below the new start). (S-16704 fixtures B/C)
- **Phone-owned workouts are untouched**: a session the phone started has its own start; nothing in
  this change reads or writes it (O-6; the import-path branch reaches it only behind a `followed`
  end, which carries no correction). (S-16703)
- **Ends, statuses, sets, ratings and summaries are outside the correction's write** (O-1, O-2,
  O-5; G2/D-5 for the held merge's end). (S-16703, S-16704 fixture C)

## Requirements

1. When the wrist's own `session_end` meets a row the phone holds (merge) or an existing row in the
   import path, and the row's start is later than the end's `startedAt`, the row's start moves down
   to the end's `startedAt` (D-16701), and a floor-artifact end drops to the wrist's end (D-16702).
2. The `session_started` report stamps the row it opens with its `at` (D-16703).
3. Nothing else in either path changes: no end, status, rating, summary, entry or Health write moves
   (O-1/O-2/O-5/G2); no lifecycle or summary-builder change.
4. Already stored rows are not repaired and no migration runs (D-16706).
5. Every phase ends with tests for its S-ids; the reproduction tests are red at HEAD (prove-red
   before the fix, evidence in the evidence file).

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC-1 The device's order (end drained while the row is open) writes the wrist's start and the
  wrist's span → S-16701.
- AC-2 The reversed order (terminal lifecycle before the end's merge) writes the wrist's start and
  the wrist's span → S-16702, S-16704 fixture B.
- AC-3 A `followed` end and a later wrist start change nothing → S-16703, S-16704 fixture A.
- AC-4 A real phone end survives the correction → S-16704 fixture C.
- AC-5 The import path corrects an existing row too → S-16705.
- AC-6 The report-opened row is born with the report's `at` → S-16706.
- AC-7 An old wrist (no `session_end`) still never writes an inverted row; the zero-span display of
  un-repaired rows is pinned as accepted → S-16707, D-16706/D-16707.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect of this change | Guarded by |
|---|---|---|---|
| `SessionCoreLifecycleMethods.endSession` (`lib/state/workout/session_core_lifecycle.dart:11`, D-153 floor :48) | Bridge `_routeLifecycleToHeld` :898 (with `atMs`), phone's own Finish (`workout_session_finish.dart:88`, `session_summary_screen.dart:492`) — grep `endSession(`; writer window test `test/session_window_never_inverted_test.dart` | **Unchanged.** Order B now floors a start the merge later corrects (D-16702); the floor keeps guarding every phone-owned writer | S-16702, S-16704 B/C |
| `WatchSessionImporter._mergeHeld` (`watch_session_importer.dart:294`), end parse :331-334, G2/D-5 comment | Sole callers: `_Pass.run` :543 (via `_attemptMerge`), `_catchUpEnd` :688; inbox settle `watch_session_inbox.dart:503` — grep `_mergeHeld` | One added call: `_carryWristStart(existing, end)` after `end`/`existing` are read; the merge's other work (entries, summary, rating) unchanged | S-16701..S-16704 |
| `WatchSessionImporter._Pass.run` existing-row branch (:508, top-up :528-531) | `apply` dispatch :167-177 (only `!followed && completed` reaches `run`); `watch_session_import_test.dart` existing-row groups | One added call before `_catchUpEnd`; D-16405's Health re-write on an end move untouched | S-16705 |
| `_createSession` (`:618`, start :632) | Import path creation | Unchanged — already writes the wrist's start | S-16704 A |
| `WatchSessionAdoptionBridge._startSessionRow` (:1049) / `onSessionStarted` (:990) | Router `onSessionStarted` callers (bridge test rig :261, :2117; D-8977 groups in `test/watch_session_import_test.dart:3290+`) | `onSessionStarted` passes the payload's `at` through; `_startSessionRow` stamps it. `createdAtMs`/`updatedAtMs`/segment `atMs` unchanged | S-16706 |
| `WatchSessionAdoptionBridge._adopt` (:1116, start stamp :1124) / `_routeLifecycleToHeld` (:871) | `consider` :723; D-16401..D-16408 clamp tests (`test/watch_session_adoption_bridge_test.dart`) | **Unchanged** — adoption keeps the arrival stamp until the merge corrects it (D-16703); lifecycle clamps are plan 164's, untouched | S-16701, S-16707 |
| `SessionSummaryBuilder.buildSessionSummary` (`session_summary_builder.dart:30`) | Summary screen, `test/finish_drops_unlogged_sets_screen_test.dart`, plan 160's summary group | **Unchanged** — reads the (now correct) span | D-16707 |
| `holdsSession` (:215-218) / `currentSession` after `endSession` (`session_core_lifecycle.dart:63`) | Inbox settle :503, `watch_sync_wiring.dart:274` | **Unchanged** — this truth is what makes D-16704 hold for Order B | S-16702 |
| `DiagnosticsLog` wiring | grep `DiagnosticsLog` over `lib/` → transport only (`watch_sync_wiring.dart:240,243-248`); plan 164 D-16407 | **Untouched** — the three proposed notes are follow-up (D-16708) | Notes |
| Rows already stored with start == end (the owner's) | Repository readers (history list, summary) | Not repaired, no migration (D-16706) | S-16707, D-16706 |

## UI Standards Impact

None — no screen, widget or shared UI piece is touched. The only user-visible change is the data the
existing summary and header already render (D-16707). Grep for the touched symbols returns no
`lib/features/` reader that changes behaviour.

## Scenarios

Clock arithmetic: the harness's `TestClock` (`test/helpers/sync_protocol_harness.dart:28-35`) starts
at `WatchPairHarness.build(start: …)`; `runner.advanceTime(n)` moves it n seconds
(`test/helpers/watch_pair_harness.dart:1078,1164`). Times are wall times of 2026-11-14 UTC; `ms(t)`
is the epoch millis the row stores. The owner's walk: wrist start T0 = 22:17:21Z, wrist end
T_end = 22:57:33Z (span 2412 s = 40 m 12 s), phone adoption/draining T_drain = 23:06:55Z.

### S-16701: the device's order — end drained while the row is open (harness E2E)
- Fixture: `WatchPairHarness.build(start: DateTime.utc(2026, 11, 14, 22, 17, 21))` with the real
  bridge/importer/transport and `MockWorkoutRepository`. `runner.linkDrops()`;
  `runner.wristStartsFreeWorkout()` (session `s-w-1`, T0); `runner.advanceTime(1200)` → 22:37:21;
  `runner.wristLogsSet()` (the harness's slot is `timed` kind — the owner logged a round; the defect
  and the fix are kind-independent, A-167-03); `runner.advanceTime(1212)` → 22:57:33;
  `runner.wristFinishes()` (the twin queues `session_end`: startedAt 22:17:21Z, endedAt 22:57:33Z,
  then the terminal lifecycle into `observations_up` — plan 160 D-16001..D-16009);
  `runner.advanceTime(562)` → 23:06:55 (9 m 22 s after the wrist ended, the owner's gap);
  `runner.linkRises()` (drains within the same second: started lifecycle, ACTIVE snapshot,
  observations_up ×4 with the set and the end, terminal lifecycle).
- Trigger: the drained burst through `WatchSyncSessionInbox` settle.
- Flow: `_adopt` stamps the row's start 23:06:55 → the end's `_mergeHeld` runs with
  `phoneOwnsSession: true` → `_carryWristStart` corrects the start to 22:17:21 → the terminal
  lifecycle ends the row at 22:57:33 (≥ the corrected start; no floor needed).
- Expected outcome: `repository.getSession('s-w-1')` reads `startedAtMs == ms(22:17:21)`,
  `endedAtMs == ms(22:57:33)`, status `completed`; span 2_412_000 ms; the set's entry merged into the
  row (the summary still carries the walk's data).
- Edge case of: none. **Red at HEAD (prove-red):** `startedAtMs == endedAtMs == ms(23:06:55)`, span 0.

### S-16702: the reversed order — terminal lifecycle first, then the end's merge (harness E2E)
- Fixture: same build/start. `runner.linkDrops()`; `runner.wristStartsFreeWorkout()` (T0);
  `runner.advanceTime(1200)` → 22:37:21; `runner.wristLogsSet()` (22:37:21);
  `runner.advanceTime(1)`; `runner.linkRises()` → adoption at T_adopt = 22:37:22, row start
  22:37:22, open; `runner.advanceTime(1201)` → 22:57:33;
  `runner.refuseNext(from: PairActor.wrist, type: 'observations_up')` — the end's `observations_up`
  frames are refused live and queue;
  `runner.wristFinishes()` → the terminal lifecycle is delivered LIVE first: `endSession(at
  22:57:33)` floors the end to the start 22:37:22 (D-153) → row end == start == 22:37:22.
- Trigger: `runner.advanceTime(540)` → 23:06:33; `runner.linkRises()` → the queued end drains.
- Flow: the end's `_mergeHeld` (still held; D-16704) → `_carryWristStart` corrects the start to
  22:17:21 and drops the floored end to 22:57:33 (D-16702: the row's end equals its
  pre-correction start).
- Expected outcome: `startedAtMs == ms(22:17:21)`, `endedAtMs == ms(22:57:33)`, span 2_412_000 ms,
  status `completed`, the entry merged.
- Edge case of: S-16701. **Red at HEAD:** start 22:37:22, end 22:37:22, span 0 (the merge never
  corrects and the lifecycle already floored). Fallback if `RefuseNext` does not queue the refused
  frame: the same order is covered at unit level by S-16704 fixture B (Assumption Log A-167-02).

### S-16703: a followed end never moves the phone's start (unit pin)
- Fixture (importer merge, `test/watch_session_import_test.dart`, new group): repository with a held
  session `s-h1` (id = the watch's session id), `startedAtMs = T − 600_000` (the phone's own start),
  one segment and one effort `sx-1`; one unapplied watch `session_end` row: `startedAt = T −
  1_800_000`, `endedAt = T − 300_000`, `status: completed`, `followed: true`, `loggedAt = T −
  300_000`; one watch `set` row for the effort; importer clock = T.
- Trigger: `WatchSessionImporter.apply('s-h1', phoneOwnsSession: true)` → `_mergeHeld`.
- Expected outcome: the row's `startedAtMs` stays `T − 600_000` (the phone's start; O-6); the
  summary attaches and the entries merge as today; the end/status untouched (G2).
- Edge case of: D-16701. Green at HEAD (pin — the fix must not break it).

### S-16704: the merge rule's edges (unit, three fixtures)
- Fixture A (start moves only earlier): held row `s-h2`, `startedAtMs = T − 600_000`,
  `endedAtMs = T − 300_000` (a real phone end, later than the start); unapplied wrist end
  (`followed: false`): `startedAt = T − 100_000` (LATER than the row's start), `endedAt = T −
  90_000`. Expected: nothing moves — the row's start is never corrected later.
- Fixture B (Order B drop): held row `s-h3`, `startedAtMs = S_adopt = T − 60_000`,
  `endedAtMs = T − 60_000` (== the start: the D-153 floor of a wrist `at` before the start);
  unapplied wrist end (`followed: false`): `startedAt = T − 1_800_000`, `endedAt = T − 560_000`
  (the wrist ended before the adoption but after its own start). Expected: `startedAtMs = T −
  1_800_000`; `endedAtMs = T − 560_000` (the floor artifact dropped); span 1_240_000 ms; status
  `completed` untouched. Edge case of: S-16702.
- Fixture C (a real end is kept): held row `s-h4`, `startedAtMs = T − 600_000`,
  `endedAtMs = T − 100_000` (real, ≠ start); unapplied wrist end (`followed: false`):
  `startedAt = T − 1_200_000`, `endedAt = T − 700_000`. Expected: `startedAtMs = T − 1_200_000`;
  `endedAtMs` stays `T − 100_000` (O-5's later-of-two-ends; not a floor artifact).
- Trigger: `apply(…, phoneOwnsSession: true)` per fixture.
- Edge case of: D-16701/D-16702. Fixture A green at HEAD (pin); B and C red at HEAD for their start
  half (B's end half is the drop).

### S-16705: the import path corrects an existing row (unit)
- Fixture: history holds session `s-i1`, `startedAtMs = T − 60_000`, `endedAtMs = T − 60_000`
  (adoption-created then floored), one segment + one effort so rows place; wrist end
  (`followed: false`): `startedAt = T − 1_800_000`, `endedAt = T − 560_000`; plus the set row;
  importer clock = T; `phoneOwnsSession: false` (the phone no longer holds the row).
- Trigger: `WatchSessionImporter.apply('s-i1')` → `_Pass.run`'s existing-row branch.
- Expected outcome: `startedAtMs = T − 1_800_000`; `endedAtMs = T − 560_000`; the set imports into
  the effort; `_topUpRating`/`_catchUpEnd` behave as today (the wrist end is not later than the
  row's end after the drop, so the catch-up is a no-op).
- Edge case of: S-16702. **Red at HEAD** (no correction on the import path today).

### S-16706: the report-opened row is born with the report's `at` (bridge)
- Fixture: the bridge test rig (`test/watch_session_adoption_bridge_test.dart`, the D-8977 rig,
  :261-270) whose `_report()` payload `at` = 2026-10-05T10:00:00Z; no row for `s-w1`; the rig's
  bridge clock pinned to a later instant (arrival > `at`, the phone-woke-later shape).
- Trigger: `onSessionStarted(report)` through the router, as the D-8977 tests call it.
- Expected outcome: the created row's `startedAtMs == ms(10:00:00Z)` (the report's `at`);
  `createdAtMs`/`updatedAtMs` and the segment's `atMs` stay the phone's arrival stamp; the row opens
  with the report's segment/effort shape exactly as D-8977 pins (D-8977's own assertions unchanged).
- Guard companion: a report whose `at` cannot parse opens the row at the phone clock (pin).
- Edge case of: none. **Red at HEAD** (`startedAtMs` is the phone clock).

### S-16707: an old wrist (no `session_end`) never writes an inverted row (pin)
- Fixture: the bridge rig's adopted held session `s-cap`, `startedAtMs = T0` (the adoption instant),
  open; no `session_end` anywhere; a wrist `session_lifecycle` frame `{state: completed, sessionId:
  s-cap, at: T0 − 2_400_000}` (a wrist that ended 40 min before the phone woke and adopted it — the
  no-`session_end` legacy shape).
- Trigger: the lifecycle through the router, as S-15403's group does.
- Expected outcome: `endSession` floors — `endedAtMs == startedAtMs == T0`, status `completed`,
  never negative (D-153, already true at HEAD). The display is the accepted un-repaired picture:
  Duration 0s, header at the adoption instant, TOTAL TIME real (D-16706/D-16707). Pin (green at
  HEAD) — documents what the owner's un-repaired rows keep showing.
- Edge case of: none.

## Iteration 1

### Phase 1: red reproduction (@developer)
1. [ ] Add the group `plan 167 the wrist's own start on the phone` with the S-16701 harness test
  (device order, fixture and assertions exactly as written) — `test/watch_convergence_harness_test.dart`
  · `group 'plan 167…'` (model: the S-14660 trace at :837-980; harness actions
  `test/helpers/watch_pair_harness.dart:1059-1078`)
2. [ ] Add the S-16702 harness test to the same group (Order B; if `refuseNext` does not queue the
  refused frame, stop, log A-167-02 in the evidence file, and note that Order B rides on S-16704
  fixture B until the harness question is settled) — `test/watch_convergence_harness_test.dart` ·
  same group
3. [ ] Add the group `plan 167 the held row's start` with the S-16703 pin and the S-16704 fixtures
  A/B/C unit tests — `test/watch_session_import_test.dart` · new group (merge groups are the model)
4. [ ] Add the S-16705 import-path test to the same new group — `test/watch_session_import_test.dart`
  · same group
5. [ ] Add the S-16706 test (report `at` stamp) beside the D-8977 group, using the rig's `_report()`
  — `test/watch_session_adoption_bridge_test.dart` · new test in the plan-129/report area (:1926+)
6. [ ] Add the S-16707 pin beside the S-15403 group (the lifecycle floor on an adopted held row) —
  `test/watch_session_finish_test.dart` · new test in the plan-146 group
7. [ ] Prove red at HEAD: run the five files' new groups; paste pass/fail counts and the failing
  assertions into `2026-11-14-167-wrist-walk-start-on-phone-plan.evidence.md` (expected reds:
  S-16701, S-16702, S-16704 B/C start+drop, S-16705, S-16706; expected pins: S-16703, S-16704 A,
  S-16707)

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test
test/watch_convergence_harness_test.dart`, `test/watch_session_import_test.dart`,
`test/watch_session_adoption_bridge_test.dart`, `test/watch_session_finish_test.dart` — new groups
pass with the expected red/pin mix recorded; `gateway.sh lint` at the baseline (181 pre-existing
issues, no new). **Predicted Files**: the four test files, the evidence file. Nothing else.

### Phase 2: the fix (@developer)
1. [ ] Add `_carryWristStart(TrainingSession existing, _End end) → TrainingSession?` implementing
  D-16701 + D-16702: correct the start to `end.startedAtMs` only when `end.startedAtMs <
  existing.startedAtMs`; when it corrects and `existing.endedAtMs != null` and
  `existing.endedAtMs == existing.startedAtMs`, set the end to `end.endedAtMs`; return the rebuilt
  row (or null when nothing moves) — `lib/core/services/watch_session_importer.dart` ·
  `_carryWristStart` (write through the row map as `_topUpRating` :657 does)
2. [ ] Call it in `_mergeHeld` right after `end` and `existing` are read (:331-341), replacing
  `existing` with the rebuilt row before the entries/summary work continues —
  `lib/core/services/watch_session_importer.dart` · `_mergeHeld`
3. [ ] Call it in `_Pass.run`'s existing-row branch before `_topUpRating` (:528-531), same
  replacement — `lib/core/services/watch_session_importer.dart` · `_Pass.run`
4. [ ] Stamp the row with the report's `at`: `onSessionStarted` passes `payload['at']` through and
  `_startSessionRow` stamps `startedAtMs` from it (phone-clock fallback on an unparseable value),
  replacing the stale comment — `lib/state/watch/watch_session_adoption_bridge.dart` ·
  `onSessionStarted`, `_startSessionRow`
5. [ ] Run Phase 1's groups: every red turns green, every pin stays green; paste the red→green
  table into the evidence file

**Done Criteria** (run until green): `gateway.sh test test/watch_session_import_test.dart`,
`test/watch_session_adoption_bridge_test.dart`, `test/watch_session_finish_test.dart`,
`test/watch_convergence_harness_test.dart`; `gateway.sh lint` at the baseline. **Predicted Files**:
`lib/core/services/watch_session_importer.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`
(+ the evidence file). Nothing else.

### Phase 3: docs and full suite (@developer)
1. [x] `docs/watch_session_sync.md`: state the start rule in the adoption-table row and the held
  merge section (:21-28 table, "The two directions of ending" :295+) — one sentence each for
  D-16701/D-16702 and D-16703, naming the tests
2. [x] `docs/watch_session_capture.md` (:8-40, the importer's role): one sentence that the merge and
  the import path correct a held/existing row's start from the wrist's end (D-16701/D-16705)
3. [x] `docs/state_management/workout_state.md`: verify-no-change — `endSession` (:136) and
  `catchUpEndedSession` (:137) describe untouched code; grep the doc for a sentence the change makes
  false (the writer-window claim stays true: the corrected window is still ordered)
4. [x] Run the full suite once with the 900 s timeout (`gateway.sh test` with no file list); paste
  the counts into the evidence file; `gateway.sh lint` at the baseline
5. [x] State each touched doc's size against the 52 KB band in the evidence file (the 64 KiB cap is
  `test/docs_indexing_contract_test.dart`)

**Done Criteria** (run until green): full suite green (or a named, pre-existing red quoted from
plan 160/164's evidence baselines); lint at the baseline; docs state the rule. **Predicted Files**:
`docs/watch_session_sync.md`, `docs/watch_session_capture.md` (+ the evidence file);
`docs/state_management/workout_state.md` only if item 3 finds a false sentence. **Phase 3
verification notes (Conductor, date):** — added at verification.

## Files Affected (whole feature)

- `lib/core/services/watch_session_importer.dart` — `_carryWristStart` (new), `_mergeHeld`,
  `_Pass.run` (Phase 2)
- `lib/state/watch/watch_session_adoption_bridge.dart` — `onSessionStarted`, `_startSessionRow`
  (Phase 2)
- `test/watch_convergence_harness_test.dart` — S-16701, S-16702 (Phase 1)
- `test/watch_session_import_test.dart` — S-16703..S-16705 (Phase 1)
- `test/watch_session_adoption_bridge_test.dart` — S-16706 (Phase 1)
- `test/watch_session_finish_test.dart` — S-16707 (Phase 1)
- `docs/watch_session_sync.md`, `docs/watch_session_capture.md` (Phase 3)
- `docs/plans/2026-11-14-167-wrist-walk-start-on-phone-plan/2026-11-14-167-wrist-walk-start-on-phone-plan.evidence.md`
  — every phase appends its baseline/counts

Untouched by design: `session_core_lifecycle.dart` (endSession/catchUpEndedSession),
`session_summary_builder.dart`, `watch_session_inbox.dart`, `watch_sync_wiring.dart`, the schema
files, `watch/watchos/**`, `watch/contract/`.

## Notes

- Phase dependency: 1 → 2 → 3 strictly; the fix without the red tests is unverifiable, the docs
  trail the code by zero phases (Phase 3 runs right after Phase 2).
- Intermediate state (after Phase 2 item 1, before item 2/3): `_carryWristStart` exists but nothing
  calls it — lint passes, suites unchanged. After item 2 only the merge corrects; S-16705 stays red
  until item 3.
- The `observations_up` drain order inside one burst is the wrist's frame order (log excerpt
  23:06:55Z: lifecycle, snapshot, observations_up ×4+, terminal lifecycle within 2 s) — that is why
  Order A is the device's order and Order B needs the refusal to construct.
- D-16408's parse clamp guarantees `end.endedAtMs >= end.startedAtMs`, so D-16702's dropped end never
  lands before the corrected start; no new bound is added.
- Follow-up (NOT in this plan, D-16708): a plan wiring `DiagnosticsLog` into the bridge/importer and
  adding the three one-line notes (adoption decision, row-created path, start corrected) the
  investigation findings propose.
- Legacy handling: rows already stored keep their zero span (D-16706); S-16707 pins the no-end
  behaviour so the accepted picture is explicit.

## Progress

- [x] Phase 1: red reproduction (@developer) — 9 tests in 4 files; red at HEAD: S-16702, S-16704 B/C
  start+drop, S-16705, S-16706 (prove-red alone: 4 of 5 files — `RED AT HEAD` ×3); pins green:
  S-16703, S-16704 A, S-16706 guard, S-16707, **S-16701** (see A-167-05). Evidence: evidence.md §1.
- [x] Phase 2: the fix (@developer) — `_carryWristStart` + two call sites; the report's `at` stamps
  the adopted row. All four groups green (`+5`, `+2`, `+2`, `+1`); three mutation proofs.
- [x] Phase 3: docs and full suite (@developer) — `watch_session_sync.md` (row + "late start" paragraph)
  and `watch_session_capture.md` ("Why a wrist end may move an existing row's start"); `workout_state.md`
  verify-no-change (the writer-window claim stays true). Full suite `+7612 ~4` all passed; lint 181
  (baseline); 200-seed sweep: 4 shipping divergers (≤ plan 161's 5). Evidence: evidence.md §3.

## Assumption Log

- A-167-01 (owner to confirm): D-16702 reads O-5 as covering real end stamps, so a floor-artifact
  end (`endedAtMs == startedAtMs`) may drop when the start is corrected. Options: drop the artifact
  (chosen — it is the phone's "no end known" placeholder, and keeping it writes the wrong span
  forever) vs keep it (the row stays zero-length). Promote to a D-x or revert at verification.
- A-167-02 (owner to confirm): `runner.refuseNext(from: PairActor.wrist, type: 'observations_up')`
  makes the refused frame queue for the next link rise (the radio queues on a refused send). If the
  harness refuses differently, Order B's harness test falls back to S-16704 fixture B (unit) until
  the harness question is settled.
- A-167-03 (owner to confirm): S-16701's `wristLogsSet` uses the harness's `timed` slot where the
  owner logged a round; the defect chain is kind-independent (only the span is at stake), and plan
  160's twin emits the same `session_end` either way.
- A-167-04 (owner to confirm): a mis-marked `followed` end for a phone-created session would move
  that phone session's start if the wrist claimed a later one — accepted: the phone trusts the
  wrist's own end for a session the wrist created; D-16003 marks `followed` from the wrist's
  creation source.
- A-167-05: S-16701 is GREEN at HEAD, not red (the plan's item 7 predicted red). With the link down
  for the whole workout, the drained snapshot's `_createSession` writes the wrist's start before any
  adoption opens a row, so the merge never sees an arrival-stamped start there. The order stays as
  written (it guards the device's order end-to-end); the correction is proven red by S-16702,
  S-16704 B/C, S-16705 and S-16706.
- A-167-06: S-16702's planned `advanceTime(1201) → 22:57:33` is a ten-second slip (22:37:22 + 1201 s
  = 22:57:23); the fixture advances 1211 s so the wrist's end is the owner's 22:57:33 (span
  2 412 000 ms).
- A-167-07: `advanceTime` only takes 1–90 s (D-14505), so both harness tests step the walk in 90 s
  slices through a local `advance(runner, seconds)` helper; the clock lands on the same instants.
- A-167-08: `_End.startedAtMs` and `_End.endedAtMs` are both non-nullable `int` (the importer builds
  `_End` only from a row that parses), so `_carryWristStart` needs no null guard: a `!followed` end
  naming a strictly earlier start moves the row, and only the floor-artifact drop then uses the end.
  No bound is added: D-16408's clamp keeps `end.endedAtMs >= end.startedAtMs`.
- A-167-09: doc byte sizes are not measurable with the developer's tools (`wc -c` is not a gateway
  check), so the 52 KB band is evidenced by `test/docs_indexing_contract_test.dart`'s
  `no documentation file is within the warning band of the ceiling` (0.80 × 64 KiB ≈ 51.2 KiB),
  which passed in the full run. Governor may confirm with `wc -c` on the two pages.
- A-167-10: the 200-seed sweep in this tree reports 4 shipping divergers (≤ plan 161's 5) against
  HEAD's 3, so one seed (136) moved into the class the defect already owns. Both `lib/` changes in
  this working tree (this plan's and the parallel plan 168's sensor mirror) feed the harness, so the
  per-seed attribution cannot be isolated from one sweep; the brief's class-count rule passes.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]