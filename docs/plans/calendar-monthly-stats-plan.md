# Feature: calendar-monthly-stats

## Overview
Add a compact monthly stats strip below the calendar grid that fills the remaining vertical space after the grid without causing the page to scroll. The strip shows: total completed sessions, total training time, current streak, and a per-modality dot breakdown for modalities that have at least one completed session this month.

## Requirements
- Total sessions completed this month
- Total training time this month (sum of `endedAtMs - startedAtMs` across completed sessions)
- Current streak (consecutive days ending at today with a completed session), computed from up to 90 days of history — not just the current month
- Modality breakdown row: small colored dot + count for each modality with ≥1 completed session this month
- No cards or extra containers — flat layout on gradient background
- Muted uppercase labels, prominent values — consistent with `_StatPill` in `session_summary_screen.dart`
- If no data for the month, show `—` instead of `0`
- Modality dots only render for modalities present this month — no fixed list
- Entire screen (grid + strip) must fit viewport with no scrolling

## Iteration 1

### DB Changes
_None._ All required data is already available via `getSessionsByDateRange` and the loaded `CalendarEntry` map in `CalendarState`.

### Backend Changes (@developer)
1. [ ] Add four computed getters to `CalendarState` derived from `_entriesByDay`:
   - `int get completedSessionCount` — count of entries where `isCompleted == true`
   - `int get totalTrainingMs` — sum of `(entry.session!.endedAtMs! - entry.session!.startedAtMs)` for entries where `isCompleted == true && session != null && session.endedAtMs != null`
   - `Map<String?, int> get modalityBreakdown` — group completed entries by `entry.modality`, count per modality key (null = Free Training)
2. [ ] Add a `_streakDays` private `int` field (default 0) to `CalendarState`.
3. [ ] Add `int get streakDays` public getter.
4. [ ] In `_loadMonth()`, after grouping entries, call `_computeStreak()` which:
   - Uses `_repository.getSessionsByDateRange(now - 90 days, now)` (already available on repository)
   - Filters to sessions where `endedAtMs != null`
   - Converts each to its calendar day (UTC midnight via `OmniDateUtils.startOfDayMs`)
   - Builds a `Set<int>` of completed day timestamps
   - Counts consecutive days backwards from today (inclusive) that are present in the set
   - Stores result in `_streakDays`
5. [ ] `_computeStreak()` must be a non-fatal helper — wrap in try/catch, default to 0 on error.
6. [ ] All four exposed values must remain in sync: they are recomputed whenever `notifyListeners()` is called after `_loadMonth()`, so they need to be pure getters computed from `_entriesByDay` and `_streakDays` — no separate caching needed.

### Frontend Changes (@developer)
1. [ ] In `_CalendarScreenState.build()`, restructure the `Column` inside `ListenableBuilder`:
   - Keep `_MonthHeader` and `_WeekDayRow` unchanged.
   - Change ** `Expanded` wrapping `_MonthGrid`** to a plain child (no `Expanded`).
   - Add `shrinkWrap: true` and `physics: NeverScrollableScrollPhysics()` to the `GridView.builder` inside `_MonthGrid` so the grid takes its natural height.
   - After the grid, add `Expanded(child: _MonthlyStatsStrip(...))` to fill the remaining space.
2. [ ] Create private widget `_MonthlyStatsStrip` (in `calendar_screen.dart`, below the existing sub-widgets):

   **Constructor:**
   ```dart
   class _MonthlyStatsStrip extends StatelessWidget {
     final int completedSessions;
     final int totalTrainingMs;
     final int streakDays;
     final Map<String?, int> modalityBreakdown;
     ...
   }
   ```

   **Layout (from top to bottom within Expanded):**
   - Thin horizontal divider: `Divider(height: 1, thickness: 0.5, color: OmniTheme.textSecondary.withOpacity(0.15))`
   - `Expanded` inner content, vertically centered with `Column(mainAxisAlignment: MainAxisAlignment.center)`
   - Stats row: three `_CompactStat` cells in a `Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly)`
     - Cell 1: label `'SESSIONS'`, value `completedSessions > 0 ? '$completedSessions' : '—'`
     - Cell 2: label `'TIME'`, value from `_formatTrainingTime(totalTrainingMs)` or `'—'` if 0
     - Cell 3: label `'STREAK'`, value `streakDays > 0 ? '${streakDays}d' : '—'`
   - `SizedBox(height: 12)`
   - Modality dots row (only if `modalityBreakdown.isNotEmpty`)

   **`_CompactStat` widget (private, nested):**
   - Label: uppercase, `fontSize: 10`, `fontWeight: FontWeight.w600`, `letterSpacing: 1.2`, `color: OmniTheme.textSecondary.withOpacity(0.55)`
   - Value: `fontSize: 22`, `fontWeight: FontWeight.w700`, `color: OmniTheme.textPrimary`, `letterSpacing: -0.5`
   - Layout: `Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min)`

   **Modality dots row:**
   - `Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min)` with `Wrap` for overflow safety
   - Each item: `Container(width: 8, height: 8, decoration: BoxDecoration(color: ModalityColors.forModality(modality), shape: BoxShape.circle))` + `SizedBox(width: 4)` + `Text('$count', style: TextStyle(fontSize: 12, color: OmniTheme.textSecondary.withOpacity(0.75), fontWeight: FontWeight.w600))` + `SizedBox(width: 14)` gap between items
   - Sort items descending by count so most-used modality appears first
   - Use `ModalityColors.forModality(modality)` for dot color (handles null → freeTraining purple)

3. [ ] Add private helper `_formatTrainingTime(int ms)` to `_MonthlyStatsStrip` (or as a top-level function in the file):
   - `< 60s` → `'${seconds}s'`
   - `< 3600s` → `'${minutes}m'`
   - `≥ 3600s` → `'${hours}h ${minutes}m'` (omit minutes if 0)
   - Return `'—'` if `ms == 0`

4. [ ] Pass data from `CalendarState` to `_MonthlyStatsStrip` in the build method:
   ```dart
   _MonthlyStatsStrip(
     completedSessions: widget.calendarState.completedSessionCount,
     totalTrainingMs: widget.calendarState.totalTrainingMs,
     streakDays: widget.calendarState.streakDays,
     modalityBreakdown: widget.calendarState.modalityBreakdown,
   )
   ```

5. [ ] While `calendarState.isLoading` is true, render a loading shimmer or simply omit stats strip (render `const SizedBox.shrink()` as the Expanded child) to avoid flashing `—` during load.

### Implementation Steps
1. [ ] Add `completedSessionCount`, `totalTrainingMs`, `modalityBreakdown` getters to `CalendarState`.
2. [ ] Add `_streakDays` field + `streakDays` getter + `_computeStreak()` method to `CalendarState`, called at end of `_loadMonth()`.
3. [ ] In `_MonthGrid`, add `shrinkWrap: true` and `physics: NeverScrollableScrollPhysics()` to `GridView.builder`.
4. [ ] Remove `Expanded` from the `_MonthGrid` wrapper in `_CalendarScreenState.build()`.
5. [ ] Add `Expanded(child: _MonthlyStatsStrip(...))` after the grid (within the isLoading branch: substitute `const SizedBox()` when loading).
6. [ ] Implement `_MonthlyStatsStrip` and `_CompactStat` widgets with `_formatTrainingTime` helper.
7. [ ] Smoke-test on web: verify no scroll, strip fills remaining space, stats update when navigating months, streak reflects cross-month data.
8. [ ] Test edge cases: month with zero sessions (all `—`), month with 1 modality (single dot), today is first of month (streak = 1 if today has session).

## Progress
- [x] Add computed getters to CalendarState
- [x] Add `_streakDays` field + `_computeStreak()` to CalendarState
- [x] Make `_MonthGrid`'s GridView non-scrolling with shrinkWrap
- [x] Remove `Expanded` from `_MonthGrid` wrapper in screen build
- [x] Add `Expanded(_MonthlyStatsStrip(...))` below grid
- [x] Implement `_MonthlyStatsStrip` + `_CompactStat` widgets
- [x] Add `_formatTrainingTime` helper
- [ ] Smoke-test and edge-case verification

## Acceptance Criteria
- [ ] Stats strip is visible on screen without scrolling on a standard phone viewport
- [ ] Strip fills exactly the vertical space between the calendar grid bottom and the safe-area bottom
- [ ] Sessions count, time, and streak all show `—` when the loaded month has no completed sessions
- [ ] Streak reflects cross-month history (e.g., a 10-day streak that started last month reads `10d`)
- [ ] Modality dots only appear for modalities with ≥1 completed session in the month
- [ ] Dot colors match `ModalityColors` constants used elsewhere in the app
- [ ] Free Training sessions (null modality) appear with the purple `freeTraining` dot
- [ ] No cards, borders, or shadow containers around the strip — flat on gradient
- [ ] Typography: muted uppercase labels, large bold white values (no teal/primary accent color)
- [ ] Navigating to a different month updates all stats

## Files Affected
- `lib/state/calendar/calendar_state.dart` (add 4 getters + streak logic)
- `lib/features/calendar/calendar_screen.dart` (restructure layout + add strip widget)

## Notes
- `_computeStreak()` fetches the last 90 days of sessions at every `_loadMonth()` call. This is a lightweight read and acceptable for the current Hive/Mock backends.
- The 90-day window caps the streak display at 90. If we later need longer streaks, increase the window or add a dedicated repository method.
- `shrinkWrap: true` on the GridView is safe here because the Column is inside `SafeArea` inside a `Scaffold` with `extendBodyBehindAppBar: true`. The GridView won't be inside another scrollable, so `NeverScrollableScrollPhysics()` is correct.
- Do NOT use the teal `colorScheme.primary` for stat values — use `OmniTheme.textPrimary` (white 90%). This matches the "prominent values" requirement and avoids the teal accent reserved for interactive elements.
- Labels must match the style from `_StatPill` semantically (muted + uppercase) but adapted to be more compact (smaller font) since space is limited.

---

@developer — Please proceed with the implementation above. Both state and UI changes are scoped to two files: `lib/state/calendar/calendar_state.dart` and `lib/features/calendar/calendar_screen.dart`.
