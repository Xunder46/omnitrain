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

| # | Item (file · symbol) | Command | Result |
| --- | --- | --- | --- |
| 1–3 | `lib/watch/session/watch_session_engine.dart` · `createSession`; `lib/watch/start/watch_session_start_paths.dart` · `startFromRoutine`, `startFreeWorkout` | `gateway.sh test test/watch_session_engine_test.dart test/watch_session_start_test.dart` | |
| 4–5 | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` · `createSession`; `WatchStartPaths.swift` · `startFromRoutine`, `startFreeWorkout` | `gateway.sh swift-test` | |
| 6–7 | `test/watch_session_engine_test.dart`, `test/watch_session_start_test.dart`, `WatchSessionEngineTests.swift`, `WatchSessionStartPathsTests.swift` | the two commands above | |
| 8 | existing-test repairs | `gateway.sh test test/watch_session_engine_test.dart` | one Assumption Log line per file repaired |

Red-at-base evidence (item 8):

```
gateway.sh prove-red <base-ref> test test/watch_session_engine_test.dart test/watch_session_start_test.dart
<paste the failing S-176/S-177 test names and their assertion text here>
```

Cross-stack parity table — the fixture values, side by side, same fixtures in both suites:

| Fixture | Dart assertion | Swift assertion | Both green |
| --- | --- | --- | --- |
| held active session, two exercises; second `createSession` | S-176 in `test/watch_session_engine_test.dart` | `WatchSessionEngineTests.swift` S-176 twin | |
| held active session; `startFreeWorkout()` | S-177 in `test/watch_session_start_test.dart` | `WatchSessionStartPathsTests.swift` S-177 | |
| held active empty session; `startFromRoutine(r)` (3 slots) | S-178 in `test/watch_session_start_test.dart` | `WatchSessionStartPathsTests.swift` S-178 | |

## Phase 2 — the phone resets the wrist

| # | Item (file · symbol) | Command | Result |
| --- | --- | --- | --- |
| 1 | `live_session_mirror_state.dart` · `owesResetFor` | `gateway.sh test test/watch_session_auto_push_test.dart` | |
| 2–3 | `watch_session_auto_push.dart` · `_pushOnce`, failure path | the same file's S-172/S-180/S-181 cases | |
| 4–5 | `watch_sync_wiring.dart` · `WatchSyncGraph.sync()` | S-182, plus `test/watch_session_projection_test.dart` S-109 A/B/C unchanged | |
| 6–7 | `test/watch_session_auto_push_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_session_finish_test.dart` | `gateway.sh test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/watch_session_finish_test.dart test/watch_session_adoption_bridge_test.dart` | |

Frame logs (paste verbatim, one line per frame kind, in order):

```
S-172  pass 1 (pair disagrees): <frames>
S-180  pass 1 (send throws) / pass 2 (retry) / sync() / final flush(): <frames>
S-182  first sync() / second sync(): <frames>
S-181  pair agrees: <frames, compared with the base's>   placeholder: <frames>
```

Mutation table — each row is a one-line change in the working tree, the suite run, and the
scenario that must go red:

| Mutation | Command | Expected red | Observed |
| --- | --- | --- | --- |
| predicate becomes `!!mirror.isActive` | `gateway.sh prove-red <base-ref> test test/watch_session_auto_push_test.dart` | S-180, S-182 | |
| reset skips the snapshot when `encoded == _baseline` | the same command | S-180 | |
| (if used) predicate drops the placeholder clause | the same command | S-181 | |

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
