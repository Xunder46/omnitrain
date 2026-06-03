# Feature: Sports Effort Screen Emphasis Redesign

## Overview

Redesign the active workout screen for sports effort kind (exercises organized into rounds/periods with a duration, e.g., American Football periods, soccer halves) to apply the same two-tier emphasis hierarchy validated on the resistance and timed screens. The round/period label and duration together form the bright hero, the state label moves to a muted status line, the period-count editor stays present but neutral, and accent is reserved for the primary action while progress dots are mostly neutral.

Applied consistently across all three surfaces: active free sessions, routine-driven sessions, and routine creation.

## Requirements

- Round/period label and duration together render at dominant tier (the compound hero)
- Duration renders bright at all times regardless of run state (never greyed when stopped)
- Workout state label (STOPPED/RUNNING/PAUSED) renders muted in the status line, not competing with the hero
- Period-count editor ("Period X of Y" with decrease/increase controls) is present, visibly tappable, and styled as neutral
- Progress dots: only the current position dot receives accent color; all others are neutral
- Play/pause icon uses neutral color (not primary/accent)
- Primary action button ("Start") is the single accent-owning element, rendered large
- The rest timer's behavior, placement, and styling are unchanged
- One shared implementation serves all sports modalities (uses 'round' effort kind)
- Verified across all six themes and all three surfaces in stopped and running states

## Acceptance Criteria

- [ ] The round/period label and duration both render at dominant tier and together read as a cohesive hero on all three surfaces
- [ ] The duration is bright in both stopped and running states — never greyed when stopped
- [ ] The workout state label (STOPPED/RUNNING/PAUSED) renders in the muted tier within the status line, not competing with the hero
- [ ] The accent color appears on exactly two elements: the primary action button and the single current position dot
- [ ] No accent color on period-count editor controls or on non-current progress dots
- [ ] The period-count editor is present, visibly tappable (secondary tier styling), and rendered as a neutral control
- [ ] The play/pause icon uses neutral color treatment, not primary
- [ ] The primary action ("Start") is the single largest interactive element and the only accent-filled button
- [ ] The rest timer's behavior, placement, and styling are unchanged
- [ ] Verified across all six themes and all three surfaces (free session, routine-backed session, routine setup), in both stopped and running states

## Scenarios

### S-001: Free session sports emphasis hierarchy — duration always dominant
- Trigger: User opens a sports/round effort in detail view from an active free session while the round/period is stopped
- Precondition: Session has a sports exercise, detail view is open, and the current round is not started
- Flow: Open the sports exercise detail, inspect the round label, duration, status line, period count, progress dots, and primary action without starting the timer
- Expected outcome: "PERIOD 1" and duration render at dominant tier without dimming, status line shows STOPPED in the muted tier, period-count editor is neutral, only the current dot has accent, and the Start button is the only accent-filled element
- Edge case of: none

### S-002: Free session sports — running state
- Trigger: User starts the sports round from the stopped detail view
- Precondition: S-001 is active and the current round is not finished
- Flow: Tap the hero to start the round timer, then inspect the round label, duration, status text, play/pause icon, progress dots, and primary action while running
- Expected outcome: "PERIOD 1" and duration remain dominant tier, RUNNING stays muted, the play/pause icon stays neutral, only the current dot has accent, and the Start/Continue button remains the only accent-filled element
- Edge case of: S-001

### S-003: Routine-driven session sports emphasis
- Trigger: User opens a sports round effort detail inside a session that was created from a routine
- Precondition: Routine-backed session is active and contains a sports exercise
- Flow: Open the sports round detail in stopped and running states and inspect the same hierarchy used in free-session detail
- Expected outcome: Routine-backed sports detail matches S-001 and S-002 exactly for hero dominance, muted status line, neutral period editor, and accent-limited progress dots and button
- Edge case of: S-001

### S-004: Routine setup sports emphasis
- Trigger: User opens a sports round effort detail in RoutineSetupScreen
- Precondition: Routine detail is open for a sports effort
- Flow: Open the sports effort detail in routine setup and inspect the period-count control and hierarchy
- Expected outcome: Sports routine setup shows the period-count editor as a tappable, neutral control; the round label and duration render at dominant tier; and the primary action remains the only accent-filled button
- Edge case of: none

### S-005: Theme parity
- Trigger: UI renders under each supported app theme
- Precondition: Sports detail is available on free-session, routine-session, and routine-setup surfaces
- Flow: Render each surface under all six themes and inspect the round label, duration, status line, period count, progress dots, and primary action
- Expected outcome: Tier hierarchy and accent allocation remain unchanged across all themes, with theme tokens supplying the actual colors

## Iteration 1

### DB Changes
None required.

### Backend Changes
None required.

### Frontend Changes

#### 1. Duration always renders at dominant tier (remove greyed-when-stopped)

File: `lib/features/session/workout_session_detail_view.dart`

In the `'round'` case (starting at line ~338):
- The `InlineMetricEditor` for the duration currently does not explicitly set `emphasisTier`
- **Add `emphasisTier: MetricEmphasisTier.dominant`** to the duration's `InlineMetricEditor`
- The duration's `isReadOnly` property should be set to `true` to disable editing (as it is currently)
- When `emphasisTier: MetricEmphasisTier.dominant` is set, the `InlineMetricEditor` will render at the dominant color tier

File: `lib/widgets/session/inline_metric_editor.dart`

Verify the behavior: when `emphasisTier` is explicitly set to `dominant`, the value color should be `OmniTheme.colors.textDominant` regardless of the `isReadOnly` state. 
- At line ~163, the condition `if (widget.isReadOnly && widget.emphasisTier == null)` ensures that `isReadOnly` dimming only applies when no explicit tier is set
- This is already correct; no changes needed

#### 2. Compound hero: round label and duration together

File: `lib/features/session/workout_session_detail_view.dart`

In the `'round'` case (line ~447 in the non-edit path):
- The "ROUND X" (or "PERIOD X" for sports modality) text currently renders using `displayLarge` style
- Change the text styling to explicitly use the dominant tier color:
  ```dart
  Text(
    'PERIOD $rounds',  // 'PERIOD' for sports, 'ROUND' for others
    style: theme.textTheme.displayLarge?.copyWith(
      fontWeight: FontWeight.w300,
      letterSpacing: -2,
      fontSize: theme.textTheme.displayMedium?.fontSize,
      color: OmniTheme.colors.textDominant,  // Add explicit dominant color
    ),
  ),
  ```
- This ensures the round/period label reads with the same emphasis as the duration

#### 3. Workout state label moves to muted tier in status line

File: `lib/features/session/workout_session_detail_view.dart`

In the `'round'` case, the state text (RUNNING/PAUSED/STOPPED) is currently rendered inline with the play/pause icon (line ~485):
- Change from:
  ```dart
  Text(
    // ...text logic...
    style: theme.textTheme.labelMedium?.copyWith(
      color: (_effortRunning[timerKey] ?? false)
          ? theme.colorScheme.primary.withOpacity(0.8)  // Too bright
          : theme.colorScheme.onSurface.withAlpha(
              (0.5 * 255).round(),
            ),
      letterSpacing: 1,
    ),
  ),
  ```
- To:
  ```dart
  Text(
    // ...text logic...
    style: theme.textTheme.labelMedium?.copyWith(
      color: OmniTheme.colors.textMuted,  // Always muted, regardless of state
      letterSpacing: 1,
    ),
  ),
  ```

#### 4. Play/pause icon uses neutral color

File: `lib/features/session/workout_session_detail_view.dart`

In the `'round'` case (line ~477), the play/pause icon currently uses:
  ```dart
  Icon(
    (_effortRunning[timerKey] ?? false)
        ? Icons.pause_circle_outline
        : Icons.play_circle_outline,
    size: 30,
    color: (_effortRunning[timerKey] ?? false)
        ? theme.colorScheme.primary.withOpacity(0.6)  // Accent when running
        : theme.colorScheme.onSurface.withAlpha(
            (0.35 * 255).round(),
          ),
  ),
  ```
- Change to:
  ```dart
  Icon(
    (_effortRunning[timerKey] ?? false)
        ? Icons.pause_circle_outline
        : Icons.play_circle_outline,
    size: 30,
    color: OmniTheme.colors.textMuted,  // Neutral for both running and stopped
  ),
  ```

#### 5. Progress dots: accent only on current dot

File: `lib/features/session/workout_session_detail_view.dart`

In the progress dots section (likely after the state text row, around line ~500+):
- Find the progress dot rendering code
- Ensure only the current/active dot uses `theme.colorScheme.primary` (accent)
- All other dots use neutral color: `OmniTheme.colors.textMuted`

#### 6. Period-count editor styling

File: `lib/features/session/workout_session_detail_view.dart`

In the `'round'` case, locate or create a period-count editor section that shows "Period X of Y" with decrease/increase controls:
- Style the entire control as secondary tier (neutral but tappable)
- Use `OmniTheme.colors.textSecondary` or similar for the text
- Use outline buttons with `OmniTheme.colors.textSecondary` border and foreground (no primary/accent)
- Example structure:
  ```dart
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      OutlinedButton.icon(
        onPressed: /* decrease period count */,
        icon: Icon(Icons.remove),
        label: Text(''),
        style: OutlinedButton.styleFrom(
          foregroundColor: OmniTheme.colors.textSecondary,
          side: BorderSide(color: OmniTheme.colors.textSecondary),
        ),
      ),
      SizedBox(width: 12),
      Text(
        'Period $_currentPeriod of $totalPeriods',
        style: theme.textTheme.labelMedium?.copyWith(
          color: OmniTheme.colors.textSecondary,
        ),
      ),
      SizedBox(width: 12),
      OutlinedButton.icon(
        onPressed: /* increase period count */,
        icon: Icon(Icons.add),
        label: Text(''),
        style: OutlinedButton.styleFrom(
          foregroundColor: OmniTheme.colors.textSecondary,
          side: BorderSide(color: OmniTheme.colors.textSecondary),
        ),
      ),
    ],
  ),
  ```

#### 7. Primary action button (Start/Continue)

Ensure the primary action button (line ~520+ or wherever the main action is):
- Uses `theme.colorScheme.primary` (accent) for fill and text
- Is the largest and most prominent interactive element
- No other accent-colored buttons exist in the view

### Implementation Steps

1. [ ] Add `emphasisTier: MetricEmphasisTier.dominant` to the duration `InlineMetricEditor` in the `'round'` case
2. [ ] Update the "PERIOD X" label to use `color: OmniTheme.colors.textDominant`
3. [ ] Change the state label (RUNNING/PAUSED/STOPPED) to always use `OmniTheme.colors.textMuted`
4. [ ] Change the play/pause icon to use `OmniTheme.colors.textMuted` in both running and stopped states
5. [ ] Update progress dots to accent only the current dot, neutral for all others
6. [ ] Create or update the period-count editor to use neutral (secondary tier) styling
7. [ ] Verify the primary action button is the single accent element and largest interactive element
8. [ ] Create widget tests for the new emphasis tiers (see Unit Tests section)
9. [ ] Run existing tests to ensure no regressions
10. [ ] Manually verify on mobile device across all six themes in stopped and running states

## Unit Tests Required

### New Tests

1. **test_sports_round_label_and_duration_at_dominant_tier**
   - Assertion: Both "PERIOD X" text and duration value resolve to `OmniTheme.colors.textDominant`
   - Verifies the compound hero effect
   - File: New file or existing test file

2. **test_sports_duration_bright_in_stopped_and_running**
   - Assertion: Duration color is `textDominant` in both stopped and running states (no greying when stopped)
   - Guards against regression where duration might be dimmed when stopped
   - File: New file or existing test file

3. **test_sports_state_label_in_muted_tier_in_status_line**
   - Assertion: State label (RUNNING/PAUSED/STOPPED) color is `OmniTheme.colors.textMuted`
   - Verifies the state label does not compete with the hero
   - File: New file or existing test file

4. **test_sports_accent_only_on_primary_and_current_dot**
   - Assertion: Only the primary action button and the current progress dot use `theme.colorScheme.primary`
   - Verifies accent is allocated correctly
   - File: New file or existing test file

5. **test_sports_period_count_editor_neutral_styling**
   - Assertion: Period-count editor (buttons and text) use neutral colors (textSecondary or textMuted), not primary
   - Verifies the editor is visibly tappable but not accent-bearing
   - File: New file or existing test file

6. **test_sports_play_pause_icon_neutral**
   - Assertion: Play/pause icon uses `OmniTheme.colors.textMuted` in both running and stopped states
   - File: New file or existing test file

### Updated Tests

- Any existing test covering the sports/round screen that asserts old color behaviors (e.g., primary color on state label, greyed duration when stopped, accent on progress dots) must be updated to match the new hierarchy
- Tests covering duration counting and round timer logic must continue to pass unchanged
- Tests covering the rest timer must continue to pass unchanged

## Progress

- [x] Plan approved by user
- [x] Implementation Phase 1: Emphasis tier changes (dominant hero, muted state label, neutral play/pause)
- [x] Implementation Phase 2: Period-count editor styling (secondary/neutral controls)
- [x] Implementation Phase 3: Progress dot accent allocation
- [x] Testing Phase 1: New widget tests created and passing
- [x] Testing Phase 2: Existing tests updated and passing
- [ ] Manual verification: All six themes, stopped and running states, mobile device
- [x] Code review and approval

## Feedback

- Review follow-up completed on 2026-06-02.
- Addressed all previously listed implementation and test gaps:
  - Routine setup sports round hero now uses PERIOD label + dominant tier.
  - Round duration editors on all required surfaces enforce dominant emphasis.
  - Status-line and play/pause chrome are muted on sports round detail.
  - Progress-dot accent behavior now applies to sports round current position while preserving non-round semantics.
  - Scenario coverage expanded to include routine-backed and routine-setup surfaces with all-theme parity checks.
  - Full test suite passes.
