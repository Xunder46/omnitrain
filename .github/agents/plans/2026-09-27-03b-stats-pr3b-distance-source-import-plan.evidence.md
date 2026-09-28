# PR 3b — Evidence (companion to `2026-09-27-03b-stats-pr3b-distance-source-import-plan.md`)

This file holds the baselines, the code facts the plan rests on, and the tables the executor fills
(`.github/agents/pr_scope_budget.md` §2).

## 1. Planning baselines (the 3a2 tree, as it will land on `develop`)

| Check | Observed |
|---|---|
| `flutter test` | `01:27 +3097 ~1: All tests passed!`, exit 0. Log: scratchpad `pr3a2_fixes_full.log`. |
| `flutter analyze` | `241 issues found.`: 0 errors, 11 warnings, 230 infos. Log: scratchpad `pr3a2_fixes_analyze.log`. |
| `cd watch/watchos && swift test` | `Executed 242 tests, with 0 failures`, exit 0. Re-run fresh on 2026-09-27; log: scratchpad `pr3b_base_swift_test_rerun.log`. |

**Analyzer ceiling per touched file:** every file 3b touches has 0 issues today, and must still have 0:
- `lib/core/sync_protocol/message_validator.dart`
- `lib/core/services/watch_session_importer.dart`
- `lib/core/utils/logged_entry_rows.dart`
- `lib/state/workout/timer_manager.dart`

## 2. Code facts (file:line on the 3a2 tree)

| # | Fact | Evidence |
|---|---|---|
| H1 | Snapshot entries reuse the `entry` definition, so one schema property covers `observations_up` and `session_snapshot`. `additionalProperties: false` refuses an undefined field with `unexpected_field`, and the message quotes the field name. | `watch/sync_protocol/schemas/messages/session_snapshot.schema.json:34`; `lib/core/sync_protocol/message_validator.dart:718-729` |
| H2 | The kind-scoped capture rules are tables: `_captureFieldKinds` in Dart and `captureFieldKinds` in Swift. Both loops produce the message `<field> is carried only by <kinds> entries; <entryId> is a <kind> entry`. | `message_validator.dart:131-140, 400-424`; `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:77-86, 290-315` |
| H3 | Each stack writes its pair rules (for example, heart rate) as its own function, called from the capture loop. The wording is identical on both stacks. | `message_validator.dart:429-452`; `SyncProtocolValidator.swift:320-349` |
| H4 | The manifest registers each fixture with `path`, `type`, `scenario`, and, for invalid ones, `expectedCode` and `expectedReasonContains`. An enum refusal is `invalid_enum_value` and its reason quotes the bad value. | `watch/sync_protocol/fixtures/manifest.json:21-24, 61-72, 103-107` |
| H5 | Both stacks walk the manifest, so a registered fixture is tested with no test edit. The Swift walk runs inside the 242-test count. | `test/sync_protocol_fixtures_test.dart`; Swift `SyncProtocolFixturesTests` |
| H6 | Watch-started sessions never run GPS: modality is nil, so the GPS policy says no. The watch's logged `distanceMeters` is the dialled value unless it is measuring. So every distance the phone imports today was dialled by hand. | `WatchSensorRecording.swift:144`; `WatchLoggingState.swift:380-389, 617-627`; `lib/watch/logging/watch_logging_state.dart:658-671` |
| H7 | The import builds a timed entry's rows with `LoggedEntryRows.timedObservations`, which today sets no source. `_Entry` parses `distanceMeters` but has no source field. | `lib/core/services/watch_session_importer.dart:697-704, 1243, 1349`; `lib/core/utils/logged_entry_rows.dart:79-96` |
| H8 | When an entry moves, the import re-keys its rows by copying the whole stored row (`toMap`) under the new id, so `value_source` survives a move. Corrections change only reps, load and the timed window, never distance. | `watch_session_importer.dart:500-530, 820-860` |
| H9 | The import reads ids with its own prefix parser. The shared `EntryRows.parseId` returns both the number and the metric key. | `watch_session_importer.dart:603-624`; `lib/core/utils/entry_rows.dart:90-101` |
| H10 | 3a2's O-4: `TimerManager.addTimedEntry` names an instance `timed-<effortId>-<count>-<ms>`, so an add after a delete, in the same millisecond, reuses a held id. Imported instances use a different name, `timed-<sessionId>-<entryId>`. | `lib/state/workout/timer_manager.dart` (`addTimedEntry`); `watch_session_importer.dart:79-80` |
| H11 | A correction's schema has no distance field, so the wire cannot carry a phone-side distance change (owner Q2, D-333). | `watch/sync_protocol/schemas/messages/structure_change.schema.json:30-42` |
| H12 | Harnesses. Mock/Hive: `RepositoryHarness`, `harnessFactories` and seeders. Import: `seedCaptureCatalog` and `CaptureTransport`; the inbox and event builders in the import tests; `observationsUp` and `loadProtocolValidator`. | `test/helpers/repository_harness.dart:51-267`; `test/helpers/watch_capture_import_harness.dart:73, 99`; `test/watch_session_import_test.dart:59-152`; `test/helpers/sync_protocol_harness.dart` |

## 3. Executor records (append below)

### Step 0 (2026-09-27)

**Step 0a — preconditions.** First attempt failed: the checkout sat on
`feature/stats-pr3a2-entry-identity` and 3a2 was not on `develop` (O-1). The owner merged 3a2 into
`develop`; second attempt passed all four checks.

| Check | Observed |
|---|---|
| `git branch --show-current` | `develop` |
| `git cat-file -e develop:lib/core/utils/entry_rows.dart && git cat-file -e develop:test/entry_identity_test.dart && echo ok` | `ok` |
| `git log develop -5 --format=%s` | `Add entry rows tests and repository harness for entry identity scenarios` / `Add tests for stats distance estimation and pace calculation` / `feat: implement PR scope budget guidelines across multiple agent documents` / `Add tests for session end handling and phone preferences synchronization` / `fix(stats): address PR 1 code review — calendar refresh, test pins, docs` |
| `git status --short \| grep -v "^.. .github/agents/plans/"` | no output (only the 3b plan, its evidence file and the series index are staged) |

**Step 0b — branch.** Skipped by owner direction: work continues directly on `develop`
("continue working in this develop branch"). No branch was created, and none will be merged, pushed
or deleted by the executor. The plan's remaining steps are unaffected — every later step that reads
"`git diff --name-only develop`" now compares against the working tree's own base, so the diff is
taken against `HEAD` instead.

**Step 0c — baselines.**

| Check | Observed |
|---|---|
| `flutter test` | `+3097 ~1: All tests passed!`, exit 0 (`/tmp/pr3b_base.log`) |
| `flutter analyze` | `241 issues found.`, 0 errors (`/tmp/pr3b_base_an.log`) |
| `cd watch/watchos && swift test` | `Executed 242 tests, with 0 failures (0 unexpected) in 0.837 (0.851) seconds`, exit 0 (`/tmp/pr3b_base_swift.log`) |

The `flutter test` baseline line quoted verbatim: `01:23 +3097 ~1: All tests passed!`, exit 0.

### Red → green (one row per new test)

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `sync_protocol_fixtures_test.dart` › fixtures · `valid/observations_up_distance_source.json` | S-871 | `Expected: empty` / `Actual: [unexpected_field at $.payload.events[0].distanceSource: field "distanceSource" is not defined by the schema, …]` (one per entry) | pass (`/tmp/pr3b_green1.log`) |
| `sync_protocol_fixtures_test.dart` › `invalid/observations_up_distance_source_on_round.json` | S-872 | `Expected: contains 'semantic_violation'` / `Actual: ['unexpected_field']` / `Which: does not contain 'semantic_violation'` | pass |
| `sync_protocol_fixtures_test.dart` › `invalid/observations_up_distance_source_without_distance.json` | S-873 | `Expected: contains 'semantic_violation'` / `Actual: ['unexpected_field']` | pass |
| `sync_protocol_fixtures_test.dart` › `invalid/observations_up_distance_source_unknown.json` | S-874 | `Expected: contains 'invalid_enum_value'` / `Actual: ['unexpected_field']` | pass |
| `sync_protocol_fixtures_test.dart` › `invalid/structure_change_correction_distance.json` | S-875 | green before and after (`unexpected_field`, `+49` at the red run) | pass |
| `distance_source_import_test.dart` › S-876 | S-876 | `Actual: [(5000.0, null), (3000.0, null), (4200.0, null)]` against `gps`, `entered`, `estimated` | pass |
| `distance_source_import_test.dart` › S-877 | S-877 | `Expected: [(2500.0, entered), (0.0, null)]` / `Actual: [(2500.0, null), (0.0, null)]` | pass |
| `distance_source_import_test.dart` › S-878 (Mock and Hive) | S-878 | `Expected: [(1000.0, entered), (5200.0, entered)]` / `Actual: [(1000.0, null), (5200.0, entered)]` — the late entry's source only; the moved row already kept `5200.0 entered` (H8) | pass |
| `distance_source_import_test.dart` › S-880 (the pure helper) | S-880 | `Error: Member not found: 'TimerManager.uniqueTimedInstanceId'` (compile) | pass |
| `distance_source_import_test.dart` › S-880 (the writer, review F-3) | S-880 | new test; red under M6 only, since the helper was already in place | pass — `+7: All tests passed!` |
| `row_invariants_guard_test.dart` › S-883 step 2a (review F-4) | S-883 | new step; red under M5 only → `holds an unsourced distance of 1500.0 m (I-c)` | pass — `+28: All tests passed!` |

The red run is `/tmp/pr3b_red1.log`: `+68 -4: Some tests failed.` — four failures, exactly
S-871–S-874; S-875 passed at `+49`.

**Phase 1 done criteria.** `flutter test test/sync_protocol_fixtures_test.dart
test/watch_session_engine_test.dart test/live_mirroring_test.dart
test/watch_reconciliation_cross_stack_test.dart` → `+145: All tests passed!`, exit 0
(`/tmp/pr3b_p1.log`). `flutter analyze` → `241 issues found.`, and
`grep -c message_validator.dart` over the log → `0` issues in that file (`/tmp/pr3b_p1_an.log`).
`swift test` → `Executed 242 tests, with 0 failures (0 unexpected)` (`/tmp/pr3b_green1_swift.log`).
Full `flutter test` → `All tests passed!`, exit 0 (`/tmp/pr3b_p1_full.log`).

**Phase 2.** Red run `/tmp/pr3b_red2.log` — the file did not compile,
`Member not found: 'TimerManager.uniqueTimedInstanceId'` (S-880). The compile failure masks the
runtime failures, so S-880's block was copied aside to a scratch file and the rest re-run
(`/tmp/pr3b_red2b.log`, `+0 -4: Some tests failed.`):

| Test | Red value |
|---|---|
| S-876 | `Expected: [(5000.0, gps), (3000.0, entered), (4200.0, estimated)]` / `Actual: [(5000.0, null), (3000.0, null), (4200.0, null)]` |
| S-877 | `Expected: [(2500.0, entered), (0.0, null)]` / `Actual: [(2500.0, null), (0.0, null)]` |
| S-878 (Mock and Hive) | `Expected: [(1000.0, entered), (5200.0, entered)]` / `Actual: [(1000.0, null), (5200.0, entered)]` |
| S-880 | compile failure, as above |

Add S-878's pre-fix detail: the phone-written row already survived the move (`5200.0, entered`),
which is H8 holding; the only red is the *late* entry's own source, which Step 2.5's
absent-means-`entered` rule fills. So S-878 was red before the fix, not green as the plan predicted
(it is green *after*, and mutation M4 proves it bites). See the Assumption Log.

Green run `/tmp/pr3b_green2.log`: `+5: All tests passed!` (S-876, S-877, S-880, S-878 on Mock, S-878
on Hive).

**Phase 2 done criteria.** `flutter test test/distance_source_import_test.dart
test/watch_session_import_test.dart test/watch_capture_contract_test.dart
test/watch_capture_repository_parity_test.dart test/watch_session_edit_restore_summaries_test.dart
test/entry_identity_test.dart` → `+135: All tests passed!`, exit 0 (`/tmp/pr3b_p2.log`).
`grep -c "EntryRows.parseId" lib/core/services/watch_session_importer.dart` → `1`.
`grep -n "indexOf('-')" lib/core/services/watch_session_importer.dart` → no output (the parser is
gone from `_observationsByIndex`). `flutter analyze` → `241 issues found.`, and `grep -c` over the
log for the four touched files → `0` (`/tmp/pr3b_p2_an.log`).

The one analyzer issue this phase introduced was mine and in the new test file (an unused
`message_validator.dart` import, `241 → 242`); removed, back to `241`.
Full `flutter test` → `01:27 +3107 ~1: All tests passed!`, exit 0 (`/tmp/pr3b_p2_full.log`).
3107 = the 3097 baseline plus Phase 1's 5 fixtures and Phase 2's 5 tests.

### Review fix round (2026-09-27)

Findings from `2026-09-27-03b-stats-pr3b-distance-source-import-plan.review.md`; the review is not
re-run, so this is the record.

| Finding | Fix | Proof |
|---|---|---|
| F-1 (CRITICAL) | `docs/distance_source.md`: the false absolute "Only the Summary's write changes a source" is deleted; the invariant now claims only what S-802/S-805/S-821 verify. The import's own write was already pointed at by the Scope and by the rationale paragraph, so no second claim was added. | `grep -n "Only the Summary" .github/agents/docs/distance_source.md` → no output |
| F-2 | `docs/distance_source.md`: the write paragraph names both phone paths and no longer reads as exclusive. | — the paragraph states what `setEntryDistance` / `confirmEntryDistance` / `updateEntryValue` each do |
| F-3 | `TimerManager` takes an optional `DateTime Function()? clock` (`clock ?? DateTime.now`, the pattern `WatchSessionInbox` and `LiveSessionMirrorState` use); `addTimedEntry` reads it. A new writer test drives add → delete → add on a clock that stands still, so the millisecond repeats and the id must not. | M6 |
| F-4 | `updateEntryValue` derives a distance row's source from the value it writes: `entered` for a positive value that has none, none for a zero, unchanged otherwise. The guard's S-883 gained steps 2a and 2b on that path. | M5 |
| F-6 | `docs/watch_session_capture.md` freshness marker → `2026-09-27`. | — |
| F-5 | Deferred to that page's next edit, as the review directs. | — |

**F-4 was a real hole, not a false alarm.** With the guard step in place and `updateEntryValue`
restored to preserving the source (M5), S-883 failed on both stores at `2a` — a positive distance
written through the live screen's own path with no source. The producer is `_persistEntryValues`'s
`case 'timed':` branch in `workout_session_screen.dart`: it calls `updateEntryValue(effortId,
entryIndex, 'distance', currentEntry['distance'] as double? ?? 0.0)` on every timed-entry persist,
and the screen holds no distance field to put anything but the default 0.0 into `currentEntry`
today — so the write this round reaches is real and common, not the `addEntry`
`previousValues?['distance']` carry-forward (a second, still-unreached path the screen never feeds;
see S-1 / Open Items O-3). The fix removes the collision from either direction: the row is given a
source at the write, and the guard now fails if that stops happening.

**Fix-round verification.** `flutter test` → `01:30 +3119 ~1: All tests passed!`, exit 0
(`/tmp/pr3b_fix_full.log`) — 3117 → 3119, the two new tests. `flutter analyze` → `241 issues
found.`, 0 errors, and `grep -c` over the log for `timer_manager`, `session_core_entry` and the two
edited test files → `0` (`/tmp/pr3b_fix_an.log`). Targeted suites
(`distance_source_import_test`, `distance_source_test`, `row_invariants_guard_test`,
`session_summary_distance_test`) → `+51: All tests passed!`. The seven-command stale-claim sweep
re-run: all as expected.

### Guard outcome (Phase 3 Step 3.3)

- **As Phase 3 landed it, F-6 and F-7 were not applicable — the guard passed on unfixed code.**
  `/tmp/pr3b_guard.log`: `00:01 +10: All tests passed!` — all ten (five scenarios × Mock and Hive),
  with `expectRowInvariants` called after every step of every scenario. I-a, I-b and I-c held
  throughout *that* run, so the searches F-6 and F-7 called for found no path. This does not still
  hold: the review round extended S-883 with steps 2a/2b, and that extension caught a real I-c
  violation — M5, above, and F-4's own paragraph — that the original ten runs never exercised.
- **The guard bites, so passing means something.** A temporary copy-aside mutation of
  `SessionCore.deleteEntry` (`doomed.clear()` in place of the delete loop, `/tmp/sce.orig`) made
  S-884 and S-887 fail on both stores with a stray row showing up as an extra entry —
  `Expected: [9, 0, 10]` / `Actual: [10, 9, 0, 10]` (Mock and Hive) and `Expected: [5, 10, 6]` /
  `Actual: [5, 5, 10, 6]` (Mock and Hive), `/tmp/pr3b_guard_mut.log`. Restored → `+10: All tests
  passed!`. `lib/state/workout/session_core_entry.dart` is unmodified in the diff.
- No fix was made, so no Phase 2 lib file was added by this step.

### Mutations (copy-aside method; never `git stash`)

| Id | File and change | Test that failed | Failing value (quoted) | Restored and green |
|---|---|---|---|---|
| M1 | `watch_session_importer.dart` Step 2.5: `distanceSource` always `EffortObservation.sourceEntered` for a distance > 0 | `test/distance_source_import_test.dart` S-876 | `Expected: [(5000.0, gps), (3000.0, entered), (4200.0, estimated)]` / `Actual: [(5000.0, entered), (3000.0, entered), (4200.0, entered)]`; `at location [0] is (5000.0, entered) instead of (5000.0, gps)` | yes — `+5: All tests passed!` |
| M2 | `message_validator.dart`: deleted `'distanceSource': ['timed'],` | `test/sync_protocol_fixtures_test.dart` › `invalid/observations_up_distance_source_on_round.json` | `Expected: non-empty` / `Actual: []` (the round fixture was accepted) | yes — `+72: All tests passed!` |
| M3 | `SyncProtocolValidator.swift`: deleted `("distanceSource", ["timed"]),` | `swift test` › `SyncProtocolFixturesTests` | `XCTAssertFalse failed - invalid/observations_up_distance_source_on_round.json must not conform`; `expected code semantic_violation, got []`; `no rejection explains distanceSource is carried only by timed entries`; `must not reach storage` | yes — `Executed 242 tests, with 0 failures` |
| M4 | `watch_session_importer.dart` move/re-key path: added `'value_source': null` to the copied map | `test/distance_source_import_test.dart` S-878 (Mock and Hive) | `Expected: [(1000.0, entered), (5200.0, entered)]` / `Actual: [(1000.0, entered), (5200.0, null)]` | yes — `+5: All tests passed!` |
| M5 (review F-4) | `session_core_entry.dart`: `valueSource: oldObs.valueSource` in place of `_sourceAfterWrite(…)` | `test/row_invariants_guard_test.dart` S-883 (Mock and Hive) | `Expected: not null` / `Actual: <null>`; `2a updateEntryValue(run, 0, distance, 1500): effort … (timed) holds an unsourced distance of 1500.0 m (I-c)` | yes — `+28: All tests passed!` |
| M6 (review F-3) | `timer_manager.dart`: `id: 'timed-$effortId-$entryIndex-$now'` in place of the `uniqueTimedInstanceId` call | `test/distance_source_import_test.dart` S-880 (the writer test) | Mock: `Actual: Set:['timed-e-t-1-1000']` / `Which: has length of <1>` and `S-880 no two entries hold the same id, got [timed-e-t-1-1000, timed-e-t-1-1000]`; Hive: `Actual: ['timed-e-t-1-1000']` | yes — `+7: All tests passed!` |

All four mutations were made with `cp <file> /tmp/<name>.orig` first and restored with
`cp /tmp/<name>.orig <file>`; `git status` afterwards shows no change in `session_core_entry.dart`,
`message_validator.dart` or `SyncProtocolValidator.swift` beyond the intended edits.

### Doc-claim table (every added or changed behaviour sentence)

| Doc:line | Sentence (short) | Test pointer (file, S-id) | Guard test for any absolute word |
|---|---|---|---|
| `watch/sync_protocol/PROTOCOL.md:246` | `distanceSource` is carried by `timed`, with `distanceMeters` | `test/sync_protocol_fixtures_test.dart` (S-871–S-874) | n/a — the fixture set pins the kind and the pairing |
| `watch/sync_protocol/PROTOCOL.md:257` | a `correct_entry` correction carries no distance | `test/sync_protocol_fixtures_test.dart` (S-875) | n/a — the schema refuses the field |
| `docs/watch_session_capture.md:8` (Scope) | the scope covers the source the import stores for a distance | — (scope, not a behaviour claim) | n/a |
| `docs/watch_session_capture.md:159` | the import stores the source the wrist sent, or `entered` when it sent none; no distance, no source | `test/distance_source_import_test.dart` (S-876, S-877) | n/a — no absolute word |
| `docs/watch_session_capture.md:162` | a later sync leaves a phone-written distance's value and source alone | `test/distance_source_import_test.dart` (S-878) | n/a — no absolute word |
| `docs/distance_source.md:11` (Scope) | `WatchSessionImporter` is a writer of a distance's source | — (scope, not a behaviour claim) | n/a |
| `docs/distance_source.md:80` | a missing source reads as `entered`: the import stores the source the watch sent, or `entered` when it sent none | `test/distance_source_import_test.dart` (S-876, S-877) | n/a — no absolute word |
| `docs/distance_source.md:82` | a watch that sends no source dialled the distance by hand | `test/distance_source_import_test.dart` (S-877) | n/a |
| `docs/data_models.md:515` | the watch import builds its own ids (no longer claims it reads them too) | `test/row_invariants_guard_test.dart` (S-887) | n/a |
| `docs/data_models.md:543` | the import reads ids with `EntryRows.parseId` | `test/row_invariants_guard_test.dart` (S-887); `grep -c "EntryRows.parseId"` → 1 | n/a |
| `docs/distance_source.md:50` (F-2) | the phone's distance writes: `setEntryDistance`/`confirmEntryDistance` record `entered` for a positive value and none for a zero; `updateEntryValue` keeps an existing source and records `entered` for a positive value that has none | `test/distance_source_test.dart` (`S-804`, `S-805`), `test/session_summary_distance_test.dart` (`S-821`) and `test/row_invariants_guard_test.dart` (S-883 steps 2a/2b) | the probe note is scoped to the phone, not absolute |
| `docs/distance_source.md:136` (F-1) | a distance's source survives a restart and an Edit Session snapshot and restore | `test/distance_source_test.dart` (`S-802`, `S-805`), `test/session_summary_distance_test.dart` (`S-821`) | the absolute was **deleted**; no guard needed |

The two `docs/data_models.md` sentences and the `distance_source.md` rationale paragraph are edits to
existing claims, so their pointers are on the sentence that now states the behaviour.

### Stale-claim sweep results

| Command | Expected | Observed |
|---|---|---|
| `grep -rn "the watch import write" .github/agents/docs/` | no output | no output |
| `grep -rn "own prefix reader" .github/agents/docs/` | no output | no output |
| `grep -rn "build and read their own ids" .github/agents/docs/` | no output | no output |
| `grep -rln "distanceSource" .github/agents/docs/` | no output | no output (case-sensitive: the docs' `DistanceSource` class references do not match the wire name) |
| `grep -rn -i "back to the watch" .github/agents/docs/` | no output | no output |
| `grep -rn "timed-<" .github/agents/docs/` | no line claiming instance ids can repeat | no output at all |
| `git diff --name-only develop \| grep -E "docs/(README\|widget_catalog\|design_system\|navigation_and_screens)\.md"` | no output | no output (taken against `HEAD`, since work is on `develop`) |

**Phase 3 done criteria.** `flutter test test/row_invariants_guard_test.dart
test/docs_indexing_contract_test.dart` → `+19: All tests passed!`, exit 0 (`/tmp/pr3b_p3.log`).
Full `flutter test` → `01:42 +3117 ~1: All tests passed!`, exit 0 (`/tmp/pr3b_p3_full.log`).
`flutter analyze` → `241 issues found.`, 0 errors (`/tmp/pr3b_p3_an.log`). `swift test` →
`Executed 242 tests, with 0 failures (0 unexpected) in 0.856 (0.871) seconds`, exit 0
(`/tmp/pr3b_p3_swift.log`). The doc checklist (items 1–9) was applied to all three `docs/` files.

**Test count.** 3097 at baseline → 3117 after Phase 3: the 5 new conformance fixtures, the 5 Phase 2
tests (S-878 counted per store) and the 10 guard runs (5 scenarios × Mock and Hive). The first
review fix round added 2 (F-3's writer test, F-4's guard steps counted per store): 3117 → 3119. The
second review round (this file's later sections) added assertions to existing tests — S-884's
weighted-set check — and no new `test(...)` blocks, so the count is unchanged: `flutter test` →
`01:31 +3119 ~1: All tests passed!`.

### Second review round (2026-09-29)

Findings from the plan's `### Review — Claude code-reviewer, 2026-09-28` checklist. One round; no
re-review.

| Finding | Fix | Proof |
|---|---|---|
| C-1 | `docs/state_management/workout_state.md:103`: `updateEntryValue`'s row no longer claims `valueSource` is preserved; it states the distance-source derivation and points at `S-804` (a) and S-883 2a/2b. | `grep -n "except.*valueSource\|preserves all existing fields including .*valueSource" docs/state_management/workout_state.md` → no output |
| C-2 | `docs/distance_source.md:49-55`: the behaviour prose for `setEntryDistance`/`confirmEntryDistance`/`updateEntryValue` now carries `S-805`, `S-804` (a) and S-883 2a/2b; "Both keep" → "All three keep"; the live-screen paragraph names `_persistEntryValues` as the real caller and states what it writes today, resolving the contradiction with the paragraph that follows it. | `grep -n "^Both keep" docs/distance_source.md` → no output |
| C-3 | `docs/data_models.md`: the false "the routine-template defaults [build their own ids]" claim is replaced with the real bypass — `SessionSummaryBuilder.buildTemplateDraftExercises` drafts a template's targets from `_observations[...].first` / `createdAtMs` order, not the id rule — restoring the warning the earlier rewrite dropped. | traced `RoutineSessionService` → `SessionCore.populateSessionFromManifest` (compliant, standard writers) and `session_summary_builder.dart`'s `buildTemplateDraftExercises` (the real bypass) by reading both files |
| W-1 | `test/row_invariants_guard_test.dart`'s `setUp` now calls `repo.setExerciseCapabilities(id, capabilities)` for all four exercises. Root cause: `seedExercise` (the `repository_harness.dart` copy this file uses, since it hides the `watch_capture_import_harness.dart` one) sets `Exercise.capabilities` on the object passed to `createExercise`, but both repositories' `getExerciseById` reads capabilities from the separate `setExerciseCapabilities` store — so bench hydrated with none and `hasLoad` read false. S-884 also gained a `weight` write/assert step so a loaded set's own row is exercised. | Mutation: reverted the bench `setExerciseCapabilities` call → `test/row_invariants_guard_test.dart` S-884 failed on both stores, `Expected: <0>` / `Actual: <3>`, "S-884 a loaded exercise writes no extra-weight row at all". Restored → `+10: All tests passed!` |
| W-2 | This file: reworded "Guard outcome" to distinguish the original ten-run guard's clean pass from the review round's real catch (M5); corrected the F-4 producer to `_persistEntryValues` (not the dormant `addEntry` carry-forward); refreshed the doc-claim table's line numbers; reconciled the test-count note above. | re-grepped every doc-claim table line after all edits landed |
| W-3 | `docs/state_management/workout_state.md:198`: `addTimedEntry`'s row now states the id-uniqueness rule (D-338) and points at `S-880`. | `grep -n "addTimedEntry" docs/state_management/workout_state.md` shows the new sentence |
| S-2 | `watch/sync_protocol/PROTOCOL.md`'s `## Version history` table gained the row for the `distanceSource` amendment (2026-09-27), which the table had never listed. | `grep -c "2026-09-27" watch/sync_protocol/PROTOCOL.md` → 1 |
| Minor: misleading comment | `test/distance_source_import_test.dart` S-880: "the fourth call" → "the third call" (the test has three `addTimedEntry`/`deleteTimedEntry` calls total, and the collision is on the third). | read the test body and counted the calls |
| Minor: guard skips numberless rows silently | `test/helpers/row_invariants.dart`'s `_checkSetGroups` now asserts no set row lacks an entry number, with a comment citing D-339, instead of silently `continue`-ing past one. | `flutter test test/row_invariants_guard_test.dart` still green after the change (no such row exists in any scenario today) |
| S-1 (deferred, not fixed) | Added as Open Item O-3: `addEntry`'s `previousValues?['distance']` carry-forward would store a distance with no source; unreachable today (no screen populates `previousValues['distance']` for a timed/drill entry); deferred to PR 3a3 per the owner. | — |

**Second-round verification.** `flutter test` → `01:31 +3119 ~1: All tests passed!`, exit 0.
`flutter analyze` → `241 issues found.`, 0 errors. Targeted suites
(`row_invariants_guard_test`, `distance_source_import_test`, `distance_source_test`) →
`+35: All tests passed!`. No `lib/` production file changed this round (W-1 and the minor guard fix
are test-only); `swift test` unaffected and not re-run.

