# Plan 278b evidence — Settings export and import

Keeper note: this file records what this run saw on disk and in the test files. Build/test counts
are the lead's; `counts: see lead` marks them.

## P1 gateway + packages — crew-builder-app

Files on disk: `lib/core/services/backup_file_gateway.dart` (exists this run),
`test/backup_file_gateway_test.dart` (read this run: `S-27830` share/pick seam tests —
share receives the file name and UTF-8 bytes, a throwing share returns false, pick decodes bytes
to text, a cancelled pick returns null, invalid UTF-8 returns an empty string; `S-27832`
source-guard that the gateway has no `dart:io` import and no `share_plus`/`file_picker` import
outside the gateway). `pubspec.yaml` package additions: not checked this run.

counts: see lead.

## P2 restore-complete screen — crew-builder-app

Files on disk: `lib/features/startup/restore_complete_screen.dart` (existence verified this run),
`test/restore_complete_screen_test.dart` (read this run). Asserted copy read this run: title
`Restore complete`, body `Close OmniTrain and open it again to finish. Your data is restored.`

Tests read this run (`test/restore_complete_screen_test.dart`, ids `S-27828`; seven tests
including `showRestartRequired replaces the fake running app, disposes it and renders the
Restore-complete screen` and `the restore-complete screen offers no way out: no back button, no
action button, system back does nothing`).

counts: see lead.

## P3 Settings section — crew-builder-app (P3a rows and export, P3b import flow)

Files on disk: `lib/features/settings/settings_screen.dart` (not read this run), `lib/main.dart`,
`lib/app.dart`, `lib/features/home/home_screen.dart` wiring (not read this run),
`test/settings_data_section_test.dart` (read this run).

Tests read this run (`test/settings_data_section_test.dart`): groups `DATA section rows`
(`S-27821 the DATA header and both rows render between HEALTH and APPEARANCE`), `Export data
flow` (`S-27822 tapping the export row shares one backup file with today's name`; `S-27834 a
service whose export throws shows the error message and never shares`), `DATA section layout`
(`S-27831 the DATA section scrolls at 390x844 with no overflow and labelled rows`; `S-27831b the
rows announce their full action labels, not the plain text`), `Export re-entry guard`
(`S-27822b a second tap while the first share is pending does not share twice`), `Import data
flow` (`S-27823 the picker returning null does nothing`; `S-27824 a picked text that is not a
backup shows the reason, opens no dialog and changes nothing`; `S-27835 a backup from a newer
build shows the newer-app reason and restores nothing`; `S-27833 the confirmation body names the
file's date and counts, plural and singular`; `S-27825 Cancel and a barrier tap restore nothing;
Replace restores the file's data`; `S-27827 the restore holds the blocking progress and blocks
re-entry until it resolves`; `S-27824b a picker that throws shows the open-failure message and no
dialog`; `S-27827b the import handler ignores a second call while a restore runs`;
`S-27826b a restore that throws shows the failure message and reports nothing`;
`S-27823b a screen that is gone while the picker is open does nothing when it returns`).
Asserted copy read this run: `Could not export. Try again.`, `Replace all data?`, body
`This replaces everything on this phone with the backup from 19 Nov 2026: 142 workouts,
6 routines. Your current data is not kept. This cannot be undone.`

counts: see lead.

## P4 end to end — crew-builder-app

File on disk: `test/backup_restore_end_to_end_test.dart` (read this run): `S-27829 the whole
chain: repo A exports, repo B restores through the Settings flow inside StartupRoot`;
`S-27836 the next launch's flag read sees the restored onboarding_complete and data version`;
`S-27829b a refused restore (running workout) leaves the app on Settings with B unchanged`.

counts: see lead.

## P5 docs — crew-docs-keeper

Docs delta rows executed this run:

| Row | Verdict |
|---|---|
| `docs/theme_and_settings.md` ADDED `Data: export and import` | done (section at :181) |
| `docs/navigation_and_screens.md` ADDED `DATA section` | done (`SettingsScreen` row at :207, marker on one line) |
| `docs/db_integration.md` ADDED `export and import from Settings` | done (:311, marker on one line) |
| `docs/theme_and_settings.md` MODIFIED "The screen groups preferences, sound and alert behaviour" → "..., data export and import" | done (:96; note: the Old marker is a strict prefix of the New marker, so both cannot hold — reported to the lead) |
| `docs/theme_and_settings.md` MODIFIED "does not include account-management rows such as sign-in, export-data, or account-removal actions" → "...sign-in or account-removal actions; data export and import live in the DATA section" | done (:152, old gone, new on one line) |
| `docs/navigation_and_screens.md` MODIFIED "appearance theme selector, and a low-emphasis version footer" → "appearance theme selector, the DATA export and import rows, and a low-emphasis version footer" | done (:207, old gone, new on one line) |

Sizes after the edits (file reader this run): `docs/theme_and_settings.md` (read in full; well
under the limit), `docs/navigation_and_screens.md` 29.9 KB, `docs/db_integration.md` 52.3 KB.

`test/docs_indexing_contract_test.dart` and `test/ui_standards_contract_test.dart`: not run —
this run's brief forbids running tests. Docs-side standards check done by reading: the new section
names `OmniMessage`-class behaviour only through the tests; no widget-code change belongs to this
phase, so no allowlist check applies.

Stale-term sweep this run (pattern `export-data|no export|export data|import data|backup|Backup|restore complete|RestoreComplete` over `docs/*.md` recursive): every hit outside this plan's three docs and plan 278a's docs is under `docs/plans/`. No stale claim.
