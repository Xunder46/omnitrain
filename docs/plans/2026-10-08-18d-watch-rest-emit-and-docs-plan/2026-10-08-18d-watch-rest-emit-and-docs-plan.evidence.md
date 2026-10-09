# Evidence — 18d: the watch emits its rests, and the totals and docs follow

Plan: `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`
Review findings live beside this file, in `…-plan.review.md`. This plan carries the wrist half of 18c's moved scope
(18c: `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/…`), and its baselines are 18c's, unchanged.

This file holds what a reader cannot get from the plan: the base-commit baselines, the pasted red evidence and the green
counts for every guard. Implementers append; the reviewer re-runs the commands and checks the numbers. **No claim of
success without a pasted count** — "it passes" is not evidence; `flutter test`'s `+N ~M` line, `swift test`'s
executed/failed counts and `flutter analyze`'s issue count are.

## Baselines at the base commit

Same numbers 18c recorded; 18d must hold or rise, never fall.

| Check | Command | Baseline |
|---|---|---|
| Flutter suites | `.github/copilot/scripts/macos/gateway.sh test` | +4181 passed, ~1 skipped |
| Watch package | `.github/copilot/scripts/macos/gateway.sh swift-test` | 376 executed, 0 failed |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing infos) |
| Watch app | `xcodebuild` for a watchOS simulator, `OmniTrain Watch App` | governor-run, once per PR |

A phase's Done Criteria are green only if its own suites pass **and** the analyzer's issue count has not risen above 196
without a stated reason.

Phase 1's own run at `2a19db2` (HEAD, unchanged): Flutter `+4205 ~1` — 24 above the table's `+4181`, all green, no
failures; the difference is 18c's phase-2 test files, which landed after the baseline read. Analyzer `196 issues found.`,
0 errors, 0 of them in a file this run touched. Watch package: `389 executed, with 120 failures` in 8 pre-existing cases
(see Phase 1's section below — the baseline's 376 + this run's 13 new tests = 389).

## Red → green (fill in per phase; one row per guard)

| Phase | S-id / guard | Test (file · name) | Red evidence (paste) | Green (counts) |
|---|---|---|---|---|
| 1 | S-320, S-322, S-331, S-332, S-333, S-334, S-336 (Swift) | `WatchSessionEngineTests.swift`, `WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift` | new code: `prove-red` says RED AT by compile error, which proves nothing; M1/M4/M5 killed their mutants (below) | 11 tests green (`swift-test --filter`) |
| 1 | S-321 (Swift) | `WatchLoggingTimersTests.swift` (the pre-entry stop's instant) | new code, as above; M6 survived (see below) | 1 test green |
| 1 | S-339 (Swift) | `WatchFileStoreTests.swift` (the lookup survives a relaunch) | new code, as above; M1 red | 1 test green |
| 1 | S-320 closed kind (Swift) | `WatchNutritionQuickLogTests.swift` · `testTheKindsTheWristCanEmitAreAClosedSet` | M7: `rest` dropped from `all` fails the literal list at `:586` | 1 test green |
| 1 | S-320, S-322, S-332, S-333, S-334, S-336 (Dart) | `test/watch_session_engine_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_rest_surface_test.dart` | `prove-red HEAD …` → **GREEN AT**: it runs the *base tree's* copy of the test file, which has none of these tests, so it proves nothing for new code. Mutations M12–M16 instead (below) | `+232` over the ten files, 0 failures (below) |
| 1 | S-321 (Dart) | `test/watch_logging_timers_test.dart` | M14: `endRest(at: loggedAt)` → `endRest()`; `--plain-name "S-321"` red (the window collapses, nothing is emitted) | 1 test green |
| 1 | S-320 rest row + emission (Dart) | `test/watch_session_rest_timer_append_test.dart` | M12: the emission call site's kind test → red | 1 test green |
| 1 | S-335 parity | `test/watch_reconciliation_cross_stack_test.dart` + the same five-step fixture in `WatchSessionEngineTests.swift` | M12 — the emission is the only new code on this path; the fixture is the same five-step script as Swift's | 1 test green |
| 1 | S-320 closed kind (Dart) | `test/watch_nutrition_quick_log_test.dart` · `the kinds the wrist can emit are a closed set` (`:1338`) | M16: `rest` dropped from `all` fails the literal list at `:1339` | 1 test green |
| 2 | S-329 total | `test/watch_session_summary_integration_test.dart` (one imported fixture, one phone-counted control) | `.github/copilot/scripts/macos/gateway.sh prove-red <the commit 18c was built on> test test/watch_session_summary_integration_test.dart -- lib/watch/session/watch_records.dart lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart` must **fail** there — the `rest` kind does not exist at that ref, so the fixture cannot be built | |
| 2 | S-340 views | `test/unified_rest_overlay_test.dart` + `test/watch_rest_ping_test.dart` (Mock-first) | the same `prove-red` on `test/unified_rest_overlay_test.dart` (the imported row cannot exist before 18c) | |
| 2 | S-341 rest rule + docs size | `test/rest_is_count_up_contract_test.dart`, `test/docs_indexing_contract_test.dart` | the two doc size numbers: `watch_surface.md` before → after, `watch-app-setup-and-qa.md` before → after | |
| 2 | S-341 residue | the two greps in Phase 2 item 8 | paste both outputs | |

## Phase 1 fixture ledger (the scenarios' populations, in one place)

| Fixture | Session | Stored observations before | Clock values | Expected emission |
|---|---|---|---|---|
| S-320 | `s1`, `se1`/`'e1'` | none | `T0`, `T0`, `T0+70s` | one rest `T0→T0+70s`, after `entry-1` |
| S-321 | `s1`, `se1`/`'e1'` | A | `T0`, `T0`, `T0+45s`, `T0+45s` | one rest `T0→T0+45s`, after A; B after it |
| S-322 / S-331 | `s1`, `se1`/`'e1'` | A | `T0`, `T0`, `T0+30s` | one rest `T0→T0+30s`, after A |
| S-323 | `s1`, `se1` | none | `T0`, `T0` | none (`endedAt == startedAt`) |
| S-332 | `s1`, `se1` | A | `T0`, `T0`, `T0+70s`, `T0+70s` | one rest, then silence |
| S-333 | `s1`, `se1`, adopted rest | A | `T0`, `T0`, `T0+5s`, `T0+20s` | none (the stop came from the phone) |
| S-334 | `s1`, no effort row | none | `T0+5s`, `T0+5s`, `T0+40s` | none (no after-entry) |
| S-336 | `s1`, `se1`, adopted rest from `T0+8s` | A | `T0`, `T0`, `T0+10s`, `T0+40s` | one rest `T0+8s→T0+40s`, after A |
| S-339 | `s1`, fresh engine over the same store | A (persisted) | `T0`, `T0`, `T0+40s` | one rest `T0→T0+40s`, after A |
| S-335 | `s1`, three logged sets | A, then B, then C | `T0`, `T0`, `T0+45s`, `T0+45s`, `T0+60s`, `T0+60s`, `T0+90s`, `T0+90s`, `T0+120s` | three rests: 45 s, 15 s, 30 s — the arithmetic is in S-335 |

## Reproducing the planner's verification answers

| Answer | Command |
|---|---|
| V-1 the finish path stops nothing (`WatchSessionEngine.swift` `transitionTo` `:1071`, `finishSession` `:340`, `abandonSession` `:349`, `captureSessionEnd` `:1381`; Dart `_transitionTo` `:1148`, `:341`/`:347`) | `grep -n "transitionTo\|captureSessionEnd\|stopTimer" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` |
| V-2 the lookup is positional, on the store's `sequence` order (D-221) | `grep -n "sequence" watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift` (`WatchObservationRecord` `:318`) + `stopTimer` `:1569` |
| V-3 the log's pre-entry stop uses the log's own instant, before the entry is appended (D-223) | `grep -n "isResting\|await endRest()\|appendObservation" watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` (`:589`) and `grep -n "isResting\|endRest()\|Future<void> log" lib/watch/logging/watch_logging_state.dart` (`log` `:607`, the stop `:629`; `endRest` `:197`) |
| V-4 the emission path already stores-then-emits and skips a stored id | `grep -n "appendObservation\|storedObservations\|_emittedMessageIds" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift lib/watch/session/watch_session_engine.dart` (Swift `:1167`/`:1225`; Dart `:1236`/`:1288`, `:1314`) |
| V-5 the twin has no `session_end` observation **and no `efforts` list** (Phase 1 adds it) | `grep -n "enum WatchObservationKind" -A 22 lib/watch/session/watch_records.dart` (`:58-68`; `grep -n efforts lib/watch/session/watch_records.dart` finds only the comment at `:644`) vs `WatchRecords.swift` (`:50-77`, `efforts` `:76`) |
| V-6 both stacks pin the kind list | `grep -n "closed set\|all ==\|unorderedEquals" watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift test/watch_nutrition_quick_log_test.dart` (`:583`, `:1338`) |
| D-220 the rest timer row carries its own start | `grep -n "func timerRowFrom\|stoppedAt\|startedAt" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (`stopTimer` `:1569`, `timerRowFrom`) |
| D-224 the timer frame's id comes from the row's `recordId` | `grep -n "messageId(for:\|appendTimer" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (`:1776`, `:1574`) |

## Environment notes that decide how a phase is run

- `flutter test` (full suite) takes minutes: run it with the gateway's 900 s timeout, and run widget tests Mock-first.
  A widget test that opens the Hive harness or awaits a real `Future.delayed` inside `testWidgets` hangs forever at ~0%
  CPU (FakeAsync never advances real time); seed Hive in `setUp` and keep persisting taps Mock-only.
- A test file whose Mock group is red can leave its Hive group hanging: fix the red group rather than re-running the file.
- `flutter analyze` exits non-zero while the repo carries pre-existing info notices — compare the count with 196.
- `swift test --package-path watch/watchos` compiles the watch package; the watch app target needs `xcodebuild` for a
  watchOS simulator, which only the governor runs. The Swift side has no `prove-red` gate, so Phase 1's Swift red evidence
  is the pasted failing-test list from the red run before the emitter lands.
- Between 18c's merge and Phase 1 there is no wrist emission at all (the phone's writer is idle): a correct, expected
  intermediate state. After Phase 1 the wrist emits; the phone is already able to write it, so there is no window in which
  the wrist re-offers an unsettled row.
- Two facts the planner corrected on its final read (A-7): the Dart twin has no `efforts` list, so Phase 1 adds one
  (`lib/watch/session/watch_records.dart:58-68`); and `prove-red` names source files after `--`, not directories — every
  row above spells the full invocation for that reason.

## Phase 1, Swift half — the developer's run (items 1, 3, 4, 5, 6, 7)

Base commit `2a19db2`. Footprint: 9 files, 649 insertions, 8 deletions
(`.github/copilot/scripts/macos/gateway.sh git-diff --stat`) — sources `WatchRecords.swift`, `WatchSessionEngine.swift`,
`WatchLoggingState.swift`; tests `WatchSessionEngineTests.swift`, `WatchLoggingTimersTests.swift`,
`WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift`, `WatchFileStoreTests.swift`,
`WatchNutritionQuickLogTests.swift`. Items 2 and 8 (the Dart twin) are part B and untouched.

### Red proof

    gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test
    guards; a compile or load error means the test could not run there (use a mutation instead).

The reason there is a compile error: `error: type 'WatchObservationKind' has no member 'rest'` at eleven sites —
`WatchSessionEngineTests.swift:2079,2102,2154,2183,2351`, `WatchNutritionQuickLogTests.swift:590,595`,
`WatchRestIsCountUpTests.swift:115`, `WatchFileStoreTests.swift:1068`. The emission is new code, so per the gateway's own
note the guards are proved by mutation below.

### Mutation table (original → mutant → verdict → restored exactly)

| # | Original | Mutant | Verdict |
|---|---|---|---|
| M1 | `stopTimer`: `if stopped.kind == WatchTimerKind.rest { await emitRestEnded(stopped, following: timer) }` | call removed | **killed**: all 9 selected tests red, `("0") is not equal to ("1")` — S-320, S-322, S-331, S-332, S-333, S-334, S-335, S-336, S-339 |
| M2 | `emitRestEnded`: `guard let endedAt = row.stoppedAt, endedAt > row.startedAt else { return }` | `…, endedAt > row.startedAt` dropped | **survived** (S-323, S-320 green). A zero-length frame is *built* but `SyncProtocolValidator.restWindowRejections` (`SyncProtocolValidator.swift:239-259`) refuses it and `appendObservation`'s `try?` drops it, so the stored count is 0 either way: the fixture cannot tell the guard from the validator. The Swift validator has no Swift test of `restWindowRejections` (grep for the rejection text and for `"kind": "rest"` over `watch/watchos/Tests` finds only `WatchLiveMirroringTests.swift:180`, a snapshot fixture) |
| M3 | `emitRestEnded`: `guard let followed = restFollowOnEntryId(before: preStop) else { return }` | `guard true`, optional chaining | **survived** (S-334 green), same reason: an empty `afterEntryId`/`sessionExerciseId` fails the envelope schema's `minLength: 1` |
| M4 | `stopTimer`: `guard let timer = activeTimer(kind), timer.state != WatchTimerState.stopped` | `timer.state != stopped` dropped | **killed**: S-332 twice — `WatchSessionEngineTests.swift:2178,2182,2187` and `WatchRestSurfaceTests.swift:186` (`("2") is not equal to ("1")`) |
| M5 | `stopTimerFromMessage`: no emission | `await emitRestEnded(row, following: timer)` added | **killed**: S-333, `WatchSessionEngineTests.swift:2228` — "the phone ended it, so the wrist must not hand it back (D-219)" |
| M6 | `restFollowOnEntryId`: `if observation.sequence >= timerRow.sequence { continue }` | line dropped | **survived** (S-321, S-335 green): every emission site stops the rest *before* the next entry is stored, so the newest stored effort row already precedes the rest row. The line's effect shows only when a phone entry lands mid-rest, which no shipped fixture does |
| M7 | `WatchRecords.swift` `all` = `[…, sessionEnd, rest]` | `rest` dropped | **killed**: `testTheKindsTheWristCanEmitAreAClosedSet`, `WatchNutritionQuickLogTests.swift:586` (the literal list) |

Every mutant was restored and the green re-run confirmed; the footprint after the last restore is the one above.

### Green

- `.github/copilot/scripts/macos/gateway.sh swift-test` → `Executed 389 tests, with 120 failures` in **8** test cases (below).
  Baseline 376 + the 13 new tests = 389, so every new test ran; none of the 8 is mine.
- `.github/copilot/scripts/macos/gateway.sh test test/rest_is_count_up_contract_test.dart test/sync_protocol_fixtures_test.dart`
  → `All tests passed!` (105 tests), so S-166's scan of `watch/watchos/Sources` and the wire fixtures stay green.
- `.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found.`, 0 errors (== baseline).
- `.github/copilot/scripts/macos/gateway.sh test` (full) → `+4205 ~1: All tests passed!`
- `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` → `+9: All tests passed!` (this run
  edits two files under `docs/plans/`, which that contract reads).

### Unplanned red: 8 pre-existing tests, 5 files, 3 of them outside Predicted Files

One root cause: the rest observation is stored and emitted, so every fixture that *enumerates* a session's observations
or its emitted frames sees one more row.

| File (in Predicted Files?) | Test | Failure |
|---|---|---|
| `WatchCaptureContractTests.swift` (no) | `testFCapFull…`, `testFCapFullUpToEnd…`, `testFCapNoSensors…`, `testFCapNoSensorsUpToEnd…`, `testFCapPromptOff…` | the F-CAP event list gains `rec-13-rest`, `rec-15-rest`, `rec-17-rest`, every later index shifts against the wrong contract event, and prompt-off sees 11 events, not 8. `swift-test --filter WatchCaptureContractTests` → `Executed 5 tests, with 112 failures` |
| `WatchEmitForwarderTests.swift` (no) | `testTheEnginesEmissionsReachTheSinkInOrder` | `("7") is not equal to ("6")`; frame 4 is now `observations_up`, frame 5 `session_lifecycle` |
| `WatchSensorRecordingTests.swift` (no) | `testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged` | its ack list `["e-run", …, "e-set3"]` never names the rest ids, so the readings are never released: `("0") is not equal to ("20")` at `:606`. `swift-test --filter WatchSensorRecordingTests` → `Executed 38 tests, with 2 failures` |
| `WatchRestSurfaceTests.swift` (yes) | `testS163LoggingEndsARunningRestFirst` | `("5") is not equal to ("3")` — `engine.entries` now counts the two rest rows beside the three sets |

Readers the plan's Existing-Functionality Impact table does not list, all reached by the new row: `engine.entries`
(`WatchSessionEngine.swift:199`, "the session's entries as the wrist shows them"), `WatchLoggingState.observations`
(`:347`, filtered by `sessionExerciseId`, which a rest copies from the entry it follows), the snapshot's
`"entries": entries.map(\.payload)` (`:248`), and the three fixtures above. Not edited: they are other features' tests and
the plan did not predict them.

## Fix round 1 (part A) — the nine pre-existing reds, closed

Brief `.work/watch-18c/brief-fix-18d-1.md`, on top of the run above (base `2a19db2`). Scope: `watch/watchos/**`
Sources/Tests, `watch/contract/watch_capture_contract.json`, this file. The Dart twin (items 2 and 8) is still part B.

### What each red was, and what it needed

| Red (from the table above) | Cause | Change | Verdict |
|---|---|---|---|
| 5 × `WatchCaptureContractTests` F-CAP | the contract did not carry the rest events the engine now emits | the three rest events added to `expectedEvents` of `full`, `no-sensors` and `prompt-off`; prompt-off's count 8 → 11 | legitimate |
| `WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder` | 7 frames, not 6 | the expectation is the 7-frame list, with the frame the rest's start and stop each send | legitimate |
| `WatchSensorRecordingTests` / `…StepsDeniedTests` S-237 | the ack list never named the rest ids, so no reading was released | the three rest ids added to `confirmObservations` | legitimate |
| `WatchRestSurfaceTests.testS163…` | `engine.entries` counts the rest rows beside the sets | 3 → 5, "three sets, plus the two rests their logs ended (D-219): the third rest is still running" | legitimate |

No production defect: every red is a fixture that enumerates a session's observations, entries or frames, and the new
rest row is the intended output (D-210, D-211, D-219).

The contract's rest events, verbatim (the same shape in all three cases; only the window and `afterEntryId` differ):

    {"entryId": "rec-13-rest", "eventId": "rec-13-rest", "kind": "rest",
     "loggedAt": "2026-09-25T10:48:00.000Z", "sessionExerciseId": "sx-bench",
     "exerciseId": "ex-bench", "startedAt": "2026-09-25T10:45:00.000Z",
     "endedAt": "2026-09-25T10:48:00.000Z", "afterEntryId": "e-set1"}

`rec-15-rest` (10:48:00 → 10:51:00, after `e-set2`) and `rec-17-rest` (10:51:00 → 10:55:00, after `e-set3`) are the same
shape. All three ids are in each case's `expectedImport.receiptedEntryIds` too, and each case's `derivation` names them.
`full` now emits `e-run, e-r1, e-r2, e-r3, e-set1, rec-13-rest, e-set2, rec-15-rest, e-set3, rec-17-rest, end-s-cap-1,
rating-s-cap-1`; up-to-End is the same without the rating; `no-sensors` is identical; `prompt-off` is those 11 without the
rating.

### Mutation table (Swift has no `prove-red`; original → mutant → verdict → restored exactly)

| # | Original | Mutant | Verdict |
|---|---|---|---|
| M8 | `emitRestEnded`: `let eventId = "\(row.recordId)-rest"` | `"\(row.recordId)"` | **killed**: `swift-test --filter WatchCaptureContractTests` → `Executed 5 tests, with 35 failures`, each naming the id — `rec-13-rest.eventId is "rec-13", the contract says "rec-13-rest"` |
| M9 | `stopTimer`: `await emitRestEnded(stopped, following: timer)` | call removed | **killed**: S-163 → `("3") is not equal to ("5")` |
| M10 | S-237's ack list, the three rest ids present | ids dropped | **killed**: both copies → `("0") is not equal to ("20")` at `:606` |
| M11 | `transitionTo`: `await stopTimer(kind: WatchTimerKind.rest, at: now)` | call removed | **killed**: the forwarder test → `("6") is not equal to ("7")`, frame 4 `observations_up` where `timer_state` is expected — so the seventh frame is the finish-path stop's `timer_state`, as the new comment claims |

All four were restored exactly (`grep` finds no mutant text) and the green run below follows the last restore.

### Green

- `.github/copilot/scripts/macos/gateway.sh swift-test` → `Executed 389 tests, with 0 failures`, exit 0, 0 failure lines.
- `.github/copilot/scripts/macos/gateway.sh test` (full) → `+4202 ~1 -3: Some tests failed.` Baseline `+4205 ~1`: the
  three are the Dart reds below and nothing else.
- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart` → `+52 -3` (the same three).
- `.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found.`, 0 errors (== baseline).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing.

### Unpredicted Dart red: the contract change reaches `test/watch_session_import_test.dart`

`S-261 {full,no-sensors,prompt-off}: nine envelopes through the router import exactly the contract` reads
`captureEvents(caseName)` — the contract's `expectedEvents` — and feeds each event through the router, so the rest events
join the stream. Its early-receipt guard then fails at `test/watch_session_import_test.dart:337`:

    Expected: empty
      Actual: ['rec-13-rest', 'rec-15-rest', 'rec-17-rest']
      S-261 receipts are sent after the rows exist

The receipt itself is correct: the conformance test's `expect(expectedImport['receiptedEntryIds'], equals(sentIds))`
passes with the three ids added, and the importer writes the row (`S-320 a staged set and rest import one rest row after
the set` is green). The gap is the test's own `_rowsExist` helper (`:201-250`): its `default:` branch treats any unknown
kind as a `set`, so a rest id gets `setEntries.indexOf(entryId) == -1` and no row is ever found. Part B needs a
`case 'rest':` branch there (the row is `getEntryRests(effortId)` at `entryIndex` = the index of `afterEntryId` among the
set entries) and the three test names, which now feed twelve envelopes in `full`, not nine.

The plan predicted `test/watch_capture_contract_conformance_test.dart` would be red here; it passes, both alone and in the
targeted run over the three contract files (`+85 -3`, the only reds being the three above). It does not read the
contract's `expectedEvents` as a stream — it reads the summary's timed, round and set events — so nothing in it moved.

Footprint of this round: this file, `…-plan.md`, `watch/contract/watch_capture_contract.json`,
`WatchCaptureContractTests.swift`, `WatchEmitForwarderTests.swift`, `WatchRestSurfaceTests.swift`,
`WatchSensorRecordingTests.swift` — the four tests inside `watch/watchos/**`, the contract in its own folder, no Dart and
no `lib/` file.

## Phase 1, Dart half (part B) — the developer's run (items 2 and 8)

Base commit `2a19db2`; part A's Swift half and fix round 1 are uncommitted on the same tree. Footprint of this half
(`.github/copilot/scripts/macos/gateway.sh git-diff --stat`, stat column = insertions + deletions): 12 files, 1090 lines —
sources `lib/watch/session/watch_records.dart` (19), `lib/watch/session/watch_session_engine.dart` (91),
`lib/watch/logging/watch_logging_state.dart` (10) and the unplanned `lib/watch/session/hive_watch_session_store.dart`
(16, below); tests `test/watch_session_engine_test.dart` (427), `test/watch_session_finish_test.dart` (140),
`test/watch_rest_surface_test.dart` (122), `test/watch_reconciliation_cross_stack_test.dart` (103),
`test/watch_session_rest_timer_append_test.dart` (89), `test/watch_logging_timers_test.dart` (44),
`test/watch_session_import_test.dart` (21), `test/watch_nutrition_quick_log_test.dart` (8). Plus this file and
`…-plan.md`. No `.swift` file moved.

### Red proof — `prove-red` says GREEN AT, so the guards are proved by mutation

    gateway: prove-red (timeout 900s): flutter test test/watch_session_engine_test.dart
    gateway: prove-red: GREEN AT HEAD (exit 0) …
    … All tests passed!

The plan's Done Criteria spell `prove-red HEAD test test/watch_session_engine_test.dart -- lib/watch/session/watch_records.dart
lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart`. `prove-red` materialises the base
ref and copies only the **named source files** over it, then runs the **base tree's** test file — which predates every
test in this half, so the run is green by construction and proves nothing. New code, per the gateway's own note, is proved
by mutation; M12–M16 below are that proof. (Part A hit the same wall and used the same route.)

### Mutation table (original → mutant → verdict → restored exactly)

| # | Original | Mutant | Verdict |
|---|---|---|---|
| M12 | `stopTimer`: `if (stopped.kind == WatchTimerKind.rest) {` | `WatchTimerKind.round` | **killed**: `--plain-name "S-320"` → 3 failures — "one rest ended, one event" gets `[]` (nothing emitted), and the two surface tests' `singleWhere` finds no rest event |
| M13 | `_transitionTo`: `if (status != null) { await stopTimer(kind: WatchTimerKind.rest, at: now); }` | `if (status == null)` | **killed**: `--plain-name "S-322"` → both tests fail — `No element` (no `rest` event) and `Expected: 'stopped' Actual: 'running'` |
| M14 | `log`: `await endRest(at: loggedAt);` | `await endRest();` | **killed**: `--plain-name "S-321"` → red, no emission: the clock has not moved, so the window is zero-length and the guard skips it |
| M15 | `HiveWatchSessionStore._nextSequence`: `return ++_lastSequence;` | `return _lastSequence;` | **killed**: `--plain-name "S-331"` → `Expected: 'stopped' Actual: 'running'` at `test/watch_session_engine_test.dart:527` |
| M16 | `all` = `[…, nutritionQuickLog, rest]` and `efforts` = `[set, timed, round, hold]` | `rest` dropped from `all`, added to `efforts` | **killed**: `--plain-name "closed set"` → `Expected: equals ['set', 'timed', 'round', 'hold', 'nutrition_quick_log', 'rest'] unordered / Actual: ['set', 'timed', 'round', 'hold', 'nutrition_quick_log']` at `test/watch_nutrition_quick_log_test.dart:1339` |

M16's `efforts` half is not separately observable: the lookup only reads it to reject a row that is not an effort, and no
fixture stores a nutrition row mid-rest (S-334's session has no observations at all), so the closed-set literal is the
guard. Every mutant was restored exactly (the two files' `git-diff --stat` is back to 19 and 16 changed lines) and the
green run follows the last restore.

### Green

- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_finish_test.dart
  test/watch_rest_surface_test.dart test/watch_logging_timers_test.dart test/watch_session_rest_timer_append_test.dart
  test/watch_nutrition_quick_log_test.dart test/watch_reconciliation_cross_stack_test.dart
  test/watch_session_import_test.dart test/watch_capture_contract_conformance_test.dart
  test/rest_is_count_up_contract_test.dart` → `+232: All tests passed!`, exit 0, 0 failure lines. Run twice — before and
  after the import cleanup below — with identical counts.
- `.github/copilot/scripts/macos/gateway.sh lint` → `202 issues found.` on the first run: six new
  `unnecessary_import` notices, one per test file this half touched, because `watch_records.dart` already exports
  `utcIso`/`parseUtcIso`/`parseOptionalUtcIso` (`:19`) and the file's own `wire_timestamps.dart` import became redundant.
  Removed those six imports → `196 issues found.`, 0 errors (== baseline), none of them in a file this run touched.
- `.github/copilot/scripts/macos/gateway.sh swift-test` → `Executed 389 tests, with 0 failures`, exit 0 (part A's tree,
  unchanged by this half).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing. (`lib/main.dart`,
  the composition root, is the only importer.)

### Unplanned, required: the Hive store's append counter (outside Predicted Files)

The S-331 rebuild guard was red for a reason the emission has nothing to do with:

    -  int? _lastSequence;
    +  int _lastSequence = -1;
    -  final highest = _lastSequence ??= (await _allRows()).fold<int>(0, …);
    -  return highest + 1;
    +  if (_lastSequence < 0) { _lastSequence = (await _allRows()).fold<int>(0, …); }
    +  return ++_lastSequence;

`??=` caches the *stored* maximum and `highest + 1` never wrote the field back, so every append in a process returned the
same sequence — 1 for every row of a fresh store. Rows then share a `sequence`, `readAll`'s sort is ambiguous, and
`_newestTimer` (which orders by sequence) picks a stale row: after the finish-path stop, a relaunch read the rest timer as
still `running`. The fix advances the counter (`++_lastSequence`) and rebuilds it from the stored rows only on the first
append of the process. The Swift twin does not have the bug (`WatchFileStoreTests` S-339 is green at part A), so this is a
Dart-only defect the planned scenario found. `HiveWatchSessionStore` is not in Predicted Files; the two test files that
construct it (`test/watch_nutrition_quick_log_test.dart`, `test/watch_session_engine_test.dart`) are both in the green set
above, so nothing else reads the changed ordering. Guard: M15.

### The one pre-existing Dart expectation this half moved

`test/watch_rest_surface_test.dart` · S-163 asserted `engine.entries.length == 3`. Part A changed the identical assertion
in `WatchRestSurfaceTests.swift` to `5` — "three sets, plus the two rests their logs ended (D-219)" — because `entries`
projects every stored observation with no kind filter in both stacks. The Dart twin now says the same, so no guard was
weakened; it is the same expectation update part A already ratified (A-14).
