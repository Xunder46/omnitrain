# Feature: session-summary-group-chips

## Overview
Redesign the progress indicator in the Session Summary screen. Remove the standalone `+x kg volume vs last time` card. Replace it with an inline progress chip on each modality-group header row inside the Exercises card. The chip shows a per-group delta vs the previous session — volume for strength, duration for cardio/isometric, round count for rounds — with directional arrows coloured teal (improvement) or muted-red (regression).

## Requirements
- Remove `_buildVolumeComparison` card entirely (the `Widget _buildVolumeComparison(ThemeData)` method and its call site in the scroll list).
- Always render exercise group headers (currently only shown in multi-modality sessions). Single-modality sessions must also show the group header row so the chip has a place to live.
- Group header row layout: `[LABEL] · [aggregate] ············ [chip]` (label left-anchored, chip right-anchored using `Expanded` + `Row`).
- Chip content per group:
  - `strength` → volume delta in kg: `↑ +6.6 kg` / `↓ -2 kg`
  - `cardio` → total timed duration delta, formatted in minutes and/or seconds: `↑ +2 min` / `↓ -30s`
  - `rounds` → total round count delta: `↑ +2 rounds`
  - `isometric` → total drill duration delta: `↑ +10s`
- Chip direction/color rules:
  - positive delta → teal up arrow `↑` using `theme.colorScheme.primary`
  - negative delta → down arrow `↓` using `theme.colorScheme.error.withOpacity(0.8)`  (muted-red)
  - zero delta → `—` in `onSurface.withOpacity(0.4)`
  - no previous data → `—` in `onSurface.withOpacity(0.4)`
- Chip text style: `labelSmall`, same font size as the existing group label. No background pill/container — plain text only to keep it compact.
- Comparison is against the single most-recent completed previous session overall (same logic as current `compareToPreviousSession`). If that session had no exercises of a given group, that group's chip shows `—`.
- No new repository methods are needed — use existing `getSessionSegments`, `getSegmentEfforts`, `getEffortObservations`, `getRoundInstances`, `getTimedInstances`.

## Iteration 1

### DB Changes (@dba)
1. [ ] Add `GroupDelta` class to `lib/core/models/session_summary.dart`:
   ```dart
   class GroupDelta {
     final double? delta;   // raw numeric delta; null = no comparison available
     final String unit;     // 'kg' | 'ms' | 'rounds'
     final bool hasPrevious;
     const GroupDelta({this.delta, required this.unit, required this.hasPrevious});
   }
   ```
2. [ ] Add private method `_computeGroupStats(String sessionId) → Future<Map<String, double>>` to `SessionSummaryService`:
   - Iterates `getSessionSegments` → `getSegmentEfforts` for each segment.
   - For `effortKind == 'set'`: reuse existing `_computeVolumeFromObservations`; accumulate into `stats['strength']`.
   - For `effortKind == 'timed'`: call `_repository.getTimedInstances(effort.id)`, sum `TimedInstance.elapsedMs`; accumulate into `stats['cardio']`.
   - For `effortKind == 'round'`: call `_repository.getRoundInstances(effort.id)`, count instances; accumulate into `stats['rounds']`.
   - For `effortKind == 'drill'`: call `_repository.getTimedInstances(effort.id)`, sum `TimedInstance.elapsedMs`; accumulate into `stats['isometric']`.
   - Returns map with only keys that had non-zero data.
3. [ ] Add public method `compareGroupsToPreviousSession(TrainingSession, SessionSummary) → Future<Map<String, GroupDelta>>` to `SessionSummaryService`:
   - Re-use the existing logic to find `previous` (most recent completed session prior to current).
   - If no previous session, return map with `GroupDelta(delta: null, unit: ..., hasPrevious: false)` for each group present in `currentSummary`.
   - Compute `prevStats = await _computeGroupStats(previous.first.id)`.
   - Build current group stats from `currentSummary` fields (no extra DB reads):
     - `strength` current = `currentSummary.totalVolume`, unit = `'kg'`
     - `cardio` current = `currentSummary.totalCardioDurationMs.toDouble()`, unit = `'ms'`
     - `rounds` current = `currentSummary.totalRounds.toDouble()`, unit = `'rounds'`
     - `isometric` current = `currentSummary.totalDrillDurationMs.toDouble()`, unit = `'ms'`
   - For each group where `currentValue > 0`: compute `delta = current - (prevStats[group] ?? 0)`, emit `GroupDelta(delta: delta, unit: unit, hasPrevious: true)`.
   - Only emit an entry for a group if the current session has data for it (i.e., skip a group key entirely if the current session has zero for that group — the chip only renders on groups that appear in the exercise list).

### Backend Changes (@developer)
No new state classes or repositories required.

### Frontend Changes (@developer)
1. [ ] In `_SessionSummaryScreenState`:
   - Add field: `Map<String, GroupDelta> _groupDeltas = {}`.
   - In `_loadAsyncData`: add call `final groupDeltas = await widget.sessionSummaryService.compareGroupsToPreviousSession(currentSession, _summary);`, store in `_groupDeltas` inside `setState`.
2. [ ] Remove `_buildVolumeComparison` widget method entirely.
3. [ ] Remove `_buildVolumeComparison(theme)` call and its preceding `SizedBox(height: 16)` from the `SliverChildListDelegate` list in `build`.
4. [ ] Update `_buildExerciseListSection`:
   - Remove the `isMultiModality` guard that currently hides headers for single-modality sessions; always iterate the grouped path (group headers + exercise tiles).
   - For single-modality sessions, `orderedGroupKeys` will have exactly one entry — render its header + tiles without dividers.
   - Pass `_groupDeltas[key]` as a new `delta` argument when calling `_buildExerciseGroupHeader`.
5. [ ] Update `_buildExerciseGroupHeader` signature to accept `GroupDelta? delta`.
6. [ ] Inside `_buildExerciseGroupHeader`, append a `_buildGroupComparisonChip(theme, delta)` widget right-aligned:
   ```dart
   // Replace the existing plain Row with:
   Row(
     children: [
       Text(label.toUpperCase(), style: ...),   // existing
       if (aggregate.isNotEmpty) ...[
         const SizedBox(width: 8),
         Text('· $aggregate', style: ...),       // existing
       ],
       const Spacer(),
       _buildGroupComparisonChip(theme, delta),
     ],
   )
   ```
7. [ ] Add private method `_buildGroupComparisonChip(ThemeData theme, GroupDelta? delta)`:
   - If `delta == null || !delta.hasPrevious || delta.delta == null` → return `Text('—', style: labelSmall dimmed)`.
   - If `delta.delta == 0` → return `Text('—', style: labelSmall dimmed)`.
   - Build label string: prefix sign (`+`/`-`), format value by unit:
     - `'kg'` → `_formatNumber(delta.delta!.abs()) + ' kg'`
     - `'ms'` → use `_formatDurationDelta(delta.delta!.abs().toInt())` (new helper, or reuse `_formatDuration`)
     - `'rounds'` → `'${delta.delta!.abs().toInt()} round${delta.delta!.abs() >= 2 ? "s" : ""}'`
   - Arrow + color: positive → `'↑'` + `theme.colorScheme.primary`;  negative → `'↓'` + `theme.colorScheme.error.withOpacity(0.8)`.
   - Return `Text('$arrow ${sign}$formattedValue', style: theme.textTheme.labelSmall?.copyWith(color: arrowColor))`.
8. [ ] Add private helper `_formatDurationDelta(int ms)` that formats a duration as:
   - `>= 60000 ms` → `'X min'` (rounded to nearest minute, e.g. 90000 ms → `'2 min'`)
   - `< 60000 ms` → `'Xs'` (seconds, e.g. 5000 ms → `'5s'`)

### Implementation Steps
1. [ ] Add `GroupDelta` model class.
2. [ ] Add `_computeGroupStats` helper to service, using `getRoundInstances` / `getTimedInstances`.
3. [ ] Add `compareGroupsToPreviousSession` method to service.
4. [ ] Update screen state: add `_groupDeltas` field, populate in `_loadAsyncData`.
5. [ ] Remove `_buildVolumeComparison` method and its call site.
6. [ ] Remove `isMultiModality` guard so single-modality sessions also render group headers.
7. [ ] Pass `delta` through `_buildExerciseGroupHeader` and render chip.
8. [ ] Add `_buildGroupComparisonChip` widget method.
9. [ ] Add `_formatDurationDelta` helper.
10. [ ] Smoke-test: multi-modality session with previous data shows per-group chips; single modality session shows single chip; first-ever session shows `—` chips.

## Progress
- [x] Add `GroupDelta` model to `session_summary.dart`
- [x] Add `_computeGroupStats` private helper to `SessionSummaryService`
- [x] Add `compareGroupsToPreviousSession` public method to `SessionSummaryService`
- [x] Add `_groupDeltas` field and populate in `_loadAsyncData`
- [x] Remove `_buildVolumeComparison` method and call site
- [x] Remove `isMultiModality` guard; always show group headers
- [x] Update `_buildExerciseGroupHeader` to accept and render `GroupDelta?`
- [x] Add `_buildGroupComparisonChip` and `_formatDurationDelta` helpers

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

@developer — Please proceed with Iteration 1 above. All changes are scoped to three files:
- `lib/core/models/session_summary.dart` (add `GroupDelta`)
- `lib/core/services/session_summary_service.dart` (add helpers + public method)
- `lib/features/session/session_summary_screen.dart` (state, chip rendering, remove old card)
