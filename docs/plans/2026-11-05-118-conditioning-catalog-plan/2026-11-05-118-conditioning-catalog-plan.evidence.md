# 118 — Evidence (baselines, suite outputs, red→green tables)

Implementers write here, not into the plan.

## Phase 1 — baselines (before any edit)

- Base commit: `ecf2d050` (`claude_develop`, ahead of origin by 2).
- P (lead's item 3, already in the working tree): `bundledCatalogVersion = 18`.
- `flutter analyze` (gateway `lint`): **`181 issues found. (ran in 3.9s)`** (0 errors, 1 warning, the rest
  `info`). Baseline for the Done Criteria.
- Done Criteria suites (item 1): `gateway test -- test/catalog_reference_refresh_test.dart
  test/catalog_delivery_contract_test.dart test/db_seed_test.dart` → **`00:01 +56: All tests passed!`**
- Watch files, unedited (S-19208 baseline): `gateway test -- test/watch_reference_sync_test.dart
  test/watch_sync_request_handler_test.dart test/watch_sync_changed_only_test.dart test/watch_transport_test.dart`
  → **`00:00 +156: All tests passed!`** (the gateway summary's "lines that look like failures (1)" is the
  progress line `S-6906 the graph when the link cannot read its stored stamp`, not a failure; exit 0,
  `All tests passed!`). No edit.

## Phase 1 — red → green

Each red is the matching production edit reverted in place, then restored; no backup file was created.

| Step | Files run | Red | Green |
|---|---|---|---|
| item 2 reverted (the D-19201 `Discipline` row removed) | `test/conditioning_catalog_test.dart` | **`00:00 +1 -4: Some tests failed.`** — "exactly one Conditioning row" (`Expected: an object with length of <1> / Actual: []`), "sits directly after Calisthenics" (`Expected: <8> / Actual: <-1>`), "37 disciplines" (`Actual: … has length of <36>`), "the Resistance / Lifting filter lists it last" (actual list ends at `discipline-calisthenics`). The fifth test ("no other row shares its key or name") passes vacuously without the row | restored: the same file is green in the run below |
| item 3 reverted (the D-19208 SQL insert removed) | `test/db_seed_test.dart` | **S-19203 red**: `Expected: an object with length of <1> / Actual: []` at `test/db_seed_test.dart:533:9` (the rest of the file green, `+12 -3` including two bogus `--plain-name` load errors — see below) | restored: the whole file green in the run below |

`--plain-name` is not forwarded by the gateway's `test` check in the argument position used: `gateway test --
test/db_seed_test.dart --plain-name "S-19203"` reported `Failed to load ".../--plain-name"` and
`Failed to load ".../S-19203"` (two load errors) before running the file normally. The S-19203 failure above is
the real one; the later green runs use no flag.

## Phase 1 — suite totals after the change

- Done Criteria (item 1 baseline re-run plus the two contract suites):
  `gateway test -- test/conditioning_catalog_test.dart test/db_seed_test.dart test/catalog_reference_refresh_test.dart
  test/catalog_delivery_contract_test.dart test/reference_data_upsert_test.dart test/catalog_refresh_test.dart
  test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
  → **`00:04 +148: All tests passed!`** (the gateway's "lines that look like failures (4)" are progress lines;
  exit 0, `All tests passed!`).
- The new `test/conditioning_catalog_test.dart` alone → **`00:00 +5: All tests passed!`**; `test/db_seed_test.dart`
  alone → **`00:00 +18: All tests passed!`** (with S-19203).
- Watch files, unedited, before any edit (S-19208 baseline) → **`+156: All tests passed!`** (four batches; the
  seeded catalog is not changed by this phase, no edit).
- `flutter analyze` (gateway `lint`) after the change: **`181 issues found. (ran in 3.5s)`** — equal to the
  baseline, so ≤ baseline holds.
- `grep -c "discipline-conditioning" lib/mock/seed_data.dart` → **1** (the new row).
- `grep -c "key='conditioning'|'conditioning', 'Conditioning'" scripts/sqlite_seed.sql` → **2** (the value and
  the `NOT EXISTS` guard).
- `grep -rln "hive_workout_repository"` in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` → **nothing**
  (the only hit in `lib/` is `lib/main.dart`, which composes the repositories and is outside the invariant's
  four directories).
- `git-diff --stat` of the touched tracked files: `lib/mock/seed_data.dart | 8 +`,
  `scripts/sqlite_seed.sql | 5 +`, `test/db_seed_test.dart | 35 +` — 48 insertions, 0 deletions.

The full `flutter test` was not run: the brief says the lead runs it.

## Phase 2A — red → green (rows 1-9)

Baseline carried from Phase 1: `flutter analyze` **181 issues**; the seed carries `discipline-conditioning`
and catalog version 18. No file is created outside the brief's predicted list.

| Step | Files run | Red | Green |
|---|---|---|---|
| the nine seed `Exercise` blocks removed from `sampleExercises` only (muscle, equipment and capability maps left in place) | `test/conditioning_catalog_test.dart` | **`00:00 +5 -10: Some tests failed.`** — the nine per-row tests (`Expected: an object with length of <1> / Actual: Set:[]`, e.g. `missing exercise-plyo-push-up`) and "the Conditioning discipline lists exactly the new rows" (`Expected` the nine ids, `Actual: Set:[]`). The S-19201 tests (+5) stay green | restored: the same file → **`00:00 +17: All tests passed!`** |

The first red run above was taken before item 1 was written at all: same `+5 -10` shape, so the group is red for
the missing rows and nothing else.

## Phase 2A — suite totals after the change

- `gateway test -- test/conditioning_catalog_test.dart test/strength_catalog_gaps_test.dart
  test/catalog_referential_integrity_test.dart` → **`00:00 +84: All tests passed!`**
- `gateway test -- test/muscle_filter_test.dart test/db_seed_test.dart test/catalog_reference_refresh_test.dart
  test/catalog_delivery_contract_test.dart test/yoga_catalog_test.dart test/watch_reference_sync_test.dart`
  → **`00:02 +140: All tests passed!`** (S-3858 and S-19306 still see four batches; S-19303's Yoga filter
  still holds its 24 rows).
- `gateway test -- test/conditioning_catalog_test.dart test/strength_catalog_gaps_test.dart
  test/catalog_referential_integrity_test.dart test/muscle_filter_test.dart test/db_seed_test.dart
  test/catalog_reference_refresh_test.dart test/catalog_delivery_contract_test.dart test/yoga_catalog_test.dart
  test/watch_reference_sync_test.dart` (the brief's Done list, one run) → **`00:02 +224: All tests passed!`**
- `flutter analyze` (gateway `lint`) → **`181 issues found. (ran in 3.5s)`**, equal to the baseline.
- `disciplineId: 'discipline-conditioning'` in `lib/mock/seed_data.dart` → **9** occurrences.
- `git-diff --stat` of the touched tracked files: `lib/mock/seed_data.dart | 188 +`,
  `test/catalog_referential_integrity_test.dart | 16 +-`, `test/strength_catalog_gaps_test.dart | 12 +-`
  (210 insertions, 6 deletions; the deletions are the two rewritten `hasLength` call sites and the two
  extended size expectations).
- `grep -rln "import .*hive_workout_repository"` in `lib/state`, `lib/features`, `lib/widgets`, `lib/core`
  → **nothing** (the only hit in `lib/` is `lib/main.dart`).

No exact Main Chest / Core set exists in `test/catalog_referential_integrity_test.dart`, so the only exact set the
new links change is Assisting Calves; it gained the six jumping rows (2B adds High Knees).

The full `flutter test` was not run: the brief says the lead runs it.

## Phase 2B — report (crew-builder-data)

- Item 1 (rows 10–13, `exercise-mountain-climber` … `exercise-high-knees`, in `lib/mock/seed_data.dart`): done.
- Item 2 (rows 14–17, `exercise-battle-ropes` … `exercise-thruster`): done; battle-ropes and medicine-ball-slam
  and wall-ball carry no equipment id, thruster carries `equipment-barbell`, rows 15–17 add `load` and rows 10–14
  do not.
- Item 3 (helper rows 10–17 in `test/helpers/conditioning_catalog_rows.dart`; the S-19202 table now runs 17
  rows; S-19204 exact sets completed in `test/catalog_referential_integrity_test.dart` with Main Calves gaining
  `exercise-jumping-jack`, Assisting Calves `exercise-high-knees`, and a new `mainIds` / `assistIds` block):
  done.
- Item 4 (S-19209 group in `test/conditioning_catalog_test.dart`; S-19208 watch files run unedited): done.
- Item 5 (name-ordered widget test suspects): not run here (the lead runs the full suite). Suspects named below.
- Item 6 (evidence, Progress, Assumption Log): this section, the plan checkbox and the Assumption Log entry.

## Phase 2B — red → green (rows 10–17)

| Step | Files run | Red | Green |
|---|---|---|---|
| the `exercise-mountain-climber` `Exercise` block removed from `sampleExercises` only (its muscle, equipment and capability entries left in place) | `test/conditioning_catalog_test.dart`, `test/catalog_referential_integrity_test.dart` | **`00:00 +36 -4: Some tests failed.`** — `S-19202 … mountain-climber` (`Expected: an object with length of <1> / Actual: Set:[]`), `the Conditioning discipline lists exactly the new rows` (`Actual` set lacks `exercise-mountain-climber`), and the two keyed-by-real-exercises tests (`R-003: relationship maps are keyed by real exercises` and `S-3: the map is keyed by real exercises`, both `Expected: empty / Actual: Set:['exercise-mountain-climber']`) | restored: the same two files → **`00:00 +40: All tests passed!`** |

## Phase 2B — suite totals after the change

- Brief's Done list, final run (the nine files: `conditioning_catalog_test`, `strength_catalog_gaps_test`,
  `catalog_referential_integrity_test`, `muscle_filter_test`, `db_seed_test`, `catalog_reference_refresh_test`,
  `catalog_delivery_contract_test`, `yoga_catalog_test`, `watch_reference_sync_test`) → **`00:02 +234: All tests
  passed!`** (`.work/gateway/test-20261105-194436-26211.log`). An earlier eight-file run of the same list before the
  red experiment was `+205` (`.work/gateway/test-20261105-194022-23213.log`).
- The four watch files, unedited, in one run (S-19208) → **`00:00 +156: All tests passed!`** — four batches still,
  the seeded catalog and the wire shape are unchanged by the phase
  (`.work/gateway/test-20261105-194029-23387.log`).
- `flutter analyze` (gateway `lint`) → **`181 issues found. (ran in 3.7s)`**, equal to the Phase 1 baseline.
- `lib/mock/seed_data.dart` by search tool: `^      id: 'exercise-` → **339**; `disciplineId:
  'discipline-conditioning'` → **17**. Before the phase the seed carried 331 rows (Phase 2A left it at 322 + 9),
  so the eight new rows put it at 339 and 17 conditioning.
- `git-diff --stat` (cumulative against HEAD, which has neither 2A nor 2B, since Phase 2A was not committed):
  `lib/mock/seed_data.dart | 346 +`, `test/catalog_referential_integrity_test.dart | 40 +-`
  (384 insertions, 2 deletions). Phase 2B alone is +158 seed lines and +24/-2 in the referential test; the shared
  helper and `test/conditioning_catalog_test.dart` are untracked files created in Phase 2A, so they do not appear
  in `git diff`.
- `grep -rln "import .*hive_workout_repository"` in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` →
  **nothing** (four searches, no matches).

Name-ordered widget test suspects (not run here): `test/screen_widget_test.dart`,
`test/pr8_exercise_library_test.dart`, `test/library_grouping_test.dart` and `test/library_row_toggle_test.dart`
all drive the exercise list with `scrollUntilVisible`, and six of the eight new names (Battle Ropes, Bear Crawl,
High Knees, Jumping Jack, Medicine Ball Slam, Mountain Climber) sort before `Push-Up` in a name-ordered list.
They are the only places a pushed-down row could matter; no failure was observed for them in this run because
they were not run.

The full `flutter test` was not run: the brief says the lead runs it.

## Phase 3 — report (crew-builder-data)

The section was written as a skeleton before the first run; the counts are the real output.

- Item 1 (S-19205, fresh install: ranking 70/80, the discipline filter, Cardio 15/5, the five muscle
  filters, the name search, the discipline name and the equipment): done, in the new
  `test/conditioning_catalog_refresh_test.dart`. Every plan expectation held on both harnesses, so no
  assertion was stopped or bent. The muscle filters use the yoga file's call shape —
  `searchExercises(muscleGroupIds: ['muscle-<id>'])` with the taxonomy ids `muscle-chest`,
  `muscle-core`, `muscle-calves`, `muscle-lats`, `muscle-shoulders` — and read primary links only
  (`MuscleTaxonomy.matches`). The Core expectation runs over both `muscle-core` (the region the plan
  names) and `muscle-abs` (the id the library's Core filter maps to, A-118-2).
- Item 2 (S-19206, a v17 install refreshes: discipline and rows land, U/T1/T2 and the copy K
  untouched, `exercise-push-up` keeps "Plyo Push-Up", the second `refresh()` false, the Hive-only
  empty equipment line): done.
- Item 3 (S-19207, discipline missing: 30/40 before, 70/80 after, the filter still 17): done.
- Item 4 (a) version mutation: SKIPPED, the lead does version mutations.
- Item 4 (b) the D-19201 row removed by hand → red: **blocked**. The edit is to
  `lib/mock/seed_data.dart`, which is outside this run's write scope; the tool denied it
  (`Permission denied because no interactive user response was available`). Not worked around.
- Item 4 (c) the `exercise-thruster` rows removed by hand → red: **blocked**, same denial.
- Item 5 (Progress and Assumption Log): done.

| Step | Files run | Red | Green |
|---|---|---|---|
| 4(b) the `discipline-conditioning` row removed from `SeedData.sampleDisciplines` by hand | — | not run: the edit to `lib/mock/seed_data.dart` is outside this run's write scope and was denied | — |
| 4(c) the `exercise-thruster` rows removed from `SeedData.sampleExercises` by hand | — | not run: same denial | — |

What the blocked rows leave uncovered, and what is still covered without a production edit:

- 4(b) removes the discipline from the seed. S-19207 stages exactly that install state through `_stageMissing`
  (the discipline absent on a v17 install) and asserts the numbers that state produces — `burpee` 30.0,
  `thruster` 40.0 before the row returns, 70.0 / 80.0 after. So the seed-absence behaviour is asserted, but the
  "the bundled seed really carries the row" half is only asserted indirectly, by S-19205/S-19206 being green
  against the real bundle.
- 4(c) removes the thruster rows. No in-scope fixture produces that state (removing seed exercises is a production
  edit), so nothing in this file covers it; `test/conditioning_catalog_test.dart`'s exact-set assertion is the
  nearest guard and was green in the Done run.

The only red the run could obtain without a production edit:

- `gateway prove-red HEAD test -- test/conditioning_catalog_refresh_test.dart` → the check ran the
  tree at `HEAD` and reported
  `test/conditioning_catalog_refresh_test.dart:35:8: Error: Error when reading 'test/helpers/conditioning_catalog_rows.dart': No such file or directory`
  (three `Undefined name 'conditioningCatalogRows'` errors after it), then
  `02:57 +6607 ~2 -1: Some tests failed.`
  The helper is an untracked Phase 2A file, so `prove-red` did not carry it: the failure is a
  compile error, not the assertions going red. It is **not** evidence that S-19205/S-19206/S-19207
  guard the absence of the discipline and the rows, and it should not be read as such.

Suite totals after the change:

- `gateway test -- test/conditioning_catalog_refresh_test.dart` → **`00:00 +6: All tests passed!`**
  (3 scenarios × Mock and Hive).
- `gateway test -- test/conditioning_catalog_refresh_test.dart test/conditioning_catalog_test.dart
  test/catalog_reference_refresh_test.dart test/catalog_delivery_contract_test.dart
  test/yoga_catalog_refresh_test.dart` (the brief's Done list, one run) →
  **`00:01 +83: All tests passed!`**
- `flutter analyze` (gateway `lint`) → **`181 issues found. (ran in 3.0s)`**, equal to the baseline,
  and the new file contributes none of them.
- `dart format test/conditioning_catalog_refresh_test.dart` → `Formatted 1 file (1 changed)`; the
  file was re-run green after the format.
- `grep -rln "import .*hive_workout_repository"` in `lib/state`, `lib/features`, `lib/widgets`,
  `lib/core` → **nothing** (the only hit in `lib/` is `lib/main.dart`).
- `git-diff --stat` → unchanged from before the run: `lib/core/constants/catalog_version.dart | 6 +-`,
  `lib/mock/seed_data.dart | 346 +`, `scripts/sqlite_seed.sql | 5 +`,
  `test/catalog_referential_integrity_test.dart | 40 +-`, `test/db_seed_test.dart | 35 +`,
  `test/strength_catalog_gaps_test.dart | 12 +-` (437 insertions, 7 deletions). This run changed no
  tracked file: the new test and the evidence are untracked.

The full `flutter test` was not run by this builder; the lead runs it.


