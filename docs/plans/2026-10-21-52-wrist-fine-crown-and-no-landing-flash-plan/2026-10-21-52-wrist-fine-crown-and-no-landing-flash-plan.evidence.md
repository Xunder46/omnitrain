# Evidence — plan 52 (the Crown is the fine control, the buttons the quick one; no card flashing on a swipe)

Proof date: 2026-10-21 (lead: unit tests, mutation pass). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-7901 the fine table: weight and extraWeight 1 kg (1 lb converted), duration and roundDuration 1 s, reps and rounds 1, distance = its quick step; the quick table untouched (weight 2.5, duration 5) | `testS7901TheFineStepTable` | `watch/watchos/Tests/WatchSessionEngineTests/WatchFineCrownTests.swift` |
| S-7902 a Crown click on a weight steps one kilogram (0 → 1.0, then 3.0 — a value no plate lands on); the − / + button still steps the plate (3.0 → 5.5) | `testS7902ACrownClickOnAWeightStepsOneKilogram` | same file |
| S-7903 a Crown click on a length steps one second (60 → 61) while the button steps five (61 → 66); a hold's time is its clock, not a dialled row | `testS7903ACrownClickOnALengthStepsOneSecond` | same file |
| S-7904 pounds: a Crown click moves the displayed weight by 1.0 ("1.0", "2.0"), the button by 5.0 ("7.0") | `testS7904ACrownClickOnAPoundWeightMovesTheDisplayByOne` | same file |
| S-7905 `WatchMetricField.fineStep` equals `fineStep(for:)` and defaults to `step` when not given | `testS7905AFieldWithoutAFineStepBorrowsItsStep` | same file |
| S-7911 the focus on the logging state: the focused slot's name, fields and log entries; nil and an unknown id fall back to the engine's current exercise | `testS7911TheFocusShowsTheFocusedExerciseAndLogsAgainstIt` | `watch/watchos/Tests/WatchSessionEngineTests/WatchPagerFocusTests.swift` |
| S-7912 `focusSlotId(for:)`: the engine's own page, an out-of-range index and a locked session give nil; another live page gives that row's slot id | `testS7912ThePagerNamesAFocusOnlyForAnotherLivePage`, `testS7912ALockedSessionFocusesNothing` | same file |
| S-7913 the view's wiring as source guards: the selection binding calls `focusSlotId(for:)`, the selected page renders the logger, `land` clears the focus on both branches, the counter reads the selection | `testS7913ThePagerViewWiresTheFocusThroughItsOwnBinding` | same file |
| S-7914 a slot the phone pushed without a `sessionExerciseId` of its own is reached through the id `WatchCatalogExercise(slot:).slotId` derives | `testS7914AFocusNamesASlotThatHasNoIdOfItsOwn` | same file |

The old Crown tests now read the fine step: `WatchCrownArmingTests.swift` reads
`field(model, WatchMetricKey.weight).fineStep` at its three step sites;
`WatchLoggingTimersTests` and `WatchCrownUnitTests` keep their Crown cases whose
value is unchanged (reps).

Count: 10 new tests (`WatchFineCrownTests` 5, `WatchPagerFocusTests` 5).

## Verified

- `swift test`, full watch package: 740 tests, 0 failures (lead, 2026-10-21).
- The lead's mutations, each red then restored byte-for-byte — 11 of the fine
  step (the weight, duration and pound constants, the extra weight, the `fine`
  flag ignored or always on, the state not passing `fine`, the model's turn
  using the quick step, the field default, the field not given its fine step,
  distance made fine) and 9 of the focus (the override ignored, the current
  page focused, a locked page focused, the binding without the focus, the page
  chosen by the engine's current, the focus not cleared on the moved branch or
  on a refusal, the counter taken from the engine, the slot-id fallback): all
  caught. Two mutants (the counter label, the keyless slot id) were caught only
  after two tests were added.
- The watch app target builds with `xcodebuild`.

## Not verified

- How the Crown and the swipe feel on a real watch: owner checks — the
  simulator has no Crown.

## Docs

- `docs/state_management/watch_surface_wrist.md`: the Crown paragraph now says
  the logging screen's Crown is the fine control (one kilogram or pound, one
  second per click) while the − / + buttons keep the quick step, citing
  S-7901..S-7905; the pager paragraph replaces the "preview card after a
  settle" reading with the focus behaviour — the settled swipe names
  `focusSlotId`, the selected page is the logger, the card remains only for the
  pages sliding in, `land(on:)` clears the focus — citing S-7911..S-7914
  alongside the S-6610..S-6612 source guards.
