# Feature: watch-auto-sync PR 1 — the phone's live session reaches the watch by itself

> **Split (governor, 2026-10-06).** This plan is two PRs. **PR 1a** = Phases 1–2 — the PROTOCOL
> amendment, the start-surface copy, and the wrist's acceptance rules (D-78/D-79/D-80), including the
> wrist's own rest countdown. **PR 1b** = Phase 3 — the phone's push (D-75…D-77, D-81…D-83) and the
> behaviour docs. Nothing is user-visible after 1a alone — the button says "Sync" while a phone change
> still needs a tap — so 1a cannot ship alone (moot for the unreleased v1, but the ordering rule
> stands: Phase 2 lands with or before Phase 3). The split is scope, not design: the PR touches three
> tracks and amends the contract, two soft signals under `.github/copilot/pr-scope-budget.md`.

> Status: DRAFT (planned; no implementation started)
> Next handoff: @developer (PR 1a, Phase 1)
> Series index: `docs/plans/2026-10-06-17-watch-auto-sync-index.md` (series contract D-70…D-74)
> Binding conventions: `docs/global_conventions.md`; `watch/sync_protocol/PROTOCOL.md`;
> `docs/documentation_standard.md`
> Supersedes: `docs/plans/2026-10-05-15-watch-session-sync-index.md` decision 4 ("Sync stays manual /
> watch-initiated") and that series' D-16/"G2" ("the phone's finish is silent") — see D-81.
> Numbering: this PR uses **D-75…D-84** and **S-70…S-84**. D-85…/S-90… are reserved for PR 2
> (`17b`), D-95…/S-100… for PR 3 (`17c`).

## Overview

Work done on the phone about a running session does not reach the watch until somebody taps Sync.
The watch hears nothing: not a set the user logged on the phone, not the exercise the phone added,
not the fact that the phone finished the session. The start surface even says so — "No automatic
sync" — and its button says "Sync routines".

PR 1 gives the phone a live push: whenever the phone's own session changes, the phone sends the
watch its snapshot, and the watch takes it silently. In the same PR the watch stops accepting a
frame that is not about the session it holds, keeps its own place in the ladder and its own rest
countdown, and the start surface's copy stops claiming sync is manual.

The owner's intent and the series' decisions are in the series index; this file is the contract for
PR 1 alone. Nothing here adds a screen, a modal or a button.

## Resolved Decisions (Ledger)

Every entry is enforceable as written. Changes are superseding entries, never edits.

- **D-75 — One push seam on the phone.** Exactly one object pushes a session: a new
  `WatchSessionAutoPush` (`lib/state/watch/watch_session_auto_push.dart`), constructed by
  `createWatchSync` and returned in `WatchSyncGraph`, bound to the `WorkoutState` the app builds in
  `lib/main.dart` (beside `watchSync?.adoption.bindWorkoutState(workoutState)`). It subscribes to that
  state's notifications and is the only caller of the session push. No screen, widget, service or
  repository calls the transport to push a session, and no per-action call site is added anywhere.
  Binding is a no-op the second time; unbinding (a test's `dispose`) removes the listener.
- **D-76 — Trigger: coalesce, then send only what changed.** Every `WorkoutState` notification starts
  (or restarts) a trailing 250 ms window; when it closes, the push composes the payload and sends it
  **only if its deterministic encoding differs** from the last payload this push sent or baselined.
  Composition happens per send and is never cached — the session may have changed again inside the
  window, and the newest state is the one that matters. Consequences that are part of the decision: a
  notification whose payload is unchanged sends nothing (a phone rest-timer tick sends nothing), and
  the sequence of changes inside one window produces exactly one frame. The window length is a
  constructor parameter (`Duration debounce`, default `const Duration(milliseconds: 250)`) so tests
  can drive it. The protocol's `revision` is **not** a sufficient trigger: the phone's projected
  revision rises only when the ladder changes, so a logged set or an end would not move it.
- **D-77 — The push carries the phone's own session and keeps the receiver's place.** The payload is
  the existing D-11 projection — the phone's own ladder, its own entries, status `active`,
  `timers: {}` — sent as a `session_snapshot` by the mirror's own envelope builder, with
  `currentExerciseIndex` taken from the place the **receiver** last reported (the mirror's converged
  state), never slot 0. The same fix applies to `LiveSessionMirrorState.projectedSession()`, which
  today composes with no incoming frame and therefore answers every request with slot 0 — a wrist on
  exercise 3 that asks for a snapshot is yanked to exercise 1. Stated limit of this decision: the
  phone's *own* move of its current exercise is not a position push (only the wrist reports a
  position); a swap or an add reaches the watch as a ladder change, and the wrist keeps its own place
  inside the new ladder.
- **D-78 — The wrist refuses a foreign snapshot, silently.** When the wrist holds a session that is
  `active` and has a non-empty ladder, and an incoming `session_snapshot` names a different
  `sessionId`, the wrist applies nothing, stores nothing, and sends nothing at all — no receipt, no
  snapshot answer, no lifecycle. The guard runs **before** `captureSessionEnd`, so a refused foreign
  snapshot does not end the wrist's own session. A snapshot naming the held session applies exactly
  as today; so does a snapshot naming another session while the wrist holds nothing, or holds a
  session that is finished or has an empty ladder (the phone starting a new workout after the wrist
  finished is the ordinary case and must keep working).
- **D-79 — A phone frame applies only to the session it names.** Every session-scoped apply on the
  watch — `applySnapshot` (D-78), `applyStructureChange`, `applyLifecycle`, `applyTimerState`,
  `applyExercisePush` — refuses a frame whose `sessionId` is absent or different from the held
  session's. Refused means: return `false`, apply nothing, write no row, send nothing. Today
  `applyLifecycle` guards only that *a* session is held (so a phone lifecycle for the phone's own
  other session ends the wrist's), and `applyTimerState` reads the envelope's `sessionId` but never
  compares it. This is the watch's half of the rule the phone already keeps (15-series D-10 and
  `test/watch_session_finish_test.dart` "a lifecycle naming another session changes nothing").
- **D-80 — Each device keeps its own rest countdown.** In `adoptTimers`, an **authoritative**
  snapshot stops a kind only when that kind's newest row was written by the sender — the sender's rows
  are the ones whose `recordId` carries the message-derived timer prefix (`tms-`), and a row the
  wrist created itself carries a generated id. A kind the wrist started itself keeps running across
  any number of incoming snapshots. A kind the message names explicitly as null is still cleared (an
  explicit statement beats the ownership rule), and a kind the message names is adopted as today.
  Symmetrically, the phone's own rest countdown is never stopped by incoming timer state: the mirror
  reports the wrist's timers for display and takes no timer action on the phone.
- **D-81 — The session's end is pushed too, decided by the mirrored session's repository row.**
  **Amended 2026-10-06 (rev 1):** both halves are keyed on the row of the mirrored session X in the
  `WorkoutRepository`, never on the phone's current-session pointer. The pointer is not "the phone
  holds X": `WorkoutState.loadHistoricalSession` (`lib/state/workout/session_core_io.dart:56`, called
  from `lib/features/home/home_screen.dart:173`, `lib/features/calendar/calendar_screen.dart:211` and
  `lib/features/calendar/day_session_list_screen.dart:206`) replaces the pointer with a PAST session
  when the user taps a day in the calendar, and `clearSession()` (`session_core.dart:188`) can null it
  without the row being deleted. So: while the phone mirrors session X as active, if X's row has
  `endedAtMs != null` the push closes the session with `LiveSessionMirrorState.completeSession()` (one
  `completed`, memoised in `_completedRecord`, so a second notification sends nothing); only if X's
  row no longer exists — which is what `discardCurrentSession` → `repository.deleteSession`
  (`lib/state/workout/session_core_lifecycle.dart:93`) produces — does the push report `abandoned`
  once (`reportLifecycle` applies locally, so the mirror's status changes and the rule cannot fire
  again). The check lives in the push, which reads the row through the interface the adoption bridge
  already holds: `WatchSessionAutoPush` takes a narrow
  `Future<TrainingSession?> Function(String sessionId) getSession` seam, wired in `createWatchSync`
  from the `WorkoutRepository` it already has (`repository.getSession`), so `lib/state/` still depends
  on `WorkoutRepository` only. Browsing history therefore sends nothing (S-84): when the pointer is a
  finished past session, `WatchSessionAdoptionBridge.projectSession`
  (`lib/state/watch/watch_session_adoption_bridge.dart:192`) answers null — `!target.hasActiveSession`
  — so the push has no snapshot to send, while X's row still exists unended and fires neither half.
  **This supersedes the 15-series' D-16/"G2"** ("The phone's finish is silent"), which is pinned by
  `test/watch_session_finish_test.dart` ("S-5 the phone's own finish is not reported…", ~line 413) and
  stated in `docs/watch_session_sync.md` (~line 145). The second half of that behaviour is unchanged:
  a phone that has *already* ended the session still answers a wrist snapshot with the end
  (`lib/state/watch/watch_incoming_router.dart:108`).
- **D-82 — A frame the phone applies from the wrist re-baselines the push.** After the frame handler
  in `createWatchSync` has handed a frame to the request handler or to the router, the push
  re-composes the payload and stores it as its baseline **without sending**. So applying a wrist frame
  never causes a push, and a push is never a reply to a wrist's own news.
- **D-83 — Dropped, never queued.** A push the radio cannot carry is dropped. The transport already
  reports the failure (`WatchConnectivityTransport.send` → `onFailure`, which `lib/main.dart` prints in
  debug) and never throws; the push adds no queue, no retry, no reachability polling and no
  user-visible state. What a peer missed arrives by that peer's own catch-up (PR 2/`17b`). A push that
  cannot be carried must not disturb the phone: no exception, no state change, no repeated attempt.
- **D-84 — The copy states what is true.** The watch start surface's button reads **"Sync"**. The
  string `noAutoSyncLabel` ("No automatic sync") and the widget that renders it are deleted from both
  stacks and from the contract fixture, and are not replaced with new prose: the hint explained why the
  app never syncs by itself, which is no longer true, and the button's own word needs no subtitle.
  `unreachableLabel` ("Phone not reachable") and the empty-routines sentence ("No routines yet. Sync
  with your phone to get them.") stay — routines are still manual (series D-72), and "Phone not
  reachable" is the one case the button is still for. No other copy changes.

## Feature Invariants

Only what bites here; project-wide rules live in `docs/global_conventions.md`.

- **Two engines, one rule set.** `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
  and its Dart twin `lib/watch/session/watch_session_engine.dart` apply the same rules to the same
  frames; every D-78/D-79/D-80 rule lands in both, with the same refusal semantics.
- **The wrist's store is append-only.** Nothing already stored is rewritten or deleted; a rule that
  "corrects" a row appends a new one. A refusal (D-78/D-79) appends nothing.
- **A snapshot is never answered with an equal one**, in both directions (today's rule; the push must
  not create a loop — see D-76/D-82).
- **Composition is per call, never cached** (15-series D-11): the projection is read fresh from the
  phone's own session each time a payload is composed.
- **The push persists nothing.** It reads the phone's session and sends; no repository write, no new
  persisted field, no schema change, so `HiveWorkoutRepository`/`MockWorkoutRepository` parity is
  untouched by this PR.
- **Layer boundary.** `lib/state/…` depends on `WorkoutRepository` only; nothing added here imports a
  concrete repository.

## Requirements

1. A change the user makes on the phone to the running session reaches the watch without the Sync
   button: a logged set, a ladder change, the current exercise moving (as a ladder change), the
   session finishing, the session being discarded.
2. The watch never loses its own work or its own context to a phone frame: its logged entries, its
   place in the ladder, and its running rest countdown survive.
3. A phone frame about a session the watch is not in changes nothing on the watch, and says nothing
   back.
4. A change that reaches the watch is idempotent: the same frame twice changes nothing the second time.
5. A phone whose watch cannot be reached behaves exactly as today: no queue, no error, no banner.
6. The start surface says "Sync" and no longer claims sync is not automatic; both stacks say the same
   thing, from the shared fixture.
7. `watch/sync_protocol/PROTOCOL.md` records the new rules additively (v1 is unreleased: no version
   bump, no migration).

## Acceptance Criteria

| # | Criterion | Scenarios |
|---|---|---|
| AC-1 | A set logged on the phone for the mirrored session is on the watch within the debounce window, without any user action on the watch | S-70, S-80 |
| AC-2 | A ladder change on the phone (add / swap) shows on the watch, and the watch's place and its own countdown are unchanged | S-71, S-76, S-79 |
| AC-3 | Finishing on the phone ends the session on the watch; discarding on the phone abandons it there; browsing a past session while a live one is mirrored sends neither | S-72, S-73, S-84 |
| AC-4 | A notification that composes an unchanged payload sends nothing, and a burst of changes sends one frame | S-74, S-75 |
| AC-5 | The wrist refuses a snapshot naming another session while it holds an active one with a ladder: nothing applied, nothing sent | S-77 |
| AC-6 | A lifecycle / timer / structure / exercise-push frame naming a session the watch does not hold changes nothing there | S-78 |
| AC-7 | The wrist's own rest countdown survives a phone snapshot; the phone's own countdown survives a wrist frame | S-79, S-80 |
| AC-8 | A re-delivered frame changes nothing the second time | S-81 |
| AC-9 | An unreachable watch: the push is dropped and reported, the phone is undisturbed, nothing is queued | S-83 |
| AC-10 | Both stacks' start surfaces read "Sync" and carry no "No automatic sync", validated against the shared fixture | S-82 |
| AC-11 | Every rule above is in both engines (Swift and the Dart twin), with the same outcomes | all S-70…S-81 (run in both stacks) |

## Existing-Functionality Impact

Each row: the touched surface → what already reads it (with the grep that found it) → the effect → what
guards it.

| Touched surface | What already reads it | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchStartSurfaceCopy.noAutoSyncLabel` (`WatchStartPaths.swift:38`) | grep `noAutoSyncLabel`: `WatchStartView.swift:34` (via `WatchNoAutomaticSyncHint`), rendered at `:165`; `watch/contract/watch_start_paths_contract.json:242`; `WatchSessionStartPathsTests.swift:361`; `WatchConnectivityBridgeTests.swift:488,497`; `lib/watch/start/watch_start_screen.dart:60,272`; `test/watch_session_start_test.dart:1032,1035,1064`; `test/watch_transport_test.dart:99`; historical rows in `docs/plans/2026-10-04-14-…-plan.evidence.md:272,308,316` (**history — never edit**) | The string and both hint widgets are deleted; the button label changes to "Sync" | S-82 (both stacks + the fixture); the 14-series' evidence rows are history and stay as they are |
| `WatchStartSurfaceCopy.syncLabel` (`WatchStartPaths.swift:42`) | `WatchStartView.swift:110,158`; contract JSON `:243`; `WatchSessionStartPathsTests.swift:361…`; `WatchConnectivityBridgeTests.swift:497…`; `lib/watch/start/watch_start_screen.dart:64,88`; `test/watch_session_start_test.dart:1045,1055,1063` | "Sync routines" → "Sync". The button's visibility rule (shown only when the phone can be asked) and its action are unchanged | S-82 |
| `LiveSessionMirrorState.projectedSession()` (`:276`) | grep `projectedSession(`: exactly one production reader, `watch_sync_request_handler.dart:102`; tests in `test/live_mirroring_test.dart`, `test/watch_session_projection_test.dart` | It now composes with the receiver's place instead of slot 0. A manual Sync stops yanking the wrist to exercise 1; the handler's answer is unchanged in every other respect | S-76 |
| `LiveSessionMirrorState.state` / `convergedState()` | the mirror's own readers (the live-session view, `currentExerciseIndex`, `entries`) and every test of the mirror | Read (not written) by the push for the receiver's place | S-76, S-80 |
| `WatchSessionAutoPush` (**new**) | nothing yet | A new listener on `WorkoutState`; it adds one listener and removes it on dispose; it reads the mirrored session's row through a `getSession` seam (`repository.getSession`, typed on `WorkoutRepository`) | S-70…S-76, S-83, S-84 |
| `createWatchSync` / `WatchSyncGraph` (`lib/state/watch/watch_sync_wiring.dart`) | `lib/main.dart:370` (`createWatchSync(...)`) and `:390` (`watchSync?.adoption.bindWorkoutState`); tests constructing the graph (`test/watch_session_*`) | Builds the push with the `getSession` seam from the `WorkoutRepository` it already holds, binds it to `WorkoutState` and returns it in the graph | S-70, S-82, S-84 (the wiring's tests still pass) |
| `WorkoutState` notifications (`lib/state/workout_state.dart:18`) | every screen; `SessionCore`/`TimerManager` notify on every mutation *and* every timer tick | Now also read by the push — a listener that must be cheap (D-76: the window collapses ticks into nothing) | S-74 (a tick sends nothing) |
| `WorkoutState.currentSession` pointer — `loadHistoricalSession` (`lib/state/workout/session_core_io.dart:56`) and `clearSession` (`lib/state/workout/session_core.dart:188`) | grep `loadHistoricalSession`: `lib/features/home/home_screen.dart:173`, `lib/features/calendar/calendar_screen.dart:211`, `lib/features/calendar/day_session_list_screen.dart:206`; `clearSession` runs from `discardCurrentSession` (`session_core_lifecycle.dart:100`) and other lifecycles | The end rules must NOT key on the pointer, which calendar browsing repoints at a past session — they key on the mirrored session's repository row read through the push's `getSession` seam (D-81). A finished past session makes `projectSession` (`watch_session_adoption_bridge.dart:192`, `!hasActiveSession`) answer null, so it is never pushed | S-84, S-72, S-73 |
| Swift `applySnapshot` (`:439`) / Dart `_applySnapshot` (`:438`) | `applyMessage`; `WatchSessionEngineTests.swift`, `WatchLiveMirroringTests.swift`, `test/watch_session_engine_test.dart`, `test/watch_reconciliation_cross_stack_test.dart` | Gains the foreign-session refusal (D-78) **before** `captureSessionEnd` | S-77 |
| Swift `applyLifecycle` (`:530`) / Dart `_applyLifecycle` (`:528`) | same test files; `WatchCaptureContractTests` (the end-of-session capture) | Gains the session guard (D-79) | S-78 |
| Swift `applyTimerState` (`:595`) / Dart `_applyTimerState` (`:568`) | `WatchLoggingTimersTests.swift`, `test/watch_logging_timers_test.dart` | Gains the session guard (D-79) | S-78 |
| Swift `applyStructureChange` (`:494`) / Dart `_applyStructureChange` (`:491`) | `WatchSessionEngineTests.swift` (`changeId` replay), `test/watch_session_engine_test.dart` | Gains the session guard (D-79) | S-78 |
| Swift `applyExercisePush` / Dart `_applyExercisePush` | `test/phone_manage_bridge_test.dart`, `test/watch_session_merge_test.dart` | Gains the session guard (D-79) | S-78 |
| Swift `adoptTimers` (`:619`) / Dart `_adoptTimers` (`:588`) | `WatchLoggingTimersTests.swift`, `test/watch_logging_timers_test.dart`, `WatchSessionEngineTests.swift` | An authoritative sweep no longer stops a kind the wrist owns (D-80) | S-79 |
| `stopTimerFromMessage` (`:688`) / `_stopTimerFromMessage` (`:672`) | the two timer test files | Unchanged; it is the mechanism the ownership rule gates | S-79 |
| The phone's own rest countdown (`WorkoutState`/`TimerManager`) | the session screen, `docs/rest_tracking.md` | Must not be stopped by incoming timer state; verified, not changed | S-79 (phone half) |
| `test/watch_session_finish_test.dart` "S-5" (`:413`) | the test itself; the 15-series' plan and index describe it | Its first expectation flips (the phone's finish is now reported); the rest of the file is unchanged | S-72, S-73 |
| `watch/sync_protocol/PROTOCOL.md` | `SyncProtocolValidator`, both engines' comments, `SyncProtocolFixturesTests.swift`, `test/watch_reconciliation_cross_stack_test.dart` | Gains an additive 2026-10-06 amendment; no version bump (v1 unreleased) | S-70…S-81 (each rule's test is named in the amendment) |

## Scenarios

Fixtures name every value. "The wrist's own rows" means rows the wrist wrote (its own logged sets, its
own timers); "phone rows" means what the phone's projection carries.

### S-70: a set logged on the phone reaches the wrist by itself
- Fixture: session `s-1`, started on the wrist, adopted by the phone; ladder `[sx-1 (squat:
  sets/reps/load), sx-2 (bench: sets/reps/load)]`, wrist index `0`. Wrist entries: its own
  `e-w1` (set 1 of `sx-1`, 60 kg × 8). Phone has no entry yet. Phone `WorkoutState`: session `s-1`
  active, current exercise `sx-1`, one repetition screen; transport = a recording fake.
- Trigger: the phone logs `e-p1` (set 2 of `sx-1`, 62.5 kg × 8) and `WorkoutState` notifies; the
  debounce window (250 ms) closes.
- Flow: the push composes the projection (ladder `[sx-1, sx-2]`, entries `[e-p1]`, index from the
  converged state = 0), sends one `session_snapshot`; the wrist applies it (same session).
- Expected outcome: the wrist's stored entries for `s-1` are `e-w1` and `e-p1`; the wrist's ladder is
  still `[sx-1, sx-2]`; its index is still `0`; exactly one frame left the phone; `e-w1` was not
  rewritten.
- Edge case of: none.

### S-71: an exercise added on the phone shows on the wrist, which keeps its place and its timer
- Fixture: as S-70's fixture, plus a wrist rest countdown running: a timer row of kind `rest`,
  `recordId` `t-1` (wrist-created), `startedAt` 30 s before now, `stoppedAt` null, planned 90 s; wrist
  index `1` (`sx-2`). Phone ladder `[sx-1, sx-2]` with `sx-2` current.
- Trigger: the phone adds `sx-3` (row: sets/reps/load) to the session, then notifies.
- Flow: one push carrying ladder `[sx-1, sx-2, sx-3]`, index 1 (the converged place, not the phone's
  own), `timers: {}`; the wrist applies it.
- Expected outcome: the wrist's ladder is `[sx-1, sx-2, sx-3]` (by `sessionExerciseId`), index `1`,
  and the `rest` countdown is still running (`newestTimer(kind: "rest").recordId == "t-1"`,
  `stoppedAt == null`); one frame left the phone.
- Edge case of: S-70 (same push, a ladder change instead of an entry).

### S-72: finishing on the phone ends the session on the wrist
- Fixture: session `s-1` mirrored and active on both, wrist index `1`, wrist entry `e-w1`, phone entry
  `e-p1`; the phone's `WorkoutState.currentSession` for `s-1` gains `endedAtMs` (the user tapped
  Finish) and `hasActiveSession` is false.
- Trigger: the resulting `WorkoutState` notification, window closed.
- Flow: the push reads X's row through its `getSession` seam, sees `endedAtMs != null` while the
  mirror still holds it as `active`, and calls `mirror.completeSession()` → one `session_lifecycle`
  `completed`; a further notification inside the same situation sends nothing (`_completedRecord` is
  set); no snapshot is sent (the projection returns null: the phone has no active session).
- Expected outcome: exactly one lifecycle frame, `completed`, `sessionId` `s-1`; the mirror's status is
  `completed`; the wrist's status is `completed`; the wrist's `s-1` end row is present and its entries
  `e-w1`/`e-p1` are untouched.
- Edge case of: none. **Replaces** the 15-series' S-5 expectation (that no frame is sent).

### S-73: discarding on the phone abandons the session on the wrist
- Fixture: as S-72's, except the phone discards: `s-1` is removed from the phone and never had
  `endedAtMs`; the mirror still holds `s-1` as `active`.
- Trigger: the resulting notification, window closed.
- Flow: X's repository row is gone (the phone's `discardCurrentSession` → `repository.deleteSession`),
  and X never had `endedAtMs`, so the row-reading half of D-81 fires → one `session_lifecycle`
  `abandoned` (applied locally by the mirror, so the rule cannot fire twice).
- Expected outcome: exactly one lifecycle frame, `abandoned`; the wrist's status for `s-1` is
  `abandoned`; the wrist's entries are untouched.
- Edge case of: S-72 (the other way a session ends).

### S-74: a phone tick sends nothing
- Fixture: as S-70's fixture after that push; a recording fake transport that counts frames. The phone's
  session state notifies five times with no change to the composed payload (a rest-timer tick each
  second, then two UI notifies).
- Trigger: the five notifications; each window closes.
- Flow: each window composes; each payload encodes identically to the last sent payload.
- Expected outcome: zero further frames.
- Edge case of: S-70 (the negative: the payload-equality gate, not a revision).

### S-75: a burst of changes is one frame
- Fixture: as S-70's fixture after that push. Three changes land inside one 250 ms window: `sx-3`
  added, `sx-4` added, `e-p2` logged.
- Trigger: the three notifications; the window closes once.
- Flow: one composition of the newest state.
- Expected outcome: exactly one frame, whose payload carries ladder `[sx-1, sx-2, sx-3, sx-4]` and
  entries `[e-p1, e-p2]`.
- Edge case of: S-74 (the same gate, a changing payload).

### S-76: a manual Sync no longer yanks the wrist to its first exercise
- Fixture: session `s-1` on both; ladder `[sx-1, sx-2, sx-3]`; the wrist is on index `2` (`sx-3`) and
  has told the phone so (the mirror's converged index is 2); phone ladder identical; the phone's own
  session's current exercise is `sx-1`.
- Trigger: the wrist asks for a snapshot (`WatchSyncRequestHandler.handle(routines|snapshot)`).
- Flow: `projectedSession()` composes from the phone's ladder with index 2.
- Expected outcome: the frame carries `currentExerciseIndex: 2`; the wrist's index is still `2`.
  (Without the fix it carries `0` and the wrist jumps to `sx-1`.)
- Edge case of: S-70. This is the mutation check for D-77: reverting `projectedSession()` to
  `_projection.call(null)` turns it red.

### S-77: the wrist refuses a foreign snapshot, silently
- Fixture: the wrist holds its own `s-2`, active, ladder `[sx-9]`, wrist index `0`, its own entry
  `e-w2`, and its own running `rest` timer `t-2`. The phone sends a snapshot for `s-1` (ladder
  `[sx-1, sx-2]`, status `active`, entries `[e-p1]`) — the phone is in its own session.
- Trigger: `applyMessage(the s-1 snapshot)`.
- Flow: the refusal is checked before anything is captured or stored.
- Expected outcome: `applyMessage` returns false; the wrist's held session is still `s-2` with ladder
  `[sx-9]`, index `0`; `e-p1` is absent; no `snap-…` row was written; no end was captured for `s-2`;
  **no frame was emitted** (the recording forwarder saw nothing). Counter-case in the same scenario:
  the wrist holds `s-2` with status `completed` → the same snapshot applies (the new workout case).
- Edge case of: none. Fixture must include the *held different* session — a test with the wrist holding
  nothing passes both with and without the rule, and proves nothing.

### S-78: a frame naming a session the wrist does not hold changes nothing
- Fixture: the wrist holds `s-2` (active, ladder `[sx-9]`, index `0`, status active). Four frames
  arrive, each naming `s-1`: (a) `session_lifecycle` `completed`; (b) `session_lifecycle`
  `exercise_advanced` with `exerciseIndex: 0`; (c) `timer_state` naming `rest` started 10 s ago;
  (d) `structure_change` with a fresh `changeId` removing `sx-9`; (e) `exercise_push` adding `sx-10`.
- Trigger: each frame through `applyMessage`.
- Flow: each is refused by the session guard.
- Expected outcome: each returns false; `s-2` is still active with ladder `[sx-9]`; no lifecycle row,
  no timer row, no change row, no pushed slot was written. (Today (a) sets `s-2`'s status to
  `completed`, and (c) adopts a timer into `s-2` — the mutation check: removing the guard turns it
  red.)
- Edge case of: S-77 (the same rule for the other frame types).

### S-79: each device keeps its own countdown
- Fixture: the wrist holds `s-1` (active, ladder `[sx-1, sx-2]`, index `0`) with its own running
  `rest` timer `t-1` (wrist id, planned 90 s, `stoppedAt` null) and a phone-written `round` timer
  `tms-m-7-round` (running). The phone sends a snapshot for `s-1` with `timers: {}`.
- Trigger: `applyMessage(the snapshot)`, authoritative for timers as a whole.
- Flow: `rest` is not named by the message and its newest row is the wrist's → left running; `round` is
  not named and its newest row is the phone's → stopped.
- Expected outcome: `newestTimer(kind: "rest")` is still `t-1` with `stoppedAt == null`; `round` has a
  new stopped row. Phone half of the same scenario: while the phone's own rest countdown runs, the
  wrist sends a snapshot with `timers: {}` and the phone's countdown still reaches its end.
- Edge case of: S-71 (the same rule, reached through the phone's push).

### S-80: both devices' logged sets survive a push in both directions
- Fixture: session `s-1` active on both; ladder `[sx-1]`; wrist entry `e-w1`; phone entry `e-p1`.
- Trigger: the wrist logs `e-w2` (its `observations_up`) and, in the same window, the phone logs
  `e-p3` and pushes; the phone then applies the wrist's `observations_up` (the D-82 re-baseline path).
- Flow: the wrist merges the snapshot by `entryId` (its own rows untouched); the phone merges the
  observation and re-baselines.
- Expected outcome: after the exchange the wrist holds `e-w1`, `e-p1`, `e-p3` plus its own `e-w2`, and
  the phone's mirror holds all four; **no frame follows the wrist's observation** (re-baselined, not
  answered).
- Edge case of: S-70.

### S-81: a re-delivered frame changes nothing
- Fixture: as S-70's fixture, after the push has been applied; the same snapshot re-delivered with the
  same `messageId`.
- Trigger: `applyMessage(the same snapshot again)`.
- Expected outcome: nothing changes on the wrist (no new row ids, entries unchanged, timers unchanged);
  the count of stored rows for `s-1` is identical. The same holds for the lifecycle of S-72 and the
  `observations_up` of S-80.
- Edge case of: S-70 (idempotency, which the push's fire-and-forget transport relies on).

### S-82: the start surface says "Sync" and no longer claims sync is not automatic
- Fixture: the contract fixture `watch/contract/watch_start_paths_contract.json` +
  `WatchStartSurfaceCopy` + `WatchStartScreen` + the two Swift views + the Dart widget tree.
- Trigger: read both stacks' surface copy, and render both surfaces.
- Flow: —
- Expected outcome: `syncLabel == "Sync"` in all three sources; the string "No automatic sync" appears
  in none of them; the rendered watch surface contains no hint widget; the rendered Dart surface
  contains no "No automatic sync" text; `unreachableLabel` and the empty-routines sentence are
  unchanged. The contract `startSurface` object has exactly the key `syncLabel`.
- Edge case of: none.

### S-83: an unreachable watch changes nothing on the phone
- Fixture: as S-70's fixture, with a transport whose `send` reports a failure (the real
  `WatchConnectivityTransport` swallows it and calls `onFailure`).
- Trigger: the phone logs `e-p1`; the window closes.
- Flow: one send attempt; the failure is reported; the push does not retry.
- Expected outcome: `onFailure` was called once; the phone's state is unchanged (same entries, no
  exception propagated, no queued payload); a second identical change after the failure sends again
  (the phone does not remember a delivery it never made as one it did — the baseline is the *sent*
  payload, and the same payload is not re-sent until it changes... **note:** the baseline records what
  was sent, so a failed send of a payload leaves that payload baselined; recovery is PR 2's catch-up).
- Edge case of: S-70.

### S-84: browsing a past session on the phone while a live session is mirrored sends nothing
- Fixture: the phone holds live session X (`s-1`), mirrored and active on both devices; ladder
  `[sx-1, sx-2]`; the phone's history also holds past session H (`h-1`), **finished** (`endedAtMs`
  set), with its own ladder `[hx-1]` and its own entries `[e-h1]`. The push's baseline is the payload
  it last sent for X.
- Trigger: the user opens H on the phone — `WorkoutState.loadHistoricalSession('h-1')` repoints the
  current-session pointer at H (`lib/state/workout/session_core_io.dart:56`) — and the resulting
  notification's window closes.
- Flow: the push reads X's repository row through its `getSession` seam. The row exists and
  `endedAtMs == null`, so neither the completed nor the abandoned half of D-81 fires. The payload it
  would compose comes from `projectSession`, which answers null for the finished past session
  (`!target.hasActiveSession`) — nothing to send.
- Expected outcome: **no frame at all** — no snapshot of H, no `abandoned` for X — and the baseline is
  unchanged. Then the user returns to X (`loadHistoricalSession('s-1')` or the live session screen):
  the payload composes to the baseline, so the equality gate (D-76) sends nothing either.
- Edge case of: S-73 (the same rule, keyed on the row). **Mutation seed:** key the abandoned rule on
  the pointer (`currentSession == null || currentSession.id != X`) instead of X's row — the
  `loadHistoricalSession('h-1')` notification then fires it and pushes `abandoned` for X, turning this
  scenario red.

## Iteration 1 (PR 1a: Phases 1–2 · PR 1b: Phase 3)

### Phase 1: The contract amendment and the copy (@developer) — PR 1a

1. [ ] *(deferred by the governor — see A-1; `PROTOCOL.md` is not edited in Phase 1)* Amend
   `watch/sync_protocol/PROTOCOL.md` additively — a dated `2026-10-06` section
   (`## 2026-10-06 — automatic session sync`), stating: a peer may send a `session_snapshot` without
   being asked (the phone does so whenever its own session changes, at most once per ~250 ms window);
   a snapshot keeps the receiver's position when the ladder is unchanged; a session-scoped frame
   applies only to the session it names and a receiver refuses a foreign one silently; a receiver that
   holds its own active session keeps it (the conflict rule, both directions); timer ownership
   (authoritative snapshots do not stop a kind the receiver started); the phone's session end is
   announced; frames are dropped, never queued. Each rule cites its plan id (`D-77`…`D-83`) and the
   test that proves it, per `docs/documentation_standard.md`. No version bump: v1 is unreleased.
2. [x] `watch/contract/watch_start_paths_contract.json`, `startSurface` block (~`:241`): delete the
   `noAutoSyncLabel` key; set `"syncLabel": "Sync"`.
3. [x] `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`: delete
   `WatchStartSurfaceCopy.noAutoSyncLabel` (`:38`); set `syncLabel = "Sync"` (`:42`).
4. [x] `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`: delete the
   `WatchNoAutomaticSyncHint` struct (`:33-42`) and its render line (`:165`).
5. [x] `lib/watch/start/watch_start_screen.dart`: delete the `noAutoSyncLabel` constant (`:60`), the
   `NoAutomaticSyncHint` class (`:265-275`) and its use (`:84`); set `syncLabel = 'Sync'` (`:64`).
6. [x] `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` (`:355-370`):
   drop the `noAutoSyncLabel` assertion, assert `syncLabel == "Sync"`.
7. [x] `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`: replace the
   `WatchNoAutomaticSyncHint()` presence assertion (`:488`) with its absence — the structural guard
   that the hint cannot come back — and drop the `noAutoSyncLabel` assertion (`:497`).
8. [x] `test/watch_session_start_test.dart`: delete the test "the screen says there is no automatic
   sync" (`:1019-1038`); in the sync-action test (`:1040-1067`) drop the `noAutoSyncLabel` lines
   (`:1032,1035,1055,1064`) and assert the new label; `test/watch_transport_test.dart:99` if it names
   the old string.
9. [ ] *(deferred by the governor — see A-2; `docs/watch-app-setup-and-qa.md` is not edited in
   Phase 1)* `docs/watch-app-setup-and-qa.md`: the walkthrough step that says the watch reports no
   automatic
   sync and every step that treats tapping Sync as the way logging gets across — rewrite to say
   "logging is automatic; Sync recovers a device that was out of reach and refreshes the routine
   list"; the routine steps stay.

**Done Criteria** (run until green):
- `.github/copilot/scripts/macos/gateway.sh lint` — issue count at or below this plan's baseline
  (196 issues, 0 errors; compare counts, not exit code).
- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_start_test.dart test/watch_transport_test.dart test/docs_indexing_contract_test.dart`
- `.github/copilot/scripts/macos/gateway.sh swift-test` — the package's tests, previously 294 passing
  / 0 failures, with the changed assertions green.
- Grep residue (by hand, recorded in the evidence file): `noAutoSyncLabel` and `NoAutomaticSyncHint`
  return nothing under `lib/`, `test/`, `watch/` — except the historical plan evidence named in the
  Impact Check, which is never edited.
- *Governor only:* build the watch scheme (`xcodebuild` for a watchOS simulator) — the Swift package
  compiles and the watch app target builds; agents do not run `xcodebuild`.

**Predicted Files**: `watch/sync_protocol/PROTOCOL.md`,
`watch/contract/watch_start_paths_contract.json`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`,
`lib/watch/start/watch_start_screen.dart`, `test/watch_session_start_test.dart`,
`test/watch_transport_test.dart`, `docs/watch-app-setup-and-qa.md`. Nothing else.

### Phase 2: The wrist's acceptance rules (@developer) — PR 1a

1. [ ] `WatchSessionEngine.swift`, `applySnapshot` (`:439`): before `captureSessionEnd`, refuse when
   `current != nil && current.status == WatchSessionStatus.active && !current.exercises.isEmpty &&
   current.sessionId != sessionId` — return false, store nothing, emit nothing (D-78). Use one helper
   (`guardSession(_ envelope:) -> Bool` or an inline predicate) so the rule reads the same in every
   apply.
2. [ ] Same file, `applyLifecycle` (`:530`): add the session guard (D-79) — the envelope's
   `sessionId` must equal the held session's; today only `current != nil` is guarded.
3. [ ] Same file, `applyTimerState` (`:595`): add the session guard (D-79) — it already parses
   `sessionId`; compare it.
4. [ ] Same file, `applyStructureChange` (`:494`) and `applyExercisePush`: the same guard.
5. [ ] Same file, `adoptTimers` (`:619`): in the not-named branch, stop the kind only when
   `timers.keys.contains(kind)` (an explicit null) or the newest row for that kind is the sender's
   (its `recordId` starts with `Self.timerPrefix`) — an authoritative snapshot no longer stops a kind
   the wrist started (D-80). `stopTimerFromMessage` itself is unchanged.
6. [ ] `lib/watch/session/watch_session_engine.dart`: the same five rules at `_applySnapshot` (`:438`),
   `_applyStructureChange` (`:491`), `_applyLifecycle` (`:528`), `_applyTimerState` (`:568`),
   `_adoptTimers` (`:588`), worded and ordered identically (Feature Invariant: two engines, one rule
   set).
7. [ ] Swift tests: `WatchSessionEngineTests.swift` (mid-session homing) — the S-77 refusal and its
   two counter-cases, the S-78 four-frame refusal, the S-81 replay; `WatchLiveMirroringTests.swift`
   (switch-on-a-snapshot) — a foreign snapshot no longer switches the held session and emits nothing;
   `WatchLoggingTimersTests.swift` — S-79's two kinds.
8. [ ] Dart tests: `test/watch_session_engine_test.dart` — the same S-77/S-78/S-79/S-81 cases against
   the twin; `test/watch_logging_timers_test.dart` — S-79's two kinds both ways;
   `test/watch_reconciliation_cross_stack_test.dart` — unchanged expectations still pass.
9. [ ] Note the 15-series evidence row whose mutation check was "delete `WatchNoAutomaticSyncHint()`"
   (`docs/plans/2026-10-04-14-…-plan.evidence.md:308`) is now historical: that struct no longer exists.
   Record it in this plan's evidence file; do not edit the old file.

**Done Criteria** (run until green):
- `.github/copilot/scripts/macos/gateway.sh lint`
- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_logging_timers_test.dart test/watch_reconciliation_cross_stack_test.dart`
- `.github/copilot/scripts/macos/gateway.sh swift-test` — all pass; paste the counts.
- Red→green: for S-77 and S-79 the new test must be shown failing with the rule stashed (the plan's
  evidence file records both runs' counts).
- `docs/`-only: `test/docs_indexing_contract_test.dart` with the other Dart suites.

**Predicted Files**:
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`,
`lib/watch/session/watch_session_engine.dart`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLiveMirroringTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`,
`test/watch_session_engine_test.dart`, `test/watch_logging_timers_test.dart`. Nothing else.

**Status: Complete** (2026-10-06). Steps 1–9 done, plus the governor's step 10 (`PROTOCOL.md` amended:
the session-switch exception, the session-scoped frame rule, timer ownership — each naming a test that
exists). Red→green shown for S-77, S-78 and S-79 on both stacks; counts in the evidence file.
`test/watch_session_projection_test.dart` needed one added line (S-40 pinned the superseded
wholesale-adoption rule) — see A-5.
**Handoff callout for Phase 3:** `docs/watch_session_sync.md`'s "the phone's rest timer is not carried"
bullet is now true only of a countdown the *phone* started (A-9), and the wrist's end-capture rule has
no Dart twin (A-8).

### Phase 3: The phone's push (@developer) — PR 1b

1. [ ] New `lib/state/watch/watch_session_auto_push.dart`: `class WatchSessionAutoPush` — constructor
   `({required LiveSessionMirrorState mirror, required Future<TrainingSession?> Function(String sessionId) getSession, Duration debounce = const Duration(milliseconds: 250)})`;
   `void bindWorkoutState(WorkoutState state)` (idempotent; adds one listener; `dispose()` removes it);
   a private `_onChanged()` that restarts the trailing `Timer`; `Future<void> flush()` that cancels the
   pending timer and performs one compose-and-maybe-send (the deterministic-encoding comparison of
   D-76 lives here); `Future<void> rebaseline()` (compose and store, send nothing — D-82); a
   `Duration debounce` knob. Encodes payloads by `jsonEncode` over a recursively key-sorted copy —
   **`Map` equality is identity in Dart and must not be used**.
2. [ ] Same file: the end rules (D-81), keyed on the mirrored session X's repository row through the
   `getSession` seam — never on the pointer (`state.currentSession`), which `loadHistoricalSession`
   repoints at a past session. While the mirror holds X as active: if `await getSession(X.id)` answers
   a row with `endedAtMs != null` → `await mirror.completeSession()`; if it answers null (the row is
   gone) → `await mirror.reportLifecycle(WatchLifecycleState.abandoned)`. While the pointer is a past
   session H, X's row still exists unended, so neither half fires (S-84).
3. [ ] Same file: the push itself — `final composed = await mirror.projectedSession(); if (composed != null) await mirror.sendState(composed);` only when the encoding differs from the baseline;
   update the baseline with what was sent. Send nothing when the phone has no session of its own
   (nothing to assert).
4. [ ] `lib/state/watch/live_session_mirror_state.dart`, `projectedSession()` (`:276`): compose with
   the receiver's place — `_projection?.call(state)` instead of `_projection?.call(null)` — so a push
   and a request answer never carry slot 0 (D-77). Update its doc comment and the D-11 reference.
5. [ ] `lib/state/watch/watch_sync_wiring.dart`: construct the push after the mirror with
   `getSession: repository.getSession` (the `WorkoutRepository` already in scope — `lib/state` stays on
   the interface); `resolved.onIncoming` calls `await push.rebaseline()` after the request handler or
   the router has applied a frame (D-82); add `final WatchSessionAutoPush autoPush` to `WatchSyncGraph`.
6. [ ] `lib/main.dart` (`:390`): `watchSync?.autoPush.bindWorkoutState(workoutState);` beside the
   adoption bind, with a one-line comment naming D-75.
7. [ ] New `test/watch_session_auto_push_test.dart`: plain `test()` (no `testWidgets` — a real debounce
   needs the real clock) with a fake transport recording frames — S-70, S-71 (ladder + the wrist's own
   timer untouched is asserted in Phase 2's engine test; here the payload), S-72, S-73, S-74, S-75,
   S-80's phone half, S-81's replay-from-the-phone-half, S-83 (a failing transport), and **S-84** (the
   `getSession` fake answers X's row present and unended while the pointer is repointed at a finished
   past H — assert zero frames and an unchanged baseline).
8. [ ] `test/live_mirroring_test.dart` and `test/watch_session_projection_test.dart`: S-76's index
   assertions; the S-5 expectation in `test/watch_session_finish_test.dart:413` flips (D-81) — the
   phone's finish is now reported; keep its second half (a wrist snapshot for an already-ended session
   is still answered).
9. [ ] `docs/watch_session_sync.md`: rewrite the D-11 sentence about `projectedSession` and the
   "manual Sync" claims; the "The phone's finish is silent" paragraph (`:145`); the "What does not sync"
   bullets — say what is automatic now and what still is not (routines; entries that are not `set`;
   deletions — PR 3); the D-26 rest-timer bullet becomes "each device keeps its own countdown". Every
   sentence names the test that proves it.
10. [ ] `docs/state_management/watch_surface.md`: the "no automatic sync" claim (`:336`) and the
    `projectedSession` description (`:81`).
11. [ ] Residue sweep, recorded in the evidence file: grep `noAutoSyncLabel`, `NoAutomaticSyncHint`,
    and every sentence in `lib/`/`docs/` that still says sync is manual or that a phone change needs a
    Sync tap; and confirm nothing outside the Predicted Files changed
    (`.github/copilot/scripts/macos/gateway.sh git-diff develop --name-only`).

**Done Criteria** (run until green):
- `.github/copilot/scripts/macos/gateway.sh lint`
- `.github/copilot/scripts/macos/gateway.sh test` — the full suite (900 s timeout expected; the
  baseline is 3949 passing / ~1 skipped / 0 failures, 2026-10-06). Paste the counts.
- `.github/copilot/scripts/macos/gateway.sh swift-test` — 294 passing / 0 failures.
- Red→green: S-76 (stash the `projectedSession` fix → the index assertion fails), S-74 (stash the
  payload-equality gate → the count assertion fails), and **S-84** (key the abandoned rule on the
  pointer instead of X's row → the "zero frames" assertion fails). All runs recorded in the evidence
  file.
- *Owner only:* the walkthrough in `docs/watch-app-setup-and-qa.md` — log a set on the phone and watch
  it appear on the watch; add an exercise on the phone; finish the session on the phone. Agents do not
  run devices or simulators.
- *Governor only:* the watch-scheme `xcodebuild`.

**Predicted Files**: `lib/state/watch/watch_session_auto_push.dart` (new),
`lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_sync_wiring.dart`,
`lib/main.dart`, `test/watch_session_auto_push_test.dart` (new), `test/live_mirroring_test.dart`,
`test/watch_session_projection_test.dart`, `test/watch_session_finish_test.dart`,
`docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`. Nothing else.

## Files Affected (whole PR)

| Path | Phase | Role |
|---|---|---|
| `watch/sync_protocol/PROTOCOL.md` | 1 | the additive amendment (the contract) |
| `watch/contract/watch_start_paths_contract.json` | 1 | the copy fixture both stacks read |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` | 1 | the surface copy constants |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` | 1 | the hint's removal |
| `lib/watch/start/watch_start_screen.dart` | 1 | the Dart twin of the same surface |
| `watch/watchos/Tests/…/WatchSessionStartPathsTests.swift`, `…/WatchConnectivityBridgeTests.swift` | 1 | the copy assertions + the erased-hint guard |
| `test/watch_session_start_test.dart`, `test/watch_transport_test.dart` | 1 | the Dart copy assertions |
| `docs/watch-app-setup-and-qa.md` | 1 | the walkthrough stops saying logging needs a tap |
| `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` | 2 | the wrist's acceptance rules |
| `lib/watch/session/watch_session_engine.dart` | 2 | the twin's identical rules |
| `watch/watchos/Tests/…/WatchSessionEngineTests.swift`, `…/WatchLiveMirroringTests.swift`, `…/WatchLoggingTimersTests.swift` | 2 | the wrist's rule tests |
| `test/watch_session_engine_test.dart`, `test/watch_logging_timers_test.dart` | 2 | the twin's rule tests |
| `lib/state/watch/watch_session_auto_push.dart` | 3 | the one push seam (new) |
| `lib/state/watch/live_session_mirror_state.dart` | 3 | the place-keeping projection |
| `lib/state/watch/watch_sync_wiring.dart` | 3 | construction, binding, re-baseline |
| `lib/main.dart` | 3 | the bind beside the adoption bind |
| `test/watch_session_auto_push_test.dart` | 3 | the push's scenarios (new) |
| `test/live_mirroring_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_session_finish_test.dart` | 3 | the projection's place, the flipped S-5 |
| `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md` | 3 | the behaviour docs |

Dependents that only *read* a touched surface (no change expected, but their tests must stay green —
the Impact Check table lists each grep): the live-session view's mirror readers, the capture-contract
tests (`WatchCaptureContractTests`, `test/watch_capture_*`), the adoption bridge and its tests, the
routine/preference sync tests, and `test/phone_manage_bridge_test.dart`.

## Notes

- **Dependency graph (after the governor's split).** PR 1a = Phases 1–2; PR 1b = Phase 3, which needs
  1a — a phone that pushed before the wrist accepted a foreign session would let the phone's snapshot
  replace the wrist's own session wholesale (data loss). Within 1a, Phase 1 (contract + copy) and
  Phase 2 (the wrist's rules) are independent of each other. **The order is 1a then 1b; no release may
  carry the push without the wrist's rules.**
- **Intermediate states.** After Phase 1 alone the button says "Sync" while a phone change still needs
  a tap; after Phase 2 alone the wrist is safe but nothing pushes; both are invisible to a user because
  1a and 1b ship together in the unreleased v1 (see the split note at the top).
- **The split is decided (governor, 2026-10-06).** PR 1a = Phases 1–2 (the contract, the copy, the
  wrist's acceptance rules and its own rest countdown — nothing user-visible improves on its own);
  PR 1b = Phase 3 (the push, D-81 and the behaviour docs). Two soft signals measured by the governor:
  the plan runs over 500 lines, and the PR touches three tracks and amends the contract. One plan
  file and one set of ids across both PRs; S-84 is this revision's new scenario.
- **The pointer trap (D-81).** The end rules read the mirrored session X's repository row, never the
  current-session pointer (S-84): `loadHistoricalSession` repoints it at a past session every time the
  user browses the calendar, and `clearSession` can null it without deleting the row.
- **What PR 1 deliberately does not do.** No catch-up for a device that was out of reach (PR 2); the
  wrist's own add-an-exercise stays silent (PR 2); deletions, the phone's `timed`/`hold`/`round`
  entries and the phone's rest timer (PR 3). Each is named in the series index.
- **The conflict rule is silent by design** (series D-70): when both devices hold their own session
  with a ladder, the wrist refuses and the user is told nothing. Elaborated as D-78.
- **The doc-size rule** (`test/docs_indexing_contract_test.dart`, 64 KiB; split at ~52 KB): all three
  docs touched are mid-size and gain a handful of lines; the check runs in Phases 1 and 3.
- **Deliverable-3 cross-link.** The 15-series index's "Sync stays manual" decision and the tail of its
  decision 2 point here (do not edit its historical evidence files).
- **Watch-scheme builds are the governor's**, not an agent's; the owner runs the walkthrough. Both are
  marked as such in the phases.

## Progress

- [x] PR 1a / Phase 1 — the contract amendment and the copy — tests 3979 passed / ~1 skipped, 0 failed; swift 302 / 0; lint 196 / 0 (steps 1 and 9 deferred by governor, A-1/A-2)
- [x] PR 1a / Phase 2 — the wrist's acceptance rules — tests 3990 passed / ~1 skipped, 0 failed; swift 315 / 0; lint 196 / 0; targeted Dart 42 / 0 (`watch_session_engine_test` + `watch_logging_timers_test`); projection file 29 / 0; red→green shown for S-77, S-78 and S-79 on both stacks (steps 1–9 plus the governor's step 10, `PROTOCOL.md`)
- [x] PR 1b / Phase 3A — the phone's push (steps 1–8) — tests 4004 passed / ~1 skipped, 0 failed; swift 315 / 0; lint 196 / 0; push file 13 / 0; projection file 30 / 0; finish file 8 / 0; mutations a–e red and restored; `PROTOCOL.md` amended (the governor addition)
- [ ] PR 1b / Phase 3B — the behaviour docs and the residue sweep (steps 9–11)

## Assumption Log

Executors append here: the decision made, the options considered, and why — the Conductor
ratifies it into a D-x or reverts it with a remediation item.

1. **A-1 — `PROTOCOL.md` is not amended in Phase 1 (governor, 2026-10-06).** Phase 1 step 1 would
   cite rules and tests that do not exist until Phases 2 and 3, and docs must not claim unshipped
   behaviour; Phase 2 adds the wrist's rules and Phase 3 the phone's push, each citing the tests that
   then exist. `watch/sync_protocol/PROTOCOL.md` is left untouched.
2. **A-2 — the QA walkthrough is not rewritten in Phase 1 (governor, 2026-10-06).** Phase 1 step 9's
   "logging is automatic" is true only after Phase 3, so `docs/watch-app-setup-and-qa.md` is left
   untouched; a sentence there that quotes the removed label is left for Phase 3, which rewrites the
   step anyway.
3. **A-3 — the residue sweep keeps three deliberate absence guards.** `grep noAutoSyncLabel` /
   `grep NoAutomaticSyncHint` under `lib/`, `test/`, `watch/` returns only the tests that assert the
   string and the type are gone (Swift `testS082TheStartSurfaceSaysSyncAndCarriesNoAutomaticSyncLabel`
   and `testTheContractLabelsMatchWatchStartSurfaceCopy`, Dart `the sync action is offered only when
   the app can ask`); production code has none. The brief's step 7 (add the guard) wins over the
   Done Criteria's "returns nothing", which the guard itself cannot satisfy.
4. **A-4 — `applyExercisePush` in the Dart twin returns `Future<WatchSessionRecord?>` (developer,
   2026-10-06).** D-79 requires a refused push to land nowhere, and the old signature had no way to
   say "nothing was inserted" without throwing; `null` is that answer. No caller distinguishes them
   yet — Phase 3's push does not insert into the wrist's log — so no behaviour changed beyond the
   refusal itself.
5. **A-5 — `test/watch_session_projection_test.dart` (S-40) gained one line (developer,
   2026-10-06).** It was not in Predicted Files or the brief's candidate list, but it applied a
   foreign snapshot mid-session — it pinned the wholesale-adoption rule D-78 supersedes. Added
   `await engine.finishSession();` so the switch happens in D-78's counter-case; every original
   assertion and the file's 29 tests are unchanged and green.
6. **A-6 — `Harness.clearEmitted()` added to the Swift test harness (developer, 2026-10-06).** The
   S-77/S-78 tests must assert that a refused frame emits *nothing*, and `emitted` is `private(set)`
   in the harness; a count-and-clear accessor was the smallest way to observe that without touching
   production code.
7. **A-7 — the ordering mutant (refusal after the wrist's end-capture) needed a stronger fixture than
   S-77's (developer, 2026-10-06).** With the plan's fixture the mutant is invisible:
   `engine.observations` filters by the held session's id, and the session the phone created is
   phone-sourced, so `captureSessionEnd` declines it either way. The new Swift test gives the wrist a
   foreign-named session it created itself and has not ended, and counts stored observations across
   the refused frame.
8. **A-8 — the wrist's end-capture rule is Swift-only, and Phase 2 does not change that (developer,
   2026-10-06).** `captureSessionEnd` exists in the Swift engine and has no counterpart in the Dart
   twin, so D-78's "before `captureSessionEnd`" ordering has nothing to precede there and the two
   engines still agree on observable output. The gap predates this phase; adding it is a data-layer
   change, so it is logged, not absorbed.
9. **A-9 — one behaviour doc sentence is now true only of the phone's own countdown (developer,
   2026-10-06).** `docs/watch_session_sync.md` ("The phone's rest timer is not carried … a countdown
   running on the wrist at a Sync loses its remaining-time line", held by `timer_cleared.json`)
   described the pre-D-80 rule; the fixture still passes because the kind it clears is one the phone
   wrote. The brief forbids editing that doc in Phase 2 — Phase 3's rewrite owns the correction.

10. **A-10 — the place is delivered as a place-only frame (developer, 2026-10-06).** The brief's
    literal `_projection?.call(state)` cannot deliver the receiver's place: the projection reads it
    from `incoming['payload']['currentExerciseIndex']`, and `state` is the mirror's bare payload, so
    slot 0 comes back. `projectedSession()` passes `{'payload': {'currentExerciseIndex': …}}` instead;
    it names no session, so the D-10 gate does not reject it (passing the mirror's payload does, and
    then S-70's push is null). Mutation (b) pins the difference.
11. **A-11 — S-76 lives in `test/watch_session_projection_test.dart` (developer, 2026-10-06).**
    Predicted Files also named `test/live_mirroring_test.dart`, but that harness's mirror has a
    projection fake and no bound `WorkoutState`, so the request-answer path over the real projection
    is only reachable in the projection file. `live_mirroring_test.dart` is unchanged and green.
12. **A-12 — S-83's two clauses contradict each other; the note was followed (developer,
    2026-10-06).** One says a failed send still becomes the baseline, the other that the payload stays
    owed. A payload kept for a retry that D-83 forbids is dead state, so the baseline is updated after
    the attempt and the same state is not attempted twice. The test asserts exactly that.
13. **A-13 — tests close the window with `flush()`, not by waiting (developer, 2026-10-06).** Only
    `S-75 the trailing window closes by itself` builds a push with a 5 ms window and polls to a
    deadline, so no test depends on a real-clock threshold. The production default stays 250 ms.
14. **A-14 — two fixtures are reached differently from the register's wording (developer,
    2026-10-06).** S-71's index 1 comes from the wrist advancing and re-syncing rather than from a
    pre-set ladder, and S-75's burst adds catalog exercises through the session path, so its slots
    carry derived ids (`effort-…-2`) instead of the plan's literal `sx-3`/`sx-4`; the assertions name
    the ids the fixture produced. The expected outcomes are unchanged.
15. **A-15 — the flipped S-5 observes two `completed` frames (developer, 2026-10-06).** The first is
    the push's; the second is the mirror's G1 answer to the wrist's stale re-assertion, which the
    brief's second half keeps. That file builds its own `WatchSessionAutoPush` because its harness
    drives a `CaptureTransport` rather than the graph's radio.

## Open questions

Owner-visible questions first; each carries the default this plan proceeded on.

1. **A rest countdown while the other device sends news.** *Default taken (D-80):* each device keeps
   its own countdown — the wrist's "90 s left" line is never stopped by a set logged on the phone, and
   vice versa. Alternative: one shared countdown that either device can stop. Say so if the shared one
   is wanted; it changes D-80 and S-79.
2. **Finishing or discarding on the phone.** *Default taken (D-81):* the watch learns it immediately and
   stops showing a live session. Alternative: keep today's silence (the watch learns at its next
   catch-up). This reverses a documented behaviour from the previous series, so it is worth one word of
   confirmation.
3. **The phone's own move of the current exercise.** *Default taken (D-77):* it does not move the
   watch's place — the wrist's own place is the wrist's to report, and the phone follows it. Adding or
   swapping an exercise still reaches the watch. Alternative: the phone's place wins.
4. **What the Sync button is for.** *Default taken (series D-72, D-74):* recovering a device that was
   out of reach, and refreshing the routine list. The button's action is unchanged in PR 1.
5. **The button's words.** *Default taken (D-84):* "Sync", with the "No automatic sync" line deleted
   and nothing invented in its place. Alternative: a new one-line explanation of the two cases the
   button covers.

Technical questions (not owner-visible):

1. **`watch_connectivity` 0.2.8's API is verified (governor, 2026-10-06).** The plugin exposes
   `isSupported`, `isPaired`, `isReachable`, `messageStream`, `sendMessage(Map)`,
   `updateApplicationContext(Map)`, `applicationContext`, `receivedApplicationContexts` and
   `contextStream`; it does **not** expose `transferUserInfo`. PR 1's push needs none of the new
   members — it goes by `sendMessage` (D-83) — and PR 2 must evaluate `updateApplicationContext`
   first (the series index's D-71 and its "Transport" section). The app's own use today is
   `isPaired`, `isReachable`, `messageStream`, `sendMessage`
   (`lib/core/platform/watch_connectivity_channel.dart`), pinned at 0.2.8 by `pubspec.lock`.
2. **Doc sizes could not be measured** (no size tool in the planner's reach); all three docs touched
   read as mid-size. `test/docs_indexing_contract_test.dart` is the gate.
3. **A snapshot's `revision` is stored, never compared** on the watch (`WatchSessionEngine.swift`
   `:470,518,569` set it, `:228` emits it; no comparison anywhere) — so the phone's revision travelling
   in a push cannot be rejected as stale. Recorded here because the push's payload carries it.
4. **The wrist's end-capture rule has no Dart twin** (developer, 2026-10-06). `captureSessionEnd`
   (D-119/D-120) exists only in `WatchSessionEngine.swift`; the Dart engine ends nothing on a snapshot,
   so AC-11's "both engines carry every rule" is not literally true for it. Phase 2 does not widen the
   gap — D-78's refusal simply has no end-capture to precede in Dart, and the observable results match
   — but the two engines are not the same rule set here. A candidate for PR 2, or a decision that the
   wrist's end-capture is deliberately Swift-only.
5. **A ninth file changed outside the phase's Predicted Files** (developer, 2026-10-06): one line in
   `test/watch_session_projection_test.dart` (A-5). Flagged for the reviewer rather than absorbed
   silently.
