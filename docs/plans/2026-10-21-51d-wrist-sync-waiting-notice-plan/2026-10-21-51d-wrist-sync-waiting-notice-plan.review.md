# Review: 2026-10-21-51d-wrist-sync-waiting-notice-plan · P1–P3 · working tree (uncommitted, base .work/2026-10-21-51d/base.txt)
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: not run by reviewer (brief forbids; lead's full `swift test`: 722 tests, 0 failures; xcodebuild watch target compiles; 11 mutants each caught, files restored byte-for-byte)
Diff vs Predicted Files: conforms (all seven files in the stat are the plan's predicted files; nothing outside)

## Findings

1. [Minor] watch/watchos/Tests/WatchSessionEngineTests/WatchSyncNoticeTests.swift:141 — S-7706 calls `deriveSyncNotice` with `reachability: .unreachable` and `now: Date().addingTimeInterval(1_000_000)`. In the `.unreachable` arm the age is ignored, so the far-future `now` is dead weight and can read as if the notice aged the entries there; a maintainer changing the arm to `.reachable` would silently change what the assertion exercises. Fix: pass `now: Date()` (the harness ages are 0–120 s, irrelevant to the unreachable arm) or a comment saying the arm ignores age. Guard: none needed (the count assertions already fail on a regression).

## Answers to the brief's questions

1. `deriveSyncNotice` misreads: none found. A pending record whose `recordedAt` is in the future of `now` (clock set back) gives a negative `timeIntervalSince` on the reachable/unknown arms → nil, the conservative outcome; the unreachable arm still shows, which is right. A pending list holding only rest windows filters to empty, `min()` is nil, returns nil (S-7708 asserts it). `WatchObservationKind` (WatchRecords.swift:50) is set/timed/round/hold/nutritionQuickLog/effortRating/sessionEnd/rest; sensor samples live in `storedSensorSamples`, never in `storedObservations`, so no sensor kind can enter the count. `session_end` and `effort_rating` are wrist-emitted, not user-logged, and are counted — that matches D-1 ("the count is its length" minus rest) and they are genuinely owed to the phone; the plan's prose enumeration omits them but D-1 is the rule and the code follows it.
2. `WatchAppHost.syncNotice` re-evaluation: receipts land through `bridge.onIncoming` → `orchestrator.receive` → `MainActor.run { revision += 1 }` (ContentView.swift:149); reachability flips bump in `onReachabilityChange` (:158). The root body observes the host, so every bump re-runs it and both `WatchStartView` (:307) and the menu sheet (:417) are rebuilt with a fresh `host.syncNotice`. The event that changes the pending list without a `revision` bump is a log itself (a set on the logging surface, a food quick-log from the start screen): neither bumps the host. Neither surface showing the line is visible at that moment — the start view is covered by the food sheet, whose dismissal re-runs the root body (local `@State` change), and the logging surface carries no line; the menu sheet blocks its own logging surface. The 90 s rule being evaluated only when a body runs (no ticker) is D-3's stated decision, not a defect.
3. `unconfirmedObservations` is exactly `storedObservations.filter { $0.confirmedAt == nil }` — the same filter on the same array `pendingObservations()` (WatchSessionEngine.swift:1431) rebuilds its messages from; `confirmObservations` (:1825) is the only receipt path and clears `confirmedAt`. Reading it from the main actor in the host is the same pattern the body already uses for `host.engine.session`; the engine is a plain class whose off-main mutation path predates this change, so the diff adds no new class of access.
4. The two views: the menu shows the notice first in the VStack, above `lockCaption` — D-3's "very top above the lock caption"; the start screen's notice sits under `WatchPhoneStatusHint` inside the `ScrollView`'s VStack (WatchStartView.swift:113), so a long line scrolls rather than clipping. Both use `.font(.footnote)` + `.foregroundStyle(.secondary)`, no colour literals, no raw pieces. Both new init parameters are labelled with `= nil` defaults; the only constructor sites in `ios/` and `watch/` are ContentView.swift:307 and :417 (grep), both updated — no existing call breaks.
5. Tests: none passes for a wrong reason. S-7701 covers all three reachabilities against empty; S-7703/S-7704 cover young-vs-old for reachable and unknown separately (no missing arm — unknown-old is asserted non-nil, so unknown is not accidentally the unreachable arm); S-7705 pins both sides of the boundary and the constant. The S-7707 source guards strip comment lines (including `///` doc lines and trailing `//`), so prose cannot satisfy them; losing either view's pass site drops the counted lines to 1, and losing the host's derivation fails the `deriveSyncNotice(` assert — both survive a regression. S-7706 exercises the real engine path (`Harness`, `WatchLoggingState.log`, `confirmObservations`) and asserts the rest window inflates the raw count to 3 while the notice reads 2 — the defect the first run found is pinned from both sides.

## Assumption Log rulings

No Assumption Log entries in the plan or the diff; nothing to rule on.

## Scenario coverage

- S-7701 → WatchSyncNoticeTests.testS7701NoPendingIsNilForEveryReachability
- S-7702 → WatchSyncNoticeTests.testS7702UnreachableSaysTheCountOfFreshEntries
- S-7703 → WatchSyncNoticeTests.testS7703ReachableWaitsForTheGraceAndCountsAllPending
- S-7704 → WatchSyncNoticeTests.testS7704UnknownGetsTheSameGraceAsReachable
- S-7705 → WatchSyncNoticeTests.testS7705TheExactGraceBoundaryShows
- S-7706 → WatchSyncNoticeTests.testS7706TheEngineCountsUnconfirmedAndAReceiptRemovesOne
- S-7707 → WatchSyncNoticeTests.testS7707TheShellHostPassesTheNoticeToBothViews · testS7707BothViewsDeclareAndShowTheNotice
- S-7708 → WatchSyncNoticeTests.testS7708RestWindowsAreNotCounted

Docs: every behaviour sentence in the `watch_surface_wrist.md` addition names a test listed above, and every name it cites (files, `deriveSyncNotice`, `WatchSyncNoticeCopy`, `graceSeconds`, `unconfirmedObservations`, all nine test names) was read in source this run. Owner checks (40 mm fit, real radio flips) remain with the owner, as the plan states.
