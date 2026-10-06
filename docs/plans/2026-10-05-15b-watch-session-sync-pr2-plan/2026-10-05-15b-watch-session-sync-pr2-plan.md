# Feature: watch-session-sync PR 2a — a set logged on the watch reaches the session the phone holds

> Status: DRAFT awaiting the owner's answers (`## Open questions`) — planning only, no code
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`. Area docs:
> `docs/watch_session_sync.md`, `docs/watch_session_capture.md`, `docs/state_management/watch_surface.md`
> Series: `docs/plans/2026-10-05-15-watch-session-sync-index.md`. This is **PR 2a**, the first of the
> two slices PR 2 was split into; PR 2b (the wrist logging surface) is planned when its turn comes
> (`.github/copilot/pr-scope-budget.md`, "Over budget at planning time").
> Builds on PR 1 — `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/2026-10-05-15a-watch-session-sync-pr1-plan.md`
> (Ledger D-1…D-12, goals G1–G3, assumptions A21/A24/A30/A33). Read it; this plan never restates it.

## Overview

PR 1 gave the phone and the wrist one shared in-progress session and left one deliberate gap, its
**G3**: a set logged on the wrist in a session the phone holds — the wrist's own session, adopted by
the phone at a mid-session Sync — is staged in the inbox and never merged. The phone applies that
session's end, its rating and its summary, and none of its sets.

**What the owner sees if this is not fixed first.** Start a session on the watch, tap **Sync** so the
phone joins it, log three sets on the watch, finish on the watch and sync again. The phone's history
entry for that session shows the duration and the rating and **none of the three sets** — they stay on
the watch, unacknowledged, for ever. That is the state PR 2b (the wrist logging surface) would ship
into, which is why this slice goes first.

This PR closes the gap: every staged wrist row for a session the phone holds is merged into that
session as it arrives, with no wrist end and no further sync needed. It is **inert on its own** — the
wrist shell has no logging screen yet, so no real handset stages an effort row until PR 2b lands, and
the automated tests are the only observer. It changes no wire shape (D-20).

## Resolved Decisions (Ledger)

Immutable. Changes are new superseding entries (`D-nn supersedes D-nn`), never edits.

| # | Decision |
|---|---|
| **D-13** | **The merge trigger.** Every staged, unapplied wrist row for the session the phone holds is merged when it is staged, and needs no `session_end` to run. The phone holds a session when `WatchSessionAdoptionBridge.holdsSession(sessionId)` is true — `WorkoutState.currentSession?.id == sessionId`, whether that session is running or already ended. A session the phone does not hold is untouched by this rule and stays with the import path (PR 1's D-131/D-132/D-133, unchanged). |
| **D-14** | **Which effort a row lands in.** A wrist effort row's effort is the session's effort whose row id equals the row's `sessionExerciseId`, because the phone's effort row id IS the slot id (D-3) — true of a session the phone created and of one it adopted (`WatchSessionAdoptionBridge._slotFor`, `_adopt`). When the session holds no such effort the row is **acknowledged and dropped**: a merge never creates a session, a segment or an effort, and never a second effort for a slot. |
| **D-15** | **Order, identity, and the phone's own rows.** Merged entries order by the row's `loggedAt`, then by `entryId` (PR 1's D-134), and are identified by `entryId`: a redelivery of a row the merge already used writes nothing (an applied row is no longer a candidate). The metrics a row becomes are the phone's own for its kind — the import's `_createEntry` rules, with `exerciseHasLoad` read from the session's exercise, so a bodyweight movement's load lands in `extra-weight` exactly as the phone's own logging puts it. Entries the phone logged in that effort are the user's (A-51): none of them is moved, edited or deleted. Merged entries order among themselves by `loggedAt` and land after the effort's last entry in logged order; the user's rows keep their positions and their stamps. |
| **D-16** | **Corrections and deletions keep working.** The merge writes through the same `LoggedEntryRows` primitives the import uses, so `_EffortRows.read` recognises a merged entry as the importer's own: a staged correction edits only the fields it names, stamped with the correction's staging time (D-137), and an entry the phone deleted is dropped and acknowledged, never re-created (D-136). |
| **D-17** | **The phone's live screen.** A merge writes through `WorkoutRepository` and then refreshes only the efforts it wrote, on the phone's live session state — never a whole-session reload, so a timer running on the phone keeps running (`SessionCoreIOMethods.loadSessionData` clears both timer managers and is not a refresh). It reports a history change through the existing `onHistoryChanged` signal exactly when it wrote a row. |
| **D-18** | **Acknowledgement.** Every row the merge looked at — placed, dropped as deleted, or skipped for a slot the session does not have — is marked applied and named in the receipt, so the wrist may forget it. Nothing a held session's merge has seen stays staged. |
| **D-19** | **The rating, the summary, the end.** For a held session the pass keeps PR 1's behaviour exactly: it tops the rating up (D-8/D-138 — the phone's own rating wins, the wrist's applies only while the session has none) and attaches the wrist's session summary when the wrist's `session_end` is staged. The wrist's `session_end` for a held session never creates a session and never changes that session's end (G2, D-5): the phone's own end stands, and the wrist's end is the wrist's own truth about its own session. |
| **D-20** | **No protocol change, no new id scheme.** This PR adds no message, field or id: the wrist already sends what it logs (`observations_up` with D-3 ids) and the merge resolves rows onto the efforts the session already has. The wire shape stays PR 1's, checked against `watch/sync_protocol/PROTOCOL.md` and `watch/sync_protocol/fixtures/`. |

## Feature Invariants

Only the invariants that bite here. Project-wide rules stay in `docs/global_conventions.md`.

- **A merge never invents structure.** No session, segment or effort is created; no effort is
  duplicated for a slot (D-14). Verified by S-12.
- **History is a function of staged rows, not of arrival order or delivery count** — the importer's
  library rule. The same rows, in any order, delivered any number of times, produce the same rows
  (D-15). Verified by S-10.
- **The phone's own rows are the user's** (A-51): a merge never moves, edits or deletes them (D-15).
  Verified by S-11.
- **Implementation parity.** `HiveWorkoutRepository` and `MockWorkoutRepository` produce the same rows
  for the same staged input. Verified by the Mock and Hive groups of `test/watch_session_merge_test.dart`.
- **Layer boundary.** The merge lives in `lib/core/services/` and `lib/state/watch/` and reaches
  storage only through `WorkoutRepository`; nothing under `lib/state`, `lib/features`, `lib/widgets`
  or `lib/core` imports a concrete repository.
- **A finished session is never resurrected** (G1) and a session the user deleted stays deleted
  (D-136). Verified by S-12 and S-14.

## Requirements

- **R1** A wrist effort row staged for a session the phone holds becomes a row in that session, in
  logged order, without waiting for the wrist's end or another sync.
- **R2** A redelivery of a row the merge already used writes nothing new, and is acknowledged again.
- **R3** The phone's own rows in that session are never moved, edited or deleted by a merge.
- **R4** A row for a slot the session does not have is acknowledged and dropped; no session, segment
  or effort is ever created by a merge.
- **R5** The phone's live session screen shows a merged row, and a timer running on the phone is not
  stopped by the merge.
- **R6** A correction or a deletion the phone stages reaches a merged row exactly as it reaches an
  imported one.
- **R7** Everything PR 1 does for a session the phone does not hold is unchanged: import on end,
  rating top-up, summary attach, the D-10 conflict guard, the silent phone finish (G2), G1.

## Acceptance Criteria

| # | Criterion | Scenario | Test |
|---|---|---|---|
| AC1 | A wrist set for a held session becomes an entry in the session's own effort | S-9 | `watch_session_merge_test.dart` |
| AC2 | Redelivery writes nothing new and is acknowledged again | S-10 | same |
| AC3 | The phone's own rows stay exactly as they were | S-11 | same |
| AC4 | A row for a slot the session lacks is acknowledged and dropped | S-12 | same |
| AC5 | A correction reaches a merged row's named fields only | S-13 | same |
| AC6 | A merge into an already-ended held session still lands, and reports history | S-14 | same |
| AC7 | The wrist's end and rating for a held session keep PR 1's outcome, plus the sets | S-15 | same |
| AC8 | The live screen refreshes the touched effort and keeps a running timer | S-16 | same |
| AC9 | A session the phone does not hold still imports on its end with its entries | S-17 | `watch_session_import_test.dart` (regression) |
| AC10 | No reader of the replaced representation is left: PR 1's G3 assertions are rewritten, not deleted | S-18 | `watch_session_finish_test.dart` |
| AC11 | Sets logged while the phone was out of reach land in logged order, once | S-19 | `watch_session_merge_test.dart` |

## Existing-Functionality Impact

Every row carries the grep that found its readers. "Unaffected" is not claimed anywhere.

| Touched surface | What already reads it (the grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchSessionImporter.apply(phoneOwnsSession:)` | `grep -rn "phoneOwnsSession" lib test` → the inbox's one production call (`watch_session_inbox.dart:419`), the wiring (`watch_sync_wiring.dart:137`, `adoption.holdsSession`), `test/watch_session_finish_test.dart:125` | the held branch stops narrowing to `_sessionScopedKinds` and merges the effort rows instead | S-9, S-15, S-18 |
| Staged `WatchInboxEntry` rows and `markWatchInboxEntriesApplied` | `grep -rn "markWatchInboxEntriesApplied" lib test` → the importer (`:242`) and `test/watch_capture_repository_parity_test.dart` | effort rows PR 1 left staged are now applied and receipted | S-9, S-12, S-15 |
| `WatchSessionImport.historyChanged` → the calendar | `grep -rn "historyChanged\|onHistoryChanged" lib` → the inbox collects it (`:422`) and calls the hook once (`:444`); `lib/main.dart:376` is `calendarState.refresh` | a merge that writes a row refreshes the calendar, as an import does | S-14 |
| `WorkoutState`'s live session rows (the session screen) | `grep -rn "loadSessionData" lib` → `workout_state.dart:137`, `session_core_io.dart:131` | the merge refreshes only the efforts it wrote, because a full reload clears the phone's running timers | S-16 |
| The wrist's retry of unacknowledged rows | `grep -rn "pendingObservations" watch/watchos/Sources` → `WatchSessionEngine`, `WatchSyncOrchestrator.sync` | a merged or dropped row is receipted, so the wrist stops re-sending it | S-9, S-12 |
| `_sessionScopedKinds` and the "the merge PR 3 owns" comments | `grep -rn "sessionScopedKinds\|PR 3" lib/core/services/watch_session_importer.dart` | deleted; the deferred merge is this PR (S-18 is the residue sweep) | S-18 |

Docs that read the old behaviour and must change with it: `docs/watch_session_sync.md` (the
"one session id, one row" invariant and the three "What does not sync" bullets) and
`docs/state_management/watch_surface.md:455` (the `G3` test reference in `WatchIncomingRouter`).

## Scenarios

**Base fixture** (every scenario starts here unless it says otherwise). The phone holds session
`s-w1`, created by the phone and in progress: one segment `seg-1`, efforts `sl-1` (kind `set`,
exercise `ex-1`, capabilities `reps` + `load`) and `sl-2` (kind `set`, exercise `ex-2`, capabilities
`reps` + `load`), both with no entries. The wrist's ladder for `s-w1` is those two slots, so its rows
carry `sessionExerciseId: sl-1` / `sl-2`. Inbox rows are `origin: watch` with `appliedAtMs: null`
unless the scenario says otherwise. `T1 < T2 < T3` are distinct millisecond stamps.

### S-9: a wrist set reaches the live phone session
- **Fixture:** base, plus one staged row `sx-1` (`kind: set`, `sessionExerciseId: sl-1`,
  `exerciseId: ex-1`, `reps: 8`, `loadKg: 40`, `loggedAt: T1`).
- **Trigger:** the row is staged (an `observations_up` for `s-w1` arrives at the inbox).
- **Flow:** the inbox settles `s-w1`; the merge places `sx-1` under `sl-1`; the phone's session state
  refreshes `sl-1`.
- **Expected outcome:** `sl-1` holds exactly one entry — `obs-sl-1-0-reps` = 8 and
  `obs-sl-1-0-weight` = 40 (`LoggedEntryRows.observationId`); `sx-1` is applied; the receipt names
  `sx-1`; the session screen shows the set. No new session, segment or effort exists.
- **Edge case of:** none.

### S-10: a redelivery, and a second set
- **Fixture:** base, plus `sx-1` (as S-9), then the same row staged again, then `sx-2`
  (`sl-1`, `reps: 10`, `loadKg: 45`, `loggedAt: T2`).
- **Trigger:** each staging settles.
- **Expected outcome:** `sl-1` holds exactly two entries, entry 0 from `T1` and entry 1 from `T2`;
  no duplicate rows and no second effort; both rows applied; the second receipt names only what was
  not already receipted.
- **Edge case of:** S-9.

### S-11: the phone's own rows are the user's
- **Fixture:** base with `sl-1` already holding one phone-logged entry (index 0, `T2`) and a
  manual entry the user added (index 1, `T3`), plus `sx-1` (`sl-1`, `reps: 8`, `loggedAt: T1` —
  earlier than both).
- **Trigger:** `sx-1` is staged.
- **Expected outcome:** both phone rows keep their ids, their values, their order and their stamps;
  `sx-1` lands **after** the last of them; nothing is edited or deleted (A-51).
- **Edge case of:** S-9.

### S-12: a slot the session does not have
- **Fixture:** base with `sl-2` removed from the phone's session (the user deleted the exercise),
  plus `sx-3` (`sessionExerciseId: sl-2`, `reps: 12`, `loggedAt: T1`) and `sx-4`
  (`sessionExerciseId: sl-9`, an exercise the phone never had, `loggedAt: T1`).
- **Trigger:** both are staged.
- **Expected outcome:** both are applied and named in the receipt; `sl-1` is untouched; no effort
  `sl-2` or `sl-9` exists; no session or segment is created; the calendar holds no new entry; the
  wrist is told to forget both.
- **Edge case of:** S-9 (the destructive half).

### S-13: a correction on a merged row
- **Fixture:** as S-9 after the merge, plus a staged `phone_correction` row naming `sx-1` with
  `reps: 12`, staged at `T2`.
- **Trigger:** the correction is staged.
- **Expected outcome:** only `obs-sl-1-0-reps` changes (to 12) and only it is stamped `T2`; the
  weight row keeps its value and its `T1` stamp (D-137); the correction row is applied.
- **Edge case of:** S-9.

### S-14: the phone finished first
- **Fixture:** base with the phone's session `s-w1` ended (`endedAtMs` set, one history row), plus
  `sx-1` (`sl-1`, `reps: 8`, `loggedAt: T1`) and `sx-2` (`sl-1`, `reps: 10`, `loggedAt: T2`).
- **Trigger:** the rows are staged after the phone's finish.
- **Expected outcome:** both land in `sl-1` in order; the session stays ended (G1); the history
  signal fires so the calendar refreshes; both rows are receipted.
- **Edge case of:** S-9 (the ended half).

### S-15: the wrist's end and rating, with sets behind them
- **Fixture:** base, plus `sx-1` (`sl-1`, `reps: 8`, `loggedAt: T1`), `end-s-w1` (`status:
  completed`, `endedAt: T2`, `avgHeartRateBpm: 140`, `maxHeartRateBpm: 165`) and `rating-s-w1`
  (value 4), all staged.
- **Trigger:** the rows are staged.
- **Expected outcome:** `sx-1` is an entry of `sl-1`; the session's rating becomes 4 (it had none);
  the session's summary is attached; the session's own end is unchanged; all three rows are applied
  and receipted — the wrist may forget the set, which PR 1 kept staged for ever.
- **Edge case of:** S-9 (the rating half, D-19).

### S-16: the screen, and the running timer
- **Fixture:** as S-9, plus the phone's session has an open rest record on `sl-1` (a rest timer
  running).
- **Trigger:** `sx-1` is staged.
- **Expected outcome:** the phone's state notifies once for `sl-1` and the merged row is visible; the
  rest record is unchanged and still open; no `clearAll` ran (D-17).
- **Edge case of:** S-9 (the live-state half).

### S-17: a session the phone does not hold is untouched
- **Fixture:** base's `s-w1` is *not* the phone's current session (the phone holds another, or
  none); staged `sx-1` (`sl-1`, `reps: 8`, `loggedAt: T1`), `end-s-w1` (completed, `endedAt: T2`)
  and `rating-s-w1` (4).
- **Trigger:** the rows are staged.
- **Expected outcome:** the ordinary import runs: one history entry for `s-w1` with the entry the
  wrist logged, the rating 4, the summary attached, everything receipted. Identical to PR 1's
  outcome for the same fixture.
- **Edge case of:** none — this is the regression that proves the merge did not swallow the import.

### S-18: no reader of the replaced behaviour remains
- **Fixture:** the repository's own tests, plus `grep -rn "sessionScopedKinds\|the merge PR 3 owns"`
  over `lib/` and `grep -rn "not merged\|staged and stay staged"` over `docs/`.
- **Trigger:** the sweep runs at the end of Phase 3.
- **Expected outcome:** the grep returns nothing; `test/watch_session_finish_test.dart`'s G3
  assertions have been rewritten to the merged outcome under a new name, and every doc reference to
  the old test name and the old behaviour is updated (not deleted).
- **Edge case of:** none.

### S-19: a set logged while the phone was out of reach
- **Fixture:** base, plus `sx-1` (`sl-1`, `reps: 8`, `loggedAt: T1`) and `sx-2` (`sl-1`, `reps: 10`,
  `loggedAt: T3`), both staged at the same settle, after the phone had been unreachable since `T1`.
- **Trigger:** the settle that delivers both at once.
- **Expected outcome:** both land in `sl-1` in `loggedAt` order (`T1` then `T3`) — arrival time never
  decides order; both are applied and receipted; nothing is lost or duplicated.
- **Edge case of:** S-10 (the delivery-order half, D-15).

## Iteration 1

Phases are ordered; 1 and 2 may swap, but Phase 3 closes the PR either way. No phase needs a
simulator, `xcodebuild` or a Swift build: this PR touches no Swift.

### Phase 1: the merge pass (@developer)
1. [x] In `lib/core/services/watch_session_importer.dart`, give `apply` a held branch: when
       `phoneOwnsSession` is true, hand the session's staged rows to a new merge pass and return,
       **before** the `endRow == null` early return — a wrist set arrives before its end and must
       not wait for one (D-13).
2. [x] The merge pass: candidates are the session's unapplied `origin: watch` effort rows, parsed
       through `_Entry.parse(row, corrections)`; drop the ones a staged `phone_deletion` names
       (D-16); group the rest by `sessionExerciseId`; resolve each group's effort by row id (D-14);
       place with the import's own primitives (`_EffortRows.read`, `_placeAroundUserRows`,
       `_createEntry`) under the **existing** effort id, never `effortIdFor(...)` (D-14/D-15).
3. [x] A group whose effort the session does not have is applied and dropped — no effort is created
       (D-14).
4. [x] Keep the held session's rating top-up and summary attach exactly as they are (D-19), and mark
       every row the pass looked at applied, returning them in `appliedEntryIds` (D-18).
5. [x] Add `changedEffortIds` to `WatchSessionImport` (default empty; the import path leaves it
       empty) and fill it from the merge (D-17) — per group, off a write **count** rather than the
       pass's overall flag, which a rating applied earlier in the same pass has already set.
6. [x] Delete `_sessionScopedKinds` and its "PR 3 owns the merge" comments (S-18's target).
7. [x] Write `test/watch_session_merge_test.dart`: a Mock group and a Hive group over the same
       fixtures for S-9…S-13 and S-19, plus S-14 (the phone's session already ended) and D-17 (the
       efforts a merge names), plain `test()`, wired the way `createWatchSync` wires them
       (`adoption.holdsSession` as `phoneOwnsSession`, a real `WorkoutState`, `MockWorkoutRepository`
       / Hive). Run the Mock group first: a red Mock group leaves a Hive group hanging behind it.
8. [x] Prove the bug-fix test fails without the fix: with `apply`'s held branch reverted, S-9's
       assertions must fail (paste the failure in `<plan>.evidence.md`).

**Phase 1 result:** items 1–8 done. 16 new tests green (Mock `+8`, file `+16`); the six Mock
scenarios shown red with the held branch reverted, and D-17 shown red with the write count reverted;
`test/watch_session_finish_test.dart` rewritten per the override (`+8`); import + parity + finish
`+90`; full suite `+3901 ~1`, 0 failures (baseline `+3885 ~1`); lint 196 issues / 0 errors. Details in
`<plan>.evidence.md`.

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh lint` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_merge_test.dart` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart test/watch_capture_repository_parity_test.dart`

**Predicted Files**: `lib/core/services/watch_session_importer.dart`,
`test/watch_session_merge_test.dart`, `docs/plans/2026-10-05-15b-watch-session-sync-pr2-plan/2026-10-05-15b-watch-session-sync-pr2-plan.evidence.md`

### Phase 2: the live screen and the wiring (@developer)
1. [x] Add `refreshEfforts(Iterable<String> effortIds)` to `SessionCoreIOMethods`
       (`lib/state/workout/session_core_io.dart`): re-read each effort's observations, its round or
       timed instances by kind, its entry rests and the exercise cache entry, then `_notify()` — no
       `clearAll`, so a running timer survives (D-17). Expose it on `WorkoutState` beside
       `loadSessionData`.
2. [x] Give `WatchSessionAdoptionBridge` a method that refreshes the efforts a merge wrote when it
       holds the session (`holdsSession(sessionId)` → `refreshEfforts`), and hand it to the inbox.
3. [x] Give `WatchSessionInbox` an `onSessionRowsChanged(sessionId, effortIds)` hook, called from
       `_settleNow` once per session whose pass reported `changedEffortIds` (D-17), and wire it in
       `createWatchSync` (`lib/state/watch/watch_sync_wiring.dart`).
4. [x] Extend `test/watch_session_merge_test.dart` with S-14 (the ended session and the history
       signal), S-15 (the end + rating + sets) and S-16 (the refresh and the untouched rest record).
       S-14 landed in Phase 1; S-15 is covered by Phase 1's override of
       `test/watch_session_finish_test.dart`, whose case runs S-15's exact fixture (A-32).
5. [x] Add S-17 to `test/watch_session_import_test.dart` (or a named case in the merge test file) as
       the regression that a session the phone does not hold still imports unchanged (R7).

**Phase 2 result:** items 1–5 done. 4 new tests ×2 groups = 8 green (`Mock +12`, merge file `+26`,
merge + import `+69`); all four guards shown red by mutation (whole-session reload, `clearAll`,
dropped `holdsSession`, unconditional hook) plus S-17 red with the merge taking every session; full
suite `+3909 ~1`, 0 failures (Phase 1's frozen `+3901 ~1`); lint 196 issues / 0 errors. Details in
`<plan>.evidence.md`.

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh lint` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_merge_test.dart test/watch_session_import_test.dart` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_finish_test.dart` — Phase 1's
override already rewrote its G3 assertions, so it is green (`+8`), not red; observed and recorded in
the evidence file

**Predicted Files**: `lib/state/workout/session_core_io.dart`, `lib/state/workout/workout_state.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/watch/watch_session_inbox.dart`,
`lib/state/watch/watch_sync_wiring.dart`, `test/watch_session_merge_test.dart`,
`test/watch_session_import_test.dart`, `<plan>.evidence.md`

### Phase 3: PR 1's assertions, the docs, the sweep (@developer)
1. [x] Rewrite `test/watch_session_finish_test.dart`'s G3 assertions to the merged outcome: the wrist's
       sets are now rows under the phone's own effort, are receipted, and the redelivery is still one
       row. Rename the case so it says what it now proves (`a set logged on the watch lands in the
       session the phone holds`), and update the file's header scenario map.
       **Result: done in Phase 1 by the governor override (A-21); this phase confirmed it and removed
       one duplicated header-map line the override had left (A-36).**
2. [x] `docs/watch_session_sync.md`: replace the "one session id, one row" invariant's "the effort
       rows stay staged, unreceipted" clause with the merge, rewrite the three "What does not sync"
       bullets that read "not merged" / "staged and stay staged" / "attached only where the importer
       places an effort", and update every `Verified by` reference to the new test names.
       **Result: the row becomes a row of the effort the session already has, under the slot's row id
       (D-14), and is receipted; the three false bullets are gone; every `Verified by` names an
       existing test.**
3. [x] `docs/state_management/watch_surface.md:455`: update the `G3` reference in the
       `WatchIncomingRouter` section to the new test name and outcome.
       **Result: the reference now reads "the wrist's set merging into the session the phone holds —
       `a set logged on the watch lands in the session the phone holds`".**
4. [x] Residue sweep (S-18): `grep -rn "sessionScopedKinds\|the merge PR 3 owns" lib/` and
       `grep -rn "not merged\|staged and stay staged" docs/` both return nothing; paste both results
       in the evidence file.
       **Result: both spellings are gone from the importer and from the docs set; the only
       `sessionScopedKinds` left is the mirror's live constant, scoped out per A-25. Pasted in the
       evidence file.**
5. [x] Update the Progress and Assumption Log sections of this plan; write nothing else into it.
       **Result: done (A-35–A-38).**

**Done Criteria** (run until green):
`.github/copilot/scripts/macos/gateway.sh lint` ·
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_finish_test.dart test/watch_session_merge_test.dart test/watch_session_import_test.dart test/watch_capture_repository_parity_test.dart` ·
`.github/copilot/scripts/macos/gateway.sh test` **(governor**, full suite, 900 s**)**
(the two greps above are the phase's own structural check)

**Predicted Files**: `test/watch_session_finish_test.dart`, `docs/watch_session_sync.md`,
`docs/state_management/watch_surface.md`, `<plan>.evidence.md`, this plan (Progress + Assumption Log only)

### Verification ownership
- **Implementer (end of each phase):** the Done Criteria above, pasted pass/fail counts in
  `<plan>.evidence.md`, red→green shown for S-9.
- **@code-reviewer:** diff against each phase's Predicted Files; per-S-x test and fixture conformance;
  the Impact table's greps re-run; parity between `MockWorkoutRepository` and `HiveWorkoutRepository`
  on the merged rows; the Assumption Log adjudicated.
- **Governor:** `swift test` is not needed (no Swift changed) and no `xcodebuild` step exists for this
  PR.
- **Owner:** no manual walkthrough is possible in this PR — nothing a handset can do reaches the
  merge until PR 2b's logging surface ships. The owner's manual QA for both slices is PR 2b's
  walkthrough (steps 15–19 of `docs/watch-app-setup-and-qa.md`). This is a deliberate, stated gap,
  not an untested claim: the automated tests are the merge's whole evidence.

### Owner walkthrough

**Not runnable in this PR.** Nothing a handset can do stages a wrist set until PR 2b's logging screen
ships, so no manual step exercises the merge yet. The walkthrough below is the one that will prove
this merge end to end the moment 2b lands, and it is what `docs/watch-app-setup-and-qa.md` steps 15–19
are updated to describe — in 2b's phase, not this one.

1. **(owner)** Start a session on the watch (Free training, one exercise).
2. **(owner)** Tap **Sync** on the watch so the phone adopts it; the phone's session screen shows the
   same exercise.
3. **(owner)** Log three sets on the watch.
4. **(owner)** Look at the phone: all three sets are on the phone's session screen, in the order they
   were logged.
5. **(owner)** Tap **End** on the watch, and answer the "How hard was this?" question if it appears.
6. **(owner)** Tap **Sync** on the watch.
7. **(owner)** Open the phone's history for that session: the three sets, the duration and the rating
   are all there, and the watch shows no unsent residue for them.

If step 4 shows the sets only on the watch, this PR did not work.

## What PR 2b carries (not this PR)

Pinned here so the next planner does not re-decide them; PR 2b's own plan holds the detail.

> **Correction, added when PR 2b was planned (2026-10-05, `docs/plans/2026-10-05-15c-watch-session-sync-pr2b-plan/`).**
> The item below says the engine "does not have" the `onEmit` sink. It does — `WatchSessionEngine.swift:24,37,86`
> declare, store and take it, and every emission point already calls it; the app target simply never passes one,
> which is why nothing leaves the wrist. PR 2b wires it (its D-21) rather than adding it. The pruning item below
> is **superseded**: with an in-memory store there is nothing to prune, and pruning confirmed rows during a session
> changes values derived from them (the next round number reads the stored rows) — pruning moves to PR 4 with the
> durable store (PR 2b's D-27).

- Host `WatchLoggingView`, `WatchEndSessionView` and `WatchEffortRatingView` in
  `ios/OmniTrain Watch App/ContentView.swift` over the in-memory store, replacing
  `startedPlaceholder(session:)`; build `WatchLoggingState` and `WatchEffortRatingState`, restore the
  owed prompt at launch, and pass the engine the `onEmit` sink that already existed unused — PR 2b's
  D-21 wires it (what the wrist emits now leaves the wrist).
- Prune confirmed rows only while no session is active; the durable store stays PR 4.
- Owner walkthrough steps 15–19 become runnable; `docs/watch-app-setup-and-qa.md` step (f) and
  `docs/state_management/watch_surface.md`'s "the wrist shell's second surface" change with it.

## Files Affected

- `lib/core/services/watch_session_importer.dart` — the merge pass (D-13…D-19)
- `lib/state/watch/watch_session_inbox.dart`, `watch_session_adoption_bridge.dart`,
  `watch_sync_wiring.dart` — the refresh seam (D-17)
- `lib/state/workout/session_core_io.dart`, `lib/state/workout/workout_state.dart` — `refreshEfforts`
- `test/watch_session_merge_test.dart` (new), `test/watch_session_finish_test.dart` (rewritten G3),
  `test/watch_session_import_test.dart` (S-17)
- `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`
- Dependents that only read a touched surface: `lib/main.dart:376` (`onHistoryChanged` →
  `calendarState.refresh`) and the session screen (a reader of `WorkoutState`'s efforts).

## Notes

- **Scope check** (`.github/copilot/pr-scope-budget.md`; the governor measures, this is the planning
  statement). No hard limit is near: 3 phases, one track (`lib/`, plus tests and docs), one production
  file changed heavily plus four small edits — far under the 1,500 predicted production lines. Soft
  signals: 3 phases (at the boundary, not over), 8 new decisions (20 across the series), 11 new
  scenarios (19 across the series), one track. PR 2 was split because the *combined* work hit two soft
  signals — two tracks and more than three phases; each slice alone sits inside the budget.
- **Phase dependency graph.** 1 → 2 (the refresh seam reports what the pass wrote) → 3 (the docs and
  PR 1's assertions describe what 1 and 2 do). Phase 2 may be done before Phase 1's tests are
  finished, but not before its pass exists.
- **Intermediate state.** After Phase 1 the merge writes rows and nothing refreshes the phone's
  screen; after Phase 2 the screen does. Both are inside one PR; no intermediate state ships.
- **Inertness.** No production path stages a wrist effort row until PR 2b ships, so this PR's only
  observable change is in the test suite. Stated in the Overview; the reviewer should treat it as
  expected, not as missing evidence.
- **Legacy handling.** PR 1's staged rows for a held session (the ones the old code kept for ever) are
  ordinary candidates for the merge: the first settle after this ships places them. Nothing needs
  migrating and no row is rewritten.
- **Not in scope:** the phone→wrist direction (PR 3, including the `entries_down` contract decision),
  the durable wrist store (PR 4), any protocol change (D-20), and any phone screen, modal or button.
  `docs/watch-app-setup-and-qa.md` is unchanged by this PR: its step (f) still waits on the wrist's
  own logging screen (2b), and the merge adds no manual step of its own.

## Progress

- [x] Phase 1 — the merge pass: **Complete** (16 new tests; full suite `+3901 ~1`, 0 failures; lint
      196/0; G3 rewritten per the override; evidence in `<plan>.evidence.md`)
- [x] Phase 2 — the live screen and the wiring: **Complete** (4 new tests ×2 groups = 8; full suite
      `+3909 ~1`, 0 failures; lint 196/0; 5 red proofs via mutation; evidence in `<plan>.evidence.md`)
- [x] Phase 3 — PR 1's assertions, the docs, the sweep: **Complete** (no new tests: docs and a
      comment-only edit; full suite `+3909 ~1`, 0 failures; lint 196/0; both sweeps clean; evidence in
      `<plan>.evidence.md`)
- [x] Fix round 1 — Review 1's remediation (bounded, 4 items): **Complete** (3 test cases: 2 in
      `test/watch_session_merge_test.dart` ×2 groups and S-15's summary clause in the finish file's
      merge case; full suite `+3913 ~1`, 0 failures; lint 196/0; 1 red-first test and 2 mutation
      proofs; A-27 and A-32 corrected, A-39 added; evidence in `<plan>.evidence.md`)

## Assumption Log

Executors append here: the decision made, the options considered, the choice and why. The conductor
marks each **RATIFIED** (promoted to a `D-n`) or **REVERT** (a remediation item opens). An empty log
after Phase 1 is itself suspicious.

- **A-21 (Phase 1, governor override).** The brief moves Phase 3 item 1 — rewriting
  `test/watch_session_finish_test.dart`'s G3 assertions — into Phase 1, because the merge turns them
  red immediately. Done here; Phase 3 item 1 is now a no-op to confirm, not to write.
- **A-22 (Phase 1).** The merge shares `_Pass` rather than adding a second pass class, so `_Pass.end`
  became nullable: a merge has no `session_end` and never reaches the code that reads one (`run`,
  `_createSession`, `_segmentId`, `_attachSessionSummary`, `_attachSetBlockSummary` assert it).
  Alternative rejected: a parallel pass class duplicating `_createEntry`, `_placeAroundUserRows` and
  the correction rules — D-16 requires the *same* primitives so `_EffortRows.read` recognises a
  merged entry as the importer's own.
- **A-23 (Phase 1).** Each group is placed with the import's own ordering call,
  `_placeAroundUserRows(key, effortId, before, now, …)`, where `before` is the effort's
  already-applied rows and `now` the live ones. For an effort the phone has not written into
  (`holdsUserRows` false, `lastIndex` −1) that places the first entry at index 0 — S-9's
  `obs-sl-1-0-reps`.
- **A-24 (Phase 1).** A merge reports `historyChanged: true` exactly when it wrote a row (D-17) and
  names the efforts it wrote in `changedEffortIds`; the live refresh that consumes it is Phase 2, so
  in this phase the field is populated but unread.
- **A-25 (Phase 1, for Phase 3).** `lib/state/watch/live_session_mirror_state.dart:129` declares its
  own `sessionScopedKinds` — a live constant the importer's deleted predicate mirrored (PR 1's plan
  line 564). Phase 3's sweep `grep -rn "sessionScopedKinds\|the merge PR 3 owns" lib/` will still hit
  it; scope the sweep to the importer, or it will delete a constant the mirror uses.
- **A-26 (Phase 1, correcting A-24).** `changedEffortIds` is filled off a per-group **write count**
  (`_Pass.writes`), not the pass's overall `changed` flag: `_topUpRating` writes the session's rating
  earlier in the same pass, so the flag is already true when the first group is placed and the merge
  named no effort at all whenever a rating arrived with the set. Caught by the D-17 test, which was
  shown red against the flag version and green against the count (evidence: "the second red proof").
  `_Pass.changed` is unchanged in meaning — a getter over the count.
- **A-27 (Phase 1; corrected in Fix round 1).** The merge attaches the wrist's session summary
  when its end row is unapplied and readable, with no `status == completed` condition. That
  **diverges** from the import path, which returns early for an abandoned end and attaches nothing:
  a held session's heart rate was measured during the phone's own session, so it is kept, while the
  phone's own end and lifecycle still own the session's fate — a discard takes the summary with it.
  Pinned by `D-19 a held session takes the wrist's end summary, abandoned or not` (mutation: adding
  the `completed` condition turns it red). The entry's earlier claim that the two paths agree on an
  abandoned end was false, and a readable-but-unapplied end whose `_End.parse` fails would have
  thrown on `_Pass.end!` — the guard now reads `end != null` (Fix round 1, red-first test in the same
  file). S-14 (a merge never writes the session's own end, G2/D-5) and D-17 (the field it names is
  populated) are unchanged, as the entry's provenance note said.
- **A-28 (Phase 2).** The hook is `WatchSessionInbox.onSessionRowsChanged(sessionId, effortIds)`,
  called in `_settleNow` only when `pass.changedEffortIds` is non-empty and wired in `createWatchSync`
  to `WatchSessionAdoptionBridge.refreshHeldEfforts`, which returns early unless `holdsSession`.
  Alternative rejected: refreshing from the inbox directly — it holds no session state and must not
  decide which session is the phone's live one.
- **A-29 (Phase 2).** `refreshEfforts` notifies once and clears nothing. Red proof 1: swapping its
  `_notify()` for `loadSessionData()` (the whole-session reload) fails S-16's one-notification
  assertion with 3; red proof 2: adding `_timerManager.clearAll()` fails the running-rest assertion
  with an empty rest list.
- **A-30 (Phase 2).** `refreshEfforts` has no early return for an empty `effortIds` — it still
  notifies once. The guard lives upstream, in `_settleNow`'s non-empty check, which S-16's redelivery
  test pins (red proof 4). Kept where D-17 puts it rather than duplicated in two places.
- **A-31 (Phase 2).** S-16 asserts the rest by record identity and open state (`restEndMs == null`,
  same id), never by elapsed seconds: `WorkoutState` builds `TimerManager` with the real clock, and
  the plan forbids real-clock thresholds in tests.
- **A-32 (Phase 2; corrected in Fix round 1).** Item 4's S-15 has a case, not a duplicate:
  `test/watch_session_finish_test.dart`'s merge case runs S-15's shape — a set, an end carrying heart
  rate (140/165), a rating 4 — and asserts all three applied and receipted, the session still ended,
  the rating 4, one summary attached, and no second row or summary on redelivery. Its set fixture is
  **not** S-15's (`reps: 5, loadKg: 80`, not `reps: 8`, `loadKg: 40`), so the entry's "S-15's exact
  fixture" was wrong; the fourth clause (the summary) was missing and was added in Fix round 1, where
  the end gained the two heart-rate numbers.
- **A-33 (Phase 2).** Item 5's S-17 is a named case in the merge test file rather than
  `test/watch_session_import_test.dart` (the item allows either): it needs the merge wiring in place
  to be a regression, and that wiring lives in this file's `_phone`. Red proof 5 — the merge taking
  every session — fails it.
- **A-34 (Phase 2).** One line outside the Predicted Files:
  `docs/state_management/workout_state.md`'s lifecycle method table gained a `refreshEfforts` row,
  because the new public method left it stale. The narrative docs stay Phase 3's (item 2–3).
- **A-35 (Phase 3).** Item 4's sweep is run importer-scoped, as A-25 predicted:
  `grep -n "sessionScopedKinds\|the merge PR 3 owns"` over
  `lib/core/services/watch_session_importer.dart` returns nothing, while the repo-wide spelling still
  hits `lib/state/watch/live_session_mirror_state.dart:129` — the mirror's live constant, which names
  the entry kinds a session snapshot must carry and is documented in
  `docs/state_management/watch_surface.md:64`. Alternative rejected: deleting it, which would break
  the mirror's snapshot assembly to satisfy a literal reading of the Done Criteria. Both results are
  pasted in the evidence file, with the constant excluded and why.
- **A-36 (Phase 3).** Phase 1's override left
  `test/watch_session_finish_test.dart`'s header map with the
  `G1 never resurrect a finished session` line listed twice. Removed one copy. Alternatives:
  leaving it (a duplicate scenario-map entry misdirects the next reader and would read as a
  second scenario), or rewriting the map (out of this phase's scope, and the map is otherwise
  correct). Comment-only; the file's test count is unchanged.
- **A-37 (Phase 3).** `docs/watch_session_sync.md`'s phone→wrist bullet is grounded in
  `test/watch_session_projection_test.dart`'s `S-2 a running phone session is answered with its own
  ladder`, which asserts the answer's `entries` is empty — that is the test the doc names for "sets
  logged on the phone are not carried to the wrist", rather than the plan's own unshipped PR 3
  (`entries_down`), which the docs must not cite (nothing unshipped is named in a doc).
- **A-38 (Phase 3).** Item 1 needed no write, so this phase adds no test and the full suite stays at
  3909. Consequence recorded rather than absorbed: the phase's Done Criteria are met by observed
  output (lint 196/0, the four-file run `+114`, the full suite `+3909 ~1`, both sweeps), not by a new
  red→green pair. `docs/watch_session_capture.md` was checked in this phase and needed no change —
  its staged-kinds invariant is about the live inbox/mirror staging, not the deleted importer
  predicate. Fix round 1 did change it (A-39): the end-waiting rationale gained the held-merge
  exception.
- **A-39 (Fix round 1).** `docs/watch_session_capture.md`'s "Why an import waits for the session end"
  now names the exception — a session the phone already holds merges its wrist effort rows as they
  arrive, with no end to wait for — and cites `test/watch_session_merge_test.dart` (`S-9`, `D-19`),
  which is the doc set's citation style and corrects A-38's "needed no change".

## Feedback

[empty — folded into a new Iteration block when non-empty, then cleared]

**Review 1 (@code-reviewer, Copilot CLI) — findings and fix checklist are in
`2026-10-05-15b-watch-session-sync-pr2-plan.review.md`.** Verdict: warnings only, one bounded pass —
(1) assert the held session's summary after the wrist's end (S-15's fourth clause, the one uncovered new
line); (2) correct A-32's fixture/assertion claim and A-27's `run`-parity claim; (3) optional:
`docs/watch_session_capture.md`'s "an import waits for the session end" needs one clause naming the held
merge. No code defect found.

## Open questions

Owner-visible choices, in plain language, each with a recommended default. Everything else in this
plan is a technical decision already made and recorded in the Ledger.

1. **Does the watch's sets have to land in the phone's live session at all?** (Owner.)
   *Recommend: yes — merge them as they arrive (this PR).* The alternative is to keep PR 1's
   behaviour (the watch's sets stay on the watch) and let the owner see, in the phone's history, a
   session that is missing the sets logged on the watch. That is the failure this PR exists to
   prevent.
2. **Order of the two slices.** (Owner.) PR 2 was split because it was over budget (two tracks, more
   than three phases). *Recommend: ship the merge first (this plan), then the wrist's logging screen.*
   The merge alone changes nothing you can see by hand; the logging screen alone would ship the
   missing-sets defect above. Shipping them in this order means the wrist can log correctly the day
   its screen arrives.
3. **A phone Sync that stops the watch's rest timer.** (Owner.) Today the phone's answer to a watch
   Sync carries no timer state, so a Sync in the middle of a rest countdown stops that countdown on
   the watch (PR 1's A24). *Recommend: keep that in this PR and fix it in PR 2b if it annoys you in
   practice* — carrying timers needs a protocol addition and belongs with the screen that shows them.
4. **Where the watch's owed "How hard was this?" question appears.** (Owner, PR 2b.) PR 1's model
   stores the question when a wrist session ends, and the shell does not show it yet. *Recommend: at
   launch, before anything else (including a running session), which is what the walkthrough already
   promises.*
5. **A set logged on the watch while the phone is unreachable.** (Owner.) *Recommend: no change — the
   watch keeps the set and sends it at the next Sync (the existing rule).* Nothing is lost, and
   nothing arrives early.

Two process notes, recorded rather than asked:

6. **The extra plan folder could not be created.** The brief asks the planner to create the folder for
   the second slice. This run has file tools only (no shell beyond the gateway), so no directory can
   be created: PR 2b's folder is created by the governor when PR 2b opens, per the budget's own
   "plan the later PRs when their turn comes". *Default taken: the series index carries PR 2b's order,
   scope, dependencies and shared decisions; its full plan is written at its turn.*
7. **This plan is PR 2a, and it replaced the skeleton at the brief's named path.** The skeleton's claim
   that "wrist-logged sets already flow to the phone via `observations_up` → inbox → import-on-end" is
   wrong for a session the phone holds — that is exactly PR 1's G3 — so the skeleton could not be
   extended; it was replaced. *Default taken: keep the brief's path for the first slice of the split.*
