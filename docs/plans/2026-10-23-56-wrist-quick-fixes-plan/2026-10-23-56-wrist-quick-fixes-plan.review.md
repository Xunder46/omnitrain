# Review: plans 56 + 57 (wrist quick fixes; cancel empty Free workout) · all phases · 1e339a6b..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 3 · tests: governor-run (Swift 802 passed / 0 failed, watch-app xcodebuild succeeded, doc contract 42 passed) — not rerun per brief
Diff vs Predicted Files: conforms (all 15 files are the plans' scopes plus the two docs; nothing outside)

## Findings

1. [Minor] `watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift:42` and `:178` — the two doc comments still tell the reader to render the accent "through `WatchAccent.usable(hex:)`" and that "a wrist wears an accent only when this parses and clears the contrast floor". After plan 56 D-1 the wrist wears the fallback when `usable` is nil, so a maintainer following either comment re-introduces the grey look the change removes. Fix: reword both comments to `WatchAccent.worn(hex:)` (comment-only). Guard: none needed (comment-only); the wiring itself is held by `WatchAccentTests.testS8604ContentViewWearsWornAndTheAssetCarriesTheColor`.
2. [Minor] `docs/watch-app-setup-and-qa.md:866` (step 20) — "the phone's Home shows no live watch session (`WatchCancelEmptyFreeWorkoutTests` S-8701..S-8706)": those tests assert only the wrist's engine state (status `abandoned`, a fresh start after it); none of them asserts anything about the phone. The phone-side claim is real and already held by `test/watch_session_import_test.dart` S-265 ("an abandoned session creates no history", l.679-698), which the sentence does not name. Fix: cite S-265 next to the wrist tests in that clause.
3. [Minor] `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift:202-206` (`cancelIfNothingPicked`) — in the pick flow itself there is no bad ordering: `WatchExercisePickerView.select` (l.283-287) awaits `paths.selectExercise` → `addExerciseToSession` → `engine.insertExercise` (the exercise is in the session before it returns, `WatchSessionEngine.swift:406-435`) and only then runs `onExerciseAdded`, whose closure sets `pickingExercise = false`; the dismissal — and so `onDismiss` — strictly follows the write, so the dismiss Task always sees a non-empty session. The one ordering that can abandon a just-picked session is a swipe-down dismissal landing while the pick's `selectExercise` is still in flight: the dismiss Task then reads an active empty session and abandons it, and `insertExercise` (whose `requireSession`, `WatchSessionEngine.swift:2065-2072`, checks only nil, not status) writes the exercise into the abandoned session, leaving the user on the logging screen of an abandoned session. It needs a swipe and a tap in the same instant. Fix (smallest): a pick-in-flight flag set in `select`'s Task and read by `cancelIfNothingPicked`. Guard: a test that starts a pick and dismisses before the insert resolves would fail without it.

## Assumption Log rulings

- 56 D-1, D-2, D-3 (fallback hex, `worn`, `defaultValue`, colorset): ratify — implemented as written; S-8601..S-8604 hold them.
- 56 D-4 (Crown sign + helper, keeping the "hand back near zero" bookkeeping): ratify. The returned position is `position − detents·ppd`, the same bookkeeping the old code had (`points + whole·ppd` under the flipped sign); the tests pin it (S-8611..S-8615). The food Crown could not be driven on the simulator (no foods synced): the direction check stays an owner check — ratify as owner check (QA step 20).
- 56 D-5 (rest clock scale): ratify; the governor measured the 40 mm layout.
- 57 D-1..D-3 (guard-only cancel, `onDismiss`, host callback): ratify; the guard is the whole safety and S-8703/S-8704/S-8705 hold each arm. D-4 (HealthKit lifecycle on abandon, no in-picker Cancel) stays out of scope as written.

## Question answers (brief items 1-5)

1. No wrong detent count found. `pointsPerDetent = 1` (`WatchMetricStepping.swift:56`) and the nutrition Crown's range is ±20 detents (`WatchNutritionView.swift:164,205-206`), so `travel ∈ [−40, 40]` and `travel * 1e9 ≤ 4e10` — far from overflow, and `.rounded()` at that magnitude is exact for the dust sizes involved (a carried 1.4 − 0.4 arrives one ulp short and snaps to 1.0, the intended case). Negative travel mirrors positive (`towardZero` on −1.4 gives −1). The returned `position` is computed from the same `whole` that is reported, so it is consistent with the detents by construction. The only failure mode is `|travel| > ~1.8e299` (scaled value overflows to infinity, `Int(whole)` traps), unreachable from the bounded Crown range.
2. No bad ordering in the pick flow (see finding 3 for the narrow concurrent-swipe case): the exercise is written and awaited before `pickingExercise = false`, so the dismissal's Task cannot observe an empty session after a pick.
3. No. Every `WatchAccent.usable(hex:)` call site in `Sources` is now only the definition (`WatchAccent.swift:65`) and `worn` itself (`:87`); the app target's only resolution is `ContentView.swift:403` through `worn`. The remaining readers of the environment are `WatchProminentModifier` (`WatchAccentStyle.swift:61`) and the armed-row outline (`WatchLoggingView.swift:254`, `accent?.color ?? Color.white` — now cyan before the first sync, which D-2 states is intended). No call site still produces the grey/default look. Only the two prose comments in `WatchPhonePreferences.swift` still describe the old rule (finding 1).
4. Yes. S-8603 is one test iterating all six contract rows, asserting each is worn as itself and — for the five rows that are not the fallback — not the fallback (kills the always-cyan mutant). S-8705 has both arms as separate tests (`testS8705ACompletedSessionIsNotCancelled`, `testS8705WithNoSessionAtAllCancelIsFalse`). None of the new source-text guards passes vacuously: each asserted or forbidden string was checked against the real files (S-8604's worn line and no-`usable` claim, S-8616's helper call / `stepPortion(step.detents)` / no `-(` in the collected body — the old body's `-(points - crownPosition)` would fail it, S-8621's chains read the single `Text(elapsed)` at `WatchRestView.swift:72` and `Text(readout)` at `WatchLoggingView.swift:129`, S-8706's four strings match the code verbatim), and every guard would fail on the pre-change source.
5. One clause (finding 2). Every test name the two docs cite was checked against the diff and exists: the seven `WatchCancelEmptyFreeWorkoutTests` names, `testS8621TheRestClockMatchesTheWorkReadoutsScale`, `WatchPortionCrownTests` S-8611..S-8616, `testS8601`–`testS8604`, and the pre-existing S-3712/S-3713/S-3714 citations. `WatchNutritionPortion.stepServings` exists (`WatchNutritionState.swift:31`).

## Scenario coverage

- S-8601 → `WatchAccentTests.testS8601WornWithNoHexIsThePhoneDefaultThemeAccent` | covered
- S-8602 → `WatchAccentTests.testS8602UnusableOrMalformedHexWearsTheFallback` | covered
- S-8603 → `WatchAccentTests.testS8603EveryContractThemeIsWornAsItselfNotTheFallback` | covered
- S-8604 → `WatchAccentTests.testS8604ContentViewWearsWornAndTheAssetCarriesTheColor` | covered
- S-8611..S-8615 → `WatchPortionCrownTests.testS8611…`–`testS8615…` | covered
- S-8616 → `WatchPortionCrownTests.testS8616TheModelTurnsThroughTheHelper` | covered
- S-8621 → `WatchRestSurfaceTests.testS8621TheRestClockMatchesTheWorkReadoutsScale` | covered
- S-8701 → `WatchCancelEmptyFreeWorkoutTests.testS8701CancellingAnEmptyFreeWorkoutAbandonsIt` | covered
- S-8702 → `…testS8702AFreshFreeWorkoutStartsAfterTheCancel` | covered
- S-8703 → `…testS8703ASessionWithAnExerciseIsNotCancelled` | covered
- S-8704 → `…testS8704ASessionHoldingAPushedSlotIsNotCancelled` | covered
- S-8705 → `…testS8705ACompletedSessionIsNotCancelled` + `…testS8705WithNoSessionAtAllCancelIsFalse` | covered
- S-8706 → `…testS8706ThePickerSheetCancelsOnDismissAndTheHostReReads` | covered
