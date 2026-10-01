# Feature: Measurement History Chart Sheet

## Overview
Replace the current `_MeasurementHistorySheet` (simple scrollable list) with a
`fl_chart`-powered line chart sheet. Triggered by tapping any measurement row on
`ProfileScreen`. Shows the last ≤10 entries for that measurement type as a line
chart with tappable dots, a selected-entry label strip, and a "Log New Entry"
button that opens the log sheet on top without dismissing the chart.

---

## Analysis
- `fl_chart: ^0.60.0` is already in `pubspec.yaml` — no dependency change needed.
- `getMeasurementHistory(type)` already exists on `ProfileState` / repository and
  returns entries sorted descending. Reverse + cap at 10 to get oldest→newest order.
- `OmniDateUtils.formatShort(date)` → `"Mar 08"` format is exactly what the spec
  calls for — use it for X-axis labels.
- `ProfileMeasurements.formatValue()` and `unitLabelFor()` handle formatting for
  the label strip.
- `OmniTheme.animationDuration` (180ms) and `OmniTheme.animationCurve` (easeInOut)
  are already defined.
- `OmniTheme.buttonBorderRadius` = 12.0, `OmniTheme.buttonPrimaryHeight` = 56.0.
- The current "Log New Entry" handler pops the history sheet before opening the log
  sheet. The spec requires the log sheet to open ON TOP of the chart sheet and the
  chart to refresh afterward — this is a behaviour change (described in detail below).
- No database or model changes are needed — this is a pure UI feature.

---

## Implementation Plan

### Phase 1: No Data Layer Work Needed (@developer only)

The existing `getMeasurementHistory` method and `BodyMeasurementEntry` model
provide everything required. Skip @dba.

---

### Phase 2: UI Implementation (@developer)

#### Step 1 — Create the chart sheet widget file

Create **`lib/features/profile/widgets/measurement_history_chart_sheet.dart`**.

This file replaces the private `_MeasurementHistorySheet` / `_MeasurementHistorySheetState`
classes that currently live at the bottom of `profile_screen.dart`.

Make the widget **public** (class `MeasurementHistoryChartSheet`) so it can be
imported from `profile_screen.dart`.

```
Required imports:
  package:flutter/material.dart
  package:fl_chart/fl_chart.dart
  ../../../core/constants/omni_theme.dart
  ../../../core/constants/profile_measurements.dart
  ../../../core/utils/date_utils.dart
  ../../../data/models/models.dart
  ../../../state/profile/profile_state.dart
```

#### Step 2 — Widget constructor

```dart
class MeasurementHistoryChartSheet extends StatefulWidget {
  final ProfileState profileState;
  final ProfileMeasurementDefinition definition;
  /// Called when user taps "Log New Entry".
  /// Must NOT pop this sheet — opens log sheet on top instead.
  /// Returns a Future that completes when the log sheet is dismissed.
  final Future<void> Function() onLogNew;

  const MeasurementHistoryChartSheet({...});
}
```

#### Step 3 — State fields

```dart
List<BodyMeasurementEntry> _entries = [];    // oldest→newest, max 10
bool _isLoading = true;
int _selectedIndex = 0;                       // updated after load
```

#### Step 4 — `_loadEntries()`

```dart
Future<void> _loadEntries() async {
  final raw = await widget.profileState.getMeasurementHistory(widget.definition.type);
  if (!mounted) return;
  final capped = raw.take(10).toList().reversed.toList(); // oldest first
  setState(() {
    _entries = capped;
    _selectedIndex = capped.isEmpty ? 0 : capped.length - 1; // most recent
    _isLoading = false;
  });
}
```

Call `_loadEntries()` from `initState`.

#### Step 5 — `build()` scaffold

```dart
return Container(
  decoration: BoxDecoration(
    color: OmniTheme.surfaceColor,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
  ),
  child: SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(),
        _buildTitle(theme),
        const SizedBox(height: 16),
        if (_isLoading)
          const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
        else if (_entries.isEmpty)
          _buildEmptyState(theme)
        else
          _buildChart(theme),
        const SizedBox(height: 16),
        if (!_isLoading) _buildLabelStrip(theme),
        const SizedBox(height: 12),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: _buildLogButton(theme),
        ),
      ],
    ),
  ),
);
```

#### Step 6 — Drag handle

```dart
Widget _buildDragHandle() => Center(
  child: Container(
    margin: const EdgeInsets.only(top: 12, bottom: 8),
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: OmniTheme.textSecondary.withOpacity(0.3),
      borderRadius: BorderRadius.circular(2),
    ),
  ),
);
```

#### Step 7 — Title

```dart
Widget _buildTitle(ThemeData theme) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(
      widget.definition.label.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: OmniTheme.textPrimary,
        letterSpacing: 2.0,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
);
```

#### Step 8 — Empty state (0 entries)

```dart
Widget _buildEmptyState(ThemeData theme) => SizedBox(
  height: 220,
  child: Center(
    child: Text(
      'No entries yet',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: OmniTheme.textSecondary.withOpacity(0.6),
      ),
    ),
  ),
);
```

Empty state: label strip area should show nothing (or hide entirely).
Button still shown.

#### Step 9 — Chart widget (2+ entries)

Fixed-height `SizedBox(height: 220)` containing `Padding` + `LineChart`.

```dart
Widget _buildChart(ThemeData theme) {
  final primary = theme.colorScheme.primary;  // neon cyan

  final spots = _entries
      .asMap()
      .entries
      .map((e) => FlSpot(e.key.toDouble(), e.value.value))
      .toList();

  final values = _entries.map((e) => e.value).toList();
  final minVal = values.reduce(min);
  final maxVal = values.reduce(max);
  final range = (maxVal - minVal).abs();
  final padding = range < 1 ? 1.0 : range * 0.15;   // headroom above/below
  final yMin = minVal - padding;
  final yMax = maxVal + padding;
  final yRange = yMax - yMin;

  return SizedBox(
    height: 220,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (_entries.length - 1).toDouble(),
          minY: yMin,
          maxY: yMax,

          // --- Grid ---
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: true,
            horizontalInterval: yRange / 4,  // 4 lines = every 25% of range
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withOpacity(0.08),
              strokeWidth: 1,
            ),
          ),

          // --- Border ---
          borderData: FlBorderData(show: false),

          // --- Titles ---
          titlesData: TitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _entries.length) return const SizedBox.shrink();
                  // If more than 6 entries, show every other label
                  if (_entries.length > 6 && idx % 2 != 0) return const SizedBox.shrink();
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    _entries[idx].recordedAtMs,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      OmniDateUtils.formatShort(date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: OmniTheme.textSecondary.withOpacity(0.6),
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // --- Touch ---
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchSpotThreshold: 24,   // 24 logical px radius → ~48dp diameter hit area
            touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
              if (event is FlTapUpEvent) {
                final spot = response?.lineBarSpots?.firstOrNull;
                if (spot != null) {
                  setState(() => _selectedIndex = spot.x.toInt());
                }
              }
            },
            getTouchedSpotIndicator: (_, __) => [],  // no built-in highlight line
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (_) => [],  // no tooltips — label strip is used instead
            ),
          ),

          // --- Line + Dots ---
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: primary.withOpacity(0.70),
              barWidth: 2,
              preventCurveOverShooting: true,

              // Show for 1 entry: barWidth doesn't render a line, but a dot appears
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, index) {
                  final isSelected = index == _selectedIndex;
                  return FlDotCirclePainter(
                    radius: isSelected ? 6.5 : 5.0,   // diameter: selected=13dp, unselected=10dp
                    color: isSelected ? Colors.white : primary,
                    strokeColor: isSelected ? primary : Colors.white,
                    strokeWidth: isSelected ? 2.0 : 1.5,
                  );
                },
              ),

              // Area fill
              belowBarData: BarAreaData(
                show: _entries.length >= 2,  // no area fill for single dot
                color: primary.withOpacity(0.10),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

**Important for 1-entry state**: `LineChart` with a single `FlSpot` renders a dot
but no line. `belowBarData.show = false` prevents a fill artifact. This satisfies
the spec's "single dot centered, no line, no area fill" requirement for 1 entry.
With only 1 entry, center the dot by setting `minX = -0.5`, `maxX = 0.5`.

#### Step 10 — Selected entry label strip

```dart
Widget _buildLabelStrip(ThemeData theme) {
  if (_entries.isEmpty) return const SizedBox.shrink();

  final entry = _entries[_selectedIndex.clamp(0, _entries.length - 1)];
  final date = DateTime.fromMillisecondsSinceEpoch(entry.recordedAtMs);
  final dateLabel = OmniDateUtils.formatShort(date);
  final valueLabel =
      '${ProfileMeasurements.formatValue(entry.value)} '
      '${ProfileMeasurements.unitLabelFor(entry.unitId)}';

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: AnimatedSwitcher(
      duration: OmniTheme.animationDuration,
      switchInCurve: OmniTheme.animationCurve,
      switchOutCurve: OmniTheme.animationCurve,
      child: Row(
        key: ValueKey(_selectedIndex),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dateLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: OmniTheme.textSecondary.withOpacity(0.7),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '·',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: OmniTheme.textSecondary.withOpacity(0.4),
              ),
            ),
          ),
          Text(
            valueLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              color: OmniTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}
```

#### Step 11 — Log New Entry button

```dart
Widget _buildLogButton(ThemeData theme) => SizedBox(
  width: double.infinity,
  height: OmniTheme.buttonPrimaryHeight,
  child: FilledButton(
    style: ButtonStyle(
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
        ),
      ),
    ),
    onPressed: _handleLogNew,
    child: const Text('Log New Entry'),
  ),
);
```

#### Step 12 — `_handleLogNew()` — opens log sheet ON TOP, then refreshes

**This is the key behaviour change from the existing implementation.**

```dart
Future<void> _handleLogNew() async {
  // Do NOT pop this sheet — widget.onLogNew() returns when log sheet closes
  await widget.onLogNew();
  if (mounted) {
    setState(() { _isLoading = true; });
    await _loadEntries();
  }
}
```

#### Step 13 — Update `profile_screen.dart`

1. **Add import:**
   ```dart
   import 'widgets/measurement_history_chart_sheet.dart';
   ```

2. **Update `_showMeasurementHistory`:**
   Change the `onLogNew` callback so it opens the log sheet WITHOUT first popping
   the history sheet:

   ```dart
   Future<void> _showMeasurementHistory(
     ProfileMeasurementDefinition definition,
   ) async {
     await showModalBottomSheet<void>(
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
       builder: (_) {
         return MeasurementHistoryChartSheet(
           profileState: widget.profileState,
           definition: definition,
           onLogNew: () => _showMeasurementLogSheet(definition),
           //          ^^^^ returns Future<void> — sheet stays open until log sheet closes
         );
       },
     );
   }
   ```

   `_showMeasurementLogSheet` already returns `Future<void>` (it's async), so
   this works as-is for the `Future<void> Function()` callback type.

3. **Delete the old private classes** — remove both:
   - `class _MeasurementHistorySheet extends StatefulWidget { … }`
   - `class _MeasurementHistorySheetState extends State<_MeasurementHistorySheet> { … }`

---

## Acceptance Criteria

- [ ] Tapping a measurement row on ProfileScreen opens the chart sheet (not the old list)
- [ ] Sheet has correct structure: drag handle → title (uppercase, letterSpacing 2.0) → chart (220dp) → label strip → divider → button
- [ ] 0 entries: "No entries yet" centered, no chart, button still shown
- [ ] 1 entry: single dot rendered, no line, no area fill; label strip shows that entry
- [ ] 2+ entries: line + area fill visible; dots for all points; X-axis labels visible
- [ ] X-axis shows every other date label when entries > 6
- [ ] Y-axis has no labels; subtle horizontal grid lines (4 bands)
- [ ] Line color is `theme.colorScheme.primary` at 70% opacity, width 2dp
- [ ] Area fill is `theme.colorScheme.primary` at 10% opacity
- [ ] Unselected dots: 10dp diameter, neon cyan fill, white border 1.5dp
- [ ] Selected dots: 13dp diameter, white fill, neon cyan border 2dp
- [ ] On open: most recent entry (rightmost dot) is pre-selected
- [ ] Tapping a dot updates the selected entry label strip
- [ ] Label strip crossfades (180ms easeInOut) when selection changes
- [ ] Label strip format: "[Mon DD]  ·  [value unit]" e.g. "Mar 14  ·  75 kg"
- [ ] "Log New Entry" button opens log sheet ON TOP of chart sheet (history sheet stays open)
- [ ] After logging a new entry, chart sheet refreshes its data automatically
- [ ] Sheet corners: 20dp top radius, `OmniTheme.surfaceColor` background
- [ ] Button: `OmniTheme.buttonBorderRadius` (12.0) shape, `OmniTheme.buttonPrimaryHeight` height
- [ ] No hardcoded colors anywhere in the new widget
- [ ] All touch targets ≥ 48dp (chart touch spot threshold = 24 logical px radius)
- [ ] No notes field anywhere in the sheet

---

## Files Affected

- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` ← **new file**
- `lib/features/profile/profile_screen.dart` ← update `_showMeasurementHistory`, remove old sheet classes, add import

---

## Notes & Implementation Hints

### fl_chart v0.60 dot-paint nuance
`getDotPainter` receives the **index in the `spots` list**, not the value. Use
`index == _selectedIndex` (not `spot.x == _selectedIndex`) to avoid floating-point
comparison issues.

### Single-entry centering
When `_entries.length == 1`, set `minX = -0.5` and `maxX = 0.5` so the single dot
renders centered in the chart area rather than pinned to the left edge.

### Y-axis grid interval when range is 0
When all entries have the same value (`range == 0`), `horizontalInterval` derived
from `yRange / 4` could be zero or near-zero, which crashes fl_chart. Guard:
```dart
final interval = yRange < 4 ? 1.0 : yRange / 4;
```

### `minOf` / `maxOf` imports
Use `dart:math`'s top-level `min()` / `max()` functions, or call `.reduce()` as
shown in the plan. Make sure to import `dart:math`.

### `AnimatedSwitcher` crossfade
The default `transitionBuilder` of `AnimatedSwitcher` is already a crossfade, so
no custom `transitionBuilder` is needed. Just set `duration` and both curve
parameters.

### Delete functionality
The existing list sheet supported swipe-to-delete. The new chart sheet spec does
not include delete. Deletion is intentionally omitted from this feature.

---

## Progress

- [x] Create `measurement_history_chart_sheet.dart`
- [x] Implement `_buildDragHandle()`
- [x] Implement `_buildTitle()`
- [x] Implement `_buildEmptyState()`
- [x] Implement `_buildChart()` with fl_chart LineChart
- [x] Implement `_buildLabelStrip()` with AnimatedSwitcher
- [x] Implement `_buildLogButton()`
- [x] Implement `_handleLogNew()` with refresh-after-save behavior
- [x] Update `profile_screen.dart`: import, update `_showMeasurementHistory`, delete old classes
- [ ] Verify 0 / 1 / 2+ entry states manually
- [ ] Verify label strip crossfade animation (touch different dots)
- [ ] Verify "Log New Entry" opens on top and chart refreshes afterward

## Feedback

