# Evidence — 87c bests-only-when-changed (planner, 2026-10-27)

Planning-only run: no product code, test or doc outside the plan folder was touched; lint/test/swift-test were NOT run (nothing to validate yet). Baselines for the implementer are below.

## Baselines (to re-check at implementation)

- `flutter analyze`: the repo carries pre-existing info notices (~180 at planning time, per the series' prior runs); it exits non-zero. Compare issue COUNTS, not exit codes. No new error or warning is acceptable.
- `flutter test` (full suite): several minutes; gateway `test` check, 900 s timeout. Widget tests hang in FakeAsync — the new tests are plain `test()`.
- `swift test` in `watch/watchos`: gateway `swift-test`, 900 s. The watch app target itself needs `xcodebuild` (governor-only).
- Doc sizes: the planner cannot measure byte sizes (no shell beyond the gateway). The implementer measures `docs/state_management/watch_reference_data.md`, `docs/db_integration.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-qa-wrist-logging.md` before and after editing (52 KB band; `docs/state_management/watch_surface_wrist.md` is 52200 B and is NOT touched).

## Research evidence for the plan's Open questions

### q-a — the four listened boxes
- `StatsProgressService._loadHistory` (`lib/core/services/stats_progress_service.dart:100`) reads: getAllSessions, getSegmentsBySession, getEffortsBySegment, getObservationsByEffort, getTimedInstancesByEffort, getRoundInstancesByEffort, getSensorSummariesBySession (seven reads).
- `getAllTimeBests` (:2264+) consumes only sessions, segments, efforts, observations. Timed/round instances and sensor summaries contribute nothing to the bests → listeners on `sessions`, `segments`, `efforts`, `observations` only (plan A-87c-3).
- Listener pattern to mirror: `_listenForReferenceWrites` (`lib/data/repositories/hive_workout_repository.dart:258-285`), counter `_referenceRevision` :179, getter :2547, called from `initialize()` before `_initialized = true`; seed/migration events count (plan 74 D-3).
- `box.watch()` semantics: one event per put/delete, one per key on `clear` (plan 74 D-3); `putAll` fires per key — `putAll` sites: hive_workout_repository.dart:385, 585-657 (seed/migrations), 3237 (watchInbox).

### q-b — implementers of `WorkoutRepository`
- `implements WorkoutRepository`: exactly `HiveWorkoutRepository` (hive_workout_repository.dart:40) and `MockWorkoutRepository` (mock_workout_repository.dart:49). Grep over `lib/` and `test/`: no third.
- Test fakes all `extends MockWorkoutRepository` (~24: DelayedNoteRepository, DelayedRestMockRepository, `_RevisionedRepo`, etc.) → they inherit Mock's `historyRevision => null`. Non-breaking.
- Mock precedent: `referenceRevision => null` at mock_workout_repository.dart:1858; Hive getter at :2547; interface declaration at workout_repository.dart:715.

### q-c — the Dart twin stays unchanged
- `lib/watch/start/watch_sync_orchestrator.dart:31` declares `requestRoutines({DateTime? since})`; caller :92 passes only `since`. `NoWatchTransport.requestRoutines` (:32) is a no-op. `WatchConnectivityTransport.requestRoutines` (watch_transport.dart:295-296) serves the twin.
- The twin never sends `exercisesVersion` — documented divergence, `docs/state_management/watch_reference_data.md` ("The Dart watch client never reports a version (D-3805)").
- No parity test forces the key: the twin's frames are pinned KEY-LESS by S-102/S-103 exact equality (`test/watch_transport_test.dart:1591-1660`).

### q-d — `handle` callers
- Production: exactly one — `watch_sync_wiring.dart:320`.
- Tests: `watch_sync_request_handler_test.dart` ×30, `watch_sync_changed_only_test.dart` ×39, `watch_sync_idle_reads_test.dart` ×14, `rest_ping_contract_test.dart:314`, `watch_accent_contract_test.dart:148,162`. None passes `holdsBests` → default false → D-5(a) → unchanged behaviour.

### q-e — contract shape
- `watch/contract/watch_start_paths_contract.json` `transportRequests` :346-356; walked with exact-equality pins: Dart `_contract()` (test/watch_transport_test.dart:116; S-102 :1591-1611, S-3856 :1645-1660), Swift `bridgeContract()` (WatchConnectivityBridgeTests.swift:136; S-102/S-103/S-3820).
- Adding the key to an existing row breaks the pins → NEW row `routinesBests` (plan 23e2 added `routinesExercises` the same way).

### q-f — revision read placement
- Plan-74 pattern: the revision read is the first statement, guarded by source test S-10411 (test/watch_sync_idle_reads_test.dart:466-487).
- Only the bests block reads history, so reading `historyRevision` as the block's first statement satisfies "before any read". Mid-walk and post-walk writes both force a re-walk (S-87c-12).

### q-g — delivery results
- `WatchDelivery` (lib/core/platform/watch_delivery.dart:19): delivered/undelivered/queued. `bests_down` is not in `_queueable` (watch_transport.dart:225-232) → the real transport never queues it; doubles might. D-5 treats anything ≠ delivered as forget. S-87c-5 pins it.

### q-h — docs
- `docs/state_management/watch_reference_data.md`: request-frame section :146-160; "The bests close every answer" :222+. Both edited.
- `docs/db_integration.md:201` documents `referenceRevision` → `historyRevision` row beside it.
- `docs/state_management/watch_surface.md:560,570` → phone-side rule.
- `docs/watch-app-qa-wrist-logging.md` step 35 (:327) is 87b's banner step → 87c adds step 36.
- `watch/sync_protocol/PROTOCOL.md`: request rules :133-139; version-history rows 2026-10-23/24/26 at :759-765 (style template).
- NOT edited: `docs/state_management/watch_surface_wrist.md` (52200 B, warning band 52428 B), `docs/watch_session_sync.md` (grep: no request key, no bests).

## Swift conformer inventory (grep `func requestRoutines` over `watch/watchos`)

- `WatchSyncOrchestrator.swift:36` (protocol), `:103` (the sync() call).
- `WatchConnectivityBridge.swift:163` (production).
- Doubles: `WireLog` WatchConnectivityBridgeTests.swift:201, `GatedTransport` :1311, `GatedRequestTransport` :1365, `RecordingTransport` WatchSessionStartPathsTests.swift:50. All five gain `holdsBests`.

## Existing-suite survival check (S-87c-11)

- `watch_sync_changed_only_test.dart` S-9201..S-9212: `handle` without `holdsBests` → D-5(a) → S-9202's "exactly one `bests_down`" holds.
- `watch_sync_idle_reads_test.dart` S-10405 (`transport.types == ['bests_down']`): the harness's request frames carry no `holdsBests` key → frame still sent.
- `watch_sync_request_handler_test.dart` S-3850..S-3857, S-7101..S-7105, S-87a-6..13: frame-count assertions unchanged.
- `watch_transport_test.dart` S-003 (:671-679, batches-then-bests) and the S-102/S-3856 pins: `routinesFrame` without the flag is byte-identical.
- `watch_reference_sync_test.dart` uses `WatchReferenceSync.exercisesVersionOf` (builder-side, a different function) — unaffected.
- No existing assertion needs loosening; the only test edits are NEW groups.

## Phase 1A (dba, 2026-10-27) — observed output

### Changes landed
- `WorkoutRepository.historyRevision` (abstract, beside `referenceRevision`).
- `HiveWorkoutRepository`: `_historyRevision` + `_historyListeners`, `_listenForHistoryWrites()` (sessions, segments, efforts, observations) called from `initialize()` right after `_listenForReferenceWrites()`, getter beside the reference getter.
- `MockWorkoutRepository.historyRevision => null`.
- `WatchTransportRequest.routinesFrame(holdsBests:)` (key only when true), `holdsBestsOf`.
- No doc edit in this phase: Phase 3 owns the `db_integration.md` row and the request-frame section.

### prove-red
The base commit `403d96d98b996f8bbafe0b7dae85e7c911e76b3d` lacks the getter and the parameter, so the new tests cannot compile there; each guard was proved by mutation instead.

| Mutation (restored exactly afterwards) | Test | Observed failure |
|---|---|---|
| Drop `_observationsBox` from the four history boxes | S-87c-15 (repo file) | `Expected: <2>  Actual: <0>` — "two observation rows deleted in one call moved the history revision by 0" (test/repository_reference_revision_test.dart 329:7) |
| `holdsBestsOf` returns `frame['holdsBests'] != null` | S-87c-9 "only the boolean true means held" | `Expected: false  Actual: <true>` — a non-true value counted as held (test/watch_transport_test.dart 1833:9) |
| `routinesFrame` adds `'holdsBests': true` unconditionally | S-87c-9 "a request without the flag is the frame the contract pins" and "only the boolean true means held" | `Expected: {'request': 'routines'}  Actual: {'request': 'routines', 'holdsBests': true}` (1775:7); then `Expected: false  Actual: <true>` (1833:9) |

After the restores, both files green (`+68 All tests passed!`, `.work/gateway/test-20261027-225440-72513.log`). `grep -rn MUTANT lib test` clean (matches only in plan/docs files).

### Suites
- Touched files: `.github/copilot/scripts/macos/gateway.sh test test/repository_reference_revision_test.dart test/watch_transport_test.dart` → `+68: All tests passed!` (only these two files, 1 s).
- Full suite: `.github/copilot/scripts/macos/gateway.sh test` → `07:14 +5767 ~2: All tests passed!` (baseline 5761 + 6 new tests; 2 skipped; `.work/gateway/test-20261027-225501-73681.log`).
- Contract files: `test/docs_indexing_contract_test.dart` + `test/ui_standards_contract_test.dart` → `+42: All tests passed!`.
- `lint`: `180 issues found.` — the same count as the baseline, all `info`; none in the six files touched.
- Invariant: `grep -rn "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → none (only `lib/main.dart` imports it).

### Red → green
| Scenario | Test (group + test name) | Before the change |
|---|---|---|
| S-87c-8 | `S-10404 Mock: the revision is unknowable` / `S-87c-8 the history revision is null too` | did not compile (`no getter historyRevision`) |
| S-87c-15 | `S-87c-15 Hive: the four history boxes move the number` / `S-87c-15 session, segment, effort and observation writes move it` | did not compile; mutation red on the observation listener |
| S-87c-15 | same group / `S-87c-15 timed instances, foods and exercises leave it alone` | did not compile; green with the four listeners |
| S-87c-9 | `S-87c-9 the request says whether the wrist holds the bests` (3 tests) | did not compile; mutation red on the always-on key and the `!= null` read |

## Phase 1B (developer, 2026-10-27) — observed output

### Changes landed
- `lib/state/watch/watch_sync_request_handler.dart`: `_bestsHeld` field, `holdsBests` on `handle`, `_sendBests({required bool holdsBests})` extracted out of `_sendRoutines` (D-5(a)..(d)), header and doc comments.
- `lib/state/watch/watch_sync_wiring.dart` (:318): `holdsBests: WatchTransportRequest.holdsBestsOf(frame)`.
- `test/helpers/revisioned_repository.dart` (new): `RevisionedRepository` — the idle test's `_RevisionedRepo` plus a settable `historyRevision`, a `getAllSessions` read counter and `bumpHistoryOnRead`.
- `test/watch_sync_idle_reads_test.dart`: local `_RevisionedRepo` replaced by the helper; new group `S-87c-17 a wrist holding the bests is sent none while they stand still`; S-10411's needle widened (A-87c-7).
- `test/watch_sync_request_handler_test.dart`: new group `S-87c-1…S-87c-14 the bests are sent only when they moved` (12 tests), the `_seedHistory`/`_seedSession`/`_seedSet` fixtures and `_RecordingTransport.bestsDelivery`.
- `docs/state_management/watch_reference_data.md` and `docs/state_management/watch_surface.md`: the two sentences the change made false — "the bests … are sent whatever … happened to the bundle" and "a phone with no completed session still sends the frame" — replaced with the D-5 rule, naming `S-87c-1` and `S-87c-3`.

### prove-red
```
$ .github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_sync_request_handler_test.dart test/watch_sync_idle_reads_test.dart
test/watch_sync_request_handler_test.dart:92:8: Error: Error when reading 'test/helpers/revisioned_repository.dart': No such file or directory
test/watch_sync_request_handler_test.dart:1321:7: Error: No named parameter with the name 'holdsBests'.
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead).
```
The new tests cannot compile at HEAD (the `holdsBests` parameter and `historyRevision` do not exist there), so every guard below is proven with a mutation instead of prove-red.

### Mutations (each: original → mutant → red → exact restore → green)
`grep -rn MUTANT lib test` was clean between every row (the mutants were committed as plain edits, never left in place).

| # | Original line (in `_sendBests`) | Mutant | Red tests (observed assertion) |
|---|---|---|---|
| M1 | `if (holdsBests &&` in (b) and `if (holdsBests && held != null && held.entriesText == entriesText)` in (c) | `holdsBests &&` dropped from both | S-87c-4 (`Expected: an object with length of <1> / Actual: []`, 1492), S-87c-14 (same, 1747); also S-87a-6 (1134) and S-87a-12 (`Bad state: No element`, 1276) |
| M2 | `held.revision == historyRevision` | `false` (branch b never taken) | S-87c-1 (`Expected: <0> Actual: <1>` on `sessionReads`, 1369), S-87c-2 (1421), S-87c-3 (1471), S-87c-5 (1543), S-87c-6 (1592), S-87c-13 (1726), S-87c-14 (1766) |
| M3 | `held.entriesText == entriesText` | `false` (branch c never taken) | S-87c-3 (`Expected: empty / Actual: [bests_down …]`, 1456), S-87c-7 (1615), S-87c-12 (1692) |
| M4 | `final delivered = await _transport.send(frame) == WatchDelivery.delivered;` … `: null;` | remember unconditionally | S-87c-5 (`Expected: length <1> / Actual: []`, 1525; queued arm 1560), S-87c-13 (`length <2>` vs `<1>`, 1709) |
| M5 | `final historyRevision = _repository.historyRevision;` used at remember time | `revisionAtRemember` read after the walk | S-87c-12 (`length <1> / Actual: []` — request 2 skipped its walk, 1670) |
| M6 | `jsonEncode((frame['payload']! as Map)['bests'])` | `jsonEncode(frame['payload'])` (includes `generatedAt`) | S-87c-3 (`Expected: empty`, 1456), S-87c-7 (1615) — both move the clock between the two raises, so the stamp is the only difference |

### Suites
- `test test/watch_sync_request_handler_test.dart` → `+34: All tests passed!` (22 pre-existing + 12 new).
- `test test/watch_sync_idle_reads_test.dart` → `+9: All tests passed!` (8 pre-existing + S-87c-17).
- Verify-only, unedited: `test/watch_sync_changed_only_test.dart`, `test/rest_ping_contract_test.dart`, `test/watch_accent_contract_test.dart` + `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart` → `+77: All tests passed!`.
- Full suite: `.github/copilot/scripts/macos/gateway.sh test` → `05:43 +5779 ~2: All tests passed!` (baseline 5767 + 12 new; 2 skipped; `.work/gateway/test-20261027-231317-4608.log`).
- Full suite after the docs sweep, at the final state: `05:53 +5779 ~2: All tests passed!` (`.work/gateway/test-20261027-232102-15012.log`); `test/docs_indexing_contract_test.dart` alone → `+13: All tests passed!`.
- `lint`: `180 issues found.` — the same count as the plan's baseline, every one `info`, none in the two production files or four test files touched.
- Invariant: `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` → no matches.

### Red → green (this phase)
| Scenario | Test (group + test name) | Before the change |
|---|---|---|
| S-87c-1 | `…the bests are sent only when they moved` / `S-87c-1 a wrist holding the bests, raising again at the same revision, is sent none and reads no history` | did not compile (`No named parameter 'holdsBests'`); M2 red |
| S-87c-2 | same group / `S-87c-2 a completed workout reaches the next request, then goes quiet` | did not compile; M2 red |
| S-87c-3 | same group / `S-87c-3 a write that leaves the bests identical costs one walk and no frame` | did not compile; M3 and M6 red |
| S-87c-4 | same group / `S-87c-4 a request that does not say the wrist holds the bests sends the frame every time` | did not compile; M1 red |
| S-87c-5 | same group / `S-87c-5 a frame the radio did not carry is sent again, and after a delivered one the next request skips it` | did not compile; M2 and M4 red |
| S-87c-5 | same group / `S-87c-5 a queued frame is not delivered, so the next request sends it again` | did not compile; M4 red |
| S-87c-6 | same group / `S-87c-6 a phone that relaunched sends the frame once` | did not compile; M2 red |
| S-87c-7 | same group / `S-87c-7 a repository that cannot tell the revision walks every request and sends only when the entries moved` | did not compile; M3 and M6 red |
| S-87c-12 | same group / `S-87c-12 a write that lands during the walk is not hidden` | did not compile; M5 red |
| S-87c-13 | same group / `S-87c-13 an undelivered frame is re-sent, then the wrist goes quiet` | did not compile; M2 and M4 red |
| S-87c-14 | same group / `S-87c-14 a request without the flag always sends, even with remembered state` | did not compile; M1 red |
| S-87c-17 | `S-87c-17 a wrist holding the bests is sent none while they stand still` / `S-87c-17 a second idle raise sends no bests_down and reads no history` | did not compile; the walk-and-read assertions it shares with S-87c-1 are the ones M2 turned red in the handler file — the idle file itself was not mutated (its guard is the same `_sendBests` branch plus the wiring's flag) |

### Notes
- S-87c-7's second raise advances the injected clock by one minute so that `generatedAt` differs while the entries do not — that is what makes M6 red (A-87c-1).
- A throwing walk still propagates and leaves `_bestsHeld` untouched, so the next request walks again; no `catch` was added, matching today's behaviour and S-87a-7.
- S-10411's source scan needed its needle widened to the method's prefix (A-87c-7): the search was for the whole signature line, which D-5 changes by construction. No assertion was loosened.
- The two doc corrections (25 changed lines across the two files) are both inside sentences about the bests' delivery rule, and each now names a test that exists; the plan put the doc sweep in a later phase, so this is logged as A-87c-9 and the remaining watch docs are left to that phase.

## Phase 2 (developer, 2026-10-27) — observed output

### Changes landed
- `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift` (:97-112): `routinesFrame(since:exercisesVersion:holdsBests:)` adds `holdsBests: true` only when the wrist holds one — the key is omitted, never `false` (D-2); `requestRoutines` (:163) forwards the flag into the builder.
- `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift` (:39): `func requestRoutines(since: Date?, exercisesVersion: String?, holdsBests: Bool) async`; `sync()` passes `bests?.hasFrame ?? false`.
- `watch/contract/watch_start_paths_contract.json`: one new `routinesBests` row (`{"request": "routines", "holdsBests": true}`, no `since`/`exercisesVersion`); the `routines`, `routinesSince` and `routinesExercises` rows are byte-identical.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`: two tests between S-103 and S-3820 — `testS87c16TheRoutinesRequestCarriesHoldsBestsOnlyWhenTheWristHoldsOne` (contract pin, NSDictionary exact equality, plus the harness sync frame omitting the key) and `testS87c16TheSyncPassesWhetherTheWristHoldsABestsFrame`; `WireLog`, `GatedTransport` and `GatedRequestTransport` now record `requestedHoldsBests`.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`: `RecordingTransport` records `requestedHoldsBests` beside `requestedVersions`.
- `test/watch_transport_test.dart` (:1638): `S-87c-16 a wrist that holds the bests says so`, inside the existing `S-102 the request frames match the contract` group, reusing `_contract()`.
- `test/watch_session_projection_test.dart` (:813): new group `S-87c-18 the wrist's holdsBests reaches the handler` with one test (the wiring seam deferred from 1B, A-87c-8).

### prove-red
```
$ .github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --filter WatchConnectivityBridgeTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift
```
The Swift tests cannot compile at HEAD (neither `holdsBests` nor `requestedHoldsBests` exists there, and the contract has no `routinesBests` row), and the Dart pair cannot run there either (`holdsBests` is not a parameter of `handle`/`requestRoutines`), so every guard below is proven with a mutation instead of prove-red. `grep -rn MUTANT watch/watchos/Sources lib test` was clean between every row.

### Mutations (each: original → mutant → red → exact restore → green)

| # | Original line | Mutant | Red tests (observed assertion) |
|---|---|---|---|
| M1 | `if holdsBests { frame["holdsBests"] = true }` (`routinesFrame`) | `frame["holdsBests"] = true` unconditionally | `swift-test --filter WatchConnectivityBridgeTests` → 31 tests, 5 failures: S-102 and S-103 and S-3820 (the key appears in frames pinned key-less), plus both arms of S-87c-16's contract pin (the harness sync frame must omit the key) |
| M2 | same line | `if !holdsBests { frame["holdsBests"] = false }` (a `false` for a wrist that holds nothing) | same 31/5: S-102, S-103, S-3820 and both S-87c-16 contract arms — the pinned-row equality fails on the extra `holdsBests: 0` |
| M3 | `bests?.hasFrame ?? false` (`sync()`) | `false` | `swift-test --filter testS87c16TheSyncPassesWhetherTheWristHoldsABestsFrame` → 1 test, 2 failures: the arm after `receive` applies `fixtures/valid/bests_down.json` and the relaunch arm, both expected `true` |
| M4 | `holdsBests: WatchTransportRequest.holdsBestsOf(frame)` (`watch_sync_wiring.dart`) | argument dropped | `test test/watch_session_projection_test.dart --plain-name "S-87c-18"` → red on `Expected: length 1 / Actual: length 2` (the repeat request sent a second `bests_down`) |

### Suites
- `swift-test --filter WatchConnectivityBridgeTests` → 31 tests, 0 failures (pre-existing S-102/S-103/S-3820 etc. + 2 new).
- `swift-test` (full, at the final state) → `1124 tests, 0 failures` (1122 at the start of this run + 2 new; `.work/gateway/swift-test-20261027-235705-57032.log`).
- `test test/watch_transport_test.dart` → `+62: All tests passed!`.
- `test test/watch_transport_test.dart test/watch_session_projection_test.dart` → `+121: All tests passed!` (`.work/gateway/test-20261027-235537-53342.log`).
- Full suite: `.github/copilot/scripts/macos/gateway.sh test` → `06:00 +5781 ~2: All tests passed!` (1B ended at 5779; +2 new Dart tests; `.work/gateway/test-20261027-235705-57033.log`).
- `lint`: `180 issues found.` — the plan's baseline count, every one `info`, none in the seven changed files (`.work/gateway/lint-20261027-235944-60700.log`).
- Invariant: `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` → no matches.

### Red → green (this phase)
| Scenario | Test (group + test name) | Before the change |
|---|---|---|
| S-87c-16 | `WatchConnectivityBridgeTests` / `testS87c16TheRoutinesRequestCarriesHoldsBestsOnlyWhenTheWristHoldsOne` | no `routinesBests` row and no `holdsBests` parameter at HEAD (does not compile); M1 and M2 red |
| S-87c-16 | `WatchConnectivityBridgeTests` / `testS87c16TheSyncPassesWhetherTheWristHoldsABestsFrame` | same compile barrier; M3 red |
| S-87c-16 | `S-102 the request frames match the contract` / `S-87c-16 a wrist that holds the bests says so` | same compile barrier (`Dart routinesFrame` has no `holdsBests`); M1 and M2 red on the same line |
| S-87c-18 | `S-87c-18 the wrist's holdsBests reaches the handler` / `S-87c-18 a request that says the wrist holds the bests sends one frame and a repeat sends none` | same compile barrier; M4 red |

### Notes
- `NSDictionary` equality bridges JSON `true`/`false` as `NSNumber`, so a failing comparison prints `1`/`0`; the pinned-row comparisons are still exact (no coercion), which is what makes M2 red rather than neutral.
- The relaunch arm builds a second `WatchPersonalBests` over the same `InMemoryWatchSessionStore` and `restore()`s it (A-87c-10), the shape `WatchPersonalBestsTests`' S-87b-11 uses.
- The Mock's `historyRevision` is always null, so in S-87c-18 only the remembered entries text can suppress the second frame — which is exactly the seam being pinned there.
- The watch app target's own `WatchSyncTransport` conformers are compiled only by `xcodebuild` against a watchOS simulator, which the governor runs; `swift-test` covers the package targets only.

## Phase 3 (developer, 2026-10-28) — docs, QA step, statuses

Docs-only phase: no `lib/`, `test/` or Swift source was written by this phase.

### Changes landed
| File | Change | Size before (governor `/brief`) | Size after |
|---|---|---|---|
| `docs/state_management/watch_reference_data.md` | request frame gains `holdsBests` (a `true` only, omitted otherwise, read only as the boolean `true`, contract row `routinesBests`); "The bests close every answer that needs them" states D-5 and names `historyRevision` | 17903 B | within ceiling (asserted by the docs contract test, below) |
| `docs/db_integration.md` | one `historyRevision` row beside `referenceRevision`: equality only, null = cannot tell, the four listened boxes, the Mock's null, the S-87c-15 tests | 39361 B | +1 line |
| `docs/state_management/watch_surface.md` | the phone-side skip rule beside the plan-74 `referenceRevision` text; "Last, always, …" → "Last, … unless the wrist says it holds that frame" | 50147 B | +16/−7 lines |
| `docs/state_management/watch_surface_wrist.md` | F3: the bests are sent "whenever they changed or the wrist does not hold them", not on every answer; surrounding words shortened so the file does not grow | 52200 B | ≤ 52429 B — the 80 % warning-band assertion passes |
| `docs/watch-app-qa-wrist-logging.md` | step 36: two syncs with no workout between, then beat a best | 25556 B | +15 lines |
| `watch/sync_protocol/PROTOCOL.md` | the request rules name `holdsBests` with D-2's exactness rule; the bests bullet no longer says "every routines request"; a version-history row dated 2026-10-28 | outside `docs/` (no ceiling) | +23/−1 lines |
| `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md` | F1: 87b row `done (403d96d9)`, 87c row `built, awaiting review 2026-10-28 (phone half 2c64ffa5, wrist half on the tree)`, header line, and the 87a data-path bullet "until the wrist holds one (… 87c D-5)" | — | 8 lines |
| this plan (`…-plan.md`) | `> Status:` → BUILT 2026-10-28; Phase 3 items `- [x]`; Progress Phase 3 → Complete | — | 39 lines |

`watch_surface_wrist.md` started at 52200 B against the 52429 B warning-band threshold
(`_maxDocBytes = 65536`, `_warnFraction = 0.80`, `round(52428.8) = 52429`), so this phase had to
rewrite the F3 sentence without growing the file: it shortens "The watch's orchestrator awaits" →
"The orchestrator awaits", "The window therefore lives" → "The window lives", "a `routines_down`" →
"`routines_down`" and "a sync that only ever received foods" → "a sync that received only foods".

### Every behaviour sentence names a test that exists
| Doc claim | Test it names |
|---|---|
| the request says `holdsBests`, read only as the boolean `true`, omitted otherwise | `test/watch_transport_test.dart` / `S-102 the request frames match the contract` / `S-87c-16 a wrist that holds the bests says so`; `WatchConnectivityBridgeTests.testS87c16TheRoutinesRequestCarriesHoldsBestsOnlyWhenTheWristHoldsOne` |
| a holding wrist is sent no bests until something moved | `S-87c-1…S-87c-14 the bests are sent only when they moved` / `S-87c-1 a wrist holding the bests, raising again at the same revision, is sent none and reads no history`; `S-87c-3 a write that leaves the bests identical costs one walk and no frame` |
| a wrist that says nothing is sent them every time | `S-87c-4 a request that does not say the wrist holds the bests sends the frame every time` |
| a frame the radio did not carry is sent again | `S-87c-5 a frame the radio did not carry is sent again, and after a delivered one the next request skips it` |
| a completed workout reaches the next request, then goes quiet | `S-87c-2 a completed workout reaches the next request, then goes quiet` |
| the wrist's `holdsBests` reaches the handler | `S-87c-18 the wrist's holdsBests reaches the handler` / `S-87c-18 a holding wrist is sent no bests until its frame is stale` (`test/watch_session_projection_test.dart`) |
| `historyRevision` moves on history writes only | `S-87c-15 Hive: the four history boxes move the number` / `S-87c-15 session, segment, effort and observation writes move it`; `… / S-87c-15 timed instances, foods and exercises leave it alone` |

### Suites (observed)
- `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` → exit 0, **42 passed, 0 failed** (`All tests passed!`). This is what proves the 64 KiB ceiling and the 80 % warning band both hold for the six edited docs. Re-run after the plan/evidence/status edits (which are themselves under `docs/`): `gateway.sh test test/docs_indexing_contract_test.dart` → exit 0, **13 passed, 0 failed**, including `no documentation file is within the warning band of the ceiling`. The UI scans were untouched by those later edits, so the 42-test run stands for them.
- `gateway.sh test` (full) → exit 0, **5781 passed, 2 skipped** (`05:44 +5781 ~2: All tests passed!`), the same counts as the pre-phase baseline: no previously passing test went red.
- `gateway.sh lint` → **180 issues**, all pre-existing `info` notices under `test/`; no `lib/` or `docs/` file this phase touched produces an issue. Same count as the plan's baseline, so no new issues.
- Invariant (no concrete repository import in state/ui): grep `import .*hive_workout_repository` over `lib/` returns only `lib/main.dart` (the composition root) — nothing under `lib/state/`, `lib/features/`, `lib/widgets/`, `lib/core/`.
- Swift untouched by this phase — no `swift-test` run; the Phase 2 run stands.

### Residue sweep (`holdsBests`, `historyRevision`, "always" wording)
| Location | State |
|---|---|
| `lib/state/watch/watch_sync_request_handler.dart` | reader present (Phase 1B) |
| `lib/data/repositories/workout_repository.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart` | `historyRevision` declared and both implementations answer it (Phase 1A) |
| `lib/watch/start/watch_sync_orchestrator.dart` | no `holdsBests` — the Dart twin is the divergence D-7/q-c records, unchanged on purpose |
| `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift` | request carries `holdsBests` only when the store holds a frame (Phase 2) |
| `docs/state_management/watch_reference_data.md` | corrected (this phase) |
| `docs/state_management/watch_surface.md` | "Last, always" corrected (this phase) |
| `docs/state_management/watch_surface_wrist.md` | F3 corrected (this phase) |
| `watch/sync_protocol/PROTOCOL.md` | "The phone sends one with every routines request" corrected; `holdsBests` added; version row added (this phase) |
| `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md` | 87a data-path bullet now reads "… until the wrist holds one (… 87c D-5)" (this phase) |
| `docs/plans/2026-10-26-87a-…evidence.md`/`.review.md`, 87b/87c plan history | historical records of what was true then — left as written |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressTests.swift` — doc comment `/// The phone sends the bests last on every request (plan 87b D-8)` | F6 corrected (this phase): now "When the phone sends the bests it sends them last (plan 87b D-8)" — comment only, no assertion or code |
| `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift` — doc comment "`bests_down` belongs here because the phone sends it last on every request" | F5 corrected (this phase): now "… last in an answer whenever the bests changed or the wrist does not hold them (plan 87b D-8, plan 87c)" — comment only |

## Review fix 3 (developer, 2026-10-28) — observed output

- [x] F4 — `watch/sync_protocol/PROTOCOL.md`: the MAY-omit condition in the request rules (:145-148) and in the 2026-10-28 version-history row (:788) now reads "the key is the boolean `true`, the last `bests_down` it sent was delivered, and either no workout-history row has been written since or the bests it computes now are identical to that frame's"; the MUST-send arms are unchanged, and the version row names `S-87c-3` beside its existing pointers. Wording only; no other sentence.
- [x] F5 — `WatchSyncProgress.swift`: the `replyTypes` doc comment now says "sends it last in an answer whenever the bests changed or the wrist does not hold them (plan 87b D-8, plan 87c)"; the rest of the sentence is unchanged.
- [x] F6 — `WatchSyncProgressTests.swift`: the S-87b-12 comment now says "When the phone sends the bests it sends them last (plan 87b D-8)"; no assertion, no code.
- [x] Residue sweep: the two Swift comment rows above replace the "not fixed" row.
- Suites: `gateway.sh test test/docs_indexing_contract_test.dart` → exit 0, **13 passed, 0 failed**. `gateway.sh test` (full) → exit 0, **5781 passed, 2 skipped** (`05:20 +5781 ~2: All tests passed!`). `gateway.sh swift-test` → exit 0, **1124 tests, 0 failures** (source and test comments only; no assertion changed). `gateway.sh lint` → **180 issues**, the plan's baseline (all pre-existing `info` notices under `test/`).




