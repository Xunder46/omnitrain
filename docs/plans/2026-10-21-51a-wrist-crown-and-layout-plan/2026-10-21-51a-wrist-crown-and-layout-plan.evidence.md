# Evidence — plan 51a (the Crown moves one step per click, the reps/weight screen fits)

Proof date: 2026-10-21 (lead: unit tests, mutation pass). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-7501 the Crown unit is one value unit per detent (logging and rating models) | `testS7501TheCrownUnitIsOneValueUnit` | `watch/watchos/Tests/WatchSessionEngineTests/WatchCrownUnitTests.swift` |
| S-7502 one value unit steps the reps by one; two more units are two more steps | `testS7502OneValueUnitStepsTheRepsByOne` | same file |
| S-7503 the first two value units pick the first two rating numbers | `testS7503TheFirstTwoValueUnitsPickTheFirstTwoNumbers` | same file |
| S-7504 the nutrition model borrows the constant, no literal | `testS7504NutritionDeclaresTheCrownUnitWithoutALiteral` | same file |
| S-7505 the three Crown sites pass the constant, never a digit literal | `testS7505TheCrownSitesPassTheUnitConstant` | same file |
| S-7511 `stepArmed` steps the armed row by its own step, not the other row | `testS7511StepArmedStepsTheArmedRowByItsOwnStep` | `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingStatusTests.swift` |
| S-7512 `stepArmed` with no rows, and with a sensor-kept value, changes nothing | `testS7512StepArmedWithNoRowsChangesNothing`, `testS7512StepArmedLeavesASensorKeptValueAlone` | same file |
| S-7513 the status line: caption + beat, caption alone, beat alone, nil | `testS7513TheStatusLineJoinsTheCaptionAndTheBeat`, `testS7513TheStatusLineIsTheCaptionAloneWithoutSensors`, `testS7513TheStatusLineIsTheBeatAloneWithoutAPlan`, `testS7513TheStatusLineIsNilWithNeitherCaptionNorSensors` | same file |
| S-7514 the view renders the shared pair and the status line, no bordered style | `testS7514TheLoggingViewRendersTheSharedStepperAndTheStatusLine` | same file |

Count: 13 new tests (`WatchCrownUnitTests` 5, `WatchLoggingStatusTests` 8).

## Verified

- `swift test`, full watch package: 701 tests, 0 failures (lead, 2026-10-21).
- The lead's mutations, each red then restored byte-for-byte: the constant back to 32 (S-7501, S-7502, S-7503 fail); `stepArmed` ignoring the armed row (S-7511 fails on the weight arm); the status line dropping the sensor half (S-7513, two cases fail); dropping the caption half (two cases fail); the bordered style back (S-7514 fails); the plus button bypassing `stepArmed` (S-7514 fails).
- The watch app target builds with `xcodebuild` (WatchLoggingView compiled); only the phone Runner target fails on a missing pod module, as before this plan.

## Not verified

- How a Crown click feels (the rotation one step needs) on a real watch: owner check — the simulator has no Crown.
- The 40 mm position of Log: owner check — the Simulator was blocked by a Health permission dialog.

## Docs

- `docs/state_management/watch_surface_wrist.md`: the Crown unit is one value unit per detent (new paragraph, citing S-7501..S-7505); the two-tile layout with the shared − / + pair, the 32-point capsules and the one status line (citing S-7511..S-7514); the Crown feel and the 40 mm position of Log named as device checks, not package tests.
