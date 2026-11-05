# Evidence: plan 116 (catalog delivery)

Base: `27a137bb` on `claude_develop`. Implementers record baselines, suite outputs and red→green tables here.

## Baselines
- `flutter analyze`: 181 issues before and after.

## Verification (lead, observed)
- Full `flutter test`, run 1 (before the last test addition and two comment/doc rewordings): `+6537 ~2: All tests passed!`, exit 0.
- Targeted after the last edit: `test/catalog_reference_refresh_test.dart`, `catalog_delivery_contract_test.dart`, `reference_data_upsert_test.dart`, `docs_indexing_contract_test.dart`, `ui_standards_contract_test.dart`, `db_seed_test.dart`: `+120: All tests passed!`.
- Diff boundary and hive-import grep: print nothing.

## Mutations (lead, applied in place, restored and compared byte for byte)
Killed: no new legs; discipline compares createdAt; order-sensitive kinds compare; disciplines leg after exercises; version left at 15; Mock `upsertUnit` no-op; tags matched by name (two shapes); category deletedAt / sortOrder / key / name / description / iconName ignored; discipline categoryId / key / name ignored; unit name / unitType / key ignored; metric key / name / dataType / defaultUnitId / isCore / appliesToEffortKind ignored; kinds leg write dropped; tags always rewritten; tag name ignored.
First pass left 11 field-level mutants alive (only some fields were drifted by S-19104); closed by 12 one-field drift tests. The independent review then found `UnitModel.key` unguarded; confirmed alive, closed by a 13th drift test, mutant now killed.
Contract test: dummy `SeedData` list, disciplines leg removed, tags leg removed, effort-kinds leg removed, source tags getter emptied: each turned `test/catalog_delivery_contract_test.dart` red (checks 1, 5, 5, 5, 4+5).
