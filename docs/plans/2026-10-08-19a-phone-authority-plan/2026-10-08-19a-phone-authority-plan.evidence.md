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

Base for this phase: `9851765` (Phase 2's head, named by the brief). Baselines there: `gateway.sh test`
→ `+4090 ~1`, 0 failures; `gateway.sh lint` → 196 issues, 0 errors; `gateway.sh swift-test` not re-run
(no `.swift` file is in this phase's Predicted Files).

| # | Item (file · symbol) | Command | Result |
| --- | --- | --- | --- |
| 1–4 | `workout_session_screen.dart` · `initState` subscription (`!editMode`), `dispose` unsubscribe, `_leaving`/`_mountedSessionId`, `_onWorkoutStateChanged` (guard → `popUntil(isFirst)` on a null session / post-frame `_pushSessionReplacement` to `SessionSummaryScreen` with `_finishSession`'s exact arguments) | `gateway.sh test test/pr4_session_controls_test.dart` | `01:01 +14: All tests passed!` (9 pre-existing + 5 new: S-174, S-184, S-185a/b/c) |
| 5 | `workout_session_finish.dart` · `_leaving = true;` before the empty-session `discardCurrentSession()`; `workout_session_list_view.dart` · `_discardCurrentSession` first line. No helper moved: the listener reuses `_pushSessionReplacement` and `_isFinishingSession` | the same command + `test/watch_session_finish_test.dart` | item 6's run below; no second guard was added |
| 6 | `test/pr4_session_controls_test.dart` · group `Watch authority — the session screen leaves on its own` | `gateway.sh test test/pr4_session_controls_test.dart test/watch_session_finish_test.dart test/session_screen_build_phase_notify_test.dart test/session_finish_timers_test.dart` (the phase's Done Criteria) | `00:01 +34: All tests passed!` |
| 7 | `test/session_screen_build_phase_notify_test.dart` · `S-174 D-179 an end delivered while the frame builds notifies nobody and still leaves`; S-185 part B lives in the pr4 group (see the Assumption Log) | `gateway.sh test test/session_screen_build_phase_notify_test.dart` | `00:00 +5: All tests passed!` |

Longer runs used while working (all green, nothing edited to make them pass):
`test/watch_session_finish_test.dart test/session_finish_timers_test.dart test/screen_widget_test.dart`
→ `+235`; after the last one-line helper fix `test/pr4_session_controls_test.dart
test/session_screen_build_phase_notify_test.dart` → `00:01 +19: All tests passed!`.

Ticker after a pop (the Done Criteria's record): the screen runs a one-second ticker, so every new
case is Mock-first with `tester.pump()` and explicit 20 ms frames; nothing uses `pumpAndSettle`.
Disposal is observed rather than assumed — S-184 pumps 25 × 20 ms after the pop and asserts
`find.byType(WorkoutSessionScreen)` `findsNothing`, i.e. the route transition finished and `dispose`
ran (where the subscription is removed and the ticker cancelled). `test/session_finish_timers_test.dart`,
the suite that holds the ticker and timer expectations, is green in the Done-Criteria run above.

`prove-red` verdicts (the tests cannot compile at base? they can — both files exist there):

```
$ .github/copilot/scripts/macos/gateway.sh prove-red 9851765 test test/pr4_session_controls_test.dart
RED AT 9851765 (exit 1)
  S-174 … Expected: <3> Actual: <2>   (the leave-once witness counts routes: base adds none)
  S-184 … Found 1 widget with type WorkoutSessionScreen … (the screen stayed mounted)

$ .github/copilot/scripts/macos/gateway.sh prove-red 9851765 test test/session_screen_build_phase_notify_test.dart
RED AT 9851765 (exit 1)
  the D-179 clause … Found 0 widgets with type SessionSummaryScreen (the reaction does not exist at base)
```

Mutation table — one-line changes in the working tree, each restored to the exact original and the
diff re-checked as `48 insertions(+)` in `workout_session_screen.dart`:

| Mutation | Command | Expected red | Observed |
| --- | --- | --- | --- |
| the `!editMode` clause is dropped **and** `initState`'s subscription made unconditional | `test test/pr4_session_controls_test.dart --plain-name "S-185a"` | S-185a | **S-185a red**: `Found 0 widgets with type WorkoutSessionScreen` — the edit-mode screen left for the summary. Dropping only the guard clause stays **green** (edit mode never subscribes), so the two conditions are one guard in practice; the plan's row is satisfied by the double mutation. Restored |
| `&& session.endedAtMs != null` is dropped | the same file, `--plain-name "S-174"` | S-174 | first run **green** — the rating notification alone opened the summary, so the clause was uncovered. S-174 was strengthened with the live-session clause ("a live session's own lifecycle does not move the screen", the route witness counts what a live session adds: none), then the mutation gave **S-174 red** `Expected: <2> Actual: <3>`. Restored |
| `_isFinishingSession` is dropped from the guard | the same file, `--plain-name "S-185b"` | S-185b | **S-185b red**: `Expected: a value less than or equal to <1> Actual: <2>` — the screen's own finish plus the same-session end produced two summaries. Restored |
| `_leaving` is dropped (the initialiser and both assignments) | the same file, `--plain-name "S-174"` | S-185b (the plan's row) | **S-174 red**: `Expected: <3> Actual: <4>` — a second same-session notification navigated a second time. The witness is the leave-once clause in S-174, not S-185b (its `_isFinishingSession` covers that case); same guard, different scenario — recorded, not re-labelled. Restored |
| the ended branch pushes inline instead of inside `addPostFrameCallback` (Trap 3's deferral) | `test test/session_screen_build_phase_notify_test.dart` | the D-179 clause | **green — this mutation is benign.** The state's end path notifies through `await`s, so a notification never lands inside `persistentCallbacks`; the clause's live assertions are "nothing is thrown" and "no notification phase during the delivery frame", and its proof is the RED AT base verdict above. Restored |

Full suite at the phase's head: `gateway.sh test` → `01:42 +4096 ~1: All tests passed!` (4090 + 6 new:
5 in the pr4 group, 1 build-phase clause; 1 pre-existing skip, 0 failures). The run before the phase's
last one-line fix (a `use_null_aware_elements` info in my own helper, `navigatorObservers: [if (observer != null) observer]`
→ `[?observer]`): `+4096 ~1`, also green; both touched files were re-run green after the fix (19/19 above).
`gateway.sh lint` → **196 issues = baseline**, none in a line this phase authored. Invariant sweep
(`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`, read with the
file tools because the shell is the gateway): **no matches**.

Honest notes. (1) The brief's S-174 fixture says "rating 7"; `updateSessionFeeling` clamps 1..5
(`lib/state/workout/session_core_lifecycle.dart:183`), so the fixture rates 4 and asserts 4 — the
scenario's point (the summary renders the watch's rating without asking) is unchanged. (2) `_leaving`
is redundant on the screen's own finish (already `_isFinishingSession`) and on the two own-discard
paths (the screen and the listener both call `popUntil(isFirst)`, so the listener's call is a no-op
there); its load-bearing witness is an end arriving from outside the screen, which is what S-174's
leave-once clause and the fourth mutation show. (3) The D-179 clause has to arm the screen first:
`_mountedSessionId` is deliberately unset during the first frame, so an end delivered then is ignored
by design; the clause arms it through a `ValueNotifier` after the deferred load and then delivers the
end from inside `build`.

## Phase 4 — docs, contract, residue sweep

Doc-sentence → test table (one row per added or rewritten sentence; a sentence with no test is
not written):

| File · line | Sentence (short) | Test that shows it |
| --- | --- | --- |
| `docs/watch_session_sync.md:105` | D-10 rewritten: "a conflict resolves to the phone's session (D-170)" — the phone refuses to adopt, and its own state is preceded by a lifecycle naming the wrist's session `abandoned` | `test/watch_session_auto_push_test.dart` · `S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer is what converges the pair` |
| `docs/watch_session_sync.md:113-128` | the same paragraph's four halves: the phone's, the retry, the wrist's, the adoption the reset leaves standing | S-172 (above); `S-180 a reset the radio cannot carry is dropped, re-sent by the next pass, and owed by nobody once the pair agrees`; `test/watch_session_projection_test.dart` · `S-183 case A the abandoned frame the reset carries ends the wrist's session and takes nothing else`; `test/watch_session_adoption_bridge_test.dart` · `S-6 the phone keeps the session it is already running` |
| `docs/watch_session_sync.md:182`, `:305` | repaired citation of the test 19a Phase 2 renamed (the old name no longer exists) | `test/watch_session_auto_push_test.dart` · `S-86 the push ends the wrist's session as a deliberate reset and never as an end the phone was told about` |
| `docs/watch_session_sync.md:245` | "A phone session now takes over the wrist's running one (D-102, D-170)" — the refusal stands, but the reset in front of the snapshot ends the wrist's session first | S-172; `S-183 case A …` and `S-183 case B a lifecycle naming a session the wrist is not holding is a no-op`; `WatchSessionEngineTests.swift` · `testS77AForeignSnapshotChangesNothingAndSaysNothing` and `testS77AWristWithAnEmptyLadderReservesNothing` |
| `docs/watch_session_sync.md:269` | "A start on the wrist never opens a second session there (D-171, D-177)" | `test/watch_session_start_test.dart` · `S-177 startFreeWorkout on a live session returns it and emits nothing`, `S-170 startFromRoutine on a session with exercises is refused too`, `S-178 a routine fills an active empty session in place`; `WatchSessionStartPathsTests.swift` · `testS177StartFreeWorkoutOnALiveSessionReturnsItAndEmitsNothing`, `testS170StartFromRoutineOnASessionWithExercisesIsRefusedToo`, `testS178ARoutineFillsAnActiveEmptySessionInPlace` |
| `docs/watch_session_sync.md:478-487` | both devices hold a session: the reset's three frames (lifecycle → snapshot → request) and its known limit ("until the next pass or the next reconnect's resume") | S-172; `S-182 the resume sends the reset before its own state, and the answer clears the debt`; S-180 |
| `watch/sync_protocol/PROTOCOL.md:566` | one dated (2026-10-08) additive row: the MUST-send order, `abandoned` never `completed`, the placeholder case, no field/schema/validator/version/fixture change | S-172, S-180, `S-181 case A a pair that already agrees sends exactly what it sent before`, `S-181 case B a phone holding its own session over a wrist that holds nothing sends no lifecycle and never names the placeholder`, S-182, `S-183 case A`/`case B`, the Swift `testS77A…` pair |
| `docs/state_management/watch_surface.md:117`, `:123` | the reset is the phone's to originate, like every other session frame | S-172 |
| `docs/state_management/watch_surface.md:195` | repaired citation of the renamed S-86 test | `S-86 the push ends the wrist's session as a deliberate reset and never as an end the phone was told about` |
| `docs/state_management/watch_surface.md:816` | "Reflection" entry: the phone's reset ends a wrist session the phone is not in | the D-170 row at `PROTOCOL.md:566`, which pins S-172 and S-183 case A/B |
| `docs/watch-app-setup-and-qa.md:354-378` | two sessions at once: the phone's takes over, the wrist's own session ends and it shows the phone's; the wrist's S-77 refusal is what a phone that has not sent the reset meets; a second wrist start is refused and keeps the first | S-172, `S-183 case A …`, S-86, `test/watch_session_engine_test.dart` · `S-77 the wrist refuses a foreign snapshot, silently`, S-177, S-170, S-178 |
| `docs/watch-app-setup-and-qa.md:444-449` | walkthrough step 5 restated the same way | `S-177 startFreeWorkout on a live session returns it and emits nothing` |
| `docs/state_management/watch_surface.md:826` | doc-freshness line bumped to 2026-10-08 (metadata, no behaviour sentence) | — |

Size measurements (the one file with a ceiling this feature presses):

| File | Bytes before | Bytes after | Band |
| --- | --- | --- | --- |
| `docs/state_management/watch_surface.md` | ~51,300 B (the plan's record: ~50.1 KB, `-plan.md:62`) | ~51,800 B (before + 505 B, the sum of the hand-computed deltas of the edited lines) | 52,429 B = 80% of 64 KiB; green |

Both figures are estimates: no check in the gateway reports a file's size, so the after-figure is the
plan's before-figure plus the byte deltas of the lines this phase touched. The arbiter is
`test/docs_indexing_contract_test.dart`, whose two tests fail above the ceiling and inside the 80%
band and print the byte count when they do — it passed in the run below. Item 4 asked for the file to
lose at least what it gained; every candidate removal was a sentence pinned to a test (the
manage-bridge reachability note, the Vocabulary pointers), so this phase spent ~505 B of the file's
~1.1 KB of headroom instead of deleting claims. Logged in the Assumption Log.

Residue sweep (the exact grep and its output):

```
$ grep -n "each keeps its own" docs/ watch/       # run with the file tools (shell grep is denied)
docs/plans/2026-10-06-17-watch-auto-sync-index.md:42
docs/plans/2026-10-05-15-watch-session-sync-index.md:21
docs/plans/2026-10-08-19a-phone-authority-plan/2026-10-08-19a-phone-authority-plan.md:16,20,62,170
docs/plans/2026-10-08-19a-phone-authority-plan/2026-10-08-19a-phone-authority-plan.evidence.md:238
docs/plans/2026-10-08-18-watch-qa-index.md:19
```

Every hit is under `docs/plans/` — records, exempt by D-181. No feature page and nothing under
`watch/` matches. The plan's `:170` expected the rest-timer line (`docs/watch_session_sync.md:497`,
now `:541`) to survive this grep; it reads "each **device** keeps its own", so it survives the wider
sweep rather than this one:

```
$ grep -n "keeps its own|keeps their own|each keeps" docs/ watch/
docs/watch_session_sync.md:541:- **The phone's rest timer is not carried; each device keeps its own
watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift:1543:  "the wrist keeps its own row"
docs/plans/** (46 hits across 12 plan files, records)
docs/plans/food-serving-unit-normalization-plan.md:27,29 (serving units, unrelated)
```

`:541` is the rest-timer rule 18b owns (D-181's one exception, left untouched); the Swift line is a
test's prose about its own *row*; the rest are plan records or unrelated. No session-level
"keeps its own" survives in a feature doc: the two pages that carried it
(`docs/watch_session_sync.md` D-10/D-102 and `docs/watch-app-setup-and-qa.md` steps (d) and 5) now
say the phone's session takes over, the wrist's own ends, and a second wrist start is refused.

Runs at the phase's head (docs-only: no Dart, no Swift and no test file changed, so nothing was
edited to make them pass):

| Check | Command | Result |
| --- | --- | --- |
| the phase's Done Criteria, targeted | `gateway.sh test test/docs_indexing_contract_test.dart test/sync_protocol_fixtures_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_session_auto_push_test.dart` | `All tests passed!` (155 cases) — the size gate and the contract fixtures, green after every doc edit |
| full suite | `gateway.sh test` | `+4096 ~1: All tests passed!` — byte-identical to Phase 3's head, which is the expected result of a phase that adds no test |
| linter | `gateway.sh lint` | `196 issues found.` = baseline; no issue line names a page this phase touched |
| watch package | `gateway.sh swift-test` | 340 tests, 0 failures (no `.swift` file is in this phase's Predicted Files; re-run because the PROTOCOL row cites the Swift pair) |
| invariant sweep | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no output |

No prove-red for this phase: it changes no code and no test, so there is no guard to prove. The
deliverable is prose, and `test/docs_indexing_contract_test.dart` is the check that binds it.

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

- **Phase 4 · shell grep denied.** The residue sweep has to be run with the file tools (ripgrep), not
  with `grep -n` in a shell. Options: ask the governor to run it, or run the same regex through the
  tool. Choice: the tool; both greps and their exact output are in the sweep block above.
- **Phase 4 · no way to measure a doc's bytes.** No gateway check reports file size and `wc` is denied,
  so the size table's after-figure is the plan's before-figure plus the hand-computed deltas of the
  touched lines. Options: state no number (the contract test prints one only when it fails), or
  estimate and say so. Choice: estimate, and let `test/docs_indexing_contract_test.dart` be the arbiter.
- **Phase 4 · item 4's byte balance.** The plan asked `watch_surface.md` to lose at least what it
  gained; it gained ~505 B instead. Options: delete a test-pinned sentence (the manage-bridge
  reachability note, or a `PROTOCOL.md` authority pointer) or spend the headroom. Choice: spend it —
  the file sits ~600 B under the 80% band and the contract test passes — and report the deviation here.
- **Phase 4 · three stale citations repaired.** 19a Phase 2 renamed
  `S-86 the phone's own push does not end the wrist's live session`; `docs/watch_session_sync.md:182`,
  `:305` and `docs/state_management/watch_surface.md:190-195` still carried the old name, which no
  test has any more. The plan did not list them; every behaviour sentence must name a real test, so
  they were repaired as part of the pages this phase already owns.
- **Phase 4 · "no queue, no retry" left standing.** `watch_surface.md:180` says `WatchSessionAutoPush`
  adds no queue and no retry. Options: qualify it for D-176's owed reset, or read it as what it says —
  no retry *queue*, the reset being recomposed by the pass predicate like F7's owed deletion
  announcement. Choice: leave it; the reset is owed by a predicate, not queued.
- **Phase 4 · freshness line bumped.** `watch_surface.md:826`'s "Last reconciled against source" moved
  from 2026-09-20 to 2026-10-08 (0 bytes). Its session-mirroring claims were reconciled against source
  in this phase; the rest of the page was not re-derived, so the date claims only that this feature's
  pages were touched.
