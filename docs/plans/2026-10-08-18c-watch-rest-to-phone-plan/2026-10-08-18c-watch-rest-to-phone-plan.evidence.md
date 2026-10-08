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
| 1A | S-330 wire | `test/sync_protocol_fixtures_test.dart` (manifest walks the four new fixtures) | run with the fixtures + manifest rows in place and the schemas unchanged — must fail on the unknown kind | `+95` all passed |
| 1A | S-330 window rule | `test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift` (`invalid/observations_up_rest_not_after.json`) | see below | `+95` / swift 376 / 0 |
| 1B | S-320/332/333/334/335 (Dart) | `test/watch_session_rest_timer_append_test.dart` | `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_rest_timer_append_test.dart` must **fail** | |
| 1B | S-320/322/331/332/334/335/336/339 (Swift) | `WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift`, `WatchSessionEngineTests.swift`, `WatchFileStoreTests.swift` | | |
| 2 | S-320/323/324/326/327/328 | `test/watch_session_import_test.dart` (`the wrist’s rests (D-210)`), `test/watch_session_rest_timer_append_test.dart` (`S-320 a wrist rest lands beside the phone's running rest`) | `prove-red dc69aa3 test test/watch_session_rest_timer_append_test.dart` → **RED AT**, `Expected: [0, 1] Actual: [0]`; `prove-red dc69aa3 test test/watch_session_import_test.dart` → RED AT but as a *load* error (the base has no `WatchInboxEntry.kindRest`), so the import group is proved by two mutations — see below | import group `+6`; rest-timer file `+2`; both files in the Done Criteria run `+105` |
| 2 | S-320/325/328/337/338 + repository parity | `test/watch_session_merge_test.dart` (Mock and Hive) | `prove-red dc69aa3 test test/watch_session_merge_test.dart` → **RED AT**, 12 assertion failures (6 Mock + 6 Hive), pasted below | `+12` (`--plain-name "the wrist's rests"`) |
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

## Phase 1A — red first, then green

Items 5–6 (the four fixtures and their manifest rows) landed first; with items 1–4 absent the Dart suite was run and
failed on the new kind, exactly as the brief asked. Pasted failure (`flutter test test/sync_protocol_fixtures_test.dart`,
`+66 -3`):

```
00:00 +24 -1: S-001 fixtures valid/observations_up_rest.json conforms to observations_up [E]
  Expected: empty
    Actual: [
              'invalid_enum_value at $.payload.events[1].kind: "rest" is not one of ["set","timed","round","hold","nutrition_quick_log","effort_rating","session_end"]',
              'unexpected_field at $.payload.events[1].afterEntryId: field "afterEntryId" is not defined by the schema',
              'no_matching_variant at $.payload.events[1]: value matches 0 of 7 allowed shapes (first mismatch: required field "reps" is missing)',
              ...
            ]
00:00 +65 -2: S-001 fixtures invalid/observations_up_rest_missing_after_entry_id.json is rejected as missing_required_field [E]
  Expected: contains 'afterEntryId'
    Actual: '"rest" is not one of ["set","timed","round","hold","nutrition_quick_log","effort_rating","session_end"] | ...'
     Which: does not contain 'afterEntryId'
00:00 +66 -3: S-001 fixtures invalid/observations_up_rest_not_after.json is rejected as semantic_violation [E]
  Expected: contains 'semantic_violation'
    Actual: [ 'invalid_enum_value', 'unexpected_field', 'no_matching_variant', ... ]
     Which: does not contain 'semantic_violation'
00:00 +66 -3: Some tests failed.
```

After items 1–4 (schema kind + `afterEntryId`, the eighth `oneOf` branch, and the window rule in both validators):

- `gateway.sh test test/sync_protocol_fixtures_test.dart` → `00:00 +95: All tests passed!`
- `gateway.sh swift-test` → `Executed 376 tests, with 0 failures (0 unexpected)` — both validators give the same answer
  on all four fixtures.
- `gateway.sh test test/rest_is_count_up_contract_test.dart test/watch_capture_contract_conformance_test.dart` →
  `00:00 +27: All tests passed!`
- `gateway.sh lint` → `196 issues found` (baseline 196; the touched files add none).

**`prove-red cd1830f test test/sync_protocol_fixtures_test.dart` → GREEN AT.** This proof is not applicable to a
data-driven contract guard: `prove-red` reverts the whole working tree to the base commit except the named test files, so
it removes the fixtures and manifest rows the change adds — with nothing new to walk, the unchanged generic walker
passes. The valid red proof is the manual run pasted above (fixtures + manifest present, schemas unchanged), which is
exactly the red state the brief prescribes for Phase 1A.

## Phase 2 — red first, then green

Base commit for every proof: `dc69aa3`.

**`prove-red dc69aa3 test test/watch_session_merge_test.dart` → RED AT** (exit 1), 12 assertion failures, 6 Mock + 6 Hive,
each for the reason its test guards:

```
00:00 +14 -1: Mock the wrist's rests (D-210) S-320 a wrist rest lands beside the set in the phone's own effort [E]
  Expected: an object with length of <1>
    Actual: []
  S-320 one rest event, one row
00:00 +14 -3: Mock the wrist's rests (D-210) S-325 the phone's own rest at that spot wins [E]
  Expected: contains 'rest-a1'
    Actual: ['sx-1']
00:00 +14 -5: Mock the wrist's rests (D-210) S-337 a rest whose after-entry is gone is dropped and consumed [E]
  Expected: not null
    Actual: <null>
00:00 +14 -6: Mock the wrist's rests (D-210) S-328 an unresolvable rest is consumed in the merge too [E]
  Expected: not null
    Actual: <null>
… the same six failures again under `Hive …` (`+28 -12` in all)
00:01 +28 -12: Some tests failed.
```

**`prove-red dc69aa3 test test/watch_session_rest_timer_append_test.dart` → RED AT** (exit 1); `S-110` passes at the base,
so the proof is the new guard alone:

```
00:00 +1 -1: S-320 a wrist rest lands beside the phone's running rest [E]
  Expected: [0, 1]
    Actual: [0]
     Which: at location [1] is [0] which shorter than expected
  S-320 the running rest keeps its spot, and the wrist's rest lands after the set the wrist logged
```

**`prove-red dc69aa3 test test/watch_session_import_test.dart` → RED AT, but not usable as a proof:** the group cannot run
at the base — `test/watch_session_import_test.dart:2480:33: Error: Member not found: 'kindRest'` (the constant is new
code), and the gateway says a load error means the test could not run there. So the import group was proved by two
mutations, each restored to the exact original line and re-run green:

| Mutation | Original line | Result with the mutation applied | After restore |
|---|---|---|---|
| `lib/core/services/watch_session_importer.dart:521` — the rest write in a new import | `    await _applyRests(unapplied);` | `the wrist’s rests` `+3 -3`: `S-320`, `S-324`, `S-327` fail with `Expected: an object with length of <1> Actual: []` (`S-320 one rest event, one row`) | `+6: All tests passed!` |
| `lib/data/models/models.dart:2635` — `kindRest` in `watchKinds` | `    kindRest,` | `the wrist’s rests` `+0 -6`: `S-323` throws `Invalid argument (kind): D-132: not a kind the inbox stages for origin watch: "rest"`, the other five find no row | `+6: All tests passed!` |

**Green.** `.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart
test/watch_session_merge_test.dart test/watch_session_rest_timer_append_test.dart test/db_seed_test.dart` →
`00:01 +105: All tests passed!` (the phase's Done Criteria command). Full suite
`.github/copilot/scripts/macos/gateway.sh test` → `01:48 +4204 ~1: All tests passed!` (baseline +4181 ~1).
`.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found` (baseline 196, 0 errors; `grep` of the lint log finds
no issue in `watch_session_importer.dart`, `watch_session_inbox.dart`, `models.dart` or the three test files).
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → no matches. The doc-contract
suites the two doc corrections touch are green too: `.github/copilot/scripts/macos/gateway.sh test
test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart
test/watch_capture_contract_conformance_test.dart` → `+36: All tests passed!`.

**Parity.** The merge group's six test bodies run twice, once under `group('Mock')` and once under `group('Hive')`
(Hive seeded in `setUp`, `Hive.deleteFromDisk()` in `tearDown`), and assert the written row's `id`, `entryIndex`,
`restStartMs` and `restEndMs` on both — the repository half of the parity row. No repository, model or SQL change was
needed (V-4): `getEntryRests`/`createEntryRest` already existed in both implementations, and the importer's
`entryIndex` guard is what keeps Mock's append-only `createEntryRest` observably equal to Hive's put-by-id.

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

## Fix round 1

Review findings F-1, F-2, F-3 (table only), F-4 and Assumption Log A-10. Base commit `dc69aa3`; Phase 2 stays
uncommitted on the tree. No production behaviour changed: the two tests are pins, so each is proved by a mutation of the
guard it pins, restored to the exact original line and re-run green.

### F-1 — the same-instant rest pin

`test/watch_session_import_test.dart`, group `the wrist’s rests (D-210)`:
`S-328 a rest naming one of two same-instant sets is dropped and consumed`. Two wrist sets share one logged instant and
the user has added a row of their own to the effort, so `_EffortRows.indexOf` cannot tell the two positions apart; the
staged rest is dropped and its row marked applied, and a second pass writes nothing either.

Mutation — `lib/core/services/watch_session_importer.dart`, `_EffortRows.indexOf` body

```
  int? indexOf(_Entry entry) {
    if (_stagedPerStamp[entry.loggedAtMs] != 1) return null;
    final indices = _indicesByStamp[entry.loggedAtMs];
    return indices != null && indices.length == 1 ? indices.single : null;
  }
```

replaced with `return _indicesByStamp[entry.loggedAtMs]?.first;` →

`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart --plain-name "S-328 a rest naming one of two same-instant sets is dropped and consumed"`
→ `+0 -1`, `Expected: empty Actual: [Instance of 'EntryRest']` (`S-328 the two same-instant sets leave no spot to name`).
After restore: `+55: All tests passed!` for the file.

### F-2 — the rest required-fields negative

`test/watch_session_import_test.dart`, group `what the inbox stages (D-132)`,
`A-3 a snapshot entry missing its kind’s fields is not staged`: a `rest` snapshot entry without `afterEntryId` is not
staged; the same row with it is staged.

Mutation — `lib/state/watch/watch_session_inbox.dart`, `'afterEntryId'` removed from `_requiredFields[kindRest]` →

`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart --plain-name "A-3 a snapshot entry missing its kind’s fields is not staged"`
→ `+0 -1`, `Expected: ['e-snap-1', 'rest-s-snap-whole'] Actual: ['e-snap-1', 'rest-s-snap-partial', 'rest-s-snap-whole']`.
After restore: `+55: All tests passed!` for the file.

### Verify

`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart test/watch_session_merge_test.dart
test/watch_session_rest_timer_append_test.dart test/docs_indexing_contract_test.dart` → `00:01 +106: All tests passed!`
`.github/copilot/scripts/macos/gateway.sh test` (full suite) → `01:49 +4205 ~1: All tests passed!` (baseline `+4204 ~1`;
the +1 is the new S-328 pin).
`.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found` (baseline 196, 0 errors; files touched this round add
none). `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → no matches.
