# Review: 116 catalog delivery · independent review · 27a137bb..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · nit 1 · tests: not run (brief says the lead runs the full suite; established: whole suite and every named test file pass)
Diff vs Predicted Files: conforms — 17 files, all inside the three phases' Predicted Files lists; boundary `git-diff --stat` over lib/features lib/widgets lib/state lib/watch watch lib/mock lib/data/models data_version.dart sqlite_seed.sql prints nothing; hive-import grep over lib/state lib/features lib/widgets lib/core prints nothing.

## Findings
1. [Major] test/catalog_reference_refresh_test.dart:205 (`_driftCases`) — no fixture drifts `UnitModel.key`. The main S-19104 test drifts `unit-kg`'s name and the timestamp-only row `unit-lbs` keeps every compared field equal, so a dropped `a.key != b.key` in `_unitDiffers` (`catalog_refresh_service.dart:470`) lets a unit whose key drifted stay wrong with no test failing. The lead's mutation evidence ("every compared field mutant turned red") is consistent with substitution mutants (caught by the S-19105(b)/S-19107(b) no-write counts), not with a pure drop. Fix: add `const _Drift('UnitModel', 'key', 'unit-lbs', 'key', 'drifted_key')` to `_driftCases`. Guard: the new per-field drift test fails while the comparison is missing.
2. [Minor] lib/core/services/catalog_refresh_service.dart:81-83 (class comment) and docs/db_integration.md:112-113 — both say rows whose id is not bundled are "never read or written". `_refreshTags` (`catalog_refresh_service.dart:117-127`) reads every stored tag via `getTags()`, including ids the bundle does not carry, to build its lookup map; it never writes them, and D-19107 names `getTags` as the read, but the absolute sentence is false for tags. Fix: soften both sentences to "never written" (or "never modified"), or note that the tags leg reads the stored list only to look up bundled ids.
3. [Nit] lib/core/services/catalog_refresh_service.dart:117 — `_refreshTags` materialises the full stored-tag map on every refresh run. Harmless at seed scale (a few dozen tags); noted for the cost question, no change needed.

## Assumption Log rulings
- The plan's `## Assumption Log` section is empty; no open entries to rule. The two derived decisions flagged vetoable in the ledger are ruled here: D-19105 (`deletedAtMs` on categories rewritten to the bundled value) — ratify, guarded by S-19104 (`category-recovery` `deletedAtMs` null again); D-19106 (leg order) — ratify, guarded by S-19106 (failure lands on climbing, `exercise-sit-up` still absent).

## Scenario coverage
S-19101 -> test/reference_data_upsert_test.dart · 5 tests over both harnesses (round-trip, rename, kinds order/copy, Hive restart, Mock delete hook + ArgumentError)
S-19102 -> test/catalog_reference_refresh_test.dart · 'S-19102 a v15 install missing reference rows refreshes to v16' (both harnesses)
S-19103 -> same file · 'S-19103 user rows that share a name or key stay byte-identical' (both harnesses)
S-19104 -> same file · 'S-19104 app-owned drift is corrected, timestamps and order are not' + 12 per-field drift tests (one per remaining compared field except UnitModel.key — finding 1)
S-19105 -> same file · 'S-19105 (a) a second refresh leaves every reference row unchanged' (both) + 'S-19105 (b) Mock: a second run writes no reference row'
S-19106 -> same file · 'S-19106 Mock: an interrupted refresh keeps version 15 and the next launch finishes'
S-19107 -> same file · 'S-19107 (a) a fresh install is unaffected by the refresh' (both) + 'S-19107 (b) Mock: a fresh install writes no reference row'
S-19108 -> test/catalog_delivery_contract_test.dart · tests 1-5 (parse sanity via 24-count + sampleExercises/sampleConsumedFoods contains; stale-row; reason; getter/id-set equality; uninitialized-Mock delivery with present-before check and equipment/food-group emptiness)

## Answers to the five questions
1. No new leg writes an id outside the bundle, deletes anything, or compares a timestamp: all six legs iterate `_source` members only, the differs helpers compare exactly the D-19102 fields (`deletedAtMs` per D-19105), and `setCatalogVersion` runs after every leg (`catalog_refresh_service.dart:60-77`), so an exception leaves the stored version unchanged (S-19106 proves it). The one read outside the bundle is `_refreshTags`'s `getTags()` map (finding 2).
2. Parity holds for all seven members: absent kinds read `[]` on both (`_asStringList` hive_workout_repository.dart:908-911; Mock `?? const []`), both copy on write (`List<String>.from`), both upsert replace in place (`put(id, toMap())` vs map assignment), S-19101 runs every case on both harnesses plus a Hive restart. `deleteReferenceRowForTest` is `@visibleForTesting` on Mock (mock_workout_repository.dart:1029); the only lib importer of Mock is the debug entry `lib/state/watch/live_session_mirror_debug_main.dart`, which does not call it.
3. `catalog_version.dart` (16, both comment edits) and the three docs are true against the code and cite tests that exist: S-19102/S-19103/S-19106 names match `catalog_reference_refresh_test.dart`, `catalog_delivery_contract_test.dart` exists, `S-18906` exists in `strength_catalog_refresh_test.dart:3`. Residue sweep over docs/lib/scripts (excluding docs/plans) finds no sentence still claiming disciplines/categories are first-install only — only equipment/food-group lines. No MISSING row in `## Docs delta`; all five rows are applied in the diff.
4. None of the five contract tests passes vacuously: the parser is pinned by the 24-count plus `sampleExercises`/`sampleConsumedFoods` contains-checks; check 4 compares real non-empty id sets; check 5 asserts every id absent before the refresh, so a silent leg cannot pass. The EXCLUDED list is honest: no refresh leg touches any excluded member (refresh() runs exactly 12 legs, read in full); equipment and food groups are probed empty by check 5; food groups are user-visible reference data but excluded with a written reason and an owner follow-up (below); orphan template rows are not user-visible (their four parent templates are created by nothing); dev fixtures and consumed foods are never/user data.
5. Both boundary checks print nothing (see header).

## Docs delta
- docs/db_integration.md MODIFIED -> applied
- docs/db_integration.md ADDED (contract-test sentence) -> applied
- docs/constants_reference.md MODIFIED (row 16 + Notes list) -> applied
- docs/constants_reference.md MODIFIED (not-delivered sentence) -> applied
- docs/state_management/services_and_utils.md ADDED -> applied
- Doc edits the table does not name: `scripts/sqlite_schema.sql:1631-1635` comment (Phase 3 item 5, applied) and the `lib/core/constants/catalog_version.dart:3-7,63-68` doc-comment edits (D-19110, applied).

## Owner decisions
- Food-group delivery: a deleted default group would come back; needs a touched-entry marker first (priced follow-up, ~80 lines).
- Equipment delivery stays excluded by the 115a/115b owner decision; carried follow-up (~100-150 lines).
- Orphan template rows (`tseg-*`/`teff-*`/`ttar-*` of the four retired template ids) remain on existing phones; a migration could remove them (invisible today).
- Ratify or veto D-19105 and D-19106 (both derived, vetoable; guarded by S-19104 and S-19106).
- Pre-existing, not this diff: `docs/data_models.md:412` says the bundled food seed "stays at its shipped values", but `_refreshFoodCatalog` updates untouched bundled foods (already priced in the plan's Notes).
