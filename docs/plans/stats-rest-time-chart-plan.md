# Feature: 30-Day Rest Time by Modality Chart

## Overview
Add a new multi-line chart card to the existing `StatsScreen` showing average rest time per day
for the last 30 days, broken down by modality. No existing screen content is modified.

## Requirements
- Query closed `EntryRest` records (restEndMs != null) for the last 30 days by `restStartMs`
- Group by modality (derived via effort → segment → session) and by calendar day
- Each data point = average rest duration in seconds for that modality on that day
- Only render a line for modalities with at least one qualifying rest record
- If no qualifying rest records exist at all, hide the entire chart card silently
- Line colors from `ModalityColors` — no hardcoding
- Legend below the chart for each visible line
- Match existing card visual style exactly

## Acceptance Criteria
- [ ] New chart card appears below the "30-Day Activity" bar chart
- [ ] Card only renders when at least one qualifying (closed) rest record exists in the window
- [ ] Only modalities with real rest data produce a visible line (no flat zero lines)
- [ ] `martialArts` modality is merged into `sports` for display (same color, same legend entry)
- [ ] Y axis shows average rest seconds; X axis mirrors the existing 30-day window
- [ ] Line colors match exactly: ModalityColors.cardioEndurance / .resistanceLifting / .sports / .isometricStretching / .freeTraining
- [ ] Legend shows each visible modality with its color dot and display name
- [ ] Card uses OmniSurface, same padding and typography as Activity card
- [ ] Days with no rest data for a line produce a gap (no FlSpot), not a zero
- [ ] No hardcoded colors, no new pubspec dependencies
- [ ] Both HiveWorkoutRepository and MockWorkoutRepository implement the new method

## Scenarios
N/A (no new DI components required — the WorkoutState `repository` getter is already public)

---

## Iteration 1

### Analysis
`EntryRest` records do not carry modality directly. Modality must be resolved via:
```
EntryRest.effortId
  → _effortsBox.get(effortId)   [O(1) in both Hive and Mock]
  → SegmentEffort.segmentId
  → _segmentsBox.get(segmentId) [O(1)]
  → SessionSegment.sessionId
  → _sessionsBox.get(sessionId) [O(1)]
  → TrainingSession.modality    [String? — null = Free Training]
```
All three boxes are keyed by their respective model `.id`, so per-record traversal is O(1).
The existing 30-day session filter is on `startedAtMs`; for rests we filter on `restStartMs`.

`Modality.martialArts` maps to `ModalityColors.sports` in `ModalityColors.byModality`.
To avoid duplicate lines with identical colors, the new method normalises `martial_arts` → `sports`
before grouping.

---

### Phase 0: DBA Task — New Repository Method

#### 0.1 — `workout_repository.dart` (abstract interface)
Add one abstract method below the existing `deleteEntryRestsForEffort` declaration:

```dart
/// Returns all closed EntryRest records (restEndMs != null) whose
/// restStartMs falls within [fromMs, toMs], grouped by normalised modality key.
/// — 'martial_arts' is folded into 'sports'.
/// — null key = Free Training (session had no modality set).
Future<Map<String?, List<EntryRest>>> getEntryRestsByModalityInDateRange(
  int fromMs,
  int toMs,
);
```

#### 0.2 — `hive_workout_repository.dart`
Implement the new method in the `// ===== ENTRY RESTS =====` section after
`deleteEntryRestsForEffort`:

```dart
@override
Future<Map<String?, List<EntryRest>>> getEntryRestsByModalityInDateRange(
  int fromMs,
  int toMs,
) async {
  final result = <String?, List<EntryRest>>{};
  for (final raw in _entryRestsBox.values) {
    final rest = EntryRest.fromMap(_asStringMap(raw));
    if (rest.restEndMs == null) continue;               // open rest — skip
    if (rest.restStartMs < fromMs || rest.restStartMs > toMs) continue;

    // Resolve modality via effort → segment → session.
    final effortRaw = _effortsBox.get(rest.effortId);
    if (effortRaw == null) continue;
    final effort = SegmentEffort.fromMap(_asStringMap(effortRaw));

    final segmentRaw = _segmentsBox.get(effort.segmentId);
    if (segmentRaw == null) continue;
    final segment = SessionSegment.fromMap(_asStringMap(segmentRaw));

    final sessionRaw = _sessionsBox.get(segment.sessionId);
    if (sessionRaw == null) continue;
    final session = TrainingSession.fromMap(_asStringMap(sessionRaw));

    // Normalise martial_arts → sports so they share one line.
    final rawModality = session.modality;
    final modality = rawModality == 'martial_arts' ? 'sports' : rawModality;

    result.putIfAbsent(modality, () => []).add(rest);
  }
  return result;
}
```

#### 0.3 — `mock_workout_repository.dart`
Implement the new method after `deleteEntryRestsForEffort`:

```dart
@override
Future<Map<String?, List<EntryRest>>> getEntryRestsByModalityInDateRange(
  int fromMs,
  int toMs,
) async {
  final result = <String?, List<EntryRest>>{};
  for (final restList in _entryRests.values) {
    for (final rest in restList) {
      if (rest.restEndMs == null) continue;
      if (rest.restStartMs < fromMs || rest.restStartMs > toMs) continue;

      final effort = _efforts[rest.effortId];
      if (effort == null) continue;
      final segment = _segments[effort.segmentId];
      if (segment == null) continue;
      final session = _sessions[segment.sessionId];
      if (session == null) continue;

      final rawModality = session.modality;
      final modality = rawModality == 'martial_arts' ? 'sports' : rawModality;

      result.putIfAbsent(modality, () => []).add(rest);
    }
  }
  return result;
}
```

---

### Phase 1: Developer Task — Stats Screen Chart

#### 1.1 — New state fields in `_StatsScreenState`
```dart
// modality key → 30-element list of average rest seconds (null = no data for that day)
Map<String?, List<double?>> _restAvgsByModality = {};
```

#### 1.2 — Extend `_loadData()`
After building `counts`, add:
```dart
// Fetch closed rests in the 30-day window, grouped by modality.
final restsByModality = await widget.workoutState.repository
    .getEntryRestsByModalityInDateRange(fromMs, toMs);

final restAvgs = <String?, List<double?>>{};
for (final entry in restsByModality.entries) {
  final modality = entry.key;
  final rests = entry.value;

  // Build per-day sum + count accumulators.
  final sumSecs = List<double>.filled(30, 0);
  final countPerDay = List<int>.filled(30, 0);

  for (final rest in rests) {
    final restDay = DateTime.fromMillisecondsSinceEpoch(rest.restStartMs);
    final day = DateTime(restDay.year, restDay.month, restDay.day);
    final dayIndex = day.difference(thirtyDaysAgo).inDays;
    if (dayIndex < 0 || dayIndex >= 30) continue;
    final durationSecs = (rest.restEndMs! - rest.restStartMs) / 1000.0;
    sumSecs[dayIndex] += durationSecs;
    countPerDay[dayIndex]++;
  }

  // Convert to averages; null where no data.
  final avgs = <double?>[];
  for (var i = 0; i < 30; i++) {
    avgs.add(countPerDay[i] > 0 ? sumSecs[i] / countPerDay[i] : null);
  }
  restAvgs[modality] = avgs;
}
```
Then inside `setState(...)`:
```dart
_restAvgsByModality = restAvgs;
```

#### 1.3 — Extend `build()` list children
After the existing `_buildActivityCard` entry, add:
```dart
if (_restAvgsByModality.isNotEmpty) ...[
  const SizedBox(height: 24),
  _buildSectionLabel('REST TIME', themeColors),
  const SizedBox(height: 8),
  _buildRestTimeCard(context, themeColors),
],
```

#### 1.4 — New `_buildRestTimeCard` method
Ordered display: render modalities in a consistent order
`[cardio_endurance, resistance_lifting, sports, isometric_stretching, null]`
so the legend is always stable.

```dart
Widget _buildRestTimeCard(BuildContext context, OmniThemeColors themeColors) {
  final theme = Theme.of(context);
  final thirtyDaysAgo = _thirtyDaysAgo!;
  final today = _today!;

  // Stable display order for modalities.
  const _displayOrder = <String?>[
    'cardio_endurance',
    'resistance_lifting',
    'sports',
    'isometric_stretching',
    null, // Free Training
  ];

  final visibleModalities = _displayOrder
      .where((m) => _restAvgsByModality.containsKey(m))
      .toList();

  // Build LineChartBarData for each visible modality.
  final lineBars = <LineChartBarData>[];
  double maxY = 10.0;
  for (final modality in visibleModalities) {
    final avgs = _restAvgsByModality[modality]!;
    final spots = <FlSpot>[];
    for (var i = 0; i < 30; i++) {
      if (avgs[i] != null) {
        spots.add(FlSpot(i.toDouble(), avgs[i]!));
        if (avgs[i]! > maxY) maxY = avgs[i]!;
      }
    }
    if (spots.isEmpty) continue;
    final color = ModalityColors.forModality(modality);
    lineBars.add(LineChartBarData(
      spots: spots,
      color: color,
      isCurved: true,
      curveSmoothness: 0.3,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    ));
  }

  if (lineBars.isEmpty) return const SizedBox.shrink();

  // Y axis interval: aim for ~4 ticks.
  final yInterval = max(10.0, (maxY / 4).ceilToDouble() / 10 * 10);

  return OmniSurface(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '30-Day Rest Time',
              style: theme.textTheme.titleSmall?.copyWith(
                color: OmniTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                '${OmniDateUtils.shortMonthName(thirtyDaysAgo.month)} ${thirtyDaysAgo.day}'
                ' – '
                '${OmniDateUtils.shortMonthName(today.month)} ${today.day}',
                style: TextStyle(fontSize: 11, color: themeColors.textMuted),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 29,
              minY: 0,
              maxY: maxY + yInterval * 0.3,
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value != value.floorToDouble()) return const SizedBox.shrink();
                      final intVal = value.toInt();
                      if (intVal < 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          intVal.toString(),
                          style: TextStyle(fontSize: 10, color: themeColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      const labelIndices = {0, 7, 14, 21, 28};
                      if (!labelIndices.contains(idx)) return const SizedBox.shrink();
                      final date = thirtyDaysAgo.add(Duration(days: idx));
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${OmniDateUtils.shortMonthName(date.month)} ${date.day}',
                          style: TextStyle(fontSize: 9, color: themeColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: themeColors.divider,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: lineBars,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: visibleModalities.map((modality) {
            final color = ModalityColors.forModality(modality);
            final label = modality == null
                ? 'Free Training'
                : Modality.getDisplayName(modality);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: themeColors.textMuted,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    ),
  );
}
```

#### 1.5 — New imports required in `stats_screen.dart`
```dart
import '../../core/constants/modality.dart';
import '../../core/constants/modality_colors.dart';
```
(`fl_chart` is already imported; `OmniDateUtils` is already imported.)

---

### Files Affected
| File | Change |
|---|---|
| `lib/data/repositories/workout_repository.dart` | Add abstract method `getEntryRestsByModalityInDateRange` |
| `lib/data/repositories/hive_workout_repository.dart` | Implement method |
| `lib/data/repositories/mock_workout_repository.dart` | Implement method |
| `lib/features/stats/stats_screen.dart` | New state field, extended `_loadData`, section + `_buildRestTimeCard` |

WorkoutState does **not** need a passthrough — the stats screen accesses
`widget.workoutState.repository` directly (the `repository` getter is already public).

---

## Progress
- [x] 0.1 Add abstract method to WorkoutRepository interface
- [x] 0.2 Implement in HiveWorkoutRepository
- [x] 0.3 Implement in MockWorkoutRepository
- [x] 1.1 Add new state field to `_StatsScreenState`
- [x] 1.2 Extend `_loadData()` to compute rest averages
- [x] 1.3 Extend `build()` list to conditionally include the new card
- [x] 1.4 Implement `_buildRestTimeCard`
- [x] 1.5 Add missing imports to stats_screen.dart

## Feedback

