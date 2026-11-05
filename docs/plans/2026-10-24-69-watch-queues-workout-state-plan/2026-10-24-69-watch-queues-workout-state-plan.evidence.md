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

## Phase 2: the watch app, the contract and the docs (built 2026-10-24, uncommitted)

Base commit cb0c1ad6 (Phase 1). G-2: the four files were clean at HEAD. Crew runs: D (the app radio file and the source guard S-9915), F (PROTOCOL.md row and one sentence, in parallel), G (docs keeper, in parallel). No fix rounds. Two small lead edits: the S-6703 snapshot message wording in `WatchBridgeQueueTests.swift` (the plan's residue grep) and the S-9915 citation in the doc (the keeper ran before the guard existed).

Observed by the lead:
- Full package `swift test`: `Executed 967 tests, with 0 failures` (965 + 2 new source guards).
- `xcodebuild` "OmniTrain Watch App" (watchOS simulator, Series 11 42mm): `** BUILD SUCCEEDED **` with the real `outstandingTransfers`/`cancelTransfers` over `WCSession`. The build's project-file rewrite was reverted with `git checkout`.
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`: `+42: All tests passed!`; invariant grep: empty.
- `watch_surface_wrist.md`: 50,480 bytes (limit 52,000).
- Residue: `try self.queue(frame)` in the app file, `Deliberately five members`, "true exactly for `observations_up`" in the doc, "a snapshot would arrive stale" in the tests: all gone.

Mutation pass on the app file guards (lead, in place, restored and compared): 5 of 5 killed: late refusal back to `self.queue` (S-9915), `cancel()` never called (S-9915), cancel without the activation guard (S-9915), list without the activation guard (S-9915), a second `transferUserInfo(` call (S-6708, S-9915).

Not checked: the real transfers on devices (listing and cancelling a transfer already in flight; delivery to a closed phone app). Those are the owner device checks 1-3 in this plan. No separate reviewer run; the lead read the diffs.
