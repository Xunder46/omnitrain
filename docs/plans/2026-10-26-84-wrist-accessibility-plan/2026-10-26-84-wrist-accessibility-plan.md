# Feature: 84 — VoiceOver on the wrist reads the rest clock, the menu rows, the summary and the rating scale as sentences

> Status: BUILT AND PROVED 2026-10-26 (uncommitted). Six modifier deletions each turned their own guard red. VoiceOver reading order is a device check (optional). Earlier status: ARCHITECT COMPLETE 2026-10-26 (seeded by the lead; every `file:line` re-verified against base `56c3e56e3c6fb5b3d889010fae39e3bddfbf2dc7`). Team: the crew. Owner request (chat, 2026-10-26, "I'll go with your suggestions", audit finding W3: minimum viable set). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md. Package targets watchOS 9 (`watch/watchos/Package.swift` `platforms: [.macOS(.v13), .watchOS(.v9)]`): no watchOS 10-only API.

## What the owner sees

Nothing changes on screen. With VoiceOver on (Settings, Accessibility, VoiceOver on the watch):

| Screen | Today | After |
|---|---|---|
| Rest screen clock | reads the digits one by one ("2 colon 0 5") | "Rest time, 2 minutes 5 seconds", and it is marked as changing, so it is not re-announced every second |
| Rest screen Next | "Next" | "Next", hint = the line the screen already shows ("Next: Bench · Set 1 of 3") |
| Menu rows | name and count are two stops ("Squat" ... "3 logged") | one stop: "Squat, 3 logged" |
| Workout summary | each label and value is its own stop | one stop per row: "Time, 32:00" (the row is `WatchWorkoutSummaryCopy.time` = "Time" and `durationText` renders "m:ss"; the seed's "Duration, 32 min" named no real row — Architect notes N-6) |
| Rating scale | numbers "1".."5" with no meaning | "Rating 3 of 5", selected one says "selected"; the Crown reads the current choice |

(owner) Optional on a device: turn VoiceOver on and walk rest screen, menu, summary, rating. Not blocking.

## Decision Ledger

- D-1 One pure helper in the package (testable on macOS): `public enum WatchSpokenText` (new file `WatchSpokenText.swift`) with `duration(seconds: Int) -> String` ("0 seconds", "1 second", "45 seconds", "1 minute", "2 minutes 5 seconds", "1 hour 2 minutes 3 seconds" — drop zero units except when the total is 0, singular for 1) and `rating(_ value: Int, of highest: Int) -> String` ("Rating 3 of 5"). No dependency on SwiftUI. Names avoid the append-only verbs (crew rule r/ac).
- D-2 Rest screen (`WatchRestView.swift:63-85`): the clock `Text(elapsed)` (`:73`) gets `.accessibilityLabel("Rest time")`, `.accessibilityValue(WatchSpokenText.duration(seconds: state.restElapsedSeconds() ?? 0))` and `.accessibilityAddTraits(.updatesFrequently)`, appended to the clock's own modifier chain after `.minimumScaleFactor(0.7)` (`:77`). The seconds are read inline: `elapsed` (`:93-98`) computes them as a local and its body is pinned verbatim by `WatchRestPingWiringSourceTests` S-9109, so it is not refactored. `nextButton` (`:101-114`) gets `.accessibilityHint(state.restLabels.next)` — the same string the line above it shows; `labels` is a local of the `TimelineView` closure (`:62`) and out of scope in `nextButton`, which already reads `state.restLabels.nextSlotId` (`:104`). [Corrected — Architect notes N-1, N-2.]
- D-3 Menu rows (`WatchMenuView.swift:148-164` `rowLabel`): `.accessibilityElement(children: .combine)` on the `VStack`. The Button wrapper at `:121-135` keeps its tap; the combined element reads "name, count".
- D-4 Summary (`WatchWorkoutSummaryView.swift:38-45`): each row `HStack` (`:38-44`) gets `.accessibilityElement(children: .combine)`; the title `Text(WatchWorkoutSummaryCopy.title)` (`:34`) gets `.accessibilityAddTraits(.isHeader)`.
- D-5 Rating (`WatchEffortRatingView.swift:78-85` `scaleButton`, `:59-70` Crown): each scale button `.accessibilityLabel(WatchSpokenText.rating(value, of: WatchEffortRatingCopy.highest))` — the numeric scale max is `WatchEffortRatingCopy.highest` = 5 (`WatchEffortRating.swift:31`; the state exposes `scale: [Int]` at `:220` and `selected: Int?` at `:118`, and `state.highestLabel` is only the caption "Max effort") — plus `.accessibilityAddTraits(.isSelected)` on the selected (`watchProminent()`) branch; the view that owns `.digitalCrownRotation` (the body's root `VStack`, `:35-53`) gets `.accessibilityValue(state.selected.map { WatchSpokenText.rating($0, of: WatchEffortRatingCopy.highest) } ?? "No rating")` appended after `.interactiveDismissDisabled(true)` (`:72`). Confirm gets `.accessibilityHint("Saves your rating")` after `.disabled(!state.canConfirm)` (`:94`); Skip unchanged. [Corrected — Architect notes N-3, N-7.]
- D-6 Existing labels stay (`WatchLoggingView.swift:283,350`, `WatchExerciseListView.swift:187`, `WatchNutritionView.swift:226`, the two "Exercises" button labels). The logging tiles already speak "label value unit", so they are NOT touched.
- D-7 Not in scope: Dynamic Type (watchOS scales system text styles itself; the views use styles, not fixed sizes; if the architect finds a fixed `.font(.system(size:))` on a screen in D-2..D-5 it is listed, not fixed here), the food screen, the start screen, localisation (copy stays English like the rest of the app). Architect: no `.font(.system(size:` occurs anywhere under `Sources/WatchSessionEngine` — nothing to list.
- D-8 `WatchSpokenText.swift` is a plain engine-target file: no `#if os(watchOS)` wrapper and no SwiftUI import, so S-15301, S-15302 and S-15309 run on macOS under `swift test`. The views that call it keep their file-level `#if os(watchOS)` (on macOS the calls compile away with the views).

## Scenarios (exact fixtures; re-derive in the first run)

- S-15301 `WatchSpokenText.duration`: 0 -> "0 seconds"; 1 -> "1 second"; 45 -> "45 seconds"; 60 -> "1 minute"; 125 -> "2 minutes 5 seconds"; 3723 -> "1 hour 2 minutes 3 seconds"; 3600 -> "1 hour"; negative -> "0 seconds". Fails today: the type does not exist.
- S-15302 `WatchSpokenText.rating(3, of: 5)` == "Rating 3 of 5"; `(1, of: 10)` == "Rating 1 of 10".
- S-15303 source guard `WatchRestView.swift` (comments stripped, exact statements): `.accessibilityLabel("Rest time")`, `.accessibilityValue(WatchSpokenText.duration(`, `.accessibilityAddTraits(.updatesFrequently)` all inside `body`'s clock `Text(elapsed)` chain (assert they appear after `Text(elapsed)` and before `Text(labels.next)`), and `.accessibilityHint(state.restLabels.next)` after `nextButton`'s label. [Corrected — Architect note N-1: `labels` is out of scope in `nextButton`; the hint reads `state.restLabels.next`, the same expression `nextButton` already uses at `:104`.]
- S-15304 source guard `WatchMenuView.swift`: `rowLabel` contains `.accessibilityElement(children: .combine)` (exact statement, inside the function body, not elsewhere in the file: count == 1 there).
- S-15305 source guard `WatchWorkoutSummaryView.swift`: row `HStack` followed by `.accessibilityElement(children: .combine)`; title followed by `.accessibilityAddTraits(.isHeader)`.
- S-15306 source guard `WatchEffortRatingView.swift`: `.accessibilityLabel(WatchSpokenText.rating(` in `scaleButton`; `.isSelected` trait; `.accessibilityValue(` on the Crown view; `.accessibilityHint("Saves your rating")` on `confirmButton`.
- S-15307 the whole-module count guard: the number of files under `Sources/WatchSessionEngine` containing a comment-stripped `.accessibility` (dot-prefixed; bare "accessibility" also matches the comment in `WatchAccent.swift:12`) rises from today's 4 (`WatchStartView.swift`, `WatchExerciseListView.swift`, `WatchLoggingView.swift`, `WatchNutritionView.swift`) to at least 8 (a ratchet test; it must name each of the 4 new files: `WatchRestView.swift`, `WatchMenuView.swift`, `WatchWorkoutSummaryView.swift`, `WatchEffortRatingView.swift`). [Corrected — Architect note N-4.]
- S-15308 existing "Exercises" label guards stay green: `WatchLoggedHapticTests.swift:207-215` (testS7805) counts `.accessibilityLabel("Exercises")` == 2 in `ios/OmniTrain Watch App/ContentView.swift` (raw, no comment stripping); plan 84 does not touch `ContentView.swift`. [Corrected — Architect note N-5.]
- S-15309 zero-unit dropping in `WatchSpokenText.duration`: 61 -> "1 minute 1 second"; 3660 -> "1 hour 1 minute"; 3661 -> "1 hour 1 minute 1 second"; 2700 -> "45 minutes"; 120 -> "2 minutes"; 0 -> "0 seconds" (the only case that keeps a zero unit).

Guard form (crew rule ao): each source guard asserts the exact statement including braces/parentheses AND the rendered view, never a bare substring.

Readers of the changed contracts: views only; `WatchRestSurfaceTests.swift` (rest view clock string), `WatchWorkoutSummaryWiringSourceTests.swift`, `WatchPagerSourceTests.swift` (reads `WatchLoggingPagerView.swift`, untouched), `WatchHealthAccessWiringSourceTests.swift`, `docs/state_management/watch_surface_wrist.md`.

## Feature invariants

- `WatchSpokenText` stays pure: no SwiftUI import, no `#if os(watchOS)` — its tests run on macOS (D-8).
- `elapsed` in `WatchRestView.swift` is never refactored: S-9109 pins its body verbatim; the accessibility value reads `state.restElapsedSeconds() ?? 0` inline.
- Every new statement is appended to an existing chain or function; no existing statement is reordered (the order assertions in `WatchRestAdvanceTests` S-9109 and the slice bounds in S-9620/S-7505 depend on it).
- Copy is English, matching the existing copy style; no localisation keys.
- No `.font(.system(size:` anywhere (D-7; verified absent at base).
- Source guards strip comments before counting (`WatchAccent.swift:12` has the word "accessibility" in a comment; it must not count) and assert exact statements, never bare substrings (crew rule ao).

## Code pointers (current lines, base 56c3e56)

`WatchRestView.swift` clock chain (`:73-77`):
```swift
Text(elapsed)
    .font(.largeTitle)
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.7)
```
`WatchRestView.swift` `nextButton` (`:101-114`): closure reads `state.restLabels.nextSlotId` (`:104`); label `Text("Next")` + `.frame(maxWidth: .infinity)` (`:111`); `.watchProminent()` (`:113`). The hint goes after `:113`.
`WatchMenuView.swift` `rowLabel` (`:148-164`): `VStack` (`:149`), `Text(row.name)` (`:150`), count label `"\(loggedCount) logged"` (`WatchMenu.swift:44-45`), `.multilineTextAlignment(.leading)` (`:162`). The combine goes on the `VStack`.
`WatchWorkoutSummaryView.swift` (`:34-45`): title `Text(WatchWorkoutSummaryCopy.title)` with `.font(.headline)` (`:35`), row `HStack` (`:38-44`) rendering `Text(row.label)` / `Text(row.value)`, `.font(.footnote)` (`:45`).
`WatchEffortRatingView.swift` root chain (`:54-72`): `.padding` (`:54`), `.focusable(true)` (`:55`), `.digitalCrownRotation(...)` (`:59-70`), `.navigationBarBackButtonHidden(true)` (`:71`), `.interactiveDismissDisabled(true)` (`:72`). `scaleButton` (`:78-85`): `let button = Button("\(value)") { state.select(value) }` (`:79`), `if value == state.selected` → `.watchProminent()` (`:81`). `confirmButton` (`:87-95`): `.watchProminent()` (`:93`), `.disabled(!state.canConfirm)` (`:94`).

## Existing-functionality impact

| Touched surface | What already reads it (search result) | Effect | Guarded by |
| --- | --- | --- | --- |
| `WatchRestView.swift` clock chain `:73-77` | `WatchRestSurfaceTests` S-8621 `modifierChain(of: "Text(elapsed)")` collects the consecutive `.`-lines; `.font(.largeTitle)`/`.monospacedDigit()` remain in the collected chain after appending | stays green | S-15303 |
| `WatchRestView.swift` `elapsed` `:93-98` | `WatchRestPingWiringSourceTests` S-9109 pins the body verbatim (collapsed contains the dimmed/`clock` ternary) | untouched; seconds read inline at the call site | D-2 |
| `WatchRestView.swift` `nextButton` `:101-114` | `WatchRestAdvanceTests` S-9109 asserts the closure's statement order (`nextSlotId` read, label, `.watchProminent()`) | hint appended after `.watchProminent()`; order assertions unaffected | S-15303 |
| `WatchMenuView.swift` `rowLabel` `:148-164` | `WatchMenuTests` token-absence checks on the file; no test slices `rowLabel` | `.accessibilityElement(children: .combine)` added inside the function; tokens stay | S-15304 |
| `WatchWorkoutSummaryView.swift` body `:34-45` | `WatchWorkoutSummaryWiringSourceTests` S-9620 (`:113-133`) whole-file `contains`: title copy, `Text(row.label)`, `Text(row.value)`, Done button | all four `contains` stay true | S-15305 |
| `WatchEffortRatingView.swift` body `:34-73` | `WatchWorkoutSummaryWiringSourceTests` S-9620 (`:90-112`) slices `public var body` → `private func scaleButton`, asserts `confirmButton\s+skipButton` | value appended after `:72` keeps the regex and the slice bounds | S-15306 |
| `WatchEffortRatingView.swift` `scaleButton`/`confirmButton` | `WatchEffortRatingTests` S-211 banned-words scan (`Button("...")` / `label: { Text("...") }` patterns) | "Saves your rating" is a hint argument, not a scanned pattern | S-15306 |
| `WatchEffortRatingView.swift` crown `:59-70` | `WatchCrownUnitTests` S-7505 slices `digitalCrownRotation` → `isHapticFeedbackEnabled` | `accessibilityValue` appended after `:72` is outside the slice | S-15306 |
| `ios/OmniTrain Watch App/ContentView.swift` "Exercises" | `WatchLoggedHapticTests` S-7805 (`:207-215`) counts `.accessibilityLabel("Exercises")` == 2, raw | file untouched by this plan | S-15308 |
| `docs/state_management/watch_surface_wrist.md` | docs keeper (P4); file is ~50.7 KB against the 52 KB ceiling | one short paragraph, or the keeper splits the file first | P4 |

## Architect evidence (brief questions)

- **a) Accessibility usage today.** Bare `accessibility` matches 5 files under `Sources/WatchSessionEngine`; `WatchAccent.swift:12` is a comment only. Real `.accessibility` modifiers: 4 files — `WatchStartView.swift:182` (`.accessibilityElement(children: .combine)`), `WatchExerciseListView.swift:187` (`.accessibilityLabel`), `WatchLoggingView.swift:282` (`.accessibilityAddTraits(.isButton)`) and `:283,350` (labels), `WatchNutritionView.swift:226` (label).
- **b) Source-guard helpers to copy.** `WatchPagerSourceTests.swift`: `engineSource(_:)`, `strippingCommentLines(_:)`, `occurrences(of:in:)`, `propertyBody`. Precedents: S-8621 `modifierChain`, S-9109 verbatim pin + order assertions, S-9620 body slice + `contains`, S-7505 crown slice, S-211 banned-words scan, S-7805 raw count.
- **c) watchOS 9 API availability.** `watch/watchos/Package.swift` declares `.watchOS(.v9)`. In-repo: `.accessibilityElement(children: .combine)` (`WatchStartView.swift:182`), `.accessibilityAddTraits` (`WatchLoggingView.swift:282`), `.accessibilityLabel` (3 files). `.updatesFrequently`/`.isSelected`/`.isHeader`: no in-repo use — SwiftUI documents them for watchOS versions below 9; the lead's `xcodebuild` (P3) is the compiler check.
- **d) Tests that could break.** See the impact table — every reader keeps its assertions under the planned edit shapes; none is expected red.

## Phases

All phases are serial: P2 appends to P1's test file and its ratchet needs P1's two view files; P3 needs P2's code; P4 needs P3's verdicts. Plan 82 builds first (it edits `WatchMenuView.swift` `init` `:65` and `finishRow` `:203-218`; the guards here are statement-based, so its line shifts are harmless, but the file must not be edited concurrently).

- P1 `crew-builder-watch` — D-1, D-2, D-3, D-8 (S-15301..S-15304, S-15309).
  1. [ ] Create `WatchSpokenText` with `duration(seconds:)` — `watch/watchos/Sources/WatchSessionEngine/WatchSpokenText.swift` · `WatchSpokenText.duration`
  2. [ ] Add `rating(_:of:)` — `watch/watchos/Sources/WatchSessionEngine/WatchSpokenText.swift` · `WatchSpokenText.rating`
  3. [ ] Append label/value/trait to the clock chain — `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift` · `body` (`Text(elapsed)` chain `:73-77`)
  4. [ ] Append the hint after `.watchProminent()` — `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift` · `nextButton` (`:113`)
  5. [ ] Add `.accessibilityElement(children: .combine)` to the row `VStack` — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `rowLabel` (`:149`)
  6. [ ] Write S-15301/S-15302/S-15309 — `watch/watchos/Tests/WatchSessionEngineTests/WatchSpokenTextTests.swift` (new)
  7. [ ] Write S-15303/S-15304 and the partial ratchet (≥6, naming the 2 new files) — `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` (new; helpers copied from `WatchPagerSourceTests.swift`)

  **Done criteria:** gateway `swift-test` green; S-15301/S-15302/S-15309 red at base (the type does not exist — `prove-red` at `56c3e56`); S-15303/S-15304 red at base (statements absent).
  **Predicted files:** `WatchSpokenText.swift` (new), `WatchRestView.swift`, `WatchMenuView.swift`, `WatchSpokenTextTests.swift` (new), `WatchAccessibilitySourceTests.swift` (new). Nothing else changes.
  **Write scope:** `"watch/watchos/Sources/WatchSessionEngine/WatchSpokenText.swift" "watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift" "watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift" "watch/watchos/Tests/WatchSessionEngineTests/WatchSpokenTextTests.swift" "watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift"`

- P2 `crew-builder-watch` — D-4, D-5 (S-15305..S-15307). Waits for P1: appends to P1's guard file; the ratchet completes only after P1's two views land.
  1. [ ] Add `.accessibilityElement(children: .combine)` to each row `HStack` — `watch/watchos/Sources/WatchSessionEngine/WatchWorkoutSummaryView.swift` · `body` (`:38-44`)
  2. [ ] Add `.accessibilityAddTraits(.isHeader)` to the title — `watch/watchos/Sources/WatchSessionEngine/WatchWorkoutSummaryView.swift` · `body` (`:34-36`)
  3. [ ] Add label + `.isSelected` in both branches — `watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift` · `scaleButton` (`:78-85`)
  4. [ ] Append `.accessibilityValue(...)` after `.interactiveDismissDisabled(true)` — `watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift` · `body` (`:72`)
  5. [ ] Append `.accessibilityHint("Saves your rating")` after `.disabled` — `watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift` · `confirmButton` (`:94`)
  6. [ ] Write S-15305/S-15306 — `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` (append)
  7. [ ] Complete S-15307: ≥8 files, naming all 4 new ones — `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` (append)

  **Done criteria:** gateway `swift-test` green; S-15305/S-15306 red at the P1-end state (`prove-red`); S-15307 passes with the 8 named files.
  **Predicted files:** `WatchWorkoutSummaryView.swift`, `WatchEffortRatingView.swift`, `WatchAccessibilitySourceTests.swift` (append only). Nothing else changes.
  **Write scope:** `"watch/watchos/Sources/WatchSessionEngine/WatchWorkoutSummaryView.swift" "watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift" "watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift"`

- P3 lead — `xcodebuild` watch app build (only the lead runs it), full `swift test` (900 s timeout), mutation pass in an isolated copy: delete each added modifier one at a time; its guard must fail and the rest stay green.
  **Done criteria:** build succeeds; full suite green; every mutation flips exactly its own guard.
  **Predicted files:** none in the repo (mutations live in the isolated copy).

- P4 `crew-docs-keeper` — one paragraph in `docs/state_management/watch_surface_wrist.md` (mind the 52 KB ceiling: keep it short or split the file first) and the QA list; then `crew-reviewer` writes the reserved review file (see Feedback).
  **Done criteria:** docs paragraph merged under the ceiling; review file written.
  **Write scope:** `"docs/state_management/watch_surface_wrist.md" "docs/plans/2026-10-26-84-wrist-accessibility-plan/2026-10-26-84-wrist-accessibility-plan.review.md"`

## Progress

- P1: 1. [ ] 2. [ ] 3. [ ] 4. [ ] 5. [ ] 6. [ ] 7. [ ]
- P2: 1. [ ] 2. [ ] 3. [ ] 4. [ ] 5. [ ] 6. [ ] 7. [ ]
- P3: build [ ] full suite [ ] mutation pass [ ]
- P4: docs [ ] review [ ]

## Assumption Log

- Plan 82 and this plan both touch `WatchMenuView.swift` (82: Finish haptic, `:204-217`; 84: `rowLabel`, `:148-164`). They never run in parallel; 82 builds first. The two edit different functions, so a merge is mechanical.
- "Hour" in the duration helper is included although a rest rarely lasts one: the elapsed clock on the logging screen can (10 h ceiling, plan 39).
- `.updatesFrequently`/`.isSelected`/`.isHeader` have no in-repo precedent; SwiftUI documents them for watchOS versions below 9, and P3's `xcodebuild` is the compiler check.
- The Crown container's `accessibilityValue` is asserted as a source guard only; how VoiceOver announces it while the crown rotates is a device QA item for the lead's list.
- `dimmedRestClock` renders rounded "N min" while the new value speaks exact seconds — an accepted precision difference, not a bug.
- The suite is assumed green at base `56c3e56`; the architect ran no checks (checks belong to the builders/prover/lead).
- `docs/state_management/watch_surface_wrist.md` is ~50.7 KB against the 52 KB ceiling; P4 keeps the paragraph short or splits the file (governor call).

## Architect notes (seed corrections, made in place)

- N-1 The seeded hint `.accessibilityHint(labels.next)` cannot compile: `labels` is a local of the `TimelineView` closure (`WatchRestView.swift:62`), out of scope in `nextButton`. Corrected to `state.restLabels.next`, the expression `nextButton` already reads at `:104`.
- N-2 The seeded `.accessibilityValue(WatchSpokenText.duration(seconds: <the elapsed whole seconds the view already computes>))` is realised inline as `state.restElapsedSeconds() ?? 0`; `elapsed` itself is pinned verbatim by S-9109 and must not be refactored.
- N-3 The seeded "the highest value comes from ... `state.highestLabel`" is wrong: `highestLabel` is the caption "Max effort"; the numeric max is `WatchEffortRatingCopy.highest` = 5 (`WatchEffortRating.swift:31`).
- N-4 The ratchet must count comment-stripped, dot-prefixed `.accessibility`: bare "accessibility" also matches the comment in `WatchAccent.swift:12`. Today's count is 4 files with real modifiers.
- N-5 The "Exercises" guard is `WatchLoggedHapticTests.swift:207-215` (S-7805), a raw count of 2 in `ios/OmniTrain Watch App/ContentView.swift`; the seeded `grep -rn "Exercises" Tests/.../*Source*` hint finds nothing.
- N-6 The owner-sees row "Duration, 32 min" named no real row: the summary row is `WatchWorkoutSummaryCopy.time` = "Time" with `durationText` "m:ss" → "Time, 32:00".
- N-7 Seed line numbers corrected against direct reads: `nextButton` `:101-114` (was `:101-111`), `rowLabel` `:148-164` (was `:148-165`), summary rows `:38-45` (was `:38-42`), Crown call `:59-70` (seed said `:60-70`), rating root chain ends `:72` (was `:73`).

## Open questions

- Trait availability (`.updatesFrequently`, `.isSelected`, `.isHeader`) is not verifiable off-device in this run; P3's `xcodebuild` is the check. If the compiler rejects one, the guard drops that trait and the governor re-scopes the scenario.
- How VoiceOver orders the combined menu row ("name, count") and how the Crown container's value is announced mid-rotation are device behaviours; they go on the lead's QA list, not into source guards.
- The architect ran no gateway checks, so the `swift test` baseline at `56c3e56` is assumed green (the builders see the real baseline first).

## Feedback

- Review file reserved: `docs/plans/2026-10-26-84-wrist-accessibility-plan/2026-10-26-84-wrist-accessibility-plan.review.md` (not created; `crew-reviewer` writes it).
- Evidence file: `2026-10-26-84-wrist-accessibility-plan.evidence.md` (same folder).
