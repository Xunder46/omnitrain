# Review: 49a+49b (food logging reachable) · working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: governor-run (Swift 687/0, Flutter +5408, analyze 181; suite not re-run per brief)
Diff vs Predicted Files: conforms for the 49a/49b scope (the six files below). The working tree also carries 50a/50b and docs-keeper changes (`watch_timer_push.dart`, `timer_manager.dart`, `workout_state.dart`, `watch_session_importer.dart`, `test/watch_timer_push_test.dart`, `test/watch_session_rest_phone_entries_test.dart`, `docs/rest_tracking.md`, the 50x plan files, `Runner.xcodeproj/project.pbxproj`) — outside this review; the docs diffs for `watch_surface.md`/`watch_surface_wrist.md` mix 49 and 50 text, only the 49 parts ruled on here.

## Findings
1. [Minor] `watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift:115-160` — `restore()` and `applyFoodsDown(_:)` both mutate the in-memory `catalog`/`syncedFoods`/`categories` with no lock, and the orchestrator is not main-actor isolated (`WatchSyncOrchestrator.swift:60-65`). A `foods_down` landing while the launch `.task` runs `nutrition.restore()` can lose: restore picks the older max-sequence row after apply already stored a newer one, and `applyCatalog()`'s two separate writes can be observed torn (foods of one catalog, categories of another). Self-heals at the next sync, so Minor. Fix: guard the catalog swap (and restore's read-then-assign) with a small `NSLock` or serialize both on one queue. Guard: unproven — no test runs restore concurrently with applyFoodsDown.
2. [Minor] `docs/state_management/watch_surface_wrist.md:276-277` — the sentence cites `WatchNutritionWiringSourceTests.swift` for "S-7201..S-7205, source scans", but S-7204 is not in that file and is not a source scan: it is the existing `WatchNutritionQuickLogTests` and the S-3103 guards run, not rewritten (the evidence file states this correctly). Fix: cite S-7201..S-7203 and S-7205 for the source-scan file and name the kept suites for S-7204.

## Assumption Log rulings
Neither plan carries an Assumption Log section and neither phase reports entries; nothing to rule on. The one plan-level correction (49b's header already notes the scout's "no watch app target" claim was wrong) is recorded in the plan itself.

## Scenario coverage
- S-7101 → `test/watch_sync_request_handler_test.dart` · `S-7101 the preferences, the routines, the foods, then the exercise batches travel in that order` (seen in diff; asserts the first three types in order, only `exercises_down` after, batch indices 0,1,2)
- S-7102 → same file · `S-7102 the foods travel in the Foods-I-Eat order…` (validator run + equality with `buildFoodsDown` over the same inputs, clock fields stripped)
- S-7103 → same file · `S-7103 a wrist that holds the exercise list still receives the foods`
- S-7104 → same file · `S-7104 a phone with no foods sends no foods frame and still sends the rest`
- S-7105 → same file · `S-7105 a foods frame the radio refuses does not stop the exercise batches` (recorder returns `WatchDelivery.undelivered` for `foods_down`)
- S-7201 → `WatchNutritionWiringSourceTests.testS7201TheHostOwnsTheNutritionStateAndRestoresIt` (one `WatchNutritionState(`, `nutrition: nutrition` in the orchestrator call, `await nutrition.restore()` in restore, `onOpenNutrition:`, `WatchNutritionView(`, `nutrition: host.nutrition` in the menu call)
- S-7202 → `…testS7202TheLogFoodCopyIsTheStartScreens` (executable copy check + source constant)
- S-7203 → `…testS7203TheMenuRowSitsBetweenAddExerciseAndFinish` (usage-line order add < food < finish, NavigationLink, shared label, no `.disabled(`)
- S-7204 → existing suites, run not rewritten (governor run: Swift 687/0)
- S-7205 → `…testS7205LogFoodSitsRightUnderFreeWorkout` (free < food < sync line order)

## Brief questions, answered from the code
1. `_sendRoutines` order is `preferences_down` → `routines_down` → `foods_down` (only when `_foodLibrary.foods.isNotEmpty`, `watch_sync_request_handler.dart:121`) → the exercise batches. The foods send sits before the version early return, so S-7103 holds. `WatchMirrorTransport.send` reports refusal as a `WatchDelivery` result and does not throw on it (`watch_transport.dart:259-274` catches), so the ignored result cannot break the batch loop; S-7105 pins it. The schema needs `foods.minItems: 1` (guarded) and allows `categoryId: null` for a food whose group the phone no longer holds (`_foodJson`, `watch_reference_sync.dart:544-546`), so a stale group cannot fail the validator. The send is sequential, so a large list delays the batches by one frame — inherent to D-1's order, no cap by decision (D-4).
2. `WatchAppHost.init` builds `WatchNutritionState(engine: engine, store: store)` before the orchestrator and keeps it as `let nutrition`; `restore()` calls `await nutrition.restore()` after `engine.restore()`. The first render is not blocked on restore (the `.task` pattern every state shares), so the list can be empty for a beat on relaunch — pre-existing pattern, not a regression. The race is finding 1.
3. The food sheet is opened only from the start screen (`showingFood` set only by `onOpenNutrition`), and the menu sheet only from the logging/rest surfaces, so the two cannot be presented at once: while the food sheet is up the start screen's buttons are covered, and a session starting underneath leaves the sheet up deliberately (comment at `ContentView.swift:262-263`) with the system's own dismiss — not stranded. The menu row stays reachable during rest: the rest branch carries the same list button (S-3103A, `WatchMenuTests.swift:1014-1044`), and the row is never disabled.
4. Mid-session logs go under the session: `engine.logNutrition` appends with `sessionId: current?.sessionId ?? WatchNutritionSession.idFor(now)` (`WatchSessionEngine.swift:1283-1286`), so a log taken from the menu lands in the session's observation stream and a start-screen log gets the synthetic nutrition session id. The phone's receipt path (`WatchNutritionLogBridge`) is untouched by this diff.
5. No existing test pinned the old start-screen order: the only references to `onOpenNutrition` outside `WatchStartView.swift` are the new source tests. The S-3103 guards survive: `WatchMenuState(` still occurs once in `ContentView.swift`, and `addExerciseRow` keeps its `.padding(.top` line with `logFoodRow` inserted after it (S-3104A's next-line check still holds). `WatchMenuView(` is constructed only in `ContentView.swift`; the new `nutrition:` parameter defaults to nil, so no other construction breaks.

## Disposition (governor, 2026-10-21)

- Minor 1 (restore vs a newer foods_down): fixed, S-7206. Minor 2 (doc citation): fixed.
