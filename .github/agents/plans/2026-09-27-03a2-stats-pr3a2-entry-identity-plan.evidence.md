# PR 3a2 — Evidence (companion to `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`)

This file holds the baselines, the code facts the plan's decisions rest on, and the executors' red→green
records (`.github/agents/pr_scope_budget.md` §2). The plan only points here.

## 1. Planning baselines

The tree was PR 3a's final state. That content is now commit 4bb4afb on `develop`. The owner may re-title
the commit, but the tree is the same.

| Check | Observed |
|---|---|
| `flutter test` | `01:15 +3052 ~1: All tests passed!`, exit 0, 0 failures. The one skip is pre-existing (`test/profile_navigation_test.dart:39`). Log: scratchpad `pr3a_final_full.log`. |
| `flutter analyze` | `242 issues found.`: 0 errors, 11 warnings, 231 infos. Log: scratchpad `pr3a_final_analyze.log`. |
| `swift test` | 242 tests, 0 failures (2026-09-26). 3a2 touches no Swift. |

**Analyzer ceiling per touched file ("none new"):**
- `lib/features/session/session_summary_screen.dart`: 10;
- `lib/state/workout/session_core.dart`: 1;
- every other file this plan touches: 0.

## 2. Code facts (file:line at 4bb4afb)

| # | Fact | Evidence |
|---|---|---|
| G1 | Hive returns box values in key order, compared with `String.compareTo`, so `obs-E-10-reps` comes before `obs-E-2-reps`. Mock returns insertion order. An effort may hold 12 entries. | hive 2.2.3 `lib/src/box/keystore.dart:46`, `lib/src/box/default_key_comparator.dart:2-16`; `lib/data/repositories/hive_workout_repository.dart:1333-1350`; `lib/data/repositories/mock_workout_repository.dart:646-659`; `lib/core/constants/workout_constants.dart:4` |
| G2 | `updateEntryValue` and `markSetSkipped` pick the n-th row of a metric in the raw in-memory list. That list comes from the store when a session is reopened. The display orders weighted sets by the number in their ids. So in a reopened Hive session with 11 or more sets, display entry k is not raw row k. | `lib/state/workout/session_core_entry.dart:198-285, 446-470`; `lib/core/utils/observation_grouper.dart:44-79` |
| G3 | The grouper's id pattern `obs-.+-(\d+)-[^-]+$` can't read `…-extra-weight` or `…-round-duration`. Every bodyweight set effort therefore falls back to sequential grouping in raw order. The entry-list builder also overlays extra weight by raw position. | `observation_grouper.dart:47-51, 82-118`; `lib/state/workout/session_summary_builder.dart:388-399` |
| G4 | `deleteEntry` deletes set rows whose id starts with `obs-<effortId>-<displayIndex>-`, and it is called with the display position. Set ids are numbered max+1 and never renumbered. So after an earlier delete, the prefix can name a different surviving set. No existing test deletes two sets from one exercise. This is from code reading and has not been reproduced. | `session_core_entry.dart:491-557`; `lib/features/session/workout_session_screen.dart:1190, 1222`; `test/state_test.dart:1826, 2240` |
| G5 | Deleting a timed entry renumbers the remaining instances, but deletes their companion rows by the current index's id prefix. Timed rows are numbered by the instance count. So an add after a delete reuses, and overwrites, an existing row id, and a second delete of the first entry leaves an orphan row behind. | `lib/state/workout/timer_manager.dart:549-581`; `session_core_entry.dart:115-147` |
| G6 | 3a's D-313 appends `-<atMs>` when an id collides, and `DistancePairing` reads such an id as unnumbered, so it sorts last (review F-5). `entryNumberInId` has no caller. `DistancePairing.forEntries` is called by the Summary, the state writes, Stats and 3a's tests. | `session_core_entry.dart:319, 345, 416-444`; `lib/core/utils/distance_source.dart:28-84`; `lib/features/session/session_summary_screen.dart:999`; `lib/core/services/stats_progress_service.dart:649`; `test/distance_source_test.dart:530, 556, 570` |
| G7 | The distance entry-count rule exists twice (review F-6), and the name of a lone legacy row counts zero-valued rows (review N-4). | `session_summary_screen.dart:940-1003` (count at ~955, name at ~971); `session_core_entry.dart:403-414` |
| G8 | The entry-list builder pairs timed and hold companions by raw position. | `session_summary_builder.dart:356-377` |
| G9 | Duplicating a block gives copied rows random UUID ids, and the UI offers it for rolling sessions. | `mock_workout_repository.dart` `cloneSessionBlock` (`_mockUuid.v4()`); `hive_workout_repository.dart:2842`; `lib/features/session/workout_session_list_view.dart:195` |
| G10 | The watch import keeps its own rows numbered by entry position. It re-numbers moved entries, appends new ones at `lastIndex + 1`, and reads ids with its own prefix parser. | `lib/core/services/watch_session_importer.dart:494-530, 579-586, 602-622` |
| G11 | Stats and PR detection group sets through the grouper. The Stats pace pairs distances through `DistancePairing`, and its day total counts only paired rows (3a review N-3; ratified by D-321). | `stats_progress_service.dart:569, 645-669`; `lib/core/services/session_summary_service.dart:522` |
| G12 | `EffortObservation.toMap` always writes `value_bool` as 0 or 1. The contract's CHECK requires exactly one non-null among int, real, text and bool, so every row the app writes is refused (3a O-4). | `lib/data/models/models.dart:652`; `scripts/sqlite_schema.sql:376-381` |
| G13 | Harnesses to reuse: the Mock/Hive harness (`_Harness`, `_MockHarness`, `_HiveHarness` open/restart; `_loadState`) and the historical Summary pump. | `test/distance_source_test.dart:30-120, 275`; `test/session_summary_distance_test.dart`; `test/calendar_summary_screen_bugs_test.dart:31-90` |

## 3. Executor records (append below; one block per phase)

### Step 0 — preconditions (2026-09-27, Copilot)

- `git branch --show-current` → `develop`; `git status --short` → only the four plan files (this plan,
  its evidence, and the two plan files the planning pass touched), as the plan allows.
- `git merge-base --is-ancestor 4bb4afb develop` → exit 0 (the owner did not re-title it).
- Branch: `git switch -c feature/stats-pr3a2-entry-identity` → `Switched to a new branch
  'feature/stats-pr3a2-entry-identity'`.
- Baseline: `flutter test` → exit 0, `01:16 +3052 ~1: All tests passed!` — matches §1.
  `flutter analyze` → exit 1, `242 issues found. (ran in 3.5s)` — matches §1.

### Phase 1: the entry rule and new-row numbering — Copilot, 2026-09-27

Files: `lib/core/utils/entry_rows.dart` (new), `lib/core/utils/distance_source.dart`,
`lib/core/utils/observation_grouper.dart`, `lib/state/workout/session_core.dart` (import),
`lib/state/workout/session_core_entry.dart`, `lib/state/workout/timer_manager.dart`,
`lib/state/workout/session_summary_builder.dart`, `lib/state/workout/workout_state.dart`,
`lib/data/repositories/{hive,mock}_workout_repository.dart`,
`test/helpers/repository_harness.dart` (new), `test/entry_rows_test.dart` (new).

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `entry_rows_test.dart › Mock — the rule S-842` | S-842 | green (`+2`, no failure) | pass |
| `entry_rows_test.dart › Hive — the rule S-842` | S-842 | green (`+7`, no failure) | pass |
| `entry_rows_test.dart › Hive — the rule S-843` | S-843 | `Expected: <3> / Actual: <11>` | pass |
| `entry_rows_test.dart › Mock — the rule S-843` | S-843 | green — Mock returns insertion order, so the store never reordered the rows | pass |
| `entry_rows_test.dart › Hive — the rule S-844` | S-844 | `Expected: <300.0> / Actual: <1100.0>` | pass |
| `entry_rows_test.dart › Mock — the rule S-845` | S-845 | `Which: has no match for 'obs-effort-…-0-3-distance' at index 2 along with 1 other unmatched` | pass |
| `entry_rows_test.dart › Hive — the rule S-845` | S-845 | same as Mock | pass |
| `entry_rows_test.dart › Mock — the rule S-846` | S-846 | `Expected: [0.0, 0.0, 0.0, 2000.0, 0.0] / Actual: [0.0, 0.0, 0.0, 0.0, 2000.0]` | pass |
| `entry_rows_test.dart › Hive — the rule S-846` | S-846 | same as Mock | pass |
| `entry_rows_test.dart › Mock — the rule S-847` | S-847 | `Which: does not contain 'obs-fe463d64-…-0-reps'` (the copied ids were UUIDs) | pass |
| `entry_rows_test.dart › Hive — the rule S-847` | S-847 | same as Mock | pass |
| `entry_rows_test.dart › S-841` (both) | S-841 | red by absence (`EntryRows` did not exist) | pass |

- **D-320 outcome (Phase 1 gate, SP-4):** **REPRODUCED, fixed.** S-843 red on Hive
  (`Expected: <3> / Actual: <11>`) and green after the change. The single rule reads
  `…-extra-weight` ids, so a bodyweight effort no longer falls back to the store's order.
- **Unplanned but required:** S-844 was also red on Hive (`Expected: <300.0> / Actual: <1100.0>`, Mock
  green). The same store-order defect reached timed companions, so the companions of `timed` and
  `drill` entries and the set extra-weight overlay went through the rule here rather than in Phase 2.
- **Dropped:** none.
- Suites at the end of the phase:
  - `flutter test test/entry_rows_test.dart test/distance_source_test.dart test/utils_test.dart` → exit
    0, `00:00 +171: All tests passed!`
  - `flutter test` → exit 0, `01:22 +3066 ~1: All tests passed!` (3052 + 14 new; the skip is the one
    pre-existing).
  - `flutter analyze` → exit 1, `243 issues found.` One new (`unused_import` in `session_core.dart`),
    removed; the touched files other than `session_summary_screen.dart` (10, its §1 ceiling) and
    `session_core.dart` (1, as at baseline) report nothing.
- `git diff --name-only develop`: the Predicted Files plus `lib/state/workout/session_core.dart` (the
  import and the `_getMetricsPerEntry` fallback the plan's item list implies).
- Changed assertions in existing tests: none.

### Phase 2: writes, deletes and the remaining readers — Copilot, 2026-09-27

Files: `lib/state/workout/session_core_entry.dart`, `lib/state/workout/timer_manager.dart`,
`lib/state/workout/session_summary_builder.dart`, `lib/state/workout/workout_state.dart`,
`lib/features/session/session_summary_screen.dart`,
`test/entry_identity_test.dart` (new), `test/entry_identity_summary_test.dart` (new).

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `entry_identity_test.dart › Mock › S-851` | S-851 (SP-1) | `Expected: [(int, bool):(6, false)] / Actual: [(int, bool):(7, false)]` | pass |
| `entry_identity_test.dart › Hive › S-851` | S-851 (SP-1) | same as Mock | pass |
| `entry_identity_test.dart › Mock › S-852` | S-852 (SP-1) | same as S-851 | pass |
| `entry_identity_test.dart › Hive › S-852` | S-852 (SP-1) | same as S-851 | pass |
| `entry_identity_test.dart › Hive › S-853` | S-853 (SP-2) | `Expected: <99> / Actual: <3>` | pass |
| `entry_identity_test.dart › Mock › S-853` | S-853 (SP-2) | green — Mock returns insertion order, so raw row 2 is set 2 | pass |
| `entry_identity_test.dart › Hive › S-854` | S-854 (SP-3) | `Expected: <0> / Actual: <3>` | pass |
| `entry_identity_test.dart › Mock › S-854` | S-854 (SP-3) | green, same reason as S-853 | pass |
| `entry_identity_test.dart › Mock › S-855` | S-855 | `Expected: [3000.0, 4000.0] / Actual: [2000.0, 3000.0]` | pass |
| `entry_identity_test.dart › Hive › S-855` | S-855 | same as Mock | pass |
| `entry_identity_test.dart › Mock › S-856` | S-856 | `Which: does not contain 'obs-effort-…-0-5-distance'` | pass |
| `entry_identity_test.dart › Hive › S-856` | S-856 | same as Mock | pass |
| `entry_identity_test.dart › Mock › S-857` | S-857 (SP-5) | `Actual: Set:['obs-e-dip-0-extra-weight', 'obs-e-dip-1-extra-weight'] / Which: does not contain 'obs-e-dip-2-extra-weight'` | pass |
| `entry_identity_test.dart › Hive › S-857` | S-857 (SP-5) | same as Mock | pass |
| `entry_identity_test.dart › Mock › S-858` | S-858 | green (`+3`, no failure) | pass |
| `entry_identity_test.dart › Hive › S-858` | S-858 | green (`+5`, no failure) | pass |
| `entry_identity_test.dart › Mock › S-860` | S-860 | `Expected: [2, 77, 4, 0, 6, …] / Actual: [2, 77, 4, 0, 7, …]` | pass |
| `entry_identity_test.dart › Hive › S-860` | S-860 | `Expected: [2, 77, 4, 0, 6, …] / Actual: [2, 77, 12, 0, 3, …]` | pass |
| `entry_identity_summary_test.dart › S-855` | S-855 | `Expected: ['Easy Run · 1', '3.00', …] / Actual: ['Easy Run · 1', '2.00', …]` | pass |
| `entry_identity_summary_test.dart › S-856` | S-856 | `Which: at location [7] is '2.00' instead of '—'` | pass |
| `entry_identity_summary_test.dart › S-858` | S-858 | green (`+2`, no failure) | pass |
| `entry_identity_summary_test.dart › S-859` | S-859 | `Expected: ['Plank', '0.40', 'KM'] / Actual: ['Plank · 2', '0.40', 'KM']` | pass |

- **D-320 outcome (Phase 2 gate):**
  - **SP-1 (S-851, S-852): REPRODUCED, fixed** — on both stores; the second delete left reps 7.
  - **SP-2 (S-853): REPRODUCED on Hive, fixed** — the edit landed on set 10 (`Actual: <3>`); green on
    Mock because Mock returns insertion order, which is the plan's expected asymmetry.
  - **SP-3 (S-854): REPRODUCED on Hive, fixed** — the skip marked set 10; green on Mock, same reason.
  - **SP-5 (S-857): REPRODUCED, fixed** — on both stores the created id was `obs-e-dip-1-extra-weight`
    (the entry's position) rather than set 2's own number. The first run of this scenario did **not**
    reproduce because the fixture gave set 2 an extra-weight row, which sent the test down the update
    path instead of the create path; the fixture now matches the plan (only set 0 has one) and the
    predicted failure is exact.
  - **Dropped: none.** SP-4 was fixed in Phase 1 (see above).
- **Unplanned, reported not absorbed (O-4):** `TimerManager.addTimedEntry` mints instance ids as
  `timed-<effortId>-<index>-<ms>`, so an add after a delete collides with an existing instance when the
  two calls land in the same millisecond — the added instance overwrites the stored one, leaving the
  effort one instance short. S-856 exposed it on Hive after a restart. The fix belongs to
  `TimedInstance` ids, which the watch import derives (`WatchSessionImporter.timedInstanceIdFor`), so it
  is out of this PR's scope: **S-856 asserts the distance rows and the live entry list**, and the
  reopened half reads the rows rather than re-pairing them against the instances.
- Suites at the end of the phase:
  - `flutter test test/entry_identity_test.dart test/entry_identity_summary_test.dart test/state_test.dart
    test/session_summary_distance_test.dart test/stats_distance_estimate_test.dart
    test/watch_session_edit_restore_summaries_test.dart` → exit 0, `00:03 +283: All tests passed!`
  - `flutter test` → exit 0, `01:31 +3089 ~1: All tests passed!` (Phase 1's 3066 + 23 new; the skip is
    the one pre-existing).
  - `flutter analyze` → exit 1, `244 issues found.` Two new (`unused_import`, `unused_element`, both in
    the new test files), removed; back to the 242 baseline below.
- `git diff --name-only develop`: within the Predicted Files.
- Changed assertions in existing tests: none.

### Phase 3: contract, docs and residue — Copilot, 2026-09-27

Files: `scripts/sqlite_schema.sql`, `test/db_seed_test.dart`, `.github/agents/docs/db_integration.md`.

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `db_seed_test.dart › S-861 the five rows the app writes insert as written` | S-861 | `Actual: SqfliteFfiException(275): CHECK constraint failed: (CASE WHEN value_int IS NOT NULL THEN 1 ELSE 0 END)` | pass |
| `db_seed_test.dart › S-861 a row carrying two values is refused` | S-861 | green (the old CHECK refused everything) | pass |

- Suites at the end of the phase:
  - `flutter test test/db_seed_test.dart test/docs_indexing_contract_test.dart` → exit 0,
    `00:00 +18: All tests passed!`
  - `flutter test` → exit 0, `01:30 +3091 ~1: All tests passed!` (3091 passed, 1 skipped — 39 more than
    the 3052 baseline, and the skip is the one pre-existing).
  - `flutter analyze` → exit 1, `242 issues found.` — the baseline count exactly, with
    `session_summary_screen.dart` at 10 (its §1 ceiling) and `session_core.dart` at 1 (its ceiling).
    Every other touched file reports nothing.
- **Residue checks:**
  - `grep -rln "RegExp(r'obs-" lib` → nothing; the only phone file that parses an observation id is
    `lib/core/utils/entry_rows.dart` (the four files that mention `obs-` are the two id builders,
    `entry_rows.dart`, and the watch importer's own prefix reader).
  - `grep -rn "entryNumberInId\|_distanceEntryCount\|-\$atMs" lib` → nothing.
  - `grep -rn "asMap()" lib/state/workout/` → nothing; no phone writer indexes the raw observation list.
- `git diff --name-only develop`: within the Predicted Files.
- Changed assertions in existing tests: `test/db_seed_test.dart` gained the S-861 group and its
  `_observationRow` helper gained an `effortId` parameter and three more metric/unit fixture rows; no
  existing assertion changed.

### Whole PR — final state, 2026-09-27

- `flutter test` → exit 0, `+3091 ~1: All tests passed!`. That is 3052 + 39: `entry_rows_test.dart`
  14, `entry_identity_test.dart` 19, `entry_identity_summary_test.dart` 4, `db_seed_test.dart` 2. The
  one skip is the pre-existing `test/profile_navigation_test.dart:39`.
- `flutter analyze` → exit 1, `242 issues found.` — the §1 baseline count exactly, with
  `session_summary_screen.dart` at 10 (its §1 ceiling), `session_core.dart` at 1 (its ceiling) and every
  other touched file at 0.
- `dart format` → every file this PR touched is formatted. The repository has 19 pre-existing
  unformatted files (`lib/core/constants/omni_theme.dart`, `lib/core/platform/watch_transport.dart`,
  the watch files and several older tests); none of them is touched here and none was reformatted.
- `git diff --name-only develop` and `git ls-files --others --exclude-standard` list only the Predicted
  Files plus the two plans the planning pass touched and this plan + its evidence file.
- The PR lands on `feature/stats-pr3a2-entry-identity`; the owner merges into `develop`.

### Review-fix round (F-1–F-5, F-8, F-9, N-1, N-2) — Copilot, 2026-09-27

Files: `lib/state/workout/session_core_entry.dart`, `lib/state/workout/session_summary_builder.dart`,
`lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`,
`lib/core/services/stats_progress_service.dart` (comment); tests `test/entry_identity_test.dart`,
`test/entry_rows_test.dart`, `test/helpers/repository_harness.dart`, `test/db_seed_test.dart`. One new
harness seeder, `seedHoldEffort` (a `drill`/`timed` effort with chosen rows).

Red runs: the fix's own hunks were reverted in place (the three source files copied to `/tmp` first, the
hunks restored by hand, then the copies restored and `diff -q`'d back — never `git stash`).

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `entry_identity_test.dart › Mock › S-862` | S-862 (F-5) | `Expected: [0.0, 1.0, 2.0] / Actual: [1.0, 2.0, 2.0]` | pass |
| `entry_identity_test.dart › Hive › S-862` | S-862 (F-5) | same as Mock | pass |
| `entry_identity_test.dart › Mock › S-863` | S-863 (F-4) | `Expected: {'obs-e-plank-1-extra-weight': 7.0, 'obs-e-plank-2-extra-weight': 5.0} / Actual: {'obs-e-plank-1-extra-weight': 5.0}` | pass |
| `entry_identity_test.dart › Hive › S-863` | S-863 (F-4) | same as Mock | pass |
| `entry_identity_test.dart › Mock › S-864` | S-864 (F-4) | `Expected: {'obs-e-side-1-extra-weight': 0.0, 'obs-e-side-2-extra-weight': 5.0} / Actual: {'obs-e-side-1-extra-weight': 5.0}` | pass |
| `entry_identity_test.dart › Hive › S-864` | S-864 (F-4) | same as Mock | pass |
| `entry_rows_test.dart › Mock › S-847` | S-847 (F-8) | `Which: does not contain 'obs-<clone>-0-reps'` (the copy's rows held fresh UUIDs) | pass |
| `entry_rows_test.dart › Hive › S-847` | S-847 (F-8) | same as Mock | pass |

- **S-847 tightened (F-8, F-9):** the timed half of the fixture now carries S-846's own shape — numbers
  1, 2, 3, a second row at 3 (`obs-e-d-3-distance-9000`) and 4 across five instances. The copy's five ids
  are asserted, so the suffixed row is proven to survive the copy and the 2000 m still pairs with entry 4.
  The copy's set ids were asserted before the round; the failure above is that assertion.
- **S-855, S-856, S-860 tightened (F-9):** their row assertions name the stored ids (S-855's two distance
  and two extra-weight rows; S-860's full `e-row` and `e-run` id sets). S-856's reopened half now waits
  2 ms before the add after the delete (O-4's instance-id collision) and asserts the full five-entry
  distance list and the live Summary half. S-860's weak "unique and unsuffixed" loop is replaced by the
  exact id sets; it surfaced that a new set also gets an `-extra-weight` row, which the expectation now
  records. The plan's S-860 spec was corrected to match.
- **Red runs for the tightened tests:** the S-847 group is the one quoted above. S-855, S-856 and S-860
  were green before the round's fixes and stay green — their tightening adds assertions over code this
  round did not change (S-860's id sets are Phase 2's D-326 behaviour), so there is no unfixed code for
  them to be red against; they are recorded as tightening, not as fix evidence.
- **Two expectations corrected against the code, not the code against the test:** S-864's fill row is
  numbered 1 (the fill numbers above the effort's stored rows), and S-860's effort also gained
  `obs-e-row-12-extra-weight`.
- Suites at the end of the round:
  - `flutter test test/entry_rows_test.dart test/entry_identity_test.dart test/entry_identity_summary_test.dart`
    → exit 0, `00:04 +43: All tests passed!`
  - `flutter test` → exit 0, `01:27 +3097 ~1: All tests passed!` (3091 + 6: S-862, S-863 and S-864 on both
    stores; the skip is the one pre-existing).
  - `flutter analyze` → exit 1, `241 issues found.`, 0 errors. `session_summary_screen.dart` at 10 (its §1
    ceiling), `session_core.dart` at 0 and every other touched file at 0. The count is one below the §1
    baseline of 242: `lib/state/workout/session_core.dart:161` no longer trips
    `curly_braces_in_flow_control_structures`, because the Phase 1 `dart fix` pass that removed the unused
    import also applied that file's other fixable lint. Its §1 ceiling of 1 still holds.
  - `dart format` → every file this round touched is formatted; the repository's pre-existing unformatted
    files are unchanged.
- `git diff --name-only develop`: unchanged from the PR's list — this round added no file.
- Changed assertions in existing tests: none loosened. `test/entry_rows_test.dart › S-847` and
  `test/entry_identity_test.dart › S-855/S-856/S-860` gained assertions (F-9);
  `test/db_seed_test.dart`'s `_observationRow` lost its unused `effortId` parameter (N-2).
