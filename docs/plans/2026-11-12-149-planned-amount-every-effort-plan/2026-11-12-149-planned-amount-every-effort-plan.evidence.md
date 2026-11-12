# Evidence — plan 149 (planned amount on every effort)

Companion to `2026-11-12-149-planned-amount-every-effort-plan.md`. Implementers fill the red→green tables per phase; the reviewer re-runs every grep row below.

## Baselines

- `flutter analyze`: **181 issues** (pre-existing info notices; the repo exits non-zero regardless). Every Done Criterion compares against this number — the pass condition is "no NEW issues", not "exit 0".
- `flutter test` full suite: several minutes; run with the gateway's 900 s timeout. Widget tests hang in FakeAsync when a real `Future.delayed` or a Hive write is awaited inside `testWidgets`: run widget tests Mock-first (`--plain-name "Mock"`), keep persisting taps Mock-only, seed Hive in `setUp`. A test file whose Mock group is red can leave its Hive group hanging behind it: fix the red group first instead of re-running the whole file.
- `swift test` in `watch/watchos`: compiles the watch package; the watch app target itself needs `xcodebuild`, which only the governor runs.
- Uncommitted neighbours: plans 144/145/146 and the wrist hold-Next fix (`WatchRestNextHoldTests.swift`) live in this tree — their tests may be red for reasons outside plan 149; a failure there is compared against their own state, never "fixed" here.

## Research table (the seed's five questions, settled with file:line)

| # | Question | Answer | Evidence |
|---|----------|--------|----------|
| 1 | Where `plannedSets` is built; per-kind planned storage | Writer in the projection, set-kind gated; every kind already stores its planned rows | `lib/state/watch/watch_session_adoption_bridge.dart:272-291` (plannedSets block), `:416` (`_wireKind` drill→hold), `:546-575` (`_slotFor`, effortKind only when declared, `:67`); `session_core_io.dart:291-377` (`populateSessionFromManifest`, `entry.setCount` rows :359-361); `session_core_entry.dart:160+` (`addEntry`: round branch :182-195, timed/drill :200-226, set :259-279), `seedFirstEntry` :129-152; `models.dart` `TemplateTarget` :855-905 (setIndex key), `RoundInstance` :1110, `TimedInstance` :1310; count rule `routine_session_service.dart:88-99` + editor `routine_setup_screen.dart:1230-1238` |
| 1b | Adoption gap | Adopted sessions seed planned rows for SET kind only | `watch_session_adoption_bridge.dart:1110` (gate), `:1174-1196` (`_createPlannedRows`), `:1199` (`_plannedValue`), `:1247` (`_plannedSetCount`) → Phase 3 |
| 2 | Contract shape + compatibility | Additive optional integer `plannedEfforts` (min 1) on the closed slot object; both validators are schema-driven, no validator code change | `PROTOCOL.md:324-331` (plannedSets paragraph), `:333` (next heading), `:833-876` (version table; 2026-10-15 row :858 is the pattern), `:871` (2026-11-06 planned_down row); `envelope.schema.json:106-160` (`$defs.sessionExercise`, `additionalProperties: false` :113, plannedSets :146); `SyncProtocolValidator.swift:8-26`; `message_validator.dart:965` |
| 3 | The watch's done rule and its readers | Planned only from plannedSets → non-set kinds done after ONE effort; rounds wedge (unbounded "Period k+1"); set-only gates; menu is kind-agnostic; NO Dart twin | `WatchRestLabels.swift:62` (isDone), `:47-54` (nextLabel), `:74-134` (deriveRestLabels; set branch :111-121, round branch :122-124, planned read :98); `WatchLoggingState.swift:335` (setCaption), `:480-497` (leaveRest), `:536-548` (restLabels/nextRound), `:652-658` (roundsLabel), `:661-669` (nextRoundNumber), `:698-707` (plannedSets getter), `:703-708` (setsHeld), `:857` (initialValue), `:37-60` (WatchEffortKind, eventKind drill→hold); `WatchMenu.swift:263-267` ("N logged"); `WatchWorkoutSummary.swift:142`; grep `deriveRestLabels\|WatchRestLabelCopy\|nextSlotId` over `lib/`+`test/` → zero matches |
| 4 | Phone read-back of plannedSets | None — projection is write-only for both keys | grep `plannedSets lib/state/watch/` → `:286` (writer), `:657` (ladder `_ladderOf` :650-658), `:615` (comment); `heldWristEntryIds` :432-476 claims by entry kind |
| 5 | Tracks / PR split | Contract + phone + Swift watch → 3 PRs (index in the plan) | `.github/copilot/pr-scope-budget.md` |
| — | Self-extension source | The importer writes a new row per logged past-plan effort, every kind | `watch_session_importer.dart:1422-1500` (`_createEntry`), `createTimedInstance` :1511, `createRoundInstance` :1552 |

## Red→green tables (implementers fill in)

### Phase 1 (contract)

| Check | Suite/ walker | Red evidence | Green evidence |
|---|---|---|---|
| Valid plannedEfforts frame conforms (Dart) | `test/sync_protocol_fixtures_test.dart` (S-001 fixtures) | `prove-red HEAD test test/sync_protocol_fixtures_test.dart` → **GREEN AT HEAD**: fixtures and schema are data on disk at HEAD, so the check passes without the change; mutation used instead — schema `plan … "minimum": 1` → `0`, then `test/sync_protocol_fixtures_test.dart --plain-name S-001`: `invalid/session_snapshot_planned_efforts_zero.json is rejected as constraint_violation [E]` / `Expected: non-empty` / `Actual: []` (`+113 -1`); original restored | **182 passed** (`All tests passed!`, `.work/gateway/test-20261112-122728-87746.log`) |
| Valid plannedEfforts frame conforms (Swift) | `SyncProtocolFixturesTests.testEveryValidFixtureConforms` | same GREEN-AT-HEAD reason; mutation proof recorded with the Dart walker above (one schema, both walkers) | 6/6 in `swift-test --filter SyncProtocolFixturesTests` |
| Refusals 0 / 2.5 / "3" (Dart) | same file | mutation above (0 accepted once `minimum` is relaxed) | 182 passed (`S-001 fixtures invalid/session_snapshot_planned_efforts_{zero,fractional,string}.json …`) |
| Refusals (Swift) | `testEveryInvalidFixtureIsRejectedAsStated` | same mutation | 6/6 |
| Lint | `gateway.sh lint` | baseline 181 | 181 issues, none in a touched file |

### Phase 2 (phone sends)

| Scenario | Test (Mock-first) | Red | Green |
|---|---|---|---|
| S-14901 drill slot carries 3 | `test/watch_session_projection_test.dart`, group `S-14901 the phone sends the planned efforts` — `S-14901 a drill slot carries how many holds it plans` | `prove-red HEAD test test/watch_session_projection_test.dart --plain-name "S-1490"` → **RED AT HEAD** (exit 1): `Expected: <3>` / `Actual: <null>` at `:2956` | group 5/5 passed |
| S-14902 round 4 + timed 2; set slot clean (S-14903) | same — `S-14902 a round and a timed slot carry their own counts`, `S-14903 a set slot never carries a count` | same run: `Expected: <4>` / `Actual: <null>` at `:3013` (S-14902); S-14903 passes at HEAD by design (no key today, no key after) | 5/5 |
| S-14904 no rows → no key | same — `S-14904 a slot with no planned effort carries no count` | passes at HEAD by design (an absent key is the pre-change state); its post-change meaning is pinned by S-14901/S-14902 running in the same group | 5/5 |
| S-14906 revision rises, S-14907 grows to 4 | same — `S-14906/S-14907 a fourth effort moves the count and the revision` | same run: `Expected: <3>` / `Actual: <null>` at `:3122` | 5/5 |
| Whole-slot pins | `S-1411` (`watch_session_adoption_bridge_test.dart:1519`), auto-push suite | — | no pin changed: every whole-slot pin in this tree holds `set` slots, which carry no `plannedEfforts`; sweep 232/232 green |

### Phase 3 (adoption seeds)

| Scenario | Test | Red | Green |
|---|---|---|---|
| S-14908 adopted holds/periods seeded + projected | `test/watch_session_adoption_bridge_test.dart`, group `S-14908 the adoption seeds the non-set plan` — `S-14908 an adopted routine session seeds its planned holds and periods` | `prove-red HEAD test test/watch_session_adoption_bridge_test.dart --plain-name "S-1490"` → **RED AT HEAD**: `Expected: an object with length of <3>` / `Actual: [Instance of 'TimedInstance']` | 2/2 in the group |
| S-14909 no-target template → defaults | same — `S-14909 a template with no per-index targets still seeds the count` | same run: `Expected: <1>` / `Actual: <null>` | 2/2 |
| D-3 set-row adoption byte-identical | existing group in the same file | — | green in the 232-test sweep (adoption, routine adoption, projection, auto-push, cross-stack reconciliation) |
| Residue grep: `grep "set efforts start with the routine's planned rows" docs/` → only amended text | — | — | zero matches (the sentence is rewritten in `docs/watch_session_sync.md:46`) |

### PR 1 — final run log

- `test/watch_session_projection_test.dart` (group `S-14901 the phone sends the planned efforts`): 5/5 passed on the change, RED AT HEAD before it (above).
- `test/watch_session_adoption_bridge_test.dart` (group `S-14908 the adoption seeds the non-set plan`): 2/2 passed, RED AT HEAD before it (above).
- Regression sweep — `test/watch_session_adoption_bridge_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_session_auto_push_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`: **232 passed, 0 failed**.
- `test/sync_protocol_fixtures_test.dart`: **182 passed** (Phase 1, after the schema restore).
- `sync_protocol_fixtures` (Swift): 6/6 passed.
- `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart`: **54 passed** (no allowlist entry added, no ratchet raised; the doc edits stay under the 64 KiB ceiling).
- Full suite `gateway.sh test`: **7452 passed, 2 skipped, 0 failed** — `All tests passed!` (`.work/gateway/test-20261112-122803-88087.log`, tail `05:13 +7452 ~2: All tests passed!`).
- `gateway.sh lint`: **181 issues found** — the baseline, and none in a touched file (`.work/gateway/lint-20261112-122755-87995.log`).
- Invariant: `grep -r hive_workout_repository lib/` → `lib/main.dart` only (the startup wiring); nothing in `lib/state`, `lib/features`, `lib/widgets` or `lib/core`.

## Phase 3 doc residue (reviewer re-runs)

`grep -rn "set efforts start with the routine's planned rows\|no planned count on the wire\|get no planned" docs/` → no live doc page matches; the only hits are historical artefacts (`docs/plans/2026-10-15-36c-routine-adoption-plan/*.review.md` and this plan's own step text). The amended pages (`docs/watch_session_sync.md`, `docs/watch_session_sync/what_does_not_sync.md`, `docs/state_management/watch_surface_wrist_pager.md`) now say every declared kind's plan travels, and the wrist pager page says the engine does not read it until PR 2.

## Predicted intermediate states (reviewer checks against the diff)

- After Phase 1: both validators accept the declared key; every client ignores it (`WatchPlannedSetsTests.swift:329` shows the drill slot ignoring `plannedSets` today — the same class). No behaviour change.
- After Phase 2: the wrist receives `plannedEfforts` it does not yet read; phone pins updated where whole non-set slots are asserted.
- After Phase 3: wrist-started routine sessions hold planned rows for every declared kind; set rows byte-identical.
- PR 2/PR 3: nothing changes on the wrist until then; `WatchMenu`, `WatchWorkoutSummary`, `WatchRestView`, the importer and `phone_entries.dart` are named read-only dependents.
