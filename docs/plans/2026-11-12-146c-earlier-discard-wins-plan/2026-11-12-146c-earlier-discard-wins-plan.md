# Plan — 146c (146 PR 3): an earlier discard wins, and the owner-confirmed remainders

**Status**: planned 2026-11-12 from the owner's confirmations; not built.
**Base**: branch `claude_develop`. Plans 144, 145 and 146 PR 1 (ad8308ec) + PR 2 (41915121) are committed.
**Parents**: plan 146 (`docs/plans/2026-11-11-146-ended-is-final-plan/` — its PR index row "PR 3: planned:"
points here), plans 145, 128/140/141. Binding conventions: `docs/global_conventions.md`;
`docs/db_integration.md` + `docs/data_models.md` for the importer and deletion items; `docs/design_system.md`
— not touched (no UI change).

## Overview

Plan 146 PR 1 landed "ended is final" with a deliberate interim: a completion outranks a discard
whatever the two instants say (A-146-15), and the phone ignores an arriving discard for an ended row.
The owner has now confirmed the real rule (O-7, 2026-11-12): **when both devices ended the same workout,
the earlier end instant decides — if you discard before the other device finishes, the discard wins and
the workout is deleted; a finish strictly before the discard keeps the workout; equal instants keep
D-14601's tie-break (completed wins, then the smaller messageId).**

What the owner sees, in plain language:

- Discard on the watch while the link is down, then you finish the workout on the phone: when the link
  returns, the phone deletes the finished workout and its calendar entry (and its Health entry); the
  watch's copy simply says "discarded".
- Finish on the phone first, discard on the watch later: the workout stays finished — the late discard
  changes nothing.
- Both devices end it at the same moment: the finish wins.
- Two different workouts open at once (one per device): the phone keeps its own; the watch's is saved
  as its own finished workout, with its sets. Nobody's data is deleted (O-6).
- When a workout's end time moves because a device caught up, the Health app entry is rewritten to the
  new window (owner wants this, done last in this PR — owner to confirm).
- The soak's unexplained divergence classes are either classified (shrink-and-classify) or explicitly
  deferred with a reason; the sweep contract is re-measured after the rule lands.

## Resolved Decisions (Ledger)

Plan 146's owner decisions O-1..O-9 remain binding and are never edited. D-14601..D-14609 (plan 146)
and D-14610.. (plan 149b) are taken; this plan uses **D-14630..**, stable and never reused.

- **D-14630 (the rule; owner-confirmed 2026-11-12; supersedes the A-146-15 interim on all stacks).**
  When both devices ended the same workout, the EARLIER end instant decides the status. A discard with
  an instant strictly earlier than the held finish deletes the workout on the phone (row, calendar
  entry, Health) and leaves the wrist's copy `abandoned`; a finish with a strictly earlier instant keeps
  the workout (the arriving discard is ignored); an exactly-equal instant keeps D-14601's tie-break —
  `completed` wins, then the lexicographically smaller `messageId`. Compared instants are the two
  devices' wall clocks; skew is accepted (D-14601, owner-vetoed never). This removes A-146-15's
  "a completion outranks a held discard whatever the instants" from the Dart twin
  (`lib/watch/session/watch_session_engine.dart`, the `if (status != completed || session.status !=
  abandoned)` skip ~766-776 in `_applyLifecycle`) and from Swift
  (`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, the same skip ~826-833 in
  `applyLifecycleExclusive`). The phone's own reconciler already obeys the rule and changes nothing
  (`lib/core/sync_protocol/session_reconciler.dart`, `_incomingEndWins` :226-241 — earlier instant
  wins, completed wins ties, then messageId; no interim special case).
- **D-14631 (the phone's delete is a discard, not an edit).** The arriving earlier `abandoned` deletes
  the held ended row through `discardCurrentSession` (`lib/state/workout/session_core_lifecycle.dart`
  :117) — the same deletion the user's own discard runs: timers closed in memory (D-14603c), row
  deleted, `onSessionDeleted` Health delete. The phone does not re-announce; the wrist's own abandon
  frame is the confirmation that retires the phone's owed-end debt
  (`lib/state/watch/watch_incoming_router.dart` :206-210), so no stale re-offer is sent after the
  delete (asserted in S-14630).
- **D-14632 (sets under a winning discard — PRODUCT, owner to confirm; default).** Default: a winning
  discard deletes the workout and its sets on the phone; nothing is resurrected; the wrist's copy is
  `abandoned` and keeps the entries it stored (the unconfirmed copies of D-14605/D-14607 are never
  turned back into history). O-4's "sets are added on both sides" applies to a winning FINISH only.
  Resurrection is already structurally impossible today: history is created only from a `completed`
  end (`lib/core/services/watch_session_importer.dart` :166-190 — an `abandoned` end is consumed
  without history, D-133) and a merge into a row that is gone consumes its rows (D-136, :329-332) —
  but S-14633 pins it with a test because this PR is what first makes the phone delete a row on an
  arriving frame.
- **D-14633 (O-6 stands as built — prove, don't rebuild).** Two different workouts open at once: the
  phone keeps its own open session; the wrist's is saved as its own finished workout with its sets.
  The machinery exists: the router answers a foreign snapshot with abandoned-for-that-session plus the
  phone's state (`watch_incoming_router.dart` :162-170, D-182) and reports the skip
  (`watch_session_adoption_bridge.dart` :113-126, "kept X, did not adopt Y"); the wrist's rows stage in
  the inbox and `WatchSessionInbox._settleNow` calls
  `WatchSessionImporter.apply(sessionId, phoneOwnsSession: adoption.holdsSession)`
  (`lib/state/watch/watch_session_inbox.dart` :467-481, wired at `lib/state/watch/watch_sync_wiring.dart`
  :270); a `completed` end with live entries and no existing row creates the session with its sets
  (`watch_session_importer.dart` `_Pass.run` → `_createSession`, :560-600). PR 3 adds the proof: an
  importer test and a scripted pair-harness trace. Predicted green; if red, fix at the confirmed seam
  and record it in the Assumption Log.
- **D-14634 (Health re-write after an end-time move — owner wants it, done last; owner to confirm).**
  When a catch-up moves a finished session's `endedAtMs` later, the HealthKit workout is rewritten to
  the new window. Today `onSessionCompleted` writes at most once per session id — the ledger
  (`lib/core/services/health_sync_service.dart` :71-104: `_writtenThisRun`, `_ledgerContains`,
  `_rememberWritten`) blocks a naive re-write, and nothing updates the window after the fact, so the
  stored workout's span goes stale (no duplicate is created — the re-write is refused). The rewrite is
  a new method: delete the workouts in `[startedAtMs, max(previousEndedAtMs, endedAtMs)]` (the old
  window is contained in the new one, so one delete covers it), clear the effort in the same window,
  write the new draft, re-rate when a rating exists; the ledger keeps the session id. Delete-then-write
  is idempotent, so any number of moves leaves exactly one workout.
- **D-14635 (the timers residue, seed 1814 — shrink, then fix at the confirmed seam).** A-146-29's
  residue: the wrist's end reaches the phone, whose own session keeps the rest it started. First step
  is a shrink of seed 1814 and a classification of the seam; the predicted seam is `endSession`
  (`lib/state/workout/session_core_lifecycle.dart` :14-62), which persists open rests as history but
  never stops the live in-memory rest the way a discard does (D-14603c closes them;
  `persistOpenRests` does not). Fix only if the red run confirms the seam.

## Feature Invariants

- An arriving discard never deletes a workout the phone finished strictly earlier; an arriving discard
  at or after the held end instant changes nothing.
- A winning discard never resurrects anything: after the delete, no reader (importer, inbox, calendar,
  stats, Health) re-creates the workout or surfaces a phantom one from staged rows.
- Both stacks resolve the same terminal-vs-terminal pair to the same status under the same instants
  (the cross-stack tests stay green in both arrival orders).
- The HealthKit store holds at most one workout per session after any number of end-time moves.
- `MockWorkoutRepository` mirrors `HiveWorkoutRepository` output value-for-value on every touched path
  (the importer and deletion items touch both).

## Requirements

- **R-1**: the earlier-discard-wins rule on all three stacks — phone (`_routeLifecycleToHeld`'s ended
  branch), Dart twin (`_applyLifecycle`), Swift (`applyLifecycleExclusive`) — with the tie-break
  unchanged (D-14630).
- **R-2**: the contract states the deletion consequence: PROTOCOL.md's lifecycle bullet gains the
  discard-deletes sentence, a new version-history row is appended, and
  `fixtures/reconciliation/discard_before_finish.json` pins the completed-then-earlier-abandoned walk.
- **R-3**: O-6 is proved by an importer test and a pair-harness trace (D-14633); a red proves a defect,
  which is then fixed at its seam.
- **R-4**: the sweep and soak are re-measured after R-1; the `status` class is re-owned in
  `knownClasses`, the ratchet is set to the measured rate, and the unexplained classes
  (`absorbing` seed 111, `entries` 11/2000, `timers` seed 1814) are each classified by a
  shrink-and-classify run or explicitly deferred with the first step recorded.
- **R-5**: the Health re-write after an end-time move (D-14634), implemented last in this PR, idempotent
  (owner to confirm).

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC-1: a discard strictly earlier than the finish deletes the workout on the phone and leaves the
  wrist's copy `abandoned`, on both stacks → S-14630, S-14640, S-14641, S-14650.
- AC-2: a finish strictly earlier than the discard keeps the workout; an equal instant keeps the
  tie-break → S-14631, S-14632, S-14643.
- AC-3: a winning discard leaves no phantom workout or stray entry → S-14633.
- AC-4: two different workouts open at once — the phone's stays open, the wrist's is saved as its own
  finished workout with its sets → S-14660.
- AC-5: the sweep contract reflects the new rule — `status` re-owned, ratchet re-measured, the three
  residue classes classified or deferred → S-14661, S-14662, S-14663.
- AC-6: a moved end rewrites the Health workout, idempotently; a never-written session writes nothing
  → S-14670, S-14671.

## Existing-Functionality Impact

- **Held-row lifecycle routing** (`_routeLifecycleToHeld`, `lib/state/watch/watch_session_adoption_bridge.dart`
  :870; grep: `watch_incoming_router.dart` `receive` :178-180 routes every `session_lifecycle` there):
  the ended branch (:884-893) gains the discard-wins arm; a held ended row can now be DELETED by an
  arriving frame, where today it is only end-caught-up or ignored → guarded by S-14630..S-14632.
- **`discardCurrentSession` callers** (grep: `lib/state/workout/workout_session_finish.dart:16`,
  `lib/features/session/session_summary_screen.dart:464`,
  `lib/features/history/workout_session_list_view.dart:1034,1043`): the bridge becomes a new caller;
  none of the existing callers change (the bridge calls it on a row the user is not holding — the
  summary screen the finish opened is closed by `clearSession`, the same thing a user discard does).
  The deliberate history delete of a finished session keeps working (O-2 permits it) → guarded by the
  existing `test/watch_session_finish_test.dart` suite + S-14630.
- **What a deleted row means to its readers** — calendar (`calendar_state.dart` lists sessions;
  duration derives on the fly at `calendar_state.dart:322`), stats
  (`stats_progress_service.dart:489/921`), day list (`day_session_list_screen.dart:581`), Health
  (`onSessionDeleted`'s window, `health_sync_service.dart` :199-234), importer D-133/D-136, the
  mirror's owed-end memory (`rememberedFateOf` :767, `takeOwedEnd` :839): a discard-deleted finished
  row is indistinguishable from a user discard to all of them — except the phone's own announced fate,
  which stays `completed` in `_fates`; the wrist's abandon frame retires that debt before the delete
  can matter (`watch_incoming_router.dart` :206-210), asserted in S-14630 → guarded by S-14630, S-14633.
- **The mirror's own terminal rule** (`lib/core/sync_protocol/session_reconciler.dart`
  `_applyLifecycle` :186-216, `_incomingEndWins` :226-241): already earlier-instant-wins with the
  D-14601 tie-break — verified no change (the grep above is the proof); the twin's interim was the
  only code that deviated from the contract text.
- **The twin's snapshot path** (`_applySnapshotExclusive`, `watch_session_engine.dart` :563-590):
  already instant + tie (`_incomingEndWinsATie`), no interim — verified no change. Swift's
  `applySnapshotExclusive` likewise (:612-625) — verified no change (Phase 3 item).
- **Fixtures and walkers** (`watch/sync_protocol/fixtures/manifest.json` :1035 names
  `ended_is_final.json`; `test/sync_protocol_fixtures_test.dart` S-004 walks every reconciliation
  fixture; `SyncProtocolFixturesTests.swift` / `WatchLiveMirroringTests.swift` in Swift): the new
  fixture joins the register in the same phase as the rule, so no walker sits red → S-14642, S-14651.
- **Tests that pin the interim** (A-146-15's three engine tests in `test/watch_session_engine_test.dart`;
  S-14512 in `test/watch_convergence_harness_test.dart`): the rule change re-points them in the same
  phase, so the suite never sits red on a pinned-but-superseded assertion → Phase 2 items 2-4.
- **The sweep contract** (`test/watch_convergence_random_test.dart`, `knownClasses` :171-191,
  `shippingRatchet` :204): `status` 166/2000 is owned by this PR and should shrink once both sides
  apply the same rule; the ratchet and the class text are re-measured after Phases 1-3 → S-14661.
- **Health** (`onSessionCompleted`'s once-per-session ledger :71-104; `onSessionRated`'s effort window
  :157-196; `onSessionDeleted`'s window :199-234): the rewrite adds a path that deliberately bypasses
  the once-guard, and its delete window must cover the window any earlier write used → guarded by
  S-14670, S-14671.

## UI Standards Impact

None — no screen, widget, copy or navigation change. The calendar entry's disappearance after a winning
discard is the product behaviour the owner confirmed, not a design exception.

## Scenarios

- **S-14630: the wrist's earlier discard deletes the phone's finished workout.**
  Fixture: the wrist starts w1; the phone adopts it and logs a set on it (loggedAt 09:55); the link
  drops; the wrist discards w1 at t1 = 10:00 (its clock; the announce queues); the phone finishes its
  copy of w1 at t2 = 10:05 (its own end; `onSessionCompleted` writes Health); the link rises; the
  queued `abandoned` (at t1) is delivered. Trigger: heal. Flow: the mirror's reconciler flips to
  `abandoned` (already instant-based); `_routeLifecycleToHeld`'s ended branch sees `abandoned` at
  t1 < endedAtMs t2 and deletes. Expected: the phone's row w1 is gone (the calendar no longer lists
  it; the summary the finish opened is closed); the HealthKit workout is deleted
  (`onSessionDeleted`); the staged set is consumed, never resurrected; the wrist reads w1 `abandoned`;
  no further lifecycle traffic for w1 leaves the phone after the delete (the debt was retired by the
  wrist's own frame); `absorbingViolations` empty. Edge case of: S-14606.
- **S-14631: the phone's earlier finish survives a later arriving discard.**
  Fixture: the same pair; the phone finishes its copy at t1 = 10:00 (announces `completed` at t1); the
  wrist abandons at t2 = 10:05 (its own act); the link returns and both frames are delivered. Expected:
  the arriving `abandoned` (t2 > t1) is ignored — the phone keeps the completed workout, row and Health
  intact; the wrist's held copy flips to `completed` on the arriving earlier end (its own restored
  rule); both sides read `completed`. Edge case of: S-14630. (Stated with real instants; under the
  harness's clocks the scripted order reads differently — see the Notes and Open question 4.)
- **S-14632: an arriving discard at exactly the held end instant is ignored.**
  Fixture: the phone's held row w1 ended at t; an `abandoned` lifecycle for w1 with `at` == t arrives.
  Trigger: message delivery. Expected: nothing changes — the tie-break keeps `completed`
  (D-14601 as amended); no delete, no end move. Edge case of: S-14630.
- **S-14633: a winning discard leaves no phantom workout or stray entry.**
  Fixture: after S-14630's delete, the phone's inbox holds a staged set for w1 (never applied); then
  the wrist's `session_end` for w1 arrives (its state is `abandoned` — the wrist discarded it); then a
  further late set for w1 arrives with no end. Trigger: inbox settle (`WatchSessionInbox._settleNow`,
  `phoneOwnsSession` now false — the row is gone). Expected: the abandoned end imports nothing (D-133)
  and is consumed; the staged sets are consumed with it or wait unapplied for ever; `getSession(w1)`
  stays null on every settle; no calendar or stats row ever appears. Edge case of: S-14630.
- **S-14640: an earlier arriving discard replaces the twin's held completed (the wrist keeps
  `abandoned`).**
  Fixture: the Dart twin holds w1 with a terminal row `completed`, `recordedAt` t2 = 20:01, one entry;
  an `abandoned` lifecycle with `at` t1 = 20:00:30 arrives; then a stale `started` (t3) and an `active`
  snapshot (t4) follow. Expected: the held status is `abandoned` with `recordedAt` t1; the entries stay
  (union by entryId); no timer starts; the later `started`/snapshot change nothing. Edge case of:
  S-14601.
- **S-14641: the arrival order does not matter — both orders converge on the same ending.**
  Fixture: (a) held `abandoned` at t1; a `completed` at t2 > t1 arrives → ignored, stays `abandoned`;
  (b) held `completed` at t2; the `abandoned` at t1 < t2 arrives → flips, `abandoned` (this is
  S-14640's arm). Expected: the same held ending whatever order the frames arrived in, on both stacks.
  Edge case of: S-14640.
- **S-14642: the contract fixture walks the rule (S-004).**
  Fixture: `watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json` — initial snapshot
  s-sw-b `active` (revision 3) with a running rest timer and entry e-b1; stream: `completed`
  (messageId msg-c, `at` 2026-07-13T20:01:00Z), then `abandoned` (messageId msg-d, `at`
  2026-07-13T20:00:30Z — strictly earlier). Expected: sessionId s-sw-b, status `abandoned`,
  revision 3, entries [e-b1], timers {}. Walked automatically by
  `test/sync_protocol_fixtures_test.dart` S-004 and, in Phase 3, by the Swift suite. Edge case of: none.
- **S-14643: cross-stack — both arrival orders on both stacks agree.**
  Fixture: the three terminal pairs of S-14641, delivered in both orders through the pair harness so
  the phone's status and the wrist's are asserted in one test each (the A-146-11 pattern). Expected:
  the phone's and the wrist's statuses agree in every case; the tie cases of the existing group stay
  green. Edge case of: S-14641.
- **S-14650: the Swift engine's earlier-discard rule.**
  Fixture: the Swift engine holds w1 `completed` at t2; an `abandoned` lifecycle at t1 < t2 arrives;
  then the S-14641 pairs in both orders. Expected: `abandoned` at t1; both orders converge; the
  existing tie tests stay green. Walked by `WatchEndedIsFinalTests.swift`. Edge case of: S-14640.
- **S-14651: the Swift fixture walker converges on `discard_before_finish.json`.**
  Fixture: the S-14642 file, replayed through the Swift engine. Expected: the expected block is
  reproduced. Walked by `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges` (no edit
  predicted — the walker enumerates the manifest). Edge case of: S-14642.
- **S-14660: O-6 — the wrist's own workout is saved as its own finished workout while the phone's stays
  open.**
  Fixture: the phone starts p1 (its own, open, one set logged on it); the wrist free-starts w2 and logs
  a set on it (entry e-w2-1); the phone holds p1; the wrist finishes w2 (`completed`, its end and set
  queue); heal; the inbox settles w2. Trigger: heal, then the inbox settle. Expected: p1 is still
  `active` on the phone (nothing adopted — the skip report or the D-182 answer names w2); a history row
  for w2 exists with the wrist's startedAt/endedAt and the set e-w2-1; the phone's calendar lists p1
  (open) and w2 (finished); nothing was deleted on either side; `entryMismatches` empty for w2. Edge
  case of: none.
- **S-14661: the sweep contract reflects the new rule.**
  Fixture: the sweep itself (seeds 1..200 on `kShippingActions`, then the 2000-seed soak). Expected:
  the `status` class shrinks from its 166/2000 residue (both sides now apply the same earlier-instant
  rule); `knownClasses['status']`'s text names the measured owner (or "closed" if it reaches 0);
  `shippingRatchet` is set to the newly measured rate; no new unknown class appears. Edge case of: none.
- **S-14662: the unexplained classes are classified or explicitly deferred.**
  Fixture: seeds 111 (`absorbing`) and the `entries` residue, replayed under the FULL action space (not
  only `kShippingActions`) and run through the Shrinker. Expected: for each class, either a minimal
  trace with the defect classified and a named owner, or a recorded no-trace finding with the first
  step for the next PR — written to the evidence file. No product change is predicted here. Edge case
  of: none.
- **S-14663: the wrist's end stops the rest the phone's own session started (seed 1814's class).**
  Fixture: the phone holds p1 active with a running rest it started; the wrist's `completed` for p1
  arrives; the phone's end runs. Expected: after the end, no rest RUNS on the phone (the persisted rest
  row is history; the live timer is stopped); the sweep's `timers` class reaches 0 if this was the
  whole residue. Edge case of: S-14603 (plan 146).
- **S-14670: a moved end rewrites the Health workout, idempotently.**
  Fixture: session s completed and written to Health with end t1 (the ledger holds s); a catch-up moves
  `endedAtMs` to t2 > t1; the rewrite runs; then a second catch-up moves it to t3 > t2. Expected: after
  each move exactly one workout exists in [start, newEnd] (the previous window's workout deleted by the
  same call); the effort is re-rated once per move; the ledger still holds s; a rewrite for a session
  with no rating writes no effort. Edge case of: none.
- **S-14671: a moved end on a session never written to Health writes nothing.**
  Fixture: a session whose write was never made (the toggle off, or a wrist-saved workout —
  `wristSavesWorkout`), then a catch-up moves its end. Expected: the rewrite is a no-op — no workout
  created, no ledger change. Edge case of: S-14670.

## Iteration 1

### Phase 1: the phone obeys the owner's rule (@developer)
1. [ ] In `_routeLifecycleToHeld`'s ended branch, parse the arriving instant and add the discard-wins
       arm: `state == abandoned && atMs != null && atMs < held.endedAtMs` → `await
       target.discardCurrentSession()`; the `completed` catch-up stays, and an equal or later instant
       stays ignored — `lib/state/watch/watch_session_adoption_bridge.dart`
       (`_routeLifecycleToHeld`, :870; ended branch :884-893) — D-14630, D-14631.
2. [ ] Red-first tests: S-14630 (the earlier discard deletes the finished row, `onSessionDeleted`
       fires, no post-delete lifecycle traffic) and S-14632 (an equal instant is ignored) —
       `test/watch_session_adoption_bridge_test.dart` (new group `O-7 an earlier discard deletes a
       finished workout`, driving the bridge's `onLifecycle`).
3. [ ] Red-first test S-14633: after the delete, a staged set + the wrist's abandoned `session_end` →
       consumed, `getSession` null; a late set with no end never creates history —
       `test/watch_session_import_test.dart` (extends the D-133/D-136 groups; driver
       `WatchSessionImporter.apply`, :131).
4. [ ] Assert `_mergeHeld`'s missing-row consume covers the discard-deleted row (`apply` with
       `phoneOwnsSession: true` on a session whose row is gone → consume, no re-create;
       `lib/core/services/watch_session_importer.dart` `_mergeHeld` :329-332) — same test file, the
       held-merge group. If it would re-create instead, record it in the Assumption Log and fix in
       this phase.
5. [ ] Assumption Log entries for every silent choice (the strict `<` on instants; reusing
       `discardCurrentSession` for the delete; the fate memory left as announced).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (issue count ≤ the
181 baseline, no new errors); `.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart`.
**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`,
`test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`.

### Phase 2: the twin and the contract restore the instant rule (@developer) — BLOCKED by Phase 1 (S-14630's delete and the twin's flip are one rule)
1. [ ] Remove the interim: in `_applyLifecycle`'s terminal branch delete the
       `if (status != WatchSessionStatus.completed || session.status != WatchSessionStatus.abandoned)`
       skip so the earlier-instant comparison and the tie apply to abandon-vs-complete —
       `lib/watch/session/watch_session_engine.dart` (`_applyLifecycle`, ~736; skip ~766-776) —
       D-14630.
2. [ ] Re-work A-146-15's three engine tests (they pin completion-beats-discard-whatever-the-instants)
       to the restored rule; keep the tie cases green — `test/watch_session_engine_test.dart`
       (the S-14512/terminal group, A-146-15's tests).
3. [ ] New engine tests S-14640 and S-14641 (both arrival orders) — same file.
4. [ ] Re-point S-14512's expectation: under the harness's clocks the wrist's discard reads earlier, so
       the pair converges on `abandoned` with the phone's row deleted —
       `test/watch_convergence_harness_test.dart` (the `S-14512` test).
5. [ ] Create `watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json` (the S-14642
       fixture, exact values above) and add its manifest row directly after the `ended_is_final.json`
       row — `watch/sync_protocol/fixtures/manifest.json` (:1035).
6. [ ] PROTOCOL.md: extend the lifecycle bullet (:690-713) with one sentence — a discard that wins
       deletes the workout on the phone's side (history), and the wrist's copy of such a workout reads
       `abandoned` — and append the version-history row after :913 (format
       `| 1 (amended) | 2026-11-12 | … |`), naming the new fixture and the walkers
       (`test/sync_protocol_fixtures_test.dart` S-004, `SyncProtocolFixturesTests.swift`) —
       `watch/sync_protocol/PROTOCOL.md`.
7. [ ] Cross-stack tests S-14643 (both arrival orders, phone + wrist asserted together) —
       `test/watch_reconciliation_cross_stack_test.dart` (extends the D-14601-as-amended tie group).
8. [ ] Assumption Log entries: the reconciler verified no-change (`_incomingEndWins` :226-241 already
       instant-based); the new fixture instead of an in-place `ended_is_final.json` amendment (see
       Open questions); the harness-clock reading of S-14512.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/sync_protocol_fixtures_test.dart test/watch_reconciliation_cross_stack_test.dart test/docs_indexing_contract_test.dart` (PROTOCOL.md stays under the 64 KiB doc cap; S-004 walks the new fixture).
**Predicted Files**: `lib/watch/session/watch_session_engine.dart`,
`test/watch_session_engine_test.dart`, `test/watch_convergence_harness_test.dart`,
`watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json`,
`watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`,
`test/watch_reconciliation_cross_stack_test.dart`.

### Phase 3: the Swift engine obeys the same rule (@developer) — BLOCKED by Phase 2 (the fixture must exist first)
1. [ ] Remove the interim in `applyLifecycleExclusive` (the
       `if status != WatchSessionStatus.completed || session.status != WatchSessionStatus.abandoned`
       skip) so the earlier-instant comparison and `incomingEndWinsATie` apply to
       abandon-vs-complete — `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
       (`applyLifecycleExclusive`, :803; skip :826-833) — D-14630.
2. [ ] Verify `applySnapshotExclusive` carries no interim (instant + tie at :612-625) and record the
       verification — same file — expected no change.
3. [ ] Re-work any `WatchEndedIsFinalTests.swift` case that pins the interim; add the both-orders
       cases (S-14650) — `watch/watchos/Tests/WatchSessionEngineTests/WatchEndedIsFinalTests.swift`.
4. [ ] Run the fixture walker over the new fixture (S-14651) —
       `watch/watchos/Tests/WatchSessionEngineTests/WatchLiveMirroringTests.swift`
       `testEveryReconciliationFixtureConverges` — no edit predicted; a red here is a fixture bug or a
       Phase 3 item 1 miss, not a walker change.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (all green; the new fixture
walked); `.github/copilot/scripts/macos/gateway.sh lint`.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchEndedIsFinalTests.swift`.

### Phase 4: O-6 proof and the sweep's new shape (@developer) — BLOCKED by Phases 1-3
1. [ ] Importer test (S-14660's importer half): the wrist's own completed session (with one set)
       imports as its own finished workout while `phoneOwnsSession` is false for it and the phone holds
       another session — `test/watch_session_import_test.dart` (new test `O-6 the wrist's own workout
       is its own finished row`, driver `WatchSessionImporter.apply`, :131) — predicted green (the
       `_createSession` path, `_Pass.run` → `_createSession`, exists); a red fixes at the confirmed
       seam with an Assumption Log entry.
2. [ ] Pair-harness scripted trace S-14660: the phone holds p1 open, the wrist free-starts w2, both
       stay open, the wrist finishes w2, heal, settle — `test/watch_convergence_harness_test.dart`
       (new test `S-14660 …`), asserting p1 still active, w2 a finished row with its set, nothing
       deleted.
3. [ ] Re-run the sweep and the soak; move `knownClasses['status']`'s text to the measured owner (or
       "closed") and set `shippingRatchet` to the newly measured rate —
       `test/watch_convergence_random_test.dart` (`knownClasses` :171-191, `shippingRatchet` :204) —
       S-14661.
4. [ ] Shrink-and-classify `absorbing` (seed 111 first): replay under the FULL action space, run the
       Shrinker, and record a minimal trace with the defect classified, or the no-trace finding with
       the first step for the next PR — `test/watch_convergence_random_test.dart` (`Shrinker`,
       `ConvergenceRun.replayActions`) — output to the evidence file (S-14662). The fix itself is
       deferred until classified.
5. [ ] Shrink-and-classify `entries` (11/2000): the same method, same file, output to the evidence file
       (S-14662) — deferred until classified.
6. [ ] Shrink seed 1814 (`timers`) and classify the seam; if the confirmed seam is `endSession`'s live
       rest, fix it (stop the live rest in memory after `persistOpenRests`, mirroring D-14603c) and add
       the regression test S-14663 — `lib/state/workout/session_core_lifecycle.dart` (`endSession`,
       :14-62), `test/watch_session_finish_test.dart` — D-14635; a different seam is recorded and
       deferred.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` (green);
`.github/copilot/scripts/macos/gateway.sh test test/watch_convergence_random_test.dart --dart-define=CONVERGENCE_SEEDS=2000` (green; the ratchet holds);
if item 6 fixed: `.github/copilot/scripts/macos/gateway.sh test test/watch_session_finish_test.dart` (green);
`.github/copilot/scripts/macos/gateway.sh lint` (≤181). Heal-stall seeds (184, 187, 548, 660, 671, 915,
1058, 1097, 1648) are the known flake — rerun individually before blaming a change.
**Predicted Files**: `test/watch_session_import_test.dart`,
`test/watch_convergence_harness_test.dart`, `test/watch_convergence_random_test.dart`,
`docs/plans/2026-11-12-146c-earlier-discard-wins-plan/2026-11-12-146c-earlier-discard-wins-plan.evidence.md`,
(item 6 only) `lib/state/workout/session_core_lifecycle.dart`, `test/watch_session_finish_test.dart`.

### Phase 5: Health re-write after an end-time move (@developer) — BLOCKED by Phase 1; runs last (owner: "we can do it at the end"; owner to confirm)
1. [ ] `HealthSyncService.rewriteWorkout(TrainingSession session, {required int previousEndedAtMs})`:
       delete the workouts in `[startedAtMs, max(previousEndedAtMs, endedAtMs)]` (one window covers the
       old write), clear the effort in the same window, write the new draft
       (`_activityKindOf` reused), re-rate when `sessionFeeling` maps; never touch the ledger —
       `lib/core/services/health_sync_service.dart` (new method after `onSessionCompleted`, :104) —
       D-14634.
2. [ ] Trigger on the phone's catch-up: `catchUpEndedSession` calls `_healthSync?.rewriteWorkout` when
       the end actually moved (it already has `_activeEnergy` beside it) —
       `lib/state/workout/session_core_lifecycle.dart` (`catchUpEndedSession`, :223).
3. [ ] Trigger on the importer's catch-up: `_catchUpEnd` reports the move (a new `WatchSessionImport`
       field, e.g. `endMovedFromMs`), and `WatchSessionInbox._settleNow` calls
       `_healthSync?.rewriteWorkout` for it (the inbox already holds `_healthSync` for ratings) —
       `lib/core/services/watch_session_importer.dart` (`_catchUpEnd`, :661; `WatchSessionImport`,
       :34), `lib/state/watch/watch_session_inbox.dart` (`_settleNow`, :467).
4. [ ] Tests S-14670 and S-14671 (one workout after a move and after two moves; a never-written session
       writes nothing) — `test/health_platform_test.dart` (the `HealthSyncService` group, the pattern
       at :177).
5. [ ] Assumption Log entries + the owner-confirmation note (this phase is vetoable as a whole; if the
       owner defers it, it moves to its own follow-up PR with D-14634 and S-14670/S-14671 unchanged).

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/health_platform_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart`.
**Predicted Files**: `lib/core/services/health_sync_service.dart`,
`lib/state/workout/session_core_lifecycle.dart`, `lib/core/services/watch_session_importer.dart`,
`lib/state/watch/watch_session_inbox.dart`, `test/health_platform_test.dart`,
`test/watch_session_import_test.dart`.

## Files Affected (whole PR 3)

- Phone: `lib/state/watch/watch_session_adoption_bridge.dart`,
  `lib/core/services/watch_session_importer.dart`, `lib/state/watch/watch_session_inbox.dart`,
  (`lib/state/workout/session_core_lifecycle.dart` — Phase 4 item 6 and Phase 5 item 2),
  `lib/core/services/health_sync_service.dart`.
- Dart twin: `lib/watch/session/watch_session_engine.dart` (the interim removal only).
- Swift: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`,
  `watch/watchos/Tests/WatchSessionEngineTests/WatchEndedIsFinalTests.swift`.
- Contract: `watch/sync_protocol/PROTOCOL.md`,
  `watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json` (new),
  `watch/sync_protocol/fixtures/manifest.json`.
- Tests: `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`,
  `test/watch_session_engine_test.dart`, `test/watch_convergence_harness_test.dart`,
  `test/watch_reconciliation_cross_stack_test.dart`, `test/watch_convergence_random_test.dart`,
  `test/watch_session_finish_test.dart`, `test/health_platform_test.dart`.
- Read-only dependents (read a touched surface, change nothing): the calendar/stats/day-list screens
  (duration derives on the fly), `watch_session_auto_push.dart` (its announced fates are untouched),
  `docs/state_management/watch_surface_transport.md` (plan 146's Phase 5 owns it — do not touch here).

## Notes

- **Phase dependency graph**: 1 → 2 → 3 → 4 → 5. Phase 2 needs Phase 1 only because S-14630's delete
  and the twin's flip are the two halves of one rule — landing them apart would leave the pair
  diverging on the sweep. Phase 3 needs Phase 2's fixture. Phase 4 needs all three (the sweep measures
  the whole rule). Phase 5 needs Phase 1 (the same catch-up point) and is otherwise independent — if
  the owner defers it, Phases 1-4 close PR 3 alone.
- **Predicted intermediate states**: after Phase 1 the phone deletes on an earlier discard but the
  twin still pins the interim, so the convergence files' `status` class may move unpredictably — do
  not measure the sweep before Phase 3. After Phase 3 both stacks agree; Phase 4 measures and sets the
  ratchet. Phase 5 changes no convergence behaviour.
- **Legacy handling**: none (pre-release, owner decision in plan 146).
- **The harness's clock skew and this rule**: the harness stamps the wrist's own actions with a
  TestClock (2026-11-10) and the phone's frames with the device clock (2026-11-12) — A-146-15. After
  the interim is removed, the sweep's scripted order stops mattering for abandon-vs-complete pairs:
  the wrist's discard always reads earlier, so both sides converge on `abandoned`/deleted. That is the
  rule working under accepted skew, not a defect; the ratchet absorbs it (Open question 4).
- **S-14512**: its "both sides read completed" expectation was the interim's product. Under the owner's
  rule and the harness's clocks it re-points to "both sides converge on `abandoned` with the phone's
  row deleted" (Phase 2 item 4). Its scenario number and its role as a re-measure are unchanged.

## Progress

- [ ] Phase 1: the phone obeys the owner's rule (@developer)
- [ ] Phase 2: the twin and the contract restore the instant rule (@developer)
- [ ] Phase 3: the Swift engine obeys the same rule (@developer)
- [ ] Phase 4: O-6 proof and the sweep's new shape (@developer)
- [ ] Phase 5: Health re-write after an end-time move (@developer)

## Assumption Log

*(executors append: decision made, options considered, choice + why — each entry at most 3 lines.
Conductor marks each RATIFIED (promote to a D-x) or REVERT (remediation).)*

- **A-146c-01 (planner, Phase 2 item 5): a NEW fixture instead of amending `ended_is_final.json` in
  place.** The brief says "ended_is_final.json amendment + manifest"; read as amending the fixture
  family. `ended_is_final.json`'s stream is abandoned-first and already complies; amending it would
  change its meaning and name. The new rule's new case (completed first, earlier abandon second) gets
  its own file, `discard_before_finish.json`, registered in the manifest — vetoable.
- **A-146c-02 (planner, Phase 2 item 4): S-14512 is re-pointed, not left green.** Its both-completed
  expectation is the A-146-15 interim's product; the owner's rule plus the harness's clocks make the
  pair converge on abandoned/deleted. The executor verifies against the actual harness clocks before
  writing the new expectation.
- **A-146c-03 (planner, Phase 4 items 1-2): O-6 is predicted to already work.** The machinery cited in
  D-14633 exists end to end; the tests are proofs, not fixes. A red is a finding, fixed at its seam.
- **A-146c-04 (planner, Phase 4 items 4-5): absorbing and entries are deferred, not planned as fixes.**
  Both classes have no minimal trace under `kShippingActions` (A-146-25); planning a fix without a
  reproduction would be a guess. The phase plans the shrink-and-classify step only.

## Feedback

*(empty — fold into a new Iteration block when non-empty, then clear)*
