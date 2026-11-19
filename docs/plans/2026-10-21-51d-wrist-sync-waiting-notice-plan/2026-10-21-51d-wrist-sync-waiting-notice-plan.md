# Feature: 51d — the wrist says when entries are waiting for the phone

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, one minor fixed: a test's needless far-future clock). Swift 722/0, full flutter +5416 ~2, analyze 180 (baseline); 11 mutants caught and restored. The count also includes the session-end record and the rating (both owed to the phone). How the line fits on 40 mm and the real radio flips are owner checks. Seeded 2026-10-21 (re-audit finding "no user-visible indication anywhere that observations are owed"; owner, in chat: "just keep going with what we agreed on": the lead builds, reviews and commits without asking in between). Not built. Base commit: `.work/2026-10-21-51d/base.txt`. Team: the crew. Series list: `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md` (the 51 series). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

Everything you log on the watch is stored on the watch first and sent to the phone when it can be reached; nothing is lost. Today nothing on the watch tells you that something is still waiting, so a workout finished out of range looks the same as one the phone already has. After 51d the watch says so, in two places.

| Situation | Now | After 51d |
|---|---|---|
| Phone out of reach (the radio says so), 3 entries not yet acknowledged, session menu open (the list button) | nothing | a line at the top of the menu: "3 entries waiting for your phone" ("1 entry waiting for your phone") |
| Same, on the start screen (after finishing the workout) | the "Phone not reachable" line only | that line plus "3 entries waiting for your phone" |
| Phone reachable, a set just logged, the phone's receipt arrives within a second or two | nothing | still nothing (no flicker) |
| Phone reachable (or not yet known) but the oldest unacknowledged entry is 90 s old or older | nothing | the same "N entries waiting for your phone" line |
| Nothing waiting | nothing | nothing |

"Entries" are what you logged and the wrist keeps for the phone until it acknowledges: sets, timed efforts, holds, periods, food quick-logs and the session rating. The count is the number still unacknowledged. A rest window the wrist stores between two efforts is its own bookkeeping, so it is neither counted nor aged (found by the first test run: two sets with a rest between them store three records, and "3 entries" would have been wrong).

Unchanged: the logging and rest screens (no new line there), the Sync button, every wire message, the phone, how and when entries are resent.

## Decision Ledger

- D-1 One pure function `deriveSyncNotice(pending:reachability:now:) -> String?` in a new `watch/watchos/Sources/WatchSessionEngine/WatchSyncNotice.swift` (platform independent, so `swift test` covers it) with copy `WatchSyncNoticeCopy` (`waiting(_ count:)` -> "1 entry waiting for your phone" / "N entries waiting for your phone", `graceSeconds = 90`). Rule: empty -> nil; reachability `.unreachable` -> the text; otherwise the text only when the oldest pending record's `recordedAt` is at least `graceSeconds` before `now` (the exact boundary shows). `pending` is `[WatchObservationRecord]`; the count is its length.
- D-2 Engine accessor `WatchSessionEngine.unconfirmedObservations: [WatchObservationRecord]` (new, beside `pendingObservations()`, `WatchSessionEngine.swift:~1431`): `storedObservations.filter { $0.confirmedAt == nil }`, the same filter `pendingObservations()` uses; a receipt (`confirmObservations`, `:1817`) removes an entry from it.
- D-3 The shell host (`WatchAppHost` in `ios/OmniTrain Watch App/ContentView.swift`) gets `var syncNotice: String?` = `deriveSyncNotice(pending: engine.unconfirmedObservations, reachability: phoneReachability, now: Date())`, read at render. `WatchStartView` and `WatchMenuView` each take `syncNotice: String? = nil` and show it as one `footnote` secondary-colour line (start screen under the phone status hint; menu at the very top above the lock caption). The views re-run on the host's `revision`, which every receipt and reachability change already bumps; the 90 s rule is evaluated whenever a body runs (no ticker is added).
- D-4 Not in scope: a line on the logging or rest screens (no room on 40 mm), a badge, a haptic, retry timing (51f), failed-start and permission messages (51e), the Dart watch client.

## Readers listed

- `WatchMenuView(` constructors: `ContentView.swift` `menuSheet` (~:401) and tests (`WatchMenuTests`, check `WatchMenuView(` grep: the new parameter has a default, so none changes). `WatchStartView(` constructors: `ContentView.swift` (~:296) only (default parameter).
- `WatchSessionEngine.pendingObservations()` readers are unchanged; the new property reads the same array.
- Scenario ids S-7701..S-7707 checked free in `test/`, `docs/`, `watch/`.

## Core scenarios

`watch/watchos/Tests/WatchSessionEngineTests/WatchSyncNoticeTests.swift` (new). Records are hand-built `WatchObservationRecord`s with a fixed `now`.
- S-7701 no pending -> nil for `.unreachable`, `.reachable` and `.unknown`.
- S-7702 `.unreachable`: 1 pending -> exactly "1 entry waiting for your phone"; 3 pending -> "3 entries waiting for your phone" (records only seconds old).
- S-7703 `.reachable`: two pending, both younger than the grace (30 s and 10 s) -> nil; two pending, the older 120 s and the other 10 s -> "2 entries waiting for your phone".
- S-7704 `.unknown`: young -> nil; old -> the text (the arm the rule gives the same grace as reachable).
- S-7705 boundary: the oldest exactly 90 s -> the text; 89 s -> nil.
- S-7706 through the engine (`Harness`, a bench session, two sets logged through `WatchLoggingState.log()`, then `confirmObservations`): raw `unconfirmedObservations` is 1 after the first set and 3 after the second (the rest window is stored too); the notice reads "2 entries waiting for your phone", and after the first set's receipt "1 entry waiting for your phone".
- S-7708 rest windows are not counted: `.unreachable` with only a rest window -> nil; a set plus a rest window -> "1 entry waiting for your phone"; `.reachable` with an old rest window and a young set -> nil (an old rest window must not age the notice).
- S-7707 source guards: `ContentView.swift` passes `syncNotice: host.syncNotice` to both views and the host defines `syncNotice` through `deriveSyncNotice`; `WatchStartView.swift` and `WatchMenuView.swift` declare `syncNotice` and show it.

## Phases

- P1 (`crew-builder-watch`, glm, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchSyncNotice.swift,watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift,watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift,watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift,ios/OmniTrain Watch App/ContentView.swift,.work/crew/2026-10-21-51d/**"`): D-1..D-3 as EXACT TEXT in the brief. Done: `swift test --filter WatchSessionEngineTests`, `--filter WatchMenuTests`, `--filter WatchStartPathsTests` (names as found); the lead builds the watch target with `xcodebuild`.
- P2 (`crew-builder-watch`, glm, after P1, `--scope "watch/watchos/Tests/WatchSessionEngineTests/WatchSyncNoticeTests.swift,.work/crew/2026-10-21-51d/**"`): S-7701..S-7707, no production edit.
- P3 (`crew-docs-keeper`): `docs/state_management/watch_surface_wrist.md` (the waiting line, where it shows, the rule), the evidence file.
- Lead: diff vs lists, full `swift test`, `xcodebuild`, analyze, docs tests, full `flutter test` once, the lead's mutation pass (each arm: unreachable, reachable-old, unknown-old, the 90 s boundary, the count, the plural), reviewer, commit.

## Owner checks (owner)

- (owner) Phone off or far away: log a set, open the list button: "1 entry waiting for your phone"; bring the phone back: the line disappears once the phone has the entry. Check the line fits the menu and the start screen on 40 mm.

## Scope budget

About 70 production lines (new file about 45, others about 25), about 120 of test, docs about 15. One track, three phases.
