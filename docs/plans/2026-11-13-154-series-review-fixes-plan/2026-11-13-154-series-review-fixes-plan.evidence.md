# Plan 154 evidence

Baseline: HEAD 860796cf, `flutter analyze` / `flutter test` counts to be filled by the lead's run.

## Phase 1 — A (EntryClaim lock, S-15401/S-15402)

Guard: `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineListRaceTests.swift`
`testS15401WaitersRacingFinishAllResume` (24 rounds x 32 waiters, finish after / racing the
registrations, 10 s poll deadline) and `testS15402WaitAfterFinishReturnsAtOnce`.

prove-red (TSan):

```
gateway: swift-test (timeout 900s): swift test --package-path watch/watchos --sanitize=thread --filter WatchEngineListRaceTests.testS15401
SUMMARY: ThreadSanitizer: data race WatchEngineRowLogs.swift:155 in EntryClaim.finish()
  #0 EntryClaim.finish() WatchEngineRowLogs.swift:155
  #0 EntryClaim.wait() WatchEngineRowLogs.swift:144
_Concurrency/CheckedContinuation.swift:172: Fatal error: SWIFT TASK CONTINUATION MISUSE: wait() tried to resume its continuation more than once
gateway: prove-red: RED AT HEAD (exit 1).
```

Green with the lock:

```
swift test --sanitize=thread --filter WatchEngineListRaceTests.testS1540
Test Case '... testS15401WaitersRacingFinishAllResume' passed (0.005 seconds).
Test Case '... testS15402WaitAfterFinishReturnsAtOnce' passed (0.007 seconds).
Executed 2 tests, with 0 failures (0 unexpected) in 0.011 seconds
```

## Phase 1 — B (`_routeLifecycleToHeld` passes `at`, S-15403/S-15404)

prove-red (HEAD, test carried over):

```
flutter test --plain-name S-15403
Expected: <1791202200000>
  Actual: <1794598807473>
D-15402 the held workout ends when the wrist ended it, not when the frame arrived
gateway: prove-red: RED AT HEAD (exit 1).
```

Green:

```
flutter test --plain-name S-1540
+2: All tests passed! (S-15403 and S-15404)
```

## Phase 2 — C (2 s end-skew tolerance, S-15405..S-15408)

Constant: `kEndSkewToleranceMs = 2000` in `lib/core/sync_protocol/end_skew.dart`. Rule: two end
instants within the tolerance (inclusive) are the same instant → D-14601's tie-break; only an end
earlier by MORE than the tolerance is the earlier end D-14630 replaces for. Applied at
`SessionReconciler._incomingEndWins`, `_routeLifecycleToHeld` (abandoned branch), the Dart twin's
snapshot and lifecycle sites, and `WatchSessionEngine` (`endSkewTolerance`, both sites).

Fixtures (new): `reconciliation/end_within_one_second.json` (S-15405, expected `completed`),
`end_exactly_at_the_tolerance.json` (S-15407, expected `completed`), `end_beyond_the_tolerance.json`
(S-15406, expected `abandoned`, already true at HEAD — the control case).

prove-red, phone bridge (HEAD, tests carried over):

```
flutter test --plain-name S-1540 test/watch_session_adoption_bridge_test.dart
Expected: <1791201900000>
  Actual: <null>
S-15405 a discard one second earlier is no earlier end
  D-15403 the tie-break keeps the finished workout (the discarded row is gone at HEAD)
Expected: <1791201900000>
  Actual: <null>
S-15407 a discard exactly at the tolerance is no earlier end
+2 -2: Some tests failed.
gateway: prove-red: RED AT HEAD (exit 1).
```

(S-15406 passes at HEAD by design: it pins the beyond-the-tolerance behaviour that must not change.)

prove-red, fixtures + Dart reference reconciler (HEAD, fixture files and manifest carried over):

```
flutter test --plain-name "S-004 every reconciliation fixture" test/sync_protocol_fixtures_test.dart
Expected: 'completed'
  Actual: 'abandoned'
  end_within_one_second.json
test/sync_protocol_fixtures_test.dart 647
gateway: prove-red: RED AT HEAD (exit 1).
```

prove-red, Dart twin (HEAD, test file carried over): four of the five new tests red, each on the
assertion it guards —

```
Expected: <true>  Actual: <false>            (S-15408 inside the tolerance, applied)
Expected: WatchSessionStatus.completed
  Actual: WatchSessionStatus.abandoned       (S-15408 exactly at the tolerance)
Expected: WatchSessionStatus.completed
  Actual: WatchSessionStatus.abandoned       (S-15408 snapshot, one second earlier)
+1 -4: Some tests failed.                    (the 3 s case passes at HEAD: no tolerance needed)
```

prove-red, Swift engine (HEAD, test file carried over):

```
swift test --package-path watch/watchos --filter WatchEndedIsFinalTests.testS15408
WatchEndedIsFinalTests.swift:327: error: ... XCTAssertEqual failed: ("Optional("a ...   (1 s, lifecycle)
WatchEndedIsFinalTests.swift:352: error: ... XCTAssertEqual failed: ("Optional("a ...   (1 s, snapshot)
WatchEndedIsFinalTests.swift:357: error: ... XCTAssertEqual failed: ("Optional(20 ...   (recordedAt)
Executed 1 test, with 6 failures (0 unexpected) in 0.203 seconds
gateway: prove-red: RED AT HEAD (exit 1).
```

Green:

```
flutter test --plain-name S-1540 test/watch_session_adoption_bridge_test.dart
+5: All tests passed!                                        (S-15405..S-15407 + S-15403/S-15404)

flutter test --plain-name S-15408 test/watch_session_engine_test.dart
+5: All tests passed!

flutter test --plain-name "S-004 every reconciliation fixture" test/sync_protocol_fixtures_test.dart
+1: All tests passed!

swift test --filter WatchEndedIsFinalTests
Executed 13 tests, with 0 failures (0 unexpected) in 0.036 seconds
```

The two pre-existing Swift tests that encode sub-2 s margins moved to a clear one
(`testS14650AnEarlierDiscardBeatsALaterCompletionInEitherOrder` 60 s → 57 s,
`testS14650ALaterDiscardLosesToAnEarlierCompletionInEitherOrder` 61 s → 63 s); no assertion changed
meaning.

Replay corpus unchanged (no recording's outcome moved with the tolerance):

```
swift test --filter WatchReplayTests
Executed 4 tests, with 0 failures
S-15208 differential Swift replay: trace-s14501, trace-s14503, trace-f2..f7, trace-a1, trace-a2,
seed-1, seed-7, seed-50, seed-111, seed-408, seed-857 — classes: none
```

`WatchLiveMirroringTests` (every manifest scenario replayed through the Swift engine):
Executed 11 tests, with 0 failures.

## Phase 3 — D (Health re-write restores the previous span, S-15409/S-15410)

Shape: `rewriteWorkout` reads the activity kind before the delete, wraps the new write in
try/catch, and on a false or thrown write calls `_restorePreviousSpan`, which writes
`startedAtMs..previousEndedAtMs` with the same draft and re-applies the rating. The ledger is never
touched, so a failed move neither claims a workout nor blocks the next catch-up. The delete stays a
window delete: `HealthPlatformService.deleteWorkouts(start, end)` is the only delete API and an
id-scoped delete needs native plugin code (A-154-02).

`test/health_platform_test.dart`'s `_FakeHealthPlatform` gained `failWriteCalls` / `throwWriteCalls`
/ `writeCalls`, so a test can fail exactly one write instead of every write.

prove-red (HEAD, tests carried over — S-15409 fails because the span is gone):

```
flutter test --plain-name S-15409 test/health_platform_test.dart
Expected: an object with length of <1>
  Actual: []
S-15409 a rewrite whose new write fails puts the previous span back
Expected: an object with length of <1>
  Actual: []
S-15409 a rewrite whose new write throws restores the span too and swallows the throw
+0 -2: Some tests failed.
gateway: prove-red: RED AT HEAD (exit 1).
```

(S-15410 passes at HEAD by design: a refused delete already returns before any write; the test pins
`writeCalls == 1` so the restore cannot fire on that path.)

Green:

```
flutter test --plain-name "plan 146c" test/health_platform_test.dart
+11: All tests passed!     (S-14670 x5, S-14671 x3, S-15409 x2, S-15410; the group's earlier tests green)
```

## Phase 4 — docs and sweep

`docs/state_management/services_and_utils.md`: the moved-end invariant now states the window delete's
reason (no workout id in the platform contract), the activity kind read before the delete, and the
restore on a failed write, and names `S-15409` / `S-15410`. No other doc states the earlier-end rule
(that lives in `watch/sync_protocol/PROTOCOL.md`, amended in Phase 2), and no screen, route, widget or
state-class surface changed, so `docs/navigation_and_screens.md`, `docs/state_management.md` and
`docs/widget_catalog.md` need no update.

200-seed sweep (`test/watch_convergence_random_test.dart`, unchanged and untouched):

```
flutter test test/watch_convergence_random_test.dart
+15: All tests passed!
S-14509 contract: 200 seeds; 184 converge on every trace; 10 diverge on a trace the shipping app can
perform [29, 43, 94, 95, 117, 124, 134, 149, 161, 193]; 2 on a heal stall alone [86, 184]; 4 only
after the harness-only re-assert [33, 89, 138, 142]
```

The same sweep at HEAD (`prove-red HEAD test test/watch_convergence_random_test.dart`, verdict GREEN AT
HEAD — it is a measurement, not a guard): 200 seeds, 184 converge, the SAME 10 shipping-app seeds
`[29, 43, 94, 95, 117, 124, 134, 149, 161, 193]`, 4 harness-only re-assert, and 2 heal-stall seeds
`[114, 187]` instead of `[86, 184]` — the A-146-15 id-derived skew drift, same count.

So: 10 shipping-app divergences before and after, inside the `shippingRatchet` of 14 (computed as
`kSeedCount * 14 / 200`, which scales for a soak). The ratchet was not touched.

## Final verification

```
flutter analyze                     181 issues      (= HEAD: 181, measured by prove-red HEAD lint)
flutter test                        +7509 ~5: All tests passed!   (0 failed, 5 skipped)
swift test --package-path watch/watchos
  Executed 1419 tests, with 0 failures (0 unexpected)
  S-15208 differential Swift replay: 16 recordings — classes: none
flutter test test/ui_standards_contract_test.dart
  41 tests: All tests passed!
```

Lint: none of the 181 names a file this plan touched (`lib/core/sync_protocol/end_skew.dart`,
`session_reconciler.dart`, `watch_session_adoption_bridge.dart`, `watch_session_engine.dart`,
`health_sync_service.dart`, `test/health_platform_test.dart`, the two bridge/engine test files); the
count equals HEAD's, so nothing was added.

Residue sweeps: no literal `2000` / `Duration(seconds: 2)` in the three Dart rule sites (all go
through `end_skew.dart`), no `1500` left in `test/watch_session_engine_test.dart`, and the only
`addingTimeInterval` comparisons in the Swift engine are the two D-15403 sites, both using
`endSkewTolerance`. `grep "import .*hive_workout_repository" lib/...` returns only `lib/main.dart`
(the composition root), never `lib/state`, `lib/features`, `lib/widgets` or `lib/core`.



