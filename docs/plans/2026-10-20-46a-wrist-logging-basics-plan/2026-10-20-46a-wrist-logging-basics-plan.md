# Feature: 46a — the Crown turns the highlighted value; the logging screen fits a 40 mm watch; each exercise keeps its own numbers

> Status: BUILT, PROVED AND REVIEWED 2026-10-20 (review APPROVE WITH FIXES, both fixes applied: S-6415 and the CRLF restore). Swift package 645/0, full flutter +5322 ~2 (before fix-2; the Dart watch files and docs contract tests re-run green after it, +102). Crown on a real watch is still an owner check. Evidence beside this file. Base commit: `.work/2026-10-20-46a/base.txt` (claude_develop, clean tree). Team: the crew (seeded by the lead; architect step skipped, as 43c).
> Series: `docs/plans/2026-10-20-46-wrist-logging-series.md` (owner decisions O-1..O-4 apply here).
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Evidence: `<plan>.evidence.md` beside this file. Scout sheets: `.work/crew/2026-10-20-45-watch-ux/scout-nav.md`, `scout-ladder.md`.

## Goal and acceptance

| What you do on the watch | Now | After 46a |
|---|---|---|
| Open the logging screen on a set (reps, weight) and turn the Crown | nothing happens (owner's watch) | the first row (Reps) is outlined; each Crown tick moves it by its step |
| Tap the Weight row (or its − / +) and turn the Crown | nothing | the outline moves to Weight; the Crown steps Weight |
| A row a sensor keeps (measured distance) | inert | cannot be outlined; the Crown steps the next row, or nothing if none |
| Look at the screen on a 40 mm watch | Log button cut by the screen edge; name under the menu button | Log fully visible; the name sits in the title area beside the menu button; − / + are smaller |
| Dial 60 kg on bench, open squat via the menu | squat shows 60 kg | squat shows its own starting weight; bench still 60 kg when you come back |
| Log a set on squat after dialling both | clears every dialled number | clears squat's only |

## Decision Ledger

- D-1 One Crown binding per surface (not per row). `WatchLoggingModel` (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift`): replace `crownPositions: [String: Double]` and `carry: [String: Double]` with `crownPoint: Double` and `carry: Double`; add `armedKey: String?`, `public var armedMetricKey: String?` = `armedKey` when that key is a non-measured field of `state.fields`, else the first non-measured field's key, else nil; `public func arm(_ metricKey: String)` ignores a key that is not a non-measured field, sets `armedKey`, zeroes `carry` and leaves `crownPoint` alone (the Crown reports an absolute position, so the position must stay continuous across arming or the next event would step by the whole difference); `public func turn(to position: Double)` replaces `turn(_:to:)`: `moved = position - crownPoint; crownPoint = position; carry += moved; detents = (carry / pointsPerDetent).rounded(.towardZero); carry -= detents * pointsPerDetent; guard detents != 0, let key = armedMetricKey else { return }; state.adjust(key, detents: detents); poll()`. `crownPosition(for:)` becomes `public var crownPosition: Double`. Why continuous: SwiftUI's `digitalCrownRotation(detent:)` writes the absolute position into the binding.
- D-2 View (`WatchLoggingView.swift`): remove the per-row `.focusable(!field.isMeasured)` and `.digitalCrownRotation`; on the surface container add `.focusable(true)`, `.focused($crownFocused)` (`@FocusState private var crownFocused: Bool`) and ONE `.digitalCrownRotation(detent: Binding(get: { model.crownPosition }, set: { model.turn(to: $0) }), from: -pointsPerDetent * crownRangeDetents, through: pointsPerDetent * crownRangeDetents, by: pointsPerDetent, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)`; `crownFocused = true` in `onAppear`, on the foreground notification (the package targets watchOS 9, where the two-argument `onChange` does not exist) and after any row tap/step. Repro (lead, 2026-10-20, Apple Watch SE 3 40 mm simulator, seeded session, Crown = scroll over the crown graphic; the same scroll DID scroll the Exercises menu list): on the logging screen the Crown scroll left Reps at 10, also after tapping the Reps value; the + button took it to 11. So the Crown binding never receives rotation. Why (cause suspected, not proven): each row owned its own focusable view, nothing took initial focus and a tap on a Text does not give focus, so no binding ever received the Crown (the fix is proven on the simulator by the same scroll, then confirmed on the owner's watch, see Owner checks). Row look: the armed row gets a `RoundedRectangle` stroke in `@Environment(\.watchAccent)` color (2 pt); a tap on the row's value area, or on its − / +, calls `model.arm(key)` first.
- D-3 Layout (40 mm = 162 x 197 pt; measured with the seeded simulator, screenshots `watch-log1.png`): the exercise name stays header text (one line, `minimumScaleFactor(0.7)`) pushed below the menu button by `titleClearance` = 14 pt (a first try with `.navigationTitle` showed a scrolling marquee cut by the button on the simulator and was dropped); − / + buttons get `.frame(width: 36, height: 36)` and a `.font(.caption)` image; the unit label sits on the value's baseline (`HStack(alignment: .firstTextBaseline)` of `Text(value).font(.title3).bold()` and `Text(unit).font(.caption2)`) instead of a third line. The set caption, round line, countdown and sensor line stay in the header. The lead checks the result on the 40 mm simulator (seeded store) before reporting; no unit test can see a layout.
- D-4 Per-exercise dialled numbers (`WatchLoggingState.swift`): `dialled: [String: [String: Double]]` keyed by `sessionExerciseId` (`""` when no slot), then metric key. Readers/writers today (all in this file): the declaration ~:179, `field(for:)` ~:568 read, `adjust` ~:760 write, `log()` ~:813 `dialled.removeAll()` -> `dialled[currentSlotKey] = nil`. `roundLengthOverrideSecs` is untouched.
- D-5 Dart mirror parity (`lib/watch/logging/watch_logging_state.dart`: `_dialled` ~:153, read ~:402, write ~:586, `.clear()` ~:636): the same per-slot rule, so the mirror's tests and docs ("mirrored file for file") stay true. The Dart watch client has no Crown, so D-1..D-3 do not apply to it.
- D-6 Out of scope: the pager (46b), the main-actor hop and engine serialisation (46c), any wire or phone change, `WatchNutritionView`/`WatchEffortRatingView` Crown code (they are `focusable(true)` single-view screens), always-on display.

## Readers listed (grep done 2026-10-20)

- `turn(_:to:)` / `crownPosition(for:)`: only `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift:509,515` (`testCrownTurnsAccumulateIntoWholeDetents`); no Dart or doc caller of the Swift signatures.
- Source scans of the view text: `test/watch_logging_surfaces_test.dart:976` (banned-framing string scan of `WatchLoggingView.swift`; new strings must stay neutral); `test/rest_is_count_up_contract_test.dart` and `WatchMenuTests.swift:1018`, `WatchSensorSourceSourceTests.swift:57` read `ContentView.swift` (46a does not touch it).
- `dialled` readers: only inside `WatchLoggingState.swift` and `watch_logging_state.dart` (grep). Tests asserting dial/carry: `WatchTimedWorkTests` (S3406 round-length rule, must stay green), `WatchPlannedSetsTests`, `WatchLoggingSurfacesTests`.

## Core scenarios (ids S-6401.. checked free in lib, test, docs, watch)

Swift model, new `WatchCrownArmingTests.swift` (plain async tests, `@MainActor`, harness as `WatchLoggingTimersTests` `testCrownTurnsAccumulateIntoWholeDetents`: bench set, reps 10, weight 0):
- S-6401 fresh model: `armedMetricKey == reps`; `turn(to: 32)` -> reps 11, weight unchanged. (Fails without: no armed key exists.)
- S-6402 `arm(weight)`; `turn(to: 32)` -> weight up by one weight step, reps unchanged.
- S-6403 position is continuous: `turn(to: 32)` (reps 11), `arm(weight)`, `turn(to: 64)` -> weight +1 step (not +2 steps); then `turn(to: 32)` -> weight back.
- S-6404 carry is dropped on arming: `turn(to: 16)` (half a detent on reps), `arm(weight)`, `turn(to: 32)` -> weight unchanged (16 + 16 would have stepped it if carry survived); a further `turn(to: 48)` steps weight once.
- S-6405 measured row: distance exercise with a sensor keeping distance: `arm(distance)` does nothing; `armedMetricKey` is the first non-measured field; with every field measured `turn(to:)` changes nothing and does not crash.
- S-6406 exercise change: arm weight on bench, `engine.selectExercise` to a bodyweight exercise with no weight row: `armedMetricKey` falls back to reps; selecting back finds weight armed again (armedKey is kept, validity is re-checked per read).
- S-6407 the existing crown-accumulation test, rewritten to `turn(to:)`: half a detent moves nothing, the next tops it to 11.
Per-exercise numbers, new `WatchDialledPerExerciseTests.swift` (Swift) and `test/watch_dialled_per_exercise_test.dart` (Dart mirror, groups Mock/Hive not needed: the state is in-memory; plain `test()`):
- S-6410 dial reps +4 on sx-bench (14), jump to sx-squat: squat reps = its initial value (10); jump back: bench reps still 14.
- S-6411 dial both, log on squat: squat's dialled gone (field back to the logged observation's value / initial), bench's 14 stays.
- S-6412 weight dialled on bench does not appear on squat (the bug as reported), using a value unlike every default (62.5 kg-equivalent canonical value).
- S-6413 no-slot session (free workout before the first exercise): `adjust` and `fields` do not crash; `""` key.
- S-6414 round-length override rule (S3406) still passes unchanged (run, do not rewrite).

## Phases

| Phase | Agent | Items | Write scope | Parallel |
|---|---|---|---|---|
| P1 model: D-1, D-4 + S-6401..6407, 6410..6413 (Swift) | crew-builder-watch | 6 | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift`, `.../WatchLoggingState.swift`, `watch/watchos/Tests/**` | with P3 (disjoint) |
| P3 mirror: D-5 + S-6410..6413 (Dart) | crew-builder-watch | 3 | `lib/watch/logging/watch_logging_state.dart`, `test/watch_dialled_per_exercise_test.dart` | with P1 |
| P2 view: D-2, D-3 (exact code in the brief; lead screenshots the 40 mm simulator) | crew-builder-watch | 4 | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` | after P1 |
| P4 docs | crew-docs-keeper | 2 | `docs/**` | after P2 |
Then prover (mutations by the lead's script), reviewer, fix rounds <= 3. Builders: never run the full `flutter test`; Swift Done list includes `swift test --filter WatchSessionEngineTests` (append-only source guard) and the sibling files `WatchTimedWorkTests`, `WatchPlannedSetsTests`, `WatchLoggingSurfacesTests`, `WatchLoggingTimersTests`.

## Owner checks (owner)

- (owner) On the real watch: open a set exercise, turn the Crown without touching the screen: Reps changes with a tick; tap Weight: the outline moves and the Crown changes Weight. If the Crown still does nothing the cause is not focus and the plan reopens.
- (owner) 40 mm and 46/49 mm watches: Log button fully visible, name and menu button do not overlap.
