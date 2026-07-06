# Hygiene Sweep

## Overview

Remove debris from the OmniTrain repository that misleads future work — especially agent-driven work, where dead duplicate files cause edits to land in the wrong place. Specifically: delete an abandoned backup of the home screen, delete two ad-hoc debug measurement tests, convert three stray `print()` calls in the session/workout code to the codebase's standard `debugPrint` mechanism (release-safe), and replace the placeholder pubspec description with a real one-liner. No behavior change; build and test suite must remain green.

## Requirements

- `lib/features/home/home_screen_backup.dart` deleted; no file in `lib/`, `test/`, `scripts/`, `assets/`, or platform directories references it.
- `test/_debug_title.dart` and `test/_debug_train_card.dart` deleted; nothing else in the suite depends on helpers inside them.
- All three remaining `print(...)` calls in session/workout code (`workout_session_screen.dart`, `workout_state.dart`, `session_overview_screen.dart`) route through `debugPrint` (the codebase's standard debug-only mechanism). What is logged and when is unchanged.
- `pubspec.yaml` `description:` is no longer the framework placeholder.
- Full `flutter test` suite passes; no behavioral change is observable.

## Acceptance Criteria

- [ ] `lib/features/home/home_screen_backup.dart` no longer exists.
- [ ] No file in `lib/`, `test/`, `scripts/`, `assets/`, `web/`, `android/`, `ios/`, `macos/`, `windows/`, or `linux/` references `home_screen_backup`.
- [ ] `test/_debug_title.dart` no longer exists.
- [ ] `test/_debug_train_card.dart` no longer exists.
- [ ] No other file in the repo references `_debug_title` or `_debug_train_card`.
- [ ] No raw `print(` call remains anywhere under `lib/` (`grep -RIn '^\s*print(' lib/` returns 0 matches).
- [ ] The three converted call sites log the identical message text through `debugPrint`.
- [ ] `pubspec.yaml` `description:` is a one-line description of OmniTrain — not `"A new Flutter project."`.
- [ ] `flutter test` (full suite) exits with code 0.

## Scenarios

### S-001: Delete abandoned backup home-screen file
- Trigger: Hygiene sweep runs.
- Precondition: `home_screen_backup.dart` exists under `lib/features/home/`; no source file imports or references it.
- Flow: Remove `lib/features/home/home_screen_backup.dart` from the working tree; confirm `grep -RIn 'home_screen_backup' lib/ test/ scripts/ assets/ web/ android/ ios/ macos/ windows/ linux/` returns no matches.
- Expected outcome: The file is gone; no compilation or import error surfaces because no live code referenced it. The live `home_screen.dart` is untouched.
- Edge case of: none

### S-002: Delete two scratch debug measurement tests
- Trigger: Hygiene sweep runs.
- Precondition: `test/_debug_title.dart` and `test/_debug_train_card.dart` exist as standalone `debugPrint`-driven measurement scripts; no other test depends on helpers inside them.
- Flow: Remove both files from the working tree; confirm `grep -RIn '_debug_title\|_debug_train_card' .` returns no matches outside `.github/agents/docs/` and `.github/agents/plans/`.
- Expected outcome: Both files are gone. The full `flutter test` suite still passes because no other test referenced any helper inside them.
- Edge case of: none

### S-003: Convert three session/workout `print` calls to `debugPrint`
- Trigger: Hygiene sweep runs.
- Precondition: Three `print('Error …: $e')` calls exist in `lib/features/session/workout_session_screen.dart`, `lib/state/workout/workout_state.dart`, and `lib/features/session/session_overview_screen.dart`. The codebase's standard debug-only logging mechanism is `debugPrint` (24 existing call sites).
- Flow: Replace each `print(...)` with the identical `debugPrint(...)` (same message text, same interpolation). Re-run `grep -RIn '^\s*print(' lib/` and confirm zero matches. Run `flutter test` and confirm all tests pass.
- Expected outcome: No raw console prints remain in `lib/`. The three log lines still emit in debug builds (preserving observability for developers) and are stripped from release builds (because `debugPrint` is a no-op when `kReleaseMode` is true). Nothing about what is logged or when changes.
- Edge case of: none

### S-004: Replace placeholder pubspec description
- Trigger: Hygiene sweep runs.
- Precondition: `pubspec.yaml` line 2 reads `description: "A new Flutter project."` (the Flutter `flutter create` template default).
- Flow: Replace the placeholder string with a one-line description of OmniTrain as a multi-sport training log for lifting, cardio, sports, and more.
- Expected outcome: `pubspec.yaml` no longer carries the framework default description. Pub/yaml parsing still succeeds; no behavior change in the app.
- Edge case of: none

## Iteration 1

### DB Changes

None. This sweep does not touch data models, schema, repositories, or the SQLite/Hive parity assets.

### Backend Changes

None. No state class, service, or repository is modified.

### Frontend Changes

- **Deletions (no replacement, no behavior change):**
  - `lib/features/home/home_screen_backup.dart` — orphan backup of the home screen.
  - `test/_debug_title.dart` — one-off `TITLE_HEIGHT` measurement script.
  - `test/_debug_train_card.dart` — one-off `CARD_TOTAL_HEIGHT` / `OMNI_HEIGHT` measurement script.
- **Logging routing (behavior-preserving):**
  - `lib/features/session/workout_session_screen.dart:487` — `print('Error loading exercises: $e')` → `debugPrint('Error loading exercises: $e')`.
  - `lib/state/workout/workout_state.dart:351` — `print('Error checking for in-progress sessions: $e')` → `debugPrint('Error checking for in-progress sessions: $e')`.
  - `lib/features/session/session_overview_screen.dart:58` — `print('Error initializing session: $e')` → `debugPrint('Error initializing session: $e')`.
- **Metadata:**
  - `pubspec.yaml:2` — `description: "A new Flutter project."` → `description: "A multi-sport training log for lifting, cardio, sports, and more."`.

### Implementation Steps

1. Create plan file (`.github/agents/plans/hygiene-sweep-plan.md`).
2. Verify `home_screen_backup.dart` has no live references across `lib/`, `test/`, `scripts/`, `assets/`, and platform directories.
3. Delete `lib/features/home/home_screen_backup.dart`.
4. Delete `test/_debug_title.dart` and `test/_debug_train_card.dart`.
5. In each of the three call sites, replace `print(...)` with `debugPrint(...)`. Confirm `flutter/foundation` is already imported (it is in all three files per existing `ChangeNotifier`/widget usage patterns).
6. Update `pubspec.yaml` description.
7. Run `flutter test` (full suite) and confirm exit code 0.

## Progress

- [x] Phase 0 — Plan written
- [x] Phase 1 — Data layer (no-op: no models/repositories/schema touched)
- [x] Phase 2 — Logic & UI: backups + scratch tests deleted; three `print` calls converted to `debugPrint`; pubspec description updated
- [x] Phase 3 — Code review delivered

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (no-op)
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Feedback

(none yet)