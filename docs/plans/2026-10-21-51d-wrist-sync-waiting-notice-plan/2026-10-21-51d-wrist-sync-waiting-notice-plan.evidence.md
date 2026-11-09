# Evidence — plan 51d (the wrist says when entries are waiting for the phone)

## Scenario-to-test table

| Scenario | Test (`watch/watchos/Tests/WatchSessionEngineTests/WatchSyncNoticeTests.swift`) |
|---|---|
| S-7701 nothing pending says nothing, for every reachability | `testS7701NoPendingIsNilForEveryReachability` |
| S-7702 unreachable says the count at once | `testS7702UnreachableSaysTheCountOfFreshEntries` |
| S-7703 reachable waits for the grace, counts all pending | `testS7703ReachableWaitsForTheGraceAndCountsAllPending` |
| S-7704 unknown gets the same grace as reachable | `testS7704UnknownGetsTheSameGraceAsReachable` |
| S-7705 the exact grace boundary shows | `testS7705TheExactGraceBoundaryShows` |
| S-7706 through the engine: the count and the receipt | `testS7706TheEngineCountsUnconfirmedAndAReceiptRemovesOne` |
| S-7708 rest windows are not counted nor aged | `testS7708RestWindowsAreNotCounted` |
| S-7707 the shell host passes the notice to both views | `testS7707TheShellHostPassesTheNoticeToBothViews` |
| S-7707 both views declare and show the notice | `testS7707BothViewsDeclareAndShowTheNotice` |

## Measured results

- Full `swift test`: 722 tests, 0 failures.
- The lead's mutation pass over `deriveSyncNotice`: 11 mutants (the unreachable
  arm off, the strict boundary, the count fixed at one on each of the two
  branches, oldest-is-newest, the plural flipped, the grace at 60, the
  reachable-old arm silenced, rest windows counted, rest windows aged, the
  engine accessor not filtering confirmed rows). All caught; every file restored
  byte-for-byte.
- One defect was found by the first test run: two sets with a rest between them
  store three records, so the count would have read "3 entries waiting for your
  phone". Fixed by excluding rest windows — `deriveSyncNotice` filters
  `kind != rest` before counting and ageing (S-7708).
- The watch app target builds with `xcodebuild`.
- NOT verified: how the line looks on the 40 mm menu and start screen, and the
  real radio's reachability flips — owner checks.
