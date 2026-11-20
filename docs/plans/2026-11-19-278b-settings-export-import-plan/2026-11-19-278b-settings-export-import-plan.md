# Plan 278b — Settings: Export data and Import data

Second half of owner list item 2 (2026-11-19). Needs plan 278a (the engine) built and green first. Owner decisions: one backup file; import replaces everything after a clear warning.
Phone only. Base commit: `.work/2026-11-19-278-export-import/base.txt` (278a's commit or working tree when this starts). Analyze baseline: 176 issues, 0 errors (278a must not raise it).

## Goal and acceptance

Settings gets a `DATA` section (after HEALTH, before APPEARANCE) with two rows:

- `Export data` (trailing `Share`): builds the backup file and opens the system share sheet with `omnitrain-backup-<today>.json` (save to Files, AirDrop, email, Drive). If it cannot, a red message says `Could not export. Try again.`; nothing else changes.
- `Import data` (trailing `Choose file`): opens the system file picker. Cancelling does nothing. A file that is not an OmniTrain backup, or is from a newer app, shows a red message with the reason and nothing else. A good file shows `Replace all data?` with the backup's date and counts (`This replaces everything on this phone with the backup from 19 Nov 2026: 142 workouts, 6 routines. Your current data is not kept. This cannot be undone.`) and the buttons `Cancel` / `Replace` (destructive style). `Replace` shows a blocking progress and restores. When it succeeded, the whole app is replaced by a full-screen `Restore complete` screen: `Close OmniTrain and open it again to finish. Your data is restored.` with no way to go on (nothing of the old in-memory data can be used or saved over the restored data); the next launch shows the restored data (Home, or onboarding if the backup says it was not finished). A restore that is refused (a workout is running: `Finish or discard your running workout first.`) or fails (`Could not restore. Nothing was changed.`) leaves the phone's data exactly as it was and says so.

Acceptance: S-27821..S-27832 green, each guard red without the change; `flutter analyze` at most 176 issues, 0 errors; `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart`, `test/navigation_contract_enforcement_test.dart` green; no new red in the full suite; the lead's iOS build (`flutter build ios --simulator --no-codesign` or the watch xcodebuild form in crew rules (ai)/(aj)) succeeds after the packages are added; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27821 | New packages `share_plus` and `file_picker` (the lead adds them with `flutter pub add`, runs `pod install` and reverts `project.pbxproj` noise per crew rules (aj)). Only one file touches them: `lib/core/services/backup_file_gateway.dart` with abstract `BackupFileGateway` (`Future<bool> shareText({required String fileName, required String text})`, `Future<String?> pickText()`) and `PlatformBackupFileGateway` (share via `XFile.fromData` bytes with mime `application/json`; pick with `withData: true` and decode UTF-8; no `dart:io`, so web stays compilable). Tests use a fake gateway. | pubspec `dependencies`; scout 278 Q4 (no share/picker exists, clipboard only); CLAUDE.md "web and native safe" |
| D-27822 | `SettingsScreen` takes optional `BackupService? backupService`, `BackupFileGateway? backupFileGateway`, `VoidCallback? onDataRestored`; the DATA section is absent when `backupService` or the gateway is null (the Diagnostics-row pattern). Wired at the composition root from the same repository instance. | `lib/features/settings/settings_screen.dart` `SettingsScreen` ctor (the `diagnostics` param) and its build list; `lib/main.dart` `runStartup` |
| D-27823 | Rows use the shared surface and row pieces of Settings (`OmniCardHeader(title: 'DATA')`, the same row widget as `_DiagnosticsRow`), never a raw `Card`/`ListTile`. The confirmation uses `ConfirmationDialog.showTwoChoice` with `isDestructive: true`; messages use `OmniMessage` (error variant for failures). The blocking progress uses an existing shared progress piece if one exists (grep the widget catalog), else a non-dismissible `showDialog` with `CircularProgressIndicator` inside the shared dialog look. | `docs/design_system.md` "Shared pieces and rules per job"; `settings_screen.dart` `_DiagnosticsRow` |
| D-27824 | After a successful restore the app does NOT re-run startup in-process (the scout found that a second `runStartup` duplicates a `DiagnosticsLifecycleObserver` and the audio players, leaves the old repository's box listeners and the watch event stream attached: `.work/crew/2026-11-19-278/pointers3.md`). Instead `StartupRoot` gains an `AppRestart` inherited widget with `showRestartRequired()`, which replaces the running app with a plain `RestoreCompleteScreen` that touches no repository or state object. `SettingsScreen.onDataRestored` is `AppRestart.of(context).showRestartRequired`. | `lib/app/startup_root.dart` `_StartupRootState`; scout 3 sheet |
| D-27825 | Import order in the screen: pick, `BackupService.describe`, confirm, progress, `restoreFromText`, then `onDataRestored` only on `restored`. A second tap while a restore runs is ignored (button state). Mounted checks after every await. | plan 278a D-27806 |
| D-27826 | No change to storage, wire or watch; the DATA section text is the only new copy: `DATA`, `Export data`, `Share`, `Import data`, `Choose file`, `Replace all data?`, `Cancel`, `Replace`, and the messages above. | owner-confirm copy |
| D-27827 | The confirmation date comes from `BackupInfo.exportedAtMs` rendered by one screen-local helper with the month-name table already used in `session_summary_screen.dart:1429` (`_formatDate`) and `ChartAxisHelper.formatDateLabel` (`lib/core/utils/chart_axis_helper.dart:161`, no `intl` in the app — grep `DateFormat|intl` in lib/ matches nothing): fixture `DateTime(2026, 11, 19, 23, 30).millisecondsSinceEpoch` (device local) → `19 Nov 2026` (S-27833). The file name is `BackupService.fileName(DateTime.now())` (278a S-27811), never re-derived in the screen. | `lib/features/session/session_summary_screen.dart` `_formatDate`; `BackupService.fileName` |
| D-27828 | Wiring hops: `runStartup` (`lib/main.dart`) builds `BackupService(repository, appVersionInfo)` and `PlatformBackupFileGateway()` after `appVersionInfo` resolves and passes them to `MyApp`; `MyApp` (`lib/app.dart`) forwards them to `HomeScreen`; `HomeScreen` forwards them at the one `SettingsScreen(` call site (home_screen.dart:1142, the 'Settings' `_MaintenanceItem`) with `onDataRestored: AppRestart.of(context).showRestartRequired`. Every new parameter is optional, so all existing call sites and tests keep compiling. | `lib/app.dart` `MyApp`; `lib/features/home/home_screen.dart` `_MaintenanceItem` 'Settings' |
| D-27829 | The blocking progress is a non-dismissible `showDialog` with `Center(child: CircularProgressIndicator())` — the pattern already in `session_summary_screen.dart:427-430`. No shared progress piece exists (the design system's "Shared pieces and rules per job" table lists none; grep `CircularProgressIndicator` in `lib/widgets` matches no widget), and a raw `AlertDialog` would raise the S-3001 hand-built-dialog ratchet. | D-27823's else-branch; `docs/design_system.md` "Shared pieces and rules per job" |

## Scenarios (core; the architect adds, never removes)

Widget tests on the Mock harness (a fake gateway recording calls, a real `BackupService` over `MockWorkoutRepository`), taps only on Mock (crew rules (bn)).

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-27821 | Settings built on the Mock harness with a service and a gateway | the `DATA` header and both rows show in that order between HEALTH and APPEARANCE; with either null the section is absent | no section (nothing renders there) |
| S-27822 | tapping `Export data` (Mock, fake gateway recording calls) | the gateway is called once with `omnitrain-backup-<today>.json` and the text that `exportToText()` gives; a gateway that returns false or throws shows `Could not export. Try again.` and no dialog | no export flow exists |
| S-27823 | `Import data` with the picker returning null | nothing happens (no dialog, no restore call) | the flow would run `describe` on null text and crash or restore junk |
| S-27824 | a picked text that is not a backup | the refusal reason shows as an error message and no confirmation dialog opens; the data is unchanged | the screen would confirm and restore an invalid file |
| S-27825 | a valid backup text (real `BackupService.describe` on Mock) | `Replace all data?` shows with the date and the counts of the file; `Cancel` (key `data-import-cancel`) never calls restore; `Replace` (key `data-import-confirm`) calls `restoreFromText` once with the picked text | without the dialog the restore runs without a warning, against the owner decision |
| S-27826 | after `Replace` (a real restore, then a refused one: a running workout) | `onDataRestored` is called exactly once, only after the restore returned `restored`; a refused restore shows its reason, calls `onDataRestored` zero times, data unchanged | the app would "succeed" while the data was not restored, or re-enter startup on a refusal |
| S-27827 | while a restore runs (a completer-held fake service) | the blocking progress is shown and a second `Replace`/`Import data` tap starts nothing | a double tap starts two restores racing on the same store |
| S-27828 | `StartupRoot` hosting a fake running app | `AppRestart.of(context).showRestartRequired()` replaces it with `RestoreCompleteScreen` (text `Restore complete`, `Close OmniTrain and open it again to finish. Your data is restored.`, no back button, no route to pop, system back does nothing); the old running app is disposed; the new screen builds without any repository or state object | the old in-memory states stay usable and could write stale data over the restore |
| S-27829 | end to end on Mock: repo A (a finished session via `seedSession`, a routine, a preference) exports; repo B (different data) restores through the Settings flow | after `Replace`, B's stored data equals A's (export equality) and `RestoreCompleteScreen` is showing; the Settings screen is gone | the pieces compose wrong: a section without a gateway, a restore that does not replace, or a screen that stays on old data |
| S-27830 | `PlatformBackupFileGateway` with injected seams for the plugin calls | `shareText` passes UTF-8 bytes, the file name and `application/json`; `pickText` decodes bytes to text and returns null for a cancelled pick (the plugin classes are not called in the test) | the gateway mis-encodes the file name or bytes and no test can see it without the real plugins |
| S-27831 | Settings at 390x844 with the new section | scrolls with no overflow (measured with a probe, not assumed); both rows have semantic labels | the two new rows overflow or are invisible to assistive tech |
| S-27832 | source-text scan of `lib/` and the new gateway file | `backup_file_gateway.dart` has no `dart:io` import; no file in `lib/features`, `lib/state`, `lib/widgets` imports `share_plus` or `file_picker` directly | a plugin import leaks past the gateway and web stops compiling (CLAUDE.md "web and native safe") |
| S-27833 | a backup whose `BackupInfo.exportedAtMs` is `DateTime(2026, 11, 19, 23, 30).millisecondsSinceEpoch` (device local), 142 sessions, 6 routines | the confirmation body reads `This replaces everything on this phone with the backup from 19 Nov 2026: 142 workouts, 6 routines. Your current data is not kept. This cannot be undone.` (one line, D-27826's copy) | the dialog cannot render the file's date and counts, so the user confirms blind |
| S-27834 | a fake service whose `exportToText()` throws | `Could not export. Try again.` shows as an error message, the gateway is not called, no dialog opens | the await escapes the handler unhandled and the row does nothing visible |
| S-27835 | a picked text whose `dataVersion` is `currentDataVersion + 1` (a backup written by a newer build — the real writer on the other phone) | the newer-app reason (`BackupService.newerAppMessage`) shows as an error message, no confirmation dialog, no restore call, data unchanged | the screen would confirm a file the engine refuses |
| S-27836 | after the S-27829 restore, the Mock harness `restart()`s and the next launch's flag read runs (`runStartup` reads `onboarding_complete` at `lib/main.dart:288`) | the flag equals the backup's value (the fixture carries `onboarding_complete` = false, so onboarding shows next launch) | the restored preferences never reach the next launch's decisions (D-27824, 278a D-27804) |

Widget-test fakes: the fake gateway implements `BackupFileGateway` and records calls; a fake service may `extends BackupService` (its instance methods are non-final) overriding `exportToText`/`describe`/`restoreFromText`, constructed over `MockWorkoutRepository` and `const AppVersionInfo(version: '0.0.0', build: '0')`; the completer-held fake of S-27827 holds `restoreFromText` until the test resolves it. Everything else uses the real `BackupService`.

## Input-reality checklist

1. Writers: the screen reads nothing stored itself; the backup text comes from 278a. The preferred-units setting does not affect the file (stored canonical).
2. Lifecycle: restore while a workout runs is refused by the service (278a S-27807); restore with the watch connected: the next launch resends reference data to the wrist as at any launch (state this in Docs; device check: owner step); the profile photo is not restored.
3. Settings: the restore replaces Settings values in the store; the app shows the restore-complete screen, so no state object keeps the old values; theme and the rest are read again at the next launch (`OmniTheme.activeTheme` at startup).
4. Time: the date in the dialog and the file name use the device's local date format already used in Settings/Calendar — named in D-27827 (a screen-local month-name-table helper, no `intl` in the app), fixture S-27833; the file name is `BackupService.fileName(DateTime.now())` (278a S-27811).
5. Cost: one export read per Export tap; one `describe` parse plus one restore parse per Import — the service parses twice (`BackupService.describe` and `restoreFromText` each call `inspect` → `decodeBackup`, backup_service.dart this run) and 278a exposes no reuse API, so the screen pays two parses and no state holds the decoded snapshot; adding a reuse API is out of this plan's scope.
6. Words: stale terms found by grep over `docs/` (excluding `docs/plans`, `docs/history`, `docs/releases`) this run: `export-data` only in `docs/theme_and_settings.md:152` (the Removed Surface sentence — MODIFIED row in the Docs delta); the Settings section-list sentence at `docs/theme_and_settings.md:96` and the `SettingsScreen` row at `docs/navigation_and_screens.md:203` (MODIFIED rows). `docs/db_integration.md` contains no `no export` mention — the seed's claim was wrong (its only `importer` phrases, db_integration.md:251 and :441, are the future SQL importer, unrelated) — so this line replaces the seeded claim and no db_integration.md REMOVED row exists.
7. Competition: Settings section order is fixed by D-27822; no other card competes.

## Phases (serial)

- **P0 scout** DONE (`.work/crew/2026-11-19-278/pointers3.md`): in-process restart rejected, see D-27824.
- **P1 gateway + packages** (lead adds the packages first; `crew-builder-app` scope `lib/core/services/backup_file_gateway.dart`, `test/backup_file_gateway_test.dart`): D-27821; S-27830, S-27832.
- **P2 restore-complete screen** (scope `lib/app/startup_root.dart`, `lib/features/startup/restore_complete_screen.dart` (new), `test/restore_complete_screen_test.dart`): D-27824; S-27828. The lead creates `lib/features/startup/` if missing (it exists).
- **P3 Settings section** (scope `lib/features/settings/settings_screen.dart`, `lib/app.dart` and the one call site that builds `SettingsScreen`, `test/settings_data_section_test.dart`): D-27822, D-27823, D-27825, D-27826; S-27821..S-27827, S-27831. Split into 3a (rows and export, S-27821, S-27822, S-27831) and 3b (import flow, S-27823..S-27827) if over 8 items.
- **P4 end to end** (scope `test/backup_restore_end_to_end_test.dart`): S-27829.
- **P5 docs** (`crew-docs-keeper`): the Docs delta table.

## Feature invariants

- The DATA section renders only when both `backupService` and `backupFileGateway` are injected (D-27822; S-27821).
- Every failure is plain words through `OmniMessage.errorOn` — `Could not export. Try again.`, the service's refusal reason, `Could not restore. Nothing was changed.` — never exception text (D-27823; S-27822, S-27824, S-27826).
- A refused or failed import leaves the store byte-identical and never calls `onDataRestored` (D-27825; S-27824, S-27826, S-27835).
- After a successful restore the old app tree is replaced by `RestoreCompleteScreen`, which touches no repository or state object, and the next launch re-runs startup over the restored store (D-27824; S-27828, S-27829, S-27836).
- The share and picker plugins are imported only in `lib/core/services/backup_file_gateway.dart` (D-27821; S-27832).
- The confirmation dialog is destructive-styled, and a barrier tap or system back counts as `Cancel` (D-27823; S-27825).
- Dates in the dialog and the file name use the device's local date (D-27827; S-27833).

## Existing-functionality impact

| Touched surface | What already reads it (searched this run) | Effect | Guarded by |
|---|---|---|---|
| `SettingsScreen` ctor (settings_screen.dart:48) | production: `lib/features/home/home_screen.dart:1142` only (grep `SettingsScreen(` in lib — the hub_sheet.dart hits of `docs/history/route-migration-audit.md` are gone from lib; glob `lib/**/hub_sheet.dart` matches nothing). Tests: 11 files, listed under Readers | three optional params; every call site keeps compiling | S-27821 |
| `MyApp` ctor (lib/app.dart:65) | `lib/main.dart:469`; `test/screen_widget_test.dart:2908`; `test/app_theme_reactive_test.dart:67`; `test/diagnostics_wiring_source_test.dart:69` (a source scan for the substring `return MyApp(` — substring-only, unaffected) | three optional params | S-27821 |
| Settings build list (section order, settings_screen.dart:132-184) | `test/header_standardization_test.dart:1180` scrolls to each of PREFERENCES..APPEARANCE and asserts `findsOneWidget` — it does not assert the set is closed, and it builds the screen without the new dependencies, so DATA is absent there; `docs/theme_and_settings.md:96` describes the grouping | DATA inserted between HEALTH and APPEARANCE shifts APPEARANCE down (scroll handles it; never a weaker assertion — the plan-208 precedent) | S-27821, S-27831 |
| `StartupRoot` build (startup_root.dart `_StartupRootState.build`) | `lib/main.dart:238` (`runApp(StartupRoot(startupRunner: _runStartup))`); `test/startup_failure_screen_test.dart:339,379,408`; `test/health_active_energy_startup_wiring_test.dart:87,112` | the succeeded branch's child gains an `AppRestart` inherited widget; the preparing and failed surfaces are untouched | S-27828 |
| `runStartup` (lib/main.dart:262-541) | the two runStartup test files above | `BackupService` + gateway created after `appVersionInfo`; passed to `MyApp` | S-27821 |
| `pubspec.yaml` dependencies | `share_plus`, `file_picker` absent today (grep this run); `cross_file` already transitive (pubspec.lock:156-165) | the lead adds both packages, runs pub get and pod install, reverts `project.pbxproj` noise per crew rules (aj); only `backup_file_gateway.dart` imports them | S-27832, acceptance iOS build |

## Readers

Every reader of a contract this plan adds or changes (grep by symbol and literal this run):

- `SettingsScreen` (+3 optional params): `lib/features/home/home_screen.dart:1142`; test constructors `test/settings_scroll_stability_test.dart:37`, `test/settings_sounds_test.dart:31..571` (20), `test/health_platform_test.dart:1487`, `test/settings_diagnostics_watch_log_test.dart:225`, `test/screen_widget_test.dart:240,303,340`, `test/settings_watch_status_test.dart:104`, `test/header_standardization_test.dart:630,1188`, `test/settings_diagnostics_test.dart:306`, `test/interaction_flow_test.dart:1314..1440` (5), `test/health_active_energy_settings_screen_test.dart:67`, `test/screen_overflow_contract_test.dart:182`. All compile unchanged (optional params); P3a's Done runs the two heaviest consumers.
- `MyApp` (+3 optional params): `lib/main.dart:469`, `test/screen_widget_test.dart:2908`, `test/app_theme_reactive_test.dart:67`, `test/diagnostics_wiring_source_test.dart:69`. In P3a's scope (main.dart, app.dart).
- `AppRestart` (new): `lib/app/startup_root.dart` (owner), `lib/features/home/home_screen.dart` (the `onDataRestored` closure), `test/restore_complete_screen_test.dart`, `test/settings_data_section_test.dart`, `test/backup_restore_end_to_end_test.dart`. Existing `StartupRoot` consumers keep compiling (no ctor change); they are P2's Done files.
- `BackupFileGateway`/`PlatformBackupFileGateway` (new): `lib/main.dart` (`runStartup`), `lib/features/settings/settings_screen.dart` (both flows), `test/backup_file_gateway_test.dart`, `test/settings_data_section_test.dart`, `test/backup_restore_end_to_end_test.dart`.
- The literals `share_plus`/`file_picker`: `pubspec.yaml` (lead) and `lib/core/services/backup_file_gateway.dart` only (S-27832).
- `RestoreCompleteScreen` (new): `lib/app/startup_root.dart`, `test/restore_complete_screen_test.dart`, `test/backup_restore_end_to_end_test.dart`.
- The literals `DATA`, `data-import-cancel`, `data-import-confirm`: `settings_screen.dart`, `test/settings_data_section_test.dart`, `docs/theme_and_settings.md` (P5).
- `BackupService.fileName`, `BackupService.describe`, `BackupService.restoreFromText`, `BackupService.newerAppMessage`, `BackupRestoreResult.isRestored` (278a's contracts): the screen and the three new test files.

## Phases expanded

All phases are one agent run each; serial order P1 → P2 → P3a → P3b → P4 → P5, except: **P2 may run in parallel with P1** — disjoint write scopes (`lib/app/startup_root.dart`, `lib/features/startup/` vs `lib/core/services/`) and no shared symbol (P2 imports neither the gateway nor the packages). P3a must wait for both (it imports `BackupFileGateway` and `AppRestart`); P3b extends P3a's file so it must wait; P4 consumes P3b's flow; P5 documents symbols P1-P4 create.

### P1 gateway + packages — crew-builder-app (the lead first: add `share_plus` and `file_picker` with `flutter pub add`, run pub get and pod install, revert `project.pbxproj` noise per crew rules (aj); the builder cannot)

Write scope: `lib/core/services/backup_file_gateway.dart` (new), `test/backup_file_gateway_test.dart` (new). Decisions D-27821. Scenarios S-27830, S-27832.

1. [ ] Add abstract `BackupFileGateway` (`Future<bool> shareText({required String fileName, required String text})`, `Future<String?> pickText()`) — lib/core/services/backup_file_gateway.dart · `BackupFileGateway`
2. [ ] Add `PlatformBackupFileGateway` with injectable seams (share and pick function fields defaulting to the share_plus / file_picker calls): share sends `XFile.fromData(utf8.encode(text), name: fileName, mimeType: 'application/json')`; pick uses `withData: true` and decodes UTF-8; no `dart:io` import — lib/core/services/backup_file_gateway.dart · `PlatformBackupFileGateway`
3. [ ] Test S-27830: the share seam receives the UTF-8 bytes, the file name and the mime; pick decodes bytes to text; a cancelled pick returns null; the plugin classes are not constructed in the test — test/backup_file_gateway_test.dart · S-27830
4. [ ] Test S-27832: source-text guard — the gateway file has no `dart:io` import; no file under `lib/features`, `lib/state`, `lib/widgets` imports `share_plus` or `file_picker` — test/backup_file_gateway_test.dart · S-27832

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/backup_file_gateway_test.dart`; `flutter analyze` at the 176/0 baseline. Predicted files: exactly the two in scope. Guard proof: the file is new, so prove-red at the base commit is impossible; mutations (a)-(c) below kill S-27830/S-27832.

### P2 restore-complete screen — crew-builder-app (may run in parallel with P1)

Write scope: `lib/app/startup_root.dart`, `lib/features/startup/restore_complete_screen.dart` (new), `test/restore_complete_screen_test.dart` (new). Decision D-27824. Scenario S-27828. (`lib/features/startup/` exists: `startup_preparing_screen.dart`, `startup_failure_screen.dart`.)

1. [ ] Add `RestoreCompleteScreen`: the two static texts, no back button, `PopScope(canPop: false)` so system back does nothing; builds with no repository or state object — lib/features/startup/restore_complete_screen.dart · `RestoreCompleteScreen`
2. [ ] Add `AppRestart` inherited widget exposing `showRestartRequired()`; `_StartupRootState` owns it and the succeeded branch of `build` wraps the running app in it, so any pushed route's context finds it — lib/app/startup_root.dart · `AppRestart`, `_StartupRootState.build`
3. [ ] Add `showRestartRequired()`: setState replaces the running app with `RestoreCompleteScreen` (the old tree unmounts and its States dispose) — lib/app/startup_root.dart · `_StartupRootState.showRestartRequired`
4. [ ] Test S-27828: a fake running app under `StartupRoot`; `showRestartRequired()` swaps it; the two texts render; no back button and no route to pop; system back does nothing; the fake app's State records `dispose`; the new screen builds without any repository or state object — test/restore_complete_screen_test.dart · S-27828

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/restore_complete_screen_test.dart test/startup_failure_screen_test.dart` (the `StartupRoot` consumers stay green); analyze baseline. Predicted files: exactly the three in scope. Guard proof: mutations (d) `showRestartRequired` keeps `_runningApp` mounted (no setState) → S-27828 red; (e) `RestoreCompleteScreen` allows pop → S-27828 red.

### P3 Settings section — crew-builder-app (after P1 and P2)

Scope: `lib/features/settings/settings_screen.dart`, `lib/app.dart`, `lib/features/home/home_screen.dart`, `lib/main.dart`, `test/settings_data_section_test.dart` (new). Decisions D-27822, D-27823, D-27825, D-27826, D-27827, D-27828, D-27829.

#### P3 part a — rows and export (S-27821, S-27822, S-27831, S-27834)

1. [ ] SettingsScreen ctor gains optional `BackupService? backupService`, `BackupFileGateway? backupFileGateway`, `VoidCallback? onDataRestored` — lib/features/settings/settings_screen.dart · `SettingsScreen`
2. [ ] Add `_DataSection`: `OmniCardHeader(title: 'DATA')` after HEALTH, before APPEARANCE; the `Export data` row (trailing `Share`) and the `Import data` row (trailing `Choose file`) on the `_SettingsRow` pattern, each carrying a semantic label (extend `_SettingsRow` with an optional `semanticsLabel` that wraps the content in `Semantics`); the section and header are absent when `backupService` or the gateway is null — lib/features/settings/settings_screen.dart · `_DataSection` (the build list)
3. [ ] Add `_exportData()`: `gateway.shareText(fileName: BackupService.fileName(DateTime.now()), text: await backupService.exportToText())`; on false or a thrown error `OmniMessage.errorOn(messenger, theme, 'Could not export. Try again.')` and no dialog; mounted checks after every await — lib/features/settings/settings_screen.dart · `_DataSection._exportData`
4. [ ] `MyApp` gains the three optional params and forwards them to `HomeScreen` — lib/app.dart · `MyApp`
5. [ ] `HomeScreen` gains the three optional params and forwards them at the `SettingsScreen(` call site (home_screen.dart:1142, the 'Settings' `_MaintenanceItem`) with `onDataRestored: AppRestart.of(context).showRestartRequired` — lib/features/home/home_screen.dart · `HomeScreen`
6. [ ] `runStartup` creates `BackupService(repository, appVersionInfo)` and `PlatformBackupFileGateway()` after `appVersionInfo` resolves and passes them to `MyApp` — lib/main.dart · `runStartup`
7. [ ] Test S-27821: with both dependencies the header and both rows render between HEALTH and APPEARANCE; with either null the section is absent — test/settings_data_section_test.dart · S-27821
8. [ ] Tests S-27822 + S-27831 + S-27834: the gateway is called once with `BackupService.fileName(DateTime.now())`'s value and the `exportToText()` text; a false-returning and a throwing gateway each show `Could not export. Try again.` with no dialog; the 390x844 probe scrolls with no overflow; both rows carry semantic labels — test/settings_data_section_test.dart · S-27822, S-27831, S-27834

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/settings_data_section_test.dart test/header_standardization_test.dart test/screen_overflow_contract_test.dart test/settings_sounds_test.dart` (the heaviest existing `SettingsScreen(` consumers stay green); analyze baseline. Predicted files: exactly the five in scope. Guard proof: mutations (f) the section renders with a null dependency → S-27821 red; (g) `_exportData` swallows the gateway result without a message → S-27822/S-27834 red; (h) the rows lose their semantic labels → S-27831 red.

#### P3 part b — import flow (S-27823, S-27824, S-27825, S-27826, S-27827, S-27833, S-27835)

1. [ ] Add `_importData()` in D-27825's order: `pickText()`; null returns doing nothing; `describe(text)` null shows the refusal reason and returns; otherwise `ConfirmationDialog.showTwoChoice(title: 'Replace all data?', body: the D-27826 date-and-counts line via D-27827's helper, dismissKey `data-import-cancel`, confirmKey `data-import-confirm`, isDestructive: true)` — lib/features/settings/settings_screen.dart · `_DataSection._importData`
2. [ ] Blocking progress: non-dismissible `showDialog` with `Center(child: CircularProgressIndicator())` (D-27829), popped when `restoreFromText` returns — lib/features/settings/settings_screen.dart · `_DataSection._importData`
3. [ ] `_importInFlight` guard: a second `Replace`/`Import data` tap while a restore runs starts nothing; mounted checks after every await — lib/features/settings/settings_screen.dart · `_DataSection._importData`
4. [ ] On `isRestored`: pop the progress, call `onDataRestored` exactly once; on refusal: pop the progress, show the reason as an error message, call it zero times; the data was never touched by the screen — lib/features/settings/settings_screen.dart · `_DataSection._importData`
5. [ ] Test S-27823: the picker returns null → no dialog, no restore call — test/settings_data_section_test.dart · S-27823
6. [ ] Tests S-27824 + S-27833 + S-27835: a text that is not a backup shows the reason with no dialog and unchanged data; the D-27826 confirmation body with the S-27833 fixture reads verbatim; a `currentDataVersion + 1` backup shows `BackupService.newerAppMessage` and restores nothing — test/settings_data_section_test.dart · S-27824, S-27833, S-27835
7. [ ] Test S-27825: `Cancel` never calls restore; `Replace` calls `restoreFromText` once with the picked text — test/settings_data_section_test.dart · S-27825
8. [ ] Tests S-27826 + S-27827: `onDataRestored` fires exactly once and only after `restored`; a refused restore shows the reason with zero calls and unchanged data; the completer-held fake shows the progress and a second tap starts nothing — test/settings_data_section_test.dart · S-27826, S-27827

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/settings_data_section_test.dart`; analyze baseline. Predicted files: exactly the two in scope. Guard proof: mutations (i) a null `describe` proceeds to the dialog → S-27824 red; (j) Cancel (or a barrier tap) calls restore → S-27825 red; (k) `onDataRestored` fires before the restore resolves or on refusal → S-27826 red; (l) the `_importInFlight` guard removed → S-27827 red; (m) the progress dialog becomes dismissible → S-27827 red.

### P4 end to end — crew-builder-app (after P3b)

Write scope: `test/backup_restore_end_to_end_test.dart` (new). Scenario S-27829, S-27836.

1. [ ] Test S-27829 on the Mock harness: repo A (a finished session via `seedSession`, a routine template through the real template write, a preference via `setPreferenceString`) exports through `exportToText`; repo B (different data) restores through the Settings flow (`Import data` → `Replace`); after `Replace`, B's `exportSnapshot()` equals A's, `RestoreCompleteScreen` is showing, and the Settings screen is gone — test/backup_restore_end_to_end_test.dart · S-27829
2. [ ] Test S-27836: the fixture's backup carries `onboarding_complete` = false; after the restore, `restart()` the harness and read `getPreferenceBool('onboarding_complete')` — the value the next launch's `runStartup` reads at lib/main.dart:288 — test/backup_restore_end_to_end_test.dart · S-27836

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/backup_restore_end_to_end_test.dart`; analyze baseline. Predicted files: exactly the one in scope. Guard proof: mutation (n) `onDataRestored` wired to a no-op → S-27829 red (`RestoreCompleteScreen` never shows); mutation (o) drop `onboarding_complete` from the carried meta keys (a 278a-side edit) → S-27836 red.

### P5 docs — crew-docs-keeper (last)

Write scope: `docs/theme_and_settings.md`, `docs/navigation_and_screens.md`, `docs/db_integration.md`. Items are the Docs delta table's rows.

1. [ ] Add the `Data: export and import` subsection (the DATA rows, the share/picker flow, the replace warning and its copy, the restart-required behaviour; every behaviour sentence names its test) — docs/theme_and_settings.md · `Data: export and import`
2. [ ] Rewrite the section-list sentence so the row-4 New marker stands on one line — docs/theme_and_settings.md · "The screen groups preferences..."
3. [ ] Rewrite the Removed Surface sentence so the row-5 New marker stands on one line and the old marker is gone — docs/theme_and_settings.md · "does not include account-management rows"
4. [ ] Mention the DATA section in the `SettingsScreen` row so the row-6 New marker stands on one line — docs/navigation_and_screens.md · `SettingsScreen` row
5. [ ] Add the `Backup file` cross-link sentence to the Settings flow so the row-7 New marker stands on one line — docs/db_integration.md · `Backup file`
6. [ ] Verify every behaviour sentence names an existing test and the file stays under the 52 KB ceiling — docs/theme_and_settings.md
7. [ ] Run plan-lint after mode and the symbol-existence checks — `test/docs_indexing_contract_test.dart`

Done: `.github/copilot/scripts/macos/gateway.sh test -- test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`. Requires P1-P4 done (the named symbols must exist).

## Docs delta (seed; the architect completes it from the stale-term sweep)

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/theme_and_settings.md` | ADDED | - | `Data: export and import` | D-27822, S-27825 |
| `docs/navigation_and_screens.md` | ADDED | - | `DATA section` | D-27822 |
| `docs/db_integration.md` | ADDED | - | `export and import from Settings` | D-27824 |
| `docs/theme_and_settings.md` | ADDED | - | The screen groups preferences, sound and alert behaviour, data export and import | D-27822, S-27821 |
| `docs/theme_and_settings.md` | MODIFIED | does not include account-management rows such as sign-in, export-data, or account-removal actions | does not include account-management rows such as sign-in or account-removal actions; data export and import live in the DATA section | D-27826, S-27821 |
| `docs/navigation_and_screens.md` | MODIFIED | appearance theme selector, and a low-emphasis version footer | appearance theme selector, the DATA export and import rows, and a low-emphasis version footer | D-27822, S-27821 |

Stale-term sweep (architect, this run) over `docs/` excluding `docs/plans`, `docs/history`, `docs/releases`: grep `export-data|no export|export data|import data|backup` and `Clipboard|share sheet` found exactly the three MODIFIED rows above and no further false claim. `docs/db_integration.md` has no `no export` mention (its `importer` phrases at :251 and :441 are the future SQL importer). `docs/state_management/watch_diagnostics.md:116` (the Diagnostics `Copy` row) stays true. In "after" mode the keeper must copy each New marker cell's text verbatim onto one line of the target doc (plan-lint strips only the outermost backticks); the ADDED rows' markers are phrases the keeper must also place literally on one line.

## Mutation list (lead)

- (a) `PlatformBackupFileGateway.shareText` drops the file name or the mime type → S-27830 red.
- (b) `PlatformBackupFileGateway.pickText` returns the raw bytes instead of decoded text (or empty instead of null on cancel) → S-27830 red.
- (c) `backup_file_gateway.dart` gains `import 'dart:io';` → S-27832 red.
- (d) `_StartupRootState.showRestartRequired` keeps `_runningApp` mounted (no setState) → S-27828 red.
- (e) `RestoreCompleteScreen` allows pop (`PopScope(canPop: true)` / a back button) → S-27828 red.
- (f) `_DataSection` renders with a null `backupService` or gateway → S-27821 red.
- (g) `_exportData` swallows a false/throwing gateway without a message → S-27822 and S-27834 red.
- (h) the two rows lose their `Semantics` labels → S-27831 red.
- (i) a null `describe` proceeds to the confirmation dialog → S-27824 red.
- (j) Cancel (or a barrier tap) reaches `restoreFromText` → S-27825 red.
- (k) `onDataRestored` fires before the restore resolves or on refusal → S-27826 red.
- (l) the `_importInFlight` guard removed → S-27827 red.
- (m) the progress dialog becomes barrier-dismissible → S-27827 red.
- (n) `onDataRestored` wired to a no-op → S-27829 red.
- (o) `onboarding_complete` dropped from the carried meta keys (a 278a-side edit) → S-27836 red.

## Open items for the owner

1. After `Replace` the app shows `Restore complete` and asks you to close and reopen it (an in-process restart would leave the old watch link, audio players and listeners running twice; decided on the scout's evidence). The restored data appears at the next launch.
2. Owner device checks: export on the phone, import on a second phone or after deleting a workout (QA step to be added by the docs keeper), watch reconnect after a restore.

## Progress

- [x] Seeded (goal, ledger D-27821..D-27826, scenarios S-27821..S-27832, Input-reality answers, phase outline, Docs delta seed)
- [x] Lead: `share_plus` + `file_picker` added to pubspec.yaml, pub get + pod install run, `project.pbxproj` noise reverted (before P1)
- [x] P1 gateway (item 1 abstract `BackupFileGateway`)
- [x] P1 gateway (item 2 `PlatformBackupFileGateway` with seams, no `dart:io`)
- [x] P1 gateway (item 3 test S-27830)
- [x] P1 gateway (item 4 test S-27832)
- [x] P2 restore-complete screen (item 1 `RestoreCompleteScreen`)
- [x] P2 restore-complete screen (item 2 `AppRestart` inherited widget)
- [x] P2 restore-complete screen (item 3 `showRestartRequired`)
- [x] P2 restore-complete screen (item 4 test S-27828)
- [x] P3a rows and export (items 1-2: ctor params, `_DataSection` with semantic labels)
- [x] P3a rows and export (item 3: `_exportData`)
- [x] P3a rows and export (items 4-6: `MyApp`, `HomeScreen`, `runStartup` wiring)
- [x] P3a rows and export (items 7-8: tests S-27821, S-27822, S-27831, S-27834)
- [x] P3b import flow (items 1-4: `_importData`, progress, guard, restore handling)
- [x] P3b import flow (items 5-8: tests S-27823, S-27824, S-27833, S-27835, S-27825, S-27826, S-27827)
- [x] P4 end to end (item 1 test S-27829)
- [x] P4 end to end (item 2 test S-27836)
- [x] P5 docs (items 1-5: the seven Docs delta rows' markers applied)
- [x] P5 docs (items 6-7: test-named sentences, 52 KB ceiling, plan-lint after, docs contract tests)
- [x] Lead: full-suite compare against the base failing set; analyze at 176/0; iOS build after the packages (acceptance)
- [ ] (owner) Open items 1-2

## Assumption Log

| ID | Assumption | Resolution |
|---|---|---|
| A-1 | The restart after a restore is a Restore-complete screen (close and reopen), not an in-process restart: a second `runStartup` doubles the diagnostics observer, audio players, repository listeners and the watch stream (scout 3). | Decided by the lead, owner told |
| A-2 | `lib/app/startup_root.dart` was edited by the lead: it is outside `crew-builder-app`'s write ceiling (`lib/app.dart` is listed, `lib/app/**` is not). | Recorded |
| A-3 | No shared progress piece exists, so the blocking progress is a bare non-dismissible `showDialog` (D-27829). | Recorded |
| A-4 | iOS simulator build with the two new packages: `flutter build ios --simulator --no-codesign -d <iPhone 17 Pro>` succeeded (Runner.app built). Not run on a device. | Owner device check |

## Open questions

1. The seeded Input-reality line 6 claimed a `no export` mention in `docs/db_integration.md`; grep this run (pattern `export-data|no export|export data|import data|backup` over docs/ excluding plans/history/releases) finds none. Line 6 was replaced per the brief's item 4; the seeded Docs delta rows are untouched.
2. No shared `d MMM yyyy` date helper exists (`grep DateFormat|intl` in lib/: no matches; the nearest forms are `ChartAxisHelper.formatDateLabel` = `MMM d` at chart_axis_helper.dart:161 and the private `_formatDate` copies at session_summary_screen.dart:1429 and effort_rating_sheet.dart:96). Appended D-27827 defines a screen-local helper with the month-name table; if the owner prefers `Nov 19, 2026` order, only the dialog body changes.
3. No shared progress piece exists in the widget catalog (the design system's shared-pieces table lists none; grep `CircularProgressIndicator` in `lib/widgets` matches no widget), so D-27823's else-branch (D-27829) is confirmed rather than a choice left open.
4. PR scope budget: five implementation phases (P3 counts as one phase split into runs a/b; P0 is the done scout), one track (phone `lib/` + docs; no watch or sync-contract file), 10 decisions (6 seeded + 4 appended), 16 scenarios, and about 470 predicted production lines (gateway ~80, restore screen ~80, startup_root ~80, settings section ~200, wiring ~30). No hard or soft split trigger of `.github/copilot/pr-scope-budget.md` fires; the plan is far under the plan-size limit; the split notes under P3 already exist in the seed.
5. S-27835's "newer backup" fixture is not producible by this app's writer (it refuses newer files by design); it models the real writer on a newer install, matching 278a S-27806's fixture rule.
6. The seeded P2 note "`lib/features/startup/` if missing (it exists)" was verified this run: the directory holds `startup_preparing_screen.dart` and `startup_failure_screen.dart`.
7. The seeded ADDED rows' New markers are descriptive, not literal phrases: row 2 (`Settings` row mentions the DATA section) and row 3 (`Backup file` cross-link to the Settings flow) name an edit, and plan-lint after-mode needs a marker that stands verbatim on one line of the doc. The keeper's P5 items 1, 4 and 5 say what to write; if plan-lint after-mode rejects a seeded marker, the governor should accept the row with the literal sentence the keeper wrote (e.g. for row 2, a `Settings` row phrase containing `DATA section`).
8. The S-27831 overflow probe lives in the new `test/settings_data_section_test.dart`, not in `test/screen_overflow_contract_test.dart` (which builds `SettingsScreen` without the new dependencies and would need its constructor call edited — out of P3's spirit of additive change; noted for the owner).
