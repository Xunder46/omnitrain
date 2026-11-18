# Evidence — plan 223 (watch pop-ups solid, nothing under the clock)

Base commit `964dc4c7`. All runs observed by the lead on 2026-11-17.

## P1 (crew-builder-watch, 8m57s)
- Production applied exactly as briefed (diffed by the lead): `WatchSheetBackground.swift` (new), `.solidSheetBackground()` on the two Start-view sheets, the food and diagnostics sheets, and once on `WatchMenuView.body`'s `Group`; the two `.alert`s replaced by `finishQuestion` / `discardQuestion` over `WatchMenuConfirmationView`.
- Tests rewritten: S-17102, S-17101 (destructive role read from `discardQuestion`), S-17112, and `WatchTimerCueTests` S-15107 (pinned the old alert's empty Cancel). New: `WatchSheetSoliditySourceTests` (S-22301, S-22302, S-22303, S-22304, S-22306, S-22312).
- Lead: `swift test` whole target — Executed 1586 tests, with 0 failures. `xcodebuild` "OmniTrain Watch App", watchOS Simulator Series 11 (42mm) — BUILD SUCCEEDED.

## P2 (crew-builder-watch, 9m35s)
- Production applied exactly as briefed (lead `diff -w` against the P1 snapshot: only the briefed lines differ; P1 files untouched): Start body in a titleless `NavigationStack`; picker in a titleless `NavigationStack`; `.listRowBackground(Color.clear)` in `rows(of:)` and `leadingButton`; `labelSideInset = 6.0`, `.padding(.horizontal, Self.labelSideInset)`, `minimumScaleFactor(0.6)`; `VStack(spacing: Self.sectionGap) { finishRow; discardRow }`.
- New tests: S-22305, S-22309 (`WatchPlannedSurfaceSourceTests`), S-22307, S-22308, S-22310 (`WatchMenuTests`). No existing test edited.
- Lead: `swift test` whole target — Executed 1591 tests, with 0 failures. `xcodebuild` — BUILD SUCCEEDED.

## Mutation pass (lead, isolated copy of `watch/` + `ios/OmniTrain Watch App/` + `project.pbxproj` in the scratchpad; each mutant restored and `cmp`-checked)
24 mutants, one per guarded line: 23 KILLED on the first pass. m13 (an empty End's else arm also raises `confirmingFinish = true`) stayed ALIVE: S-22312 located each flag by `firstIndex`, so a second assignment escaped. The lead added two count assertions to `testS22312OneQuestionAtATime` (each flag raised exactly once in `finishRow`); m13 re-run: KILLED. Final: 24/24 killed.

## P3 (crew-docs-keeper, 5m36s)
- All 8 Docs delta rows applied. The keeper's re-wrap split four New markers across two lines; the lead joined each onto one line. `plan-lint after`: clean (13 scenarios, 8 docs-delta rows).
- Lead amendment before the docs brief (A-3): three New markers reworded so none contains its Old marker.

## Not verifiable here
- How the screens look: a titleless `NavigationStack` keeping the clock's corner clear, the solid backdrop on watchOS 26 glass, the label at 0.6 scale, the 10 pt gap. Owner checks in the plan; a 40 mm simulator look is offered to the owner.

## Lead fixes after review
- Finding 1: `WatchTimerCueTests.swift` added to P1 Predicted Files and the pinned-tests table.
- Finding 2: `testS17102TheViewDiscardsOnlyFromTheAlertsDiscardButton` renamed `…FromTheQuestionsDiscardButton` in the test and in `watch_surface_wrist_logging.md` (2 places) and `watch-app-qa-wrist-logging.md`.
- Finding 3: the question view spaces with `WatchMenuView.surfaceInset` / `.sectionGap` (now `fileprivate`, D-22316); S-3104B reads the exact `fileprivate` line.
- Finding 4: Progress table updated.

## Lead's simulator look (owner asked, 2026-11-17) — Apple Watch SE 3 (40mm), watchOS 26.4, the review's seeded store
- Start screen: the grid rests below the clock at launch; scrolled, the tiles and the Sync/Health lines blur and dim under the clock (system scroll edge), the time stays readable; scrolled back, the grid rests where it launched. "Resistance" keeps a margin on both sides of its tile.
- Exercise picker (Cardio tile): solid black; rows start below the ✕; each row is one capsule (no box); a row scrolled under the ✕ and the clock is blurred out.
- Session menu: solid black (no glow from the logging screen); End Session and Discard Session about 11 pt apart. Add Exercise: solid, single-shape rows under its title.
- Empty End -> "Discard session?" on a solid screen: red Discard, then Cancel; Cancel put the menu back with the workout still running.
- After logging one timed effort, End -> "Finish Workout?" on a solid screen, Finish in the theme colour (no red); Finish ended the workout and showed "Workout done" (the round-3 review could not confirm this tap).
- Nutrition sheet: solid black.
- No transition is played when a question replaces the menu (it switches instantly); not judged here — owner call.
- Seen, NOT caused by plan 223 (logic untouched): after relaunch, the last DISCARDED workout (the review's Push A) is still treated as the current session — the Cardio picker listed its three exercises as prominent in-session rows, and tapping one wrote a second "abandoned" row for that session and closed the picker without starting a workout (`WatchStartPaths.pickerRows` / `availablePickerExercises` read `engine.session` with no status check). Follow-up proposed to the owner.
