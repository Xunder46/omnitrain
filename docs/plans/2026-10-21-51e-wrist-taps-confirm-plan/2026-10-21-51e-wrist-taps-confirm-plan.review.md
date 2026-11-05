# Review: 2026-10-21-51e-wrist-taps-confirm-plan · wrist taps confirm a log, list-button label · working tree (uncommitted)
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: 727 passed / 0 failed (governor-run, per brief; full suite not re-run per brief)
Diff vs Predicted Files: conforms — the 5 named sources, the new `WatchLoggedHapticTests.swift`, and `docs/state_management/watch_surface_wrist.md`; nothing outside.
## Findings

None.

## Assumption Log rulings

No Assumption Log entries in the plan; nothing to rule on.

## Scenario coverage

- S-7801 -> `WatchLoggedHapticTests.testS7801ASetPlaysOneTapPerLoggedSet` (asserts 1 tap, then 2 after the clock advance; also asserts `nexts == 0`).
- S-7802 -> `…testS7802ATimedEffortStartsSilentlyAndLogsOnTheSecondTap` (Start arm genuine: the slot has no declared kind, so `WatchEffortKind.resolved(["time","distance"])` resolves `timed` via `fromMetric`, `WatchLoggingState.swift:63-78`; had it resolved to `set`, the first tap would have logged and the first assert would fail — the test cannot pass for the wrong reason).
- S-7803 -> `…testS7803LogPlaysTheTap`.
- S-7804 -> `…testS7804ARefusedLogPlaysNothing` (arrangement genuinely throws: a session created with no exercises leaves `slot` nil, so `WatchLoggingState.log()` throws `malformed("no exercise is in progress…")` at `WatchLoggingState.swift:803-806`; both entries asserted silent).
- S-7805 -> `…testS7805TheSurfacesPlayTheTapsAndNameTheListButton` (guards match surviving code after comment stripping, trailing `//` prose blanked too; the `playLogged`/`playNext` body guards bound the match to within 120 chars of the declaration).

## Brief questions

1. No path plays for an unrecorded log or twice for one log. `primaryAction()` is called only from `WatchLoggingView.primaryButton` (`WatchLoggingView.swift:345`), once per tap; `WatchLoggingModel.log()`'s only production caller is the nutrition surface, which goes through `WatchNutritionModel.log()`, not the logging model. Both model entries guard on `(try? await state.log()) != nil`, and `state.log()` returns a non-optional record or throws, so non-nil means recorded. Tests call `state.log()`/`surface.log()` directly and assert no haptic counts, so no interference.
2. No finding. `WatchRestView` holds its own `haptics` (default `WristHaptics()`, `WatchRestView.swift:46`), the `Task` captures it strongly, `state.endRest()` is non-throwing (`WatchLoggingState.swift:360`), and `WKInterfaceDevice.play` is device-level, so a removed view still plays exactly once before `onNext()`.
3. The guard is right: `WatchNutritionModel.log()` is `@discardableResult async -> WatchObservationRecord?` (`WatchNutritionView.swift:71`), nil when `state.logSelected()` throws (`WatchNutritionState.swift:222-224`, e.g. `nothingSelected`). `import WatchKit` conflicts with nothing in the file (SwiftUI + WatchKit only; `WKInterfaceDevice` is unambiguous).
4. Yes: the only conformers in `watch/` and `ios/` are `WristHaptics` and `RecordingHaptics`, both updated; no conformer exists in `ios/`.
5. No test passes for the wrong reason (see Scenario coverage for S-7802/S-7804/S-7805 reasoning).

Owner checks (feel of the taps, VoiceOver) remain with the owner per the brief; not verifiable here.
