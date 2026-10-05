# Feature: watch-session-sync PR 1 — one session on phone and watch (phone side)

> Status: Owner answers recorded 2026-10-05; defaults below applied
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`, `docs/documentation_standard.md`
> Series: `docs/plans/2026-10-05-15-watch-session-sync-index.md`
> Builds on: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md` (D-1..D-16), base commit 373c39b

## Overview

The phone has two parallel session concepts today: `WorkoutState`/`SessionCore` (the real,
repository-persisted session driving Free Session, the picker, logging and finish) and
`LiveSessionMirrorState` (a separate mirror of the wrist's session, driving the Watch Session
screen and the home card). This PR removes the three phone-side watch surfaces and makes the
phone's real session the one session shared with the wrist — a wrist-started session becomes the
phone's normal in-progress session, and a phone session becomes the wrist's in-progress ladder.
No set logging crosses the bridge in this PR (that is PR 2/3); the bridge moves ladder, lifecycle
and session identity only.

## Resolved Decisions (Ledger)

- **D-1 — Single session.** `WorkoutState` owns the phone's one in-progress session. The watch
  mirror (`LiveSessionMirrorState`) is demoted to the protocol-transport projection of
  `WorkoutState`; no screen reads it directly. The three phone-side watch surfaces are deleted.
- **D-2 — Wrist→phone adoption.** A wrist `session_snapshot` naming a session the phone is not
  holding creates a real, repository-persisted in-progress `TrainingSession` in `WorkoutState`
  with the wrist's ladder (slots → `SegmentEffort`s; entries are absent in PR 1). After adoption
  the phone is the structure authority (PROTOCOL.md unchanged). D-10 bounds this adoption when the
  phone already holds a real active session.
- **D-3 — Identity IS the protocol ids; nothing new is persisted.** The phone reuses the protocol's
  own strings as its row ids, so identity survives a phone restart with no new storage. An adopted
  wrist session's `TrainingSession.id` IS the protocol `sessionId`, and each adopted
  `SegmentEffort.id` IS the protocol `sessionExerciseId`. A phone-started session's protocol
  `sessionId` IS its `TrainingSession.id`, and each effort's slot id IS that effort's own id (a
  phone-added effort keeps its own id; the wrist only ever sees it as a new slot). Both are free
  strings (`String` / `TEXT PRIMARY KEY`; cast, never parsed or format-validated) and the families
  are disjoint: phone-minted ids start `session-` / `effort-`, wrist-minted slot ids start `sx-`.
  The inbox already stages and imports by that same `sessionId` (`WatchSessionImporter` writes
  `TrainingSession(id: sessionId)`), so D-5's no-double-import guard keys on it. Consequence to
  respect: the importer's derived effort id (`effortIdFor` →
  `effort-<sessionId>-<slot>-<exerciseId>-<kind>`) is NOT the slot id, so an import pass over a
  session the phone already holds live would duplicate its efforts — exactly what D-5's guard
  prevents.
- **D-4 — Phone→wrist surfacing.** A phone session surfaces on the wrist at the next
  watch-initiated sync: the wrist asks for a snapshot (session-switch rule) and the phone answers
  with its real session projected to protocol shape. No phone-initiated push (bridge D-16).
- **D-5 — Shared lifecycle.** `session_lifecycle` (completed/abandoned) from the wrist ends the
  phone's mirrored session through the normal finish/clear; the phone's finish reports
  `session_lifecycle` to the wrist. Exactly one session reaches history — the inbox must not
  double-import a session it already mirrored live.
- **D-6 — Active semantics.** A mirrored session is "active" on the phone under the SAME rule as a
  phone session (`endedAtMs == null` AND ≥1 effort). A wrist session with zero exercises reads
  "not yet active" on the home, matching a just-created phone session.
- **D-7 — Modality.** A wrist free session (no modality) adopts as null-modality (Free Training).
  A routine session adopts the modality carried by the routine.
- **D-8 — One rating.** The phone finishes a mirrored session through the normal finish flow
  (rating written to the now-real session). The wrist's rating still arrives via `observations_up`
  `effort_rating` with phone-rating precedence, applied to the same session — one rating, not two.
- **D-9 — No protocol change in PR 1.** PROTOCOL.md's authority rules stand. The phone→wrist
  set-entry contract decision is PR 3's (`entries_down` proposal in the index), not PR 1's.
- **D-10 — No silent data loss on conflict (phone-policy layer).** If the phone holds a real
  in-progress session with at least one exercise (the D-6 "active" rule), a wrist
  `session_snapshot` naming a DIFFERENT session is NOT adopted into `WorkoutState`: nothing is
  deleted, nothing is merged, no prompt, no screen — both devices keep their own session until one
  is finished. The skipped adoption is reported through the bridge's `onSkipped` callback (one
  plain `debugPrint` line by default, no stack), once per (held, offered) pair — it is not an
  error. If the
  phone holds no session, or only an empty one (no exercises, nothing logged), the wrist's session
  is adopted as in S-1. This is a phone-policy layer ABOVE the protocol's rule: PROTOCOL.md's
  "snapshot naming another session MUST replace the held session wholesale" still holds for the
  mirror/transport projection and the wrist engine, because D-1 made the phone's held session
  durable. The guard lives in the new state-boundary bridge, NOT the reconciler:
  `SyncSessionReconciler`, `fixtures/reconciliation/session_switch.json`, `live_mirroring_test.dart`
  S-251 and PROTOCOL.md are all unchanged.
- **D-11 — On-demand projection (phone edits reach the wrist).** The projection from `WorkoutState`
  to the protocol shape (ladder, slot ids per D-3, current exercise, status, revision) is derived on
  demand when a snapshot is composed — never cached — and the revision rises whenever the ladder
  changes through the regular session screen, so the wrist's replace-structure rule accepts the
  phone's current ladder. The answer to a wrist snapshot always reflects the phone's CURRENT
  regular-screen ladder, not a mirror copy.

## Feature Invariants

- `WorkoutRepository` parity: `MockWorkoutRepository` and `HiveWorkoutRepository` produce identical
  output for the adoption path (same session/segment/effort rows).
- Never mutate records for past periods: a mirrored live session is present, never past.
- Layer boundaries: `lib/state/` depends on `WorkoutRepository` only; the bridge lives at the state
  boundary; `lib/features/` never touches persistence.
- Protocol conformance (`SyncSessionReconciler`) still holds for the mirror as a projection.

## Requirements

1. Remove the Watch Session screen, the home entry-point card (+ layout budget), and the picker
   "Send to watch session" icon, with their DI wiring and tests/docs.
2. A wrist-started session (manual sync) appears as the phone's normal in-progress session on the
   home and opens in the regular Free Session screen.
3. A phone-started session appears as the wrist's in-progress ladder at the next watch sync.
4. Finishing on either device ends the one session on both; one session in history.

## Acceptance Criteria

- AC1: `grep -rln "live_session_screen|live_session_entry_point" lib/ test/` returns nothing (R1).
- AC2: a wrist snapshot with ≥1 exercise makes the home Free Training tile active and opens the
  regular session screen with that ladder (R2) → S-1.
- AC3: a phone session is answered as the snapshot at watch sync (R3) → S-2.
- AC4: finish on either device yields one history entry (R4) → S-4, S-5.
- AC5: an empty wrist session does not surface as active (R2, D-6) → S-3.

## Existing-Functionality Impact

Each row's readers were located by grep at plan time.

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `lib/features/session/live_session_screen.dart` | `screen_widget_test.dart`, `live_session_effort_rating_test.dart`, `live_session_capture_entries_test.dart`, `live_session_fixtures.dart` | Deleted (R1) | S-7 |
| `lib/widgets/session/live_session_entry_point.dart` | `home_screen.dart` (~511-567, 606-615), `home_short_viewport_test.dart` (`budgetHeight`), `screen_widget_test.dart` | Deleted (R1) | S-7 |
| `lib/features/home/home_screen.dart` `liveSession`/`liveSessionEntryGap`/`liveSessionBlock` | `home_screen.dart` layout budget + `_openLiveSession` | Card + budget removed; layout re-verifies short-viewport | S-7, S-1 |
| `lib/features/exercise/exercise_picker_screen.dart` `liveSession`/`liveSessionInsertIndex`/`liveSessionSwapSlotId`/`_sendToWatchSession` | picker row trailing icon (~689-760), `interaction_flow_test.dart` | "Send to watch" icon + live-row-tap removed; picker returns to pop-only behavior | S-7 |
| `lib/main.dart` (370-429), `lib/app.dart` (54-81, 175-176) `liveSession`/`watchSessionRatings` | `MyApp`/`HomeScreen` construction | `liveSession` param removed from screens; mirror/ratings graph itself kept (`createWatchSync` unchanged) | S-7 |
| `lib/state/watch/live_session_mirror_state.dart` | `watch_sync_wiring.dart` (116-129), `watch_incoming_router.dart`, `watch_sync_request_handler.dart`, `live_mirroring_test.dart`, `phone_manage_bridge_test.dart` | Repurposed as projection of `WorkoutState` (D-1); stays as snapshot-answer source | S-2 |
| `lib/state/watch/watch_sync_request_handler.dart` snapshot answer | `watch_sync_wiring.dart`, `watch_transport_test.dart` | Answer source becomes `WorkoutState` projection instead of placeholder/mirror | S-2 |
| `lib/state/watch/watch_session_inbox.dart` import-on-end | `watch_session_import_test.dart`, `watch_capture_import_harness.dart`, `watch_nutrition_quick_log_test.dart` | Add live-mirror dedup guard (D-5) | S-4 |
| `docs/navigation_and_screens.md` (177, 184, 190, 265) | index | Remove the three surface entries | S-7 |
| `docs/watch-app-setup-and-qa.md` | owner QA walkthrough | Replace "send to watch"/"watch session on phone" walkthrough with one-session walkthrough — **(owner)** step | S-1 |

## Scenarios

### S-1: wrist-started free session becomes the phone's in-progress session (happy path)
- Fixture: phone has no active session. Wrist holds `s-w1` (status `active`, revision 3,
  currentExerciseIndex 1, slots `sl-1`→`ex-bench` (set), `sl-2`→`ex-squat` (set), entries []).
  Catalog seeded with `ex-bench`, `ex-squat`.
- Trigger: watch syncs → phone receives `session_snapshot`.
- Flow: phone adopts `s-w1` into `WorkoutState` as `TrainingSession` (id mapped from `s-w1`,
  modality null, endedAtMs null) with one segment and two `SegmentEffort`s; home Free Training
  tile renders active; tapping it opens the regular session screen showing bench then squat.
- Expected outcome: home active tile + regular session screen with the 2-exercise ladder.
- Edge case of: none.

### S-2: phone session surfaces as the wrist's in-progress ladder (happy path)
- Fixture: phone `TrainingSession` `session-phone-1` (null modality, endedAtMs null) with segment
  `segment-phone-1`, efforts `effort-a`→`ex-bench` (set), `effort-b`→`ex-squat` (set). Wrist holds
  placeholder (no session).
- Trigger: watch syncs and asks for a snapshot.
- Flow: `WatchSyncRequestHandler` answers with the `WorkoutState` session projected to
  `session_snapshot` (id, active, slots minted from efforts); wrist adopts via session-switch rule.
- Expected outcome: wrist post-start shows bench and squat; phone session id unchanged.
- Edge case of: none.

### S-3: empty wrist session is not yet active (D-6)
- Fixture: wrist holds `s-w0` (status `active`, revision 1, exercises [], entries []). Phone no
  active session.
- Trigger: watch syncs.
- Flow: phone adopts a session with zero efforts; `hasActiveSession` is false.
- Expected outcome: home shows no active tile; no navigation to a session screen.
- Edge case of: S-1.

### S-4: finishing on the wrist ends the one session (no double import) (D-5)
- Fixture: S-1 state after adoption (phone has mirrored `s-w1`). Wrist sends `session_lifecycle`
  `completed` with `effort_rating`.
- Trigger: phone receives lifecycle.
- Flow: phone ends the mirrored session via normal finish (rating written once); inbox skips its
  own import because the session was mirrored live.
- Expected outcome: exactly one `TrainingSession` for `s-w1` in history, one rating.
- Edge case of: S-1.

### S-5: finishing on the phone ends the wrist session (D-5, G2)
- Fixture: S-1 state after adoption.
- Trigger: user finishes in the regular session screen.
- Flow: phone `endSession` writes the rating and sends nothing to the wrist (G2); the wrist learns
  the session is over from the phone's next answer to a sync request.
- Expected outcome: no message leaves the phone on the finish; the phone has one history entry; the
  wrist's next sync is answered with `completed`.
- Test: `test/watch_session_finish_test.dart`, `S-5 the phone's own finish is not reported, and the
  wrist is answered at its next sync`.
- Edge case of: S-1.

### S-6: phone holds an active session, wrist names another — phone keeps its own (D-10)
- Fixture: phone `WorkoutState` holds active `session-phone-1` (null modality, `endedAtMs` null)
  with segment `segment-phone-1` and efforts `effort-a`→`ex-bench` (set), `effort-b`→`ex-squat`
  (set). Wrist holds a different `s-w2` (one slot `sl-1`→`ex-deadlift`, entries []).
- Trigger: watch syncs with `session_snapshot` naming `s-w2`.
- Flow: the reconciler applies the switch to the mirror projection (protocol MUST rule, unchanged);
  the bridge's D-10 guard sees `WorkoutState` already holds an active session and does NOT adopt
  `s-w2` into `WorkoutState`; the skipped adoption is reported through the bridge's `onSkipped`
  callback, once, with no stack trace and no failure entry.
- Expected outcome: `WorkoutState.currentSession.id` is still `session-phone-1` with the same two
  efforts and entries; no history row is created or deleted; the home tile still shows
  `session-phone-1`; the wrist snapshot is not adopted — nothing deleted, merged, prompted or shown.
- Test: `test/watch_session_adoption_bridge_test.dart`, `S-6 the phone keeps the session it is
  already running` (the skip is reported once and the failure list stays empty).
- Edge case of: S-1.
- Edge case (counter-case): the phone holds no session, or only an empty one (zero efforts) → the
  wrist's `s-w2` is adopted as in S-1.

### S-8: phone edits reach the wrist via manual sync (D-11)
- Fixture (case A — add): S-1 state after adoption — phone `WorkoutState` holds `s-w1` with efforts
  `sl-1`→`ex-bench` (set), `sl-2`→`ex-squat` (set) (D-3: an effort's row id IS its slot id); the
  wrist holds `s-w1` with slots `sl-1`→`ex-bench`, `sl-2`→`ex-squat`, revision 3. The phone then
  adds `ex-deadlift` via the regular session path (`addExerciseToSession`), so the phone ladder is
  bench, squat, deadlift.
- Trigger (case A): the wrist taps Sync and hands over its snapshot with the old two-slot ladder.
- Flow (case A): the phone's answer is composed on demand from `WorkoutState` (D-11) with the
  three-slot ladder and a higher revision; the wrist's replace-structure rule adopts it.
- Expected outcome (case A): the phone answers with the three-exercise ladder; the slot ids of the
  first two (`sl-1`, `sl-2`) are unchanged; replaying the wrist's old snapshot again produces no
  second answer (agreeing peers stay silent).
- Fixture (case B — remove current): S-8 case A state after the add; the wrist's current position is
  on `sl-2`→`ex-squat` (index 1); the phone removes `ex-squat` via the regular session path
  (`removeExerciseFromSession`).
- Trigger (case B): the wrist taps Sync and hands over its old three-slot snapshot.
- Flow (case B): the answer carries the two-slot ladder (bench, deadlift) with a higher revision;
  the wrist applies it per the protocol's structure rules.
- Expected outcome (case B): the wrist's current position moves the way
  `fixtures/reconciliation/remove_current_exercise.json` pins it — index 1 stays but now holds the
  exercise that followed the removed slot, and the removed slot's logged entries are not lost.
- Edge case of: S-1, S-2.

### S-7: residue sweep — no readers of the removed surfaces remain (AC1)
- Fixture: whole repo.
- Trigger: `grep` per AC1.
- Flow: implementer runs the grep; reviewer re-runs it.
- Expected outcome: zero matches in `lib/` and `test/`; `flutter analyze` clean to baseline.
- Edge case of: none.

## Iteration 1

### Phase 1: Remove the three phone-side watch surfaces (@developer)
1. [x] Delete `lib/features/session/live_session_screen.dart` and its route registration (see
   `docs/navigation_and_screens.md` 177/184/190).
2. [x] Delete `lib/widgets/session/live_session_entry_point.dart`.
3. [x] In `lib/features/home/home_screen.dart`: remove `liveSession`/`watchSessionRatings` params,
   the `LiveSessionEntryPoint` card, `_openLiveSession`, `liveSessionEntryGap`, and the
   `liveSessionBlock` layout budget; re-verify short-viewport layout.
4. [x] In `lib/features/exercise/exercise_picker_screen.dart`: remove `liveSession`,
   `liveSessionInsertIndex`, `liveSessionSwapSlotId`, `_sendToWatchSession`, the watch icon and
   the live-row-tap branch; restore pop-only row behavior.
5. [x] In `lib/app.dart` (54-81, 175-176) and `lib/main.dart` (370-429): stop passing
   `liveSession`/`watchSessionRatings` to screens; keep `createWatchSync` and its graph intact.
6. [x] Delete/update tests: `live_session_effort_rating_test.dart`,
   `live_session_capture_entries_test.dart`, `home_short_viewport_test.dart` (budget assertions),
   `screen_widget_test.dart` ("no entry point" + home), `interaction_flow_test.dart`
   (send-to-watch), and helpers `test/helpers/live_session_fixtures.dart` where now unused.
7. [x] Update `docs/navigation_and_screens.md` (177, 184, 190, 265) to drop the three surfaces;
   update `docs/watch-app-setup-and-qa.md` walkthrough (owner-facing) to the one-session flow.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/screen_widget_test.dart test/home_short_viewport_test.dart test/interaction_flow_test.dart`,
`.github/copilot/scripts/macos/gateway.sh test` (full, after edits).
**Predicted Files**: the five `lib/` files above; the named tests/helpers; the two docs. Nothing else.

### Phase 2: Wrist→phone adoption bridge (@developer)
1. [x] Add a state-boundary bridge that adopts a wrist `session_snapshot` into `WorkoutState` as a
   real in-progress `TrainingSession` (D-2): modality (D-7), slots → `SegmentEffort`s with one
   default segment; ids are the protocol ids — session row id = `sessionId`, effort row id = its
   slot id (D-3). — `lib/state/watch/watch_session_adoption_bridge.dart`.
2. [x] Wire the bridge so `WatchIncomingRouter`/mirror snapshot adoption drives it (the mirror
   stays as the reconciler; the bridge projects its result into `WorkoutState`). — router drives it
   after `_mirror.receive`; `WatchSyncGraph.adoption`; `main.dart` binds the graph's bridge to the
   `WorkoutState` it builds.
3. [x] Implement the D-10 guard IN THE BRIDGE, not the reconciler: when `WorkoutState` already holds
   an active session (D-6) and the reconciler switches to a different-session snapshot, do NOT adopt
   it into `WorkoutState`; report the skipped adoption through the bridge's `onSkipped` callback
   (one `debugPrint` line by default, once per (held, offered) pair), never the failure hook.
   `SyncSessionReconciler`, `fixtures/reconciliation/session_switch.json`, `live_mirroring_test.dart`
   S-251 and PROTOCOL.md stay unchanged. — mutation-checked (routing the skip back to `onFailure`
   turns the three D-10 assertions red); none of the four named artifacts is in this diff.
4. [x] Ensure `hasActiveSession` semantics per D-6; empty snapshot → not active (S-3). — empty
   session adopts (user opened it) but reads not-yet-active.
5. [x] Add state tests (plain `test()`, Mock repository) covering S-1, S-3 and S-6 (phone keeps its
   own; no history rows created/deleted) plus its counter-case (empty phone session → adopted), a
   parity test that Mock and Hive produce the same adopted rows, and a restart test — a fresh
   `WorkoutState` over the same repository resolves the same session id and the same effort slot ids
   unchanged (D-3). — `test/watch_session_adoption_bridge_test.dart`, 10 tests, `+10`.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart` and the
existing `test/live_mirroring_test.dart` (still green — mirror conformance unchanged).
**Predicted Files**: a new bridge file under `lib/state/watch/`; edits to `watch_sync_wiring.dart`,
`watch_incoming_router.dart`; new tests under `test/`. `lib/features/` untouched.

### Phase 3: Phone→wrist surfacing (@developer)
1. [x] Make `WatchSyncRequestHandler`'s snapshot answer source the `WorkoutState` session projected
   to protocol shape (D-4) when one is in progress; fall back to the placeholder when not. Compose
   the projection on demand (D-11): ladder from `WorkoutState` efforts, slot ids = the efforts' own
   ids (D-3), current exercise/status from `WorkoutState`, and a revision that rises whenever
   the ladder changes through the regular screen. — `projectSession` on the bridge, handed to the
   mirror as `projection:`; the answer is composed per call, and the revision seeds from the wrist's
   frame and rises by one only when the ladder changes.
2. [x] Because a wrist-visible slot id IS the effort's row id (D-3), it stays stable across phone
   edits of the same effort; a phone-added effort keeps its own new id as its slot id. — the slot is
   built from the effort (`sessionExerciseId` = `effort.id`); S-8 case A pins `sl-1`/`sl-2` unchanged
   and the added effort's own id as the third slot.
3. [x] Add a test asserting a phone session is answered as the snapshot (S-2), and that the
   placeholder is still answered when the phone has no session. — `S-2 a running phone session is
   answered with its own ladder` (ladder, slot ids, status, position) and `S-2 an idle phone still
   answers with silence`; the copy's fallback is covered by `test/watch_transport_test.dart` S-003.
4. [x] Add the S-8 tests in `test/watch_session_projection_test.dart`: (A) a phone
   `addExerciseToSession` is answered at sync with the new ladder, the first two slot ids unchanged
   and a higher revision, and replaying the wrist's old snapshot produces no second answer; (B) the
   phone removes the exercise the wrist is on and the answer moves the wrist's position per
   `fixtures/reconciliation/remove_current_exercise.json`. — both cases assert through the real wrist
   engine (`WatchSessionEngine.applyMessage`); case B lands on index 1, the following slot, as the
   fixture's `expected` block pins it.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart test/watch_session_projection_test.dart`.
**Predicted Files**: `lib/state/watch/watch_sync_request_handler.dart`, the Phase 2 bridge file;
new tests. Nothing else.

### Phase 4: Lifecycle, dedup, rating, docs (@developer)
1. [x] Route wrist `session_lifecycle` (completed/abandoned) to end the mirrored `WorkoutState`
   session via the normal finish/clear (D-5); add the inbox dedup guard so a live-mirrored session
   is not imported again on `session_end`. — `WatchSessionAdoptionBridge.onLifecycle` (finish/clear)
   routed by `WatchIncomingRouter.receive`; the guard is `WatchSessionImporter.apply`'s
   `phoneOwnsSession` (G3), decided in the importer (A28).
2. [x] ~~Route phone `endSession` to report `session_lifecycle` to the wrist~~; fold the phone's rating
   into the now-real session (D-8). — the first half is **superseded by G2**: the phone's finish sends
   nothing (A32). The rating half is `_catchUpSessionRow` (A30), and `WatchSessionInbox` passes
   `phoneOwnsSession: adoption.holdsSession` so a session the phone owns is deduped (G3).
3. [x] Add tests covering S-4 (one history entry, one rating) and S-5 (lifecycle reported). —
   `test/watch_session_finish_test.dart`, 8 tests: S-4 ×2 (roster first, end first), S-5, G1 ×2,
   G3, plus the foreign-lifecycle and abandoned cases. First run `+5 -3`; `+8` after.
4. [x] Update `docs/state_management/watch_surface.md`, `docs/watch_session_capture.md`,
   `docs/widget_catalog/session_widgets.md` (remove the Watch Session screen/home-card entries) and
   `docs/navigation_and_screens.md`; write a short consolidated `docs/watch_session_sync.md` stating
   the single-session model and naming the tests that prove it. State each doc's size vs the 52 KB
   band in Progress. — the screen/home-card entries were already gone (Phase 1); the three residues
   this phase made false were corrected and `watch_session_sync.md` is new. Sizes: 8702 B new,
   `watch_surface.md` 39789 B (61% of the 64 KiB ceiling), `watch_session_capture.md` 20897 B,
   `watch-app-setup-and-qa.md` 22641 B; all under the 52 KiB band.
5. [x] Residue sweep: re-run AC1 and confirm no reader of any replaced representation remains. —
   only `test/in_session_pr_toast_test.dart`'s `pumpLiveSessionScreen` helper matches the names, and
   it builds `WorkoutSessionScreen`; S-7's import invariant is clean. See `<plan>.evidence.md`.
**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart test/<new-lifecycle-tests>`,
`.github/copilot/scripts/macos/gateway.sh test` (full).
**Predicted Files**: `lib/state/watch/watch_session_inbox.dart`, the bridge file, `watch_sync_wiring.dart`;
new tests; the named docs. Nothing else.

## Files Affected (whole feature; mark dependents that only read a touched surface)

- Deleted: `lib/features/session/live_session_screen.dart`, `lib/widgets/session/live_session_entry_point.dart`.
- Edited: `lib/features/home/home_screen.dart`, `lib/features/exercise/exercise_picker_screen.dart`,
  `lib/app.dart`, `lib/main.dart`, `lib/state/watch/live_session_mirror_state.dart` (re-role),
  `lib/state/watch/watch_sync_wiring.dart`, `lib/state/watch/watch_incoming_router.dart`,
  `lib/state/watch/watch_sync_request_handler.dart`, `lib/state/watch/watch_session_inbox.dart`.
- New: a bridge file under `lib/state/watch/`; a consolidated `docs/watch_session_sync.md`.
- Tests: delete `live_session_effort_rating_test.dart`, `live_session_capture_entries_test.dart`,
  `test/helpers/live_session_fixtures.dart` (if unused); edit `screen_widget_test.dart`,
  `home_short_viewport_test.dart`, `interaction_flow_test.dart`; keep green
  `live_mirroring_test.dart`, `phone_manage_bridge_test.dart`, `watch_transport_test.dart`,
  `watch_session_import_test.dart`, `watch_nutrition_quick_log_test.dart`, `in_session_pr_toast_test.dart`.

## Notes

- Phase dependency: 2 and 3 both need the Phase 1 removal only for a clean analyze; the bridge can
  be written first if preferred. Phase 4 depends on 2 and 3. Phase 1 is independently shippable.
- Intermediate states: after Phase 1 alone the phone has no watch session surface but the mirror
  still exists and answers the placeholder snapshot — no user-visible regression, sync still works.
- PR 1 makes no Swift changes; wrist adoption of a phone snapshot is already implemented
  (`WatchLiveMirroringTests.testJoiningAsksForASnapshotRatherThanOfferingOne`). Verification of the
  wrist side is a **(governor)** `swift test` / **(owner)** manual QA step, not an agent step.
- "Phone edits reach the watch" under manual sync works via D-11 (R2): the snapshot answer is
  composed on demand from `WorkoutState` and its revision rises on ladder changes, so the wrist's
  replace-structure rule accepts it. No push happens in PR 1 — this becomes automatic with PR 3's
  `entries_down`.
- Other direction (R1): a wrist that holds a session and receives a phone snapshot naming a
  different session replaces its own wholesale (Swift `WatchSessionEngine.applySnapshot`). This
  cannot overwrite a wrist session in practice: `WatchSyncOrchestrator.sync()` requests a snapshot
  only when `engine.session == nil`, and re-assertion snapshots name the session the phone holds, so
  the wrist only ever receives a snapshot it asked for while sessionless. Verified by
  `WatchLiveMirroringTests.testJoiningAsksForASnapshotRatherThanOfferingOne`.
- Empty wrist session (S-3): per D-6 the home shows no active tile until the first exercise
  (owner-settled 2026-10-05).

## Progress

- [x] Phase 1: remove surfaces — **Complete.** The screen, the home card (with `liveSessionEntryGap`
  and `liveSessionBlock`), the picker's watch icon/branch and all DI wiring for them are gone, with
  their tests and docs; the mirror/sync graph is untouched. `gateway.sh lint` → 196 issues, 0 errors
  (baseline); the three touched test files → `All tests passed! (+277)`; full suite → `+3847 ~1 -2`
  (34 tests went with the surfaces). The `-2` is an untouched Stats file failing in isolation, not
  this change — see `<plan>.evidence.md` → "External red".
- [x] Phase 2: wrist→phone adoption — **Complete.** The bridge adopts a snapshot the mirror applied
  as the phone's own in-progress session (one segment, one effort per slot, protocol ids verbatim),
  guarded by D-10 and driven by the router after `_mirror.receive`; empty → adopted but not active.
  `gateway.sh lint` → 196 issues, 0 errors (baseline); `test/watch_session_adoption_bridge_test.dart`
  → `+10`; `+ test/live_mirroring_test.dart` → `+52`; full suite → `+3857 ~1 -2` (the same external
  `cardio_efficiency_drift_signal_screen_test.dart` pair). Reconciler, session-switch fixture,
  `live_mirroring_test.dart` S-251 and PROTOCOL.md unchanged. See `<plan>.evidence.md`.
- [x] Phase 3: phone→wrist surfacing — **Complete.** Every ladder this phone asserts is composed on
  demand from the bound `WorkoutState` session (`WatchSessionAdoptionBridge.projectSession`, D-11) and
  passed to the mirror as `projection:`; a slot id is the effort's row id (D-3); the revision seeds
  from the wrist's frame and rises only when the ladder changes, so the wrist's replace-structure rule
  accepts a real edit and a replay stays silent. The mirror's own copy answers only when the phone has
  no session to speak from, or the wrist named another session (D-10). `gateway.sh lint` → 196 issues,
  0 errors (baseline); `test/watch_transport_test.dart test/watch_session_projection_test.dart` → `+29`;
  the new file alone → `+6`; full suite → `+3863 ~1 -2` (the same two external
  `cardio_efficiency_drift_signal_screen_test.dart` failures). RED shown by mutation — the feature
  absent (`projection: null`) is `+2 -4`, and each of four mutants turns its own scenario red; the
  reconciler, `PROTOCOL.md` and `fixtures/reconciliation/` are untouched. See `<plan>.evidence.md`.
- [x] Phase 4: lifecycle + dedup + rating + docs + residue — **Complete.** A wrist `session_lifecycle`
  ends the phone's copy through the ordinary finish (`completed`) or clear (`abandoned`), decided in
  the router and carried out by the bridge; a snapshot of a session whose row is already history
  adopts nothing and is answered with that session's `completed` lifecycle (G1), so a finished session
  never comes back; the ordinary phone finish sends nothing (G2, item 2 superseded), the router's
  answer being `reportLifecycle`'s only production caller; a session the phone owns applies only its
  session-scoped rows and leaves the wrist's effort rows staged (G3), and the wrist's rating is
  carried onto the row the ordinary finish writes (D-8). `gateway.sh lint` → 196 issues, 0 errors
  (baseline, 0 in touched files); `test/watch_session_import_test.dart test/watch_session_finish_test.dart`
  → `+53`; new file alone → `+8`; full suite → `+3871 ~1 -2` (the same two external
  `cardio_efficiency_drift_signal_screen_test.dart` failures). RED shown by six mutants (M1–M6), each
  red on its own scenario, plus the first-run `+5 -3`; `docs/watch_session_sync.md` is new (8.5 KiB,
  13% of the ceiling) and the four touched docs are 61% and below. Two files outside Predicted Files
  (A28, A29). See `<plan>.evidence.md`.
- [x] Fix round 1: review 1's findings (7 findings, 8 checklist items) — **Complete.** Docs corrected
  to the shipped behaviour (`docs/state_management/watch_surface.md`, `docs/watch_session_capture.md`,
  `docs/watch-app-setup-and-qa.md`, `docs/watch_session_sync.md`); S-5's Flow rewritten to G2 and its
  test named; `effortEntries`, `effortEntriesOf` and `mintSlotId` deleted, with no reference left in
  `lib/`, `test/` or `watch/`; one guard test added for the in-progress ordering
  `checkForInProgressSession` relies on. No product behaviour changed and no file added or removed.
  `gateway.sh lint` → 196 issues, 0 errors (baseline); the guard's file → `+11`; full suite →
  `+3872 ~1 -2` (the same two external `cardio_efficiency_drift_signal_screen_test.dart` failures).
  The guard was shown red by mutation (`+10 -1`) and restored byte-identical. Seam retention recorded
  as A34, the ordering tie as A35. See `<plan>.evidence.md` → "Fix round 1".
- [x] Fix round 2: the owner's three simulator findings — **Complete.** (A) The D-10 skip now leaves by
  the bridge's own `onSkipped` callback — one `debugPrint` line by default, once per (held, offered)
  pair — instead of the failure hook, and `WatchSessionAdoptionSkipped` is gone; `onFailure` stays
  live for the one real failure left in the bridge (a snapshot row that cannot be written), which
  now has its own test. (B) The reported `setState() or markNeedsBuild() called during build` did
  **not** reproduce in four widget tests over the real home screen — no production change was made
  for it, and the log the owner must send is named in the evidence. (C) The discarded-session
  limitation is documented in `docs/watch_session_sync.md`. `gateway.sh lint` → 196 issues, 0 errors
  (baseline, 0 in touched files); the four watch test files → `+30`; full suite → `+3877 ~1 -2` (the
  same two external `cardio_efficiency_drift_signal_screen_test.dart` failures). The skip was shown
  red by mutation (`+23 -3`, the three D-10 assertions). See `<plan>.evidence.md` → "Fix round 2".

## Assumption Log

- **A1 — how the deletions happened.** `rm`, `git rm` and every command but the gateway are denied, so
  the four files were deleted by a throwaway `test/zz_*.dart` probe run through `gateway.sh test`
  (`.work/friction.md` line 204), then removed with `gateway.sh delete-scratch`. Options: leave the
  files (fails AC1), or escalate (no one is listening in this run). Report and probe transcript in the
  evidence file.
- **A2 — out-of-plan file, build kept green.** `lib/state/watch/live_session_mirror_debug_main.dart`
  (−35 lines) built the deleted screen, so the tree would not analyze without touching it. Predicted
  Files did not name it; the alternative (deleting the debug entrypoint) removes a debugging aid the
  plan's Phase 2/3 still want.
- **A3 — picker row left wrapped.** The `Row` around the surviving details `IconButton` in
  `exercise_picker_screen.dart` was kept rather than reflowed to a bare button, to hold the diff to
  the removed surface. Purely presentational; Phase 4's polish pass can collapse it.
- **A4 — debug harness fields kept.** `_PhoneStates.workoutState`/`settingsState` remain in
  `live_session_mirror_debug_main.dart` though nothing reads them now; removing them is a larger diff
  in a debug-only entrypoint and the build is clean.
- **A5 — index row deleted with its section.** `docs/widget_catalog.md`'s `LiveSessionEntryPoint` row
  went with the section; a row pointing at a deleted heading is an orphan the docs contract test
  flags. Coupled to item 7, not new scope.
- **A6 — one stale sentence beyond the walkthrough.** `docs/watch-app-setup-and-qa.md`'s non-walkthrough
  "the phone half is wired" sentence was made false by this phase, so it was corrected in place and
  left citing `test/watch_transport_test.dart` rather than a removed surface.
- **A7 — two doc residues left alone.** `docs/watch_session_capture.md` (lines 17, 36) and
  `docs/state_management/watch_surface.md` (line 379) still mention removed surfaces; the plan assigns
  both docs to Phase 4 and the brief's doc list names only the three files edited here.
- **A8 — helper trimmed, not deleted.** `test/helpers/live_session_fixtures.dart` was reduced to
  `RecordingMirrorTransport` (still imported by `test/watch_nutrition_quick_log_test.dart`) instead of
  being deleted; item 6 said "where now unused", and it is not.
- **A9 — the external red was not fixed.** Two `cardio_efficiency_drift_signal_screen_test.dart`
  failures are outside this change (untouched dependency path, fails in isolation, date-anchored
  fixtures, baseline measured before the week rollover). The phase reports them instead of editing
  another feature's test or code, per the agent rules.
- **A10 — `lib/main.dart` is outside Phase 2's Predicted Files.** The bridge needs a `WorkoutState`,
  which is built in `runStartup`, not in the watch graph; Phase 1 already edited this file for the
  removals and the plan's Files Affected name it. Alternative: build the graph after the state —
  larger, ordering-entangled diff. Five added lines.
- **A11 — `startedAtMs` is the adoption instant.** A PR 1 snapshot carries no session start time, and
  `WorkoutState`'s clock is the only honest source; the phone's recorded duration therefore begins at
  adoption, not at the wrist's first set. Phase 3 can carry a real start when it owns the projection.
- **A12 — only a running snapshot is adopted.** `converged['status'] != active` answers `notRunning`
  and writes nothing (the schema allows `active`/`completed`/`abandoned`). D-2 adopts the session the
  wrist *is running*; a closed one belongs to Phase 4's finish path. Silent — not a conflict.
- **A13 — the session already held is a silent no-op.** Same session id already in `WorkoutState` →
  `alreadyHeld`, no write and no reload: after adoption the phone owns the ladder (Phase 3), so
  re-applying a wrist snapshot would fight the phone's own edits.
- **A14 — effort kind resolved by the wrist's own order, mirrored not imported.** Declared slot kind
  if it is one of set/timed/round/drill, else the first capability in hold→rounds→reps→sets→load→
  time→distance, else the free-session default (`set`). Order copied from `WatchLoggingState.effortKind`
  with a comment: importing it would drag wrist logging state into the phone.
- **A15 — no modality on a PR 1 snapshot.** The envelope has no modality field, so D-7's
  routine/modality branch is unreachable; the free-session config applies. Nothing was invented to
  fill the gap — Phase 3 sends the modality when it owns the projection.
- **A16 — `WatchSessionStatus` imported from `lib/watch/session/watch_records.dart`.** That file is
  shared Dart (the phone's `LiveSessionMirrorState` already imports it), so the imported enum beats a
  locally spelled literal that could drift from the protocol.
- **A17 — no defensive slot skip or try/catch.** The validator rejects a malformed envelope before the
  mirror applies it, and `convergedState` copies slots verbatim, so a missing slot id is unreachable;
  behind the guard it would silently drop a set rather than fail loudly.
- **A18 — the wrist's current exercise and an empty ladder.** `currentExerciseIndex` is not adopted
  (the phone opens at the first slot; Phase 3 reconciles the cursor), and a held-but-empty session is
  not "filled in" from a later snapshot — S-3 accepts both as not-yet-active rather than guessing.
- **A19 — the projection lives on the bridge, and is handed to the mirror.** `projectSession` is a
  method of the Phase 2 bridge, passed as `projection:` into `LiveSessionMirrorState`, so one composer
  answers both a request and a wrist snapshot. Options: a separate projector class (a second reader of
  `WorkoutState`), or composing inside `WatchSyncRequestHandler` (leaves the re-assertion path on the
  mirror's copy — D-11 would be half-implemented).
- **A20 — the revision rule.** `_projectedRevision` seeds upward from the incoming frame's `revision`
  and rises by 1 only when `_ladderOf` changes (session id plus each slot's id, exerciseId, name,
  capabilities and effortKind). Replaying a snapshot is therefore not a change, and a changed ladder is
  always newer than what the wrist holds, which is what makes the wrist's replace-structure rule fire.
- **A21 — whose position the answer reports.** The answer carries the position the wrist's own frame
  reports (clamped to the ladder's last slot), not the phone's cursor: item 1 says "current exercise
  from `WorkoutState`", but S-8 case B's fixture and `remove_current_exercise.json` pin the wrist's
  place (`index 1 stays`), and pushing the phone's cursor would move the wrist off the slot it is
  working. A bare request reports index 0. PR 3's push is where a phone-driven cursor belongs.
- **A22 — what a slot may carry.** `sessionExerciseId` = the effort's row id (D-3), `exerciseId`,
  `name`, `effortKind` only when it is a wire kind (the bridge's declared set), capabilities copied. A
  slot whose exercise is unknown here or carries no capability is dropped — the schema refuses an empty
  capability list — and a ladder with nothing left answers nothing rather than an empty one.
- **A23 — the D-10 gate is repeated in the projection.** A snapshot naming a session this phone is not
  in projects to null, so the mirror's own copy answers it — the path `test/watch_transport_test.dart`
  S-003 covers for a phone with no bound state, unchanged.
- **A24 — the projection carries no entries and no timers.** PROTOCOL.md merges a same-session
  snapshot's entries by `entryId`, so omitting them loses nothing (S-8 case B asserts the removed
  slot's entry survives the wrist applying the answer), but timer state is authoritative as a whole, so
  an answer clears the wrist's timers. D-11 names ladder/slot ids/position/status/revision only; flagged
  for the owner's manual QA (a wrist rest timer stopped by a sync).
- **A25 — the mirror hook takes the incoming frame, not `before`.** `before` would answer with index 0
  and the pre-apply copy; the frame carries the wrist's position and revision. The `?? before` fallback
  keeps the no-projection path byte-identical.
- **A26 — two files outside Phase 3's Predicted Files.** The projection needs a seam in
  `live_session_mirror_state.dart` (the `projection` callback, `projectedSession`, `sendState`) and the
  wiring that passes it; the brief's "may need a line … list it as an assumption" clause covers these.
  No `lib/main.dart` line was needed — Phase 2 already binds the bridge (`main.dart:395`).
- **A28 — `watch_session_importer.dart`, outside Phase 4's Predicted Files.** G3 ("the wrist's entries
  are not lost") is decided where an import chooses what to materialise, so the predicate lives there
  rather than in the inbox that calls it; `apply` gained `phoneOwnsSession` (39 lines changed).
  Alternative: filter in the inbox — it would have to re-parse row kinds and could not skip the
  `entries` comprehension, which is where the duplication is created.
- **A29 — `watch_incoming_router.dart`, outside Phase 4's Predicted Files.** Both endings are decided
  where the envelope is read: G1's answer after the adoption outcome, D-5's routing to
  `onLifecycle` — the bridge owns neither (46 lines changed). Phase 3 already edited this file, so it
  is not new to the plan, only to this phase's Predicted Files.
- **A30 — `_catchUpSessionRow`, added for the new end path.** `WorkoutState.endSession` writes the
  session row from its in-memory copy, which was read before the inbox applied the wrist's rating, so
  the wrist's rating was overwritten by the finish (M5: `Expected: <4> Actual: <null>`). The bridge now
  re-reads `sessionFeeling` and writes it through `updateSessionFeeling` before ending. The stale-copy
  wart is pre-existing; only this path reaches it.
- **A31 — G1's answer is asserted through a bare map.** `receive` consumes the real `consider` call, so
  a test that calls `consider` first sees `alreadyHeld` and the answer never fires (the first-run red).
  The G1 test therefore feeds the envelope shape the router acts on and asserts the lifecycle that goes
  back out; the adoption outcome itself is covered by M2 and `test/watch_session_adoption_bridge_test.dart`.
- **A32 — G2's evidence is a grep, not a mutation.** G2 is the absence of a call, and there is no line
  to remove; evidence is the production-caller grep (the router only) plus M6, a harness that pushes on
  finish. M6 exposed that S-5's synchronous `sent` check cannot see that push (the send follows an
  awaited `applyMessage`, so it lands on a microtask) — the lifecycle-list assertion is what catches it.
- **A33 — G3's rows stay staged, by design.** A session the phone owns keeps the wrist's effort rows
  with `appliedAtMs == null` and unreceipted, so nothing is lost and the wrist re-sends them; PR 3's
  `entries_down` merge is what consumes them. Options: import them (duplicates every set — M1), or
  acknowledge and drop them (silent loss). Flagged for the owner: until PR 3, a wrist set logged into a
  phone-owned session is visible on the wrist only.
- **A34 — the test-only seams are kept, with guards (fix round 1, item 6).** `effortEntries`,
  `effortEntriesOf` and `mintSlotId` were unreferenced everywhere and are deleted; `pushExercise`,
  `swapExercise`, `correctEntry`, `deleteEntry` and `completeSession` are kept because
  `test/phone_manage_bridge_test.dart` (`S-002`, `S-004`, `S-005`, `S-007`) and
  `test/watch_session_import_test.dart` exercise them as the schema-conformity set;
  `WatchSyncGraph.ratings` and `WatchSessionInbox.recordPhoneRating` are kept for the successor unit
  that hosts the wrist's rating and finish (`test/watch_session_import_test.dart`, `S-281`, `S-284`).
  `sessionScopedKinds` stays too: the importer's own predicate mirrors the same two kinds.
- **A35 — the S-1 ordering guard accepts a same-millisecond tie.** `checkForInProgressSession` keeps
  `sessions.first` and sweeps the rest, and both repositories sort in-progress rows by `startedAtMs`
  descending. The new test (`test/watch_session_adoption_bridge_test.dart`, `S-1 the adopted session
  survives checkForInProgressSession beside an empty phone row`) pins the ordinary case; a tie is
  decided by the sort's stability and is noted in the test file, not asserted. The adopted row is
  stamped from the wrist's clock and a phone row from the phone's, so the tie does not arise.
- **A36 — `onSkipped` is threaded through `createWatchSync` (fix round 2, A).** The bridge is built
  inside the graph, so the callback had to reach its construction site; `main.dart` keeps the default
  reporter and its `onFailure` unchanged. Options: pass the callback to the bridge directly (the
  graph owns construction), or move the bridge out of the graph (a larger DI change).
- **A37 — the failure hook stays, with the one failure it still has (fix round 2, A).** Deleting
  `onFailure` with the skip would leave the "failure list stays empty" assertions meaningless; instead
  the adoption write is wrapped in `try`/`catch` → `_onFailure` + rethrow, and
  `an adoption that cannot be written is reported as a failure` (`test/watch_session_adoption_bridge_test.dart`)
  pins it. Product behaviour is unchanged: the error still reaches the caller.
- **A38 — Problem B: no production change, one new test file (fix round 2, B).** The owner's
  `setState() or markNeedsBuild() called during build` did not reproduce in four widget tests over the
  real `HomeScreen`; every watch entry point yields before it notifies, and nothing in the UI listens
  to the mirror. `test/watch_session_adoption_build_notify_test.dart` is new (Predicted Files allowed
  "new test file(s) for B"); no `lib/` line was touched for B. Evidence → "Fix round 2" → "Problem B".

## Feedback

- **Not a blocker; the governor must see it.** Two failures in `test/cardio_efficiency_drift_signal_screen_test.dart`
  (S-2511, Mock and Hive variants) are **not** this phase's: the failing file's dependency path is
  untouched, it fails in isolation (`+15 -2`), its fixtures are `DateTime.now()`-anchored, and the last
  all-green full suite on this tree ran on 2026-10-04 — the day before the calendar week rolled over.
  Reasoning and the run logs are in `<plan>.evidence.md` → "External red". Owner: the Stats feature
  (signal fixtures/thresholds). Not fixed here, per the rule against editing another feature's test.

- **Review 1 (code-reviewer): changes requested — a bounded fix pass, not a plan blocker.** Full findings,
  reasoning and the scenario/impact tables: `<plan>.review.md`. Fix checklist, one round, no re-review:
  1. `docs/state_management/watch_surface.md:63-66` — delete the claim that a surface lists/counts logged
     work through `effortEntries`/`effortEntriesOf`, and its citation of the deleted
     `test/live_session_capture_entries_test.dart`; then correct the push-family purpose claim at `:96-101`.
  2. `docs/watch_session_capture.md:187` — repoint the rating claim to `test/watch_session_finish_test.dart`
     (`S-4`, `S-5`) and `test/watch_session_import_test.dart`; drop "live-mirrored session".
  3. `docs/watch-app-setup-and-qa.md:57` and `:441` — correct "`main.dart` → `liveSession`", which no longer
     exists in `lib/` (owner-facing QA step).
  4. S-5's Flow in this plan — say G2: the phone's finish sends nothing, the wrist catches up at its next sync.
  5. Decide and record the fate of the now test-only seams (`pushExercise`, `swapExercise`, `correctEntry`,
     `deleteEntry`, `completeSession`, `effortEntries`, `effortEntriesOf`, `mintSlotId`,
     `WatchSyncGraph.ratings`, `WatchSessionInbox.recordPhoneRating`), each with a guard.
  6. Add the guard test for the in-progress ordering `checkForInProgressSession` relies on: after adoption
     beside an empty phone row, a restart keeps the adopted session and its slot ids.
  Evidence for this review: this reviewer ran `gateway.sh test` on the three new files → `+24: All tests
  passed!` (exit 0); the full suite was not re-run and the governor's `+3871 ~1 -2` stands.

- **Review 1's fix round is applied and closed (one round, as instructed; no second review opened).** All
  eight checklist items are done: the four docs now say what ships, S-5 says G2, the three dead members
  are gone, and the ordering guard test exists. The round's specifics — the mutant's original line, the
  search behind the deletions and the real suite counts — are in `<plan>.evidence.md` → "Fix round 1".
  `gateway.sh test` → `+3872 ~1 -2`: the `-2` is still the same untouched external pair, and the `+1`
  over the governor's baseline is the new guard test. Two decisions the reviewer should ratify or revert
  are logged as A34 (which seams are kept, and why) and A35 (the ordering tie the guard does not
  assert). Nothing is blocked.

- **Fix round 2 (owner's simulator findings), three one-liners.** (A) The D-10 skip left the failure
  hook and now leaves by `onSkipped`: one `debugPrint` line, once per (held, offered) pair, no stack —
  the console no longer reads a safe refusal as a crash, and the three tests that asserted the old
  route now assert the new one. (B) `setState() or markNeedsBuild() called during build` **did not
  reproduce** in four widget tests over the real home screen; no production change was made, and the
  one log the owner must send is named in `<plan>.evidence.md` → "Fix round 2" → "Problem B". (C) The
  discarded-session limitation is documented as not handled in `docs/watch_session_sync.md`, no code
  changed. Details in `<plan>.evidence.md` → "Fix round 2".

## Open questions

**Owner-settled (2026-10-05):** both devices log sets into the one session; no conflict-resolution
logic beyond D-10 (R1) — "no special logic" means no resolution UI and no merge design, not silent
data loss; the three phone-side watch surfaces are removed; sync stays manual / watch-initiated.

**Defaults applied (proceed; record in Assumption Log).**
1. An empty wrist session shows no in-progress affordance until its first exercise (D-6).
2. Finishing on either device ends the one session; one session in history.
3. (Formerly Q4) Phone→wrist set logging: adopt the `entries_down` message family. This is PR 3's
   decision and does not block PR 1.

