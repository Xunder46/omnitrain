# Feature: Discard Workout on the watch (plan 171)

> Status: Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` (+ `docs/design_system.md`, `docs/documentation_standard.md`, `docs/state_management/watch_surface_wrist_logging.md` for the surface this edits)

## Overview

The wrist's session menu (the sheet the list button opens: the session's exercises
with their logged counts, Add Exercise, End Session) gains a **Discard Session**
row at the very bottom, below End Session. Confirming it:

- ends the wrist session as **abandoned** (the engine's existing
  `abandonSession()`; entries already logged stay in the wrist's own store, and
  the session is not a finished workout);
- **discards the platform workout**: no new code — `WatchWorkoutCoordinator.apply`
  already ends an abandoned session's workout with `platform.end(saving: false)`
  (plan 89 D-2), so nothing reaches Apple Health;
- sends the phone a `session_lifecycle` `abandoned` stamped with the wrist's own
  instant, exactly as the existing abandon path does (D-120), and the phone's
  existing discard rules apply unchanged (D-14630/D-14631/D-14632, O-1..O-9).

The button is destructive and always confirms first, in the phone's own discard
words (`workout_session_list_view.dart::_showDiscardDialog`). It is never
disabled, so it is reachable mid-set and mid-rest, and its two-step flow plus the
absence of any Crown binding on the menu keep it out of reach of an accidental
tap or a Digital Crown scroll. The owner's "both" rule is also implemented: an
End Session with nothing logged behaves as a Discard (abandoned, nothing saved)
with no extra dialog.

The new logic lives in the package (`WatchMenu.swift`); the app target gets only
thin view wiring, pinned by source-scan tests (the plan 168 pattern).

## Resolved Decisions (Ledger)

- **D-17101 (the screen and the placement).** The session-details screen is
  `WatchMenuView` (`watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`),
  the sheet the logging and rest surfaces' list button opens: it is the only wrist
  surface that shows the running session's own details (the ladder's exercises
  with their logged counts) beside the session's actions, and it already holds
  End Session and Add Exercise. The wrist's other candidate, `WatchWorkoutSummaryView`,
  shows a *finished* workout's summary, not a live session — it is not a discard
  site. The Discard row is the **last row of the menu's `VStack`, below the
  `finishRow`**, after the existing `Divider()`/`addExerciseRow` block, inside the
  existing `ScrollView` and its `surfaceInset` padding, in the `.bordered` style
  with a **destructive role**. The Digital Crown on this surface only scrolls the
  list (the menu binds no Crown today) and never activates a button; the
  row-tap-then-confirmation flow is the guard against an accidental tap.
- **D-17102 (what Discard does).** `WatchMenuState.discard()` calls
  `engine.abandonSession()` directly. It never routes through
  `WatchEffortRatingState`: no rating is asked, and no owed-prompt record is
  written for a discard, even when the phone's preference asks and efforts are
  logged. The wrist's end instant is the wrist's clock at the tap (D-120), and it
  travels in the `session_lifecycle` `abandoned` frame the engine already emits.
  The logged entries stay in the wrist's store; the session does not become a
  finished workout (no `WatchWorkoutSummary` pending row — S-9605 already holds).
- **D-17103 (the platform workout — no new code).** An abandoned session closes
  its workout with `saving: false` in `WatchWorkoutCoordinator.apply` (plan 89
  D-2; proven by `WatchFitnessFollowsSessionTests` S-89-1/S-89-2 and
  `WatchWorkoutCoordinatorTests:304-314`). Discard reaches it by being an
  abandonment; the sensors, GPS recorder and rest-ping scheduler follow the
  session's end through the plumbing every abandonment already uses
  (`WatchSensorCoordinator` "completed, abandoned, or no session at all — stops
  them"; the rest is stopped by `transitionTo` before the terminal row, D-223).
- **D-17104 (the confirmation, the phone's own words).** The confirmation is the
  menu's own `.alert`, mirroring the phone's destructive discard dialog
  (`lib/features/session/workout_session_list_view.dart:1018-1031`): title
  "Discard session?", body "This will permanently delete this session and all its
  data. You will return to the start screen." (the phone's last clause says Home;
  the wrist returns to the Start surface, so the return clause names the wrist's
  own surface — derived, owner-vetoable), buttons Cancel (role `.cancel`) and
  Discard (role `.destructive`). `state.discard()` runs only from the alert's
  Discard; Cancel changes nothing. No haptic on confirming a discard: the
  destructive action is not a confirmed success, unlike Finish's `.success` tap
  (derived, owner-vetoable).
- **D-17105 (an empty End behaves as Discard — owner to confirm).** "Empty" means
  the session holds **zero effort-kind entries** in the engine's corrected
  projection (`WatchObservationKind.efforts` over `engine.entries` — the same
  population the menu rows count and `isRatingOwed` reads, after the phone's
  deletions). One predicate, one router: `WatchMenuState.hasLoggedEfforts` and
  `WatchMenuState.finish()` — an empty session's `finish()` calls `discard()`
  instead of `rating.end()`; `WatchEffortRating.swift` is unchanged. The view
  raises the discard confirmation for an empty End (one dialog, the right
  question — no extra dialog on top) and the Finish confirmation otherwise. This
  matches the phone's own empty finish
  (`lib/features/session/workout_session_finish.dart:14-20`: no exercises with
  entries discards and exits) and the wrist's `cancelEmptyFreeWorkout`, which
  already abandons the empty session
  (`WatchStartPaths.swift:739-746`). Coherence rule: the wrist's End mirrors the
  phone's finish — nothing logged, nothing saved, no finished workout anywhere.
- **D-17106 (the phone needs no change — verified, do not touch).** On receiving
  the wrist's `abandoned`, the phone's bridge
  (`lib/state/watch/watch_session_adoption_bridge.dart::_routeLifecycleToHeld`,
  :870-934) already: deletes the held, unfinished session through
  `discardCurrentSession()` (`lib/state/workout/session_core_lifecycle.dart:189-208`,
  which stops the phone's open rests in memory, deletes the row and its sets, and
  deletes the Health workout the phone wrote, plan 89 D-4); applies D-14630's
  earlier-discard-wins rule against an end the phone already holds; and returns
  early for a session it does not hold. The phone writes no Health workout for a
  wrist-run session (a wrist `completed` ends it with `writeToHealth: false`,
  plan 89c1 D-1; the importer creates no session row for a completed end with no
  live entries, `lib/core/services/watch_session_importer.dart:243-267`).
- **D-17107 (the replay corpus is unaffected).** Discard emits only frames the
  existing abandon path already emits (`session_lifecycle` `abandoned`, the
  snapshot pair the phone already tolerates, the rest observation when a rest
  stops). No new frame type, no contract change, no
  `watch/sync_protocol/PROTOCOL.md` edit; the replay and soak suites
  (`WatchReplayTests.swift:274`, the Dart convergence harness) run unchanged.
- **D-17108 (the Dart twin has no menu — parity is not owed).** `lib/watch/`
  holds no session menu: grep `menu` over `lib/watch/` returns only one doc
  comment (`lib/watch/start/watch_routine_catalog.dart:67`). The twin has no
  surface to discard from and its engine already has the twin's `abandonSession`
  equivalent; no Dart change and no Dart test in this plan. The twin's discard
  parity is the engine-level rules plans 146/146c already prove.

## Feature Invariants

- A discard on the wrist is an abandonment, never a completion: it can never save
  anything to Apple Health, on either device.
- The confirmation stands between the tap and every destructive effect; Cancel
  leaves the session exactly as it was.
- A discard adds no user-visible data anywhere: the wrist keeps its logged
  entries in its own store, and nothing new appears in Fitness, on the phone's
  history, or in a summary.
- The rating state stays out of the discard path: a discard owes no prompt and
  writes no prompt record.
- The wrist's instant, not the phone's arrival clock, is the discard's end
  (D-120); the phone's earlier-end rule (D-14630) reads both stamps as sent.

## Requirements

- R-1: the session menu has a Discard Session row as its last row, destructive,
  confirming first, never disabled (D-17101, D-17104).
- R-2: confirming Discard ends the session abandoned through the engine's
  existing path, stops the running rest, and writes nothing beyond what an
  abandonment already writes (D-17102, D-17103).
- R-3: the owed-rating machinery is untouched by a discard (D-17102).
- R-4: an End with nothing logged behaves as a Discard with no extra dialog
  (D-17105 — owner to confirm).
- R-5: the phone's discard handling needs no change and receives none (D-17106).
- R-6: the docs that describe the menu and the owner's device QA script describe
  the new row (Phase 3).

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC-1 the row exists, sits last, is destructive and confirms (S-17101, S-17102,
  S-17112).
- AC-2 a confirmed discard ends the session abandoned mid-set or mid-rest, with
  the rest stopped and no rating prompt (S-17102, S-17103, S-17104, S-17105).
- AC-3 nothing reaches Health and no workout is saved on either device
  (S-17108, S-17109).
- AC-4 the first ending stays final and the phone's rules hold (S-17106,
  S-17107).
- AC-5 an empty End behaves as a Discard (S-17109 — owner to confirm).
- AC-6 logged entries stay on the wrist; water and food are untouched; no
  summary appears (S-17110, S-17111).
- AC-7 the docs say the new words (S-17115, Phase 3).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchMenuState.finish()` (watch) | `WatchMenuView.finishRow` (`Task { … await state.finish() … }`); `rating.end()` | gains the empty→discard router; non-empty path byte-identical | S-17109 |
| `WatchMenuView`'s rows/alert | `WatchMenuTests` source scans (S-1108, S-3104A, S-3103A); `ContentView.menuSheet` | one new last row + one new alert; the Finish row and its alert unchanged | S-17101, S-17102 |
| `ContentView.menuSheet`/`onFinish` | `WatchMenuTests.testS3103ATheRestScreenCarriesTheMenuButton` reads `ios/OmniTrain Watch App/ContentView.swift` | gains `onDiscard` wiring beside `onFinish` | S-17102 |
| `engine.abandonSession()` | `WatchActiveEnergyTests:190`, `WatchEndedIsFinalTests`, `WatchFitnessFollowsSessionTests:39-41`, `WatchReplayTests:274`, `cancelEmptyFreeWorkout` (`WatchStartPaths.swift:741`) | no change; one more caller of the same path | S-17102, S-17107 |
| `WatchWorkoutCoordinator.apply` end branch | `WatchFitnessFollowsSessionTests` S-89-1/S-89-2, `WatchWorkoutCoordinatorTests:304-314` | no change; an abandonment closes the workout with `saving: false` | S-17108 |
| Phone `_routeLifecycleToHeld` | `test/watch_session_bridge_test.dart`-family + plan 146/146c suites | no change (D-17106) | S-17106 |
| `WatchEffortRatingState.end()` | `WatchMenuState.finish()` (only caller), `WatchEffortRatingTests` | no change; empty End no longer reaches it via the router | S-17105, S-17109 |
| Replay corpus / soak | `WatchReplayTests.swift:274`, Dart convergence seeds | no new frames (D-17107) | S-17113 |

Standing invariants this could break, from `docs/global_conventions.md` and plan
146: O-2 "the first ending is final" (S-17107), O-7/D-14630 "an earlier discard
wins and deletes the workout and its sets on the phone" (S-17106), plan 89 D-2
"an abandoned session leaves no Health workout" (S-17108), D-120 "the wrist's own
end is stamped with the wrist's clock" (S-17106), D-223 "a rest cannot outlive
the workout" (S-17104). A claim of "unaffected" above carries its grep or cited
test.

## UI Standards Impact

- `test/ui_standards_contract_test.dart` covers `lib/` minus `lib/watch/`
  (`test/ui_standards_contract_test.dart:21,284`): it does **not** govern the
  watchOS views. The rules that bind this change are the watch source-scan
  suites in `watch/watchos/Tests/WatchSessionEngineTests/`
  (`WatchMenuTests`, `WatchAccessibilitySourceTests`) and the shared values the
  wrist mirrors under `docs/design_system.md`'s watch scope (accent, button
  styles, destructive-confirmation words).
- The destructive confirmation follows `docs/design_system.md` "Deleting"
  (every delete of the user's data confirms first; destructive wording), rendered
  with the wrist's own `.alert` shape as the Finish confirmation already is.
- The row reuses the menu's existing pieces only: `.bordered` button, the shared
  `surfaceInset`, the accent system untouched. No new exception to record.
- 40 mm: the menu is a `ScrollView`, so the extra row costs a scroll, not a
  layout; the on-device look stays the QA owner device check (the same rule the
  doc states for the pager and the two-tile layout — "no unit test sees a
  layout").
- Doc sizes: `docs/state_management/watch_surface_wrist_logging.md` and
  `docs/watch-app-qa-wrist-logging.md` are both far under the 52 KB split band
  (463 and 489 non-empty lines at planning); the 64 KiB ceiling is enforced by
  `test/docs_indexing_contract_test.dart`. Verify the band at edit time.

## Scenarios

### S-17101: the Discard row sits at the bottom of the session menu
- Fixture: the app target's and package's source text, read by source-scan tests
  (`WatchMenuTests.menuSource(_:)` pattern — comment lines blanked).
- Trigger: the scans run in the suite.
- Flow: `WatchMenuView.swift` shows a Discard row whose use sits **after** the
  `finishRow`'s use in the body's `VStack`, below the Add Exercise block;
  `WatchMenu.swift` holds the copy constants.
- Expected outcome: the row is the menu's last row, `.bordered` with a
  destructive role; the scan fails if the order inverts or the copy leaves
  `WatchMenuCopy`.
- Edge case of: none (new surface).

### S-17102: confirm-then-discard, and Cancel changes nothing
- Fixture: `WatchMenuHarness` — one engine, store, start paths, preferences,
  rating state, menu over them; a session with one exercise and one logged set.
- Trigger: `state.discard()`, and the view scan asserting `discard()` runs only
  from the alert's Discard button.
- Flow: discard → `engine.abandonSession()`; cancel path → no engine call.
- Expected outcome: the session's status is `abandoned`, a `session_lifecycle`
  `abandoned` frame is emitted stamped with the harness clock's instant, the
  menu's sheet closes (the host's status change does it), and a cancel leaves
  the session `active` with no row appended.
- Edge case of: none.

### S-17103: Discard is reachable mid-set
- Fixture: the harness with a session whose current slot holds a running work
  clock (`engine.startTimer(kind: elapsed|hold|round)`), so `state.isLocked` is
  true.
- Trigger: `state.discard()` while locked.
- Flow: the row is never disabled (the view scan asserts no `disabled` on the
  discard row), the model has no `isLocked` guard.
- Expected outcome: the session ends `abandoned`; the running clock goes with
  the session (the same rule Finish already follows — the engine's terminal
  guard D-14602 refuses everything after).
- Edge case of: S-17102.

### S-17104: Discard during a rest stops the rest
- Fixture: the harness with a logged set whose rest is running
  (`engine.startTimer(kind: rest)`).
- Trigger: `state.discard()` during the rest.
- Flow: `transitionTo` stops the rest before the terminal row (D-223) and emits
  the rest's own observation.
- Expected outcome: the rest row is stopped, the rest-ended observation is
  emitted, and the host's rest-ping scheduler has no rest to arm (the scheduler
  reads the engine's rest; its "no rest" case, S-9108, already covers after).
- Edge case of: S-17102.

### S-17105: no rating prompt for a discard
- Fixture: the harness with the phone's preferences asking for an effort rating
  and one logged effort.
- Trigger: `state.discard()`.
- Flow: the rating state is never called; `WatchEffortRatingState.end()`'s
  owed-prompt write is not reached.
- Expected outcome: no prompt record is stored, `rating.owedSessionIds` is
  empty, and the session's own store holds no `ratingPrompt` row.
- Edge case of: S-17102.

### S-17106: the phone hears the wrist's abandonment, under its own rules
- Fixture: the harness emissions on the wrist; on the phone, the existing Dart
  bridge suites (plan 146/146c coverage).
- Trigger: the discard's `session_lifecycle` `abandoned` (S-17102).
- Flow: wrist reachable → the frame travels; wrist out of reach → the bridge
  queues and delivers it on catch-up (existing bridge behaviour, unchanged).
- Expected outcome: the phone deletes the held, unfinished session (D-14631),
  an end the phone already holds is compared by D-14630's earlier-instant rule
  (a wrist discard stamped earlier than the phone's finish deletes the finished
  workout; a later one loses), and a session the phone does not hold changes
  nothing. Wrist-side this scenario asserts only the emitted frame and its
  stamp; the phone half is the existing Dart coverage, unchanged (D-17106).
- Edge case of: S-17102.

### S-17107: the first ending is final on the wrist too
- Fixture: the harness with a session already `completed`, and a second with one
  already `abandoned`.
- Trigger: `state.discard()` on each.
- Flow: the engine's terminal guard (D-14602) returns the held row.
- Expected outcome: no new row, no new emission, no timer stopped; the model's
  return value is the unchanged record. (An earlier discard winning over a later
  finish on the phone is D-14630/D-14632, already proven — nothing here can
  reach it from the wrist.)
- Edge case of: S-17102.

### S-17108: the platform workout is discarded, never saved
- Fixture: the coordinator suites' shape (`WatchWorkoutCoordinatorTests`,
  `WatchFitnessFollowsSessionTests`).
- Trigger: `coordinator.refresh(abandonedRecord)` — the record S-17102 produced.
- Flow: `WatchWorkoutLifecycle.action` answers `.end` for a non-active session;
  `platform.end(saving: false)` runs.
- Expected outcome: the workout ends with `saving == false`; no Health workout
  exists for the discarded session. The rule is existing coverage (S-89-1,
  S-89-2); this plan adds only the harness-level assertion that the discard's
  abandoned record drives it, and cites the suites for the rest.
- Edge case of: S-17102.

### S-17109: an empty End behaves as a Discard (owner to confirm)
- Fixture: two harness sessions — one with an exercise and zero effort entries,
  one with one logged effort.
- Trigger: `state.finish()` on each (the End Session row's action).
- Flow: the router reads `state.hasLoggedEfforts`; the view raises the discard
  confirmation for the empty one and the Finish confirmation otherwise.
- Expected outcome: empty → the session ends `abandoned`, nothing is saved to
  Health (`platform.end(saving: false)` through the coordinator), and only the
  discard dialog was raised; non-empty → `completed` as today. Coherent with the
  phone's empty finish (immediate discard) and `cancelEmptyFreeWorkout`.
- Edge case of: S-17102, S-17108.

### S-17110: the logged entries stay on the wrist; no summary appears
- Fixture: the harness with one logged set.
- Trigger: `state.discard()`.
- Flow: `abandonSession` keeps the entries ("Entries already logged stay
  logged").
- Expected outcome: the entries are still readable from the store; a phone
  deletion arriving later still wins over them (D-14603c's rule is the phone's
  own delete); `host.summary.pending` is nil for the abandoned session (S-9605),
  so no summary screen is shown.
- Edge case of: S-17102.

### S-17111: water and food entries are unaffected
- Fixture: the harness with a water log and a food log recorded through the
  engine (`logWaterGlass`, `logNutrition`) before the discard.
- Trigger: `state.discard()`.
- Flow: the discard path touches only the session's rows.
- Expected outcome: the water and nutrition rows are unchanged; the nutrition
  model's state is untouched (food is logged from the start screen only, not
  part of the session).
- Edge case of: S-17102.

### S-17112: VoiceOver reads the row and its confirmation
- Fixture: the source text of `WatchMenuView.swift` and the copy constants.
- Trigger: the accessibility source scan (`WatchAccessibilitySourceTests`
  pattern).
- Flow: the row's label is its own text ("Discard Session"); the alert's buttons
  read their words (Cancel / Discard); no new `.accessibilityLabel` invention.
- Expected outcome: the scan holds the label text and the alert's roles; the
  menu keeps one VoiceOver element per row as today.
- Edge case of: S-17101.

### S-17113: the replay corpus is unaffected
- Fixture: the existing replay suite (`WatchReplayTests.swift`) and the Dart
  convergence harness.
- Trigger: the full suites after Phases 1–2.
- Flow: discard adds no frame type (D-17107).
- Expected outcome: every replay and soak test green with no edit; a red is a
  finding at this plan's seam, not a corpus change.
- Edge case of: S-17102.

### S-17115: the docs say the new words
- Fixture: `docs/state_management/watch_surface_wrist_logging.md` (the menu
  paragraph) and `docs/watch-app-qa-wrist-logging.md` (the numbered owner
  checks).
- Trigger: Phase 3's edits.
- Flow: the menu paragraph names the Discard row, its confirmation and the
  empty-End rule; the QA script gains the Discard step (next free number after
  43) with the owner-device checks: the row, the confirmation, nothing in
  Fitness, the phone's row gone, and an empty End discarding.
- Expected outcome: both docs updated under their size band; the QA step lists
  what the owner checks on real hardware.
- Edge case of: none.

## Iteration 1

### Phase 1: model, copy and behaviour tests (@developer)
1. [ ] Add the discard copy to `WatchMenuCopy` — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuCopy` gains `discardLabel = "Discard Session"`, `discardConfirmTitle = "Discard session?"`, `discardConfirmBody = "This will permanently delete this session and all its data. You will return to the start screen."`, `discardConfirmCancel = "Cancel"`, `discardConfirmDiscard = "Discard"` (D-17104; no em dash in any string)
2. [ ] Add the emptiness predicate — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuState.hasLoggedEfforts`: `engine.entries.contains { WatchObservationKind.efforts.contains($0.kind) }` (D-17105)
3. [ ] Add the discard method — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuState.discard()`: `guard engine.session?.status == WatchSessionStatus.active` then `await engine.abandonSession()`; no rating state, no `isLocked` guard (D-17102, D-17103)
4. [ ] Route the empty End — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuState.finish()`: `guard hasLoggedEfforts else { await discard(); return }` before `await rating.end()` (D-17105)
5. [ ] Red→green behaviour tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · new `WatchMenuDiscardTests` cases in the file's style (harness reuse): S-17102 (abandoned + lifecycle frame + instant + cancel-no-op), S-17103 (mid-set), S-17104 (mid-rest: rest stopped, rest-ended observation), S-17105 (no prompt record), S-17107 (terminal idempotence), S-17109 (empty `finish()` → abandoned; non-empty → completed), S-17110 (entries kept), S-17111 (water/food untouched)
6. [ ] Extend the copy guard — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `testS3401TheMenuCopyIsTheOwnersWords`: hold the five new constants to the phone's words
7. [ ] Update the no-edit/delete source guard — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `testS1108TheMenuSourceNamesNoRestEditOrDelete`: it forbids `delete` tokens in `WatchMenu.swift`/`WatchMenuView.swift`; keep the guard, and if the word "discard" trips it, narrow the token list precisely (the discard deletes nothing wrist-side) and note the choice in the Assumption Log

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (full package run; new cases red before items 1–4 land, green after) — every named S-171xx case listed in its output.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`. Nothing else.
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: view, shell wiring and source-scan guards (@developer) — after Phase 1
1. [ ] Add the row — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `WatchMenuView.body`: a `discardRow` after `finishRow` in the `VStack`, `.bordered` destructive-style, inside the existing `ScrollView`/`surfaceInset`; never disabled (D-17101)
2. [ ] Add the confirmation — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `discardRow` + `@State private var confirmingDiscard`: `.alert(WatchMenuCopy.discardConfirmTitle, isPresented:)` with Cancel (role `.cancel`, no-op) and Discard (role `.destructive`) whose action runs `Task { await state.discard(); onDiscard() }` (D-17104)
3. [ ] Pick the confirmation by emptiness — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `finishRow`: an empty session raises the discard alert instead of the Finish alert (one dialog either way; D-17105)
4. [ ] Thread the closure — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `init` gains `onDiscard: @escaping () -> Void`; no haptic on discard (D-17104)
5. [ ] Wire the shell — `ios/OmniTrain Watch App/ContentView.swift` · `View.menuSheet(_:menu:isPresented:)` passes `onDiscard: { isPresented.wrappedValue = false; host.noteSurfaceChange() }` (the sheet also self-closes on the status change it already observes)
6. [ ] Source-scan guards — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · new scan tests (S-17101: the discard row's use is after the `finishRow`'s use in the body; S-17102's view half: `state.discard()` appears once, inside the alert's Discard action; S-17109's view half: the empty branch raises the discard alert; read via `menuSource(_:)` with the repo-root paths)
7. [ ] Accessibility scan — `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` · new case for S-17112: the row's label text and the alert's two roles

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (full) green; the Phase 1 suite stays green (the new scans red before items 1–4, green after).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift`.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: docs and the QA step (@developer) — after Phases 1–2
1. [ ] Menu paragraph — `docs/state_management/watch_surface_wrist_logging.md` · "The wrist shell's second surface" section: name the Discard row (last row, destructive, the phone's own confirmation words), the no-rating rule, the empty-End rule, and link the new test names; keep the page inside the 64 KiB ceiling (`test/docs_indexing_contract_test.dart`)
2. [ ] Haptics sentence — `docs/state_management/watch_surface_wrist_logging.md` · "A recorded log is confirmed with one tap" paragraph: confirming Finish plays `.success`; confirming Discard plays nothing (D-17104)
3. [ ] QA step — `docs/watch-app-qa-wrist-logging.md` · next numbered step after 43 (S-17115): on real hardware — log a set, open the menu, tap Discard Session, confirm: the session ends to the Start surface, nothing appears in Fitness, the phone's open session row is gone with its sets; then an empty-session End asks the discard question and saves nothing

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test` (full `flutter test` — the docs indexing contract rides in it) green.
**Predicted Files**: `docs/state_management/watch_surface_wrist_logging.md`, `docs/watch-app-qa-wrist-logging.md`.
**Phase 3 verification notes (Conductor, date):** —

## Files Affected (whole feature)

- `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` — Phase 1
- `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` — Phase 2
- `ios/OmniTrain Watch App/ContentView.swift` — Phase 2 (app target; not compiled by `swift test`, pinned by source scans)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` — Phases 1–2
- `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` — Phase 2
- `docs/state_management/watch_surface_wrist_logging.md`, `docs/watch-app-qa-wrist-logging.md` — Phase 3
- Dependents that only read a touched surface and change nothing:
  `WatchEffortRating.swift` (its `end()` loses the empty-session caller via the
  router, unchanged), the engine and coordinator (existing abandon plumbing),
  `lib/state/watch/watch_session_adoption_bridge.dart` and
  `lib/state/workout/session_core_lifecycle.dart` (D-17106), `lib/watch/` (no
  menu, D-17108).

## Notes

- Phase graph: Phase 1 → Phase 2 → Phase 3. No phase can be reordered: the view
  (2) needs the model's `discard()` and `hasLoggedEfforts` (1), and the docs (3)
  name what 1–2 built. Running Phase 3 first would document a row that does not
  exist.
- No engine, coordinator, bridge, importer or contract change: the whole feature
  rides the existing abandonment path (D-17103, D-17106, D-17107). If a Phase 1
  test shows the abandon path itself deficient, that is a plan 146 defect —
  record it under Feedback, do not fix it here.
- Owner-confirm list for the handoff: D-17104's return clause and the
  no-haptic-on-discard default; D-17105 whole (the empty-End rule and its
  discard-confirmation wording). All are defaults; none blocks implementation.
- Legacy handling: none. No stored representation changes, no migration, no seed
  change; the SQLite contract (`scripts/sqlite_schema.sql`) is untouched.
- QA note for the executor: `swift test` compiles only the package; the app
  target's `ContentView.swift` change is proven by the source scans and the
  owner device check (plan 168's pattern). A widget-less plan: no `testWidgets`
  anywhere.

## Progress

- [ ] Phase 1 (@developer): model, copy and behaviour tests
- [ ] Phase 2 (@developer): view, shell wiring and source-scan guards
- [ ] Phase 3 (@developer): docs and the QA step

## Assumption Log

- **A-171-1 (planner): the return clause's words.** The phone's dialog says "You
  will return to Home."; the wrist returns to its Start surface. Options: keep
  the phone's clause verbatim, or name the wrist's own destination. Chosen: the
  wrist's own words ("You will return to the start screen.") — a wrist user has
  no Home screen; the permanence sentence stays verbatim. Owner-vetoable
  (D-17104).
- **A-171-2 (planner): no haptic on a confirmed discard.** Options: reuse the
  Finish `.success` tap, or stay silent. Chosen: silent — a destructive action
  is not a confirmed success; the wrist's haptic vocabulary has no destructive
  cue and inventing one is out of scope. Owner-vetoable (D-17104).
- **A-171-3 (planner): the empty End raises the discard dialog, not none.** The
  phone's empty finish discards with no dialog at all; the owner's brief said
  "no extra dialog" for the wrist. Chosen: one dialog — the discard one —
  because the row's whole point is that a destructive end never happens without
  a confirmation, and "no extra dialog" reads as no *additional* dialog.
  Owner-vetoable (D-17105).

## Feedback

[empty]
