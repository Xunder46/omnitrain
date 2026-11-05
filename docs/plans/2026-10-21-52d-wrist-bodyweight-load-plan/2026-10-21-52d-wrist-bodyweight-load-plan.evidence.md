# Evidence — plan 52d (a push-up or an ab wheel rollout has a weight row on the watch, like the phone)

## Scenario-to-test table

| Scenario | Test (`watch/watchos/Tests/WatchSessionEngineTests/WatchBodyweightLoadTests.swift`) |
|---|---|
| S-8101 a set effort offers reps and weight whatever the exercise's capabilities: a push-up offers the added weight, a hold keeps only its extra-weight row, a timed effort has no row the user dials | `testS8101ASetEffortOffersRepsAndWeightAHoldItsExtraWeightATimedEffortNothing` |
| S-8102 a dialled weight is logged as the set's `loadKg` and a weight left at 0 sends none | `testS8102ADialledWeightIsLoggedAsLoadKgAndAZeroWeightSendsNone` |
| S-8103 an assist travels with its sign down to the wire's floor | `testS8103AnAssistTravelsWithItsSignDownToTheWireFloor` |
| S-8104 a planned row starts the weight tile at its own `loadKg`, not the set just logged | `testS8104APlannedRowStartsTheWeightTileAtItsOwnLoad` |
| S-8105 the next set starts at the weight just logged | `testS8105TheNextSetStartsAtTheWeightJustLogged` |

The four older tests that pinned "no weight row without load" now state the new
behaviour: `WatchCrownArmingTests.swift` S-6406
(`testS6406AnArmedRowIsReCheckedWhenTheExerciseChanges`),
`WatchLoggingSurfacesTests.swift` S-001
(`testS001ABodyweightSetOffersAWeightThatCarriesNoLoadAtZero`),
`WatchPagerFocusTests.swift` S-7911
(`testS7911TheFocusShowsTheFocusedExerciseAndLogsAgainstIt`) and S-7914
(`testS7914AFocusNamesASlotThatHasNoIdOfItsOwn`).

## Measured results

- Full `swift test` (run by the lead, see the plan): 744 tests, 0 failures.
- The lead's mutation pass: 5 mutants, all caught — the `weight`→`load`
  capability filter put back, the `loadKg` payload dropped, the
  `WatchMetricStepping.minimumLoadKg` clamp removed, the planned-row dial-in
  ignored, the carry-over off. Removing the (pre-existing) distance capability
  filter is an equivalent mutant: a timed effort has no dialled distance row.
- NOT verified on a real watch: the wrist half of plan 52c's owner check (a
  real push-up logged on a watch).
