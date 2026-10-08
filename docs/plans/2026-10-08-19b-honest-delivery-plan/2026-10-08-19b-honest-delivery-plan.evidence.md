# Evidence — 19b, a frame that did not get through is owed, never forgotten

Plan: `2026-10-08-19b-honest-delivery-plan.md` (and its `.review.md`). Implementers append to this file as
each phase runs: the planner's baselines and the required tables are below. A claim that is not a pasted
count, a pasted frame log or a pasted grep output does not belong here — and is not evidence.

## Baselines measured for this plan (2026-10-08, planning run)

| Check | This plan's baseline | The 18-series baseline (for context) |
| --- | --- | --- |
| `.github/copilot/scripts/macos/gateway.sh test` | 4083 tests / ~1 pre-existing failure (moves as 19a lands; 19a Phase 1 added 10 cases, 2 repaired) | 4061 tests / ~1 pre-existing failure |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors — the repo carries pre-existing info notices, so compare the count, not the exit code | 196 / 0 |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 340 tests / 0 failures | 335 / 0 |
| `docs/state_management/watch_surface.md` | ~50.1 KB of the `test/docs_indexing_contract_test.dart` ~51.2 KB split band (64 KiB hard ceiling) | — |

`flutter test` (the whole suite) needs the gateway's 900 s timeout. Widget tests run Mock-first, Hive is
seeded in `setUp`, and no widget test awaits a real `Future.delayed` — FakeAsync never advances real time.

## Phase 1 — an honest transport result, on both sides

| S-id / item | Test file and name | Red at base (`prove-red <ref> test <file>`) | Green at head |
| --- | --- | --- | --- |
| S-206 reachable + ok | `test/watch_transport_test.dart`, group `S-206 a send answers whether the frame was handed over` › `S-206 a reachable counterpart means delivered, and the radio carried the frame` | mutation (b), `:741` | passed |
| S-206 unreachable, channel NOT called | same group › `S-206 an unreachable counterpart is undelivered, unsent and unreported` | mutation (a), `:753` | passed |
| S-206 the cached hint is not re-read (D-190) | same group › `S-206 a send reads reachability again rather than trusting the last answer` | mutation (b), `:770` | passed |
| S-206 throw → `undelivered` + one report | same group › `S-206 a radio that refuses the frame is undelivered and reported once` | mutation (b), `:793` (the channel is never called, so no report) | passed |
| S-207/S-218 the unreachable pass is quiet | same group › `S-218 a transport that cannot carry a frame is undelivered and quiet` | mutation (c), `:759` | passed |
| The wrist's radio refusal is reported once (item 7) | `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift` › `testS206ARefusedFrameIsReportedOnceAndTheRowStaysOwed` | mutation (d), `:485` and `:508` | passed (0.006 s, 343/0 in the suite) |

`prove-red <ref> test test/watch_transport_test.dart` cannot give an assertion red here: the file names
`WatchDelivery`, which does not exist at the base commit, so the run stops at the compile error (the
brief prescribes the mutation route). Each mutation was applied alone, run, and the EXACT original
restored and re-run green.

| Phase 1 mutation (alone, then restored) | Red rows | Observed |
| --- | --- | --- |
| (a) `watch_transport.dart` `send`: the per-send `await _channel.isReachable` read deleted | S-206 unreachable; the hint row | `Expected: WatchDelivery:<WatchDelivery.undelivered> / Actual: WatchDelivery:<WatchDelivery.delivered>` — `test/watch_transport_test.dart:753` and `:774`; `00:00 +3 -2: Some tests failed.` |
| (b) `reachable = await _channel.isReachable;` → `reachable = _phoneReachable;` | the reachable, the hint and the refusal rows | `Expected: WatchDelivery:<WatchDelivery.delivered> / Actual: WatchDelivery:<WatchDelivery.undelivered>` at `:741` and `:770`, and `Expected: <Instance of 'StateError'> / Actual: <null>` at `:793`; `00:00 +2 -3: Some tests failed.` |
| (c) `if (!reachable) return WatchDelivery.undelivered;` → a `_report(StateError('the wrist is not reachable'), …)` before the return | S-218 quiet; the hint row | `Expected: <0> / Actual: <1>` with the reason `a counterpart that is simply apart is quiet (D-201), not an error to report on every send` — `:759`, and `:781`; `00:01 +3 -2: Some tests failed.` |
| (d) `WatchConnectivityBridge.swift` `send`: the `session.send` catch body emptied (a refusal swallowed) | the wrist refusal row | `XCTAssertEqual failed: ("0") is not equal to ("1") - a r …` at `WatchConnectivityBridgeTests.swift:485`; `Executed 1 test, with 2 failures`; restored → `Executed 1 test, with 0 failures` |

After the four restores: `watch_transport_test.dart` `01:46 +4113 ~1` in the full suite, and
`git-diff --stat` no longer lists `watch/…/WatchConnectivityBridge.swift` — no mutation is left applied.

Counts at Phase 1 head: `.github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart`
→ `00:00 +28: All tests passed!`; full `gateway.sh test` → `01:46 +4113 ~1: All tests passed!`
(this plan's baseline +4108 ~1, Phase 1 adds the five rows above); `gateway.sh swift-test` →
`Executed 343 tests, with 0 failures (0 unexpected)` (baseline 342, +1); `gateway.sh lint` →
`196 issues found. (ran in 3.1s)` — 0 errors, no file Phase 1 touched appears in the log (grep over
`.work/gateway/lint-20261008-042238-96982.log`: no match for any touched path); invariant grep
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → no output.

Re-run at Phase 1 close, after the last (comment-only) edits: `gateway.sh lint` → `196 issues found.
(ran in 2.5s)` — 0 errors, and the log `.work/gateway/lint-20261008-042525-97744.log` matches neither a
touched path nor `error •`; `gateway.sh test test/watch_session_auto_push_test.dart` → `00:00 +42: All
tests passed!`. The full suite was not re-run for those edits: they change comments in two test files and
plan prose, and the same suite was green at `+4113 ~1` on the code they sit on.

The doubles table (D-200) — one row per double, filled in by the implementer:

| Double | File:line | Reachability switch | Records the frames it was asked to carry | Default |
| --- | --- | --- | --- | --- |
| `WatchConnectivityTransport` (production) | `lib/core/platform/watch_transport.dart:149` | reads `_channel.isReachable` per send, never the `_phoneReachable` hint | — (real radio) | — |
| `WatchInboxStagingTransport` (production) | `lib/state/watch/watch_session_inbox.dart:552` | the wrapped transport's | `sent` | the wrapped transport's |
| `_PhoneTransport` (production, debug loopback) | `lib/state/watch/live_session_mirror_debug_main.dart:644` | none — in-process | `sent` | `delivered` |
| `_Endpoint` / `_Link` | `test/watch_transport_test.dart:125` (`send` `:150`) | carries `reachable` + `sendFailure` | `sent` | reachable |
| `_PhoneRadio` | `test/watch_session_auto_push_test.dart:219` (`send` `:261`) | `failing` → `undelivered` **and** the report (unchanged), `throwing` still throws, `hangNext` never completes its `Future<WatchDelivery>` | `attempted` + `sent` | reachable → `delivered` |
| `_PhoneRadio` | `test/watch_session_projection_test.dart:428` (`send` `:451`) | none | `sent` | `delivered` |
| `_PhoneRadio` | `test/watch_session_adoption_build_notify_test.dart:95` (`send` `:116`) | none | no | `delivered` |
| `RecordingMirrorTransport` | `test/helpers/live_session_fixtures.dart:11` (`send` `:29`) | none | `sent` | `delivered` |
| `CaptureTransport` | `test/helpers/watch_capture_import_harness.dart:100` (`send` `:120`) | none | `sent` | `delivered` |
| `_PhoneTransport` | `test/live_mirroring_test.dart:316` (`send` `:325`) | none — hands the frame to the wrist engine | `sent` | `delivered` |
| `_RecordingTransport` | `test/live_mirroring_test.dart:339` (`send` `:343`) | none | `sent` | `delivered` |
| `_PhoneTransport` | `test/phone_manage_bridge_test.dart:198` (`send` `:207`) | none — hands the frame to the wrist | `sent` | `delivered` |
| `FakeWatchConnectivitySession` (Swift) | `watch/watchos/Tests/WatchSessionEngineTests/FakeWatchConnectivitySession.swift:18` (`sendError` `:24`) | carries `sendError` and `isPhoneReachable` | `sent` | reachable |

Deliberately unchanged `Future<void> send(` sites after the sweep (`grep -rn "Future<void> send(" test lib/state lib/core`):
`lib/core/platform/watch_connectivity_channel.dart:32` (the channel seam), `lib/core/platform/watch_transport.dart:44`
(`WatchSyncTransport`: the wrist's own contract, unchanged this phase — `Future<WatchDelivery>` is a subtype, so one
override satisfies both interfaces), `lib/state/watch/live_session_mirror_debug_main.dart:625` (`_WatchTransport`),
`test/live_mirroring_test.dart:305` (`_WatchTransport`), `test/phone_manage_bridge_test.dart:192` (`_WristTransport`),
`test/watch_transport_test.dart:150` (`_Endpoint`, the channel), `test/watch_session_start_test.dart:110` (`_Transport`),
`test/watch_nutrition_quick_log_test.dart:1369`, `test/watch_reference_sync_test.dart:614` and
`test/watch_capture_contract_conformance_test.dart:156` (`_Transport`/`_RecordingTransport`) — every one of them implements
`WatchSyncTransport` or `WatchMessageChannel`; a `WatchMirrorTransport` implementer left on `Future<void>` would not compile.

Also in this phase: `test/watch_session_projection_test.dart:3154` read the value `reportLifecycleFor` used to
return as if it were the frame; it now reads the frame the radio recorded (`radio.sent.last`) — the one existing
test the signature change touched. No Swift production change: `WatchEmitForwarder.enqueue`/`WatchConnectivityBridge.send`
let a refusal reach the failure hook exactly once and swallow no throw into a silent success (mutation (d) shows the pin has teeth).

## Phase 2 — the phone's push owes what was not delivered

| S-id | Test file and name | Red at base | Green at head | The frame log (verbatim) |
| --- | --- | --- | --- | --- |
| S-200 (site 2) | `test/watch_session_auto_push_test.dart` (`:3352`), group `S-200 a frame the radio did not carry stays owed` › `S-200 the baseline does not advance on an undelivered send, so the same state is offered again when the radio comes back` | the base commit stops at the compile error (`WatchDelivery` is absent — Phase 1 recorded the same), so the pin is mutation (a), whose failure list names S-200 | passed | apart → sent `∅`, attempted 1 `session_snapshot`, failures `∅`; radio back → the same `session_snapshot` (`sessionId` and `entryIds` equal to the refused one); third pass → still 1 |
| S-200 (site 4, D-198) | same file (`:3429`), same group › `S-200 a resume whose own snapshot the radio refused stays owed, and the push offers it again (D-191 site 4, D-198)` | mutation (d) (the `forgetBaseline()` call removed from `WatchSyncGraph.sync()`) | passed | apart, `sync()` → sent `∅`, attempted `[session_snapshot:P, request:session_snapshot]`, failures `∅`; radio back, `flush()` → 1 `session_snapshot` |
| S-201 (the phone's finish, D-197 site 2) | same file (`:3475`), group `S-201 an end the radio refused stays pending` › `S-201 the phone's finish is offered once when the radio comes back, and the pending set empties only on the delivered frame` | mutation (f), the same guard on the `completed` branch: `Expected: an object with length of <1> / Actual: []` at `:3542` | passed | apart → 0 `session_lifecycle` sent, attempted 1 (`completed`, P), failures `∅`; radio back → exactly 1 lifecycle (`completed`, P); third pass → still 1; attempted total 2 |
| S-201 (a discard the radio did not carry) — the case added in this run | same file (`:3573`), same group › `S-201 a discard the radio did not carry stays pending and is announced when the watch can be reached` | mutation (b), the `row == null` branch's guard: `Expected: an object with length of <1> / Actual: []` at `:3640`, reason `S-201 the end stayed pending and goes out at the next trigger, once (D-191, D-197 site 2)` | passed | apart → 0 `session_lifecycle` sent, attempted 1 (`abandoned`, P), failures `∅`; radio back → exactly 1 lifecycle (`abandoned`, P); third pass → still 1; attempted total 2 |
| S-203 | same file (`:2858`), group `F7 a deletion whose send failed is owed, not lost` › `S-203 a deletion frame the radio reports `undelivered` stays owed under the change id it was minted with` | mutation (c) — the full-suite log names exactly this test as the first failure | passed | apart → 0 `structure_change` sent, attempted 1, failures `∅`; radio back → 1 sent, the same `changeId`, `payload.changes` = `[{kind: delete_entry, entryId: <doomed>}]`; pass after the delivery → still 1 |
| S-208 (green at base) | same file (`:3815`), group `S-208 triggers inside one window make one drain` › `S-208 three triggers in flight are one running pass and, at most, the one pass they asked for` | green at base deliberately: the debounce/coalescing rule is not what 19b changes, so there is nothing to redden | passed | three triggers → `passes <= 2`, attempted `∅`; the window closes into one pass for the change (`passes == 1`), sent 1 `session_snapshot` (the newest state), attempted 1 |
| S-205 / S-209 | same file (`:3673`), group `S-205 a frame from the wrist re-offers what is owed, never itself` › `S-205 (S-209) the wrist's own set arrives while a deletion is owed: it is applied, never echoed, and the deletion leaves after it` | cannot be pinned at the base (compile error); it went GREEN under mutation (e) — observed in both the full-suite log and a targeted run — so its teeth are the arriving-frame rules below, not the closure guard | passed | the arriving observation is applied to the phone's own session; sent 1 `structure_change` (the minted `changeId`, naming the vanished entry), 0 `session_snapshot`, nothing carrying the observation's own row id, 1 `receipt`, failures `∅` |
| S-210 (the real `onIncoming` path) | same file (`:3901`), group `S-210 an undelivered reset is re-offered whole` › `S-210 pass one carries nothing and the debt stays, the next pass sends the three frames in order, and the wrist's answer is what clears it` | cannot be pinned at the base (compile error); it is the fixture the governor's trap names — the wrist announces its own W while the phone holds P, driven through the real `onIncoming` — and a targeted run recorded that mutation (e) leaves it GREEN, so its pin is the counts below | passed | apart → sent `∅`, attempted `['lifecycle:s-1', 'snapshot:<P>', 'request:session_snapshot']`, failures `∅`; radio back → the same three in order, attempted exactly +3; the wrist applies and answers → the debt clears; a later pass sends nothing and the `session_lifecycle` count stays 1 |
| S-217 | same file (`:4158`), group `S-217 the phone's own end is not owed (D-197)` › `S-217 a refused `completeSession()` frame is not re-offered: the exclusion the plan kept, pinned as the behaviour it is` | cannot be pinned at the base (compile error), and nothing should redden it: it pins a deliberate exclusion, so its teeth are the counts below (attempted 1, sent 0, and no re-offer) | passed | apart → attempted 1 `session_lifecycle` (`s-1`, `completed`), sent `∅`, failures `∅`, the mirror is still `completed`; radio back → 0 lifecycle, attempted still 1, 0 `session_snapshot` |
| S-218 | same file (`:4232`), group `S-218 ten changes while the wrist is apart are one owed frame` › `S-218 ten notifications with the radio unreachable attempt one frame — the newest payload — and report nothing` | mutation (a) | passed | apart → sent `∅`, attempted 1 `session_snapshot` (11 entry ids), failures `∅`; radio back → sent 1 `session_snapshot`, the same 11 ids; next pass → still 1 |

Reading key for the table above: each list is the test's own recorded frame kind in order — `sent` is what the radio carried, `attempted` is what the pass offered it (the two differ exactly when a send is `undelivered` or refused), `failures` is what the failure hook reported. `∅` is the empty list.

Mutation rows. Each of (a)–(e) was run against the **full** suite (`gateway.sh test`), not the one file, so a red in another file counts as evidence too; the row names the raw log. After every restore, `gateway.sh git-diff --stat` returned the identical footprint — 4 files, 1221 insertions, 50 deletions (the two plan files were untouched until this write-up) — so no mutation is left applied.

| Mutation | Expected red S-id | Result (failures, verdict line, log) |
| --- | --- | --- |
| (a) both `_baseline` delivery guards removed, so the baseline advances before the transport's result (`_pushOnce`'s reset step and the normal tail) | S-200 | RED — 4 failures, all in `test/watch_session_auto_push_test.dart`: `S-83 a push the radio cannot carry is owed › S-83 a failed send is reported per attempt, changes nothing, and the same state is offered again`; `S-200 a frame the radio did not carry stays owed › S-200 the baseline does not advance on an undelivered send, so the same state is offered again when the radio comes back`; `S-211 re-offering an arrived frame changes nothing › S-211 a frame that reached the wrist although its result did not is re-offered, and the wrist is unchanged by the second copy`; `S-218 ten changes while the wrist is apart are one owed frame › …`; `01:46 +4121 ~1 -4: Some tests failed.` (`.work/gateway/test-20261008-051509-31586.log`) — the governor's reference said 4: matches |
| (b) the `row == null` branch's `if (delivery == WatchDelivery.delivered)` guard removed — the pending end released before the result | S-201 | RED — 1 failure: the new `S-201 an end the radio refused stays pending › S-201 a discard the radio did not carry stays pending and is announced when the watch can be reached`, `:3640`, `Expected: an object with length of <1> / Actual: []`, reason `S-201 the end stayed pending and goes out at the next trigger, once (D-191, D-197 site 2)`; `01:45 +4124 ~1 -1: Some tests failed.` (`test-20261008-051725-36435.log`) |
| (c) `_announceDeletions`: `if (delivery != WatchDelivery.delivered) break;` removed, so the owed deletion is released regardless of the result | S-203 | RED — 2 failures: `F7 a deletion whose send failed is owed, not lost › S-203 a deletion frame the radio reports `undelivered` stays owed under the change id it was minted with` and `S-205 a frame from the wrist re-offers what is owed, never itself › S-205 (S-209) the wrist's own set arrives while a deletion is owed: it is applied, never echoed, and the deletion leaves after it`; `01:47 +4123 ~1 -2: Some tests failed.` (`test-20261008-051922-41357.log`) — the governor's reference said 2: matches |
| (d) `WatchSyncGraph.sync()`'s `if (delivery == WatchDelivery.undelivered) autoPush.forgetBaseline();` removed | S-200 (site 4) | RED — 1 failure: `S-200 a frame the radio did not carry stays owed › S-200 a resume whose own snapshot the radio refused stays owed, and the push offers it again (D-191 site 4, D-198)`; `01:46 +4124 ~1 -1: Some tests failed.` (`test-20261008-052127-46193.log`) — the governor's reference said 1: matches |
| (e) the `onIncoming` closure's `if (!answeredReset) await push.flush();` made unconditional — the duplicate of the reset the router already sent | the answered-reset set: 19a's S-6, S-86, S-172, S-180, S-182 | RED — 5 failures: `test/watch_session_projection_test.dart` › `D-10 the phone never asserts a session it is not in › S-6 a wrist session this phone is not in is left alone`; and in `test/watch_session_auto_push_test.dart`: `S-86 a session the phone never held is not ended by the phone's own rule › S-86 the push ends the wrist's session as a deliberate reset and never as an end the phone was told about`; `S-172 the phone resets the wrist's live session, then asserts its own › S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer is what converges the pair`; same group › `S-180 a reset the radio cannot carry is dropped, re-sent by the next pass, and owed by nobody once the pair agrees`; same group › `S-182 the resume sends the reset before its own state, and the answer clears the debt`; `01:48 +4120 ~1 -5: Some tests failed.` (`test-20261008-052328-51017.log`). **Discrepancy to record: the governor's reference for (e) said 4 failures; this run got 5 — the extra is the `D-10`/`S-6` projection case, which pins exactly the rule the guard protects (a flush answering a session the phone is not in).** **Observation: the same file's two real-`onIncoming` cases, S-205 (S-209) and S-210, stayed GREEN under (e) in the full-suite log and in a targeted run (`gateway.sh test test/watch_session_auto_push_test.dart --plain-name "S-210"` → `00:00 +1: All tests passed!`), so the guard's observed teeth are the five tests above.** |
| (f) the `completed` branch of `_announceEnd` unguarded — the same shape as (b) on the other terminal branch; run in this run as the extra pin for S-201's first case | S-201 (finish) | RED — `S-201 the phone's finish is offered once…` at `:3542`, `Expected: an object with length of <1> / Actual: []`, `00:00 +0 -1: Some tests failed.` (targeted: `gateway.sh test test/watch_session_auto_push_test.dart --plain-name "S-201 the phone's finish is offered once"`); after the exact restore, `--plain-name "S-201"` → `00:00 +2: All tests passed!` |

## Phase 3 — the wrist announces a finished session at catch-up, and the phone follows

| S-id | Test file and name (Dart / Swift) | Red at base | Green at head | The frame (verbatim: `messageId`, `at`, payload) |
| --- | --- | --- | --- | --- |
| S-212 | `test/watch_session_engine_test.dart`, group `S-212 the replay is the live end frame, not a new event` (`:2177`), tests `S-212 the replay repeats the live frame field for field` (`:2207`) and `S-212 an abandoned session replays the same way` (`:2243`); the same frame at the orchestrator: `test/live_mirroring_test.dart`, group `S-216 the catch-up re-announces the wrist's end behind what it owes` (`:1262`) › `S-216 the rating is announced before the end frame, and the exchange follows it` (`:1310`); Swift `WatchSessionEngineTests.testS212TheReplayRepeatsTheLiveFrameFieldForField` (`:1155`), `…AnAbandonedSessionReplaysTheSameWay` (`:1191`), and `WatchConnectivityBridgeTests.testS216TheEndIsReAnnouncedBehindTheWristsOwedObservations` (`:996`) | RED — `gateway prove-red HEAD test test/live_mirroring_test.dart` → `RED AT HEAD`, three failures: `:1388`, `:1416` and the reachability gate, `Actual: []` where the replay is expected, and the step log `['routines', 'send:observations_up', 'send:session_snapshot']` (the replay's step absent, the snapshot the only carrier of the end). The engine file and the Swift files cannot be pinned at the base — they do not compile without `replaySessionEnd` (`prove-red 0f7aaff test test/watch_session_engine_test.dart` → load failure) — so their pins are the mutation rows below | passed | `{'protocolVersion': 1, 'messageId': 'msg-rec-2', 'sessionId': 'w9', 'type': 'session_lifecycle', 'origin': 'watch', 'sentAt': '2026-10-08T10:00:00.000Z', 'payload': {'state': 'completed', 'at': '2026-10-08T10:00:00.000Z'}}` — `messageId` = `msg-<terminal rowId>`, `sentAt`/`payload.at` = the terminal row's own `recordedAt`; Swift asserts the same dictionary whole (`["protocolVersion": 1, "messageId": "msg-rec-2", "sessionId": "w9", "type": "session_lifecycle", "origin": "watch", "sentAt": "2026-10-08T10:00:00.000Z", "payload": ["state": "completed", "at": "2026-10-08T10:00:00.000Z"]]`). The pair harness runs at its own clock and shows the same frame with `sentAt`/`at` `2026-07-13T06:00:00.000Z`. No new row and no new id per replay (the wrist's `rec-2` survives) |
| S-213 | `test/pr4_session_controls_test.dart` › `testWidgets('S-213 the end the wrist re-announces at its next catch-up leaves the screen for one summary carrying the wrist's rating')` (`:800`) | green at base **by design**: `gateway prove-red HEAD test test/pr4_session_controls_test.dart` → `GREEN AT HEAD`. D-199 puts the whole change on the wrist ("the phone needs no new rule"); what the phone does with the frame is consumption, and it is exactly the frame S-216 proves is composed and carried (red, above) | passed | the router hands the frame to `WatchSessionAdoptionBridge.onLifecycle`, the importer folds the rating into the phone's copy, and the screen leaves for one summary: `WorkoutSessionScreen` gone, one `SessionSummaryScreen`, the summary shows `4 / 5`, no `EffortRatingSheet`, and the phone's `w9` carries an `endedAtMs` |
| S-214 (green at base) | `test/watch_session_engine_test.dart`, same group › `S-214 a session still running replays nothing` (`:2259`) and `S-214 a wrist with no session replays nothing` (`:2279`); Swift `WatchSessionEngineTests.testS214ASessionStillRunningReplaysNothing` (`:1207`), `…AWristWithNoSessionReplaysNothing` (`:1223`) | pinned by mutation, not by the base commit (the API does not exist there): (a′) Dart → RED at `test/watch_session_engine_test.dart:2271`, reason `a session in progress has no end to re-announce (D-199)`; (a″) Swift → RED at `WatchSessionEngineTests.swift:1216`, `XCTAssertEqual failed: ("3") is not equal to ("2") - a session in progress h…` | passed | — (nothing is composed: a running row's replay is refused, and a wrist with no session has nothing to compose) |
| S-215 (the deliberate extra frame) | `test/live_mirroring_test.dart`, same group › `S-215 every catch-up repeats the same frame, and the phone stays still` (`:1396`); the repeat half of `WatchConnectivityBridgeTests.testS216TheEndIsReAnnouncedBehindTheWristsOwedObservations` | RED — the same `prove-red HEAD` run, `:1416`: `Actual: []` where the two identical frames are expected | passed | two catch-ups carry **two** `session_lifecycle` frames, identical to each other and to the live one (`msg-rec-2`, `2026-07-13T06:00:00.000Z` twice); the wrist's row stays `completed`, two stored rows, nothing minted by the repeat, and the phone's state is read before and after the repeat and compared |
| S-216 | `test/live_mirroring_test.dart`, group `:1262`, tests `:1310` (the order), `S-216 the replay is gated on reachability: an apart sync re-announces nothing, and the later one does` (`:1362`); Swift `WatchConnectivityBridgeTests.testS216TheEndIsReAnnouncedBehindTheWristsOwedObservations` (`:996`) | RED — `gateway prove-red HEAD test test/live_mirroring_test.dart` → `RED AT HEAD`, `:1388` and `:1416` (+ the gate test), each for the reason it guards | passed | the reachable catch-up's exact step log: `['routines', 'send:observations_up', 'send:session_lifecycle', 'send:session_snapshot']` — the owed rating first, the replay behind it, the exchange last; unreachable → no replay at all (`steps` and `sent` both show none), and the wrist still holds its end |

Mutation rows: replay unconditionally (S-214 red) · replay before the observations (S-216 red).

| Mutation | Where | Expected red S-id | Result (failure line, reason, restore) |
| --- | --- | --- | --- |
| (a) the terminal-status guard removed, `_emitLifecycleIfConformant(row, row.status)` kept (`replaySessionEnd`, `:354-360`) | `lib/watch/session/watch_session_engine.dart` | S-214 | **not detected** — `gateway test test/watch_session_engine_test.dart` → 46 passed. Finding, recorded because it is one: the emit path refuses a non-terminal lifecycle anyway — `_emitLifecycleIfConformant` (`:1201-1208`) validates the composed envelope and drops it (`active` is not a state the schema admits for a `session_lifecycle`; Swift's `emitLifecycle` does the same) — so the guard is the second line of defence, and D-199's rule holds only while both are in place. The mutant with teeth is the one that ignores the row's status: |
| (a′) `_emitLifecycleIfConformant(row, WatchSessionStatus.completed)` — a running row replays as an end | same method | S-214 | RED — `test/watch_session_engine_test.dart:2271`, reason `a session in progress has no end to re-announce (D-199)`: actual = the start lifecycle, the snapshot **and** `{'protocolVersion': 1, 'messageId': 'msg-rec-1', 'sessionId': 'w9', 'type': 'session_lifecycle', 'origin': 'watch', 'sentAt': '2026-10-08T10:00:00.000Z', 'payload': {'state': 'completed', 'at': '2026-10-08T10:00:00.000Z'}}` — one frame too many. Restored exactly; the Dart files then ran `+100: All tests passed!` |
| (a″) guard narrowed to `guard let row = current else { return }` and `emitLifecycle(row, state: WatchSessionStatus.completed)` | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `replaySessionEnd()` | S-214 | RED — `WatchSessionEngineTests.swift:1216`, `XCTAssertEqual failed: ("3") is not equal to ("2") - a session in progress h…`. Restored exactly |
| (b) `if (_paths.phoneReachable) _engine.replaySessionEnd();` moved above `await _sendOwedObservations();` | `lib/watch/start/watch_sync_orchestrator.dart`, `sync` | S-216 | RED — `test/live_mirroring_test.dart:1322`: expected `['routines', 'send:observations_up', 'send:session_lifecycle', 'send:session_snapshot']`, actual `['routines', 'send:session_lifecycle', 'send:observations_up', 'send:session_snapshot']`. Restored exactly; both Dart files then ran `+100: All tests passed!` |
| (c) the same call moved above the `pendingObservations()` loop | `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`, `sync` | S-216 | RED — `WatchConnectivityBridgeTests.swift:1051` (`XCTAssertEqual failed: ("Optional("session_lifecyc…")` — the first carried frame is the replay, not the owed observation) and `:1066` (`XCTAssertGreaterThan failed: ("0") is not greater …`). Restored exactly; `gateway swift-test` then `Executed 348 tests, with 0 failures` |

Why (c) needed a fixture of its own: through the production `WatchEmitForwarder` the emit is enqueued on
its own `Task`, so on the wire the replay can land after the snapshot wherever it is composed — a
wire-order assertion could not see the reordering, and the existing `Harness`'s local `emitted` array
never sees a replay at all. The bridge fixture therefore reads a synchronous sink (`WireLog`, a
`WatchSyncTransport` that is both the send log and the engine's `onEmit`), which records the composition
order exactly as the Dart twin's single list does; the forwarder's own ordering remains S-020's test's.

What landed: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` +12 (`replaySessionEnd()`:
the terminal-status guard, then `emitLifecycle(row, state: row.status)` over the stored row);
`WatchSyncOrchestrator.swift` +4 (the replay between the owed observations and the snapshot branch,
gated on `paths.phoneReachable`); `lib/watch/session/watch_session_engine.dart` +14 and
`lib/watch/start/watch_sync_orchestrator.dart` +3 (the twin's halves); tests
`WatchSessionEngineTests.swift` +160, `WatchConnectivityBridgeTests.swift` +187,
`test/watch_session_engine_test.dart` +112, `test/live_mirroring_test.dart` +197,
`test/pr4_session_controls_test.dart` +163. `gateway git-diff --stat` ends at 9 files, 848 insertions,
**4 deletions** — the four are the pair harness's `_Session` constructor and `onEmit:`/`sessionIdFactory`
lines this phase parameterised, every other file is insertions only, and the figure is identical before
and after every mutation, which is what shows the restores were byte-identical. `gateway git-status`
lists those nine modified paths and no untracked file. No phone production change was needed: the router
already routes `session_lifecycle` to the adoption bridge, and neither `WatchSessionAdoptionBridge` nor
`WatchSessionImporter` took a line — which is exactly why S-213 is green at base.

Phase totals: `gateway test` 4125 passing / 1 skipped (baseline) → **4133 passing / 1 skipped, 0 failed**
(`01:46`, exit 0, `.work/gateway/test-20261008-060916-86918.log`); `gateway swift-test` 343 / 0 →
**Executed 348 tests, with 0 failures**; `gateway lint` 196 / 0 → **196 issues found** (equal to the
baseline, and no issue in that log names a file this phase touched); the plan's named Done Criteria set
`gateway test test/watch_session_auto_push_test.dart test/watch_session_engine_test.dart test/live_mirroring_test.dart test/watch_session_projection_test.dart test/watch_resume_sync_test.dart`
→ `01:01 +198: All tests passed!` (`.work/gateway/test-20261008-060906-86757.log`); the invariant
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing.

Base frame order for a catch-up (recorded once, so S-212 can be compared against it — read from the
double's list before any Phase 3 change):

```
routines request → owed observations → snapshot request/answer
```

The prove-red run's own failing log shows that order verbatim as the base's actual:
`['routines', 'send:observations_up', 'send:session_snapshot']` — the owed rating, then the exchange,
with nothing between them; Phase 3 inserts the replay between the two.

Phase 3's own residue (the formal sweep is Phase 4 item 6): `grep -rn "replaySessionEnd" lib/ watch/watchos/`
returns exactly four production hits — the two definitions
(`WatchSessionEngine.swift:1151`, `watch_session_engine.dart:356`) and the two `sync` call sites
(`WatchSyncOrchestrator.swift:102`, `watch_sync_orchestrator.dart:96`) — plus four Swift test call sites;
and no `Future.delayed`, `Task.sleep` or `DispatchQueue` appears in any of the four touched production
files, so trap (a) holds (the re-announcement rides the catch-up that already exists).

## Phase 4 — docs, contract and the residue sweep

Doc-sentence → test table (one row per added sentence):

| File:line | The sentence's claim | The test (file + name) that shows it |
| --- | --- | --- |
|  |  |  |

Residue sweeps (exact greps and their output):

```
grep -rn "isReachable" lib/
grep -rn "WatchDelivery" lib/ test/
grep -rn "sendState(\|deleteEntryAs(\|reportLifecycleFor(" lib/
grep -rn "replaySessionEnd" lib/ watch/watchos/
```

## The four existing cases whose reason inverts (Phase 2 item 7)

| Case | File:line | The old assertion (kept here) | The new assertion |
| --- | --- | --- | --- |
| S-83 | base `:984-1034`, head `:1022` (`test/watch_session_auto_push_test.dart`) | The base case's claim, as its own header line still shows in the working-tree diff: `//   S-83 a push the radio cannot carry is dropped` — a frame the radio refused was dropped and forgotten, because the baseline advanced before the send, so the same state was never offered again. | `S-83 a failed send is reported per attempt, changes nothing, and the same state is offered again` (`:1023`): one report per attempt (2 after the second refused pass), the radio's recovery pass sends the state it never took, and only that delivered frame advances the baseline (a fourth pass sends nothing, reports stay 2). |
| S-112 | base `:1592-1670`, head `:1677` | The base case's claim, from its retained group name and the plan's `## Existing-Functionality Impact` row: a hung send is abandoned and reported — and, with the baseline advanced before the send, the change made while it hung never left the phone. | `S-112 a send that never completes is abandoned and reported, and the change made while it hung still leaves the phone` (`:1679`): the abandoned pass is reported once (a timeout, `:1717`), and the newer change is offered as exactly one `session_snapshot` — the newest state (`:1739`). |
| S-113 | base `:1672-1730`, head `:1758` | The base case's claim, from its retained group name and the Impact row: a send that fails is reported; the state that send lost was not re-offered. | Both halves of the group are rewritten: `S-113 a throwing send is reported once, and the next change still pushes` (`:1760`) — the throw is reported once and the next pass carries the newest state; and `S-113 an Error from the debounce timer path is reported, not unhandled, and a direct flush still throws it` (`:1819`). |
| F7's deletion case | base `:~2700-2770`, head group `:2786` (`test/watch_session_auto_push_test.dart`); the rewritten case is the second test in the same group, `:2858`, still S-203-named | The base case's claim, from its retained group name: a deletion whose send failed is owed, not lost. (The base *body* and its seam could not be read — see the note below — so its exact old assertions are not repeated here.) | Two tests now share the group: `F7 the next pass announces the deletion the failed one could not, under the change id it was minted with` (`:2788`) drives the seam `radio.throwing` — a transport that fails the future rather than reporting the outcome — and asserts the deletion stays owed with its minted change id, the watch applies it, and it is not announced again (`:2830`, `:2852`); the reported-outcome half is `S-203 a deletion frame the radio reports `undelivered` stays owed under the change id it was minted with` (`:2858`), the case mutation (c) reddens. |

Note on the old side. This change is uncommitted, so the base bodies live only in the working-tree diff; the diff for this file (1124 added lines) came back as a 43 KB truncated summary that this run's file tools cannot open. The old claims above therefore come from what the diff did show (S-83's removed header comment), the retained base group names, and the plan's `## Existing-Functionality Impact` row, which records the four cases as pinning "a dropped frame is dropped and forgotten".

## Known limits (stated once, here and in the plan's Open questions)

- The plugin's iOS sources (`watch_connectivity-0.2.8/ios/…/WatchConnectivityPlugin.swift:46-47`) are
  outside the repository, so D-190's "no reply handler, no error handler" claim is verified indirectly,
  through the plugin's Dart surface (`lib/core/platform/watch_connectivity_channel.dart`) and the owner's
  log. The design does not depend on the plugin rejecting.
- `swift-test` covers the package, not `ios/OmniTrain Watch App/ContentView.swift`; the watch app target's
  behaviour around a locked wrist is the owner's QA walkthrough, plus the governor's simulator build.
- While the wrist still holds a terminal session, each catch-up carries one extra `session_lifecycle`
  (S-215, the deliberate AC-4 reading): asserted, quantified, and a no-op on the phone by construction.
- 19a's `rememberedFateOf` memory is process-local; a relaunched phone can adopt a wrist session it had
  discarded. Deliberately deferred (19a Open question 10, 19b Open question 6).
