# Review: 115b strength catalog gaps · Phases 1, 2A, 2B, 3 · 7631ea34..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 0 · minor 2 · tests: 6485 passed / 0 failed / 2 skipped (`+6485 ~2: All tests passed!`, full `flutter test` via gateway, 06:32)
Diff vs Predicted Files: outside: `lib/widgets/layout/omni_back_header.dart`, `test/omni_back_header_centering_test.dart`, `docs/plans/2026-11-04-115-strength-catalog-gaps-series.md`

## Findings

1. [Blocker] `lib/widgets/layout/omni_back_header.dart:38-52` (+ new `test/omni_back_header_centering_test.dart`) — a production UI change (pinning iOS `centerTitle`) and its test sit in this working tree but appear in no Predicted Files line of Phases 1–3 and are unrelated to the catalog (a Stats title-centering fix). Committed with 115b it breaks the plan's Diff-boundary invariant and mixes two units in one PR. Fix: the governor splits these two files out into their own unit/PR, or confirms they are another in-flight agent's work and excludes them from this diff. Guard: the Phase 4 diff-boundary check.
2. [Minor] `docs/plans/2026-11-04-115-strength-catalog-gaps-series.md:16` — one-line pointer update ("not planned" → the 115b plan folder, Q1 default noted). Not in any Predicted Files line; harmless series bookkeeping, listed so the governor knows it rides in this diff.
3. [Minor] `lib/mock/seed_data.dart:4699` — Leg Press Calf Raise step 2, "Keep your knees straight but not locked as you press the platform away", reads as holding straight knees while pressing away from the bent-knee start of step 1; the intent is "press the platform away until your knees are straight but not locked". D-19003's requirement is present and the step order (sit → extend → calf raise) is correct; wording only. Fix: one-line reword by the builder.

## Answers to the brief's five questions

1. Diff-boundary check output (`git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/data/repositories lib/watch watch lib/core/constants/data_version.dart`): `lib/widgets/layout/omni_back_header.dart | 8 ++++++++` — one file, 8 insertions (finding 1). No other boundary file changed; `lib/core/constants/data_version.dart` untouched. Production files of the plan: exactly the four (`seed_data.dart`, `catalog_version.dart`, `sqlite_seed.sql`, `sqlite_schema.sql`); the seed diff is pure additions (20 `Exercise(` rows, 2 `Equipment(` rows, 20 entries in each of the three maps), and `sqlite_schema.sql` changes comment lines only.
2. All 20 descriptions and step lists read correct against D-19003: Dead Bug and Bird Dog say the limbs "reach out and come back on every rep"; Hanging Knee Raise keeps the knees bent and names itself "An easier step before the Hanging Leg Raise"; Rack Pull starts "on safety pins or blocks at about knee height" (description and step 1); Push Press has the "short knee dip and leg drive" (description and step 2); Trap-Bar Deadlift says "Stand inside the bar" (step 1); both sled rows end "Time- or distance-based."; no brand names. Single-Leg Hip Thrust order is correct (sit with shoulders on bench and one foot planted → lift the other leg → drive through the planted foot). The only wording quibble is Leg Press Calf Raise step 2 (finding 3).
3. Muscle tagging: all 20 rows in `seed_data.dart:5401-5420` match the New-row table exactly (P/S roles, ids, order); no clear anatomical error. Push Press triceps/side-delts/quads as assists, Bird Dog main on Lower back and Abs, Curtsy Lunge assisting Abductors, Lateral Lunge assisting Adductors, sleds assisting Calves — all as decided.
4. No stale reader. Grep over `lib` and `test` for `hasLength(206|216|280|300|236)`, `252 +`, `178 +`, `188 +`, `equals(14)`, `Version(14)`, `hasLength(10)`, `252 seeded`: the only hits are the new values (`hasLength(226)` at `catalog_referential_integrity_test.dart:205,270`; `252 + added` formulas at `strength_catalog_gaps_test.dart:543-546`), the staging literals `setCatalogVersion(14)` in the new v15 test (`:166,346`, per plan), `greaterThanOrEqualTo(14)` with a 115a reason string at `strength_catalog_refresh_test.dart:578` (still true at 15; line not touched by this diff), and a historical 115a comment at `catalog_referential_integrity_test.dart:437`. No hard-coded 280/252-as-total, 206, or equipment count 10 remains.
5. The three doc edits state only what the code does. `docs/db_integration.md:139-145`: the version-15 sentence cites `S-19006 a v14 install refreshes to v15`, `S-19007 a renamed touched row and near-twins keep their own` and `S-19008 a new install knows the equipment` — all three titles exist verbatim in `test/strength_catalog_v15_refresh_test.dart:135,281,437`, and the claims (20 rows added; edited/copied/same-name/renamed rows never rewritten; equipment new-install only) are each asserted by the named test. `docs/constants_reference.md:575` says `15`, matching `catalog_version.dart:62`. `docs/state_management/watch_reference_data.md:22` applies D-19011 ("300 seeded exercises … tens of kilobytes").

## Scenario coverage

- S-19001 → `test/strength_catalog_gaps_test.dart` group `S-19001 new 115b rows` (20 per-row tests + shared guards over both tables: name uniqueness over the whole seed, id order, sizes 300/300/236/226)
- S-19002 → same file, group `S-19002 the seed equipment rows` (3 tests)
- S-19003 → `test/db_seed_test.dart` `S-19003 app_equipment carries the 12 equipment names the seed defines`
- S-19004 → `test/catalog_referential_integrity_test.dart` (226 at both sites; main/assisting Calves, Lower back, region and 115a sets)
- S-19005 → `test/muscle_filter_test.dart` group `S-19005 the new rows and their main muscles` (Mock + Hive)
- S-19006 → `test/strength_catalog_v15_refresh_test.dart` `S-19006 a v14 install refreshes to v15` (Mock + Hive)
- S-19007 → same file `S-19007 a renamed touched row and near-twins keep their own` (Mock + Hive)
- S-19008 → same file `S-19008 a new install knows the equipment` and `S-19008(b) a link to a missing equipment row is skipped` (Hive-only, guard as planned)

No scenario of Phases 1–3 lacks a test that would fail without the change; the evidence file records eight mutations, all red on the named tests.

## Assumption Log rulings

- Q1 sled logging (rows 19–20 carry the Farmer's Carry capability set): ratified — the plan records it as the default for an open owner question; the brief forbids flagging the choice. The owner must still answer before merge; changing to (b) is two capability lines plus two table rows.
- Equipment deliberately not delivered by the refresh: ratified — pinned by the Hive-only assertions in S-19006 and S-19008(b).
- `catalog_version.dart` edited by the lead (outside the data builder's ceiling): ratified — recorded in the evidence file's deviations.
- The plan's sweep expected 0 hits in `docs/data_models.md` but found 2 (the Traps muscle): ratified — both hits are the muscle name, unrelated to equipment.
