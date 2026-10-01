# Feature: Timed Effort Screen Emphasis Redesign

## Overview

Redesign the active workout screen for timed effort kinds (cardio and isometric/drill — which are structurally identical and share one implementation path) to apply the same two-tier emphasis hierarchy as the resistance screen. The timer becomes the dominant-tier hero at all times (including when stopped), the weight-adjustment control becomes a quiet neutral chip (no accent), the workout state label moves to a muted status line, and accent remains reserved for the primary action while existing unlogged progress dots stay neutral.

Applied consistently across all three surfaces: active free sessions, routine-driven sessions, and routine creation.

## Requirements

- Timer renders at dominant tier regardless of run state (never greyed when stopped)
- Workout state label (STOPPED/RUNNING/PAUSED) renders muted, not in the hero zone
- Weight-adjustment control becomes a neutral collapsed chip (no accent border, no accent foreground)
- Weight chip is present only for load-capable timed exercises (when `entryData['extra-weight'] != null`)
- When expanded, the weight value uses the secondary tier via `emphasisTier: MetricEmphasisTier.secondary`
- Accent remains on the primary action button; timed/drill do not introduce accent on unlogged progress dots
- Timer play/pause icon loses its `primary` coloring — becomes neutral
- The rest timer's behavior, placement, and styling are unchanged
- One shared implementation serves both cardio (`timed`) and isometric (`drill`)
- Verified across all six themes and all three surfaces

## Acceptance Criteria

- [ ] The timer renders at the dominant tier in both stopped and running states — never greyed when stopped — on all three surfaces
- [ ] The workout state label (STOPPED/RUNNING/PAUSED) renders in the muted tier within the status line, not in the hero zone
- [ ] The weight-adjustment control is a quiet neutral collapsed chip with no accent; expanded, its weight value uses the secondary tier
- [ ] The weight chip is present only for load-capable timed exercises; absent entirely for no-load timed exercises
- [ ] The primary action remains the only accent-filled control introduced by this redesign; unlogged progress dots stay neutral
- [ ] The interval/hold count editor is present, visibly tappable, and neutral
- [ ] The primary action ("Start") is the single largest interactive element and the only accent-filled button
- [ ] The rest timer's behavior, placement, and styling are unchanged
- [ ] One shared implementation serves both cardio and isometric; both render identically in structure
- [ ] Verified across all six themes and all three surfaces, in both stopped and running states

## Scenarios

### S-001: Free session timed emphasis hierarchy — timer always dominant
- Trigger: User opens a timed effort in detail view from an active free session while the timer is stopped
- Precondition: Session has a timed exercise, detail view is open, and the current entry is not started
- Flow: Open the timed exercise detail, inspect the hero metric, status line, weight control, current progress dot, and primary action without starting the timer
- Expected outcome: Timer renders at dominant tier without read-only dimming, status line shows STOPPED in the muted tier, the weight chip is neutral and collapsed by default when extra weight is zero, and unlogged progress dots remain neutral
- Edge case of: none

### S-002: Free session timed — running state
- Trigger: User starts the timed effort from the stopped detail view
- Precondition: S-001 is active and the current timed entry is not finished
- Flow: Tap the timer hero to start the timer, then inspect the timer, play/pause affordance, status line, current progress dot, and primary action while running
- Expected outcome: Timer remains dominant, RUNNING stays muted, the play/pause icon stays neutral, and unlogged progress dots remain neutral
- Edge case of: S-001

### S-003: Timed exercise without load capability
- Trigger: User opens a timed exercise detail for an entry that has no extra-weight metric
- Precondition: Session detail is open for a timed effort and `entryData['extra-weight']` is null
- Flow: Render the detail view and inspect the metric column below the timer
- Expected outcome: No weight-adjustment chip or expanded weight editor is rendered anywhere in the layout
- Edge case of: S-001

### S-004: Timed exercise with load capability — weight chip styling
- Trigger: User opens a timed exercise detail for an entry that includes extra weight
- Precondition: Session detail is open for a timed effort and `entryData['extra-weight']` is not null
- Flow: Render the detail view with extra weight equal to zero, verify the neutral collapsed chip, then expand it and inspect the extra-weight editor; if the initial extra weight is greater than zero, the chip starts expanded and subsequent user toggles control the state
- Expected outcome: Collapsed chip uses neutral foreground and border colors, expanded extra-weight value renders with `MetricEmphasisTier.secondary`, and user toggles override the initial auto-expansion state
- Edge case of: S-001

### S-005: Routine-driven session timed emphasis
- Trigger: User opens a timed effort detail inside a session that was created from a routine
- Precondition: Routine-backed session is active and contains a timed exercise
- Flow: Open the timed exercise detail in stopped and running states and inspect the same hierarchy used in free-session detail
- Expected outcome: Routine-backed timed detail matches S-001 and S-002 exactly for timer dominance, muted status line, neutral weight chip, and unchanged neutral unlogged dots
- Edge case of: S-001

### S-006: Routine setup timed emphasis
- Trigger: User opens a timed effort detail in RoutineSetupScreen
- Precondition: Routine detail is open for a timed effort
- Flow: Open the timed effort detail in routine setup and inspect the editable extra-weight control and progress/action chrome
- Expected outcome: Timed routine setup always shows the extra-weight editor even without a seeded target, the value renders at the secondary tier, no accent is applied to the weight control, and the primary action remains the only accent-filled button
- Edge case of: none

### S-007: Drill routine setup mirrors timed extra-weight behavior
- Trigger: User opens a drill effort detail in RoutineSetupScreen
- Precondition: Routine detail is open for a drill effort
- Flow: Open the drill effort detail in routine setup and inspect the editable extra-weight control and supporting chrome
- Expected outcome: Drill routine setup always shows the extra-weight editor, the value renders at the secondary tier, and the structure matches timed routine setup for emphasis hierarchy
- Edge case of: S-006

### S-008: Drill (isometric) renders identically to timed in active sessions
- Trigger: User opens a drill/isometric effort in an active session detail view
- Precondition: Session detail is open for a drill effort
- Flow: Inspect the stopped and running drill detail states, including timer hero, status line, weight chip, and primary action
- Expected outcome: Drill uses the same timer-dominant, muted-status, neutral-weight, accent-limited structure as timed and therefore proves both effort kinds share one implementation path
- Edge case of: S-001

### S-009: Theme parity
- Trigger: UI renders under each supported app theme
- Precondition: Timed or drill detail is available on free-session, routine-session, and routine-setup surfaces
- Flow: Render each surface under all six themes and inspect the timer, status line, weight control, progress dots, and primary action
- Expected outcome: Tier hierarchy and accent allocation remain unchanged across all themes, with theme tokens supplying the actual colors and unlogged progress dots staying neutral
- Edge case of: none

## Iteration 1

### DB Changes
None required.

### Backend Changes
None required.

### Frontend Changes

#### 1. Timer always renders at dominant tier (remove greyed-when-stopped)
File: `lib/features/session/workout_session_detail_view.dart`

In `_buildMetricWidget` case `'timed'` (line ~270):
- The `InlineMetricEditor` for the timer currently has `isReadOnly: true`, which causes the value to be dimmed (`color: onSurface.withAlpha(0.45)`).
- **Add `emphasisTier: MetricEmphasisTier.dominant`** to the timer's `InlineMetricEditor`.
- In `InlineMetricEditor`, when `emphasisTier` is explicitly set, the `isReadOnly` dimming override should be suppressed — the tier color takes precedence. This requires a small change in `inline_metric_editor.dart`: when `emphasisTier != null && isReadOnly`, do NOT apply the dimming override.

File: `lib/widgets/session/inline_metric_editor.dart`

In the `build()` method (around line 157):
- Currently, when `isReadOnly` is true, `valueStyle` is overridden to use dimmed color regardless of tier.
- Change: when `emphasisTier != null`, skip the `isReadOnly` color override. The tier color already expresses the correct emphasis. The `isReadOnly` flag still disables drag interaction, just not the color.

#### 2. Workout state label moves to muted tier
File: `lib/features/session/workout_session_detail_view.dart`

In the timed case (around lines 296-310), the state text (`RUNNING`/`PAUSED`/`STOPPED`) currently uses:
- Running: `theme.colorScheme.primary.withOpacity(0.8)` — too bright, competes with timer
- Non-running: `theme.colorScheme.onSurface.withAlpha((0.5 * 255).round())` — acceptable

Change BOTH to use `OmniTheme.colors.textMuted`:
```dart
color: OmniTheme.colors.textMuted,
```

Also change the play/pause icon (line ~285) from:
- Running: `theme.colorScheme.primary.withOpacity(0.6)` → `OmniTheme.colors.textMuted`
- Stopped: `theme.colorScheme.onSurface.withAlpha((0.35 * 255).round())` → `OmniTheme.colors.textMuted`

#### 3. Weight-adjustment control becomes neutral chip
File: `lib/features/session/workout_session_detail_view.dart`

In `_buildWeightAdjustmentSection` (line ~110):
- Change `OutlinedButton.icon` style from:
  ```dart
  foregroundColor: theme.colorScheme.primary,
  side: BorderSide(color: theme.colorScheme.primary),
  ```
  To neutral:
  ```dart
  foregroundColor: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
  side: BorderSide(color: theme.colorScheme.onSurface.withAlpha((0.2 * 255).round())),
  ```

- When expanded, add `emphasisTier: MetricEmphasisTier.secondary` to the `InlineMetricEditor` for extra-weight:
  ```dart
  InlineMetricEditor(
    metricType: 'extra-weight',
    currentValue: currentValue,
    unitLabel: _preferredWeightUnitLabel,
    showUnitInline: true,
    emphasisTier: MetricEmphasisTier.secondary,
    onValueChanged: (value) => onValueChanged((value as num).toDouble()),
  ),
  ```

#### 4. Same changes in drill case
File: `lib/features/session/workout_session_detail_view.dart`

The `drill` case (further down in `_buildMetricWidget`) uses the same timer structure. Apply identical changes:
- Add `emphasisTier: MetricEmphasisTier.dominant` to the drill timer `InlineMetricEditor`
- Mute the state label and play/pause icon
- The weight chip for drill already calls `_buildWeightAdjustmentSection` (shared — already fixed in step 3)

#### 5. Routine setup screen — timed/drill metric emphasis
File: `lib/features/routine/routine_setup_screen.dart`

In `_buildMetricWidget` case `'timed'` (line ~1270):
- The extra-weight `InlineMetricEditor` currently has no `emphasisTier`. Add `emphasisTier: MetricEmphasisTier.secondary`.

In `_buildMetricWidget` case `'drill'` (line ~1330):
- Same: add `emphasisTier: MetricEmphasisTier.secondary` to the extra-weight editor.

#### 6. Ensure the timer InlineMetricEditor in routine setup uses dominant tier
File: `lib/features/routine/routine_setup_screen.dart`

The routine setup for timed/drill doesn't show a live timer (it shows target duration). For this surface, the primary metric (target duration) should also use `emphasisTier: MetricEmphasisTier.dominant` if it exists, but currently the timed case only shows extra-weight (no duration editor for timed in routine). So no additional timer-tier changes needed on routine setup.

### Implementation Steps

1. [ ] Update `InlineMetricEditor`: when `emphasisTier != null`, skip the `isReadOnly` dimming color override (tier takes precedence)
2. [ ] In `_buildMetricWidget` case `'timed'`: add `emphasisTier: MetricEmphasisTier.dominant` to the timer `InlineMetricEditor`
3. [ ] In `_buildMetricWidget` case `'timed'`: change state label color (RUNNING/PAUSED/STOPPED) to `OmniTheme.colors.textMuted`
4. [ ] In `_buildMetricWidget` case `'timed'`: change play/pause icon color to `OmniTheme.colors.textMuted`
5. [ ] In `_buildWeightAdjustmentSection`: change OutlinedButton style from primary accent to neutral (onSurface-based)
6. [ ] In `_buildWeightAdjustmentSection`: add `emphasisTier: MetricEmphasisTier.secondary` to the expanded InlineMetricEditor
7. [ ] Apply identical changes to the `'drill'` case in `_buildMetricWidget` (timer dominant, state label muted, icon muted)
8. [ ] In `routine_setup_screen.dart`: add `emphasisTier: MetricEmphasisTier.secondary` to timed extra-weight editor
9. [ ] In `routine_setup_screen.dart`: add `emphasisTier: MetricEmphasisTier.secondary` to drill extra-weight editor
10. [ ] Write widget test: timer resolves to dominant tier in BOTH stopped and running states
11. [ ] Write widget test: state label resolves to muted tier and sits below the timer (not in hero zone)
12. [ ] Write widget test: weight chip renders for load-capable timed exercise, absent for no-load
13. [ ] Write widget test: weight chip uses no accent collapsed, expanded value uses secondary tier
14. [ ] Write widget test: accent appears only on primary action and current dot
15. [ ] Write test: cardio and isometric render through same shared implementation
16. [ ] Write tests: consistent rendering across free-session, routine-session, and routine-creation paths
17. [ ] Update any existing tests that assert greyed stopped timer or accent weight toggle

### Files Affected

- `lib/widgets/session/inline_metric_editor.dart` — suppress isReadOnly dimming when emphasisTier is set
- `lib/features/session/workout_session_detail_view.dart` — timer tier, state label muting, weight chip neutralization (timed + drill cases)
- `lib/features/routine/routine_setup_screen.dart` — add secondary tier to timed/drill extra-weight editors
- New test file: `test/timed_emphasis_redesign_test.dart`

### Notes

- The change to `InlineMetricEditor` (skipping isReadOnly dimming when tier is explicit) is backward-compatible: only callers that now pass `emphasisTier` are affected. The resistance screen already passes tiers and is NOT read-only, so unaffected.
- The `_buildWeightAdjustmentSection` is shared across timed and drill cases (and also used by set-without-load) — the neutral styling change applies universally, which is the desired outcome.
- The weight chip now defaults to expanded when the current extra-weight value is greater than zero; after first render, explicit user toggles win.
- The `COMPLETED` state label and its `primary` color are intentionally left unchanged — it signals a terminal state and doesn't compete with the hero since it replaces the action button semantically.
- Rest timer is entirely out of scope — no changes to rest overlay, rest behavior, or rest styling.
- The progress dots and set-count editor were already neutralized in the resistance redesign iteration — verify they remain neutral for timed/drill (they should, since `_buildSetProgress` and `_buildSetIndicator` are effortKind-agnostic).

## Progress

- [x] Update InlineMetricEditor to skip isReadOnly dimming when emphasisTier set
- [x] Add dominant tier to timed timer InlineMetricEditor
- [x] Mute timed state label and play/pause icon
- [x] Neutralize weight-adjustment chip styling
- [x] Add secondary tier to expanded weight editor
- [x] Apply same changes to drill case
- [x] Add secondary tier to routine setup timed/drill editors
- [x] Write all new widget tests
- [x] Update any existing tests asserting old styling

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback

