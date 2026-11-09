# Review — PR 94a (watch water logging: contract + phone)

Reviewer: code-reviewer (Claude Code), 2026-11-01. Phases 1-4 reviewed against the plan and the
working tree. No source, test, doc or fixture was edited; no git state changed.

## Scope

Layers in scope: models, persistence, state, core (constants, utils, platform, sync_protocol), Dart
twin (`lib/watch/session`), Swift validator, sync contract (schemas, fixtures, PROTOCOL.md, contract
JSON), SQL contract, docs.
Layers skipped: screens (`lib/features/`), shared widgets (`lib/widgets/`), wrist views (no 94a change).

Shared checkout: files changed by another session (food form, nutrition screens, exercise editor,
`workout_state.dart`, `session_core_entry.dart`, `watch_session_adoption_bridge.dart`,
`docs/state_management/workout_state.md`, several tests, `scripts/*.sh`) and the uncommitted step-1
Home change (`WatchStartView.swift`, `WatchNutritionWiringSourceTests.swift`,
`docs/state_management/watch_surface_wrist.md`, `ios/OmniTrain Watch App/ContentView.swift`) were
out of scope. None of their hunks mentions water, `wantsWater` or glasses (diff grep), so 94a did not
touch them and they are not counted.

## Diff vs Predicted Files

Conforms. Every predicted file of Phases 1-4 is touched (14 new fixtures, new schema, new bridge, two
new test files, 33 edited paths); no 94a hunk outside the predicted set.

## Checks run by the reviewer

| Check | Result |
|---|---|
| `flutter test` full suite, local (America/New_York), 900 s wrapper | `+6021 ~2 -1: Some tests failed.` (04:01, no hang). The one red is A-8, `state_test.dart` "NutritionState saveNutritionTargetForDate does NOT modify past dates when forward-propagating" (`Expected: <2500>`) — DST day, not a finding |
| `TZ=UTC flutter test` full suite, 900 s wrapper | `+6022 ~2: All tests passed!` (04:20, exit 0) |
| Scenario tests by name (`--plain-name "S-94a"`, per file) | `watch_water_log_test` +13, `water_tap_ledger_test` +12, `watch_sync_request_handler_test` +7, `watch_transport_test` +3, `watch_session_projection_test` +1, `db_seed_test` +1 — all passed; D-14 test +1 |
| Targeted files incl. `sync_protocol_fixtures_test` (S-94a-1/2), `ui_standards_contract_test`, `docs_indexing_contract_test`, `watch_nutrition_quick_log_test` | `+459: All tests passed!` |
| `swift test` in `watch/watchos` | Executed 1139 tests, 0 failures (0 unexpected), exit 0 |
| Hive import invariant grep | empty |
| Docs > 64 KiB outside `docs/plans/` | none; plan file 54,170 B (over the 52 KB band, under the ceiling) |
| Fixtures vs S-94a-1/2 | 3 valid + 11 invalid on disk, manifest codes and reason substrings match the scenario text; `water_down_over_500.json` holds 501 unique ids (isolates `maxItems` from the duplicate rule) |
| Hive `put` atomicity (D-5) | hive 2.2.3 `BoxImpl._writeFrames` inserts into the keystore synchronously (`keystore.beginTransaction`) before its first await, so read-check-put in `applyWaterTap` cannot interleave on one isolate |
| Inbound serialization | `WatchConnectivityTransport._dispatch` runs handlers one at a time on `_lane` (`lib/core/platform/watch_transport.dart:437-443`) |

## Findings

Severity | file:line | finding | fix | route. Kind in brackets.

### Blocking (document made false / prohibited content added)

- 🔴 REJECT [mechanical] | `docs/state_management/watch_surface.md:675-676` (and the graph summary at :628) | The router's owner list ("`WatchSessionInbox`, `LiveSessionMirrorState` and `WatchNutritionLogBridge`") is now false: every message is also handed to `WatchWaterLogBridge` (`lib/state/watch/watch_incoming_router.dart:177`). D-15 skipped this file for size, not accuracy. | Add the water bridge to the owner sentence and the :628 parenthesis, pointing at `test/watch_water_log_test.dart` (`S-94a-18 taps never touch workout history`); ~150 B keeps the file (50,743 B) under the band. Guard: a source-scan test that every constructor parameter of `WatchIncomingRouter` is named in that section. | @developer
- 🔴 REJECT [mechanical] | `docs/nutrition.md:430-431` | "its own + and − reach the watch at the watch's next sync" is untrue of the shipped product: no wrist sends `wantsWater` or shows a water count until 94b. | Delete the clause; 94b adds it back with a pointer to its Swift test. Guard: 94b's doc step cites the test that proves it. | @developer
- 🔴 REJECT [mechanical] | `docs/state_management/watch_reference_data.md:168-169`, `:307-308` | Standard §3.7 scheduled-change notes: "the Swift wrist starts sending it in PR 94b" and "built in PR 94b". | Delete both sentences (the plan keeps the delivery schedule). Guard: add a "(starts|built|lands) … in PR <n>" pattern to `test/docs_indexing_contract_test.dart`. | @developer
- 🔴 REJECT [mechanical] | `docs/data_models.md:539`, `docs/db_integration.md:273`, `docs/state_management/nutrition_state.md:58` | Standard §3.4 numbers restated from constants: "(500)" after `kWatchWaterTapsPerDay` (both docs) and "250 ml" in the rewritten `waterTodayGlasses` row. | Name the constant only; drop the values. Guard: a docs contract check that a backticked `k[A-Z]\w*` constant is not followed by a parenthesized number. | @developer

### Warnings

- 🟡 WARNING [design — decision] | `lib/state/watch/watch_sync_wiring.dart:285-290` | AC-6 / S-94a-17 hold only when a validator is injected; production builds `WatchWaterLogBridge` without one (as it builds the food bridge — pre-existing, every phone-side receiver in production runs `evaluateOrAccept(null, …)`). On a real phone a tap envelope with an extra field is applied and acknowledged; only `glassChange` outside add/remove is skipped by the bridge's own guard. The Swift emission pipeline validates before sending, so a shipped wrist cannot produce one. PROTOCOL.md's "a refused message applies and acknowledges nothing" is true only of a validating receiver. | Governor decides: record "the phone trusts the wrist's emission validation" as a D-n, or plan production validation for all bridges as its own PR. Not a 94a fix. | governor
- 🟡 WARNING [mechanical] | `watch/contract/watch_start_paths_contract.json:2` | The description still says `transportRequests` "pins the four request frames … the three ways it asks for routines"; the block has six rows. 94a extended this sentence and left the counts (stale since 87c, now worse). | Drop the counts from the sentence; existing rows stay byte-identical. | @developer
- 🟡 WARNING [doc incomplete] | `docs/data_models.md:545-556`; `docs/db_integration.md:288-289` | The "Daily Water State Cache" table omits `applyWatchWaterTap` and the cache day (nutrition_state.md has them); db_integration.md says the Hive ledger key is "absent on a row written before plan 94", but a row first created by `saveWaterVolumeForDate` today also has no key (`hive_workout_repository.dart:2507-2513`). Silent, not false. | Optional: point the table at nutrition_state.md rather than add a row; drop "written before plan 94" or say "absent until the first tap". | @developer
- 🟡 WARNING [process] | `…evidence.md` (Phases 1-4) | There is no Docs section naming each implicated doc as updated or "no update required"; that is how watch_surface.md's false owner list went unnoticed. | Add one with the 4d result once the REJECTs are fixed. | @developer

### Suggestions

- 💡 SUGGEST [design] | `lib/core/utils/watch_reference_sync.dart:665-666` | `readWaterDown` reads the volume and the ledger in two awaits outside the `NutritionState` chain. A tap landing between them would give a frame whose `glasses` excludes a tap its `appliedTapIds` lists (wrist undercounts by one until the next frame). The inbound `_lane` prevents this in production, except after a `_handlerTimeout` lets the lane move on. | A single repository read returning volume and ledger together; guard with a repository subclass that applies a tap between the two reads. | @developer
- 💡 SUGGEST [decision for 94b] | D-3 vs D-7 | A tap past the 500 cap is acknowledged but never listed in `appliedTapIds`, so D-7's fold would count it on the wrist forever (wrist > phone by one per capped tap). Practically unreachable. | 94b decides: leave a receipted tap out of the fold, or accept it. | planner (94b)
- 💡 SUGGEST [mechanical] | `lib/state/nutrition_state.dart:29` | The edited comment line is 127 columns. | Reflow to 80. | @developer

## Behavioural verification

**4a Acceptance criteria.** AC-1..AC-7 each have an implementation and a test: AC-1 manifest suites (both stacks); AC-2
`water_tap_ledger_test` S-94a-3/4 + `watch_water_log_test` S-94a-20; AC-3 S-94a-5 (restart on Hive) + S-94a-14; AC-4
S-94a-15; AC-5 S-94a-8/16; AC-6 S-94a-17 (validator injected — see the design WARNING); AC-7 S-94a-21..24.

**4b Scenarios.** 26/26 have a test. The fixtures match the scenarios, adversarial ones included:
duplicate delivery (S-94a-5 across `restart()` on Hive, S-94a-14 identical envelope); minus at 0 (S-94a-4 repo, S-94a-20a
bridge, row asserted on Hive); both devices apart (S-94a-15 phone + then two wrist taps, 1250 ml); midnight (S-94a-16, clock
00:00:30 local, frame day `2026-11-02`, D at 750); non-multiple of 250 (100 and 600 ml in S-94a-3, 600 in S-94a-20b and
S-94a-21); empty foods/routines (S-94a-23 asserts both empty); unknown/extra fields (S-94a-17: event `volumeMl`, `"double"`,
payload `note`). S-94a-12 runs `Future.wait` on the real chain; S-94a-6/11/12/13/21/22/25/26 have recorded mutants in the
evidence file. Bridge scenarios run on Mock only, as the scenario fixtures state; storage scenarios S-94a-3..8 run on both.

**4c Test run.** The evidence pastes real counts for every phase, and they match the reviewer's runs (table above:
same +6021/-1 local and +6022 UTC, same 1139 Swift). Red-before-green is recorded for every bug-class test (S-94a-6,
S-94a-11, S-94a-12, and the Phase 1/4 mutants).

## Verdict

❌ Changes requested — docs only. The code, the contract and the tests meet every acceptance criterion and the
architecture holds. Four doc findings are rejections under 4d/4e (one owner list made false, one false clause about the
watch, two classes of prohibited content). All are mechanical, about 10 lines in total. Critical 4 (docs) | Warnings 4 |
Suggestions 3.

**4d Doc falsification.** Most docs carry no scope block, so they are all implicated (rule 4). Each was
checked by grepping every touched surface (water, ledger, `WatchIncomingRouter`, `transportRequests`, frame order,
message families, slotless kinds, `SqliteWorkoutRepository`), and every hit was read.
- DOC FALSIFICATION: ❌ REJECT — `docs/state_management/watch_surface.md:675` — owner list omits `WatchWaterLogBridge` → point at S-94a-18
- DOC FALSIFICATION: ❌ REJECT — `docs/nutrition.md:430` — phone taps "reach the watch" — no wrist reads the count yet → delete the clause
- DOC FALSIFICATION: 🟡 WARNING — `docs/data_models.md` cache table, `docs/db_integration.md:288` — incomplete (see Warnings)
- DOC FALSIFICATION: 🟡 SCOPE — `docs/state_management/watch_reference_data.md` — its scope says the owning code is Swift + protocol, but it now documents the phone handler (`watch_sync_request_handler.dart`); verified anyway
- DOC FALSIFICATION: ✅ PASS — PROTOCOL.md (every cited path exists; the rules match the code and both validators), `docs/state_management/nutrition_state.md` (chain, cache-day and test pointers match the code), `docs/db_integration.md` table rows, `docs/data_models.md` ledger paragraph. Every cited test was found by its exact group and test name.
- Pre-existing and not 94a's: `docs/db_integration.md:154,363,542,583,746` still say "future `SqliteWorkoutRepository`" (false since the retirement); out of scope, worth a cleanup PR.

**4e Doc standard.** DOC STANDARD: ❌ REJECT — §3.7 in watch_reference_data.md; §3.4 in data_models.md, db_integration.md, nutrition_state.md (see Blocking).

**4f Conventions.** PASS (8): repository interface only from state/core, constructor DI, no concrete storage
import, constants in `lib/core/constants/`, plain `test()` for state, both repositories value-for-value, model symmetric
serialization, no formatter on the tree. N/A (3): UI, buttons and design-system rules (no screen or widget touched).

**4g Impact.** All 12 rows checked; greps re-run match: 2 `implements WorkoutRepository`; 21 `WatchIncomingRouter(` files;
`handle(` single production caller; `WatchObservationKind.all` read only by the closed-set test; `water_log` touched only by
Hive. No unlisted reader found. `water_down` is not in `_queueable` (D-6). A remove at 0 leaves a 0 ml row where the phone's
own minus leaves none; no reader distinguishes a 0 ml row from no row (only `getWaterVolumeForDate` reads it).

## Design checks asked for

- **At-most-once ledger.** Sound under the concurrency the plan describes: (1) the repository check-and-write is
  synchronous on both implementations (Mock fully, Hive up to the keystore insert); (2) every `NutritionState` water write
  is serialized on one chain, so the phone's read-modify-write cannot overwrite a tap; (3) inbound frames are serialized on
  the transport lane; (4) `saveWaterVolumeForDate` carries the ledger (S-94a-6, mutant proven). The remaining exposures are
  the torn read (SUGGEST) and a phone time-zone change between a delivery and a redelivery, which can move a tap to
  another day's ledger (the plan excludes time-zone mismatch, D-7).
- **Swift/Dart validator parity.** The same four additions on both stacks (message type, slotless kind, capture field,
  duplicate rule with identical text and path); the semantic layer runs only after the schema passes on both (Dart
  `message_validator.dart:204`), so Dart's force-unwrap of `appliedTapIds` and Swift's `?? []` cannot diverge. Proven by
  the shared manifest on both stacks and the evidence's mutants on each.
- **A-3 departure** (single `applyWaterTap` write instead of increment/decrement). Safe: same math and clamp (S-94a-3 parity
  on Mock and Hive vs the phone's buttons); the phone's buttons are unchanged and still go through the chain; the one
  observable difference (a 0 ml row after a wrist minus at 0) has no reader.

## Assumption Log rulings

RATIFY: A-1, A-2, A-5 (owner), A-3, A-4, A-6, A-7, A-9, A-10, A-12 (supersedes A-11). Recommend promoting A-3, A-9 and A-10
to decisions so 94b binds to them. A-8 is not a finding (DST day; see Test runs).

## Scope triage (pr-scope-budget §1 "At review")

4 blocking findings, all docs, all mechanical (≈ 10 lines across 5 docs); 4 warnings, one of them a governor decision.
Fewer than 6 substantive findings and none spans layers in code: fix the 4 REJECTs and the contract-description count in
one round, with no second review loop. The validator decision (WARNING 1) and the torn-read suggestion go to a follow-up
plan if the governor wants them.
