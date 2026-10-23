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
