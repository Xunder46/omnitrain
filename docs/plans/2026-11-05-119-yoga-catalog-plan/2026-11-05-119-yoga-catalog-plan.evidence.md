# 119 yoga catalog — evidence

Implementers record here: P (the catalog version before this PR), baselines, red→green tables, suite totals,
the residue sweep, and unpredicted files.

## Phase 3B — the docs delta and the residue sweep (`crew-builder-data`, docs only)

P at this run = **17** (`lib/core/constants/catalog_version.dart:74`: `const int bundledCatalogVersion = 17;`).

The four Docs-delta edits:

- `docs/db_integration.md` — a new "Catalog version `17` adds 22 yoga poses …" paragraph after the version-15
  paragraph (before the `SeedEntryType` table), citing `S-19304 a version-P install refreshes`,
  `S-19305 a renamed touched row and near-twins keep their own` and `S-19307` (all in
  `test/yoga_catalog_refresh_test.dart`) and `S-19311` (`test/health_yoga_kind_test.dart`). +7 lines, no existing
  line reflowed.
- `docs/constants_reference.md:575` — `bundledCatalogVersion` value `16` → `17`.
- `docs/constants_reference.md:271` — the `HealthActivityKind` vocabulary gains `yoga` between `sport` and
  `conditioning`, the enum's own order (`lib/core/constants/health_constants.dart:41-43`).
- `docs/state_management/watch_reference_data.md:22` — "a phone with 300 seeded exercises" → "a phone with more
  than 300 seeded exercises" (D-19311).

Checks:

```
gateway: test test/docs_indexing_contract_test.dart   →  00:00 +13: All tests passed!
gateway: lint                                         →  181 issues found. (ran in 3.4s)   (baseline 181)
grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core  →  nothing
```

`wc -c` cannot run from this agent's shell (the gateway is the only command). The indexing contract test that
just passed is the stronger check: it fails any doc above the 64 KiB ceiling and any doc above 80 % of it
(52,429 B), so all three docs are ≤ 52,429 B — under the brief's 53,248 B.

Residue sweep:

```
$ grep -rn "hasLength(226)\|equals(16)" test
test/data_migration_test.dart:564: expect(mockSteps[mockSteps.length - 2].targetVersion, equals(16));
test/data_migration_test.dart:566: expect(hiveSteps[hiveSteps.length - 2].targetVersion, equals(16));
test/data_migration_test.dart:748: expect(mockSteps[mockSteps.length - 2].targetVersion, equals(16));
test/data_migration_test.dart:750: expect(hiveSteps[hiveSteps.length - 2].targetVersion, equals(16));
```

All four are `data_migration_test.dart` data-version pins (the migration step list's second-to-last target), not
catalog pins; `hasLength(226)` returns nothing.

```
$ grep -rn "hasLength(3)," test        (28 hits, 12 files)
crash_reporting_test.dart:625,738,803        reporter.capturedErrors — three captured crash reports
screen_widget_test.dart:5219                 a screen fixture list
watch_session_engine_test.dart:763,1409      queued session entries
watch_finish_once_test.dart:902,953,1142     finish/attempt frames
watch_session_queue_test.dart:370,394        _entryIds of the queued snapshots
watch_bodyweight_load_test.dart:331,399,413,531  load rows
watch_live_refresh_screen_test.dart:730,1057 rows in the live-refresh fixture
mix_layer_screen_test.dart:2693              reason: 'three distinct weeks'
watch_timed_fill_test.dart:744,764,790,1132,1145  timed-fill frames
watch_session_auto_push_test.dart:4146       pushes in the fixture
watch_reference_sync_test.dart:475           S-3843's synthetic 250-exercise fixture: three batches by construction
watch_timer_push_test.dart:1141,2717,3089    frames (S-9930 T1, the clear, then T2)
```

Every site counts a fixture list of three in its own domain; none pins the seeded catalog's `exercises_down`
batch count. The real-catalog pin S-3858 is already `hasLength(4)` with reason "the seeded catalog is more than
three batches" (`test/watch_reference_sync_test.dart:596` and `:624`).

```
$ grep -rn --exclude-dir=plans --exclude-dir=history --exclude-dir=releases "300 seeded" docs
docs/state_management/watch_reference_data.md:22: … a phone with more than 300 seeded exercises would send tens
```

The only remaining site is the edited line, and it says "more than"; no site says exactly `300 seeded exercises`
without `more than` → **0**. (The raw phrase survives only inside `docs/plans/**`, which is the plan text.)

```
$ grep -n "bundledCatalogVersion" docs/constants_reference.md
575:| `bundledCatalogVersion` | `17` | Content version of the bundled catalog (…)
578:`bundledCatalogVersion`; when the bundled version is newer,
```

```
$ git diff --stat -- scripts
 scripts/sqlite_seed.sql | 27 +++++++++++++++++++--------
 1 file changed, 19 insertions(+), 8 deletions(-)
```

Only the `sqlite_seed.sql` hunk of Phase 3A item 5 — `sqlite_schema.sql` untouched.

Phase 3B box 6 (the full `flutter test`) is the lead's and stays open on this run's exit.

## Phase 3A — the governor's red→green and the D-19313 implementation

Red step (all five production files reverted to base `24e1a26d` — version 16, 300-row seed, no yoga kind):

- `flutter test test/yoga_catalog_refresh_test.dart test/muscle_filter_test.dart test/health_yoga_kind_test.dart
  test/health_platform_mapper_test.dart` → **`+22 -15: Some tests failed.`** (S-19303/04/05/07 red on the missing
  rows, the Stretching-filter pins and the Yoga discipline; S-19311's two files fail to load: `Member not found:
  'yoga'`).

Implementation by the lead (D-19313): `HealthActivityKind.yoga` (`health_constants.dart`),
`pluginActivityTypeFor(yoga)` → `YOGA` on both platforms (`health_platform_gateway_io.dart`), and the writer's
all-yoga branch (`health_sync_service.dart`: `_activityKindOf` reads the session's segments + efforts from the
repository, requires every exercised id's discipline to be `discipline-yoga` and the list non-empty, else the
modality mapping).

Green step (files restored + implementation in):

- The same four files → **`+49: All tests passed!`**.
- Phase 3A Done Criteria (five test files + ui_standards + db_seed) → **`+128: All tests passed!`**;
  `flutter analyze` → `181 issues` (baseline).
- Full suite → **`+6607 ~2 -0: All tests passed!`** (log at `.work/2026-11-05-119-yoga-catalog/full-suite-p3a.log`).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing.

Mock-only exceptions as planned: S-19307's equipment-link staging is Hive-only (Mock cannot delete a link);
S-19311 is Mock-only by rig.

## Phase 1 — baselines (before any edit)

Measured 2026-11-05 at base `24e1a26d16d88c1a1aa70234ebc170a402f4dc7c`.

- **P** (D-19307) = `bundledCatalogVersion` = **16** (`lib/core/constants/catalog_version.dart`).
- **`flutter analyze`** (gateway `lint`): **`181 issues found. (ran in 3.9s)`** — 0 errors, 1 warning,
  the rest `info`. This is the baseline the Done Criteria compare against.
- **Done Criteria suites** (the nine that exist before this PR; `test/yoga_catalog_test.dart` is new):
  `flutter test test/strength_catalog_gaps_test.dart test/catalog_referential_integrity_test.dart
  test/catalog_reference_refresh_test.dart test/catalog_delivery_contract_test.dart
  test/catalog_refresh_test.dart test/strength_catalog_v15_refresh_test.dart test/muscle_filter_test.dart
  test/watch_reference_sync_test.dart test/db_seed_test.dart` → **`00:02 +203: All tests passed!`**
  (203 passed, 0 failed).

## Phase 1 — red → green

| Scenario | File | Red (before the seed rows) | Green (after) |
|---|---|---|---|
| S-19301 | `test/yoga_catalog_test.dart` | `00:00 +2 -13: Some tests failed.` — the 11 rows missing (`Expected: an object with length of <1> / Actual: Set:[]`), the Yoga set `Actual: Set:[]`, Pigeon Pose `Expected: 'discipline-yoga' / Actual: 'discipline-stretching'` | `00:00 +15: All tests passed!` |
| S-19302 (guards, re-baselined) | the four guard files | n/a — re-baselined, not new | `00:02 +134: All tests passed!` (four files together) |

## Phase 1 — suite totals after the change

- `flutter test test/yoga_catalog_test.dart test/strength_catalog_gaps_test.dart
  test/catalog_referential_integrity_test.dart test/catalog_reference_refresh_test.dart
  test/catalog_delivery_contract_test.dart test/catalog_refresh_test.dart
  test/strength_catalog_v15_refresh_test.dart test/muscle_filter_test.dart
  test/watch_reference_sync_test.dart test/db_seed_test.dart
  test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
  → **`00:05 +272: All tests passed!`**
- `flutter analyze` (gateway `lint`) after the change: **`181 issues found. (ran in 3.4s)`** — equal to the
  baseline, so ≤ baseline holds.
- `grep -c "disciplineId: 'discipline-yoga'" lib/mock/seed_data.dart` → **13** (11 new rows + the 2 moves).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing.

## Phase 1 — the lead's item 4 (version bump)

- `bundledCatalogVersion` `16` → **`17`** and the D-19307 sentence appended to the doc comment
  (`lib/core/constants/catalog_version.dart`). After the bump: the same Done Criteria run
  (the nine suites + the two contract suites) → **`00:04 +272: All tests passed!`**;
  `flutter analyze` → `181 issues` (baseline); `grep -n "bundledCatalogVersion = " shows 17`.

Unpredicted files: none.

## Phase 2 — red → green (rows 12–22, S-19306)

Scope of this phase (runner-enforced): `lib/mock/seed_data.dart`, `test/helpers/yoga_catalog_rows.dart`,
`test/watch_reference_sync_test.dart`, `docs/plans/2026-11-05-119-yoga-catalog-plan/*`.

| Step | Files run | Red | Green |
|---|---|---|---|
| helper rows 12–22 first (seed untouched) | `test/yoga_catalog_test.dart` | `00:00 +14 -12: Some tests failed.` — the 11 rows missing (`Expected: an object with length of <1> / Actual: Set:[]`) and the Yoga set `Actual: Set:[]` | — |
| seed rows 12–22 + the three maps | `test/yoga_catalog_test.dart test/strength_catalog_gaps_test.dart test/catalog_referential_integrity_test.dart test/watch_reference_sync_test.dart` | — | `00:00 +122: All tests passed!` |
| item 5 red step (seed rows reverted, helper left at 22) | `test/yoga_catalog_test.dart test/watch_reference_sync_test.dart` | `00:00 +42 -13: Some tests failed.` — S-19301 on the 11 missing rows + the Yoga set, S-19306 `does not contain 'exercise-eagle-pose'` | — |
| item 5 green step (seed rows restored) | the same two files | — | `00:00 +55: All tests passed!` |

The item-5 revert was done as an in-place edit and its exact inverse, not as a
`.work/crew/2026-11-05-119-yoga-catalog/backup/` copy cycle: the runner has no copy/`mkdir` check and the
`.work/crew/` paths are outside this phase's `--scope`, so a backup file cannot be created here. Byte
identity was established instead by (a) re-applying the identical edit text, (b) `git-diff --stat -- lib/mock/seed_data.dart test/watch_reference_sync_test.dart`
returning the same `390 / 88` (474 insertions, 4 deletions) before and after the cycle, and (c) the helper
holding 22 `YogaCatalogRow(` entries again. The `diff`-against-backup check in the brief therefore has no
artefact to run against; recorded as an Open question.

## Phase 2 — suite totals, greps, analyze

- Full suite (`gateway test`, i.e. `flutter test` with the 900 s timeout):
  **`04:39 +6577 ~2 -11: Some tests failed.`** (log `.work/gateway/test-20261105-001205-79348.log`).
  **0 failures were fixed**: all 11 live in four files outside this phase's `--scope`, and the runner denies
  the edit (`Permission denied because no interactive user response was available`), so the plan's
  "scope widens by that one file" rule could not be exercised. This is a BOUNDED, BLOCKED item, not a pass.
- The 11 failures are all the seeded catalog crossing three exercise batches (300 rows → 311 in Phase 1 →
  322 in this phase; 100 rows per batch, so the fourth batch appears with Phase 1, not here):
  - `test/watch_transport_test.dart` S-003 (`types.skip(3)` expects
    `['exercises_down','exercises_down','exercises_down','bests_down']`, gets a fourth `exercises_down`).
  - `test/watch_sync_changed_only_test.dart` S-9201 and S-9209 (`transport.batchIndices` expects `[0, 1, 2]`,
    gets `[0, 1, 2, 3]`).
  - `test/watch_sync_request_handler_test.dart` S-3851, S-3852, S-7101, S-7104, S-7105, S-8310, S-87a-7 (same
    `[0, 1, 2]` pin, and S-7101's ordered frame list ends `bests_down` after three `exercises_down`).
    Note `test/watch_reference_sync_test.dart` S-3858 was already re-baselined to 4 in Phase 1; these files were
    not, and Phase 1 did not run the full suite, so the pins were already stale before this phase.
  - `test/pr7_exercise_details_view_test.dart` S-003 (`Bad state: No element` out of
    `dragUntilVisible` at line 239): the picker is alphabetical and `Custom Sparse Exercise` now sits further
    down, past `dragUntilVisible`'s default `maxIteration: 50`. Adding the seven new names that sort before it
    (Boat, Bridge, Camel, Crescent, and Phase 1's Chair/Cobra) moves the row ~6 rows deeper.
  The minimal in-place fixes (one line each, not applied here) are `[0, 1, 2]` → `[0, 1, 2, 3]`, the
  `types.skip(3)` list gaining a fourth `exercises_down`, and `maxIteration: 200` on the `dragUntilVisible`.
- `grep -c "disciplineId: 'discipline-yoga'" lib/mock/seed_data.dart` → **24** (13 after Phase 1 + rows 12–22).
- `flutter analyze` (gateway `lint`, run once): **`181 issues found. (ran in 3.3s)`** — equal to the Phase 1
  baseline, so ≤ baseline holds.
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing.

## Phase 2 — unpredicted files

The four stale-pin files were fixed by the governor (lead) after the builder run, as closed one-line fixes,
each backup-copied to `.work/2026-11-05-119-yoga-catalog/backup-*` first, then re-run green:

- `test/watch_transport_test.dart` S-003: `types.skip(3)`'s ordered list gains a fourth `exercises_down`
  before `bests_down`.
- `test/watch_sync_changed_only_test.dart` S-9201, S-9209: `transport.batchIndices` expects `[0, 1, 2, 3]`.
- `test/watch_sync_request_handler_test.dart` S-3851 (two assertions), S-3852, S-7101 (two assertions),
  S-7104, S-7105, S-8310, S-87a-7: same `[0, 1, 2, 3]` pin and the two ordered lists; S-3851's reason updated
  to "four batches".
- `test/pr7_exercise_details_view_test.dart` S-003: `maxIteration: 200` added to the `dragUntilVisible`
  (`Custom Sparse Exercise` sits ~6 rows deeper once Boat/Bridge/Camel/Crescent sort before it).

Post-fix runs, observed:
- The four files together → `00:02 +139: All tests passed!`
- The full suite (`flutter test`, 900 s window; 04:36 wall) → **`+6588 ~2 -0: All tests passed!`**
  (the log is saved at `.work/2026-11-05-119-yoga-catalog/full-suite-p2.log`.)

These were already stale before Phase 2 began (Phase 1's 300→311 changed nothing they pin; Phase 2's rows
crossed 350 = a fourth batch — which is why `watch_reference_sync_test.dart` S-3858 was re-baselined in
Phase 1 while the transport pins still said three).

## Phase 3A — scenarios, mapper pins, SQL move (`crew-builder-data`)

| Step | Files run | Observed |
|---|---|---|
| item 1, S-19303 (three tests in a new group) | `test/muscle_filter_test.dart` | `00:00 +28: All tests passed!` (14 per harness, Mock + Hive) |
| item 2, S-19304 / S-19305 / S-19307 (new file, plain `test()` over `harnessFactories`) | `test/yoga_catalog_refresh_test.dart` | `00:00 +6: All tests passed!` — green on the first run, as predicted |
| item 3, the mapper pins | `test/health_platform_mapper_test.dart` | RED: `00:00 +0 -1` — `Member not found: 'yoga'` at `:115:37`, `:122:50`, `:126:50` |
| item 3, the five rig fixtures (new file) | `test/health_yoga_kind_test.dart` | RED: `00:00 +0 -1` — `Member not found: 'yoga'` at `:139:57`, `:184:57` |
| item 5, the SQL move | `test/db_seed_test.dart` | `00:00 +12: All tests passed!` (unchanged count: the file pins no exercise count) |
| item 6, Done Criteria files that are green now | `test/muscle_filter_test.dart test/yoga_catalog_refresh_test.dart test/yoga_catalog_test.dart test/ui_standards_contract_test.dart` | `00:01 +101: All tests passed!` (log `.work/gateway/test-20261105-003151-5200.log`) |

Why the four green files are green: the tree already carries Phases 1–2, so the 24 Yoga rows, the two moves and
`bundledCatalogVersion = 17` are in place and the refresh already skips touched rows. The red step that proves
S-19303/S-19304/S-19305/S-19307 (version 17 → 16 and the seed rows/unions reverted) is Phase 3A item 4, which
belongs to the governor — no builder edit can stage it.

The S-19311 red is the whole of it: `HealthActivityKind` has no `yoga` member, so the two mapper pins and
fixtures A and E cannot compile (`test/health_platform_mapper_test.dart:115`, `:122`, `:126`;
`test/health_yoga_kind_test.dart:139`, `:184`). The rig's fixture B (mixed), C (an exercised id the store no
longer holds) and D (empty) need no new symbol and answer `HealthActivityKind.flexibility` today, so they
would already pass — `M10` in the review's mutation list is what they guard once the branch exists.

`flutter analyze` (gateway `lint`, run once): **`186 issues found. (ran in 3.6s)`** — the Phase 2 baseline of
181 plus exactly the 5 `undefined_enum_constant` errors of the intentional red above. It returns to 181 when
the governor lands `HealthActivityKind.yoga`; the over-baseline count is the red, not a new style issue.
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing.

`git-diff --stat -- test/muscle_filter_test.dart test/health_platform_mapper_test.dart scripts/sqlite_seed.sql`

```
 scripts/sqlite_seed.sql               |  27 ++-
 test/health_platform_mapper_test.dart |  22 +++
 test/muscle_filter_test.dart          | 303 ++++++++++++++++++++++++++++++++++
 3 files changed, 344 insertions(+), 8 deletions(-)
```

The SQL move (D-19312): the stretching block's `Pigeon Pose` and `Child''s Pose` unions are gone, and a new
block after it carries them verbatim under `WHERE d.key='yoga'`:

```sql
-- Yoga poses — the two rows this catalog keeps under the Yoga discipline.
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Pigeon Pose' AS name,
    'Deep stretch for the glutes, piriformis, and outer hip, with the front leg folded under the torso and the rear leg extended straight back.' AS description,
    json_array('Front shin angled across the body, rear leg extended straight back with the top of the foot down.','Square the hips as much as possible — use a block under the front-side hip if it floats.','Walk the hands forward to deepen; keep the breath steady.') AS how_to_steps
  UNION ALL
  SELECT 'Child''s Pose',
    'Kneeling rest position with hips sitting back onto the heels and arms extended forward. Gentle stretch for the low back, lats, and shoulders.',
    json_array('Knees wide, big toes together, hips sinking back to the heels.','Reach the arms long in front, chest heavy toward the floor.','Breathe into the low back.')
) e
WHERE d.key='yoga'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);
```

The `app_discipline` row for `yoga` already exists (`scripts/sqlite_seed.sql:325`), so the block's `JOIN` finds
its discipline; the statement is idempotent through the same `NOT EXISTS` name guard as every other block.


