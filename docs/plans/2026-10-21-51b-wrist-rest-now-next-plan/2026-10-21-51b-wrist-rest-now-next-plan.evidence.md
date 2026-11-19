# Evidence — plan 51b (the rest screen says what you just did and what comes next)

## Scenario-to-test table

| Scenario | Test (`watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift`) |
|---|---|
| S-7601 planned set counts the logged sets | `testS7601APlannedSetCountsTheLoggedSets` |
| S-7602 plan done names the later exercise | `testS7602ACompletePlanNamesTheLaterExercise` |
| S-7603 forward search first, then from the top | `testS7603TheForwardSearchWinsThenTheBackwardOne` |
| S-7603c a plan exactly logged is skipped | `testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped` |
| S-7604 everything done | `testS7604EverythingDoneSaysNothingPlannedNext` |
| S-7605 free set with no plan | `testS7605AFreeSetCountsPastThePlan` |
| S-7606 rest after a jump, nothing logged | `testS7606AJumpedToExerciseWithNothingLogged` |
| S-7607 round effort names the next period | `testS7607ARoundEffortNamesTheNextPeriod` |
| S-7608 timed effort names the next exercise with work | `testS7608ATimedEffortNamesTheNextExerciseWithWork` |
| S-7609 through the engine, the phone's set counts | `testS7609ThroughTheEngineThePhonesSetCounts` |
| S-7610 the view reads the labels | `testS7610TheRestViewReadsTheLabels` |
| S-7611 only set entries count as sets | `testS7611OnlySetEntriesCountAsSets` |

## Measured results

- Full `swift test`: 711 tests, 0 failures (701 before; 10 new at first, then two
  more added in a fix round for two mutants the lead found unguarded — 12 in the
  new file).
- The lead's mutation pass over `deriveRestLabels`: 11 mutants (partial-plan
  boundary, backward-first search, no backward search, strict "done", unplanned
  counted as done, next label without plan suffix, unplanned next number, round
  branch off, now line without count, nothing-planned copy, counting all entries
  as sets). 9 were caught at once; the strict-done and all-entries-as-sets
  mutants were caught after two tests were added (S-7603c, S-7611). Every file
  restored byte-for-byte.
- The watch app target builds with `xcodebuild` (`WatchRestView` compiled; only
  the phone Runner target fails on a missing pod module, as before).
- NOT verified: how the two new lines look on the 40 mm screen (the Simulator
  was blocked by a Health permission dialog) — an owner check.
