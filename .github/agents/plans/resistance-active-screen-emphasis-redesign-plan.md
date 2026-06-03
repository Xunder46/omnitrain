# Feature: Resistance Active Screen Emphasis Redesign

## Overview

Redesign the active workout screen for the resistance effort kind (`set` — reps + weight) to apply a strict two-tier emphasis hierarchy. The screen must have exactly two loud elements — the rep/weight hero and the primary action — with everything else quiet. Applied consistently across all three surfaces: active free sessions, routine-driven sessions, and routine creation.

## Requirements

- Remove accent from count stepper controls (the "+" add-set icon currently uses `theme.colorScheme.primary`)
- Remove tracking-type chip from routine creation detail view
- Remove the "previous set" reference line entirely (low-value — only shows prior set in same session)
- Reps figure uses dominant tier (largest, brightest)
- Weight figure uses secondary tier (bright but visibly smaller and subordinate)
- Workout state label (STOPPED/RUNNING) renders muted
- Rest timer unchanged
- Set-count editor present, visibly tappable, neutral (non-accent)
- Primary action ("Log Set") is the single accent-filled button
- Progress dots passive; logged dots are primary and only unlogged dots are neutral
- Consistent across all three surfaces and all six themes

## Acceptance Criteria

- [ ] On active session surfaces, logged position dots are primary and only unlogged dots are neutral; on routine creation, dots remain neutral
- [ ] The reps figure is the largest, brightest element (dominant tier); weight is bright but visibly smaller and subordinate (secondary tier)
- [ ] Workout state (STOPPED/RUNNING) renders in the muted tier and does not compete with the hero
- [ ] The rest timer's behavior, placement, and styling are unchanged
- [ ] The "previous set" reference line is removed
- [ ] The set-count editor is present, visibly tappable, and rendered in a neutral (non-accent) tier on every surface
- [ ] Progress dots are passive; logged dots are primary and unlogged dots are neutral
- [ ] The primary action ("Log Set") is the single largest interactive element and the only accent-filled button
- [ ] Routine creation detail removes the tracking-type chip entirely
- [ ] Verified across all six themes and all three surfaces

## Scenarios

### S-001: Free session resistance emphasis hierarchy
- Trigger: User opens a resistance effort (`set`) in WorkoutSessionScreen detail view from an active free session
- Precondition: Session has at least one resistance exercise and detail view is open
- Flow: Open exercise detail, inspect reps/weight editors, set-progress row, progress dots, and Log Set control
- Expected outcome: Reps editor renders dominant tier, weight editor renders secondary tier, plus/minus set-count controls are neutral, logged dots are primary while unlogged dots are neutral, primary action remains the accent-filled Log Set button
- Edge case of: none

### S-002: Routine-driven resistance emphasis hierarchy
- Trigger: User opens a resistance effort (`set`) in WorkoutSessionScreen detail view from a routine-driven session
- Precondition: Routine session is active and selected effort is resistance
- Flow: Navigate to resistance detail and inspect the same emphasis elements as S-001
- Expected outcome: Same emphasis behavior as S-001, including neutral set-count controls and logged-dot primary logic
- Edge case of: S-001

### S-003: Routine setup resistance emphasis hierarchy
- Trigger: User opens a resistance effort (`set`) in RoutineSetupScreen detail view
- Precondition: Routine exists with at least one resistance exercise
- Flow: Open detail view and inspect reps/weight editors, set-progress controls, and set indicator
- Expected outcome: Reps editor is dominant, weight editor is secondary, set-count controls are neutral, tracking-type chip is absent, and dots remain neutral (no logged state in setup)
- Edge case of: none

### S-004: Previous-set reference removed across effort kinds
- Trigger: User navigates between entries where previous-set text previously appeared
- Precondition: Any effort kind (`set`, `timed`, `round`, `drill`) on WorkoutSessionScreen or RoutineSetupScreen detail view
- Flow: Move to set/entry index > 1 and inspect content below set-progress row
- Expected outcome: No previous-set line is rendered for any effort kind on either surface
- Edge case of: none

### S-005: Logged dot accent rule
- Trigger: User views a set/entry indicator with multiple entries
- Precondition: Total entries > 1 in detail view
- Flow: Navigate between entries, including logged/skipped and unlogged entries
- Expected outcome: Logged (including skipped) dots are accent; unlogged dots are neutral
- Edge case of: S-001

### S-006: Neutral set-count editor behavior
- Trigger: User inspects or uses set-count +/- controls
- Precondition: Detail view is open on resistance effort
- Flow: Observe enabled and disabled states of remove/add controls, then tap controls to confirm they still work
- Expected outcome: Enabled +/- icons use neutral on-surface alpha styling (non-accent) while retaining tappability and existing add/remove behavior
- Edge case of: S-001

### S-007: Theme parity for redesign
- Trigger: UI is rendered under each supported app theme
- Precondition: Detail view available for each target surface
- Flow: Render the redesigned elements under all six themes
- Expected outcome: Tier hierarchy and accent placement rules remain consistent across themes
- Edge case of: S-001

## Iteration 1

### DB Changes
None required.

### Backend Changes
None required.

### Frontend Changes

#### 1. InlineMetricEditor emphasis tier support
File: `lib/widgets/session/inline_metric_editor.dart`

Currently `InlineMetricEditor` uses a single `displayLarge` style for all metrics. The resistance screen needs the reps editor at dominant tier (larger, textDominant color) and weight editor at secondary tier (smaller, textSecondary color).

Changes:
- Add an optional `emphasisTier` parameter (`dominant`, `secondary`, `muted`) to `InlineMetricEditor`
- When `emphasisTier: dominant` → use `displayLarge` font size + `OmniTheme.colors.textDominant` color
- When `emphasisTier: secondary` → use `displayMedium` (or ~0.75× font size) + `OmniTheme.colors.textSecondary` color
- Default (no tier specified) → current behavior unchanged (backward compatible)

#### 2. Session detail view — resistance metric widget
File: `lib/features/session/workout_session_detail_view.dart`

In `_buildMetricWidget` case `'set'`:
- Pass `emphasisTier: dominant` to the reps `InlineMetricEditor`
- Pass `emphasisTier: secondary` to the weight `InlineMetricEditor`

#### 3. Remove "previous set" line from all effort kinds
File: `lib/features/session/workout_session_detail_view.dart`

- Remove the call to `_buildPreviousSetStats(...)` from the layout in the list view (`workout_session_list_view.dart` line ~736)
- The method `_buildPreviousSetStats` itself can remain (dead code removal is optional) or be removed

File: `lib/features/session/workout_session_list_view.dart`
- Remove the `_buildPreviousSetStats(...)` call and surrounding SizedBox

#### 4. Remove accent from set-count add button
File: `lib/features/session/workout_session_detail_view.dart`

In `_buildSetProgress`:
- Change the add-set "+" icon color from `theme.colorScheme.primary` to `theme.colorScheme.onSurface.withAlpha((0.35 * 255).round())` (matches remove button)

#### 5. Fix progress dots to only accent the current dot
File: `lib/features/session/workout_session_detail_view.dart`

In `_buildSetIndicator`:
- Currently: logged dots get `primary.withOpacity(0.8)`, current unlogged gets `primary.withAlpha(0.35)`, others get `onSurface.withAlpha(0.2)`
- New: current dot (regardless of logged state) gets `primary`, all others get `onSurface.withAlpha((0.2 * 255).round())`

#### 6. Routine setup screen — same changes
File: `lib/features/routine/routine_setup_screen.dart`

- In `_buildMetricWidget` for the `'set'` case: pass `emphasisTier: dominant` to reps, `emphasisTier: secondary` to weight
- Remove `_buildPreviousSetStats(...)` call from detail view layout (line ~659)
- Remove accent from add-set "+" icon (line ~1466: change `theme.colorScheme.primary` to neutral)
- Progress dots in `_buildSetIndicator` (line ~1556): only current dot uses accent, all others neutral

#### 7. Workout state label muted tier
File: `lib/features/session/workout_session_detail_view.dart`

In the timed effort kind's status text (RUNNING/PAUSED/STOPPED area around line ~300):
- Already renders as `theme.colorScheme.onSurface.withAlpha(0.5)` for non-running state — this maps to muted tier. Running state currently uses `primary.withOpacity(0.8)` — this stays since it's for the timed effort kind, not resistance. No change needed for resistance `'set'` kind since it doesn't have a running/stopped state display.

### Implementation Steps

1. [ ] Add `emphasisTier` parameter to `InlineMetricEditor`
2. [ ] Update `_buildMetricWidget` case `'set'` in `workout_session_detail_view.dart` to pass tier params
3. [ ] Remove `_buildPreviousSetStats` call from `workout_session_list_view.dart` layout
4. [ ] Remove accent from add-set "+" icon in `_buildSetProgress` (detail view)
5. [ ] Fix `_buildSetIndicator` progress dots: only current dot is accent
6. [ ] Apply same changes to `routine_setup_screen.dart`: metric tiers, remove previous-set line, neutral add-set icon, fix progress dots
7. [ ] Write widget tests: accent applied only to primary action + current dot
8. [ ] Write widget tests: reps at dominant tier, weight at secondary tier
9. [ ] Write widget test: "previous set" element absent
10. [ ] Write widget test: set-count editor present and interactive
11. [ ] Write parameterized tests confirming layout across all three surfaces
12. [ ] Update existing test `previous set banner respects lbs preference` (screen_widget_test.dart ~line 4916) — remove or adapt since "previous set" line no longer exists
13. [ ] Update existing test `S-019: previous set stats show "—"` (session_toolbar_rework_test.dart ~line 729) — remove or adapt

### Files Affected

- `lib/widgets/session/inline_metric_editor.dart` — add emphasisTier param
- `lib/features/session/workout_session_detail_view.dart` — metric tiers, remove previous-set, fix dots, fix add-set accent
- `lib/features/session/workout_session_list_view.dart` — remove `_buildPreviousSetStats` call
- `lib/features/routine/routine_setup_screen.dart` — metric tiers, remove previous-set, fix dots, fix add-set accent
- `test/screen_widget_test.dart` — update/remove previous-set test
- `test/session_toolbar_rework_test.dart` — update/remove previous-set test
- New test file: `test/resistance_emphasis_redesign_test.dart`

### Notes

- The `InlineMetricEditor` change is backward-compatible: when no `emphasisTier` is passed, behavior is identical to today
- The "previous set" line removal applies to ALL effort kinds (set, timed, round, drill) — it's consistently low-value across all of them since it only shows the immediately prior set within the same session
- The routine setup screen has its own independent implementations of `_buildSetProgress`, `_buildPreviousSetStats`, `_buildSetIndicator` — each must be updated separately
- Rest timer is entirely out of scope — its overlay, its behavior, and its styling remain untouched
- The `LOGGED` label that appears after logging a set currently uses `primary.withOpacity(0.9)` — this is acceptable since it replaces the primary action button position and carries the same semantic weight

## Progress

- [x] Add emphasisTier to InlineMetricEditor
- [x] Update resistance metric widget in session detail view
- [x] Remove previous-set line from session list view
- [x] Remove accent from add-set icon in session detail view
- [x] Fix progress dots in session detail view
- [x] Apply all changes to routine setup screen
- [x] Write new widget tests
- [x] Update existing tests that assert previous-set line
- [x] Remove routine setup tracking-type chip
- [x] Fix routine setup add-set first tap behavior
- [x] Update dot coloring to logged-primary / unlogged-neutral

## Phase 0 Test Evidence

- Red run before implementation: `test/resistance_emphasis_redesign_test.dart` -> 1 passed, 4 failed
- Green run after implementation: `test/resistance_emphasis_redesign_test.dart` -> 4 passed, 0 failed
- Regression run: `test/session_toolbar_rework_test.dart` + `test/screen_widget_test.dart` -> 184 passed, 0 failed
- Full suite run: `flutter test` -> 1008 passed, 0 failed

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback

- Resolved: routine setup tracking chip styling is neutralized to stay aligned with the two-loud-elements acceptance criteria.
- Resolved: scenario tests now cover previous-set absence across `set`, `timed`, `round`, and `drill` on both session and routine setup surfaces.
- Resolved: six-theme tests now assert accent-placement invariants (neutral set controls + logged-dot primary / unlogged-neutral) across all three surfaces.
- Resolved: routine creation detail view tracking-type chip is removed entirely.
- Resolved: routine creation detail view add-set plus button now adds a set on the first tap.
- Resolved: set indicators now use primary hue for logged sets and neutral hue only for unlogged sets.

## Doc Updates (This Pass)

- `docs/navigation_and_screens.md`: no update required (no route or screen-constructor contract changes in this pass).
- `docs/state_management.md`: no update required (no new state class or public state API added in this pass).
- `docs/widget_catalog.md`: updated (`InlineMetricEditor.emphasisTier` behavior and props).
- `docs/data_models_and_repository.md`: no update required (no model or repository contract changes in this pass).
- `docs/db_integration.md`: no update required (no schema/migration/storage-layer changes in this pass).

