# Evidence — 18c: a rest done on the watch reaches the phone's rest history

Plan: `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/2026-10-08-18c-watch-rest-to-phone-plan.md`
Review findings live beside this file, in `…-plan.review.md`.

This file holds what a reader cannot get from the plan: the base-commit baselines, the pasted red evidence and the green
counts for every guard, and the commands that reproduce the planner's verification answers. Implementers append; the
reviewer re-runs the commands and checks the numbers. **No claim of success without a pasted count** — "it passes" is not
evidence; `flutter test`'s `+N ~M` line, `swift test`'s executed/failed counts and `flutter analyze`'s issue count are.

## Baselines at the base commit

| Check | Command | Baseline |
|---|---|---|
| Flutter suites | `.github/copilot/scripts/macos/gateway.sh test` | +4181 passed, ~1 skipped |
| Watch package | `.github/copilot/scripts/macos/gateway.sh swift-test` | 376 executed, 0 failed |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing infos) |
| Watch app | `xcodebuild` for a watchOS simulator, `OmniTrain Watch App` | governor-run, once per PR |

A phase's Done Criteria are green only if its own suites pass **and** the analyzer's issue count has not risen above 196
without a stated reason.

## Red → green (fill in per phase; one row per guard)

| Phase | S-id / guard | Test (file · name) | Red evidence (paste the failure) | Green (counts) |
|---|---|---|---|---|
| 1A | S-330 wire | `test/sync_protocol_fixtures_test.dart` (manifest walks the four new fixtures) | run with the fixtures + manifest rows in place and the schemas unchanged — must fail on the unknown kind | |
| 1A | S-330 window rule | `test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift` (`invalid/observations_up_rest_not_after.json`) | | |
| 1B | S-320/332/333/334/335 (Dart) | `test/watch_session_rest_timer_append_test.dart` | `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_rest_timer_append_test.dart` must **fail** | |
| 1B | S-320/322/331/332/334/335/336/339 (Swift) | `WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift`, `WatchSessionEngineTests.swift`, `WatchFileStoreTests.swift` | | |
| 2 | S-320/323/324/326/327/328 | `test/watch_session_import_test.dart`, `test/watch_session_rest_timer_append_test.dart` | `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_import_test.dart` must **fail** | |
| 2 | S-320/325/328/337/338 + repository parity | `test/watch_session_merge_test.dart` (Mock and Hive) | | |
| 3 | S-329 total | `test/watch_session_summary_integration_test.dart` | | |
| 3 | view guard | `test/watch_rest_to_phone_view_test.dart` (new) | | |
| 3 | rest rule + docs size | `test/rest_is_count_up_contract_test.dart`, `test/docs_indexing_contract_test.dart` | | |

## Phase 1A fixture ledger

| Fixture | Manifest row | Expected verdict |
|---|---|---|
| `fixtures/valid/observations_up_rest.json` (set `entry-a1`, then one 70 s `rest`, `afterEntryId: "entry-a1"`) | `valid`, `type: observations_up`, `scenario: S-330` | accepted |
| `fixtures/invalid/observations_up_rest_missing_after_entry_id.json` | `invalid`, `expectedCode: missing_required_field`, `expectedReasonContains: afterEntryId` | refused |
| `fixtures/invalid/observations_up_rest_planned_duration.json` | `invalid`, `expectedCode: unexpected_field`, `expectedReasonContains: plannedDurationMs` | refused |
| `fixtures/invalid/observations_up_rest_not_after.json` | `invalid`, `expectedCode: semantic_violation`, `expectedReasonContains: endedAt` | refused |

`test/sync_protocol_fixtures_test.dart` lists every fixture on disk exactly once (`:158`) and checks that every
`schemas/`/`fixtures/` path `PROTOCOL.md` names exists (`:764`); the Swift suite walks the same manifest, so a divergence
between the two validators fails in `swift-test`.

## Reproducing the planner's verification answers

| Answer | Command |
|---|---|
| V-1 the finish path stops nothing (`WatchSessionEngine.swift:1071` `transitionTo`, `:340`/`:348`, `:1381`; Dart `:1148`, `:341`/`:347`) | `grep -n "transitionTo\|captureSessionEnd\|stopTimer" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` |
| V-2 the lookup is positional (D-221) | read `WatchSessionEngine.stopTimer` (`:1569`) + `WatchLoggingState.log` (`:589` `if isResting { await endRest() }`) and the shared sequence counter in `WatchSessionStore.append` |
| V-3 the three flows and two hook sites | `grep -n "_Pass.run\|_markApplied\|_mergeHeld\|_consume" lib/core/services/watch_session_importer.dart` (`:429`, `:214`, `:224`, `:367`/`:369`) |
| V-4 no repository change | `grep -n "EntryRest createEntryRest\|getEntryRests" lib/data/repositories/hive_workout_repository.dart lib/data/repositories/mock_workout_repository.dart` (`:1550`/`:1560`, `:859`/`:866`) |
| V-5 the wire edits | `grep -n "afterEntryId" watch/sync_protocol/` must find it only in the new schema/fixture text; `grep -n "enum" watch/sync_protocol/schemas/envelope.schema.json` for the kind list (`:175`) |

## Environment notes that decide how a phase is run

- `flutter test` (full suite) takes minutes: run it with the gateway's 900 s timeout, and run widget tests Mock-first.
  A widget test that opens the Hive harness or awaits a real `Future.delayed` inside `testWidgets` hangs forever at ~0%
  CPU (FakeAsync never advances real time); seed Hive in `setUp` and keep persisting taps Mock-only.
- A test file whose Mock group is red can leave its Hive group hanging: fix the red group rather than re-running the file.
- `flutter analyze` exits non-zero while the repo carries pre-existing info notices — compare the count with 196.
- `swift test --package-path watch/watchos` compiles the watch package; the watch app target needs `xcodebuild` for a
  watchOS simulator, which only the governor runs.
- **Split (governor, 2026-10-08).** This plan ships Phase 1A and Phase 2 only. The rows above that name Phase 1B or
  Phase 3 belong to plan 18d and are tracked in its evidence file
  (`docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.evidence.md`),
  which keeps this plan's baselines. The view-guard row's test file is the one 18d's Phase 2 names there. So there is no
  state in which the wrist emits what the phone cannot stage: the emission lands with 18d, after this plan's writer.
