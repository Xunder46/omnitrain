# Review: 115a strength catalog gaps · Phases 1, 2A, 2B, 3, 4 · 50a95486..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: 6446 passed / 0 failed / 2 skipped (`+6446 ~2: All tests passed!`, full `flutter test`, 2026-11-04)
Diff vs Predicted Files: conforms — 17 files, all named by Phases 1–4 (evidence file is untracked, so absent from `git diff`). Boundary check `git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/data/repositories lib/watch watch lib/core/constants/data_version.dart scripts/sqlite_schema.sql` printed nothing.

## Findings
1. [Minor] `lib/mock/seed_data.dart` (exercise-cable-rear-delt-fly howToSteps, step 1) — "Stand side-on to a low pulley … pull the handle out and back … until your arm is level with your shoulder": with the pulley low and the lifter upright, the arm raised to shoulder height is loaded mostly as a lateral raise (side delt); the rear-delt-biased single-arm setup is a shoulder-height pulley (or a hinged torso). A user following the steps trains a different primary muscle than the row's P `rear-delts` claims. Fix: one line — "Stand side-on to a pulley set at shoulder height" (or add a slight hinge). No test pins the wording beyond non-empty. Guard: none needed beyond S-18909's text checks.
2. [Minor] `docs/plans/…plan.md` `## Assumption Log` — empty after a five-phase build, while the evidence file records five deviations (lead-made version edit, four-run row build, extra `constants_reference.md` sentence, 800×1400→1800 surface, S-18908 skipped). Rule each entry there (ratify/revert/escalate) or move the notes into the log. Fix: copy the five notes into the plan's Assumption Log with a ruling each.

## Answers to the brief's five questions
1. No file outside the Predicted Files; no production file beyond the four named. Boundary check output: empty (exit 0).
2. All 28 descriptions and step lists read against D-18907. Cable Crossover says high to low, Low-to-High Cable Fly says low to high; no brand names; 3–4 imperative steps each; nothing unsafe. One imprecision: finding 1 (Cable Rear Delt Fly pulley height). Everything else anatomically correct (side-lying ER forearm path, internal rotation across the body, Zottman supinated-up/pronated-down, reverse curl overhand, clamshell/lateral-walk band placement, leg-curl pad positions, pec-deck/reverse-pec-deck body position).
3. New-row tagging: no clear errors. Reverse Curl P brachialis+forearms / S biceps, shrug S forearms (grip), diamond push-up S abs, band pull-apart S traps+rotator-cuff — all defensible; the three re-tags match D-18902 exactly.
4. No stale reader. `grep` over `lib`+`test` for `hasLength(24)|24 entries|17 muscles|24 groups|hasLength(23)|hasLength(178)|equals(13)|Version(12)|setCatalogVersion(12)|hasLength(252)|hasLength(188)` → only `test/tibialis_muscle_refresh_test.dart:140,258,307` `setCatalogVersion(12)`, the deliberate staging literal the plan says to keep. Re-tagged ids outside seed appear only as ids in `demo_routines_seed.dart` and as v13 fixtures/assertions in the new tests. No catalog-version-13 hard-code remains.
5. Docs state what the code does. `catalog_refresh_service.dart:53-68` runs exactly six legs (exercises, capabilities, muscle groups, exercise-muscle links, food catalog, demo routines) — no equipment, discipline or category leg, so `constants_reference.md` ("equipment links, disciplines and categories are written at first install only") and `db_integration.md` are true; `sampleDisciplines`/`sampleSportCategories` exist in the seed and are not refreshed. Every test name the docs cite exists: `27 entries: 5 regions, 20 muscles, 2 standalone` (`muscle_taxonomy_test.dart:27`), `S-18906 a v13 install refreshes to v14` / `S-18907 a user-edited row keeps its muscles` (`strength_catalog_refresh_test.dart:239,481`), `S-9 … seeds the 27 groups the taxonomy defines` (`db_seed_test.dart:418`).

## Assumption Log rulings
Plan log empty — see finding 2. The five evidence-file deviations were checked against the diff and are all real and consistent with the code; none needs revert.

## Scenario coverage
- S-18901 → `test/muscle_taxonomy_test.dart` · `S-18901: Brachialis, Rotator cuff and Abductors sit in their regions`
- S-18902 → `test/muscle_taxonomy_test.dart` · `S-18902: storage rules with the new muscles`
- S-18903 → `test/muscle_display_test.dart` · `S-18903: Brachialis, Rotator cuff and Abductors sit in the dropdown where the taxonomy puts them`
- S-18904 → `test/catalog_referential_integrity_test.dart` · re-tag list assertions and the main/assist sets inside the approved-rows test (map length 206)
- S-18905 → `test/muscle_filter_test.dart` · `S-18905 the new muscles, their regions and the re-tags` (Mock + Hive via harnessFactories)
- S-18906 → `test/strength_catalog_refresh_test.dart` · `S-18906 a v13 install refreshes to v14` (Mock + Hive; Hive-only equipment pin present)
- S-18907 → `test/strength_catalog_refresh_test.dart` · `S-18907 a user-edited row keeps its muscles` (Mock + Hive)
- S-18909 → `test/strength_catalog_gaps_test.dart` · `S-18909 new strength rows` (28 rows, uniqueness, id order, sizes 280/280/216/206)
- S-18910 → `test/db_seed_test.dart` · `S-9 app_muscle_group carries parent_id and seeds the 27 groups the taxonomy defines`
- S-18911 → `test/muscle_filter_picker_test.dart` · `_displayOrder`/`_indentedOrder` order, stacking and indentation checks (28 rows, 20 indented, surface 800×1800)
- S-18912 → `test/muscle_picker_test.dart` · `S-18912 the new muscles sit last in their region rows`, `S-18912 whole arms then brachialis keeps just brachialis`

No scenario is missing its test. The plan has no `## Docs delta` table, so no delta block is due; the three doc edits Phase 4 predicts are all present and true.
