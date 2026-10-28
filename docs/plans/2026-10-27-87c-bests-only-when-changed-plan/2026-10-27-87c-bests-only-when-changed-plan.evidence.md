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


