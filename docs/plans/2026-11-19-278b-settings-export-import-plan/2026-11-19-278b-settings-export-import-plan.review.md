# Review: 278a + 278b (Export / Import) · all phases · base.txt..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 2 · minor 4 · tests: not run (brief: the governor already ran; full suite 8633 passed, 1 failed = test/watch_summary_notify_test.dart S-10207, red before this work; analyze 174 vs 176 baseline, 0 errors; docs contract tests green; plan-lint after clean)
Diff vs Predicted Files: conforms — all plan-278 files match the plans' Predicted Files; the extras are plans 277/279 (per brief, ignored) and generated package side effects (pubspec.lock, ios/Podfile.lock, linux/windows/macos plugin registrants). The two doc part pages `docs/data_models_watch.md` and `docs/db_integration_nutrition.md` are untracked (`??`), so `git-diff` cannot show them — see finding 1.

## Findings
1. [Major] docs/data_models_watch.md, docs/db_integration_nutrition.md (whole files, untracked) — both part pages show as `??` in git status, not intent-to-add, so `git-diff` does not list them and a plain commit loses them: the docs delta's moves would leave db_integration.md:364/:368 and data_models.md:582/:586 pointing at missing pages, breaking the docs-index contract. Fix: `git add docs/data_models_watch.md docs/db_integration_nutrition.md` (Governor action). Guard: none (repo state).
2. [Major] docs/theme_and_settings.md:181-232 (new `## Data: export and import`) — plan 278b's Input-reality line 57 requires the sentence "restore with the watch connected: the next launch resends reference data to the wrist as at any launch" to be stated in Docs, and Open item 2 (:220) requires a QA step for export/import device checks "to be added by the docs keeper"; neither exists (grep over docs/ finds no such sentence outside plans; no QA doc gained an export/import step). A maintainer restoring on a second phone has no doc telling them the wrist re-syncs at the next launch. Fix: one sentence in the new section (owner device check, name no test — the docs rule's test-naming requirement cannot bind an owner step; mark it so) and one QA step line in the relevant QA doc. Guard: none (owner device check).
3. [Minor] lib/core/services/backup_service.dart:121-123 — the rollback re-import sits in `catch (_) {}`; if the rollback import itself throws, the store can be left half-replaced while the result still carries `Could not restore. Nothing was changed.` (:76) — a false claim also stated absolutely in docs/state_management/services_and_utils.md:242 ("a refused restore leaves the store untouched"). Only reachable when a Hive IO failure hits both the import and the rollback. Fix: a separate catch for the rollback failure that returns a distinct message ("Could not restore. Some data may have changed."). Guard: a service test whose repository throws on every importSnapshot call.
4. [Minor] docs/db_integration.md:313-315 — the "never carried" sentence names only boxes (`foods_catalog`, `watch_session_*`, device-only meta keys); a restore on a new phone also silently drops the profile-photo file bytes (only the `avatar_path` basename travels; image_storage_service_io.dart holds the file) and `hub_open_count` (SharedPreferences, preferences_service.dart:13). Plan 278a Open item 1 records the photo, but the shipped doc does not. Fix: one sentence in `## Backup file` (photo files and device-only bookkeeping stay behind), `unguarded` per the docs rule.
5. [Minor] docs/plans/2026-11-19-278a-backup-file-engine-plan.md Progress section — all boxes unchecked and the S-27819 fixture change (5,000 → 500 observations) is not recorded, though Open question 6 required the builder to record it in Progress; the Assumption Log also keeps a stray "No assumptions recorded yet." line under A-1. Plan 278b's Progress section is likewise all unchecked. Bookkeeping only. Fix: tick the boxes, record the fixture change, drop the stray line.
6. [Minor] docs/plans/2026-11-19-278b-settings-export-import-plan.md `## Assumption Log` — empty ("No assumptions recorded yet.") after the complex P1-P4 runs (wiring through app.dart, main.dart, home_screen.dart, startup_root.dart). Per the standing check an empty log after a complex phase is a finding. Fix: the lead records the made assumptions or ratifies "none needed" explicitly.

## Brief questions
### 278a — Q1 restore safety
Safe. Both `HiveWorkoutRepository.importSnapshot` and the Mock validate every collection name before any clear (doc comment "Validate every name before writing anything"), so an unknown collection cannot leave the store half-cleared; `foods_catalog` is refused, `nutrition_targets` is accepted-and-ignored on the Mock only (no Mock storage — parity, D-27810's comparison rule). Types are safe: the codec restricts meta to bool/int/String and rows to Map/List/JSON scalars; an oversized JSON int decodes as a double or throws, both refused by `inspect` before anything is written. Rollback exists (S-27808 test) but see finding 3 for its failure mode.
### 278b — Q2 post-restore behaviour
Correct. The progress dialog is popped before `onDataRestored`; `onDataRestored` is wired via `AppRestart.maybeOf` in home_screen.dart (a null only occurs outside the real tree); the tree swap disposes all old state (S-27828, end-to-end S-27829); re-entry is blocked (`_exporting`, `_importInFlight`, non-dismissible progress, PopScope(canPop:false)) and each guard has a test. The Restore-complete screen pairs a `failureTheme`-themed MaterialApp (fixed dark, startup_root.dart:129-146) with a gradient following `OmniTheme.activeTheme` — all six shipped themes are dark with near-white text, so contrast holds for every user. The watch link and audio players keep running until process close — deliberate, stated in the new docs section. The one doc gap is finding 2.
### Q3 export completeness
Hive's `initialize` opens 34 map boxes + 5 list boxes + `foods_catalog` + meta; the allowlist constants classify exactly those (34+5 carried, foods_catalog excluded, 3 device-only meta keys filtered), enforced by the S-27818 source guard (:1122). Staying behind by design and named in docs: `foods_catalog` (rebuilt), `watch_session_*` boxes, device-only meta keys. Staying behind but NOT named in the shipped docs: the photo file bytes and `hub_open_count` — finding 4. SharedPreferences (`hub_open_count`) is outside the backup entirely.
### Q4 platform setup
`ios/Runner/Info.plist` needs no key for share_plus 12 or file_picker 11 (no share/picker permissions exist; camera/photo/health keys pre-exist); Android needs no manifest addition (SAF); the generated plugin registrants for linux/windows/macos and Podfile.lock are committed. The iPad share-origin question is n/a as shipped: the Runner iOS target is `TARGETED_DEVICE_FAMILY = 1` (project.pbxproj:568/:852/:905) and the plan declares one phone track, so the share sheet never presents on iPad; if iPad is ever targeted, share_plus 12 without `sharePositionOrigin` may fail to present and the gateway's catch turns that into the existing `Could not export. Try again.` message. Not checked: the plan's acceptance "iOS build after the packages" — the governor's facts do not report it (Governor action).
### Q5 UI standards + doc moves
The DATA section uses only shared pieces (`OmniSurface`, `OmniCardHeader`, `_SettingsRow` with `Semantics` excludeSemantics, theme-coloured trailing text, `ConfirmationDialog.showTwoChoice`, `OmniMessage.errorOn`); the bare progress dialog is sanctioned by D-27829 (no shared progress piece exists — the widget catalog has none); no colour literal, no raw Card/SnackBar/IconButton, no button without `shape`. No allowlist entry was added and no ratchet count moved (test/helpers/ui_standards_allowlist.dart and the contract test are not in the diff). Both part pages are verbatim pure moves (checked against the removed diff text). The S-27831 overflow probe lives in the new test file per plan Open question 8, not screen_overflow_contract_test — recorded there, not a finding.

## Assumption Log rulings
- 278a A-1 (codec moved to lib/data/models/) — RATIFY: `lib/data/models/backup_codec.dart` exists in the diff; `BackupService` stayed in lib/core/services/.
- 278b empty log — finding 6 (Minor).

## Scenario coverage
### 278a (S-27801..S-27823)
S-27801 → test/backup_snapshot_repository_test.dart · `S-27801 a snapshot restores into a fresh store, row for row` (both harnesses)
S-27801b/c → same file · `S-27801b the export carries rows for every box the fixture fills`, `S-27801c the carried data and catalog versions are restored`
S-27802(a-g) → same file · `S-27802 import replaces a carried collection instead of merging`, `S-27802b an import removes preferences the backup does not carry`, `S-27802c an import replaces list-valued collections`, `S-27802d an import removes a seed tombstone the backup does not carry`, `S-27802e an import replaces every list-valued collection`, `S-27802f an import replaces round instances, timed instances and rests`, `S-27802g an import removes water entries the backup does not carry`
S-27803(a,b) → same file · `S-27803 boxes and meta the snapshot does not carry are left alone`, `S-27803b the bundled food catalog is left alone by an import`
S-27804a → same file · `S-27804a the export never carries a device-only meta key` + test/backup_service_test.dart · `S-27804 the exported text carries no excluded boxes or device keys`
S-27805 → test/backup_codec_test.dart (15+ refusal tests) + backup_service_test.dart · `S-27805 malformed texts are refused and change nothing` (full-export equality before/after; 4 texts)
S-27806 → backup_service_test.dart · `S-27806 a newer dataVersion is refused; 1 and the current one restore`
S-27807 → backup_service_test.dart · three tests (blocks / rolling does not / finished does not) + end-to-end `S-27829b`
S-27808 → backup_service_test.dart · `S-27808 a failed restore puts back the phone's OWN data, not the file's`
S-27809 → backup_service_test.dart · `S-27809 an older backup runs the pending data steps at the next start`
S-27810 → backup_service_test.dart · `S-27810 describe reads the file without writing anything` (covers 'nope' and '{}' as null), `S-27810b describe counts what the file holds, whatever the numbers`
S-27811 → backup_service_test.dart · `S-27811 fileName is the local date, zero-padded`
S-27812 → backup_codec_test.dart · `S-27812 stored values survive the backup text exactly`, `S-27812 encodeBackup writes the header and decodeBackupHeader reads it`, `S-27812 decodeBackupHeader reads a damaged body but refuses a bad marker`
S-27813 → backup_snapshot_repository_test.dart · `S-27813 a planned session keeps its wall-clock day and series text`
S-27814 → backup_snapshot_repository_test.dart · `S-27814 a fresh store exports a well-formed snapshot` + backup_codec_test.dart · `S-27814 an empty snapshot round-trips`
S-27815 → backup_snapshot_repository_test.dart · `S-27815 a Mock snapshot and a Hive snapshot carry the same rows`
S-27816 → backup_snapshot_repository_test.dart · `S-27816 two consecutive exports are equal`
S-27817 → backup_service_test.dart · `S-27817 the service takes the repository interface`
S-27818 → backup_snapshot_repository_test.dart · `S-27818 every box initialize opens is classified for the backup` (source guard)
S-27819 → backup_service_test.dart · `S-27819 a store with 500 observations exports and restores in time` (plan's 5,000 reduced per Open question 6; change unrecorded — finding 5)
S-27820 → backup_service_test.dart · `S-27820 after a refusal the repository still works`
S-27821 → PARTIAL: refused half at backup_codec_test.dart · `S-27805 a lists value holding a non-list is refused`; the "B unchanged" half rests on S-27805's equality mechanism (codec refusal happens before any write), not on this exact text
S-27822 → PARTIAL: refused half at backup_codec_test.dart · `S-27805 a meta value that is an object is refused`; B-unchanged half same as S-27821
S-27823 → PARTIAL: `S-27810` asserts describe-null for 'nope' and '{}' only, not for each of S-27805's invalid texts as the plan words it
### 278b (S-27821..S-27836)
S-27821 → test/settings_data_section_test.dart · `S-27821 the DATA header and both rows render between HEALTH and APPEARANCE`, `S-27821 with a null backupService the DATA section is absent`, `S-27821 with a null backupFileGateway the DATA section is absent`
S-27822 → same file · `S-27822 tapping the export row shares one backup file with today's name`, `S-27822 a gateway that returns false shows the error message and no dialog`, `S-27822 a gateway that throws shows the error message and no dialog`, `S-27822b a second tap while the first share is pending does not share twice`, `S-27822c the export handler ignores a second call while a share is pending`
S-27823 → same file · `S-27823 the picker returning null does nothing`, `S-27823b a screen that is gone while the picker is open does nothing when it returns`
S-27824 → same file · `S-27824 a picked text that is not a backup shows the reason, opens no dialog and changes nothing`, `S-27824b a picker that throws shows the open-failure message and no dialog`
S-27825 → same file · `S-27825 Cancel and a barrier tap restore nothing; Replace restores the file's data`
S-27826 → same file · `S-27826 a restored import reports once, after the data changed`, `S-27826 a running workout refuses the restore with zero reports`, `S-27826b a restore that throws shows the failure message and reports nothing`
S-27827 → same file · `S-27827 the restore holds the blocking progress and blocks re-entry until it resolves`, `S-27827 a restore that resolves refused shows the reason with no report`, `S-27827b the import handler ignores a second call while a restore runs`
S-27828 → test/restore_complete_screen_test.dart · 7 testWidgets, all prefixed `S-27828`
S-27829 → test/backup_restore_end_to_end_test.dart · `S-27829 the whole chain: repo A exports, repo B restores through the Settings flow inside StartupRoot`, `S-27829b a refused restore (running workout) leaves the app on Settings with B unchanged`, `S-27829c Cancel at the confirmation keeps Settings and B unchanged`
S-27830 → test/backup_file_gateway_test.dart · 5 tests (`S-27830 shareText: …`, `S-27830 pickText: …` incl. cancel and invalid UTF-8)
S-27831 → settings_data_section_test.dart · `S-27831 the DATA section scrolls at 390x844 with no overflow and labelled rows`, `S-27831b the rows announce their full action labels, not the plain text`
S-27832 → backup_file_gateway_test.dart · `S-27832 source guard: gateway has no dart:io import`, `S-27832 source guard: no share_plus/file_picker import outside the gateway`
S-27833 → settings_data_section_test.dart · `S-27833 the confirmation body names the file's date and counts, plural and singular`
S-27834 → settings_data_section_test.dart · `S-27834 a service whose export throws shows the error message and never shares`
S-27835 → settings_data_section_test.dart · `S-27835 a backup from a newer build shows the newer-app reason and restores nothing`
S-27836 → backup_restore_end_to_end_test.dart · `S-27836 the next launch's flag read sees the restored onboarding_complete and data version`

## Docs delta — 278a
docs/db_integration.md ADDED `Backup file` -> applied (read at :309-328; every behaviour sentence names a test)
docs/state_management/services_and_utils.md ADDED `BackupService` -> applied (:232-258, test list present)
docs/data_models.md ADDED `BackupSnapshot` -> applied (`## Backup Snapshot Model` at :588)
Doc edits the table does not name: docs/README.md part-page rows + backup pointer (:90, :92); the db_integration.md water-log/food-library moves to db_integration_nutrition.md with pointer sentences (:364, :368); the data_models.md watch-capture/session-energy moves to data_models_watch.md with pointer sentences (:582, :586); the services_and_utils.md `saveRoutineFromDraft` row removal belongs to plan 279, ignored here.

## Docs delta — 278b
docs/theme_and_settings.md ADDED `Data: export and import` -> applied (:181)
docs/navigation_and_screens.md ADDED `DATA section` -> applied (SettingsScreen row :207)
docs/db_integration.md ADDED `export and import from Settings` -> applied (:312 first sentence)
docs/theme_and_settings.md ADDED "The screen groups preferences, sound and alert behaviour, data export and import" -> applied (:98)
docs/theme_and_settings.md MODIFIED (account-management sentence) -> applied (:152)
docs/navigation_and_screens.md MODIFIED (theme selector sentence) -> applied (:207)
Not named by the table: the Input-reality line 57 watch sentence and Open item 2's QA step — MISSING (finding 2).
