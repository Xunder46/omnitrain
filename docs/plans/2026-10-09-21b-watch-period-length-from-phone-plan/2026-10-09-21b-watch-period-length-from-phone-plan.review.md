# Review — plan 21b (the watch counts a period down from the phone's number)

Base commit: 916f869. Reviewed commits: 5f41f8b (plan), c79fc6a (contract), beb5fa7 (phone senders), de0757f (Phase 3, HEAD).
Verdict: CHANGES_REQUESTED (1 blocker — documentation falsity in the plan/evidence readout for S-1412; one mechanical edit, no
code change).

Test runs: `.github/copilot/scripts/macos/gateway.sh test` → `+4238 ~1: All tests passed!` (exit 0, 1:53;
`.work/gateway/test-20261010-002935-49950.log`). `swift-test` → `Executed 429 tests, with 0 failures (0 unexpected)` (exit 0;
`.work/gateway/swift-test-20261010-002935-49951.log`).
Guard spot-check: `prove-red 916f869 test test/watch_session_adoption_bridge_test.dart test/watch_reference_sync_test.dart` →
**RED AT 916f869 (exit 1)**, 6 failures, every one an assertion of the missing number (`Expected: <2400>/<900>/<180> … Actual:
<null>`) — S-1405 (×4), S-1406, S-1408, S-1409, S-1411. No compile or load error, so the guards are proven red for the reason
they guard.

## Scope

Layers in scope: sync contract (`watch/sync_protocol/`, `watch/contract/`), phone senders (`lib/core/utils`, `lib/state/watch`),
watch engine (`watch/watchos/Sources/WatchSessionEngine`), docs, tests (Dart + Swift).
Layers skipped: `lib/data/models`, `lib/data/repositories`, `lib/features` (no changes), `lib/watch/serve` (Wear client, out of scope D-1408).

## Findings

1. **BLOCKER — the plan and evidence state a readout the product does not print.** `…-plan.md:166` ("the readouts are `\"0:01\"`
   and `\"1440:00\"`"), `…-plan.md:382` (`86400` → `\"1440:00\"`), `…-plan.evidence.md:193` (`\"1440:00\"`/`86_400_000`). Both
   clients render hours as `h:mm:ss` (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:630-639`;
   `lib/core/utils/date_utils.dart:177-184`), so 86 400 s reads **`24:00:00`** — exactly what
   `WatchLoggingTimersTests.testS1412TheEndsOfTheRangeCountDown:425` asserts. The test is right and the two prose rows are
   wrong. Fix: replace `\"1440:00\"` with `\"24:00:00\"` in both plan lines and the evidence row (or delete the readout clause
   and point at `testS1412TheEndsOfTheRangeCountDown`). No code change. → governor (plan/evidence text).
2. **Minor — S-1412's "both validators" half is unverified.** `…-plan.md:166` claims both validators accept 1 and 86 400 s, but
   only the Swift side exercises those values; no Dart test (`grep 86400 test/` → unrelated ms constants only) and no fixture
   carries them. The two clients read one schema file, so the fact is single-sourced, but the Dart walker's acceptance of a
   large length is unpinned. Guard: add a third slot carrying `roundDurationSecs: 86400` to
   `watch/sync_protocol/fixtures/valid/session_snapshot_round_length.json` plus its `manifest.json` row — that row goes red the
   day anyone adds a `maximum` to the schema. → @dba, or governor if the fixtures are out of the fix round's scope.
3. **WARNING — register drift (known, plan Open question 4).** `test/watch_transport_test.dart:863` walks a hardcoded fixture
   list, so the six new `round_length` files get no transport coverage. The register's own walkers
   (`test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift`) do see them, and both suites are green — this is
   missing coverage, not a false claim. One-line list addition. → @developer.
4. **SUGGEST — recorded divergence between the two wrist clients.** The Wear client's `toSlot` writes no field (D-1408), so a
   Wear round counts from its own preset while the Apple Watch counts from the phone's number. Owner-approved scope, recorded in
   the plan (Open question 2) and the Assumption Log; left for a separate one-line plan.

### Verified, no finding

- **One place computes a length.** `_slotFor` (bridge `:468-497`) and `_fallbackJson` (`watch_reference_sync.dart:143-168`) are
  the only emitters; the wrist reads one seam, `plannedRoundMs` (`WatchLoggingState.swift:167-230`), used by both
  `workRemainingSeconds` and `startWork`.
- **D-1412 one capability→kind function.** `WatchEffortKind.precedence` + `fromMetric` (`WatchLoggingState.swift:36-66`) matches
  Dart `ModalityConfig.effortKindFromMetric` (`lib/core/constants/modality_config.dart:243-260`); the wrist's former ad-hoc path is
  gone and the phone's `_effortKind` keeps delegating to the same list.
- **No `Date()` added.** The only occurrence in the touched Swift files is the pre-existing injected default,
  `WatchLoggingState.swift:198`; the harness injects the clock.
- **Leftover mutation restored.** `WatchRoutineRecords.swift:56` reads the catalog again (`roundSeconds(json[roundDurationKey])`).
- **Residue sweep clean.** No `MUTANT`, `XCTExpectFailure` or `XXX` in `watch/watchos`, `lib`, `watch/sync_protocol`, `test` (the
  one `MUTANT` left is a diff quote in plan 15a's evidence, per the Assumption Log; the `skip: true` in
  `test/profile_navigation_test.dart:39` is pre-existing and is the suite's `~1`).
- **`WatchRoutineEffort.slot`'s `roundSeconds(fromMillis:)` fallback** to `self.roundDurationSecs` is benign: the contract's
  `roundRoutine` pins `eff-soccer-open` (round, no `durationMs`) to **no** field, which S-1404 asserts.
- **Docs still true.** `docs/state_management/watch_surface.md:436-438`, `docs/watch-app-setup-and-qa.md:615` and the QA index's
  21b row describe the shipped behaviour (phone's number, else the wrist's preset; QA step 6 extended); the QA index's row 21
  status ("independent review round 1 APPROVE") matches plan 21's own Status line. No doc enumerates the slot's fields, so the
  new wire key makes none of them incomplete. `docs/state_management/watch_surface.md` 51,127 B < the 64 KiB contract.
- **Doc standard.** The three doc edits swap a superseded test citation and add prose pointing at tests; no flow walkthrough, no
  visual values, no control inventory, no restated constant, no roadmap or unshipped-change note.
- **Diff vs Predicted Files: conforms.** Every touched path is in the plan's "Files Affected (whole feature)"; `WatchStartPaths.swift`
  stayed untouched as predicted; no file outside the predicted set.

### Assumption Log adjudication

- RATIFY: the conductor/governor entries on the three wire sources, last-round value, 180 s omitted, the length joining the ladder
  identity, `WatchEffortKind.resolved`, new fixture files over mutations, `_sameSlots` untouched.
- RATIFY: the developer entries on `updateRoundPlannedDuration` over `setRoundDuration`, `_seedPhoneSession`'s defaulted `kinds`,
  the per-test `roundRepository()`, no Phase-2 `docs/` edit, the restored `WatchRoutineRecords.swift:56` mutation and its
  `prove-red` rationale (a Swift guard cannot compile at base), the 15a `MUTANT` quote, the `watch_surface.md` citation swap.
- REVERT: none. ESCALATE: none. The log is complete for a three-phase change — the one thing it does not record is the
  `\"1440:00\"` figure, which is finding 1.
