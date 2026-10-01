# Feature: Rolling Session Summary — Hide Duration and Rest Time Stats

## Overview
The post-workout Session Summary screen shows a Duration stat and a Rest Time
stat at the top of the screen. For rolling sessions both values are always zero
because rolling sessions have no continuous session clock. Displaying two zeroed
stats makes a completed summary look broken. For rolling sessions only, both stats
must be hidden. When hidden, the containing card and its spacing must also
disappear so there is no empty container or residual spacing. Standard sessions
remain unchanged.

## Requirements
- For a rolling session, neither Duration nor Rest Time stat is rendered on the
  summary screen.
- When both stats are hidden, the surrounding stat card (`_buildStatsCard`) must
  also be absent, along with the preceding spacer — no empty container and no
  leftover vertical gap.
- For a standard (non-rolling) session, Duration and Rest Time continue to appear
  exactly as they do today.
- Group cards (Strength, Cardio, Sports, Isometric), the session note field, and
  the calendar card must continue to appear for both session types.
- No change to how duration or rest time is calculated for any session type.
- No schema changes, repository changes, or new state methods.

## Acceptance Criteria
- [ ] Opening the summary of a rolling session shows neither a Duration stat nor a
      Rest Time stat (neither the label nor the value).
- [ ] When no top stats remain for a rolling session, the stat card and its spacer
  are fully absent with no empty container and no residual gap.
- [ ] Opening the summary of a standard session still shows both Duration and Rest
      Time, identical to today's behaviour.
- [ ] Group cards, session note, and calendar card appear unchanged for both session
      types.

## Scenarios
- Rolling session summary: DURATION label absent; REST TIME label absent; top
  stats card absent; group cards, note card, and calendar card still present.
- Standard session summary: DURATION label present; REST TIME label present;
  existing top stats layout unchanged.

## Iteration 1
### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
Only `lib/features/session/session_summary_screen.dart` and
`test/screen_widget_test.dart`.

### Implementation Steps

**`lib/features/session/session_summary_screen.dart`**

1. [ ] In the sliver child list where `_buildHeaderCard(theme)` is followed by
  `const SizedBox(height: 16), _buildStatsCard(theme),` (currently around
  [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart#L606)),
  replace the unconditional spacer and stats card with a single conditional
  spread so no widget is emitted at all for rolling sessions:
  `if (!widget.workoutState.isRollingSession) ...[const SizedBox(height: 16), _buildStatsCard(theme)]`.
2. [ ] Keep the condition at the call site instead of inside `_buildStatsCard()` so
  the empty spacing is removed together with the card.
3. [ ] Do not change `_buildStatsCard()`, `_formatDuration()`,
  `_formatDurationOrZero()`, summary aggregation, or rest-time calculation.

**`test/screen_widget_test.dart` — `SessionSummaryScreen` group**

4. [ ] Update the existing test
  `'rolling session uses same top stats layout as non-rolling'`
  at [test/screen_widget_test.dart](test/screen_widget_test.dart#L3393):
  rename it to reflect the new requirement and change its expectations to
  `findsNothing` for both `find.text('DURATION')` and
  `find.text('REST TIME')`. Keep the existing `findsNothing` assertion for
  `EXERCISES` unchanged.
5. [ ] Add a new render regression test in the same `SessionSummaryScreen` group for
  a standard session (`isRolling: false`) asserting both `DURATION` and
  `REST TIME` still render together.
6. [ ] Confirm existing summary tests that cover top stats, group cards, note field,
  and calendar card still pass. If any current test implicitly assumes the top
  stats area always renders, update that assumption only for rolling-session
  coverage and leave standard-session assertions unchanged.
7. [ ] Run the focused suite: `flutter test test/screen_widget_test.dart`.

## Progress
- [x] Guard the top stats spacer and card behind `!isRollingSession`
- [x] Update the existing rolling-session summary render test
- [x] Add a standard-session render regression test for both labels
- [x] Reconfirm group cards, note, and calendar rendering coverage
- [x] Run `flutter test test/screen_widget_test.dart`

## Feedback
Post-review follow-up complete: added explicit rolling-session coverage for the
unchanged lower summary sections and updated session summary documentation to
match the implemented top-stats behavior.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.
