# 119 yoga catalog — architect validation report

Validated 2026-11-05 against the working tree (`claude_develop` + plan 117 uncommitted). The plan was read in full;
every number below was re-derived this run with greps over `lib/mock/seed_data.dart` and the named test files.
Plan edits are wording/number/anchor fixes only; no decision id, scenario fixture, phase owner or scope was changed.

## 1. Number re-derivations

| Number | Claim | Re-derived this run | Result |
|---|---|---|---|
| 300 | `SeedData.sampleExercises` Exercise( entries | `grep -c "Exercise\("` `lib/mock/seed_data.dart` → **300** (the list at `:378` is the file's only `Exercise(` source; the three maps and `MetricApplicability` contain none) | PASS |
| 226 | `exerciseMuscleLinks` entries | `grep -c "_muscles\(primary:"` → **226** (every link entry is one `_muscles(...)` line; map spans `:5194`–`:5421`) | PASS |
| 236 | `exerciseEquipmentRelationships` entries | 185 non-empty (`grep -c "': \['equipment-"`) + 51 empty (`grep -c "': \[\],"`, all 51 line-numbered inside `:5437`–`:5684`) = **236** | PASS |
| 300 | `exerciseCapabilityRelationships` entries | 288 single-line (`grep -c "': \['"`) + 12 multi-line (`grep -c "': \[$"` — lists wrapped over 5–6 lines, e.g. `exercise-concentration-curl`) = **300**; map spans `:5689`–`:6092` | PASS |
| 46 | `['hold', 'time', 'sets']` occurrences | `grep -c "\['hold', 'time', 'sets'\]"` → **46** | PASS |
| 46th = Plate Pinch Hold, not an Isometric-Holds/Stretching row | D-19303's "45 rows + the 46th" wording | `exercise-plate-pinch-hold` at `seed_data.dart:3972` carries `disciplineId: 'discipline-bodybuilding'` (`:3976`) — so 45 holds/stretch rows + 1 bodybuilding row = 46. Wording is correct as written | PASS |
| Cross-check | 762 = 226 + 236 + 300 | `grep -c "^    'exercise-"` → **762** | PASS |
| Sizes after this PR alone | 322 / 322 / 258 / 247 | 300+22, 300+22, 236+22, 226+21 (Savasana has no link entry) — arithmetic consistent with the re-derived bases | PASS |
| `hasLength(3)` at `watch_reference_sync_test.dart:473` is synthetic | S-3843, 250-row fixture | `:473` sits in the S-3843 test: reason `"S-3843 250 exercises are three batches of at most 100"`, `payload['totalCount'] == 250`, ids `ex-000…` — synthetic, does not move | PASS |
| Only `:594` S-3858 moves | S-3858 `hasLength(3)` → 4 | `:594` is in `test('S-3858 the first batch of the seeded catalog stays under the frame budget')`, reason `"the seeded catalog is more than two batches"` — the real-catalog assertion; moves to 4 per D-19309 | PASS |
| P today = 16 | `catalog_version.dart:70` | `const int bundledCatalogVersion = 16;` at `:70` | PASS |
| `currentDataVersion = 17` untouched | `data_version.dart:36` | `const int currentDataVersion = 17;` at `:36` | PASS |

Note on the brief's token "92": neither the plan nor `watch_reference_sync_test.dart` contains a meaningful "92"
tied to `:473`. Read as a typo for **S-3843** (the synthetic test at that line), the claim is true as re-derived
above. Listed under Open questions.

## 2. Anchor spot-checks (two findings quoted per check)

1. **The 22 ids exist nowhere.** `grep "'exercise-mountain-pose'"` over `lib test watch scripts` → *No matches
   found*; `grep "'exercise-savasana'"` → *No matches found*; third spot-check `grep "'exercise-camel-pose'"` →
   *No matches found*. (Plan D-19301 claim holds.)
2. **No Hive import outside the data layer.** `grep -rln "import .*hive_workout_repository"` over
   `lib/state lib/features lib/widgets lib/core` → *No matches found*. (Phase 3B Done Criteria grep will keep
   printing nothing.)
3. **`discipline-yoga` unread outside the seed.** `grep -n "discipline-yoga"` over `lib test watch` → exactly one
   hit: `lib/mock/seed_data.dart:321: id: 'discipline-yoga',` (the discipline row itself). Zero in `test/` and
   `watch/`. (Impact-table row 1 holds.)
4. **No screen shows equipment.** `grep -n "getExerciseEquipment"` over `lib/` → three hits, all repository:
   `workout_repository.dart:148` (interface), `mock_workout_repository.dart:1048`, `hive_workout_repository.dart:1818`.
   Repo-wide, the only other callers are tests (`muscle_filter_test.dart`, `strength_catalog_v15_refresh_test.dart`,
   `strength_catalog_refresh_test.dart`) — **no health/weight or screen caller exists in `lib/`**. The brief expected
   "repository + health/weight only"; the truth is repository-only, which is strictly stronger: the claim
   "nothing reads equipment on screen" holds.
5. **Guard sites** (D-19309 rewrite targets, confirmed at the claimed lines): `equals(16)` exactly at
   `catalog_reference_refresh_test.dart:500,501,970,979,1003,1124` (the four `data_migration_test.dart` `equals(16)`
   hits at `:564,566,748,750` are data-version migration pins — correctly out of scope); `hasLength(226)` at
   `catalog_referential_integrity_test.dart:205,270`; assisting-Calves set at `:344-345` (`exercise-nordic-curl`,
   `exercise-wall-sit`, …); "catalog sizes" test at `strength_catalog_gaps_test.dart:541` with `252 + added` at
   `:543-544`.
6. **Plumbing anchors**: `_stageMissing` at `catalog_reference_refresh_test.dart:71`; Mock
   `deleteReferenceRowForTest:1021`, `setCatalogVersion:1909`, `markSeedEntryTouched:1919`;
   `ExerciseLibraryService.copyAsCustom` at `exercise_library_service.dart:236`; `_Rig` at
   `health_platform_test.dart:140`; `mapModalityToActivityKind(session.modality)` at `health_sync_service.dart:82`;
   `enum HealthActivityKind` at `health_constants.dart:37`. All as the plan cites.
7. **Docs markers** (Docs delta old markers, copied from the files today): `watch_reference_data.md:22`
   "a phone with 300 seeded exercises would send tens" ✓; `constants_reference.md:575`
   `| \`bundledCatalogVersion\` | \`16\` | …` ✓; `db_integration.md` version history ends at the version-`15`
   sentence (`:152`) ✓ — "after the last Catalog version `N` adds sentence" is actionable.

## 3. Plan edits made

1. **Phase 3 split into Phase 3A + Phase 3B** (it had 10 items; the rule is ≤ 8). 3A = items 1–5 (S-19303,
   S-19304/05/07, S-19311, red→green, SQL move) with its own Done Criteria and Predicted Files; 3B = the four
   Docs-delta rows as items 1–4, residue sweep item 5, full-suite item 6, with its own Done Criteria and Predicted
   Files. Same owner (`@dba · crew-builder-data`), same scope, serial. Dependency graph and Progress line updated
   (`1 → 2 → 3A → 3B → 4`); impact-table "Phase 3" guards now say "Phase 3B"; Notes scope-budget line carries a
   parenthetical recording the split.
2. **Docs delta completed**: added row `docs/constants_reference.md | MODIFIED | \`conditioning\`, \`other\`) |
   \`conditioning\`, \`yoga\`, \`other\`) | D-19313` — the `HealthActivityKind` vocabulary row at
   `constants_reference.md:271` enumerates the kinds without `yoga`; D-19313 makes it false. Phase 3B item 3
   implements it (same file as item 2, so no new file). No other doc outside `docs/plans|history|releases` is made
   false: `services_and_utils.md:98-101` (mapper description) and `watch_sensors.md:130` (wrist path) stay true;
   `modality_tracking.md:39` "(planks, yoga, stretching)" stays true.
3. **SQL Yoga-block correction** (anchor fix; the lead's brief asserted a Yoga block exists — it does not):
   `grep -n "WHERE d.key" scripts/sqlite_seed.sql` enumerates the exercise blocks `:421`–`:2504`
   (running, cycling, rowing, swimming, walking, machine_cardio, bodybuilding, boxing, isometric_holds `:1973`,
   stretching `:2068`, bjj … climbing) and there is **no** `WHERE d.key='yoga'` block; the only yoga hits are the
   discipline INSERT at `:325-327` and a comment at `:46`. D-19312, D-19308, the impact-table SQL row and Phase 3A
   item 5 now say the move **creates** a new Yoga exercise INSERT block carrying the two unions verbatim
   (`Pigeon Pose` at `:2004`, `Child''s Pose` at `:2036`, both inside the stretching block) and removes them from
   the stretching block. The decision (move both rows to Yoga in the SQL) is unchanged; only the mechanical
   description now matches the file.
4. **`S-19312` → `D-19312`** (7 occurrences: A2, A5, S-19303 body, S-19304 body ×3, Phase 3A item 2). No scenario
   S-19312 is defined in the Scenarios section; every reference is to the decision's assertions.
5. **Phase 2 Done Criteria grep count 22 → 24**: `disciplineId: 'discipline-yoga'` in `seed_data.dart` is 0 today
   (re-derived); after Phase 1 it is 13 (11 new + 2 moves, as Phase 1 already says), after Phase 2 it is 13 + 11 = 24.
6. **Residue-sweep piped grep rewritten as one command**: `grep -rn "300 seeded" docs | grep -v …` →
   `grep -rn --exclude-dir=plans --exclude-dir=history --exclude-dir=releases "300 seeded" docs` → 0 (single
   grep, gateway/tool-expressible).
7. **File paths added to process items** that lacked them: Phase 1 item 6, Phase 2 item 5, Phase 3A item 4,
   Phase 3B item 6 now name the files they revert/run/record.
8. **READY-TO-PASTE `--scope` lines added** to each phase intro (§5 below).
9. "Intermediate states" note: "docs are stale until Phase 3" → "until Phase 3B".

## 4. Pins / risks

- **Pin (lead ratify): the Phase 3 split** — beyond "tighten wording", but mandated by the ≤ 8-items rule; scope,
  owner and order unchanged. If the lead prefers one Phase 3, merge 3B's items 1–4 back and accept 10 items.
- **Pin (lead ratify): the SQL correction** — D-19312/D-19308's original "moves into the (existing) Yoga block /
  changes only by two discipline_id values" is not what the file shows; the corrected text keeps the decision and
  the db_seed_test gate identical. The git diff of `scripts/sqlite_seed.sql` will read as a new INSERT statement
  plus two removed unions — Phase 3A item 5 and the Phase 4 review already re-check it against `db_seed_test`.
- **Pin: the added docs-delta row** is a new sentence in a file already in scope (constants_reference.md), not new
  scope; flagged for the lead because the seeded table was declared complete.
- **Risk (accepted by the plan, re-stated):** D-19309's S-3858 reason "300 + 22 + plan 118's rows ≤ 400" assumes
  plan 118 adds ≤ 78 rows; plan 118's own docs say 17 rows (317 seeded), so 4 batches holds in either order.
- **Risk: Phase 1 item 2's first run is intended RED** (helper exists, seed rows land in item 3) — left as seeded;
  the brief explicitly endorses this order.
- **Not checked** (outside this run's scope): `.claude/crew.env` `MAX_PARALLEL_WRITERS=2` and `.claude/crew-rules.md`
  (the `.claude/` tree is off-limits); the brief's stated values were used. Phase structure is serial regardless
  (one owner per phase, dependency chain 1 → 2 → 3A → 3B → 4), and the ≤ 3-new-files rule holds per phase
  (Phase 1: helper + yoga test + evidence = 3; Phase 2: 0 new; Phase 3A: refresh test + health test = 2; 3B: 0 new).
- **Not run**: `flutter test` / `flutter analyze` (the builders run them; the brief forbids it here). Baselines are
  Phase 1 item 1's job.

## 5. READY-TO-PASTE `--scope` per phase

- **Phase 1**: `lib/mock/seed_data.dart lib/core/constants/catalog_version.dart test/helpers/yoga_catalog_rows.dart test/yoga_catalog_test.dart test/strength_catalog_gaps_test.dart test/catalog_referential_integrity_test.dart test/watch_reference_sync_test.dart test/catalog_reference_refresh_test.dart "docs/plans/2026-11-05-119-yoga-catalog-plan/*"`
- **Phase 2**: `lib/mock/seed_data.dart test/helpers/yoga_catalog_rows.dart test/watch_reference_sync_test.dart "docs/plans/2026-11-05-119-yoga-catalog-plan/*"` (an unpredicted name/rank-ordered test fix widens by that one file, recorded in the evidence file)
- **Phase 3A**: `test/muscle_filter_test.dart test/yoga_catalog_refresh_test.dart test/health_yoga_kind_test.dart test/health_platform_mapper_test.dart scripts/sqlite_seed.sql "docs/plans/2026-11-05-119-yoga-catalog-plan/*"`
- **Phase 3B**: `docs/db_integration.md docs/constants_reference.md docs/state_management/watch_reference_data.md "docs/plans/2026-11-05-119-yoga-catalog-plan/*"`
- **Phase 4**: `"docs/plans/2026-11-05-119-yoga-catalog-plan/*"` (review file; everything else read-only)

## 6. Done-Criteria command shapes (Copilot-CLI edition check)

Every Done Criteria command is gateway-expressible: `flutter analyze` → gateway `lint`; `flutter test <files>` and
the 900 s full `flutter test` → gateway `test`; `git diff --stat -- …` → gateway git-diff view; the `grep`/`wc`
one-liners run with the grep/file tools (the gateway itself exposes only lint/test/build/codegen/pub-get/format/
swift-test/base-setup + git views + prove-red, per `gateway.sh list`). The one piped grep was rewritten (edit 6).
No `pip`, `xcodebuild`, `xcrun` or other non-expressible command appears. The header's note naming both editions
(`bash .claude/scripts/macos/with-timeout.sh` for Claude agents, gateway for Copilot agents) stays.

## Open questions

1. Brief token "92" (`hasLength(3)` at `watch_reference_sync_test.dart:473`): read as a typo for S-3843; the
   synthetic-fixture claim is confirmed either way (§1). No "92" exists in the plan or that test.
2. The lead's brief fact "the Yoga block is the one whose `WHERE d.key='yoga'`" is contradicted by the file
   (§3 edit 3); the plan now matches the file. If the lead intended a different SQL shape (e.g. reusing the
   isometric_holds UPDATE pattern at `:1842-1905`), the corrected Phase 3A item 5 still describes a valid block.
3. `lib/watch` appears in Phase 4's diff-boundary path list; no such directory was verified to exist (not checked).
   A nonexistent pathspec is harmless to `git diff --stat`; left as written.

## Governor actions

None. Every fix was inside the plan file; no file outside the write scope was needed.
