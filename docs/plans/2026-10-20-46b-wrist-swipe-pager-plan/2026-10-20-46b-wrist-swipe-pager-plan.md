# Feature: 46b — swipe between exercises on the wrist logging screen

> Status: BUILT, PROVED AND REVIEWED 2026-10-20 (review APPROVE WITH FIXES, all four findings fixed). Swift 669/0, full flutter +5323 ~2 on the last run (two phone-side tests, S-144 and S-5115, failed in some full runs and pass alone and in other full runs: pre-existing flakiness, see `.work/friction.md`), mutation pass 10/10 red, watch target builds with xcodebuild, 40 mm simulator shows the counter and a remount on the third exercise. A real swipe, the preview card, the locked notice and its haptic are owner checks (the Simulator could not be driven: Mac screen locked). Base commit: `.work/2026-10-20-46b/base.txt`. Team: the crew (lead-seeded; facts from the audit scout sheets `scout-nav.md`, `scout-ladder.md`, `scout-engine-writers.md`).
> Series: `docs/plans/2026-10-20-46-wrist-logging-series.md` (owner decisions O-5, O-6, O-7). Needs 46a (per-exercise numbers, Crown on the surface) and 46c (serialised session writes) committed first.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md

## Goal and acceptance

| What you do on the watch | Now | After 46b |
|---|---|---|
| On the logging screen of a session with several exercises, swipe left or right | nothing | the next or previous exercise slides in as a preview card (name, how many sets logged, "2/5"); when it settles it becomes the current exercise and shows its own rows and numbers |
| Swipe while an effort clock is running (timed work, hold, period countdown) | nothing | no paging; a swipe gives a failure tap and a one-line notice "An effort is running" for about a second and a half |
| Swipe on a session with one exercise | nothing | nothing (no pager, no counter) |
| The Crown | steps the outlined value | unchanged: it never changes exercise |
| Rest | replaces the screen; menu button available | unchanged (no swiping in rest; end the rest first) |
| The phone screen when you swipe | unchanged | unchanged (the phone keeps its own focus; owner decision O-5) |
| The menu sheet jump | works | works, same select path |

## Decision Ledger

- D-1 `WatchPagerModel` (new `watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift`, `@MainActor public final class ... : ObservableObject`, platform independent so `swift test` covers it) over one `WatchMenuState` (`WatchMenu.swift`: `rows` with `isCurrent`, `isLocked`, `jump(to:)`): `rows`, `pageCount`, `currentIndex` (first row with `isCurrent`, else 0), `isLocked`, `showsPager` (`rows.count > 1 && !isLocked`), `pageLabel` ("2/5", nil when one exercise), `land(on index:) async -> Bool` (same index: true without any select; out of range: false; locked: records a notice and returns false; else `menu.jump(to: rows[index].slotId)`), `noteLockedSwipe()` (sets `noticeUntil = clock() + noticeSeconds`, publishes), `noticeVisible(at:) -> Bool`, constants `WatchPagerCopy.lockedNotice = "An effort is running"` (same words as `WatchMenuView.lockCaptionText`) and `noticeSeconds = 1.5`; the clock is injected (`init(menu:clock:)`).
- D-2 Preview, commit on settle (O-7): the pager shows a preview card for every page that is not the current exercise; the engine's current exercise changes only through `settle` (one `jump` per settled page, never per intermediate frame). The select writes a row and emits one `exercise_advanced` lifecycle frame (existing behaviour); the phone screen does not follow (O-5, scout sheet `scout-phonesession.md` Q1: the phone resync pins its own focus).
- D-3 Lock (O-7): while `isLocked` the view renders the single live page without a `TabView` (so no dots, no paging) and a `simultaneousGesture(DragGesture(minimumDistance: 24))` whose end, when mostly horizontal and over 24 pt, calls `noteLockedSwipe()` and plays `WKInterfaceDevice.current().play(.failure)`; the notice shows as a one-line overlay while `noticeVisible`.
- D-4 No paging in rest (O-6): the shell already swaps the whole screen to the rest view when `host.logging.isResting` (`ContentView.body`); unchanged. The pager is only mounted by `loggingSurface`.
- D-5 View (`WatchLoggingPagerView.swift`, watchOS only, new): `TabView(selection: $selection)` with `.tabViewStyle(.page(indexDisplayMode: .never))` (own counter instead of dots, which would sit on the Log button on a 40 mm screen); page `i` is `WatchLoggingView` when `rows[i].isCurrent` else a `WatchExercisePreviewPage`; `.onChange(of: selection)` (single-argument form: the package targets watchOS 9) starts `Task { if await pager.land(on: newValue) == false { selection = pager.currentIndex } }`; an engine-driven change (phone push, menu jump) moves `selection` to `pager.currentIndex` when the host `revision` changes and the user is not mid-settle. `WatchLoggingView` gains `pageLabel: String? = nil` shown at the end of the name line.
- D-6 Shell: `ContentView.loggingSurface` builds `WatchLoggingPagerView(menu: WatchMenuState(engine: host.engine, paths: host.paths, rating: host.rating), state: host.logging, revision: host.revision, onLogged: { host.noteSurfaceChange() })` instead of `WatchLoggingView(...)`; the toolbar menu button stays.
- D-7 Not in scope: any change to the phone, the wire, the rest view, the menu sheet; dots; Crown paging; swiping while resting.

## Readers listed

- Tests reading `ContentView.swift` text: `WatchMenuTests.testS3103ATheRestScreenCarriesTheMenuButton` (~:1017), `WatchSensorSourceSourceTests` (`viewSource()`), `WatchHostHopSourceTests` (46c), `test/rest_is_count_up_contract_test.dart`; the edit changes only `loggingSurface`'s body.
- `WatchLoggingView(` constructor callers: `ContentView.swift` only (grep) plus the Dart debug harness (separate language).
- `WatchMenuState(` constructions: `ContentView.menuSheet` and tests.

## Core scenarios (ids S-6601.. checked free)

`WatchPagerModelTests.swift` (`@MainActor`, harness like `WatchMenuTests`: a three-exercise session [A, B, C], current A, a controllable clock):
- S-6601 rows/currentIndex/pageLabel: "1/3" on A; after `engine.selectExercise(B)` the model reads index 1 and "2/3" (no caching).
- S-6602 land(on: 2) when free: returns true, the engine's current slot is C, one `exercise_advanced` frame emitted (count frames via the harness sink); a second `land(on: 2)` returns true and emits nothing more.
- S-6603 settle while a work clock runs (start an elapsed timer on A): returns false, current stays A, `noticeVisible(at: now)` true, false at `now + 1.5` (boundary arm) and false before any attempt.
- S-6604 settle out of range (-1, 3): false, nothing changes.
- S-6605 a running REST does not lock: land(on: 1) returns true.
- S-6606 `showsPager` false with one exercise (and `pageLabel` nil), false while locked, true otherwise.
- S-6607 a phone-driven change of the current exercise between two reads is visible in `currentIndex` (engine applies an `exercise_advanced` lifecycle from the phone).
- S-6608 `land(on:)` for the phone-removed slot (row list shrank between the swipe and the settle): false, no crash.
Source scans (`WatchPagerSourceTests.swift`, helper style of `WatchSensorSourceSourceTests.swift`): S-6610 `ContentView.swift` `loggingSurface` contains `WatchLoggingPagerView(` and not `WatchLoggingView(`; S-6611 `WatchLoggingPagerView.swift` contains `.tabViewStyle(.page(indexDisplayMode: .never))`, exactly one `TabView(`, and a `DragGesture(` in the locked branch; S-6612 the pager file contains no `digitalCrownRotation` (the Crown stays on `WatchLoggingView`).

## Phases

| Phase | Agent | Items | Write scope | Parallel |
|---|---|---|---|---|
| P1 model + S-6601..6608 | crew-builder-watch | 4 | `WatchPagerModel.swift`, `WatchPagerModelTests.swift` | after 46c |
| P2 views (exact code in the brief) + shell + S-6610..6612 | crew-builder-watch | 5 | `WatchLoggingPagerView.swift`, `WatchLoggingView.swift`, `ContentView.swift`, `WatchPagerSourceTests.swift` | after P1 |
| P3 docs | crew-docs-keeper | 2 | `docs/**` | after P2 |
The governor builds the watch target with xcodebuild and looks at the 40 mm simulator (static: the seeded three-exercise session shows the live page with "1/3"). Builders: never run the full `flutter test`; Done lists include `swift-test --filter WatchSessionEngineTests` and the sibling `WatchMenuTests`, `WatchSensorSourceSourceTests`.

## Owner checks (owner)

- (owner) On a real watch, a session with three exercises: swipe left, the preview card appears and the next exercise becomes current; the counter reads 2/3; the phone screen does not move.
- (owner) Start a timed effort and swipe: you feel a failure tap and see "An effort is running"; the exercise does not change.
- (owner) With the effort stopped, swiping works again; the Crown still steps the outlined value and never changes exercise.

## Assumption Log

- A-1 The method is `land(on:)`, not `settle(on:)`: the module's S-004 source guard bans new names that start with `set` (settle does). Behaviour as D-1.
- A-2 `WatchLoggingPagerView` takes one `onSurfaceChange` closure (the host's `noteSurfaceChange`), used both after a logged set and after a landed swipe; the host's `revision` bump is what makes the pager re-read the engine.
