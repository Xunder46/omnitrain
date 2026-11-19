# Review: 2026-10-23-66a-wrist-workout-summary-and-skip-plan · P1–P4 · working tree vs HEAD
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · nit 1 · tests: governor-run — full `swift test` 916 passed / 0 failed; `xcodebuild` BUILD SUCCEEDED; full `flutter test` green except one known flaky unrelated to this plan (green alone); lead mutations 21 of 22 red after a tests-only fix (the survivor, "skip with nothing owed", is equivalent: a stray id in the private skipped set changes nothing observable)
Diff vs Predicted Files: conforms — every predicted file is present, nothing outside the plan's list is in the diff under review (the plan-61/62 edits in `ContentView.swift` and the plan-66b content in `docs/session_summary.md` / `docs/watch_session_capture.md` / `docs/watch-app-setup-and-qa.md` steps 22–23 are other plans' work per the brief; the 66b docs' named test `test/session_summary_heart_rate_test.dart` exists).

## Findings

1. [Nit] `WatchWorkoutSummary.swift:126` — `note`'s completed gate carries an extra condition beyond D-2's letter (`engine.session?.sessionId == session.sessionId`), refusing a stale completed row when the engine has moved to another session. It is deliberate and tested (`WatchWorkoutSummaryTests.testS9605fANoteForASessionTheEngineIsNotOnBuildsNothing`) and consistent with S-9606 (a new workout gives way), so no action; recorded so D-2's text and the code can be reconciled in the next docs pass.

## Answers to the brief's questions

Q3 (double build / unseen end / deleted rows / recordedAt):
- Double build: no. `pending?.sessionId != session.sessionId` plus `activeSeenId = nil` before building (`WatchWorkoutSummary.swift:127-129`); a second `note` of the same completed row publishes nothing and leaves `pending` equal (`testS9605ACompletedWorkoutIsSummarisedOnce`).
- A workout the app did not see end: no. The `session.sessionId == activeSeenId` gate refuses a completed row this process never saw active (`testS9605AWorkoutCompletedBeforeThisProcessRanOwesNothing`); a relaunch mid-workout is covered because `restore()` ends with `revision += 1` (`ContentView.swift:306`), so the `$revision` sink notes the active session before any End.
- Rows deleted by the phone: the count is read from `engine.entries` (the live projection) at the completion revision itself, so a deletion that arrived before completion is excluded — the summary counts what the wrist actually holds, the same rule the End's `isRatingOwed` uses ("at least one effort entry after the phone's deletions", `WatchEffortRating.swift:186-190`). There is no snapshot taken at End that could go stale.
- `session.recordedAt` as the end instant: per the plan's recorded fact (D-120: the completed row's `recordedAt` is the end instant; a phone-sent completion uses the snapshot's `sentAt`) — not re-verified; for a wrist End `testS9603NoteBuildsTheSummaryForAWorkoutItSawActive` asserts `pending.endedAt == ended.recordedAt == clock.now`.

Q4 (Skip against the other readers): no reader breaks.
- The End action decides owed via `isRatingOwed` (`WatchEffortRating.swift:186-190`: preferences + entries + `hasEffortRating`) — it never reads `owedSessionIds`, so the filter cannot stop the End recording a prompt.
- `promptSessionId` / `isPromptOwed` / `canConfirm` are derived FROM `owedSessionIds` (`WatchEffortRating.swift:216-227`), so the filter is the intended behaviour: a skipped session stops being asked, the next owed one is asked (`testS9611SkipIsPerSession`).
- `restore()` re-reads prompts from the store; `declinedSessionIds` is in-memory only — the documented limit, pinned by `testS9612SkippedPromptReturnsAfterRelaunch`.
- The phone-answer path: the `engine.hasEffortRating` filter runs before the declined filter, so a rating arriving after a skip still removes the session, and the answer is stored (`testS9612SkipKeepsTheFirstAnswerWinning`).
- The amended guards still catch the named escapes: `testTheRatingOffersNoWayOutButAnAnswer` keeps `dismiss`, `cancel`, `close`, `later`, `not now` banned over declarations AND button labels in both files, and `testSkipAppearsOnlyUnderItsTwoNames` fails any second skip-prefixed name or label outside `skipPrompt`/`skipLabel`/`skipButton` (a label like "Skip for now" fails the prefix check). A way out named with a fresh word outside both lists (e.g. "postpone") would evade both — the same finite-list limitation the original guard had, not a regression.

Q5 (branch order, new workout, docs):
- Order: `ContentView.swift:417-420` — `isPromptOwed` → `host.summary.pending` → `isResting` → logging → start; the summary is reachable only after the question is closed and before rest/logging, pinned by `WatchWorkoutSummaryWiringSourceTests.testS9620TheShellShowsTheSummaryBetweenTheQuestionAndTheRest`.
- A new workout while it is up: every revision bump runs `self.summary.note(self.engine.session)` first in the `$revision` sink (`ContentView.swift:270-273`), and `note(active B)` takes a pending of another id away (`WatchWorkoutSummary.swift:123-126`); arrivals, `restore()`, `noteSurfaceChange()` and the rating/summary sinks all bump revision, so the summary gives way. Pinned by `testS9606ANewWorkoutTakesThePendingSummaryAway`.
- Docs say what the code does: `docs/watch_session_capture.md:288-302` matches the implementation (gates, rows, `dismissPending`, relaunch shows nothing, root order); `docs/state_management/watch_surface_wrist.md:365-380` matches plan 65's D-1/D-2/D-3; QA steps 27–28 (`docs/watch-app-setup-and-qa.md:700-722`) match both behaviours and name existing tests.

## Assumption Log rulings
The plan has no Assumption Log entries; its Decision Ledger decisions were all carried out as written and are ratified: D-1, D-2 (with the extra gate noted as a Nit), D-3 (the state names the set `declinedSessionIds` rather than `skippedSessionIds` — required by the amended guard's own scan, equivalent), D-4, D-5, D-6 (no wire change: Skip appends nothing, the summary is local — verified in the diffs).

## Scenario coverage
S-9601 → `WatchWorkoutSummaryTests.testS9601DurationTextReadsMinutesUnderAnHourAndHoursFromOne`
S-9602 → `testS9602RowsShowTimeSetsAndTheAverageHeartRate`, `testS9602AMixOfEffortsIsCountedUnderEffortsNotSets`, `testS9602AWorkoutWithNoHeartRateShowsExactlyTwoRows`, plus the built-from-`note` pair `testS9602b…` (2)
S-9603 → `testS9603NoteBuildsTheSummaryForAWorkoutItSawActive`
S-9604 → `testS9604TheAverageHeartRateCoversOnlyTheWorkoutWindow`, `…RoundsToTheNearestBeat`, `AWorkoutWithNoHeartRateCarriesNoAverage`
S-9605 a–f → one test each (`…CompletedBeforeThisProcessRan…`, `…WithNoEffort…`, `AnAbandonedWorkout…`, `…IsSummarisedOnce`, `…OfAnotherSession…`, `fANoteForASessionTheEngineIsNotOn…`)
S-9606 → `testS9606ANewWorkoutTakesThePendingSummaryAway`
S-9607 → `testS9607DismissEmptiesThePendingSummaryAndBothChangesArePublished`
S-9610 → `WatchRatingSkipTests.testS9610SkipRecordsNothing`
S-9611 → `testS9611SkipIsPerSession`
S-9612 → `testS9612SkipKeepsTheFirstAnswerWinning`, `testS9612SkippedPromptReturnsAfterRelaunch`
S-9613 → `testS9613SkipWithNothingOwedDoesNothing`
S-9614 → `WatchEffortRatingTests.testTheRatingOffersNoWayOutButAnAnswer` + `testSkipAppearsOnlyUnderItsTwoNames`
S-9620 → `WatchWorkoutSummaryWiringSourceTests` (3 tests: shell order, Skip under Confirm in the body slice, summary view rows)
No scenario without a test.
