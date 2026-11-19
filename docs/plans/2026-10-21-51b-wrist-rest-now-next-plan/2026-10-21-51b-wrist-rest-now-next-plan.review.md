# Review: 51b wrist rest now/next · P1-P3 · HEAD..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: per the brief's established facts — full `swift test` 711 tests, 0 failures before the last two tests were added; the new file now carries 12 tests (not re-run here, per the brief)
Diff vs Predicted Files: conforms (WatchRestLabels.swift new, WatchLoggingState.swift, WatchRestView.swift, WatchRestLabelsTests.swift new, docs/rest_tracking.md, docs/state_management/watch_surface_wrist.md — all in the plan's list)
## Findings
None. Notes per question, no findings:

1. `deriveRestLabels` edge ladder: empty ladder → `clamped` = 0, no valid slots, `position` nil → "No exercise" / "Nothing planned next". Current slot invalid (`WatchCatalogExercise(slot:)` rejects it) → `position` stays nil (the `if index == clamped` sits after the `guard ... continue`) → same safe pair. `currentIndex` out of range → clamped to the last valid index (or 0). `(here + 1)..<slots.count` with `here` last → empty range, `Array` of it is `[]`, the backward half `0..<here` still runs; single-slot ladder → both halves empty → "Nothing planned next". No crash path found.
2. Jump during rest: `restLabels` reads `session.currentExerciseIndex` and `effortKind` (which re-resolves from the *current* slot's declared kind or capabilities) on every read, so after a jump the "now" line names the jumped-to exercise: with nothing logged, the name alone (S-7606); with logged sets and a set effort, "Set N done" where N is that slot's logged count — the set just done if one was just logged there. Matches D-2's rule; the plan's table only pins the nothing-logged case, which the code and test satisfy.
3. `nextRoundNumber` is highest logged `roundNumber` + 1 over the engine's observations — the right "next" for a rest that follows a logged period. Singulars: "Periods"→"Period", "Intervals"→"Interval", "Rounds"→"Round" (all three end in "s", so the `dropLast` always applies correctly). Read correctly.
4. `WatchRestView`: `let labels = state.restLabels` before the `VStack` inside `TimelineView` is a legal result-builder local declaration (the file already used `let _ = pingIfOwed()` in the same closure). Both new lines are `lineLimit(2)` with `minimumScaleFactor(0.8)` and centered alignment; the `labels.next` line sits directly above `nextButton`, which the diff does not touch (action and last-element position preserved). 40 mm fit is the owner check, not a defect.
5. No test passes for the wrong reason. S-7601's first case uses plan 4 / 3 logged (unlike any default); S-7604 asserts both the copy constant and the literal; S-7609's first assertion ("Set 1 done" before any wrist `log()`) is what proves the phone's snapshot entry counts; S-7607's fall-through case has the current slot's own round entry making it done, so the search genuinely names Squat; S-7608's "alone" case is a genuine single-slot ladder. S-7610's guard strips comment lines including trailing `//`, so prose cannot satisfy it.
## Assumption Log rulings
The plan has no Assumption Log entries; nothing to rule on.
## Scenario coverage
S-7601 -> WatchRestLabelsTests.testS7601APlannedSetCountsTheLoggedSets
S-7602 -> WatchRestLabelsTests.testS7602ACompletePlanNamesTheLaterExercise
S-7603 -> WatchRestLabelsTests.testS7603TheForwardSearchWinsThenTheBackwardOne (+ testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped)
S-7604 -> WatchRestLabelsTests.testS7604EverythingDoneSaysNothingPlannedNext
S-7605 -> WatchRestLabelsTests.testS7605AFreeSetCountsPastThePlan
S-7606 -> WatchRestLabelsTests.testS7606AJumpedToExerciseWithNothingLogged
S-7607 -> WatchRestLabelsTests.testS7607ARoundEffortNamesTheNextPeriod
S-7608 -> WatchRestLabelsTests.testS7608ATimedEffortNamesTheNextExerciseWithWork
S-7609 -> WatchRestLabelsTests.testS7609ThroughTheEngineThePhonesSetCounts
S-7610 -> WatchRestLabelsTests.testS7610TheRestViewReadsTheLabels
(extra: testS7611OnlySetEntriesCountAsSets — only set entries count as sets)
Every test named in both docs files was checked against the test file; all exist.
