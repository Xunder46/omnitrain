# Evidence — the rest ping works on the watch too, from the one setting on the phone (22)

Companion to `2026-10-08-22-rest-ping-on-watch-plan.md`. Implementers write the suite output and the
red→green tables here; the plan keeps one line per item and Assumption Log entries of at most 3 lines.
Suite output, not claims: paste the pass/fail counts.

## Baselines (recorded by the governor before the first phase)

| Check | Baseline |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (flutter, full) | 4152 passing, ~1 failing (pre-existing) |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 359 passing, 0 failing |
| `.github/copilot/scripts/macos/gateway.sh lint` (`flutter analyze`) | 196 issues, 0 errors (pre-existing infos) |

Record the same three numbers at the end of each phase and state the delta. A phase that moves one of them
without saying why is a finding. `test/docs_indexing_contract_test.dart` hard-fails above 64 KiB per doc and
warns above 80% (≈51.2 KiB); `docs/state_management/watch_surface.md` is the doc to watch in plan 22b.

## Red → green

The red column is the failure observed at the base commit for that scenario; the green column is the
passing run after the phase. `S-241` is the happy path and is covered on both clients and by the phone
fixture.

| Scenario | Phase | Red (observed) | Green (suite output) | Test file · test name |
|---|---|---|---|---|
| S-241 interval 30, rest open to 100 | 1 | file absent at the base commit: the table and the test are both new, so the first run was `FileSystemException: ... watch_rest_ping_contract.json` (no table to read) | 8/8 `rest_ping_contract_test.dart`; full suite 4163 passing, 0 failing | `test/rest_ping_contract_test.dart` · `S-241 one-second polls S-241 an interval of 30 polled every second from 0 to 100 pings at 30, 60 and 90 and nowhere else` |
| S-241 interval 30 (Apple Watch) | 2 | compile red before implementation — the type is new, so the file does not load: `cannot find type 'WatchRestPing' in scope`, `value of type 'WatchPhonePreferences' has no member 'restPingSeconds'`, `value of type 'WatchHaptics' has no member 'playRestPing'` (5 errors). The `boundary > lastPinged` clause proved by mutation M1 (11 failures) | 17/17 `WatchRestPingTests`, 0 failures; full `swift-test` 376/0 | `WatchRestPingTests.swift` · `testS241AnIntervalTapsAtItsMultiplesAndNowhereElse` and `testS241TheTablesOwnExpectationIsEachMultiple` |
| S-242 interval 0 / never synced | 2 | mutation M4 (`interval > 0` → `interval == 0` returns true): 668 failures on the file, `("[0, 1, 2, …]") is not equal to ("[]")`; mutation M5 (`?? 0` → `?? 30`): 22 failures, `("30") is not equal to ("0")` | 17/17 | `WatchRestPingTests.swift` · `testS242WithTheIntervalOffNothingTaps`, `testS242AWristThatNeverSyncedReadsOff` |
| S-243 rest ends at 45, Next | 2 | mutation M1 (a gap counts up to the boundary it crossed) | 17/17 | `WatchRestPingTests.swift` · `testS243AGapTapsOnceForTheBoundariesItCrossed` |
| S-244 interval arrives with a copy | 2 | mutation M1 (a lowered interval re-fires the pinged boundary) | 17/17 | `WatchRestPingTests.swift` · `testS244ALoweredIntervalDoesNotRefireAPingedBoundary`, `testS244TheNextUnpingedBoundaryOfTheLoweredIntervalStillTaps` |
| S-245 two rests, row turnover | 2 | mutation M2 (the per-rest reset removed): `("[]") is not equal to ("[30, 60, 90]") — S-245: the next rest row pings` | 17/17 | `WatchRestPingTests.swift` · `testS245ANewRestRowStartsFromZero` |
| S-246 the wire carries the interval | 1 | compile red before implementation: `No named parameter 'restPingSeconds'` (the parameter is new, so the file cannot load) — guard proved by mutation instead (below) | 8/8 `rest_ping_contract_test.dart` | `test/rest_ping_contract_test.dart` · `S-246 the wire S-246 the payload carries the interval the table names, and the protocol accepts it` and `... two intervals stamped in one millisecond are two messages, and a rebuild is one` |
| S-247 the wrist stores and reads it | 2 | mutation M7a (`!CFNumberIsFloatType` dropped) over the strengthened test: `XCTAssertFalse failed - 90.0 is not a whole number of seconds`; mutation M7b (`number.intValue >= 0` dropped): `("−30") is not equal to ("90")` | 17/17 | `WatchRestPingTests.swift` · `testS247TheWristStoresTheIntervalItReceives`, `testS247TheRecordRoundTripsAndARowWithoutTheKeyReadsOff`, `testS247AMalformedIntervalIsRefusedAndNothingIsStored` |
| S-248 the phone sends the current setting | 1 | compile red before implementation: `No named parameter 'restPingSeconds'` / `Undefined name 'WatchTransportRequest'`; guard proved by mutation instead | 8/8 `rest_ping_contract_test.dart` | `test/rest_ping_contract_test.dart` · `S-248 the phone sends the interval it holds S-248 a wrist sync is answered with the Rest Ping setting the phone holds` |
| S-221 same second pinged once | 1, 2 | compile red before implementation (same named parameter) | 8/8 `rest_ping_contract_test.dart`; `WatchRestPingTests` 17/17, and the once-per-boundary clause proved red by mutation M1 (11 failures, this scenario among them) | rule tests (phone, Swift): `S-221 the same second polled twice S-221 a second polled three times pings once`; `WatchRestPingTests.swift` · `testS221ASecondPolledThreeTimesPingsOnce` |
| S-222 interval lands mid-rest | 2 | mutation M1 (the mid-rest interval pings the boundary that fell before it arrived) | 17/17 | `WatchRestPingTests.swift` · `testS222TheIntervalArrivingMidRestTapsFromItsNextBoundary` |
| S-223 large interval (180) | 1, 2 | compile red before implementation (same named parameter); the interval row mutated in Phase 1 | 8/8 `rest_ping_contract_test.dart`; `WatchRestPingTests` 17/17 | rule tests (phone, Swift): `S-223 a long interval S-223 an interval of 180 over 0 to 200 pings once, at 180`; `WatchRestPingTests.swift` · `testS223ALargeIntervalTapsAtItsFirstBoundary` |
| S-224 a closed rest is never evaluated | 2 | mutation M6 (`guard let elapsed` dropped, `elapsed ?? interval`): `XCTAssertFalse failed - S-224: a closed rest pings nothing, however much of it the rule walked` | 17/17 | `WatchRestPingTests.swift` · `testS224AClosedRestIsNeverEvaluated` |
| S-225 the ping is not the countdown path | 2 | mutation M1 (the ping fires where the table says none is owed) | 17/17 `WatchRestPingTests`; `WatchLoggingTimersTests` unchanged and green | `WatchLoggingTimersTests.swift` (S-164A) + `WatchRestPingTests.swift` · `testS225ThePingIsItsOwnEventAndNotACountdownAlert` |

Red for a *new* rule type is the new test file's first run at the base commit: with the type absent, the
test does not compile — record that run's output, not a later one. For the fixtures, red is the schema walk
failing on a payload without the key.

## Phase evidence

### Phase 1 — contract and phone (@developer)

- `.github/copilot/scripts/macos/gateway.sh lint`: **196 issues, 0 errors** — the baseline, unchanged. One
  new notice appeared in the new test file (`prefer_collection_literals` at `rest_ping_contract_test.dart`,
  a `[...].toSet()` that is now a set literal) and was fixed before the count was taken; the run before the
  fix read 197.
- `.github/copilot/scripts/macos/gateway.sh test <the five suites>`: **157 passed, 0 failed**
  (`.work/gateway/test-20261008-154035-88064.log`, `All tests passed!`). The three new invalid fixtures are
  each refused as the manifest states — `preferences_down_negative_rest_ping.json` as
  `constraint_violation`, `..._string_rest_ping.json` as `invalid_type`, `..._missing_rest_ping.json` as
  `missing_required_field` — and the valid fixture still conforms.
- `.github/copilot/scripts/macos/gateway.sh test` (full suite, end of phase): **4163 passed, 1 skipped,
  0 failed** (`.work/gateway/test-20261008-154404-89940.log`, `All tests passed!`). Against the 4152-passing
  baseline that is +11 passing and no failures; the skip is pre-existing.
- `.github/copilot/scripts/macos/gateway.sh swift-test`: **359 tests, 0 failures**
  (`.work/gateway/swift-test-20261008-154121-88448.log`) —
  the baseline count, unchanged. `SyncProtocolFixturesTests.testEveryInvalidFixtureIsRejectedAsStated` walks
  the manifest's invalid register, so the three new fixtures are refused by `SyncProtocolValidator` too, with
  the same codes and messages.
- Diff versus Predicted Files: all nine changed files are predicted. `WatchSessionStartPathsTests.swift` and
  `WatchFileStoreTests.swift` are predicted but needed no change: both build their payloads through the
  shared `preferencesDown` helper, and the stored `WatchPreferencesRecord` has no rest-ping field until
  Phase 2. No file outside the list was touched; `git-diff --stat` is 63 insertions, 14 deletions across
  nine files.
- Assumption Log entries added: two (the wrist-side scope boundary; the table-versus-phone rule divergence).

#### Prove-red (mutations)

The new guards cannot be proved by a base-commit run: `restPingSeconds` is a new named parameter and the
table is a new file, so the test file does not compile at `53f3f2be` — the red run was a load error, not an
assertion. Each guard was therefore proved by mutation: the original line was recorded, changed, the test
seen to fail for the stated reason, then restored exactly and re-run green (contract file 8/8; the four
files together 140 passed, `.work/gateway/test-20261008-154325-89384.log`).

| Mutation (original → changed) | Test red | Observed |
|---|---|---|
| `watch_reference_sync.dart` `'restPingSeconds': restPingSeconds,` → `'restPingSecondsX': ...` | `S-246 the payload carries the interval…`, `S-248 a wrist sync is answered…` | `is missing map key 'restPingSeconds'`; `restPingSecondsX: 90` / `45` |
| `watch_reference_sync.dart` id `'${…'off'}-$restPingSeconds'` → without `-$restPingSeconds` | `S-246 two intervals stamped in one millisecond are two messages…` | `Expected: not 'msg-preferences-1791460800000-off'` |
| `watch_rest_ping_contract.json` S-223 row `"intervalSeconds": 180` → `90` | `S-223 an interval of 180 over 0 to 200 pings once, at 180` | `Expected: [180]  Actual: [90, 180]` |
| `watch_sync_request_handler.dart` `restPingSeconds: _settings.restPingInterval,` → `0` | `S-248 a wrist sync is answered with the Rest Ping setting the phone holds` | `at ['restPingSeconds'] is <0> instead of <45>` |
| `preferences_down.schema.json` `"minimum": 0` → `-100` | `sync_protocol_fixtures_test.dart` `invalid/preferences_down_negative_rest_ping.json is rejected as constraint_violation` | `Expected: non-empty  Actual: []` (the payload is accepted once the floor is gone) |

### Phase 2 — Apple Watch (@developer)

- Phase 0 red, recorded before any implementation: `swift-test --filter WatchRestPingTests` on the new test
  file and the untouched sources → **red by compilation** (`cannot find type 'WatchRestPing' in
  scope`, `value of type 'WatchPhonePreferences' has no member 'restPingSeconds'`, `value of type
  'WatchHaptics' has no member 'playRestPing'`, `value of type 'RecordingHaptics' has no member
  'restPings'`). No assertion had run, so each guard below is proved by mutation.
- `.github/copilot/scripts/macos/gateway.sh swift-test` (full package, end of phase): **376 tests, 0
  failures** (`.work/gateway/swift-test-20261008-160305-6214.log`, `Executed 376 tests, with 0 failures`).
  Against the 359-passing baseline that is **+17, no failures** — the whole of `WatchRestPingTests`. The
  touched filter alone: `swift-test --filter WatchRestPingTests` → `Executed 17 tests, with 0 failures` (run
  at 16:02:55; the output was under the gateway's size threshold, so no log file was written).
- `.github/copilot/scripts/macos/gateway.sh lint`: **196 issues, 0 errors** — the stated baseline, unchanged
  (`.work/gateway/lint-20261008-160310-6316.log`); no Dart file changed in this phase, and no issue is
  reported in a file this phase touched (all of them Swift, outside `flutter analyze`).
- Project invariant: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets
  lib/core` → no matches. `WatchTimerHaptics.poll` untouched, and no `WatchTimerMilestone` case added
  (D-244, D-251): `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` and
  `WatchSessionStartPathsTests.swift` pass unmodified.
- Governor's `xcodebuild` of the "OmniTrain Watch App" scheme: **not run here** — it is the governor's, and
  it is the only check that compiles `WatchRestView` and `WristHaptics`, which sit behind `#if os(watchOS)`
  and are therefore not built by `swift-test` on macOS.
- Diff versus Predicted Files: all eight predicted paths are present.
  `git-diff --stat` for the six already-tracked ones:
  `ContentView.swift | 6 ++-` · `WatchLoggingModel.swift | 12 +++++-` · `WatchLoggingView.swift | 6 +++` ·
  `WatchPhonePreferences.swift | 43 ++++++++++++++++++++--` · `WatchRestView.swift | 39 +++++++++++++++++++--` ·
  `Fixtures.swift | 13 +++++++`. The other two — `WatchRestPing.swift` and `WatchRestPingTests.swift` — are
  new and untracked, so they do not appear in the stat. No file outside the list was touched by this phase.
- Assumption Log entries added: two (the redundant `boundary > 0` clause; the strengthened S-247 float
  case).
- Docs: **no update required** — D-247 moved the convention row, the three feature docs and
  `watch_surface.md` to plan 22b, and this phase changes no documented behaviour on a surface the docs
  describe (the watch's rest screen's own doc page arrives with 22b).

#### Prove-red (mutations)

`prove-red` cannot be used at the base commit: `WatchRestPing` is a new type, so at `HEAD` the new test file
does not compile — the red run is a load error, not an assertion. Every guard was therefore proved by
mutation: the original line recorded, changed, the assertion seen to fail for the stated reason, restored
**exactly**, and the file re-run green (`swift-test --filter WatchRestPingTests`, `Executed 17 tests, with 0
failures`).

| Mutation (original → changed) | Test red | Observed |
|---|---|---|
| `WatchRestPing.swift` `guard boundary > 0, boundary > lastPinged` → `guard boundary > 0` | S-221, S-222, S-223, S-225, S-241, S-243, S-244, S-245 | 11 failures: every once-per-boundary assertion, e.g. `("[30, 60, 90]") is not equal to ("[30, 60, 90, …]")` |
| `WatchRestPing.swift` the `if pingingRestId != restId { … lastPinged = 0 }` block → removed | S-245 | `("[]") is not equal to ("[30, 60, 90]") — S-245: the next rest row pings` |
| `WatchRestPing.swift` `boundary > 0` → `boundary >= 0` | *none* | **survived** — see Assumption 1: with `lastPinged` starting at 0 the clause is an equivalent mutant, not an unproven guard |
| `WatchRestPing.swift` `guard interval > 0 else { return false }` → `if interval == 0 { return true }` | S-242 (both) | 668 failures; `("[0, 1, 2, … 600]") is not equal to ("[]") — S-242: Off never taps, however long the rest runs` |
| `WatchPhonePreferences.swift` `current?.restPingSeconds ?? 0` → `?? 30` | S-242, S-247 | 22 failures; `("30") is not equal to ("0") - S-242: a wrist that never synced reads`, `… - before the first sync` |
| `WatchRestPing.swift` `guard let restId, let elapsed else { return false }` → `guard let restId else { return false }` + `let running = elapsed ?? interval` | S-224 | `XCTAssertFalse failed - S-224: a closed rest pings nothing, however much of it the rule walked` |
| `WatchPhonePreferences.swift` `!CFNumberIsFloatType(number),` → removed | S-247 | first run **survived** (no case covered a JSON `90.0`); after the test gained that case: `XCTAssertFalse failed - 90.0 is not a whole number of seconds` |
| `WatchPhonePreferences.swift` `number.intValue >= 0` → removed | S-247 | `XCTAssertFalse failed - fixtures/invalid/preferences_down_negative_rest_ping …`; `("-30") is not equal to ("90") - S-247: nothing malfo…` |

After the last mutation the file was restored and re-run green: `Executed 17 tests, with 0 failures`; the
full package then ran 376/0. No mutation is left applied (`grep MUTATION` over `watch/` and `ios/` → no
matches).

- Phase 3 (the Wear mirror, the Settings copy, the rule and the docs) moved whole to plan 22b; its evidence
  lives in `2026-10-08-22b-rest-ping-wear-settings-docs-plan.evidence.md`.

## Fix round 1 — review findings 1, 6, 7, 8 (@developer, brief `.work/watch-22/brief-fix-1.md`)

Base commit `53f3f2be`. Findings 2–5 belong to plan 22b and were not touched. Four items, no production
code changed (`lib/core/utils/rest_ping_utils.dart` is not in `git-diff --stat`).

| Finding | Change | Result |
|---|---|---|
| F1 | `docs/theme_and_settings.md` — deleted the clause ", and the wrist owes no alert for a rest at all" from the timer-alert bullet; the sentence keeps no claim about what the wrist owes | `git-diff --stat`: 1 insertion, 1 deletion |
| F6 | plan `§Existing-Functionality Impact` row 1 reader list — added `watch/contract/watch_effort_rating_contract.json` (`preferencesField: effortRatingPrompt`) and `watch/contract/watch_capture_contract.json` (four `preferences` ops) | one row edit, nothing else in the plan |
| F7 | `test/rest_ping_contract_test.dart` — S-242 (Off) and S-244 (mid-rest lowering) now driven through `_phoneTaps`, one `test()` each named with its S-id; header corrected to name only the rows still not driven (S-243's gap, S-222's second poll) | file 10 passed / 0 failed (was 8); both rows match the table, so no row was bent |
| F8 | `watch/sync_protocol/PROTOCOL.md` — one clause in the `restPingSeconds` bullet: a fractional value (`90.5`) and a JSON number written with a fraction (`90.0`) are refused on the wrist, the phone always sends an integer (cited `testS247AMalformedIntervalIsRefusedAndNothingIsStored`) | no code change, no new fixture |

### Prove-red

`prove-red` is not usable here: the new rows are asserted by a test file whose table
(`watch/contract/watch_rest_ping_contract.json`) is untracked at `HEAD`, so the run at base is a load error,
and the rule under test (`shouldFireRestPing`) is not changed by this round — no test can be red at base for
a change that is not in the rule. Both new guards were therefore proved by mutation: original line recorded,
changed, the S-242/S-244 assertion seen to fail for the stated reason, restored **exactly**, re-run green.

| Mutation (`lib/core/utils/rest_ping_utils.dart`) | Test red | Observed |
|---|---|---|
| `if (interval == 0) return false;` → `return true;` | S-242 | `Expected: []  Actual: [0, 1, 2, … 600]` — "S-242 Off taps on no second, however long the rest runs" |
| `if (elapsed % interval != 0) return false;` → `if (elapsed % interval != 0 && elapsed != 70) return false;` (the poll right after the lowering pings the boundary that fell before it arrived) | S-244 | `Expected: [60, 90]  Actual: [60, 70, 90]` — "S-244 a boundary already pinged is not pinged again when the interval is lowered past it" |

After both mutations the file was restored and re-run green: `test/rest_ping_contract_test.dart` **10 passed,
0 failed**; `git-diff --stat` does not list `rest_ping_utils.dart`.

### Verification (real counts)

- `.github/copilot/scripts/macos/gateway.sh test test/rest_ping_contract_test.dart test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart`
  → **28 passed, 0 failed** (`All tests passed!`), so F1's two doc guards stay green.
- `.github/copilot/scripts/macos/gateway.sh test` (full suite) → **4165 passed, 1 skipped, 0 failed**
  (`All tests passed!`; `.work/gateway/test-20261008-161804-14507.log`). Against the plan's Phase-1 end
  (4163 passing) that is +2 — the two new S-242/S-244 tests — and no failure.
- `.github/copilot/scripts/macos/gateway.sh lint` → **196 issues, 0 errors** — the stated baseline, unchanged
  (`.work/gateway/lint-20261008-161756-14424.log`); no issue is reported in a file this round touched.
- Project invariant: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`
  → no matches.
- No `.swift` file changed, so `swift-test` was not run.

