# Settings Version Row — Live Build Metadata

## Status: 🚧 In progress

### Phase 0 Complete ✓

## Phase Match
TRIVIAL — single-screen, no schema change, no new state, no new behavior. The bug is a hardcoded UI string; the fix is one dynamic render.

## Overview

`SettingsScreen` ships a hardcoded `'Version 1.0.0'` footer text. The first version bump will silently leave this stale and mislead users when filing bug reports. This plan replaces the literal with metadata sourced from the live build (`pubspec.yaml` → compiled into the native bundle by Flutter, surfaced at runtime via `package_info_plus`), and renders the standard `Version X.Y.Z (N)` format. Visual placement, copy phrasing, and styling stay byte-identical apart from the value.

## Requirements

- `SettingsScreen` displays `'Version $version ($build)'` using the installed build's actual version + build number.
- Source = `package_info_plus`'s `PackageInfo.fromPlatform()`, resolved once at app startup (cached because version metadata is static for the lifetime of the process).
- No fallback constants. If the metadata load fails on a platform, the literal `Version 1.0.0 (1)` is never shown — instead we render an empty footer placeholder (a centered, low-emphasis spacer that preserves layout). Console logs the error for diagnostics.
- One new constructor argument on `SettingsScreen`: `AppVersionInfo appVersion`. Default value supplied so the 8+ existing test sites that instantiate `SettingsScreen` without that argument do not break.
- `MyApp` and `main.dart` are the sole load point: read `package_info_plus` at startup, pass through the constructor chain (no global mutable singleton, no async `FutureBuilder` inside the screen).
- All existing test sites that assert `'Version 1.0.0'` are updated to inject a stub `AppVersionInfo` and assert the new format instead.

## Acceptance Criteria

- [ ] The Settings version row displays the version and build number of the installed build, matching the values the app was built with.
- [ ] The displayed format is exactly `Version X.Y.Z (N)` (version dot-separated, build number in parentheses).
- [ ] Changing `pubspec.yaml` `version:` line and rebuilding changes the row with no source-code edit.
- [ ] No literal version string remains anywhere in `lib/features/settings/`.
- [ ] Row position and styling in Settings are visually unchanged (same `Center`, same padding, same `labelMedium`/textMuted token, same `FontWeight.w500`).
- [ ] No hardcoded `1.0.0`, `1.0.0+1`, or similar version literal lives in any committed file outside `pubspec.yaml` after the change.

## Scenarios

```
### S-001: Settings row reflects injected version + build
- Trigger: Open the Settings screen with a stub `AppVersionInfo(version: '2.3.4', build: '42')`.
- Precondition: `SettingsScreen` is rendered through `pumpWidget` with a `MaterialApp.home`.
- Flow: Settle the widget tree. Scroll to the bottom of the `ListView`.
- Expected outcome: The footer text widget reads exactly `Version 2.3.4 (42)`. No other string is rendered in the footer slot.
- Edge case of: none

### S-002: Different injected value overrides any literal
- Trigger: Open the Settings screen with a different stub `AppVersionInfo(version: '9.8.7', build: '6')`.
- Precondition: Same as S-001.
- Flow: Settle and scroll to the footer.
- Expected outcome: Footer text reads exactly `Version 9.8.7 (6)`. If a hardcoded literal like `1.0.0` ever appears in this row instead, the test fails (locks in "sourced from metadata, never from a constant").
- Edge case of: S-001

### S-003: Production wiring reads from the real bundle
- Trigger: App launch in `main.dart`.
- Precondition: `package_info_plus` resolves successfully on the target platform.
- Flow: `main()` reads `PackageInfo.fromPlatform()` into an `AppVersionInfo`, threads it through `MyApp` → `HomeScreen` → `SettingsScreen` construction.
- Expected outcome: At runtime, the published version of the package (whatever `pubspec.yaml` declared at build time) and the build number are observable by toggling the field; the screen never displays a literal.
- Edge case of: none
```

## Iteration 1

### Core Changes
- New tiny immutable model `lib/core/models/app_version_info.dart`:
  - `class AppVersionInfo { final String version; final String build; const AppVersionInfo({required this.version, required this.build}); }`
  - Pure Dart — no Flutter, no IO, no `dart:io`, no platform plugin.
  - Source of truth: build metadata from `package_info_plus`. No serialization / `fromMap`/`toMap` needed — this is a process-local value object.
- Add `package_info_plus` to `pubspec.yaml` under `dependencies`. (Latest 8.x supports Dart SDK 3.x.)

### Backend Changes (main.dart + app.dart wiring)
- `main.dart`: after constructing `settingsState`, await `PackageInfo.fromPlatform()` and create `AppVersionInfo(version: info.version, build: info.buildNumber)`.
- `main.dart`: pass the new `appVersion` into `MyApp`.
- `app.dart`: `MyApp` accepts `final AppVersionInfo appVersion` (required). Threads it into `HomeScreen` (`appVersion: widget.appVersion`).
- `lib/features/home/home_screen.dart`: `HomeState`-shaped constructor receives `appVersion` (already huge — add the parameter in positional order alongside the existing injected services). Forward to `SettingsScreen(appVersion: widget.appVersion, ...)`.
- `lib/widgets/hub/hub_sheet.dart` (the second `SettingsScreen` construction site): receive `appVersion` from its existing constructor — the sheet already takes `settingsState`, `timerAlertService`, etc., so append `appVersion` and forward to `SettingsScreen`.
- `lib/features/home/home_screen_backup.dart`: identical wiring change so the archive file stays buildable.
- `SettingsScreen`:
  - Add `final AppVersionInfo appVersion;` field.
  - Add a default-on-all-defaults variant: `AppVersionInfo appVersion = const AppVersionInfo(version: '1.0.0', build: '1')` is **NOT** acceptable (locked-out by acceptance criteria "no hardcoded version string remains"). Instead, the parameter is **required** with no default, but every internal test in the repo that constructs the screen already accepts an extra constructor argument surface, so test sites are updated. The one production construction is via `MyApp`.
  - Render `'Version ${appVersion.version} (${appVersion.build})'` in the same `Center` + `Padding` + `Text` slot. Same `labelMedium` style with `OmniTheme.colors.textMuted`.

### Frontend Changes
- One widget edit in `lib/features/settings/settings_screen.dart` — replace the literal in line 215 area with the formatted dynamic string. Visual frame unchanged.

### Implementation Steps

1. Author the `AppVersionInfo` model.
2. Run `flutter pub add package_info_plus` (or hand-edit `pubspec.yaml` + `flutter pub get`) and verify resolved.
3. Update `main.dart` to await `PackageInfo.fromPlatform()` and construct `AppVersionInfo`.
4. Add `appVersion` to `MyApp`.
5. Forward `appVersion` through `HomeScreen` → `SettingsScreen`.
6. Forward `appVersion` through `HubSheet` → `SettingsScreen`.
7. Forward `appVersion` through `home_screen_backup.dart` (compile-fixes the archive file).
8. Replace the `Text('Version 1.0.0', ...)` in `SettingsScreen` with the dynamic expression.
9. Update `test/screen_widget_test.dart` S-001 to inject `AppVersionInfo` and assert `Version 2.3.4 (42)`.
10. Add new test S-002 injecting `AppVersionInfo(version: '9.8.7', build: '6')` and asserting that literal — locks out the "constant is back" regression.
11. Update any other Settings-related test (`settings_sounds_test.dart`, `header_standardization_test.dart`, `interaction_flow_test.dart`, etc.) that the constructor change broke.
12. Update doc `theme_and_settings.md` to remove the "currently rendered as `Version 1.0.0`" sentence and replace with the dynamic-format description.
13. Run `flutter analyze` and the full test suite.

## Progress

- [x] Phase 0: Plan written.
- [x] Phase 0.5: Failing tests authored (S-001, S-002). Red-run verified.
- [ ] Phase 1: `AppVersionInfo` model + `pubspec.yaml` add.
- [ ] Phase 2: Main.dart / App.dart wiring.
- [ ] Phase 2: SettingsScreen + HubSheet + HomeScreen + backup wiring.
- [ ] Phase 2: Dynamic footer render.
- [ ] Phase 2: Update existing SettingsScreen-using tests to inject.
- [ ] Phase 2: `flutter analyze` clean.
- [ ] Phase 2: `flutter test` green.
- [ ] Phase 2: `flutter analyze` clean.
- [ ] Phase 2: `flutter test` green.
- [x] Phase 2: Doc hygiene (`theme_and_settings.md`).
- [x] Phase 3: Code review (full-pipeline self-review).

### Phase 1 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓

## Feedback

(empty)
