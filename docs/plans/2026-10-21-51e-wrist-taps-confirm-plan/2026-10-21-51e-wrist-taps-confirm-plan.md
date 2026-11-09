# Feature: 51e — the wrist taps to confirm a log, and VoiceOver names the list button

> Status: SEEDED 2026-10-21 (re-audit findings "no haptic on Log, Next, food log" and "the icon-only menu button has no accessibility label"; owner, in chat: "just keep going with what we agreed on"). Not built. Base commit: `.work/2026-10-21-51e/base.txt`. Team: the crew. Series list: `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 51e |
|---|---|---|
| Log a set, a timed effort, a hold or a period on the watch | the screen swaps to rest, nothing in the hand | one success tap when the log was recorded |
| Press Start on a timed effort | the clock starts | unchanged: no tap (starting is not logging) |
| Press Next on the rest screen | the logging screen returns | one light directional tap |
| Log a food on the watch | a small text line | the line plus one success tap |
| A log that is refused (nothing to log against) | nothing | still nothing (no tap) |
| VoiceOver on the list button (top right, logging and rest screens) | reads the symbol name | reads "Exercises" |

Unchanged: the countdown haptic (still one alert for every countdown end), the rest ping, the failure tap of a refused swipe, every wire message, the phone.

## Decision Ledger

- D-1 `WatchHaptics` (protocol, `WatchLoggingModel.swift:~229`) gains two requirements: `func playLogged()` and `func playNext()`. `RecordingHaptics` (same file) counts them (`public private(set) var logged = 0`, `nexts = 0`). `WristHaptics` (`WatchLoggingView.swift:~32`) plays `.success` for `playLogged()` and `.directionUp` for `playNext()`. The only conformers in the package and its tests are those two (grep `WatchHaptics`, `RecordingHaptics`).
- D-2 `WatchLoggingModel.primaryAction()` (`:170`) and `WatchLoggingModel.log()` (`:203`) call `haptics.playLogged()` only when `state.log()` returned a record (a thrown error plays nothing); `startWork` branch plays nothing.
- D-3 Views (exact text in the brief): `WatchRestView` Next button calls `haptics.playNext()` after ending the rest; `WatchNutritionView`'s Log button plays `.success` through `WKInterfaceDevice` when `model.log()` returned a record; `ContentView.swift`'s two list buttons (rest and logging toolbars) get `.accessibilityLabel("Exercises")`.
- D-4 Not in scope: distinct countdown haptics per milestone (every milestone is the same kind of event: a countdown ended), a haptic on Finish or on the failures of 51d/51e later, Always-On, a11y of the tiles (51a labelled them), the phone.

## Readers listed

- `WatchHaptics` conformers: `RecordingHaptics`, `WristHaptics` only (grep `: WatchHaptics`, `WatchHaptics` in `watch/watchos` and `ios/OmniTrain Watch App`). `RecordingHaptics()` callers (tests) use the no-argument init, unchanged.
- `WatchLoggingModel.primaryAction`/`log` callers: `WatchLoggingView` (`primaryButton`), `WatchTimedWorkTests` and others (the model's behaviour is unchanged apart from the haptic).
- Scenario ids S-7801..S-7805 checked free.

## Core scenarios

`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggedHapticTests.swift` (new; harness copied from `WatchCrownUnitTests.swift`'s `benchModel` with a `RecordingHaptics` kept in a local):
- S-7801 a set: `primaryAction()` -> `haptics.logged == 1`; a second `primaryAction()` -> 2 (the first log starts a rest, so check the count after each).
- S-7802 a timed effort awaiting start (a cardio slot, `capabilities ["time","distance"]`, `effortKind` timed): `primaryAction()` starts the clock -> `logged == 0`; the next `primaryAction()` logs -> `logged == 1`.
- S-7803 `model.log()` (the other entry) -> `logged == 1`.
- S-7804 a refused log plays nothing: arrange a model whose `state.log()` throws (read `WatchLoggingState.log()` for the throw; e.g. a session with no exercise); `primaryAction()` -> `logged == 0` and no crash. If no throwing arrangement exists in two attempts, report and say so (the positive arms stay).
- S-7805 source guards (comment lines stripped): `WatchRestView.swift` calls `haptics.playNext()`; `WatchNutritionView.swift` plays `.success` guarded by the record; `WatchLoggingView.swift`'s `WristHaptics` maps `playLogged` to `.success` and `playNext` to `.directionUp`; `ContentView.swift` carries `.accessibilityLabel("Exercises")` exactly twice.

## Phases

- P1 (`crew-builder-watch`, glm, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift,watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift,watch/watchos/Sources/WatchSessionEngine/WatchNutritionView.swift,ios/OmniTrain Watch App/ContentView.swift,.work/crew/2026-10-21-51e/**"`): D-1..D-3 as exact text. The lead builds the watch target.
- P2 (same builder, after P1, tests only): S-7801..S-7805.
- P3 docs keeper: `docs/state_management/watch_surface_wrist.md` (the taps and the label), evidence file. Lead: full `swift test`, `xcodebuild`, analyze, docs tests, full `flutter test` once, mutations (log arm, start arm, other entry, refused arm, view maps), reviewer, commit.

## Owner checks (owner)

- (owner) Log a set: one firm tap; Next: a lighter, different tap; log a food: a tap; Start on a timed effort: none. Turn VoiceOver on: the list button reads "Exercises".

## Scope budget

About 40 production lines, about 110 of test, docs about 10. One track, three phases.
