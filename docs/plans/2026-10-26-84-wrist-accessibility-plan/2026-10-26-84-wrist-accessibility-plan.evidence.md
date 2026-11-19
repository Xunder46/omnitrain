# Evidence — plan 84 (wrist VoiceOver accessibility)

Architect run 2026-10-26. Base `56c3e56e3c6fb5b3d889010fae39e3bddfbf2dc7` (`.work/2026-10-26-84/base.txt`). Every claim below was read from a file this run; nothing is inferred.

## Accessibility usage today (brief 2a)

- Bare `accessibility` under `watch/watchos/Sources/WatchSessionEngine`: 5 files. `WatchAccent.swift:12` is a comment only.
- Real `.accessibility` modifiers: 4 files.
  - `WatchStartView.swift:182` — `.accessibilityElement(children: .combine)` (in-repo precedent, watchOS 9 target).
  - `WatchExerciseListView.swift:187` — `.accessibilityLabel`.
  - `WatchLoggingView.swift:282` — `.accessibilityAddTraits(.isButton)`; labels at `:283`, `:350`.
  - `WatchNutritionView.swift:226` — `.accessibilityLabel`.
- `.updatesFrequently`, `.isSelected`, `.isHeader`: no in-repo usage (not checked on device; P3 `xcodebuild` is the compiler check).

## Source-guard helpers (brief 2b)

`watch/watchos/Tests/WatchSessionEngineTests/WatchPagerSourceTests.swift`: `engineSource(_:)`, `strippingCommentLines(_:)`, `occurrences(of:in:)`, `propertyBody`.

Precedents read in full:
- `WatchRestSurfaceTests.swift` S-8621 — `modifierChain(of: "Text(elapsed)")` collects consecutive `.`-lines; appending modifiers keeps it green.
- `WatchRestPingWiringSourceTests.swift` S-9109 — pins `private var elapsed: String {` body verbatim (collapsed contains the dimmed/`clock` ternary). Do not refactor `elapsed`.
- `WatchRestAdvanceTests.swift` S-9109 — asserts `nextButton` closure statement order.
- `WatchWorkoutSummaryWiringSourceTests.swift` S-9620 — slices `WatchEffortRatingView` body from `public var body: some View {` to `private func scaleButton`, asserts regex `confirmButton\s+skipButton` (`:90-112`); whole-file `contains` on `WatchWorkoutSummaryView.swift`: title copy, `Text(row.label)`, `Text(row.value)`, Done button (`:113-133`).
- `WatchCrownUnitTests.swift` S-7505 — slices `digitalCrownRotation` → `isHapticFeedbackEnabled`.
- `WatchEffortRatingTests.swift` S-211 — banned-words scan over `Button("...")` / `label: { Text("...") }` patterns; skip-names scan.
- `WatchLoggedHapticTests.swift:207-215` (S-7805) — counts `.accessibilityLabel("Exercises")` == 2 in `ios/OmniTrain Watch App/ContentView.swift`, raw (no comment stripping).
- `WatchMenuTests.swift` S-1108/S-3617/S-3106/S-3104A — token-absence checks; no `rowLabel` slice.

## API availability (brief 2c)

`watch/watchos/Package.swift`: `platforms: [.macOS(.v13), .watchOS(.v9)]`. In-repo: `.accessibilityElement(children: .combine)`, `.accessibilityAddTraits`, `.accessibilityLabel` (see above). No `.font(.system(size:` anywhere under `Sources/WatchSessionEngine`.

## Duration helpers (brief 3)

No spoken-words helper exists. Digit-only formats: `WatchLoggingState.clock` "m:ss" (`:850-857`), `dimmedRestClock` "N min" (`:411-412`), `WatchWorkoutSummary.durationText` "m:ss"/"h:mm:ss" (`:98-105`). D-1's wording is new.

## Verified line numbers (base 56c3e56)

- `WatchRestView.swift`: body `:57`, `TimelineView` `:61`, `let labels = state.restLabels` `:62`, VStack `:63`, `Text(elapsed)` `:73` (chain `:74-77`), `Text(labels.next)` `:79`, nextButton usage `:85`, `elapsed` `:93-98`, `nextButton` `:101-114` (`nextSlotId` `:104`, label `:111`, `.watchProminent()` `:113`).
- `WatchMenuView.swift`: `rowButton` `:121-135`, `rowLabel` `:148-164` (VStack `:149`, `Text(row.name)` `:150`, count `:152-157`, `.multilineTextAlignment(.leading)` `:162`), `finishRow` `:203+`.
- `WatchWorkoutSummaryView.swift`: title `:34-36`, ForEach `:37`, row HStack `:38-44`, `.font(.footnote)` `:45`.
- `WatchEffortRatingView.swift`: body `:34-73`, VStack `:35-53`, `.padding` `:54`, `.focusable` `:55`, crown `:59-70`, nav `:71`, dismiss `:72`; `scaleButton` `:78-85`; `confirmButton` `:87-95` (`.watchProminent()` `:93`, `.disabled` `:94`); `skipButton` `:99-104`.
- `WatchEffortRating.swift`: `lowest` = 1 `:30`, `highest` = 5 `:31`, `selected: Int?` `:118`, `scale` `:220`.
- `WatchMenu.swift:44-45` — count label `"\(loggedCount) logged"`.
- `WatchLoggingState.swift:32` — `restCaption` = "Rest".

## Copy constants

`WatchWorkoutSummaryCopy.time` = "Time" → owner-sees row is "Time, 32:00" (not "Duration, 32 min").

## Docs ceiling

`docs/state_management/watch_surface_wrist.md` ≈ 50.7 KB (ceiling 52 KB); section starts at `:1, :17, :148, :191, :317, :715`.

## Plan 82 overlap

Plan 82's file edits `WatchMenuView.swift` `init` (`:65`) and `finishRow` (`:203-218`) — different functions from `rowLabel`; serial ordering kept.
