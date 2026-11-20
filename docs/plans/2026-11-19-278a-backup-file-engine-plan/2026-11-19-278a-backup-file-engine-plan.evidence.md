# Plan 278a evidence — Backup file: export and restore engine

Keeper note: this file records what this run saw on disk and in the test files. Build/test counts
are the lead's; `counts: see lead` marks them.

## P1 value type and codec — crew-builder-data

Files on disk (existence verified this run):
- `lib/data/models/backup_snapshot.dart` (`BackupSnapshot`: `collections`, `lists`, `meta`, `dataVersion`, `catalogVersion`)
- `lib/data/models/backup_codec.dart` (`encodeBackup`, `decodeBackup`, `BackupFormatException`)
- `test/backup_codec_test.dart`
- `test/backup_snapshot_repository_test.dart`

Tests read this run: `test/backup_codec_test.dart` (top-level tests; no groups) —
`S-27812 stored values survive the backup text exactly`, `S-27812 encodeBackup writes the header
and decodeBackupHeader reads it`, `S-27805 text that is not JSON is refused`, `S-27814 an empty
snapshot round-trips`.

## P2 interface + Hive — crew-builder-data

Files: `lib/data/repositories/workout_repository.dart` (interface additions; not read this run),
`lib/data/repositories/hive_workout_repository.dart` (allowlists read this run:
`_backupMapBoxes`, `_backupListBoxes`, `_backupExcludedBoxes = {foods_catalog}`,
`_backupDeviceOnlyMetaKeys`; `exportSnapshot`/`importSnapshot`), `test/backup_snapshot_repository_test.dart`.

Tests read this run (`test/backup_snapshot_repository_test.dart`, groups
`${harness.name} — backup snapshot` with harness `Mock`/`Hive` from
`test/helpers/repository_harness.dart`): `S-27801 a snapshot restores into a fresh store, row for
row`, `S-27801b the export carries rows for every box the fixture fills`, `S-27802 import
replaces a carried collection instead of merging`, `S-27802b an import removes preferences the
backup does not carry but keeps device-only keys`, `S-27803 boxes and meta the snapshot does not
carry are left alone`, `S-27803b the bundled food catalog is left alone by an import`,
`S-27804a the export never carries a device-only meta key`, `S-27818 every box initialize opens
is classified for the backup` (source-scans the declarations). Top-level:
`S-27815 a Mock snapshot and a Hive snapshot carry the same rows`.

counts: see lead.

## P3 Mock — crew-builder-data

File: the Mock repository (not read this run; the group names above are the same file's).
counts: see lead.

## P4 service — crew-builder-data

Files on disk: `lib/core/services/backup_service.dart` (read this run: `exportToText`,
`restoreFromText` → `BackupRestoreResult`, `describe` → `BackupInfo`, `fileName`,
`newerAppMessage`, `runningWorkoutMessage`, `failedMessage`), `test/backup_service_test.dart`.

Tests read this run (`test/backup_service_test.dart`, groups `Mock — BackupService` /
`Hive — BackupService`): `S-27804 the exported text carries no excluded boxes or device keys`,
`S-27805 malformed texts are refused and change nothing`, `S-27806 a newer dataVersion is
refused; 1 and the current one restore`, `S-27807 a running workout blocks the restore`,
`S-27809 an older backup runs the pending data steps at the next start`,
`S-27810 describe reads the file without writing anything`, `S-27810b describe counts what the
file holds, whatever the numbers`, `S-27819 a store with 500 observations exports and restores
in time`, `S-27820 after a refusal the repository still works`. Top-level: `S-27808 a failed
restore puts back the phone's OWN data, not the file's`, `S-27811 fileName is the local date,
zero-padded`, `S-27817 the service takes the repository interface`.

counts: see lead.

## P5 docs — crew-docs-keeper

Docs delta rows executed this run:

| Row | Verdict |
|---|---|
| `docs/db_integration.md` ADDED `Backup file` | done (section at :309; `## Backup file` on one line) |
| `docs/state_management/services_and_utils.md` ADDED `BackupService` | done (section at :232) |
| `docs/data_models.md` ADDED `BackupSnapshot` | done (section at :676) |

Sizes after the edits (reported by the file reader this run): `docs/db_integration.md` 52.3 KB
(ceiling 52,428 bytes per the brief), `docs/data_models.md` 51.9 KB (trimmed from 52.5 to stay
under the 52 KB keeper limit), `docs/state_management/services_and_utils.md` 50.0 KB.

`test/docs_indexing_contract_test.dart`: not run — this run's brief forbids running tests.
Symbol existence was checked by reading `lib/data/models/backup_snapshot.dart`,
`lib/data/models/backup_codec.dart` and `lib/core/services/backup_service.dart` this run;
`WorkoutRepository` additions and the Mock's methods: not checked this run.

Stale-term sweep this run (pattern `export-data|no export|export data|import data|backup|Backup|restore complete|RestoreComplete` over `docs/*.md` recursive): every hit outside this plan's five docs and plan 278b's docs is under `docs/plans/`. No stale claim.
