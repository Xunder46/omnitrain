# Evidence — plan 43b1 (wire + wrist)

Proof date: 2026-10-20 (lead). Docs and evidence: docs keeper, 2026-10-20.

## Baselines

- `flutter analyze`: 181 issues before and after (no new notices).
- Full `flutter test`, `swift test` (624+ tests) and the `xcodebuild` of the watch app target: re-run by the lead at the end of the plan (pending at the time this evidence was written).

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-6001 a `timer_state` whose `elapsed` timer carries `sessionExerciseId` validates; empty string, number and unknown extra field refused | manifest-driven: `S-001 fixtures` → `valid/timer_state_with_slot.json` conforms, `invalid/timer_state_slot_empty.json`, `invalid/timer_state_slot_number.json`, `invalid/timer_state_slot_unknown_field.json` rejected as stated | `test/sync_protocol_fixtures_test.dart`; `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift` (`testEveryValidFixtureConforms`, `testEveryInvalidFixtureIsRejectedAsStated`) |
| S-6002 a work start names its slot on the wire; a rest names none | `testS6002AStartOfATimedSlotNamesTheSlotOnTheWire`, `testS6002AStartOfAHoldSlotNamesTheSlotOnTheWire`, `testS6002AStartOfARoundsSlotNamesTheSlotAndKeepsItsLength`, `testS6002TheRestTheFollowingLogStartsCarriesNoSlot` | `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift` |
| S-6003 the slot survives the store round trip, pause/resume/stop rows keep it, an older row without it restores with none | `testS6003ATimerRowWithItsSlotSurvivesTheStoreRoundTrip`, `testS6003AStoredTimerRowRestoresItsSlotThroughJSON`, `testS6003ATimerRowWrittenWithoutTheSlotRestoresWithNone`, `testS6003PauseResumeAndStopKeepTheSlot` | `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` |
| S-6004 a message timer for another slot is not the wrist's work clock; a wrist-started clock survives the jump; a slot-less phone timer behaves as today | `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock`, `testS6004AClockTheWristStartedSurvivesTheJump`, `testS6004APhoneTimerWithNoSlotIsShownForTheCurrentSlot` | `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift` |
| S-6005 the earlier start wins at adoption (work kinds); stopped always applies; another slot stored beside; rest exempt | `testS6005AnEarlierPhoneStartReplacesTheWristsRunningTimer`, `testS6005ALaterPhoneStartLeavesTheWristsTimerAlone`, `testS6005AStoppedPhoneRowWithALaterStartStillStopsTheTimer`, `testS6005AnEarlierPhoneStartForAnotherSlotIsStored`, `testS6005ALaterTimerForAnotherSlotIsStoredNotIgnored`, `testS6005AStartAfterThePreviousTimerStoppedIsStored`, `testS6005RestIsNotAnEarlierStartWinsKind` | `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` |
| S-6006 Dart twin: the slot on the frame, the store round trip, and the earlier-start rule | group `S-6006 a work timer says which exercise it is for` (`a work timer started with a slot names it on its own frame`, `a rest names none, whatever it was started with`, `a timer row keeps its slot across the store`, `a stored timer row restores its slot through JSON`, `a row written without the slot restores with none`, `a stopped row keeps the slot of the row it copies`) | `test/watch_session_engine_test.dart` |
| S-6006 Dart twin: the earlier-start rule | group `S-6006 the earlier start wins at adoption` (`an earlier phone start replaces the wrist start`, `a later phone start leaves the wrist start alone`, `a stopped phone row with a later start still stops it`, `a timer for another slot is stored beside`, `a LATER timer for another slot is stored`, `a start after the previous timer stopped is stored`, `a phone rest with a later start still supersedes`) | `test/watch_logging_timers_test.dart` |

## Mutations (each made a named test red, then restored byte for byte)

Two tests-only gap rounds ran before the mutation round; every mutant below was killed by the named test.

Schema (3):
1. the `sessionExerciseId` property removed from `$defs.timer` → S-6001 red
2. `minLength: 1` loosened → S-6001 red
3. `"type": "string"` loosened → S-6001 red

Swift (9 + 4):
1. slot not stamped in `WatchLoggingState.startWork()` → S-6002 red
2. slot not emitted in `toTimerJson` → S-6002 red
3. slot not read back from JSON → S-6003 red
4. slot not kept by pause/resume/stop rows → S-6003 red
5. slot not stored when adopted → S-6005 red
6. the earlier-start comparison flipped → S-6005 red
7. the stopped-incoming-always-applies branch removed → S-6005 red
8. the same-slot condition dropped → S-6005 red
9. the held-not-stopped condition dropped → S-6005 red
10. the rest exemption dropped → S-6005 red
11. the message-only slot hiding in `WatchLoggingState.workTimer` removed → S-6004 red
12. (4th of the second group) the hiding's slot comparison loosened → S-6004 red

Dart (11 + 4): the same twelve behaviours against the Dart twin (`lib/watch/session/watch_records.dart`, `watch_session_engine.dart`), each killed by the matching S-6006 test in `test/watch_session_engine_test.dart` and `test/watch_logging_timers_test.dart`.

## Design corrections found by the P2 builder

1. **D-3 and D-4 narrowed (2026-10-20, recorded in the plan's Decision Ledger).** D-3: the hiding applies only to a timer that CAME FROM A MESSAGE (`isTimerFromMessage`, the `tms-` record id prefix) — a clock the wrist started itself keeps running across an exercise jump (existing S-1403 pins that). D-4: the earlier-start rule is for the WORK kinds only (`round`, `hold`, `elapsed`); a rest keeps last-write (existing S-336 pins that).
2. **Three existing tests turned red** under the original, un-narrowed wording and went green again once D-3/D-4 were narrowed. The brief does not name them and `.work/` is outside this run's read scope; the existing tests the narrowed rules cite are `WatchLoggingTimersTests.testS1403ARunningPeriodIsNotRetimedByTheJump` (S-1403) and the S-336 rest tests (`WatchRestSurfaceTests.testS336NextEndsARestThePhoneStartedAndTheWristStillReportsIt`, `WatchSessionEngineTests.testS336ARestThePhoneStartedAndTheWristEndsStillTravels`) — which of these three were the red ones is not checked.

## Pending

- `crew-reviewer` review of the built code.
- Owner checks: none visible yet (per the plan).
- The lead's end-of-plan full `flutter test`, `swift test` and `xcodebuild` re-runs.
