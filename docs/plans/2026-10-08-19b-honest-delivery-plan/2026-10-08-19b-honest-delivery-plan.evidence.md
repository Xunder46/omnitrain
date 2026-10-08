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
| S-200 |  |  |  |  |
| S-201 |  |  |  |  |
| S-203 |  |  |  |  |
| S-208 (green at base) |  |  |  |  |
| S-209 |  |  |  |  |
| S-210 |  |  |  |  |
| S-217 |  |  |  |  |
| S-218 |  |  |  |  |

Mutation rows (`prove-red <ref> test test/watch_session_auto_push_test.dart`):

| Mutation | Expected red S-id | Result |
| --- | --- | --- |
| (a) advance `_baseline` before the result | S-200 |  |
| (b) remove the pending end before the result | S-201 |  |
| (c) remove the owed deletion regardless of the result | S-203 |  |

## Phase 3 — the wrist announces a finished session at catch-up, and the phone follows

| S-id | Test file and name (Dart / Swift) | Red at base | Green at head | The frame (verbatim: `messageId`, `at`, payload) |
| --- | --- | --- | --- | --- |
| S-212 |  |  |  |  |
| S-213 |  |  |  |  |
| S-214 (green at base) |  |  |  | — |
| S-215 (the deliberate extra frame) |  |  |  |  |
| S-216 |  |  |  |  |

Mutation rows: replay unconditionally (S-214 red) · replay before the observations (S-216 red).

Base frame order for a catch-up (recorded once, so S-212 can be compared against it — read from the
double's list before any Phase 3 change):

```
<fill in the base order, e.g. routines request → owed observations → snapshot request/answer>
```

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
| S-83 | `test/watch_session_auto_push_test.dart:984-1034` |  |  |
| S-112 | `test/watch_session_auto_push_test.dart:1592-1670` |  |  |
| S-113 | `test/watch_session_auto_push_test.dart:1672-1730` |  |  |
| F7's deletion case | `test/watch_session_auto_push_test.dart:~2700-2770` |  |  |

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
