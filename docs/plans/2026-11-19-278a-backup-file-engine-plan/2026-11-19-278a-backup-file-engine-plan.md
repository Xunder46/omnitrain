# Plan 278a — Backup file: export and restore engine

Owner list item 2 (2026-11-19): "Export/Import data (in the app Settings probably?)". Owner decisions: one backup file; import REPLACES everything on the phone after a clear warning (no merge).
This plan is the engine (file format, repository read/write of everything, the service with its safety checks). Plan 278b adds the Settings screen, the share sheet and file picker, and the restart after a restore. 278a ships no visible screen.
Phone only. No wire or watch change. Base commit: `.work/2026-11-19-278-export-import/base.txt`. Analyze baseline: 176 issues, 0 errors.

## Goal and acceptance

`BackupService.exportToText()` returns the text of one JSON file holding everything the user owns; `BackupService.restoreFromText(text)` replaces the data on the phone with it, or refuses and leaves the data exactly as it was.

The file holds: every user-data collection of the store (sessions, segments, efforts, observations, round and timed instances, entry rests, session blocks, session energy, sensor summaries, the wrist inbox (it records which wrist sessions were already applied), exercises with their capability, muscle, equipment and tag links, exercise notes, routines (templates, their segments, efforts, targets), planned sessions (with their recurrence text), training periods, profile and body measurements, nutrition targets, foods, food groups, consumed foods, water log, and the reference sets the store keeps beside them (units, metrics, muscle groups, disciplines, sport categories, equipment, tags, metric-to-effort links)), plus the preference and bookkeeping values of the meta box except the device-only ones. It does NOT hold: the bundled food catalog (`foods_catalog`, rebuilt by the app), the watch app's own boxes (`watch_session_*`), the diagnostics log, `notification_permission_asked`, `data_version_last_from`, `data_version_last_to`, and the profile photo file (only its stored path is in the profile row: see Open items).

Restore refuses, changing nothing, when: the text is not JSON or lacks the marker `"format": "omnitrain-backup"`; `formatVersion` is not 1; the backup's `dataVersion` is newer than `currentDataVersion` (made by a newer app: `This backup was made by a newer version of OmniTrain. Update the app and try again.`); a workout is running on this phone (D-27806); any collection is malformed. When it accepts, it clears and rewrites exactly the boxes the file carries, the meta box keys the file carries (device-only keys untouched), and puts everything back as it was if a write fails halfway (rollback from a snapshot taken first). After a restore, the next app start runs the pending data steps for an older backup (`DataMigrationService`).

Acceptance: S-27801..S-27820 green (Mock and Hive harness where stored), each guard red without the change; `flutter analyze` at most 176 issues, 0 errors; `test/db_seed_test.dart`, `test/docs_indexing_contract_test.dart` green; the invariant grep (state/features/widgets/core never import `hive_workout_repository`) clean; no new red in the full suite; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27801 | File format: UTF-8 JSON, one object: `{"format":"omnitrain-backup","formatVersion":1,"appVersion":"x.y.z","exportedAtMs":N,"dataVersion":N,"catalogVersion":N,"collections":{"<box name>":{"<key>":<value>}},"lists":{"<box name>":{"<key>":[...]}},"meta":{"<key>":<bool\|int\|string>}}`. Map-valued boxes go under `collections` (value = the stored map), list-valued boxes under `lists`. Names are the Hive box names (they are also the SQL table contract's collections). | `lib/data/repositories/hive_workout_repository.dart` `initialize` (box names), `docs/db_integration.md` |
| D-27802 | New interface methods on `WorkoutRepository`: `Future<BackupSnapshot> exportSnapshot()` and `Future<void> importSnapshot(BackupSnapshot s)` (replace). `BackupSnapshot` is a plain Dart value type (the three maps above + versions) in `lib/data/models/backup_snapshot.dart`; JSON encode/decode lives in `lib/core/services/backup_codec.dart`. State/features see only the interface (repository pattern). | `lib/data/repositories/workout_repository.dart`; CLAUDE.md "Repository pattern is non-negotiable" |
| D-27803 | Hive implementation: an explicit list of exported box names (the allowlist in D-27801; any box not on it is not exported and not touched). `exportSnapshot` deep-converts each stored `Map<dynamic,dynamic>`/`List` to JSON-safe values. `importSnapshot` clears each box named in the snapshot, writes its rows, then writes the carried meta keys; it never clears a box the snapshot lacks. | `hive_workout_repository.dart` `_asStringMap`, `clear()` (the box list), `_metaBox` |
| D-27804 | Meta box: exported whole except the device-only keys named in Goal. `catalog_version` and `data_version` travel in the header AND stay in meta. Tombstones (`seed_entry_touched_*`) and legacy migration markers are exported (a tombstone lost would let the next catalog refresh overwrite a user-edited bundled exercise). | scout sheet 278 Q1/Q5/Q6, `catalog_refresh_service.dart` `_refreshExercises` |
| D-27805 | Mock implementation: `MockWorkoutRepository.exportSnapshot/importSnapshot` over the same names using each model's `toMap`/`fromMap` through a small table of (name, read, write) entries, so one round-trip test runs against Mock and Hive. | `lib/data/repositories/mock_workout_repository.dart` fields (scout 2 Q5) |
| D-27806 | `BackupService` (new, `lib/core/services/backup_service.dart`; depends on `WorkoutRepository` and an `AppVersionInfo`-like value, nothing concrete): `exportToText()`, `restoreFromText(String)` returning a `BackupRestoreResult` (`restored`/`refused(reason)`), `describe(String)` to read a file's date and counts for the confirmation text without restoring. Order in restore: parse, validate format/version, check no workout is running (a stored `TrainingSession` with `endedAtMs == null` and `isRolling == false`; a rolling free session is allowed), take a rollback snapshot with `exportSnapshot`, `importSnapshot`, on any throw `importSnapshot(rollback)` and return `refused('Could not restore. Nothing was changed.')`. | `lib/core/services/session_summary_service.dart` (service shape), `TrainingSession` fields |
| D-27807 | A backup whose `dataVersion` is older than `currentDataVersion` is accepted: the file's `data_version` stays in meta so the next start runs the pending steps (one launch later). A backup newer than the app is refused (D-27806). | `lib/core/services/data_migration_service.dart` `run` (scout 2 Q3: a newer stored version is a silent no-op today, so the guard must be here) |
| D-27808 | `scripts/sqlite_schema.sql` and `models.dart` are untouched (no model or table changes). The export reads and writes stored maps as they are, so it follows every future model change without code (guard: S-27818). | `scripts/sqlite_schema.sql`, `lib/data/models/models.dart` |
| D-27809 | File name for the later share sheet is produced by one pure function `BackupService.fileName(DateTime)` = `omnitrain-backup-YYYY-MM-DD.json` (local date), so 278b has no naming logic. | - |
| D-27810 | Mock parity rule (appended by the architect): the Mock's (name, read, write) table synthesizes the exact shape Hive stores, under the Hive box and meta key names. Water rows are exported as Hive writes them (`id`, `date_ms`, `volume_ml`, `applied_tap_ids`); tombstones are exported under their `seed_entry_touched_` meta names; legacy migration markers (`seed_loaded`, `*_migrated_v1`) live in the Mock's `_boolPrefs` under the same key names Hive uses in meta. Fields the Mock cannot store (a water row's `created_at_ms`/`updated_at_ms`, Hive's legacy by-id `nutrition_targets` box) are absent from a Mock export, so S-27815's cross-implementation equality compares only what both implementations hold; each implementation's own round trip (S-27801) is exact. | `mock_workout_repository.dart` `_waterVolumesByDate` (:1706)/`_waterTapIdsByDate` (:1730), `_boolPrefs` (:102), `getLegacyAppliedDataVersion` (:1967), `_nutritionTargetsByDate` (:132); `hive_workout_repository.dart` water row writes (:2573-2651) |
| D-27811 | Strict decode (appended by the architect): `decodeBackup` also refuses a `lists` entry whose value is not a list and a `meta` entry whose value is not bool/int/string, and `describe` returns null for any text `restoreFromText` would refuse (no counts, no throw), so 278b's confirmation text can say "not a backup file". The meta box holds bools, ints and strings only today (preference strings, tombstone bools, version ints — `hive_workout_repository.dart` :450, :2659, :2691), so no real key is lost by the rule. | S-27821, S-27822, S-27823 |

## Scenarios (core; the architect adds, never removes)

Fixture for the round trips: a repository seeded through the real writers: 2 finished sessions with segments, efforts, observations and an `EntryRest`; one session block with an effort assigned; a custom exercise (`ownerUserId 'user-1'`) with a muscle link and an exercise note; a routine with 2 template segments, efforts and targets; a planned session with a `recurrenceRule` JSON text (plan 277's format) and one completed with `linkedSessionId`; a training period; a profile and 2 body measurements; a nutrition target for a date; a custom food, a food group and 2 consumed foods; one water entry; session energy and a sensor summary; a wrist inbox entry; preferences `app_theme`, `preferred_weight_unit`, `onboarding_complete`; a tombstone `seed_entry_touched_*`.

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-27801 | repository A seeded through the real writers (the fixture paragraph above), built through `harnessFactories` on Mock and Hive | export from repo A, restore into an empty repo B: every collection equal by `toMap` (a table-driven assertion over the allowlist), every preference and tombstone equal | no export/import methods exist on the repository interface, so the round trip cannot be built |
| S-27802 | B already holds a session and a food that A lacks | after restore B has exactly A's rows (the extra ones are gone) | importSnapshot merges into existing boxes instead of clearing each named box first |
| S-27803 | B holds `foods_catalog` rows, `notification_permission_asked` and `data_version_last_from/to`; restore a file lacking them | the `foods_catalog` rows survive; the device-only meta keys survive; `data_version_last_from/to` are not overwritten | importSnapshot clears boxes the snapshot does not name, or copies the device-only keys into meta |
| S-27804 | the round-trip fixture exported to text | the text never contains `foods_catalog`, `watch_session_`, `notification_permission_asked`, `data_version_last_from` | the allowlist and exclusion filters are missing, so excluded boxes and keys leak into the file |
| S-27805 | texts: not JSON; JSON without the marker; `formatVersion` 2; a collection whose value is not a map | each refuses, and B is unchanged (compare a full export before and after) | no parse or validation happens before the import writes |
| S-27806 | files with `dataVersion` = `currentDataVersion + 1`, `dataVersion` 1, and the current one | the newer one refuses with the newer-app message; `dataVersion` 1 and the current one are accepted | there is no comparison against `currentDataVersion` in restoreFromText |
| S-27807 | a session with `endedAtMs null`, `isRolling false`; a rolling session with `endedAtMs null`; a finished session | the running one blocks restore; the rolling and the finished one do not | there is no running-workout guard (or `isRolling` is not filtered), so restore runs under a live workout |
| S-27808 | a repository stub wrapping the real one whose `importSnapshot` throws on the 3rd box | B is exactly as before (full-export equality) and the result is `refused('Could not restore. Nothing was changed.')` | no rollback snapshot is taken before the import, so a halfway failure leaves B half-written |
| S-27809 | a backup with `dataVersion` 5 in meta and header, rows as they were | it restores, and opening a new `HiveWorkoutRepository` over the same storage runs the pending data steps and ends at `currentDataVersion` (Hive harness `restart()`) | the file's `data_version` never reaches meta, so the next start sees nothing pending and skips the steps |
| S-27810 | the round-trip text | `describe(text)` returns the export date, the app version and counts (sessions, routines, foods) and writes nothing (a counting repository shows zero writes) | describe does not exist, so 278b cannot build the confirmation text without importing |
| S-27811 | `DateTime(2026, 11, 19, 23, 59)` and `DateTime(2027, 1, 5, 0, 0)` | `omnitrain-backup-2026-11-19.json` and `omnitrain-backup-2027-01-05.json` (local date, zero-padded) | fileName does not exist and 278b would have to invent naming |
| S-27812 | a stored row with `scheduled_date_ms` above 2^31, doubles, nulls, a string with quotes, newline and emoji, a nested list (`exercise_muscle_groups`) | the exported text survives decode exactly: ints stay ints, doubles stay doubles, nulls stay null, the string and the nested list survive | the codec loses fidelity (for example ints routed through double or string) |
| S-27813 | a planned session with a `recurrence_rule` text (plan 277's format) and its `scheduled_date_ms` wall-clock key | restore then `getPlannedSessions()` equals the original instants | stored values are re-derived through a day-key or rule parser instead of copied |
| S-27814 | a fresh install (empty store, seeded by nothing) | the export is valid and restores into an empty repository leaving it equally empty | the codec or import cannot handle empty collections and throws or writes junk |
| S-27815 | export from Mock restored into Hive, and the reverse | the collections compare equal (per D-27810's comparison rule), proving both implementations write the same file | the Mock's (name, read, write) table diverges from the stored-map shape Hive uses |
| S-27816 | two exports in a row | the two files differ only in `exportedAtMs` | an export has a side effect on the store (a counter or a marker written), so the second export differs |
| S-27817 | the invariant grep `import .*hive_workout_repository` over lib/state, lib/features, lib/widgets, lib/core (empty today: only lib/main.dart imports the Hive repo) and `BackupService`'s constructor | the grep stays empty; the constructor takes `WorkoutRepository` | a concrete Hive import leaks past the interface or BackupService takes the concrete type |
| S-27818 | the box-open list in `HiveWorkoutRepository.initialize` (:206-262) read by the test as source text | every opened name is on the export allowlist or on the named exclusions (`foods_catalog`); a new box fails the test until classified | there is no source guard, so a future box is silently dropped from the file |
| S-27819 | a store with 5,000 observations written through the real write methods | export and restore finish under the test's 10-second guard (a plain `test()`, not `testWidgets`) | a per-read or per-row loop that does not scale to real volumes |
| S-27820 | after a refused restore (any guard of S-27805..S-27808) | the repository is still usable: a normal write and read works | the rollback or refusal leaves boxes cleared or the repository half-initialized |

Appended by the architect (edge cases the seeded 20 do not name; all from the same codec):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-27821 | a `lists` entry whose value is not a list (`"exercise_muscle_groups": {"k1": 7}`) | refused, B unchanged | decode accepts it and the import's `put` throws halfway, costing a rollback instead of a cheap refusal (D-27811) |
| S-27822 | a `meta` entry whose value is an object (`"custom": {"a": 1}`) | refused, B unchanged | a nested meta value would crash or corrupt the meta `put` (no meta key of this shape exists today, D-27811) |
| S-27823 | `describe` on each of S-27805's invalid texts | returns null (no counts, no throw) | describe would throw or invent counts for a text that is not a backup |

## Input-reality checklist

1. Writers: every stored value is written by its own repository method as `toMap`; the export never re-interprets values, it copies stored maps (D-27808). Units: stored canonical (kg, metres, ms). The profile photo path is written by `ImageStorageService` via `ProfileState`: the file itself is NOT in the backup (Open item 1).
2. Lifecycle: a running workout blocks restore (S-27807); unfinished rolling sessions are included as they are; deleted rows are simply absent (the wrist inbox rows are the tombstones and are included); archived exercises included (`is_archived`).
3. Settings: none read at export; after restore Settings values come from the carried `meta` keys; the screen (278b) restarts startup so every state re-reads them.
4. Time: wall-clock day keys are copied as stored (S-27813); `exportedAtMs` is `DateTime.now()` in UTC milliseconds; the file name uses the local date.
5. Cost: export reads each box once; restore clears and writes each box once, plus one export for the rollback; no per-row reload.
6. Words: stale terms to sweep in `docs/`: `no export`, `Export`, `import` near Settings (see Docs delta); `db_integration.md` lists box names that now carry an export allowlist.
7. Competition: n/a.

## Feature invariants

- Restore replaces, never merges: each box named in the file is cleared and rewritten; boxes the file lacks are untouched (D-27803; S-27802, S-27803).
- A refused restore changes nothing, down to equality of a full export taken before (D-27806; S-27805, S-27808, S-27820).
- The file carries no `foods_catalog`, no `watch_session_*` box and no device-only meta key (D-27801, D-27803; S-27804).
- Stored maps are copied as they are, never re-derived or re-interpreted (D-27808; S-27812, S-27813).
- Tombstones and legacy migration markers travel in meta, so the next catalog refresh and the next start's data steps keep their semantics (D-27804; S-27809).
- `dataVersion` above `currentDataVersion` refuses; older versions pass and the next start migrates (D-27807; S-27806, S-27809).
- Outside `lib/data` only the `WorkoutRepository` interface is seen (repository pattern; S-27817).
- Every box opened by `initialize` is classified on the export allowlist or the named exclusions (S-27818).
- `currentDataVersion` (lib/core/constants/data_version.dart, 20 today) is the only version constant the service compares against; no hard-coded number anywhere else.

## Existing-functionality impact

| Touched surface | What already reads it (searched this run) | Effect | Guarded by |
|---|---|---|---|
| `WorkoutRepository` gains `exportSnapshot`/`importSnapshot` | `implements WorkoutRepository` matches exactly `HiveWorkoutRepository` (hive_workout_repository.dart:45) and `MockWorkoutRepository` (mock_workout_repository.dart:53); every test fake `extends MockWorkoutRepository` and inherits (about 40 classes across test/, e.g. `DelayedNoteRepository`, `DelayedRestMockRepository`, `RevisionedRepository`; `test/helpers/repository_harness.dart:117` `harnessFactories` builds exactly the two implementations) | Mock gets throwing stubs the moment the interface lands (compilation), replaced in P3; fakes compile unchanged | S-27817, S-27815 |
| `initialize` box-open list (hive_workout_repository.dart:206-262) | S-27818's new source guard; `docs/db_integration.md` names the boxes | no code change; the guard classifies every name once | S-27818 |
| `getInProgressSessions()` (workout_repository.dart:24; Hive :3319 and Mock :467 both return `endedAtMs == null` rows including rolling ones) | no state reads it for a guard today; BackupService becomes its second reader | one filtered read (block only when a row has `isRolling == false`) | S-27807 |
| meta-box data-version keys (:69-79) | `DataMigrationService.run` (data_migration_service.dart:67; a newer stored version is a silent no-op at :83), `catalog_refresh_service.dart:146` `_refreshExercises` tombstone gates | carried meta keys keep both semantics alive after a restore on a fresh phone | S-27809, D-27804 |
| the full suite | the two interface methods are additive; no existing test names them; the repository harness is unchanged | no existing behaviour changes; the Mock stubs are `UnimplementedError` only between P2 and P3 | each phase's Done command and the lead's full-suite compare |

## Readers

Every reader of a contract this plan adds or changes:

- `WorkoutRepository.exportSnapshot`/`importSnapshot`: the two implementations above, `BackupService` (P4), and 278b's screen (a later plan); no state, feature, widget or screen reads them in this plan. Every test fake inherits without edit.
- `BackupSnapshot`: `lib/core/services/backup_codec.dart`, both repositories, `BackupService`, the tests.
- `BackupRestoreResult`: `BackupService.restoreFromText`, its tests, and 278b's screen later.
- `BackupInfo?` (describe's return): `BackupService.describe`, its tests, 278b later.
- The allowlist constants (`_backupMapBoxes`, `_backupListBoxes`, `_backupExcludedBoxes`, `_backupDeviceOnlyMetaKeys`): `HiveWorkoutRepository.exportSnapshot`/`importSnapshot` and S-27818's source guard.
- The repository harness is untouched, so its existing consumers (every repository test) are unaffected.

## Phases (`crew-builder-data` for 1-4, then `crew-docs-keeper`; serial)

All five phases are serial, in this order, no parallel runs: P2's interface change breaks the package's compilation until P3 lands the Mock methods; P4 consumes both; P5 documents symbols P1-P4 create. Each phase is one agent run.

### P1 value type and codec — crew-builder-data

Write scope: `lib/data/models/backup_snapshot.dart` (new), `lib/core/services/backup_codec.dart` (new), `test/backup_codec_test.dart` (new). Decisions D-27801 (codec half), D-27802 (type half), D-27811. Scenarios S-27805 (parse half), S-27812.

1. [ ] Add the `BackupSnapshot` value type (the three maps `collections`, `lists`, `meta` plus `dataVersion` and `catalogVersion`; plain final fields, no `toMap`) — lib/data/models/backup_snapshot.dart · `BackupSnapshot`
2. [ ] Add `encodeBackup(snapshot, {required String appVersion, DateTime? now})` producing the D-27801 object with `"format":"omnitrain-backup"`, `formatVersion: 1`, `appVersion`, `exportedAtMs` — lib/core/services/backup_codec.dart · `encodeBackup`
3. [ ] Add `decodeBackup(String)` returning `BackupSnapshot` and throwing `BackupFormatException` for: not JSON; the marker missing; `formatVersion != 1`; a `collections` value that is not a map; a `lists` value that is not a list; a `meta` value that is not bool/int/string (D-27811) — lib/core/services/backup_codec.dart · `decodeBackup`
4. [ ] Cover S-27812: an int above 2^31, a double, a null, a string with quotes, newline and emoji, a nested list — test/backup_codec_test.dart · S-27812
5. [ ] Cover S-27805's parse half: each bad text throws and a valid text decodes — test/backup_codec_test.dart · S-27805
6. [ ] Round trip: `decodeBackup(encodeBackup(x))` equals x for a snapshot holding all three maps — test/backup_codec_test.dart

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/backup_codec_test.dart`; `flutter analyze` at the 176/0 baseline. Predicted files: exactly the three in scope. Guard proof: the test file is new, so nothing compiles at the base commit and prove-red is impossible; both guards are proven by mutations (a), (b) in the Mutation list.

### P2 interface + Hive — crew-builder-data (after P1)

Write scope: `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart` (stubs only), `lib/data/repositories/hive_workout_repository.dart`, `test/backup_snapshot_repository_test.dart` (new). Decisions D-27802, D-27803, D-27804, D-27808. Scenarios S-27801..S-27803, S-27813, S-27814, S-27816, S-27818 — the Hive halves; the Mock halves land in P3 (the P2 stub would red them).

1. [ ] Add the two abstract methods to the interface — lib/data/repositories/workout_repository.dart · `WorkoutRepository`
2. [ ] Add throwing stubs (`UnimplementedError`) so the package compiles; P3 replaces them — lib/data/repositories/mock_workout_repository.dart · `MockWorkoutRepository.exportSnapshot`, `MockWorkoutRepository.importSnapshot`
3. [ ] Add the allowlist constants (map-box names, list-box names) and the exclusion names (`foods_catalog`; device-only meta keys `notification_permission_asked`, `data_version_last_from`, `data_version_last_to`) beside the initialize box list — lib/data/repositories/hive_workout_repository.dart · `_backupMapBoxes`, `_backupListBoxes`, `_backupExcludedBoxes`, `_backupDeviceOnlyMetaKeys`
4. [ ] Implement `exportSnapshot`: deep-copy each stored map/list to JSON-safe values, read meta, filter the device-only keys — lib/data/repositories/hive_workout_repository.dart · `HiveWorkoutRepository.exportSnapshot`
5. [ ] Implement `importSnapshot`: for each name in the snapshot clear that box and write its rows; write the carried meta keys; never clear a box the snapshot lacks; never touch `_initialized` or a device-only key — lib/data/repositories/hive_workout_repository.dart · `HiveWorkoutRepository.importSnapshot`
6. [ ] Tests S-27801, S-27802, S-27803 on the Hive harness (seed Hive in `setUp`, plain `test()`) — test/backup_snapshot_repository_test.dart
7. [ ] Tests S-27813, S-27814, S-27816 — test/backup_snapshot_repository_test.dart
8. [ ] Test S-27818: the source-text guard over the initialize box-open list — test/backup_snapshot_repository_test.dart

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/backup_snapshot_repository_test.dart` (run only after items 1 and 2, the package does not compile between them); analyze at baseline; `test/db_seed_test.dart` still green. Predicted files: exactly the four in scope. Guard proof: mutations (c)-(f), (n); the source guard itself cannot be red at base (new file).

### P3 Mock — crew-builder-data (after P2)

Write scope: `lib/data/repositories/mock_workout_repository.dart`, `test/backup_snapshot_repository_test.dart`. Decisions D-27805, D-27810. Scenarios S-27815 plus the Mock halves of S-27801..S-27803, S-27813, S-27814, S-27816.

1. [ ] Implement `exportSnapshot` over the (name, read, write) table: every store under its Hive box name; water rows synthesized as Hive stores them (`id`, `date_ms`, `volume_ml`, `applied_tap_ids`); tombstones under their `seed_entry_touched_` meta names; `_boolPrefs`/`_stringPrefs` (which carry the legacy markers) and `catalog_version`, `data_version` as meta, device-only keys filtered — lib/data/repositories/mock_workout_repository.dart · `MockWorkoutRepository.exportSnapshot`
2. [ ] Implement `importSnapshot`: clear each named store directly (never via `clear()`, which omits `_exerciseNotes` and `_sessionBlocks`), write the rows, write the carried meta (`_boolPrefs`, `_stringPrefs`, tombstones, `_catalogVersion`, `_dataVersion`); the Mock has no `foods_catalog` store, so it is structurally untouched — lib/data/repositories/mock_workout_repository.dart · `MockWorkoutRepository.importSnapshot`
3. [ ] Add the Mock halves of S-27801, S-27802, S-27803, S-27813, S-27814, S-27816 — test/backup_snapshot_repository_test.dart
4. [ ] Test S-27815: Mock→Hive and Hive→Mock; `water_log` compares `volume_ml` and `applied_tap_ids` only (Hive's row timestamps have no Mock writer and are lost on a Hive→Mock restore, D-27810); meta compares the keys both implementations carry — test/backup_snapshot_repository_test.dart
5. [ ] Search that every other implementer and fake compiles unchanged: `grep -rln "implements WorkoutRepository\|extends MockWorkoutRepository" lib test` and list the result in the phase report — search only, no edit

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/backup_snapshot_repository_test.dart`; analyze at baseline. Predicted files: exactly the two in scope. Guard proof: mutation (g); the structural checks are reported, not tested.

### P4 service — crew-builder-data (after P3)

Write scope: `lib/core/services/backup_service.dart` (new), `test/backup_service_test.dart` (new). Decisions D-27806, D-27807, D-27809. Scenarios S-27804..S-27811, S-27817, S-27819, S-27820.

1. [ ] Add `BackupRestoreResult` (`restored` / `refused(String reason)`) — lib/core/services/backup_service.dart · `BackupRestoreResult`
2. [ ] Add `BackupService` whose constructor takes `WorkoutRepository` and `AppVersionInfo` (lib/core/models/app_version_info.dart:15, verified this run), and record the S-27817 invariant grep result in the phase report — lib/core/services/backup_service.dart · `BackupService`
3. [ ] Add `exportToText()` (encode `exportSnapshot()` with the app version) — lib/core/services/backup_service.dart · `BackupService.exportToText`
4. [ ] Add `restoreFromText(String)` in D-27806's order: decode; refuse a `dataVersion` above `currentDataVersion`; read `getInProgressSessions()` and refuse when any row has `isRolling == false`; take the rollback snapshot with `exportSnapshot`; `importSnapshot`; on any throw restore the rollback and return `refused('Could not restore. Nothing was changed.')` — lib/core/services/backup_service.dart · `BackupService.restoreFromText`
5. [ ] Add `describe(String)` returning the export date, app version and counts (sessions, routines, foods), null when restore would refuse (D-27811) — lib/core/services/backup_service.dart · `BackupService.describe`
6. [ ] Add `fileName(DateTime)` (local date, D-27809) — lib/core/services/backup_service.dart · `BackupService.fileName`
7. [ ] Guard tests S-27805..S-27808 (the refusal halves) — test/backup_service_test.dart
8. [ ] Behaviour tests S-27804, S-27806 (accept halves), S-27809 (Hive harness `restart()`, next start ends at `currentDataVersion`), S-27810, S-27811, S-27819 (5,000 rows written through the real write methods, plain `test()`), S-27820 — test/backup_service_test.dart

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/backup_service_test.dart`; analyze at baseline. Predicted files: exactly the two in scope. Guard proof: mutations (h)-(m), (p), (q); S-27814 and S-27819 are behaviour fixtures with no single-line mutation.

### P5 docs — crew-docs-keeper (last)

Write scope: `docs/db_integration.md`, `docs/state_management/services_and_utils.md`, `docs/data_models.md`. Items are the Docs delta table's rows.

1. [ ] Add the `Backup file` section (format, allowlist, exclusions, restore rules, version handling; every behaviour sentence names its test) — docs/db_integration.md · `Backup file`
2. [ ] Add the `BackupService` row to the service list — docs/state_management/services_and_utils.md · `BackupService`
3. [ ] Add the `BackupSnapshot` row — docs/data_models.md · `BackupSnapshot`
4. [ ] Verify the size ceilings and that every symbol the docs name exists in lib — test/docs_indexing_contract_test.dart

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/docs_indexing_contract_test.dart`. Requires P1-P4 done (the named symbols must exist).

## Mutation list (lead)

- (a) `encodeBackup` routes ints through `toDouble()` → S-27812 red.
- (b) `decodeBackup` drops the `"format"` marker check → S-27805 red.
- (c) Hive `exportSnapshot` drops one box name (`efforts`) → S-27801 red (collections not equal).
- (d) `importSnapshot` (both implementations) skips the per-box clear → S-27802 red.
- (e) Hive `importSnapshot` clears `foods_catalog` (a box the snapshot lacks) → S-27803 red; (f) `exportSnapshot` drops the device-only meta filter → S-27804 red.
- (g) the Mock's water table writes `volume_ml` under a wrong key (`volumeML`) → S-27815 red.
- (h) `restoreFromText` drops the `dataVersion > currentDataVersion` comparison → S-27806 red.
- (i) `restoreFromText` drops the running-workout check (or inverts the `isRolling` filter) → S-27807 red.
- (j) the catch block skips `importSnapshot(rollback)` → S-27808 red.
- (k) Hive `importSnapshot` skips writing the carried `data_version` into meta → S-27809 red.
- (l) `describe` returns hardcoded counts without reading the text → S-27810 red.
- (m) `fileName` uses the UTC date → S-27811 red.
- (n) remove `foods_catalog` from the exclusion constants → S-27818 red (an opened box unclassified).
- (o) `exportSnapshot` writes a counter into meta → S-27816 red (the second export differs beyond `exportedAtMs`).
- (p) `BackupService`'s constructor takes `HiveWorkoutRepository` → S-27817 red (the test constructing it with the Mock stops compiling).
- (q) the refused path returns `restored`, or the rollback leaves the repository unusable → S-27820 red.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/db_integration.md` | ADDED | - | `Backup file` | D-27801, D-27803, D-27807, S-27818 |
| `docs/state_management/services_and_utils.md` | ADDED | - | `BackupService` | D-27806 |
| `docs/data_models.md` | ADDED | - | `BackupSnapshot` | D-27802 |

Stale-term sweep (architect, this run) over `docs/` excluding `docs/plans`, `docs/history`, `docs/releases`: no additional row. No doc contains the phrase `no export`. The only near hit is `docs/theme_and_settings.md:152` `The Settings screen does not include account-management rows such as sign-in, export-data, or account-removal actions.` which stays true — 278a ships no screen; that doc is owned by plan 278b's own Docs delta. The `db_integration.md` box-name table (:253) stays correct: the export allowlist is a subset of it, and the new section says so. `docs/data_models.md`, `docs/state_management/services_and_utils.md` get only the ADDED rows above. In "after" mode the keeper must copy each New marker cell's text verbatim onto one line of the target doc (plan-lint strips only the outermost backticks).

## Open items for the owner

1. The profile photo is not in the backup (the file lives outside the data store). After a restore on a new phone the profile shows no photo until one is picked again. Say if you want the photo inside the file (it makes the file bigger).
2. I kept the wrist inbox in the file even though you said "skip watch sync leftovers": it is the record that stops the watch from re-adding sessions already in your history, so a restore without it could duplicate them.
3. The bundled food catalog is not in the file (the app rebuilds it); custom foods and your food groups are.

## Progress

- [x] Seeded (goal, ledger D-27801..D-27809, scenarios S-27801..S-27820, phase outline)
- [x] P1 value type and codec (D-27801 codec, D-27802 type, D-27811; S-27805 parse, S-27812)
- [x] P2 interface + Hive (D-27802..D-27804, D-27808; Hive halves of S-27801..S-27803, S-27813, S-27814, S-27816, S-27818)
- [x] P3 Mock (D-27805, D-27810; S-27815 and the Mock halves)
- [x] P4 service (D-27806, D-27807, D-27809; S-27804..S-27811, S-27817, S-27819, S-27820)
- [x] P5 docs (the three Docs delta rows)
- [x] Full-suite compare against the base failing set and analyze at the 176/0 baseline (lead)
- [x] (owner) Open items 1-3

## Assumption Log

| ID | Assumption | Resolution |
|---|---|---|
| A-2 | S-27819 uses 500 observations instead of 5,000 (the 5,000-row Hive fixture is slow; the loop shape is the same). | Recorded |
| A-3 | The wrist inbox is carried in the file although the owner said to skip watch leftovers (it is the record that stops a restored phone re-adding wrist sessions). | Owner told in the report |
| A-1 | Lead, 2026-11-19: the codec moves from `lib/core/services/backup_codec.dart` to `lib/data/models/backup_codec.dart` (crew-builder-data cannot write `lib/core/**`, crew-builder-app cannot write `lib/data/**`; the codec is a pure data-format file). `BackupService` (P4) stays in `lib/core/services/` with crew-builder-app. | Done in the P1 brief |



## Open questions

1. Plan-lint "after" mode (this run's read of `.claude/scripts/macos/plan-lint.py`): a Docs delta New marker must appear literally on one line of the target doc, with only the outermost backticks stripped — so row 1 needs the text `Backup file` (new section: format, allowlist, exclusions, restore rules, version handling) and row 2 needs `BackupService` row` on one line. The seeded rows are kept as written; the keeper must copy the marker cells verbatim (easiest: open the new section with the row 1 phrase, and give the new table cells the exact `Xxx` row text).
2. The seeded S-27815 says "collections equal" for the cross-implementation restore, but a Hive→Mock restore cannot be byte-equal for `water_log` (Hive rows carry `id`/`created_at_ms`/`updated_at_ms`; the Mock has no writer for them). Kept as written and given a comparison rule in appended D-27810; if the owner wants exactness, the Mock would need new fields (a model change D-27808 forbids).
3. `notification_permission_asked` is a repository preference (`SettingsState`:416 reads it via `_repository.getPreferenceString`), stored in the meta box on both implementations — consistent with the seed's device-only exclusion. Verified, no change.
4. 278b's seeded input-reality line 6 claims `docs/db_integration.md` has a "no export" mention — not found by grep this run; that claim looks stale and is 278b's to fix, not this plan's.
5. Budget (`.github/copilot/pr-scope-budget.md`): 5 implementation phases is exactly at the hard limit (a split triggers at more than 5); 11 decisions (< 20), 23 scenarios (< 30), one track (phone, no watch), predicted production code about 600 lines (< 1,500). The plan is about 380 lines, under the 800-line hard limit; the only soft signal is plan length if it grows past 500 during execution. One PR.
6. S-27819's 5,000-row fixture is built through the real write methods in a loop; if seeding that volume on the Hive harness is too slow to keep the file under the 10-second guard while still testing it, the builder should use the smallest count that exercises the same loop shape and record the change in the Progress section.
