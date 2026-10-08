# Evidence — 19a, the phone is the authority for the shared session

Companion to `2026-10-08-19a-phone-authority-plan.md`. Executors paste evidence here;
the code reviewer reads it instead of trusting the Progress line. Claims go in the plan,
pasted command output goes here.

Bound by `docs/global_conventions.md`. Every command is run through the gateway, spelled
`.github/copilot/scripts/macos/gateway.sh`; output over 200 lines or 16 KB lands under
`.work/gateway/` and only its summary and log path belong here.

## Baselines (recorded by the planner, 2026-10-08 — do not re-measure without cause)

| Check | Baseline at plan time | How to read a phase's result |
| --- | --- | --- |
| `gateway.sh test` (full suite) | 4070 tests, 1 pre-existing failure | the phase must add cases and leave exactly that one failure |
| `gateway.sh swift-test` | 335 tests, 0 failures | any failure is the phase's own |
| `gateway.sh lint` | 196 issues, 0 errors | compare the count; an increase is a finding |

The full suite takes several minutes: run it with its own 900 s timeout, never inside a phase
that can be judged by three files.

## How this file is filled

One block per phase, in order, each with: the item number, the file and symbol touched, the
command that shows it, and the pasted result (counts, not adjectives). Scenario rows carry the
S-id the test names. A phase is not closed until its block exists.

## Phase 1 — the watch refuses a second session

Baseline for this phase (brief, at base `996130a` = HEAD; the plan's own baseline row above is from plan time and the suite has grown since): `gateway.sh test` → `+4078 ~1`, 0 failures; `gateway.sh swift-test` → 335 tests, 0 failures; `gateway.sh lint` → 196 issues.

| # | Item (file · symbol) | Command | Result |
| --- | --- | --- | --- |
| 1, 2–3 | `lib/watch/session/watch_session_engine.dart` · `createSession` (refusal, D-171/D-177); `lib/watch/start/watch_session_start_paths.dart` · `startFromRoutine` (absorb into a held active empty session) — `startFreeWorkout` took no edit: the engine's refusal already covers it | `gateway.sh test test/watch_session_engine_test.dart test/watch_session_start_test.dart` | `All tests passed!` (+77) |
| 4–5 | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` · `createSession`; `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` · `startFromRoutine` (absorb) — `startFreeWorkout` unchanged, the engine refuses | `gateway.sh swift-test` | 340 tests, 0 failures (335 + the 5 new) |
| 6–7 | `test/watch_session_engine_test.dart` (S-176 ×2), `test/watch_session_start_test.dart` (S-170, S-177, S-178); `WatchSessionEngineTests.swift` (S-176 ×2), `WatchSessionStartPathsTests.swift` (S-170, S-177, S-178) | the two commands above | 10 new cases: 5 Dart, 5 Swift |
| 8 | existing-test repairs (Trap 1) | `gateway.sh test test/watch_sensor_recording_test.dart` / `gateway.sh swift-test` | Dart `+37` green; Swift 340/0. Dart: `test/watch_sensor_recording_test.dart` "starting a session closes the workout the last one left open" gained `await engine.finishSession();` between its two starts. Swift: `WatchSensorRecordingTests.testStartingASessionClosesTheWorkoutTheLastOneLeftOpen` (it runs a second time through its subclass `WatchSensorRecordingStepsDeniedTests`) gained `_ = await engine.finishSession()` between its two starts. No other existing case started a second session on a live engine — the first full run reported exactly this one failure. |

Full suite at the phase's head: `gateway.sh test` → `01:56 +4083 ~1: All tests passed!` (4078 + 5 new, 1 pre-existing skip, 0 failures).
The same command before the item-8 repair: `+4082 ~1 -1`, the one failure being the Dart victim above.
`gateway.sh lint` → `196 issues found.` (baseline; no issue line names a file this phase touched).
Invariant sweep: `import .*hive_workout_repository` under `lib/state lib/features lib/widgets lib/core` → no matches.

Red-at-base evidence (item 8) — Dart, base `996130a`, log `.work/gateway/test-20261007-235101-86980.log`:

```
$ .github/copilot/scripts/macos/gateway.sh prove-red 996130a test test/watch_session_engine_test.dart test/watch_session_start_test.dart
gateway: prove-red: RED AT 996130a (exit 1)
...
00:00 +49 -1: S-176 createSession on a live engine hands back w1, untouched [E]
  Expected: 'w1'
    Actual: 'w2'
  w2 never exists (D-177)
00:00 +49 -2: S-176 an empty second start is refused the same way [E]
  Expected: 'rec-1'
    Actual: 'rec-2'
00:00 +50 -3: S-177 startFreeWorkout on a live session returns it and emits nothing [E]
  Expected: 'rec-2'
    Actual: 'rec-3'
00:00 +50 -4: S-170 startFromRoutine on a session with exercises is refused too [E]
  Expected: 'rec-2'
    Actual: 'rec-3'
00:00 +50 -5: S-178 a routine fills an active empty session in place [E]
  Expected: an object with length of <1>
    Actual: [ {…'type': 'session_lifecycle', …msg-rec-2}, {…'type': 'session_lifecycle', …msg-rec-3} ]
     Which: has length of <2>
  no second started lifecycle (S-178)
00:00 +72 -5: Some tests failed.
```

Red-at-base evidence — Swift, base `996130a`, log `.work/gateway/swift-test-20261007-235523-92720.log`:

```
$ .github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --filter 'S176|S177|S170|S178' -- watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift
gateway: prove-red: RED AT HEAD (exit 1)
... Executed 5 tests, with 23 failures (0 unexpected)
WatchSessionEngineTests.swift:1816 S-176 hands back w1: XCTAssertEqual failed: ("w2") is not equal to ("w1") - w2 never exists (D-177)
WatchSessionEngineTests.swift:1817 S-176 hands back w1: XCTAssertEqual failed: ("rec-2") is not equal to ("rec-1") - the held row comes back
WatchSessionEngineTests.swift:1818 S-176 hands back w1: XCTAssertEqual failed: ("["u-row"]") is not equal to ("["u-squat", "u-press"]")
WatchSessionEngineTests.swift:1823 S-176 hands back w1: XCTAssertEqual failed: (lifecycle+snapshot ×2) is not equal to (lifecycle+snapshot) - no second started lifecycle, no snapshot (D-177)
WatchSessionEngineTests.swift:1828 S-176 hands back w1: XCTAssertEqual failed: ("2") is not equal to ("1") - the row store still holds one row (S-176)
WatchSessionEngineTests.swift:1834 S-176 hands back w1: XCTAssertEqual failed: (Optional("rec-2")) is not equal to (Optional("rec-1")) - the session getter still answers w1
WatchSessionEngineTests.swift:1849/1850/1854/1859 S-176 empty second start: rec-2 vs rec-1; [] vs [u-squat, u-press]; 2 lifecycles vs 1; 2 rows vs 1
WatchSessionStartPathsTests.swift:533 S-177: XCTAssertEqual failed: ("rec-3") is not equal to ("rec-2") - the held session comes back, not a second one (D-177)
WatchSessionStartPathsTests.swift:504 S-177: ("[]") is not equal to ("["sx-eff-bench", "sx-eff-plank", "sx-eff-pullup"]")
WatchSessionStartPathsTests.swift:508 S-177: (lifecycle,snapshot,lifecycle,snapshot) is not equal to (lifecycle,snapshot) - a refused start emits nothing at all (S-177)
WatchSessionStartPathsTests.swift:513 S-177: ("2") is not equal to ("1") - and appends no row
WatchSessionStartPathsTests.swift:519 S-177: (Optional("rec-3")) vs (Optional("rec-2"))
WatchSessionStartPathsTests.swift:533/544/545 S-170: rec-3 vs rec-2; ladder 4 vs 2; rows 2 vs 1
WatchSessionStartPathsTests.swift:587/592/607/608/609 S-178: 2 started lifecycles vs 1; [lifecycle, snapshot] vs [snapshot]; rec-4 vs rec-3; index 0 vs 3; 6 frames vs 4
```

Cross-stack parity table — the fixtures both suites build, and their assertions:

| Fixture | Dart assertion | Swift assertion | Both green |
| --- | --- | --- | --- |
| held active session `w1`/`rec-1` with `u-squat`, `u-press`; second `createSession` returns it: same id, same record id, ladder unchanged, frames and rows unchanged (and again for an empty second start) | S-176 ×2 in `test/watch_session_engine_test.dart` | `WatchSessionEngineTests.swift` S-176 twin ×2 | yes |
| held active session (routine `routine-push-a`, 3 slots); `startFreeWorkout()` returns it, 0 frames, 0 rows | S-177 in `test/watch_session_start_test.dart` | `WatchSessionStartPathsTests.swift` S-177 | yes |
| held active session with the routine's ladder; `startFromRoutine("routine-push-a")` returns it unchanged (3 slots), 0 frames, 0 rows | S-170 beside S-177 | `WatchSessionStartPathsTests.swift` S-170 | yes |
| held active EMPTY session; `startFromRoutine("routine-push-a")` fills it in place: same session id, the contract's 3 `expectedSlots` in template order, position 0, same `startedAt`, exactly one `session_lifecycle`, every new frame a `session_snapshot`, all rows one session id, then S-171's free start still refused | S-178 (+S-171) in `test/watch_session_start_test.dart` | `WatchSessionStartPathsTests.swift` S-178 (+S-171) | yes |

Each slot is compared field by field (`sessionExerciseId`, `exerciseId`, `name`, `capabilities`, `effortKind`): a slot carries no `targets`, the routine's targets stay on the phone, so "one target each" is not observable at the slot.

## Phase 2 — the phone resets the wrist

Base for this phase: `6c5da29` (HEAD when the brief was written; Phase 1's head). Baselines at that base: `gateway.sh test` → `+4083 ~1`, 0 failures; `gateway.sh lint` → 196 issues, 0 errors; `gateway.sh swift-test` → 340 tests, 0 failures (not re-run: no `.swift` file is in this phase's Predicted Files).

| # | Item (file · symbol) | Command | Result |
| --- | --- | --- | --- |
| 1 | `live_session_mirror_state.dart` · `owesResetFor`, `watchSessionPlaceholderId` | `gateway.sh test test/watch_session_auto_push_test.dart` | `All tests passed!` (42 cases: 37 pre-existing incl. S-85/S-86/S-87, 5 new); also green in the two-file run below |
| 2–3 | `watch_session_auto_push.dart` · `_pushOnce`, `_announceEnd` (returns the ids it announced an end for) | the same file's S-172/S-180/S-181 cases | S-172, S-180, S-181 A/B green |
| 4–5 | `watch_sync_wiring.dart` · `WatchSyncGraph.sync()` (placeholder map uses `watchSessionPlaceholderId`) | S-182, plus `test/watch_session_projection_test.dart` S-109 A/B/C unchanged | S-182 green; S-109 A/B/C green; S-183 A/B green (new group) |
| 6–7 | `test/watch_session_auto_push_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_session_adoption_bridge_test.dart` | `gateway.sh test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart` → `All tests passed!` (84); `gateway.sh test test/watch_session_projection_test.dart test/watch_session_finish_test.dart` → `All tests passed!` (50) | 7 new cases total (S-172, S-180, S-181 A/B, S-182, S-183 A/B); the adoption-bridge file is covered by the full suite below, not run on its own |

Frame logs (verbatim from the runs; `s-1` is the wrist's live session in the S-172/S-180/S-182 fixtures, `session-<t>` the phone's own):

```
S-172  pass 1 (pair disagrees): ['lifecycle:s-1', 'snapshot:session-<t>', 'request:snapshot']
S-180  pass 1 (send throws): [] — the failure reported once, nothing carried; pass 2 (retry):
       ['lifecycle:s-1', 'snapshot:session-<t>', 'request:snapshot']; then sync() and a final
       flush(): by S-182's own rule an agreeing pair sends no lifecycle, and S-180's last
       assertion — 'owed by nobody once the pair agrees' — holds: no second 'abandoned'
S-182  first sync(): ['lifecycle:s-1', 'snapshot:session-<t>', 'request:snapshot']; second sync():
       ['snapshot:session-<t>', 'request:snapshot'] — no lifecycle
S-181  pair agrees: [] (compared with the base's own frames: nothing added)   placeholder: []
       — nothing at all, and no frame in the whole run names 's-phone-unjoined'
```

`prove-red 6c5da29 test test/watch_session_auto_push_test.dart` is **not** a valid proof for this file: the run reports `RED AT 6c5da29 (exit 1)` for a *load* error (`Undefined name 'watchSessionPlaceholderId'`), and the gateway's own rule is that a compile or load error means the test could not run there. The gateway's name filter does not help — the whole file must compile. Every guard below is therefore proved by a mutation, each recorded with its original line, run, and restore.

Mutation table — each row is a one-line change in the working tree, the suite run, and the
scenario that must go red:

| Mutation | Command | Expected red | Observed |
| --- | --- | --- | --- |
| predicate becomes `!!mirror.isActive` (the plan's own row) | `gateway.sh test test/watch_session_auto_push_test.dart` (whole file, mutation in the tree) | S-180, S-182 | **S-180 red** for the guarded reason (`Expected: ['lifecycle:s-1', 'snapshot:…', 'request:snapshot'] Actual: []` — "an owed reset is not cleared by the attempt that failed", D-178); **S-182 stayed green** — its wrist is `active`, so the narrowed clause fires for it. Result `+41 -1`. Restored: `status != WatchSessionStatus.completed` |
| reset skips the snapshot when `encoded == _baseline` (the plan's own row) | the same command, `--plain-name "S-180"` | S-180 | **S-180 red**: `Expected: ['lifecycle:s-1', 'snapshot:…', 'request:snapshot'] Actual: ['lifecycle:s-1', 'request:snapshot']` — the retry carried the abandoned frame but dropped the phone's own state. Restored |
| predicate drops the placeholder clause (the plan's own row) | the same command, `--plain-name "S-181"` | S-181 | **S-181 case B red** (`D-173`: "the mirror holds the placeholder, which is not a session"), actual frame `{'type': 'session_lifecycle', 'sessionId': 's-phone-unjoined', 'payload': {'state': 'abandoned'}}`; case A green. Result `+1 -1`. Restored |
| predicate drops `held != composedId` | the same command, `--plain-name "S-181"` | S-181 case A | **S-181 case A red** (`S-181 A the push of an agreeing pair sends no lifecycle`: an `abandoned('s-1')` appears on an agreeing pair), case B green. Result `+1 -1`. Restored |
| the both reset call sites disabled (`false &&`, `_pushOnce` and `WatchSyncGraph.sync()`) | the same command, `--plain-name "S-172"` | S-172, S-180, S-182 | **all three red**: S-172 `Actual: []`; S-180 "the failed pass is reported, once (D-98)" `Actual: []`; S-182 `Actual: ['snapshot:session-<t>', 'request:snapshot']` — the reset frame missing, which is the only mutation that proves the wiring's own call site. S-181 A/B green. Result `+2 -3`. Restored |
| `watch_session_engine.dart` · `_applyLifecycle` maps `abandoned` to the session's own status | `gateway.sh test test/watch_session_projection_test.dart --plain-name "S-183"` | S-183 case A | **S-183 case A red** (`Expected: 'abandoned' Actual: 'active'`), case B green (`+1 -1`). Restored to `WatchSessionStatus.abandoned`'s exact original line. This is S-183's proof: it guards *existing* engine behaviour, so no prove-red and no production change of this phase can turn it red |

An existing-test note (not a repair): the first targeted run reddened three pre-existing frame-count
cases — S-85 (`:1188`), S-87 (`:1366`, `:1426`) — with two extra `abandoned(W)` frames for a stale
wrist session. Trap 2 says exactly this: a red count there means the predicate is too wide. The
predicate was narrowed (see the Assumption Log), not the suite; all three are green and unedited in
the final run.

Full suite at the phase's head: `gateway.sh test` → `01:43 +4090 ~1: All tests passed!` (4083 + 7 new, 1 pre-existing skip, 0 failures).
The same command before the last one-line fix (a redundant `wire_timestamps.dart` import my new `watch_records.dart` import shadowed, the phase's only lint issue): `+4090 ~1`, also green.

## Phase 3 — the phone's screen follows an end from the watch

| # | Item (file · symbol) | Command | Result |
| --- | --- | --- | --- |
| 1–4 | `workout_session_screen.dart` · `initState`, `dispose`, the listener, `_pushSessionReplacement` | `gateway.sh test test/pr4_session_controls_test.dart` | |
| 5 | `workout_session_finish.dart` (only if the helper moves) | the same command plus S-185 part B | |
| 6–7 | `test/pr4_session_controls_test.dart`, `test/watch_session_finish_test.dart`, `test/session_screen_build_phase_notify_test.dart` | `gateway.sh test test/pr4_session_controls_test.dart test/watch_session_finish_test.dart test/session_screen_build_phase_notify_test.dart test/session_finish_timers_test.dart` | |

| Mutation | Expected red | Observed |
| --- | --- | --- |
| the `!editMode` clause is dropped | S-185 part A | |
| `endedAtMs != null` is ignored | S-174 | |

Widget-test discipline for every row above: Mock repository, `tester.pump()` only, no real
`Future.delayed`, no Hive harness inside `testWidgets`, no `pumpAndSettle` on the session
screen's one-second ticker.

## Phase 4 — docs, contract, residue sweep

Doc-sentence → test table (one row per added or rewritten sentence; a sentence with no test is
not written):

| File · line | Sentence (short) | Test that shows it |
| --- | --- | --- |
| | | |

Size measurements (the one file with a ceiling this feature presses):

| File | Bytes before | Bytes after | Band |
| --- | --- | --- | --- |
| `docs/state_management/watch_surface.md` | | | under 80% of 64 KiB (`test/docs_indexing_contract_test.dart`) |

Residue sweep (the exact grep and its output):

```
$ grep -n "each keeps its own" docs/ watch/
<only docs/watch_session_sync.md:497 (the rest-timer rule, 18b's territory) and docs/plans/ records may remain>
```

## Not covered by these checks (state it, never claim it)

- `ios/OmniTrain Watch App/ContentView.swift` (the SwiftUI app target and its `onWatchResume`
  wiring around `:167-180`) is outside `swift-test`; only the governor's `xcodebuild` watchOS
  simulator build covers it. A phase touching it must say so and ask the governor.
- A pair that never reconnects: the reset stays owed and each side keeps its own session.
  19b makes delivery durable.
- The Dart twin emits nothing when it applies a lifecycle (`watch_session_engine.dart:583`)
  while the Swift engine captures a session end for the frame's own id
  (`WatchSessionEngine.swift:584,609`). Record both behaviours here as they are observed; the
  plan's sentence is written to the one both stacks satisfy.

## Assumption Log entries appended by executors

One line per entry: phase, decision, options, choice. The Conductor ratifies or reverts each.
