# Feature: Stats Screen Progress Rework

## Overview

Replace the current Stats screen's training-frequency bar chart and rest-time
line chart with progress-focused views: an estimated-strength (e1RM) trend,
a total volume trend, a recent-PR list, and a cardio pace/distance trend.
The screen's all-time summary row is preserved unchanged.

## Requirements

- Remove the per-day session frequency bar chart and the REST TIME section.
- Keep the ALL TIME summary row (sessions, total time, streak) exactly as-is.
- Add a **Strength** section covering the top-3 most-frequently-trained lifts.
  - e1RM trend (estimated 1-rep max, Epley formula, one point per training day).
  - Volume trend (total weight moved per training day).
  - Recent PRs list (when a lift reaches a new all-time e1RM high).
- Add a **Cardio** section covering the top-2 most-frequently-performed timed
  activities.
  - Pace and/or distance trend, one point per training day.
- Effort-type keying: discriminate by `SegmentEffort.effortKind`, NOT session
  `modality`. A `set` effort inside a null-modality session counts as strength;
  a `timed` effort inside a lifting-modality session counts as cardio.
- Each section has an independent empty state.
- No new database tables, no new model fields, no new repository methods.

## Acceptance Criteria

- [ ] Per-day session BarChart no longer appears on the Stats screen.
- [ ] REST TIME section no longer appears on the Stats screen.
- [ ] ALL TIME row (sessions, time, streak) renders identically to today.
- [ ] Strength section shows e1RM trend for up to 3 auto-detected top lifts, one
      chronological point per training day.
- [ ] Volume trend shows total weight moved per training day across tracked lifts.
- [ ] Recent-PR list entries agree with the e1RM trend (no silent divergence).
- [ ] Cardio section shows pace/distance trend for up to 2 auto-detected
      top cardio activities, one chronological point per training day.
- [ ] A `set` effort inside a Free-Training (null modality) session appears in
      the Strength section.
- [ ] A `timed` effort inside a lifting-modality session appears in the Cardio
      section.
- [ ] A lifting session containing zero `set` efforts contributes nothing to
      Strength charts.
- [ ] With no strength history → Strength section shows empty state; Cardio
      section is unaffected.
- [ ] With no cardio history → Cardio section shows empty state; Strength
      section is unaffected.
- [ ] All existing unit tests still pass (or are updated per audit rules below).
- [ ] Axis value labels render as a single-line string on all progress charts (value + unit never wraps).
- [ ] Top y-axis value label has visible clearance from chart title/section content above.
- [ ] Y-axis labels are sparse enough that adjacent labels do not touch in the chart's available height.
- [ ] Strength e1RM, strength volume, and cardio charts use the same gutter width and label-spacing policy.
- [ ] Plotted series geometry (line path, points, area fill) is unchanged from current behavior.

## Scenarios

### Effort-type keying — strength set in null session
A completed session with `modality = null` contains one `SegmentEffort` with
`effortKind = 'set'`, weight = 80 kg, reps = 5.  
Expected: exercise appears in the Strength section; e1RM ≈ 93.3 kg.

### Effort-type keying — cardio in lifting session
A completed session with `modality = 'resistance_lifting'` contains one
`SegmentEffort` with `effortKind = 'timed'`, distance = 5 000 m, duration = 1 800 s.  
Expected: exercise appears in the Cardio section.

### Lifting session with no sets
A completed session with `modality = 'resistance_lifting'` contains no
`SegmentEffort` rows with `effortKind = 'set'`.  
Expected: no data flows into Strength charts from this session.

### Single-rep set
One `set` effort, weight = 120 kg, reps = 1.  
Expected: e1RM = 120.0 (Epley: `120 × (1 + 1/30)` ≈ 124. **Note**: for
reps = 1 the formula returns weight × (1 + 1/30) = 1.033× — this is fine and
standard. No special-casing needed.)

### Zero / bodyweight set
One `set` effort, weight = 0 or null, any reps.  
Expected: skipped (contributes neither to e1RM trend nor to volume).

### Tie-breaking in top-N detection
Two exercises both trained on exactly N distinct days.  
Expected: deterministic order (alphabetical by exercise name, ascending).

---

## Iteration 1

### Phase 1: Data Layer — NO CHANGES NEEDED

No new tables, no new model classes, no new repository methods. All required
data is accessible through the existing repository interface:

| Data needed | Repository call |
|-------------|-----------------|
| All completed sessions | `getAllSessions()` |
| Segments per session | `getSessionSegments(sessionId)` |
| Efforts per segment | `getSegmentEfforts(segmentId)` |
| Observations per effort | `getEffortObservations(effortId)` |
| Timed instances per effort | `getTimedInstances(effortId)` |
| Exercise metadata (name) | `getExerciseById(id)` |

### Phase 2: New Service + UI (@developer)

#### 2.1 — New model file: `lib/core/models/stats_progress.dart`

Define plain Dart value classes (no Flutter imports):

```
StatsProgressData
  topLifts: List<LiftProgress>
  topCardio: List<CardioProgress>
  recentPRs: List<StatsPR>

LiftProgress
  exerciseName: String
  e1RmTrend: List<TrendPoint>   // x = DateTime (training day), y = e1RM kg
  volumeTrend: List<TrendPoint> // x = DateTime (training day), y = total volume kg

CardioProgress
  exerciseName: String
  trend: List<CardioTrendPoint> // date, durationSecs, distanceM (nullable), paceSecPerKm (nullable)

TrendPoint
  date: DateTime
  value: double

CardioTrendPoint
  date: DateTime
  durationSecs: int
  distanceM: double?         // null if no distance logged
  paceSecPerKm: double?      // null if no distance logged; = durationSecs / (distanceM/1000)

StatsPR
  exerciseName: String
  e1Rm: double
  date: DateTime
```

#### 2.2 — New service: `lib/core/services/stats_progress_service.dart`

Pure Dart, takes `WorkoutRepository`. Public surface:

```dart
// Top-level constants (easy to adjust):
static const int kTopLiftCount = 3;
static const int kTopCardioCount = 2;

/// Compute all progress data for the Stats screen.
Future<StatsProgressData> computeProgressData();
```

**Internal algorithm:**

1. **Load all completed sessions** (`endedAtMs != null`).
2. **Walk segments → efforts** for each session. For each `SegmentEffort`:
   - If `effortKind == 'set'` → classify as **strength**. Load observations.
     Record `(exerciseId, sessionDay, weight, reps)` tuples.
   - If `effortKind == 'timed'` → classify as **cardio**. Load timed instances
     (filter `state == TimedState.finished`) and distance observations
     (`metricId == MetricIds.distance`). Record `(exerciseId, sessionDay,
     durationSecs, distanceM?)` tuples.
   - Other effort kinds (`drill`, `round`) → skip.
3. **Top-N auto-detection:**
   - For strength: count distinct `sessionDay` values per `exerciseId`. Sort
     descending by count, then ascending by name for ties. Take first
     `kTopLiftCount` exerciseIds.
   - For cardio: same logic, take first `kTopCardioCount` exerciseIds.
4. **E1RM formula** (Epley): `e1RM = weight × (1 + reps / 30.0)`.
   - Skip if `weight == null || weight <= 0 || reps == null || reps <= 0`.
   - For reps = 1 the formula still applies (returns `weight × 1.033...`).
5. **Trend aggregation (per exercise, per training day):**
   - e1RM: group all set tuples by day; for each day emit the **maximum**
     e1RM across all sets that day.
   - Volume: group by day; for each day sum `reps × weight` across all sets.
   - Sort days chronologically.
6. **PR detection:** Walk the e1RM trend in chronological order. A new PR is
   recorded when the current day's e1RM exceeds the running best. Collect the
   most recent N PRs across all tracked lifts (N = 5, easily adjustable).
7. **Cardio trend:** Per exercise per day, aggregate:
   - `durationSecs` = sum of all finished `TimedInstance.actualDurationSecs`
     for that exercise on that day.
   - `distanceM` = sum of all `metric-distance` observations for that exercise
     on that day (null if none exist).
   - `paceSecPerKm` = `durationSecs / (distanceM / 1000)` when both are
     present and `distanceM > 0`.
   - Sort days chronologically.

**Performance note:** The service makes O(sessions × segments × efforts)
async calls. For any foreseeable athlete history this is acceptable on-device.
No caching is needed for v1.

#### 2.3 — Rework `lib/features/stats/stats_screen.dart`

- **Remove** all code relating to `_dayCounts`, `_restAvgsByModality`,
  `_thirtyDaysAgo`, `_today`, `_buildActivityCard`, `_buildRestTimeCard`.
- **Keep** `_buildAggregateCard`, `_buildEmptyState`, `_StatsPill`,
  `_formatDuration`, `_buildSectionLabel`, and all aggregate loading logic.
- **Add** `_progressData: StatsProgressData?` loaded via `_loadData()`.
- **Add** to `_loadData()`: call `StatsProgressService(widget.workoutState.repository).computeProgressData()` and store result.
- **Add** `_buildStrengthSection(...)` — renders:
  - A `STRENGTH` section label.
  - For each lift in `_progressData.topLifts`:
    - Small `OmniSurface` card with exercise name, e1RM line chart
      (`fl_chart` `LineChart`, dots enabled, chronological x-axis).
    - Volume trend line chart below it.
  - If `topLifts` is empty: single `OmniSurface` empty-state card ("No
    strength history yet. Log your first sets to see trends here.").
- **Add** `_buildPRList(...)` — renders inside the Strength section:
  - Short tile list of recent PRs (exercise name + e1RM value + date).
  - Hidden when `recentPRs` is empty.
- **Add** `_buildCardioSection(...)` — renders:
  - A `CARDIO` section label.
  - For each activity in `_progressData.topCardio`:
    - `OmniSurface` card with activity name and a pace/distance line chart.
    - Show pace (sec/km) as primary line; distance as secondary if present.
  - If `topCardio` is empty: single `OmniSurface` empty-state card ("No
    cardio history yet. Log timed efforts to see trends here.").

**Imports to remove:** `dart:math` (if no longer used), `modality.dart`,
`modality_colors.dart`, `calendar_state.dart` (move streak logic to keep it
or keep the CalendarState call — check which parts still need it).

#### 2.4 — New test file: `test/stats_progress_test.dart`

All tests are pure unit tests (no widget pump needed).

**e1RM calculation:**
- `test('Epley formula: 5 reps at 100 kg → 116.67')` (allow ±0.01 tolerance).
- `test('Epley formula: 1 rep at 120 kg → 124.0')`.
- `test('Epley formula: 0 weight → skipped (returns null)')`.
- `test('Epley formula: 0 reps → skipped (returns null)')`.

**Top-N auto-detection:**
- Seed 4 exercises with training-day counts [5, 5, 3, 1]. Expect top 3 to be
  the three highest; among the tied exercises (count=5) expect alphabetical order.
- Verify kTopLiftCount cap is respected.
- Same for cardio with kTopCardioCount = 2.

**Trend aggregation:**
- One exercise, two sets on Day 1 (e1RMs: 100, 110) and one set on Day 2 (e1RM: 90).
  Expect trend = [{Day1, 110}, {Day2, 90}] (max per day, chronological).

**Volume aggregation:**
- One exercise, Day 1: two sets (5×100, 3×80). Volume = 740. Day 2: 10×60. Volume = 600.

**Effort-type keying:**
- Create a session with `modality = null` containing one `set` effort. Verify
  the exercise appears in `topLifts` and NOT in `topCardio`.
- Create a session with `modality = 'resistance_lifting'` containing one `timed`
  effort. Verify the exercise appears in `topCardio` and NOT in `topLifts`.
- Create a session with `modality = 'resistance_lifting'` containing ONLY a
  `drill` effort. Verify neither section receives data (drill is out of scope).

**Empty states:**
- Repository with only `set` efforts → `topCardio` is empty, `topLifts` is
  non-empty.
- Repository with only `timed` efforts → `topLifts` is empty, `topCardio`
  is non-empty.
- Empty repository → both are empty.

**PR detection:**
- Seed 3 training days for one exercise with e1RMs [100, 95, 110].
  Expect PRs at Day 1 (first ever = PR) and Day 3 (new high = PR). Day 2 is not a PR.

**Session-summary vs stats PR consistency audit:**
- Seed a single session where `bestWeight = 110 kg × 1 rep`.
  Session-summary `computePRs` yields a weight-PR at 110 kg.
  Stats e1RM for the same set = `110 × (1 + 1/30) ≈ 113.67`.
  Assert `statsPR.e1Rm >= sessionPR.newBest` (e1RM is never less than
  raw weight for any positive rep count — this is mathematically guaranteed
  by the Epley formula, and the test documents that invariant).

#### 2.5 — Audit `test/screen_widget_test.dart` — StatsScreen group

| Existing test | Action |
|---|---|
| `'shows Stats AppBar title'` | **Keep** unchanged. |
| `'zero state renders without crash or phantom data'` | **Update**: remove `find.byType(BarChart)` assertion; remove `find.text('ACTIVITY')` assertion; add `find.text('STRENGTH')` → `findsNothing`. |
| `'aggregate totals reflect seeded completed sessions'` | **Update**: remove `find.byType(BarChart)` assertion; keep all `OmniSurface` / text assertions for aggregate row. |
| `'30-day activity excludes sessions outside the window'` | **Delete** entirely — tests a removed feature (the 30-day bar chart). |
| `'rolling sessions are excluded from duration aggregates'` | **Keep** — tests the aggregate row, which is unchanged. Remove `BarChart` assertion if present. |
| `totalSessionsShownInChart` helper function | **Delete** — no longer needed. |

### Files Affected

```
lib/core/models/stats_progress.dart                     (new)
lib/core/services/stats_progress_service.dart           (new)
lib/features/stats/stats_screen.dart                    (rework)
test/stats_progress_test.dart                           (new)
test/screen_widget_test.dart                            (audit: StatsScreen group)
```

### Notes

- **No DBA work required**. All data for the new views exists in the current
  schema and is reachable through the existing repository interface.
- `StatsProgressService` must work identically against `MockWorkoutRepository`
  (web/test) and `HiveWorkoutRepository` (production) because it depends only
  on the `WorkoutRepository` interface.
- The Epley formula (`weight × (1 + reps/30)`) is the standard estimation
  method used across the industry and is consistent with the spirit of the
  "widely accepted" requirement. Alternative formulas (Brzycki, Lander) give
  very similar results for 1–12 reps.
- **Chart library**: continue using `fl_chart` (already a dependency) for all
  new charts.
- **Distance unit preference**: check `SettingsState.preferredDistanceUnit`
  and convert metres to the preferred unit for display. The stored observations
  are always in metres (`unit-m`).
- **Empty state independence**: `_buildStrengthSection` and `_buildCardioSection`
  are fully independent render paths. Neither queries the other's data.
- The `kTopLiftCount = 3` and `kTopCardioCount = 2` constants live at the top
  of `StatsProgressService` so any future adjustment is a single-line change.

## Progress

- [x] 2.1 Create `lib/core/models/stats_progress.dart`
- [x] 2.2 Create `lib/core/services/stats_progress_service.dart`
- [x] 2.3 Rework `lib/features/stats/stats_screen.dart`
- [x] 2.4 Create `test/stats_progress_test.dart`
- [x] 2.5 Audit and update StatsScreen group in `test/screen_widget_test.dart`
- [x] 2.6 Post-review fix 1: cardio pace unit conversion (s/km → s/mi) + stale nav doc
- [x] 2.7 Post-review fix 2: weight unit conversion for e1RM, volume, and PRs + weight unit regression test + docs updated

**Phase 2: Complete** — All 162 targeted tests pass after post-review fixes.

---

## Iteration 2

### Analysis

Two independent improvements to the already-shipped stats screen:

**PR 1 — Chart legibility:** All trend charts currently hide both axes (`showTitles: false`). This means an athlete sees only slope direction — no numbers, no dates. The single-point fallback for lifts and cardio renders as bare inline text inside an `OmniSurface` card, which looks broken compared to charted cards. Exercise names in chart headers and PR rows are also truncated by `overflow: TextOverflow.ellipsis`.

Scope: purely UI — `stats_screen.dart` (axis rendering, single-point widgets, text overflow) and a new pure-Dart `ChartAxisHelper` utility. No model or service changes.

**PR 2 — PR list dedupe:** `StatsProgressService` adds a `StatsPR` entry every time a new running-best e1RM is recorded. A frequent lifter sees the same exercise repeated in the Recent PRs list (screenshot: Hammer Curl appears three times in five rows). "Recent PRs" should read as standing records, not a changelog.

Scope: one algorithm change in `stats_progress_service.dart` (deduplicate by exercise name, keep current best) and the corresponding test updates.

Both PRs touch no database layer and require no DBA work.

---

### PR 1: Chart Legibility

#### 1.1 — New utility: `lib/core/utils/chart_axis_helper.dart`

Pure Dart, no Flutter imports. Contains:

```dart
/// Axis bounds for a trend chart (min, max, and a nice interval for ticks).
class ChartAxisBounds {
  final double min;
  final double max;
  final double interval; // distance between adjacent tick labels
}

class ChartAxisHelper {
  /// Compute padded axis bounds from a list of data values.
  ///
  /// - Pads each side by [paddingFraction] × range.
  /// - Clamps min to 0.
  /// - Adds a floor of 1.0 to the range so flat/single-value series still
  ///   produce a visible range.
  /// - Rounds interval to a "nice" power-of-10-based step.
  static ChartAxisBounds computeBounds(
    List<double> values, {
    double paddingFraction = 0.15,
  });

  /// Format a DateTime as "MMM d" for a date axis label (e.g. "Jan 5").
  static String formatDateLabel(DateTime date);

  /// Whether index [idx] (0-based) in a series of length [total] should carry
  /// a date label. Returns true for: first (0), last (total-1), and up to 2
  /// evenly-spaced intermediate indices when total > 3.
  /// Always returns true for total ≤ 3. Never returns more than 4 trues.
  static bool shouldShowDateLabel(int idx, int total);
}
```

**`computeBounds` algorithm:**
1. `minVal = min(values)`, `maxVal = max(values)`
2. `range = maxVal - minVal`
3. `paddedMin = max(0.0, minVal - range * paddingFraction)`
4. `paddedMax = maxVal + range * paddingFraction + 1.0` (the `+ 1.0` prevents zero range)
5. `rawInterval = (paddedMax - paddedMin) / 3.0`
6. Round `rawInterval` to nearest "nice" number (power-of-10 base: 1, 2, 5, 10, 20, 50 …)
7. Return `ChartAxisBounds(min: paddedMin, max: paddedMax, interval: niceInterval)`

**`shouldShowDateLabel` algorithm:**
- `total <= 3`: always `true`
- `total == 4`: always `true`
- `total > 4`: `true` only for indices `{0, total-1, total/3, 2*total/3}` (using integer division); the two intermediate indices may coincide with 0 or total-1 — those duplicates are harmless (the check will still return `true` and fl_chart won't double-render).

#### 1.2 — Update `_buildTrendChart()` in `stats_screen.dart`

**Height**: increase `SizedBox(height: 100)` → `SizedBox(height: 120)`.

**Remove `const`** from `FlTitlesData(...)` (it will have closures).

**Left axis** — replace `SideTitles(showTitles: false)` with:
```dart
leftTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 52,
    interval: bounds.interval,
    getTitlesWidget: (value, meta) => SideTitleWidget(
      meta: meta,
      space: 4,
      child: Text(
        '${value.toStringAsFixed(0)} $label',
        style: const TextStyle(fontSize: 9, color: /* themeColors.textMuted */),
      ),
    ),
  ),
),
```
`bounds` comes from `ChartAxisHelper.computeBounds(points.map((p) => p.value).toList())`.
Replace the inline `chartMinY/chartMaxY` computation with `bounds.min` / `bounds.max`.

**Bottom axis** — replace `SideTitles(showTitles: false)` with:
```dart
bottomTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 20,
    interval: 1,
    getTitlesWidget: (value, meta) {
      final idx = value.round();
      if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
      if (!ChartAxisHelper.shouldShowDateLabel(idx, points.length)) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
        meta: meta,
        space: 4,
        child: Text(
          ChartAxisHelper.formatDateLabel(points[idx].date),
          style: const TextStyle(fontSize: 9, color: /* themeColors.textMuted */),
        ),
      );
    },
  ),
),
```

Apply the identical axis treatment to **`_buildCardioPaceChart()`** and **`_buildCardioDurationChart()`** (each with their own unit strings: `s/$distUnit` for pace, `min` for duration).

#### 1.3 — Fix single-point states

**In `_buildLiftCard()`:** the `else if (e1RmDisplay.length == 1)` branch currently returns a bare `Text(...)`. Replace with a styled container widget:

```dart
_buildSinglePointCard(
  theme: theme,
  themeColors: themeColors,
  label: 'Estimated 1RM:',
  value: '${e1RmDisplay.first.value.toStringAsFixed(1)} $weightLabel',
  date: e1RmDisplay.first.date,
)
```

Identical treatment for the `volumeDisplay.length == 1` branch (label: `'Volume:'`).

**New private helper `_buildSinglePointCard(...)`:**
```dart
Widget _buildSinglePointCard({
  required ThemeData theme,
  required OmniThemeColors themeColors,
  required String label,
  required String value,
  required DateTime date,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: themeColors.divider.withAlpha(30),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label $value',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('1 session — log more to see a trend',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: themeColors.textMuted)),
          ],
        ),
      ],
    ),
  );
}
```

**Preserve the substring `'Estimated 1RM:'`** in the rendered text so the existing widget test assertion `find.textContaining('Estimated 1RM:')` continues to pass without modification.

**In `_buildCardioCard()` / `_buildSingleCardioDaySummary()`:** the existing helper returns a plain `Text` joined by `' · '`. Wrap the same text in a styled container identical to the lift approach (reuse `_buildSinglePointCard` or create a parallel `_buildSingleCardioCard`). The `parts.join(' · ')` string must remain intact so `find.textContaining('Pace: 579 s/mi')` still passes.

#### 1.4 — Fix exercise name truncation

**In `_buildLiftCard()` and `_buildCardioCard()` headers:** the `Text(lift.exerciseName / cardio.exerciseName)` currently has no overflow constraint and is inside a `Column` — it should already wrap. Verify no enclosing `Row` or `Expanded` is cutting it; if so, remove any explicit `overflow: TextOverflow.ellipsis` or `maxLines: 1`.

**In `_buildPRList()` PR rows:** remove `overflow: TextOverflow.ellipsis` from the `Expanded(child: Text(pr.exerciseName, ...))`. Since it is already wrapped in `Expanded`, the text will naturally wrap to multiple lines. This is the primary truncation source.

#### 1.5 — New test file `test/chart_axis_helper_test.dart`

Pure Dart unit tests (no `flutter_test` pump needed — just `test` package):

**`computeBounds` — ascending data:**
- Input: `[90, 95, 100, 110]`. Expect `min ≈ 0` (clamped), `max ≈ 113`, `interval` is a nice round number.

**`computeBounds` — descending data (Conventional Deadlift decline):**
- Input: `[200, 190, 180, 170]`. Expect `min ≈ 163`, `max ≈ 207`, `interval` is a nice round number, and `max - min ≈ 44` (full range preserved — the decline shows its magnitude).

**`computeBounds` — flat data:**
- Input: `[100, 100, 100]`. Expect `range = 0`, `min = 0`, `max ≈ 101`, non-zero `interval` (the `+ 1.0` floor prevents a degenerate zero-range).

**`computeBounds` — single value:**
- Input: `[150.0]`. No crash; `min = 0`, `max ≈ 151`, valid `interval`.

**`formatDateLabel`:**
- `DateTime(2024, 1, 5)` → `'Jan 5'`
- `DateTime(2024, 12, 31)` → `'Dec 31'`

**`shouldShowDateLabel` — branching:**
- `total = 1`: only idx 0 → `true`.
- `total = 2`: idx 0 → `true`, idx 1 → `true`.
- `total = 4`: all four → `true`.
- `total = 10`: idx 0 → `true`, idx 9 → `true`, idx 3 → `true`, idx 6 → `true`; idx 1 → `false`.

**Single-point vs. multi-point branching (widget integration):**
These are documented in the existing test for widget rendering — an existing widget test (`'strength e1RM and PRs displayed in lbs when unit is lbs'`) already exercises the single-point path. Audit it:
- Currently asserts `find.textContaining('Estimated 1RM:')` — this must continue to pass with the new styled container (since the label text `'Estimated 1RM: ...'` is preserved).
- Add assertion: `find.textContaining('1 session — log more to see a trend')` → `findsOneWidget`.

---

### PR 2: PR List Dedupe

#### 2.1 — Update PR collection in `stats_progress_service.dart`

**Current algorithm** (lines ~121–132 of service):
```dart
double bestSoFar = 0;
for (final point in e1RmTrend) {
  if (point.value > bestSoFar) {
    bestSoFar = point.value;
    allPRs.add(StatsPR(exerciseName: name, e1Rm: point.value, date: point.date));
  }
}
```

This appends one `StatsPR` per new-high event — same exercise appears repeatedly.

**New algorithm:**

Step 1: Keep the per-exercise inner loop unchanged. It still collects every new-high event into `allPRs`.

Step 2: After the loop over all top lifts, **deduplicate** before trimming:

```dart
// Deduplicate: one entry per exercise, representing its current best.
// "Current best" = the StatsPR with the highest e1RM. In case of tie,
// keep the most recent date. Deterministic because exercise names are unique
// within topLiftIds.
final dedupedPRs = <String, StatsPR>{};
for (final pr in allPRs) {
  final existing = dedupedPRs[pr.exerciseName];
  if (existing == null ||
      pr.e1Rm > existing.e1Rm ||
      (pr.e1Rm == existing.e1Rm && pr.date.isAfter(existing.date))) {
    dedupedPRs[pr.exerciseName] = pr;
  }
}

// Sort by date descending (most recently achieved record first), then
// alphabetically by name for ties (deterministic).
final sortedPRs = dedupedPRs.values.toList()
  ..sort((a, b) {
    final dateCmp = b.date.compareTo(a.date);
    if (dateCmp != 0) return dateCmp;
    return a.exerciseName.compareTo(b.exerciseName);
  });

final recentPRs = sortedPRs.take(kRecentPRCount).toList();
```

Replace the current two lines:
```dart
allPRs.sort((a, b) => b.date.compareTo(a.date));
final recentPRs = allPRs.take(kRecentPRCount).toList();
```

#### 2.2 — Update `test/stats_progress_test.dart`

**Add new group `'PR list dedupe'`:**

```dart
group('PR list dedupe', () {
  test('same exercise appearing 3× collapses to 1 entry at current best', () async {
    // Seed Hammer Curl with e1RMs [50, 55, 60] on three separate days.
    // Expect recentPRs contains exactly one entry for 'Hammer Curl' at e1RM = 60.
    ...
    expect(data.recentPRs.length, 1);
    expect(data.recentPRs.first.exerciseName, 'Hammer Curl');
    expect(data.recentPRs.first.e1Rm, closeTo(60 * (1 + 1/30.0), 0.01));
  });

  test('ordering is deterministic and stable when records share a date', () async {
    // Seed two exercises each achieving their PR on the same date.
    // Expect the two entries are ordered alphabetically by name.
    ...
    expect(data.recentPRs[0].exerciseName.compareTo(data.recentPRs[1].exerciseName),
        lessThan(0));
  });

  test('single-PR exercise appears correctly — dedupe does not drop singletons', () async {
    // Seed one exercise with exactly one training day.
    // Expect recentPRs.length == 1 and the entry has the correct e1RM.
    ...
    expect(data.recentPRs, hasLength(1));
  });
});
```

**Update existing `'PR detection'` group test:**

`'PRs on Day 1 (first ever) and Day 3 (new high), not Day 2'` currently asserts `data.recentPRs.length == 2` (Squat at Day 1 and Day 3). After deduplication, Squat is a single exercise — only one row for its current best (Day 3).

Update:
```dart
// Old: expect(data.recentPRs.length, 2);
expect(data.recentPRs.length, 1); // deduped: Squat appears once

// Old: prDates contains both Day1 and Day3
expect(data.recentPRs.first.date, DateTime(2024, 1, 3)); // standing record date
expect(data.recentPRs.first.e1Rm, closeTo(105 * (1 + 5/30.0), 0.01)); // Day 3 value
```

Remove (or update) the `expect(prDates, contains(DateTime(2024, 1, 1)))` assertion since Day 1 is no longer in the list.

---

### Files Affected

```
lib/core/utils/chart_axis_helper.dart            (new — PR 1)
lib/features/stats/stats_screen.dart             (update — PR 1: axes, single-point, name overflow)
lib/core/services/stats_progress_service.dart    (update — PR 2: PR dedupe algorithm)
test/chart_axis_helper_test.dart                 (new — PR 1)
test/stats_progress_test.dart                    (update — PR 2: new dedupe group + existing PR test fix)
test/screen_widget_test.dart                     (update — PR 1: add 'log more' assertion to single-point test)
```

### Notes

- **No DBA work needed.** Both PRs are pure service/UI changes.
- `ChartAxisHelper` has no Flutter imports — safe to test with plain `dart:test`, no widget pump.
- **`_buildTrendChart` height increase** (100 → 120): The chart is inside an `OmniSurface` `Column`. The increase adds ~20 px per chart section. Verify scrolling still works on small screens.
- **Left axis `reservedSize: 52`**: chosen to fit "120.0 kg" at font size 9. If volume numbers grow large (e.g. "5 000 kg"), the label will clip. An alternative is to omit the unit from left-axis ticks and keep it only in the section label above the chart. The plan prefers the inline unit for readability; Developer may adjust `reservedSize` if needed.
- **`const` removal on `FlTitlesData`**: All three chart builder methods use `const FlTitlesData(...)`. This must become non-const once `getTitlesWidget` closures are added.
- **Dedupe ordering** — newest date first, then alphabetical on tie — is intentional: it matches the pre-existing sort direction (`allPRs.sort((a, b) => b.date.compareTo(a.date))`) and adds determinism.
- The existing widget test `'cardio single-day pace respects miles preference'` asserts `find.textContaining('Pace: 579 s/mi')`. The new styled single-point container must preserve that substring exactly.
- The existing widget test `'strength e1RM and PRs displayed in lbs when unit is lbs'` asserts `find.textContaining('Estimated 1RM:')`. The new styled container must render `'Estimated 1RM: X.X lbs'` as a single `Text` widget to preserve that match.

## Progress (Iteration 2)

- [x] 1.1 Create `lib/core/utils/chart_axis_helper.dart`
- [x] 1.2 Update `_buildTrendChart()` in `stats_screen.dart` (left + bottom axes)
- [x] 1.3 Update `_buildCardioPaceChart()` + `_buildCardioDurationChart()` (axes)
- [x] 1.4 Fix single-point states in lift and cardio cards
- [x] 1.5 Fix exercise name truncation (headers + PR rows)
- [x] 1.6 Create `test/chart_axis_helper_test.dart`
- [x] 1.7 Update `test/screen_widget_test.dart` single-point assertion
- [x] 2.1 Dedupe PR algorithm in `stats_progress_service.dart`
- [x] 2.2 New dedupe group in `test/stats_progress_test.dart`
- [x] 2.3 Update existing PR detection test (length + date assertions)

**Iteration 2: Complete** — All 882 tests pass (186 targeted, 0 regressions).

## Feedback

- Reviewer follow-up required: chart plot area currently sits too far right within the stats cards on-device, causing the right edge/x-axis area to read as if it is overflowing the card boundary instead of sitting cleanly under the left-side value labels.
  - Observed issue: in multi-point strength charts, the plotted area extends visually to the card's right edge while the widened left y-axis gutter added in Iteration 4 leaves the chart body feeling offset; the result is insufficient right-side breathing room and an imbalanced chart frame.
  - Required fix: add a shared horizontal plot inset/margin policy for all progress charts so the drawable plot area shifts slightly left under the labels and retains visible right-side clearance inside the card.
  - Required fix: keep data, bounds, line geometry, points, fill, and tooltip semantics unchanged; this is a layout-only adjustment.
  - Required fix: add a widget-level regression test that verifies the chart render path includes explicit horizontal inset/containment behavior for multi-point charts.

## Progress (Iteration 3)

- [x] 3.1 Implement cardio pace + distance dual-series chart behavior in `stats_screen.dart`
- [x] 3.2 Add widget regression test for dual-series cardio chart path
- [x] 3.3 Add explicit doc-update status evidence for required docs

## Doc Updates (Iteration 3)

- `docs/navigation_and_screens.md`: no update required for this follow-up (already updated in Iteration 1 for StatsScreen content change)
- `docs/state_management.md`: no update required (no state API or service contract changes in this follow-up)
- `docs/widget_catalog.md`: no update required (no reusable widget public API changed)
- `docs/data_models.md`: no update required (no model schema/type changes)
- `docs/db_integration.md`: no update required (no repository/database behavior changed)
- `docs/stats_screen.md`: updated (Cardio section now documents pace + distance dual-series overlay behavior)

---

## Iteration 4

### Analysis

Refine axis-title rendering density and chart headroom across all Stats progress charts without changing any data calculations or plotted series styling. Current crowding stems from three layout issues in `stats_screen.dart`: y-axis gutter too narrow for large values with units (causing wrap), too many y-axis labels for current chart height, and insufficient top/left-title spacing causing top labels to visually collide with chart titles.

Scope is UI/layout only:

- `lib/features/stats/stats_screen.dart` (axis reserved size, top/bottom/title spacing, tick density inputs)
- `lib/core/utils/chart_axis_helper.dart` (single-line y-label formatter + readable max tick policy)
- tests under `test/chart_axis_helper_test.dart` and selective Stats widget-test audit

No model/service/repository/database changes.

### Questions (if any)

1. Default readability budget assumption for implementation: cap visible y-axis ticks to **4** for 120px chart height (first/last + up to 2 interior), with a shared minimum vertical spacing policy. If you want 3 or 5 instead, adjust before implementation.

### Implementation Plan

### Phase 1: Data Layer (@dba)

1. [ ] No data-layer changes required.

### Phase 2: Logic/UI (@developer)

1. [ ] Update `ChartAxisHelper` with a reusable y-label formatter that always returns a single-line `"<rounded-value> <unit>"` string and never inserts manual line breaks.
2. [ ] Add a readable y-axis tick-budget helper in `ChartAxisHelper` based on chart height and minimum label spacing (shared constants used by all progress charts).
3. [ ] In `stats_screen.dart`, apply one shared y-axis config builder for strength e1RM, strength volume, cardio pace, and cardio duration charts:
  - consistent `reservedSize` (wider gutter to fit large value+unit strings),
  - shared `interval` derived from bounds + tick-budget,
  - single-line label text style.
4. [ ] Add top headroom so the highest y-axis label cannot overlap/touch the chart title above:
  - increase chart title-to-plot separation and/or add top-side titles reservation,
  - keep chart height treatment consistent across all three chart types.
5. [ ] Ensure the plotted line, points, area fill, and tooltip content remain unchanged (layout-only patch).
6. [ ] Keep bottom axis behavior unchanged except for any needed uniform spacing constants (no data/format semantic changes).
7. [ ] Audit for hard-coded chart-specific gutter widths (`52`, `40`, etc.) and replace with shared constants to guarantee visual uniformity.

### Phase 3: Tests (@developer)

1. [ ] Add unit tests in `test/chart_axis_helper_test.dart`:
  - single-line y-label formatting with small value (~50) and large value (~3000), asserting one-line output string with unit.
  - readable max tick-count policy test: computed y-axis tick count does not exceed spacing budget for 120px charts.
2. [ ] Audit and update any existing PR1 axis tests that lock old cramped tick assumptions (specific tick count/placement) so they assert readability constraints instead.
3. [ ] Keep existing widget tests for line-series behavior passing to verify no regressions in plotted geometry.

### Acceptance Criteria (Iteration 4)

- [ ] No axis value label wraps to a second line on any progress chart.
- [ ] Top y-axis label never overlaps/touches chart title or preceding section content.
- [ ] Visible y-axis labels in a chart do not overlap each other.
- [ ] Strength e1RM, strength volume, cardio pace, and cardio duration charts share consistent y-axis gutter width and label-spacing rules.
- [ ] Plotted line, points, and fill rendering are unchanged from current build.
- [ ] New/updated axis-helper tests pass and enforce single-line labels plus tick-budget cap.

### Files Affected (Iteration 4)

- `lib/core/utils/chart_axis_helper.dart`
- `lib/features/stats/stats_screen.dart`
- `test/chart_axis_helper_test.dart`
- `test/screen_widget_test.dart` (audit-only if any axis crowding assumptions exist)

### Notes (Iteration 4)

- Fast-track option does **not** apply because this is user-facing UI behavior refinement.
- No interactivity additions.
- No bounds/data recalculation changes; only axis label layout, spacing, and shared rendering constants.

## Progress (Iteration 4)

- [x] 4.1 Define shared y-axis spacing constants and single-line formatter in `ChartAxisHelper`
- [x] 4.2 Refactor all stats chart builders to use consistent y-axis gutter + spacing policy
- [x] 4.3 Add chart-headroom separation to prevent top-label/title collisions
- [x] 4.4 Add unit tests for single-line labels (~50, ~3000)
- [x] 4.5 Add unit tests for y-axis tick-budget cap vs chart height
- [x] 4.6 Audit/update PR1 axis tests that pinned cramped tick assumptions

**Iteration 4: Complete** — Targeted tests pass (`chart_axis_helper_test.dart`: 24, `screen_widget_test.dart`: 167).

---

## Iteration 5

### Analysis

Iteration 4 improved axis readability, but the wider left-axis gutter now leaves the chart plot area visually pushed toward the card's right edge on-device. The chart needs a small, consistent horizontal inset so the plot sits more naturally under the left-side labels and no longer appears to overflow the card boundary on the right.

Scope remains UI/layout only:

- `lib/features/stats/stats_screen.dart`
- `test/screen_widget_test.dart`

No model, service, repository, database, or calculation changes.

### Phase 1: Data Layer (@dba)

1. [ ] No data-layer changes required.

### Phase 2: Logic/UI (@developer)

1. [ ] Introduce a shared horizontal chart inset constant for all multi-point stats charts in `stats_screen.dart`.
2. [ ] Apply the inset consistently to strength e1RM, strength volume, cardio pace, and cardio duration charts so the plot body shifts slightly left under the y-axis labels.
3. [ ] Ensure the rightmost plotted point/date label has visible clearance from the card edge after the inset is applied.
4. [ ] Keep chart height, y-axis gutter width, tick spacing, line/point/fill styling, and data ranges unchanged.
5. [ ] Prefer an internal chart/container inset over ad-hoc per-chart padding so all chart types remain visually uniform.

### Phase 3: Tests (@developer)

1. [ ] Add/update a widget test in `test/screen_widget_test.dart` for a multi-point chart path that asserts the chart is rendered within an explicit horizontal inset/containment wrapper.
2. [ ] Keep existing stats widget tests passing to confirm no regression in line-series count or single-point fallback behavior.

### Acceptance Criteria (Iteration 5)

- [ ] The plot area for all multi-point stats charts sits slightly more left under the y-axis labels.
- [ ] The chart no longer appears to overflow or press against the right edge of the card on-device.
- [ ] Strength and cardio charts use the same horizontal inset treatment.
- [ ] No changes are made to plotted values, bounds, line path, points, fill, or tooltip semantics.
- [ ] Updated widget tests pass.

### Files Affected (Iteration 5)

- `lib/features/stats/stats_screen.dart`
- `test/screen_widget_test.dart`

### Notes (Iteration 5)

- This is a visual containment refinement, not a data or axis-scale change.
- The likely implementation surface is a shared chart wrapper/padding layer around each `LineChart`, not per-series geometry edits.

## Progress (Iteration 5)

- [x] 5.1 Add shared horizontal inset policy for stats charts
- [x] 5.2 Apply inset uniformly to strength and cardio multi-point charts
- [x] 5.3 Add widget regression coverage for chart containment/inset

**Iteration 5: Complete** — Targeted stats widget tests pass after shared chart inset containment fix.

