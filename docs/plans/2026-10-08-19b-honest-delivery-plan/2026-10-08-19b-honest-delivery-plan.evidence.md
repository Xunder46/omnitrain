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
| S-206 reachable + ok |  |  |  |
| S-206 unreachable, channel NOT called |  |  |  |
| S-206 throw → `undelivered` + one report |  |  |  |
| S-207/S-218 the unreachable pass is quiet |  |  |  |
| The wrist's radio refusal is reported once (item 7) |  |  |  |

The doubles table (D-200) — one row per double, filled in by the implementer:

| Double | File:line | Reachability switch | Records the frames it was asked to carry | Default |
| --- | --- | --- | --- | --- |
| `_Endpoint` / `_Link` | `test/watch_transport_test.dart:124-180` | already carries `reachable`/`sendFailure` | yes | reachable |
| `_PhoneRadio` | `test/watch_session_auto_push_test.dart:210` (`send` `:252`) | added by Phase 1 | yes | reachable |
| `_PhoneRadio` | `test/watch_session_projection_test.dart:425` | added by Phase 1 | yes | reachable |
| `_PhoneRadio` | `test/watch_session_adoption_build_notify_test.dart:94` | added by Phase 1 | yes | reachable |
| `RecordingMirrorTransport` | `test/helpers/live_session_fixtures.dart:10` | added by Phase 1 | yes | reachable |
| `CaptureTransport` | `test/helpers/watch_capture_import_harness.dart:99` | added by Phase 1 | yes | reachable |
| `_PhoneTransport` / `_RecordingTransport` | `test/live_mirroring_test.dart:278,300` | added by Phase 1 | yes | reachable |
| `_PhoneTransport` | `test/phone_manage_bridge_test.dart:197` | added by Phase 1 | yes | reachable |
| `FakeWatchConnectivitySession` (Swift) | `watch/watchos/Tests/WatchSessionEngineTests/` | already carries `isPhoneReachable`/`reportReachable`/`sendError` | yes | reachable |

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
