# Feature: 79 — the wrist swipe has no name card in between; Next on the rest screen goes where the rest line says

> Status: BUILT AND PROVED 2026-10-26, review pending. Base commit: `.work/2026-10-26-79/base.txt` (9ac47772). Team: the crew (lead-seeded; the architect run is skipped because the seed carries the exact code, see the Assumption Log). Owner request (chat, 2026-10-26): "1. Middle screen with exercise name when swiping on the watch is back, I remember cancelling it. 2. When I click Next on the watch rest screen, the same exercise is still shown; we should allow logging another set for the same exercise but the rest screen builds the expectation of the next exercise appearing and it doesn't." Owner answers: swipe = "Switch at once"; rest Next = "Go to the announced exercise". Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## What the owner sees

| Moment | Today | After |
|---|---|---|
| On the logging screen of a session with several exercises, swipe left or right | the pages slide; the exercise you are leaving and the one you are entering are separated by a name-only card ("Barbell Squat", "3 sets", "2/3") that is visible during the slide (plan 52 only removed it for the moment after the swipe settles) | the logging screen of the neighbouring exercise replaces the current one at once with a light tap; no name-only screen at any moment; counter reads 2/3 as before |
| Swipe at the first exercise to the right, or at the last to the left | nothing moves | same: nothing moves |
| Swipe while an effort clock runs | failure tap and "An effort is running" notice | unchanged |
| Rest screen says "Next: Set 3 of 3" (sets remain) and you tap Next | back to the same exercise | unchanged |
| Rest screen says "Next: Barbell Squat · Set 1 of 3" (this exercise's planned sets are all logged) and you tap Next | back to the SAME exercise | the logger of Barbell Squat opens, as the line promised. An extra set on the finished exercise: swipe back to it |
| Rest screen says "Nothing planned next", or "Next: Set 4" (no plan), or a round "Next: Period 2" | back to the same exercise | unchanged |

(owner) On a real watch: (a) swipe between three exercises: no name card at any point, a light tap, counter right; (b) log the last planned set of exercise 1, tap Next on the rest screen: exercise 2 opens; (c) swipe back to 1 and log an extra set.

## Decision Ledger

- D-1 Pager without a page-turn (owner answer "Switch at once"): `WatchLoggingPagerView.swift` mounts ONE `WatchLoggingView` for the shown exercise instead of a `TabView` of pages; the `WatchExercisePreviewPage` card is deleted. A horizontal `DragGesture` on it (the locked page already has one: `single`, `:89-103`) moves to the neighbouring page. The `selection` state, `land(on:)`, `followEngine()`, `landing`, `state.focusSlotId` stay exactly as they are (plan 52 D-5/D-6, S-7911..S-7916 still hold), so a swipe sets the focus synchronously and the engine lands behind it.
- D-2 `WatchPagerModel.neighbourIndex(of index: Int, towardsNext: Bool) -> Int?` (new, `WatchPagerModel.swift`): nil unless `showsPager`; else `index ± 1`, nil when outside `rows.indices`. No wrap. (Name avoids the module's append-only verb guard: not update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy/set.)
- D-3 Swipe direction as the page-turn had it: translation.width < 0 (finger moves left) goes to the NEXT exercise, > 0 to the previous. Qualifies only when `abs(width) > 24` and `abs(width) > abs(height)` (same rule as the locked branch).
- D-4 Feedback: `WKInterfaceDevice.current().play(.click)` on a swipe that moves. The locked branch keeps `.failure`.
- D-5 The logger is rebuilt per exercise with `.id(<shown slot id>)`, as each page used to be its own view, so no tile/Crown state of one exercise leaks into the next.
- D-6 Rest Next goes to the announced exercise (owner answer): `WatchRestLabels` gains `nextSlotId: String?`, set ONLY by the final forward/backward search of `deriveRestLabels` (`WatchRestLabels.swift:121-124`, the "Next: <exercise> · Set …" and "Next: <exercise>" outcomes); nil for "Next: Set n", "Next: Period n" and "Nothing planned next". The slot id is the same string the line's slot has in the menu: `(slot["sessionExerciseId"] as? String) ?? exercise.slotId` (`:78`, equals `menuSlotId(of:_:)`, `WatchMenu.swift:246`).
- D-7 `WatchRestView` (`WatchRestView.swift`) gets `advance: @escaping (String) async -> Bool` (init parameter, default `{ _ in false }`). Its Next (`:95-106`) reads `state.restLabels.nextSlotId` BEFORE `state.endRest()`, then `await state.endRest()`, then `if let target { _ = await advance(target) }`, then `haptics.playNext()`, `onNext()`. `ContentView.swift` passes `advance: { await menuState.jump(to: $0) }` (`menuState`, `:517`). A refused or failed jump leaves the rest ended and the old exercise shown (no error, no retry): the session is never stuck.
- D-8 Not in scope: the menu sheet, the phone, the sync protocol (a jump already emits one `exercise_advanced` frame, plan 46b D-2), the rest line wording, the "Nothing planned next" case, wrapping swipes, any Dart.
- D-9 Docs: `docs/state_management/watch_surface_wrist.md` (pager paragraph, rest Next paragraph) and `docs/watch-app-setup-and-qa.md` QA list (one step per owner check above, appended to the list that holds the newest wrist steps). `watch/watchos/**` PROTOCOL.md is untouched.

## Scenarios (exact fixtures)

Fixture ladder (rest-label tests, reuse the helper `slot(_:_:planned:effortKind:)` in `WatchRestLabelsTests.swift`): A "Squat" planned 2, B "Bench" planned 3, C "Row" planned 0. Entries are `set` observations carrying `sessionExerciseId`.

- S-9101 `deriveRestLabels` current A (index 0), effort `set`, A has 2 sets logged, B has 0: `next` = "Next: Bench · Set 1 of 3" and `nextSlotId == "B"`. Fails today: the field does not exist.
- S-9102 current A, 1 of 2 sets logged: `next` = "Next: Set 2 of 2", `nextSlotId == nil`.
- S-9103 current A with no plan (planned 0), effort `set`, 3 sets logged: `next` = "Next: Set 4", `nextSlotId == nil`.
- S-9104 everything done: `next` = "Nothing planned next", `nextSlotId == nil`.
- S-9105 round effort with a `nextRound` ("Period 2"): `nextSlotId == nil`.
- S-9106 timed effort on A (A has one timed entry), B not done: `nextSlotId == "B"`; and the search order is unchanged: from the last exercise (index 2, C done) with A not done, `nextSlotId == "A"` (the wrap).
- S-9107 a slot with no `sessionExerciseId` of its own (only `exerciseId`/`name`/`capabilities`): the `nextSlotId` is `WatchCatalogExercise(slot:).slotId` ("sx-<exerciseId>"), the id `menu.jump` accepts.
- S-9108 through the engine (Mock-free; the Swift harness the pager tests use, `WatchPagerModelTests.swift` fixtures): session A,B,C, A's two planned sets logged, a rest running. `let target = logging.restLabels.nextSlotId` is B's slot id; `await logging.endRest()`; `await menu.jump(to: target!)` is true; afterwards `logging.isResting == false`, `session.currentExerciseIndex == 1`, exactly one `exercise_advanced` frame after the rest-ended frame. Guard the order too: jump BEFORE endRest also succeeds today (a rest does not lock), so the source guard S-9109 fixes the order.
- S-9109 source guard on `WatchRestView.swift` (comment lines stripped, as the other guards do): contains `state.restLabels.nextSlotId`, the statement `await state.endRest()`, the statement `_ = await advance(target)`, with the `nextSlotId` read BEFORE `await state.endRest()` and `advance(` AFTER it; the init has `advance:`; `ContentView.swift` contains `advance: { await menuState.jump(to: $0) }` inside the rest branch (the property `body`).
- S-9110 `WatchPagerModel.neighbourIndex`: three rows, current index 1: `(of: 1, towardsNext: true) == 2`, `(of: 1, towardsNext: false) == 0`, `(of: 2, towardsNext: true) == nil`, `(of: 0, towardsNext: false) == nil`; a locked session (work clock running, as `testS6603` builds it) returns nil for both; a one-exercise session returns nil.
- S-9111 source guard on `WatchLoggingPagerView.swift` (comment lines stripped): contains no `TabView`, no `WatchExercisePreviewPage`, no `.tabViewStyle`; contains `.id(` on the shown logger, `DragGesture(minimumDistance: 24)` at least twice (the swipe and the locked branch), `pager.neighbourIndex(of: selection, towardsNext:`, `state.focusSlotId = pager.focusSlotId(for: target)`, `selection = target`, `.onChange(of: selection)`, `play(.click)`, and still no `digitalCrownRotation` / `.focusable`.
- S-9112 the existing guards S-6611 (`WatchPagerSourceTests`) and S-7913 (`WatchPagerFocusTests`) encode the old TabView. They are REWRITTEN to S-9111's statements (S-6611 keeps its "locked page answers a drag" claim; S-7913 keeps its focus-through-swipe claim as `state.focusSlotId = pager.focusSlotId(for: target)` before `selection = target`, and its "land clears the focus at least twice" count). S-6610, S-6612, S-7911, S-7912, S-7914..S-7916 stay unchanged and must stay green.

Readers of the changed contracts (grepped 2026-10-26): `WatchRestLabelsTests.swift` (every `XCTAssertEqual(deriveRestLabels(...), WatchRestLabels(now:next:))` comparison of a "next exercise" outcome now needs `nextSlotId:`; S-7602, S-7603, S-7603c, S-7608 are the candidates, the builder runs the file and fixes every red one, tests only), `WatchRestSurfaceTests.swift` (S-8621 reads the view's clock; unaffected), `WatchPagerSourceTests.swift` (S-6611), `WatchPagerFocusTests.swift` (S-7913), `docs/state_management/watch_surface_wrist.md`, `docs/rest_tracking.md` (mentions the labels), `ios/OmniTrain Watch App/ContentView.swift` (the one caller of `WatchRestView(`, `:430`).

## Phases

- P1 `crew-builder-watch` — rest Next (D-6, D-7, S-9101..S-9109). Scope: `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchRestAdvanceTests.swift` (new). Serial.
- P2 `crew-builder-watch` — pager (D-1..D-5, S-9110..S-9112). Scope: `watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchLoggingPagerView.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchPagerModelTests.swift`, `WatchPagerSourceTests.swift`, `WatchPagerFocusTests.swift`. Serial after P1 (one Swift package, one `.build`).
- P3 lead — `xcodebuild` of the watch app (watchOS 9 API check), full `swift test`, full `flutter test` only if Dart is touched (it is not), mutation pass in an isolated copy, simulator look if the Mac is unlocked.
- P4 `crew-docs-keeper` — D-9 docs, after the last test-adding round; then `crew-reviewer`.

## Assumption Log

- The architect run is skipped: the seed carries exact code and two phases of ≤8 items. Recorded in friction.
- "Switch at once" was read as: no slide animation at all. If the owner wants a slide later, it is a transition on the `.id`'d logger, not a second page.
- A rest whose search finds an exercise whose planned sets are only partly logged (e.g. B 1 of 3) still goes to B: the line says "Next: B · Set 2 of 3" and Next opens B.
