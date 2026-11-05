# Feature: 70 — the wrist's exercise page fits a 40 mm watch

> Status: Iteration 1 active. Owner answers (2026-10-24, asked and answered): the "No heart rate, Health access is off" line leaves the exercise pages; the Start screen (already) and the workout summary (new, below) say it instead. One track: watch client (`watch/watchos/`, `ios/OmniTrain Watch App/`).
> Next handoff: `crew-builder-watch` (Phase 1), then the lead's simulator check.
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`. Starts after plan 73's Phase 1 is verified (same Swift package, serial).

## Overview

| What you do | Now (seen on the 40 mm simulator, 2026-10-24) | After 70 |
|---|---|---|
| Open a run / ride / row exercise page | The "2/3" counter sits under the menu button; the Health line below it is cut mid-word on every exercise page; Start is pushed to the very bottom edge (off it when the line wraps to two lines) | The counter sits to the left of the menu button; no Health line on exercise pages; Start has its room back |
| Location access refused, on a distance exercise | "No distance, Location access is off" wraps or is cut | The same words on one line (it shrinks to fit), only on distance exercises |
| Heart-rate access off, finish a workout | Nothing on the summary says why there is no heart rate | The summary shows one line, "No heart rate, Health access is off", where the Avg HR row would be |
| The lifting page | Fits | Fits (the counter moves left of the button there too) |

Code facts (scouts + lead, with a screenshot of the 40 mm simulator):
- One view for every effort kind: `WatchLoggingView` (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift`); `header` l.164-212; `titleClearance = 14.0` (l.70); `surfaceInset = 4.0`; the notices `ForEach(model.sensorNotices, ...)` l.199-206 with `.lineLimit(2)`. The menu button is a toolbar item (`ios/OmniTrain Watch App/ContentView.swift` l.542-551, `.topBarTrailing`). Measured on the 40 mm simulator (162 x 197 pt): the button is a circle spanning x 122-152 pt, y 9-41 pt; the name row starts at y ≈ 37 pt, so the counter at the trailing edge sits under the button.
- `WatchLoggingState.sensorNotices` (`WatchLoggingState.swift` l.318-326) adds `noHeartRate` when `sensors.heartRateAccess == .denied` and `noDistance` when location is denied and the exercise covers distance. Strings in `WatchHealthAccess.swift` (`WatchSensorNoticeCopy`). The Start screen has its own, longer line (`WatchHealthAccessCopy.offLine`), unchanged.
- The summary: `WatchWorkoutSummary` / `WatchWorkoutSummaryView` (`WatchWorkoutSummary.swift`, `WatchWorkoutSummaryView.swift`); shown from `ContentView.swift` l.419-420 `WatchWorkoutSummaryView(summary: pending, onDone: { host.summary.dismissPending() })`; the host exposes `healthAccess` (`WatchHealthAccess`, `.off` when Health refused). The summary today shows the Avg HR row only when a heart rate was recorded and says nothing otherwise.

## Decision Ledger

- **D-1** `WatchLoggingState.sensorNotices` stops adding `WatchSensorNoticeCopy.noHeartRate`; only `noDistance` remains (same condition). `WatchSensorNoticeCopy.noHeartRate` stays declared: the summary uses it (D-4).
- **D-2** `WatchLoggingView.header`: the first `HStack` (exercise name + page counter) gets `.padding(.trailing, Self.menuClearance)` placed before `.padding(.top, Self.titleClearance)`, with `private static let menuClearance = 40.0` and a doc comment ("Width the name row leaves free at the trailing edge so the page counter and a long name stop short of the menu button, which spans the last 40 pt of a 40 mm screen's top-right corner"). The counter stays the trailing child of that row; nothing else in the header moves.
- **D-3** The notices' `Text(notice)` modifier chain keeps `.font(.caption2)`, `.foregroundStyle(.secondary)`, `.minimumScaleFactor(0.7)` and changes `.lineLimit(2)` to `.lineLimit(1)` (35 characters at caption2 scaled to 0.7 fit 154 pt).
- **D-4** Summary line: `WatchWorkoutSummary` gains `public func heartRateNote(healthOff: Bool) -> String?` returning `WatchSensorNoticeCopy.noHeartRate` when `averageBpm == nil && healthOff`, else nil. `WatchWorkoutSummaryView` gains `public let healthOff: Bool`, init `init(summary:healthOff:onDone:)`, and renders `Text(note)` (`.font(.caption2)`, `.foregroundStyle(.secondary)`, `.multilineTextAlignment(.center)`) between the rows and the Done button when `summary.heartRateNote(healthOff: healthOff)` is non-nil. `ContentView.swift` l.420 passes `healthOff: host.healthAccess == .off`.
- **D-5** Not changed: the Start screen's own line; the workout summary rows; the pager; the Crown; the rest page. A distance page still carries a "Distance" tile, a stepper pair is not added or removed.
- **D-6** Deviation noted for the owner: they were told the summary "shows" the Health line; it did not, so D-4 adds it (smallest honest way to keep the promise).
- **D-7** Waiting readers (lead's rule as): nothing waits on a notice; no spinner or timeout reads `sensorNotices`.

## Feature Invariants

- On a 40 mm screen the name row, the counter and the menu button never overlap; Start is fully on screen on a distance exercise with Location refused.
- The lifting, timed, round and hold pages keep their layout apart from the header clearance.

## Scenarios (ids `S-100xx`; grep 2026-10-24: unused)

- **S-10001 (model) heart-rate refusal no longer produces an exercise-page notice.** Fixtures (surface built as in `WatchSensorAccessNoticeTests.swift` l.140-270): (a) `heartRateAccess = .denied`, `locationAccess` allowed → `sensorNotices == []`; (b) both denied, exercise capabilities `["time","distance"]` → `[noDistance]`; (c) both denied, capabilities `["reps","sets","load"]` → `[]`; (d) `heartRateAccess = .allowed`, location denied, distance exercise → `[noDistance]`. Fails today: (a) and (b) return `noHeartRate`.
- **S-10002 existing notice tests move with D-1**: `WatchSensorAccessNoticeTests.swift` l.148-149 (`[noHeartRate]` → `[]`), l.172-173, l.227-228 (`[noHeartRate, noDistance]` → `[noDistance]`), l.264. The builder edits these and lists each in the report.
- **S-10003 (source guard) header clearance.** Comment-stripped `WatchLoggingView.swift`: contains `private static let menuClearance = 40.0`; in the header body the statement `.padding(.trailing, Self.menuClearance)` occurs after the closing brace of the first `HStack(spacing: 4) {` row and before `.padding(.top, Self.titleClearance)` (compare indices of the exact statements).
- **S-10004 (source guard) one-line notices.** The `ForEach(model.sensorNotices, id: \.self) { notice in ... }` block contains `.lineLimit(1)` and does not contain `.lineLimit(2)`; it still contains `Text(notice)` (S-8908 stays green).
- **S-10005 (model) the summary's line, one test per arm.** (nil avg, off) → `noHeartRate`; (nil avg, not off) → nil; (140 avg, off) → nil; (140 avg, not off) → nil. Use an average (`137`) unlike any default.
- **S-10006 (source guards) the summary view and the shell.** `WatchWorkoutSummaryView.swift` contains `public let healthOff: Bool`, `self.healthOff = healthOff`, `summary.heartRateNote(healthOff: healthOff)` and `Text(note)`; `ContentView.swift` contains the exact statement `healthOff: host.healthAccess == .off`; the S-9620 string at `WatchWorkoutSummaryWiringSourceTests.swift` l.58 (`WatchWorkoutSummaryView(summary: pending, onDone: { host.summary.dismissPending() })`) becomes the new call (reader list: that file only; grep 2026-10-24).
- **S-10007 (lead, simulator, 40 mm SE 3)** the distance exercise page seeded with a session whose first exercise is a ride shows the counter left of the menu button, no Health line, Start fully on screen; the lifting page likewise; a screenshot is taken for each (not a package test).

## Phase 1 (`crew-builder-watch`, one run, 7 items)

1. [ ] D-1 — `WatchLoggingState.swift` `sensorNotices` (l.318-326).
2. [ ] D-2, D-3 — `WatchLoggingView.swift` `header`.
3. [ ] D-4 model — `WatchWorkoutSummary.swift`.
4. [ ] D-4 view + shell — `WatchWorkoutSummaryView.swift`, `ios/OmniTrain Watch App/ContentView.swift` l.420.
5. [ ] Move existing tests with D-1 (S-10002) and the S-9620 string.
6. [ ] New tests S-10001, S-10003..S-10006 — new `watch/watchos/Tests/WatchSessionEngineTests/WatchExercisePageFitTests.swift`.
7. [ ] Report FIRST as a skeleton, then fill it.

**Done**: `swift test --package-path watch/watchos --filter WatchSensorAccessNoticeTests`, `--filter WatchExercisePageFitTests`, `--filter WatchHealthAccessWiringSourceTests`, `--filter WatchWorkoutSummary`, `--filter WatchSessionEngineTests` (append-only guard; new names avoid update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy/set: `heartRateNote` is fine). The SwiftUI view code compiles only under xcodebuild: use only watchOS 9 API (no `.onChange(of:) { old, new in }`, nothing watchOS 10-only); the lead builds it.
**Predicted files**: the five source files above, `WatchSensorAccessNoticeTests.swift`, `WatchWorkoutSummaryWiringSourceTests.swift`, `WatchExercisePageFitTests.swift` (new), plan evidence.

## Owner device checks

- (owner) ODC-1 On a 40 mm watch: start a ride/run, check the counter, Start, and (with Health access off) that the Start screen and the final summary say it.

## Progress
- [x] Phase 1
- [x] Lead's 40 mm check (S-10007)

## Assumption Log
- Lead's 40 mm check (S-10007) done on the SE 3 (40 mm) simulator: ride page and lift page, counter left of the menu button, Start fully on screen (screenshots in the session scratchpad). The summary line with Health access off was not seen on a screen (owner check ODC-1).
- Deviation told to the owner: the summary did not show the Health line before; D-4 added it.
- Swift: 15 mutants of plans 70/73/71 killed (isolated copy).

## Feedback
