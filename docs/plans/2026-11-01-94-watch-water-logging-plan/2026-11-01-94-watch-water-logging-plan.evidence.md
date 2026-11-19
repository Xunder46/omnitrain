# Evidence — plan 94 (PR 94a)

## Phase 1 — Contract (@developer, 2026-11-01)

### Pre-edit checks

- Predicted files clean before editing (`git status --short` on `watch/sync_protocol`, `watch/contract`,
  `lib/core/sync_protocol`, `SyncProtocolValidator.swift`: no output).
- Lint baseline (`gateway.sh lint`): **181 issues**, 1 warning (pre-existing
  `test/food_catalog_load_test.dart:270:68 unnecessary_non_null_assertion`), 0 errors.
  Log `.work/gateway/lint-20261101-194557-55518.log`.

### Red — fixtures and manifest written, schemas and validators untouched

`gateway.sh test test/sync_protocol_fixtures_test.dart` → `+143 -13: Some tests failed.`
(log `.work/gateway/test-20261101-194824-56416.log`). Red tests:

| Test | Why red |
|---|---|
| valid/water_down.json, valid/water_down_empty_day.json conform | `unknown_message_type` (no `water_down` type) |
| valid/observations_up_water.json conforms | `"water_glass" is not one of [...]` (no kind) |
| invalid/water_down_* (7 fixtures) rejected as stated | rejected only as `unknown_message_type` |
| invalid/observations_up_water_missing_change.json | reason lacks `glassChange` (kind unknown) |
| invalid/observations_up_water_unknown_change.json | reason lacks `"double" is not one of ["add","remove"]` |
| invalid/observations_up_glass_change_on_set.json | `unexpected_field`, not `semantic_violation` |

Not red: `invalid/observations_up_water_extra_field.json` — an unknown event field (`volumeMl`) was already
refused as `unexpected_field` before 94a; it stays as a regression guard (S-94a-17).

`gateway.sh swift-test --filter SyncProtocolFixturesTests` → `Executed 6 tests, with 28 failures (1 unexpected)`
(log `.work/gateway/swift-test-20261101-194835-56668.log`): 5 of 6 tests red (no schema for `water_down`,
the same refusal mismatches, and the emission pipeline refusing the `water_glass` event as non-conformant).

### Green — Done Criteria

| Command | Result |
|---|---|
| `gateway.sh lint` | **181 issues** (= baseline), same single pre-existing warning, 0 errors. Log `.work/gateway/lint-20261101-195013-57576.log` |
| `gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_transport_test.dart test/watch_nutrition_quick_log_test.dart` | **+256: All tests passed!** Log `.work/gateway/test-20261101-195023-57926.log` |
| `gateway.sh swift-test` (full package) | **Executed 1139 tests, with 0 failures (0 unexpected)**. Log `.work/gateway/swift-test-20261101-195013-57567.log` |

`test/sync_protocol_fixtures_test.dart` alone: `+156: All tests passed!` (143 → 156: the 13 new fixture tests).

Extra readers of the manifest / contract and the AGENTS.md invariants:
`gateway.sh test test/watch_session_engine_test.dart test/live_mirroring_test.dart
test/watch_capture_contract_conformance_test.dart test/watch_session_start_test.dart
test/phone_manage_bridge_test.dart test/watch_second_session_same_exercise_repro_test.dart
test/stats_bests_builder_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
→ **+261: All tests passed!** (log `.work/gateway/test-20261101-195035-58185.log`).
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty.

### Mutation checks (the two semantic rules, which the red run could not isolate)

Original lines (Dart, `message_validator.dart`):
`      case 'water_down':` / `        return _waterRejections(payload);` and `    'glassChange': ['water_glass'],`
Original lines (Swift, `SyncProtocolValidator.swift`):
`        case "water_down":` / `            return waterRejections(payload)` and `        ("glassChange", ["water_glass"]),`

| Mutant | Result | Restored |
|---|---|---|
| Dart: both lines removed | `+154 -2`: `water_down_duplicate_tap.json` and `observations_up_glass_change_on_set.json` red | exact copy restored; diff stat back to 24+/1-; `+156: All tests passed!` |
| Swift: both lines removed | `Executed 6 tests, with 9 failures`: the same two fixtures (validator suite and emission pipeline) | exact copy restored; diff stat back to 26+/1-; `Executed 6 tests, with 0 failures` |

### Footprint

New: `schemas/messages/water_down.schema.json`, 3 valid + 11 invalid fixtures. Edited: `envelope.schema.json` (+8/-1),
`observations_up.schema.json` (+6/-1), `manifest.json` (+106), `message_validator.dart` (+24/-1),
`SyncProtocolValidator.swift` (+26/-1), `PROTOCOL.md` (+41/-1), `watch_start_paths_contract.json` (+2/-1).
No file outside the Phase 1 Predicted Files; no file of the other session touched.

## Phase 2 — Storage (@dba, 2026-11-01)

### Pre-edit checks

- Predicted files clean before editing (`git status --short` on `water_constants.dart`, `models.dart`,
  `sqlite_schema.sql`, `lib/data/repositories/`, `test/db_seed_test.dart`, `docs/data_models.md`,
  `docs/db_integration.md`, `test/helpers/repository_harness.dart`: no output).
- Lint baseline (`gateway.sh lint`): **181 issues**, the same single pre-existing warning, 0 errors.
  Log `.work/gateway/lint-20261101-195322-59719.log`.

### Red — tests written first, no implementation

`gateway.sh test test/water_tap_ledger_test.dart test/db_seed_test.dart` → `+0 -2: Some tests failed.`
(log `.work/gateway/test-20261101-195442-60184.log`): both files fail to compile — `WaterLogEntry` has no
`appliedTapIds`, the repository has no `applyWaterTap` / `getAppliedWaterTapIds`, no `waterGlassesFor`.

### Green

`gateway.sh test test/water_tap_ledger_test.dart test/db_seed_test.dart` → **+29: All tests passed!**
(`water_tap_ledger_test.dart` alone: +18 — 1 constants, 4 model round trip, 6 scenarios × Mock and Hive, 1 Mock `clear()`).

### S-94a-6 red → green (hand-reverted hunk, no `git stash`)

Original line (Hive `saveWaterVolumeForDate`, existing-row branch):
`        'applied_tap_ids': _waterTapIdsOf(existing),`

| Step | Result |
|---|---|
| Line removed (the pre-94a map rebuild) | `+17 -1`: only `water tap ledger — Hive S-94a-6` red, `Expected: ['w-1'] Actual: []` |
| Exact line restored | `+18: All tests passed!` |

### Extra mutation checks (plan's list, both implementations)

Original line (Hive and Mock `applyWaterTap`):
`    if (ledger.contains(tapId) || ledger.length >= kWatchWaterTapsPerDay) {`

| Mutant | Result | Restored |
|---|---|---|
| ledger check dropped (`if (ledger.length >= kWatchWaterTapsPerDay)`) | `+12 -6`: S-94a-4, S-94a-5, S-94a-6 red on Mock and Hive | exact line, both files |
| cap skipped (`if (ledger.contains(tapId))`) | `+16 -2`: S-94a-7 red on Mock and Hive | exact line, both files; `+18: All tests passed!` |

### Done Criteria

| Command | Result |
|---|---|
| `gateway.sh lint` | **181 issues** (= baseline), same single pre-existing warning, 0 errors. Log `.work/gateway/lint-20261101-195657-62270.log` |
| `gateway.sh test test/water_tap_ledger_test.dart test/db_seed_test.dart test/state_test.dart test/nutrition_test.dart test/docs_indexing_contract_test.dart` | **+370 -1** (log `.work/gateway/test-20261101-195704-62439.log`). The one red: `state_test.dart` "NutritionState saveNutritionTargetForDate does NOT modify past dates when forward-propagating" (`Expected: <2500> Actual: <null>`, l.4122) |
| the same five files with `TZ=UTC flutter test …` | **+371: All tests passed!** |

The red test is a nutrition-target test that uses `DateTime.now()` ± one day; this machine is
America/New_York and DST ended today (2026-11-01, a 25-hour day). Alone: red in local time, green under
`TZ=UTC`. No Phase 2 edit reaches nutrition targets. Not edited (another feature's test).

Invariants: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty;
`gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → **+54: All tests passed!**

### Footprint

New: `test/water_tap_ledger_test.dart` (364 lines, `dart format` applied to it only). Edited (`git diff --stat`):
`water_constants.dart` +10, `models.dart` +21, `workout_repository.dart` +21, `hive_workout_repository.dart` +44,
`mock_workout_repository.dart` +28, `sqlite_schema.sql` +15/-3, `db_seed_test.dart` +77, `data_models.md` +2 (+419 B → 47,183 B),
`db_integration.md` +15/-6 (+1,083 B → 41,113 B). Total 233+/9-. No file outside the Phase 2 Predicted Files.

## Phase 3 — Phone applies taps (@developer, 2026-11-01)

### Pre-edit checks

- Predicted files clean before editing (`git status --short` on `nutrition_state.dart`, `watch_records.dart`,
  `watch_reference_sync.dart`, `lib/state/watch/` (only the other session's `watch_session_adoption_bridge.dart`
  dirty, not touched), `docs/state_management/nutrition_state.md`, `docs/nutrition.md`: no output).
- Lint baseline (`gateway.sh lint`): **181 issues**. Log `.work/gateway/lint-20261101-200200-64952.log`.

### Red — tests written first

1. `test/watch_water_log_test.dart` alone, no implementation: does not compile (40 `Error:` lines — no
   `applyWatchWaterTap`, no `WatchWaterLogBridge`, no `WatchIncomingReceipt.water`, no `WatchObservationKind.waterGlass`).
2. API stubs only (`applyWatchWaterTap` returns false, bridge `receive` returns `ignored`, router param unused,
   twin constant): `flutter test test/watch_water_log_test.dart` → **`+2 -14: Some tests failed.`** Red: S-94a-10,
   both S-94a-11, S-94a-12 (`Expected: <500> Actual: <250>`), the throwing-write test, S-94a-13, -14, -15, -16, -17,
   both S-94a-20, S-94a-18, S-94a-19. Green: D-14 twin constant; "a message with no water tap is ignored".

### Green

`flutter test test/watch_water_log_test.dart` → **`+16: All tests passed!`**

### Mutation checks (hand-reverted hunks, no `git stash`; restored file `cmp`-identical to the pre-mutation copy)

| Mutant (original line) | Result | Restored |
|---|---|---|
| Chain removed: `_serialiseWater` body `final result = _waterChain.then((_) => write());` / `_waterChain = result.then((_) {}, onError: (_, _) {});` / `return result;` → `return write();` | `+15 -1`: only **S-94a-12** red, `Expected: <500> Actual: <250>` | identical; `+16: All tests passed!` |
| Day check removed: `if (applied && _waterDayMs == dateMs) {` → `if (applied) {` | `+13 -3`: **S-94a-11** (both: `Expected: <500> Actual: <250>`, `Expected: <0> Actual: <750>`) and S-94a-16 red | identical; `+16: All tests passed!` |
| Count before receipt: swapped `await _acknowledge(acknowledged);` / `if (acknowledged.isNotEmpty) await _sendCount();` | `+10 -6`: S-94a-13, -14, -15, -16, both -20 red | identical; `+16: All tests passed!` |

### Done Criteria

| Command | Result |
|---|---|
| `gateway.sh lint` | **181 issues** (= baseline). Log `.work/gateway/lint-20261101-200704-68011.log`; `flutter analyze` on the 7 touched Dart files: No issues found |
| `gateway.sh test test/watch_water_log_test.dart test/watch_nutrition_quick_log_test.dart test/state_test.dart test/nutrition_test.dart test/watch_session_import_test.dart test/docs_indexing_contract_test.dart` | **+451 -1** (log `.work/gateway/test-20261101-200714-68290.log`). The one red is A-8: `state_test.dart` "NutritionState saveNutritionTargetForDate does NOT modify past dates when forward-propagating" (`Expected: <2500> Actual: <null>`) |
| the same six files, `TZ=UTC flutter test …` | **+452: All tests passed!** |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | empty |

Extra dependents (every test file that builds `WatchIncomingRouter`/`createWatchSync` or drives the water
buttons, plus `water_tap_ledger_test`, `ui_standards_contract_test`, `sync_protocol_fixtures_test`,
`watch_sync_request_handler_test`, `watch_transport_test`, `home_nutrition_summary_card_test`; 40 files, local time):
**+1018 ~1: All tests passed!**

`flutter run`: not exercised (no device or simulator in this run; owner's standing "simulator off by default").
Nothing visible changes until a 94b wrist sends taps; the phone path is covered end to end by S-94a-18/19 through the router.

### Footprint

New: `lib/state/watch/watch_water_log_bridge.dart` (194 lines), `test/watch_water_log_test.dart` (548 lines),
`dart format` applied to these two only. Edited (`git diff --stat`): `nutrition_state.dart` +57/-11,
`watch_reference_sync.dart` +53, `watch_incoming_router.dart` +18/-1, `watch_sync_wiring.dart` +9,
`watch_records.dart` +4, `docs/state_management/nutrition_state.md` +5/-2 (→ 30,910 B), `docs/nutrition.md` +9 (→ 37,975 B).
No file outside the Phase 3 Predicted Files; none of the other session's files touched.

## Phase 4 — Phone sends the count (@developer, 2026-11-01)

### Pre-edit checks

- Predicted files clean before editing (`git status --short` on `watch_transport.dart`, `watch_sync_request_handler.dart`,
  the three test files, `watch_reference_data.md`: no output). `watch_sync_wiring.dart` carried only this plan's Phase 3
  hunk (+9, the `WatchWaterLogBridge` construction). Lint baseline: **181 issues** (Phase 3's closing count).

### Red — tests written first

1. No API: `flutter test test/watch_sync_request_handler_test.dart` does not compile
   (`No named parameter with the name 'wantsWater'`).
2. API stubs only (`routinesFrame(wantsWater:)` ignored, `wantsWaterOf` returns false, `handle(wantsWater:)` ignored):
   the three Phase 4 files → **`+158 -8: Some tests failed.`** Red: S-94a-26 contract pin (`Expected {'request': 'routines',
   'wantsWater': true} Actual {'request': 'routines'}`), S-94a-26 wiring arm, both S-94a-22 transport tests, S-94a-21,
   S-94a-23, S-94a-24 (frame), S-94a-25 (a) — each `Expected: an object with length of <1> Actual: []` or equivalent.
   Green with stubs, as expected for "nothing is sent" cases: S-94a-22 handler, S-94a-24 residue scan, S-94a-25 (b);
   each is proved by a mutant below.

### Green

`flutter test test/watch_sync_request_handler_test.dart test/watch_transport_test.dart test/watch_session_projection_test.dart`
→ **`+166: All tests passed!`**

### Mutation checks (whole-file copies in the session scratchpad; restored file `cmp`-identical, then re-run green)

| Mutant (original line) | Result |
|---|---|
| Truthy read: `frame['wantsWater'] == true;` → `frame['wantsWater'] != null && frame['wantsWater'] != false;` | `+164 -2`: **S-94a-22** red (transport table and handler) |
| Count after bests: `if (wantsWater) await _sendWater();` moved below `await _sendBests(holdsBests: holdsBests);` | `+164 -2`: **S-94a-21** and S-94a-25 (a) red |
| No catch: `_sendWater`'s `try { … } catch (_) { return; }` removed | `+165 -1`: **S-94a-25 (b)** red |
| Wiring drops `wantsWater: WatchTransportRequest.wantsWaterOf(frame),` | `+165 -1`: **S-94a-26** wiring arm red |

After the last restore: `+166: All tests passed!`

### S-94a-24 residue scan (A-11 → A-12)

The test reads every `lib/**/*.dart` file, skips lines whose trimmed text starts with `//`, and expects only
`lib/core/constants/water_constants.dart` to contain `~/ kWaterGlassMl`. Raw `grep -rn "~/ kWaterGlassMl" lib` also lists
comment lines in `water_tracker_control.dart:21` and `models.dart:2377` (not edited).

### Done Criteria

| Command | Result |
|---|---|
| `flutter analyze` | **181 issues** (= baseline); the six touched Dart files alone: `No issues found!` |
| `flutter test` (full suite, local America/New_York, 900 s wrapper) | **`+6021 ~2 -1: Some tests failed.`** (03:49). The one red is A-8: `test/state_test.dart` "NutritionState saveNutritionTargetForDate does NOT modify past dates when forward-propagating" |
| `TZ=UTC flutter test` (full suite) | **`+6022 ~2: All tests passed!`** (03:52) |
| `swift test` in `watch/watchos` | **Executed 1139 tests, with 0 failures (0 unexpected)** |
| `ui_standards_contract_test` + `docs_indexing_contract_test` (also inside both full runs) | **`+54: All tests passed!`** |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | empty |
| Verify-only, unedited: `watch_sync_changed_only_test`, `watch_sync_idle_reads_test`, `rest_ping_contract_test`, `watch_accent_contract_test`, `watch_message_order_test` | **`+53: All tests passed!`** |

No hang in either full run.

Residue sweep `grep -rln "water_down\|wantsWater\|water_glass" lib watch/sync_protocol watch/contract test docs`: only
files of Phases 1-4 (the validator, builders, bridge, twin, constants comment, transport, handler, wiring, schemas,
fixtures, manifest, PROTOCOL.md, contract, the four test files, `watch_reference_data.md`, this plan and evidence).

`flutter run`: not exercised (no device or simulator; owner's standing "simulator off by default"). No wrist sends
`wantsWater` until 94b, so nothing the owner sees changes.

### Footprint

Edited (`git diff --stat`): `watch_transport.dart` +13, `watch_sync_request_handler.dart` +35/-1,
`watch_sync_wiring.dart` +2/-1 in Phase 4, `test/watch_sync_request_handler_test.dart` +268,
`test/watch_transport_test.dart` +74, `test/watch_session_projection_test.dart` +32,
`docs/state_management/watch_reference_data.md` +26 (→ 21,465 B). No formatter run (all edited files pre-existed).
No file outside the Phase 4 Predicted Files; none of the other session's files touched.
Plan file is now 54,170 B: over the ~52 KB split band, under the 64 KiB ceiling.

## Docs (PR 94a, after the review fixes)

| Doc | Result |
|---|---|
| `docs/state_management/watch_surface.md` | updated (review fix): `WatchWaterLogBridge` named among the router's owners and in the graph summary; pointer S-94a-18. 50,865 B |
| `docs/state_management/watch_reference_data.md` | updated (Phase 4): `wantsWater`, `routinesWater`, the `water_down` frame; review fix removed the two "PR 94b" schedule sentences. 21,266 B |
| `docs/state_management/nutrition_state.md` | updated (Phase 3): `waterTodayGlasses`, `applyWatchWaterTap`, the write chain; review fix dropped "250 ml" after `kWaterGlassMl` in the `waterTodayGlasses` row |
| `docs/nutrition.md` | updated (Phase 3): "Glasses tapped on the watch"; review fix removed the false "reach the watch at the next sync" clause |
| `docs/data_models.md` | updated (Phase 2): `appliedTapIds`; review fix dropped "(500)" and added the `applyWatchWaterTap` row to the water cache table |
| `docs/db_integration.md` | updated (Phase 2): the two repository methods, the ledger; review fix dropped "(500)" and made the Hive ledger-key sentence true (absent on a pre-ledger row or one created by the phone's own +, until its next write — `hive_workout_repository.dart` `saveWaterVolumeForDate`) |
| `watch/sync_protocol/PROTOCOL.md` (outside `docs/`) | updated (Phase 1) |
| `docs/navigation_and_screens.md` | no update required: no screen, route or constructor dependency changed |
| `docs/widget_catalog.md` and `docs/widget_catalog/*` | no update required: no reusable widget or prop changed |
| `docs/state_management/watch_surface_wrist.md` | no update required: no wrist code changed in 94a (D-1) |
| `docs/watch_session_capture.md` | no update required: its router sentence ("calls the inbox before the mirror and the nutrition bridge") stays true |
| `docs/state_management.md` | not updated (gap, not false): the class index has no `WatchWaterLogBridge` row; left for the governor (outside this fix round's list) |
| `docs/constants_reference.md` | not updated (gap, not false): the `water_constants.dart` table lists `kWaterGlassMl` only, not `kWatchWaterTapsPerDay` or `waterGlassesFor`; left for the governor |

## Review fixes (2026-11-01, @developer)

Docs and contract wording only; no source or test file changed. Lines changed:
- `docs/state_management/watch_surface.md` :628 "nutrition bridge" → "nutrition and water bridges"; :676-678 owner list + `WatchWaterLogBridge` with pointer `test/watch_water_log_test.dart`, S-94a-18.
- `docs/nutrition.md` :430-431 clause "its own + and − reach the watch at the watch's next sync" deleted (other session's hunks untouched).
- `docs/state_management/watch_reference_data.md` sentence "The phone reads it today; the Swift wrist starts sending it in PR 94b (plan 94, D-9)." and sentence "How the wrist turns the frame plus its own unsent taps into the number it shows is plan 94 D-7, built in PR 94b." deleted.
- `docs/data_models.md` :539 "(500)" dropped; cache table + `applyWatchWaterTap` row (points at nutrition_state.md).
- `docs/db_integration.md` :273 "(500)" dropped; :288-289 ledger-key sentence rewritten.
- `docs/state_management/nutrition_state.md` :58 ", 250 ml" dropped.
- `watch/contract/watch_start_paths_contract.json` description: "the four request frames" → "the request frames", "the three ways" → "the ways"; rows byte-identical; `json.loads` ok.

Checks:
- `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart test/sync_protocol_fixtures_test.dart test/watch_transport_test.dart test/watch_session_projection_test.dart` (900 s wrapper): `+335: All tests passed!`, exit 0.
- `flutter test test/watch_session_start_test.dart` (the other Dart reader of the contract JSON): `+43: All tests passed!`.
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`: empty (exit 1).
- Not run: `swift test` (no Swift reader decodes the `description` key; JSON validity checked).
