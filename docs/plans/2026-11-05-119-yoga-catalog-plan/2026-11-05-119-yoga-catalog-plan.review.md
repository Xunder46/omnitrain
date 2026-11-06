# Review: 2026-11-05-119-yoga-catalog · Phases 1–3B · base 24e1a26d..working tree

Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · nit 1 · tests: `+6607 ~2 -0: All tests passed!` (full suite, run by the
lead at Phase 3B — the brief hands the counts over as established; not re-run here). `flutter analyze` 181
(baseline 181); docs-indexing 13/13; db_seed 12/12.
Diff vs Predicted Files: conforms — the 23 changed paths are exactly the plan's predicted files, the plan
folder, and the four stale-pin files the evidence records as the governor's closed one-line fixes
(`watch_transport_test.dart`, `watch_sync_changed_only_test.dart`, `watch_sync_request_handler_test.dart`,
`pr7_exercise_details_view_test.dart`). No plan-117/118 hunk, no allowlist change, no file under
`lib/features|widgets|state|data`, no `data_version.dart` change.

## Findings

1. [Nit] `lib/core/services/health_sync_service.dart:128` — `if (id == null || disciplineById[id] != _yogaDisciplineId)`:
   the `id == null` half of the all-yoga condition has no pinning fixture (S-19311's B pins a non-Yoga
   discipline, C an absent row, D the empty-effort list via the default segment) and is behaviourally
   redundant: `disciplineById[null]` on the `Map<String, String?>` literal returns null, so the lookup half
   already sends a null-id effort to the modality mapping. Dropping the null check changes no behaviour, so
   no test can go red either way. Fix, if wanted: drop `id == null ||` and let the lookup speak, or leave as
   defensive. Guard: none needed (no behaviour to pin).

## Assumption Log rulings

- A-119-1 (moved rows keep every field but `disciplineId`): ratify — the seed rows at `seed_data.dart:2199/:2311`
  carry the same description/steps the SQL unions carry verbatim, and the three maps still hold both ids
  (`:5614/:5622`, `:5894/:5902`, `:6244/:6252`).
- A-119-2 (YOGA in both platform sets): ratify as recorded — the gateway case returns `YOGA` unconditionally
  (`health_platform_gateway_io.dart:70-73`) and the both-platform pin passes
  (`test/health_platform_mapper_test.dart` 'yoga resolves to the YOGA type on both platforms').
- A-119-3 (public `YogaCatalogRow`): ratify — `test/helpers/yoga_catalog_rows.dart` declares the public class.
- A-119-4 (extra `muscle_taxonomy.dart` import): ratify — the helper imports it and uses `MuscleTaxonomy.normalize`.

## Docs delta

- `docs/db_integration.md` ADDED (version-17 paragraph) -> applied; names `S-19304 a version-P install
  refreshes`, `S-19305 a renamed touched row and near-twins keep their own` (both verbatim test names in
  `test/yoga_catalog_refresh_test.dart`), `S-19307`, and `S-19311` in `test/health_yoga_kind_test.dart` —
  all exist; every claim is asserted by the named test.
- `docs/constants_reference.md` MODIFIED (`bundledCatalogVersion` `16`→`17`) -> applied (`:575`).
- `docs/state_management/watch_reference_data.md` MODIFIED ("more than 300 seeded exercises") -> applied (`:22`).
- `docs/constants_reference.md` MODIFIED (`HealthActivityKind` gains `yoga`) -> applied (`:271`, matches the
  enum order in `health_constants.dart`).
- No doc edit outside the table: `grep "300 seeded"` docs → only the edited line; no doc claims a phone pose
  workout records as Flexibility (`Flexibility` hits are the wrist docs and generic type lists, all still true);
  no doc names Pigeon/Child's Pose under Stretching any more.

## Scenario coverage

- S-19301 -> `test/yoga_catalog_test.dart` (per-row conformance, the Yoga set, the moves, name uniqueness, id order)
- S-19302 -> `test/strength_catalog_gaps_test.dart` 'catalog sizes' (+ `yogaCatalogRows` terms),
  `test/catalog_referential_integrity_test.dart` (both `hasLength` sites + assisting-Calves set),
  `test/watch_reference_sync_test.dart` S-3858 `hasLength(4)`, `test/catalog_reference_refresh_test.dart`
  (`equals(bundledCatalogVersion)` / `greaterThanOrEqualTo(16)`)
- S-19303 -> `test/muscle_filter_test.dart` group 'S-19303 the yoga poses in the filters' (3 tests)
- S-19304 / S-19305 / S-19307 -> `test/yoga_catalog_refresh_test.dart` (Mock + Hive)
- S-19306 -> `test/watch_reference_sync_test.dart` 'S-19306 every yoga pose reaches the wrist once, as a hold'
- S-19311 -> `test/health_yoga_kind_test.dart` fixtures A–E + `test/health_platform_mapper_test.dart` 2 pins

## The five brief questions

1. Tagging: all 22 rows match the New-row table cell for cell (seed `:4756-:5061`, links `:5742-:5762`,
   equipment `:6027-:6048`, caps `:6456-:6477`; Savasana has no links entry). Near-twin sentences present:
   Bridge Pose "slide the arms under the body" + "chest toward the chin"; Low Lunge "back knee down" + "arms
   overhead"; Crescent Lunge "lift the back heel … ball of that foot" + "arms overhead". Other-side step present
   in eagle, low lunge, crescent lunge, reclined twist, half moon, tree (and the four one-sided rows 1–11).
2. Moved rows: only `disciplineId` differs; SQL carries the two unions verbatim under `WHERE d.key='yoga'`
   (`sqlite_seed.sql:2066-2084`) with the `NOT EXISTS` guard, and the stretching block (`:2060`) no longer
   lists them.
3. Health branch: the three conditions map to the fixtures — B/C pin the discipline lookup, D pins
   "at least one effort" (the default segment exists, so the `efforts.isEmpty` return fires, not the
   segments-null one); fixture E (`createNewSession()` → `modality: null`) pins the Free-all-yoga case
   reaching `yoga` through the branch.
4. Version pins: no dreg — the only `equals(16)` sites left are the four `data_migration_test.dart`
   migration-step pins the plan expects; every remaining `[0, 1, 2]` counts a segment/frame/group list in its
   own domain; the batch pins read `[0, 1, 2, 3]` and the transport list carries four `exercises_down`.
5. Docs: all three edits state only what the named tests assert; no in-scope doc claim made false.

APPROVE
