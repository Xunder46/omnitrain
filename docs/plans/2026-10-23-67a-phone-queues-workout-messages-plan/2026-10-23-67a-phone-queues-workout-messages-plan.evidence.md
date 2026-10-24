# 67a evidence

## Phase 1: the native link lists and withdraws transfers (built 2026-10-23, uncommitted)

Base commit 2ddc6bc2. Two crew runs: A (watch builder) wrote the plugin Swift, the package Dart API, the README and the package tests;
B (app builder) wrote the core interface, the channel and the channel tests. Run A's builder sent no change outside `packages/omnitrain_watch_link/**`
and `test/watch_link_package_test.dart`; run B none outside `lib/core/platform/**` and `test/watch_connectivity_channel_test.dart`.
Both builders were pointed at exact code for the logic, so the lead read the diffs rather than trusting the reports.

Observed by the lead:

- `flutter test test/watch_link_package_test.dart test/watch_connectivity_channel_test.dart` → `+22: All tests passed!` (before and after `dart format` on the five changed Dart files).
- `flutter analyze` → 180 issues (the pre-existing info notices, 0 errors; same count the builders saw before their edits).
- `flutter build ios --simulator --no-codesign -d <iPhone 17 Pro>` → `✓ Built build/ios/iphonesimulator/Runner.app` (compiles the new Swift). The bare command in the Done Criteria needs a device id because the app has a watch companion.
- `grep -rln "package:omnitrain_watch_link" lib` → `lib/core/platform/watch_connectivity_channel.dart` only (S-9703 guard).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty.
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → `+42: All tests passed!`.
- Full suite not run: Phase 1 adds methods nothing calls yet, and the Phase 2 Done Criteria carry the full run.

Mutation pass (lead, in place, original restored and byte-compared after each):

| Mutation | Result |
|---|---|
| `cancelTransfers` without the empty-list guard | killed (S-9702 B) |
| `cancelTransfers` returns 0 on a platform error instead of throwing | killed (S-9702 C) |
| `outstandingTransfers` keeps an entry with no string `messageId` | killed (S-9701) |
| channel drops `changeId` | killed (S-9703) |
| channel reverses the ids it cancels | killed (S-9703) |
| `outstandingTransfers` reverses the order | killed (S-9701) |

Not covered by any test (the Swift cannot be unit-tested here): the native list and cancel against real `WCSession` transfers. Compiled, not run;
Phase 2's owner device checks exercise it.

Scope guard: the plan is 278 lines, 2 phases, tracks phone only; Phase 1 diff is 327 lines added across 6 files plus one new 47-line file, as predicted. Within budget.

## Phase 2: the phone queues its workout messages (built 2026-10-24, uncommitted)

Base commit 7912d738 (G-0 printed nothing: the tree was clean after plans 61/62 landed). Crew runs: C (transport rules, `lib/core/platform/watch_transport.dart`),
F (PROTOCOL.md amendment, in parallel with C), D1 and D2 (transport tests S-9710..S-9719, S-9724), E1 and E2 (`test/watch_session_queue_test.dart`: S-9720, S-9721, S-9722, S-9723), G (docs keeper: `watch_surface.md`). No fix rounds.
One deviation, caught by run C: the capability check needed an `Object` local because `WatchMessageChannel` is not a supertype of `WatchQueueControl` (type promotion does not apply). Same behaviour.
One addition beyond the plan: queue work runs one call at a time (`_inQueueLane`), pinned by S-9724 (two sends at once leave one held snapshot).

Observed by the lead:

- `flutter test` (full suite): `+5509 ~2: All tests passed!`.
- Impact suites together with the contract tests (`watch_transport`, `watch_session_queue`, `watch_message_order`, `watch_session_auto_push`, `watch_timer_push`, `live_mirroring`, `watch_session_projection`, `settings_watch_status`, `ui_standards_contract`, `docs_indexing_contract`): `+340: All tests passed!`.
- `flutter analyze`: 180 issues, 0 errors (unchanged from the baseline before Phase 2).
- Invariant grep (`hive_workout_repository` in `lib/state lib/features lib/widgets lib/core`): empty. Residue `== 'receipt';` in the transport: none; `is true exactly for .receipt.` in `docs/state_management`: none.
- `watch_surface.md` about 47.7 KB (ceiling 52 KB).

Mutation pass (lead, in place, original restored and compared after each; script kept outside the tree): all killed.

| Mutation | Killed by |
|---|---|
| withdraw ignores `sessionId` | S-9711, S-9714, S-9716 A |
| withdraw ignores `changeId` | S-9717 |
| `receipt` and `exercise_push` withdrawn | S-9718 |
| `timer_state` queued | S-9715, S-6811 timer arm |
| a queued frame reported as `delivered` | S-9710, S-6810, S-6812 |
| no withdraw after a live delivery | S-9714, S-9721 |
| a failing list read skips the queue (rethrow) | S-9719 A, S-9719 B |
| no serialising lane | S-9724 |
| the frame's own `messageId` cancelled | S-9716 B |
| withdraw matches any type | S-9711, S-9714, S-9717 |

S-9723 (static data is never pushed) is an absence guard: no mutation exists without adding a push, so it is proven by the plan's design, not by a mutation.
Not run: a separate reviewer run (the lead read every diff). Not checked: the real `WCSession` behaviour (cancel of a transfer already in flight, delivery to a closed watch app), which is the owner device checks 1-3.
