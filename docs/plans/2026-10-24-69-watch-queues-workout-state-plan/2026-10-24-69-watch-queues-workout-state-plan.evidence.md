# 69 evidence

## Phase 1: the package keeps only the newest workout state waiting (built 2026-10-24, uncommitted)

Base commit 88406be6. Owner answered Q1 = (A) (a watch-only workout simply appears in the phone's history), so the plan stands as written. G-1: the three files were clean at HEAD.
Crew runs: A (the bridge, `WatchConnectivityBridge.swift`), B (the fake session and the three superseding tests), C (19 replacement tests in the new `WatchBridgeReplacementTests.swift`). No fix rounds.
One deviation, a technical call: the two new seam members (`outstandingTransfers()`, `cancelTransfers(messageIds:)`) have default implementations in a protocol extension, so the watch app target keeps compiling until Phase 2 gives it the real ones.

Observed by the lead:
- Full package `swift test`: `Executed 965 tests, with 0 failures` (the append-only name guard is in that run). Baseline before the phase: 945.
- `xcodebuild` of "OmniTrain Watch App" (watchOS simulator, Series 11 42mm): `** BUILD SUCCEEDED **` with the defaults in place (project file rewrite reverted with `git checkout`).
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`: `+42: All tests passed!`; invariant grep (`hive_workout_repository`): empty. No Dart file changed.
- S-6706 stayed green unchanged (its assertions never covered a snapshot with a payload); S-9901 is the real guard for the new rule.

Mutation pass (lead, in place, original restored and compared after each; script kept outside the tree): 14 of 14 killed.

| Mutation | Killed by |
|---|---|
| active snapshot not durable | S-9901, S-9902 A, S-9903 |
| any snapshot durable | S-9901, S-9902 B |
| withdraw ignores `sessionId` | S-9903, S-9908 A |
| snapshot's own messageId not withdrawn | S-9904 A, S-9904 B, S-9909 |
| no `sentAt` comparison | S-9905 A, S-9911 C |
| equal stamp treated as newer | S-9905 B, S-9909 |
| terminal lifecycle withdrawn by a later frame | S-9908 C |
| terminal arm removed | S-9908 A, S-9910 |
| an observation withdrawn | S-9903, S-9908 A, S-9909 |
| no withdraw after a live send | S-9911 A, S-9911 B |
| package dedupe removed | S-9908 B, S-9909 |
| lock removed | S-9914 |
| a stale frame still queued | S-9905 A |
| the queue call without the withdraw | S-9903, S-9904 A, S-9904 B |

Not checked: the real `WCSession` (lists and cancels of the app target are Phase 2), and everything on a device. No separate reviewer run; the lead read the production diff.
