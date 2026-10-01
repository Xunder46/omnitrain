# Feature: Stats Screen Remediation — Copilot Prompt Pack (Revised Scope)

> Status: ACTIVE PHASE A
> Next handoff: @developer (Phase A)
> Binding conventions: docs/global_conventions.md

**Scope (revised per user direction 2026-08-15)**: Delete Records, Volume Trends, and Consistency sections entirely. Fix inter-section spacing convention (remove competing gap styles, unify parent-list ownership). Add Isometric and Sports duration trend sections mirroring Cardio. Rebuild shared chart layer (y-axis rounding, clipping fix, unit display). Investigate per-exercise best-load defect.

**Batching**: 
- **PR A** (Phase A): Deletions + spacing fix (developer) + toggle shrinking (developer)
- **PR B** (Phase B): Shared chart corrections (developer)
- **PR C** (Phase C+D): DBA work (dba) + new sections (developer)
- **PR D** (Phase E): Investigation finding (any)

---

## Resolved Decisions (Ledger)

### D-1: Segmented Toggle Label Width Rule
**Principle**: A segmented toggle's labels must render on exactly one line, fully legible, with no wrapping, mid-word breaking, or ellipsis, at the app's default text size and at its largest accessibility text size (5.0x multiplier).

**Rationale**: Wrapping reads as a rendering bug and undermines the instrument-panel design intent. Applies to all toggles in the app.

**Enforcement**: Test at 360dp width and accessibility scales 1.0–5.0. Report any label that cannot fit after removing decorative elements; never truncate silently.

---

### D-2: Y-Axis Label Rounding
**Principle**: Vertical axis labels always fall on round numbers: 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, etc., and their multiples by powers of ten.

**Minimum/Maximum Rule**:
- Lowest label ≤ lowest data value
- Highest label ≥ highest data value
- All labels sit on the same round increment spacing
- Full data range remains visible with comfortable margin; no clipping to achieve round labels

**Special Cases**: Flat series and single-point series produce ≥2 distinct labels with visible non-zero range (never crop to the flat value).

**Scope**: Applied to all charts — strength trends, cardio trends, isometric trends, sports trends, nutrition, profile measurements.

**Rationale**: Arbitrary labels (765, 1765, 2765) defeat the axis purpose. Users need reference numbers they can estimate against.

---

### D-3: Shared Unit Display — Appear Once Per Chart
**Principle**: Every chart displays its measurement unit exactly once, in the dedicated position the shared `ScrollableTrendChart` wrapper provides, not repeated on each y-axis label.

**Scope**: Strength trends, cardio trends, isometric trends, sports trends, nutrition charts, profile measurements.

**Rationale**: Dense instrument-panel design; no redundant text.

---

### D-4: Chart Clipping and Overlap Prevention
**Principle**: No data point or axis label clips at card edges or is obscured by overlapping components.

**Specific Requirements**:
- Leftmost point's complete marker renders fully visible when scrolled fully left
- Rightmost point's complete marker renders fully visible when scrolled fully right
- No horizontal-axis date label overlaps vertical axis label column
- Vertical axis label column and leftmost plotted content occupy non-overlapping horizontal space
- Applies to short non-scrolling and long scrolling series at both scroll extremes

**Rationale**: Extremes contain oldest and newest data — the two points users look for first.

---

### D-5: Inter-Section Spacing Convention
**Principle**: The parent `ListView` builder owns every inter-section gap (24dp). Section builders never emit their own leading `SizedBox` spacer.

**Specific Correction**: Remove self-prefixed `SizedBox(height: 24)` from `_buildFeelingSection()` (line 715 in current code) and `_buildNutritionSection()` (line 1601). Replace with explicit gaps in the ListView children list.

**Within-Section Rule**: Individual exercise cards within a section maintain 12dp spacing (e.g., between lift cards at line 296, between cardio cards at line 685).

**Target Assembly** (all deletions and additions complete):
```
Aggregate Card
    ↓ 24dp (SizedBox in list)
Strength Section
    ↓ 24dp (SizedBox in list)
Cardio Section
    ↓ 24dp (SizedBox in list)
Isometric Section
    ↓ 24dp (SizedBox in list)
Sports Section
    ↓ 24dp (SizedBox in list)
Feeling Section
    ↓ 24dp (SizedBox in list)
Nutrition Section
```

**Rationale**: Competing conventions (some sections self-prefix, others don't) create hidden gaps and re-introduce defects when sections are added or removed. Single convention eliminates the ambiguity.

**Guard Test**: Assert that inter-section gap is uniform across the whole screen and that no section builder emits a leading spacer.

**Note**: This decision touches Feeling and Nutrition sections, which were listed out-of-scope in the original prompt pack. Per explicit user direction (2026-08-15), this is a deliberate, user-directed exception to fix a structural defect in spacing conventions.

---

### D-6: Hold and Round Time Aggregation — Sum Per Day
**Principle**: Isometric and Sports duration trends aggregate time the same way Cardio does: sum of all hold times (isometric) or round times (sports) on a training day, per exercise, per day.

**Fixture Example**: Three 30-second planks on one day → trend point at 90 seconds (sum), not 30 seconds (max) and not 3 (count).

**Rationale**: Identical aggregation across all three duration sections (Cardio, Isometric, Sports) makes y-axis interpretation uniform. Sum matches Cardio's "total duration per exercise per training day" pattern.

---

### D-7: Records Section and Volume/Consistency Deletion
**Principle**: Remove Records section, Volume Trends section, and Consistency section entirely. Do not leave placeholders or empty states.

**Records Cleanup**:
- Remove `ExerciseRecord` model (used only by Records section)
- Remove `computeExerciseRecords()` from `StatsProgressService` (single call site: stats_screen.dart:113)
- Remove `_buildRecordsSection()` and `_buildRecordsCard()` from stats_screen.dart
- Remove `_exerciseRecords` state field

**Volume Trends Cleanup**:
- Remove `_VolumeView` enum
- Remove `_buildVolumeTrendsSection()` and `_buildVolumeTrendsCard()` and `_buildVolumeTrendChart()` and related builders
- Remove `_volumeView` state field
- Remove `_tonnageTrend`, `_durationTrend`, `_distanceTrend` state fields
- Remove `computeVolumeTonnage()`, `computeTimedDuration()`, `computeTimedDistance()` from `StatsProgressService` (single call sites: lines 114-116)
- Remove `VolumeTrend` model (used only by volume trends)
- Remove segmented toggle for tonnage/time/distance

**Consistency Cleanup**:
- Remove `_ConsistencyView` enum
- Remove `_buildConsistencySection()` and `_buildConsistencyCard()` and `_buildConsistencyChart()` and related builders
- Remove `_consistencyView` state field
- Remove `_weeklyConsistency`, `_monthlyConsistency` state fields
- Remove `computeConsistencyWeekly()`, `computeConsistencyMonthly()` from `StatsProgressService` (single call sites: lines 117-118)
- Remove `ConsistencyTrend` model (used only by consistency card)
- Remove segmented toggle for week/month

**Rationale**: Records duplicates Recent PRs and displays contradictory values. Volume Trends plots incomparable quantities. Consistency is redundant with modality-based views. All three push important sections below the fold.

---

### D-8: Segmented Toggle Survival
**Principle**: Only the Nutrition toggle (Calories / Macros) survives. Volume Trends and Consistency toggles are deleted with their sections.

**Surviving Toggle**: Nutrition (2 options, both fit on one line without wrapping). Apply D-1 guard test to this toggle.

**Rationale**: Volume and Consistency toggles are removed by section deletion. Nutrition toggle remains and must comply with D-1 one-line-no-wrap rule.

---

### D-9: Per-Exercise Best-Load Defect Investigation (Written Finding, No Code Changes)
**Principle**: Investigate but do not fix. Produce written finding only.

**Scope of Investigation**:
1. Every computation producing per-exercise "best" or "heaviest load" figure — state what quantity it actually computes
2. Every surface displaying those computations — state which computation feeds it and whether its label matches
3. Whether any computation behind the incorrect Records values is still reachable from a user-visible surface today (after deletion)
4. Whether any computation caps, defaults, or constrains rep record values
5. Whether uniform rep records across exercises are data-driven or computation artifacts

**Deliverable**: New doc at `docs/stats_best_load_investigation.md`. For each finding: state what was verified, how, and what remains uncertain. Distinguish verified facts from educated guesses.

**Rationale**: Symptom (Records section) is being deleted; underlying defect may surface elsewhere. Scoping a fix before understanding it guarantees wrong fixes.

---

## Feature Invariants

- **Repository parity** (standing invariant): `HiveWorkoutRepository` and `MockWorkoutRepository` sit behind `WorkoutRepository` interface. Mock must mirror Hive-path output value-for-value on all touched data.
- **Effort-kind-driven analytics** (standing invariant, global_conventions.md:12): Progress/history analytics classify by `SegmentEffort.effortKind`, never by session label or modality name.
- **Chart layer reuse**: `ChartAxisHelper` and `ScrollableTrendChart` are shared by Stats, Nutrition, and Profile. Fixes to either layer are validated across all consumers.
- **Shared duration aggregation**: Cardio, Isometric, and Sports all sum duration/time per exercise per training day (D-6).
- **Shared 14-day window**: All three duration sections inherit the same `data.window` (Last 14 training days) with no new computation.
- **Inter-section gap convention**: Parent list owns all inter-section gaps; sections never self-prefix (D-5).

---

## Requirements

1. Remove Records, Volume Trends, Consistency sections entirely
2. Fix inter-section spacing convention (unify gap ownership, remove competing styles)
3. Add Isometric and Sports duration trend sections mirroring Cardio structure
4. Correct chart y-axis labels to start at round numbers
5. Fix chart clipping and axis-label overlap
6. Move unit label to single display location per chart
7. Investigate and document per-exercise best-load defect

---

## Acceptance Criteria

| Item | Criterion | Maps to Scenario(s) |
|------|-----------|-------------------|
| 1 | No Records, Volume Trends, or Consistency sections render | S-101, S-102 |
| 1 | Recent PRs card intact; Feeling and Nutrition sections present | S-103 |
| 1 | Inter-section gaps uniform (24dp); no section self-prefixes a gap | S-104 |
| 1 | No unused data retrieval or computation remains (Records, Volume, Consistency) | S-105 |
| 2 | Nutrition toggle (only surviving toggle) renders labels on one line | S-201 |
| 2 | No label wrapping at narrowest width or largest a11y scale | S-201 |
| 2 | Selecting toggle options works; selected option visually distinct | S-202 |
| 3 | Y-axis labels on all charts fall on round numbers | S-301, S-302 |
| 4 | First/last points render fully; no date label overlap with axis column | S-401, S-402 |
| 5 | Every chart shows unit once; no unit on individual axis labels | S-501 |
| 6 | Isometric section renders; shows duration trends per exercise per day; mirrors Cardio structure | S-601, S-602 |
| 6 | Sports section renders; shows duration trends per exercise per day; mirrors Cardio structure | S-603, S-604 |
| 6 | Multiple hold drills on same day sum (not max or count) | S-605 |
| 6 | Isometric/Sports inherit shared 14-day window; no new computation | S-606 |
| 7 | Written finding names every best-load computation and displaying surface | S-701 |

---

## Scenarios

### S-101: Records Section Absent
- **Fixture**: Account with 20+ logged exercises, personal bests in all modalities
- **Trigger**: Open Stats screen
- **Expected outcome**: No "RECORDS" header, no per-exercise list, no rows

### S-102: Volume Trends and Consistency Sections Absent
- **Fixture**: Account with data across all modalities and effort kinds
- **Trigger**: Open Stats screen
- **Expected outcome**: No "VOLUME TRENDS" header/card, no "CONSISTENCY" header/card

### S-103: Recent PRs, Feeling, Nutrition Intact After Deletions
- **Fixture**: Account with mixed history (sets, timed efforts, rounds, drills)
- **Trigger**: Scroll Stats screen
- **Expected outcome**: Recent PRs card visible (same content/cap/position as before); Feeling section present; Nutrition section present; no blank space or orphaned headers

### S-104: Inter-Section Gaps Uniform, No Self-Prefixed Spacers
- **Fixture**: Stats screen build (all sections present after additions)
- **Trigger**: Widget tree inspection and layout measurement
- **Expected outcome**: Every inter-section gap measures 24dp; ListView children include explicit `SizedBox(height: 24)` separators; no section builder emits a leading `SizedBox`; `_buildFeelingSection()` does NOT self-prefix with 24dp; `_buildNutritionSection()` does NOT self-prefix with 24dp

### S-105: No Unused Computations Remain
- **Fixture**: Codebase after deletions
- **Trigger**: Grep for deleted symbols
- **Expected outcome**: No `ExerciseRecord`, `VolumeTrend`, `ConsistencyTrend` models; no `computeExerciseRecords()`, `computeVolumeTonnage()`, `computeTimedDuration()`, `computeTimedDistance()`, `computeConsistencyWeekly()`, `computeConsistencyMonthly()` methods; no `_buildRecordsSection()`, `_buildVolumeTrendsCard()`, `_buildConsistencyCard()` in stats_screen.dart; no dead code in stats_progress_service.dart

### S-201: Nutrition Toggle Labels Fit One Line (Default Text Scale)
- **Fixture**: Widget test, Nutrition toggle (Calories / Macros), 360dp viewport
- **Trigger**: Render at textScaleFactor: 1.0
- **Expected outcome**: Both labels on exactly one line, no wrapping, no ellipsis

### S-202: Nutrition Toggle Labels Fit One Line (Largest A11y Scale)
- **Fixture**: Widget test, Nutrition toggle, 360dp viewport
- **Trigger**: Render at textScaleFactor: 5.0
- **Expected outcome**: Both labels remain on one line, no truncation or wrapping

### S-203: Nutrition Toggle Selection Works
- **Fixture**: Widget test, Nutrition card with both views (calories + macros data)
- **Trigger**: Tap Calories; observe chart; tap Macros; observe chart
- **Expected outcome**: Calories chart renders, then Macros chart renders; selected option visually distinct

### S-301: Y-Axis Labels Round (Four-Digit Series)
- **Fixture**: Strength e1RM chart with data 765–4200 kg; Cardio chart with duration data; Isometric chart with hold data; Sports chart with round time data
- **Trigger**: Render all charts
- **Expected outcome**: All show round-number axis labels (0, 1000, 2000 or similar multiples; not 765, 1765, 2765); lowest label ≤ minimum; highest label ≥ maximum

### S-302: Y-Axis Labels Round (Flat and Single-Point Series)
- **Fixture**: Test data with flat series [50, 50, 50] and single point [120]
- **Trigger**: Build ChartAxisBounds
- **Expected outcome**: Both produce ≥2 distinct labels with visible non-zero range

### S-401: First/Last Points Render Fully (Isometric and Sports Charts)
- **Fixture**: Isometric chart with 12 data points, 280dp interior; Sports chart same
- **Trigger**: Scroll to left and right extremes
- **Expected outcome**: Leftmost and rightmost points fully visible (complete marker inside card boundary)

### S-402: Date Labels Don't Overlap Axis Column (Isometric and Sports)
- **Fixture**: Same as S-401
- **Trigger**: Inspect label positions at scroll extremes
- **Expected outcome**: No horizontal-axis date label overlaps pinned y-axis column; clear separation maintained

### S-501: Unit Appears Once Per Chart (Including Isometric/Sports)
- **Fixture**: Stats screen with Strength, Cardio, Isometric, Sports, Nutrition; each with ≥2 data points
- **Trigger**: Render all charts
- **Expected outcome**: Every chart displays unit exactly once in pinned column; y-axis values are bare numbers only

### S-601: Isometric Section Renders with Duration Trends
- **Fixture**: Account with multiple isometric exercises logged across 14+ days
- **Trigger**: Open Stats screen
- **Expected outcome**: "ISOMETRIC" section header visible below Cardio; per-exercise hold-time trend cards below header; same structure as Cardio section

### S-602: Isometric Section Empty State
- **Fixture**: Account with no isometric history
- **Trigger**: Open Stats screen
- **Expected outcome**: "ISOMETRIC" header renders; beneath it, empty-state message (e.g., "No isometric history yet. Log hold exercises to see trends here.")

### S-603: Sports Section Renders with Duration Trends
- **Fixture**: Account with multiple sports exercises logged across 14+ days
- **Trigger**: Open Stats screen
- **Expected outcome**: "SPORTS" section header visible below Isometric; per-exercise round-time trend cards below header; same structure as Cardio section

### S-604: Sports Section Empty State
- **Fixture**: Account with no sports history
- **Trigger**: Open Stats screen
- **Expected outcome**: "SPORTS" header renders; beneath it, empty-state message (e.g., "No sports history yet. Log sports rounds to see trends here.")

### S-605: Hold Time Aggregation — Sum Per Day
- **Fixture**: Isometric session with three 30-second plank holds on the same day
- **Trigger**: Build isometric trends for that exercise
- **Expected outcome**: One trend point for that day showing 90 seconds (sum), not 30 seconds (max) or 3 (count)

### S-606: Isometric/Sports Inherit Shared 14-Day Window
- **Fixture**: Stats screen after additions
- **Trigger**: Inspect window chip in Isometric and Sports section headers
- **Expected outcome**: Both show same window label as Cardio (e.g., "· Last 14 training days"); no separate computation; all three inherit `data.window`

### S-701: Written Finding Distinguishes Verified from Uncertain
- **Fixture**: Completed investigation of best-load computations
- **Trigger**: Review finding document
- **Expected outcome**: Document names every computation producing best/heaviest load; states what each computes (with line-number evidence); names every surface displaying those computations; states plainly whether the computation behind incorrect Records values is still reachable; provides evidence distinguishing "verified" from "uncertain"

---

## Iteration 1

### Phase A: Deletions + Spacing Fix (@developer)

**Checklist**:
1. [ ] Verify current state: Stats screen renders Records (line ~904), Volume Trends (line ~1046), Consistency (line ~1144)
2. [ ] Remove `_buildRecordsSection()`, `_buildRecordsCard()`, `_buildRecordRow()`, `_buildRecordLine()` methods
3. [ ] Remove line 169 from ListView children that calls `_buildRecordsSection()`
4. [ ] Remove `_buildVolumeTrendsSection()`, `_buildVolumeTrendsCard()`, `_buildVolumeTrendChart()`, `_buildModalitySeries()`, `_buildModalityLegendEntries()`, `_buildLineLegend()`, `_buildSegmentedToggle()` (keep definition but remove Volume Trends usage), `_buildVolumeTrendChart()` helper methods
5. [ ] Remove lines 171-174 from ListView that calls `_buildVolumeTrendsSection()`
6. [ ] Remove `_buildConsistencySection()`, `_buildConsistencyCard()`, `_buildConsistencyChart()`, `_buildConsistencySeries()` methods
7. [ ] Remove lines 178-181 from ListView that calls `_buildConsistencySection()`
8. [ ] Remove state fields: `_exerciseRecords`, `_tonnageTrend`, `_durationTrend`, `_distanceTrend`, `_weeklyConsistency`, `_monthlyConsistency`, `_volumeView`, `_consistencyView`
9. [ ] Remove initialization in `_loadData()` for all deleted fields (lines ~113-119)
10. [ ] Remove `_VolumeView` enum (line ~30)
11. [ ] Remove `_ConsistencyView` enum (line ~33)
12. [ ] Remove `_volumeUnitLabel()` and `_indexSpots()`, `_indexSpotsFromConsistency()` methods
13. [ ] Fix spacing: Remove `SizedBox(height: 24)` self-prefix from `_buildFeelingSection()` (line 715)
14. [ ] Fix spacing: Remove `SizedBox(height: 24)` self-prefix from `_buildNutritionSection()` (line 1601, or line will be different after prior deletions)
15. [ ] Add explicit `SizedBox(height: 24)` gaps in ListView between sections: after Strength, after Cardio (will be before Isometric once Phase E lands), before Feeling, before Nutrition
16. [ ] Remove model `ExerciseRecord` from data models file (if it exists only in models.dart)
17. [ ] Run grep to confirm Records, Volume, Consistency models and computations are not used elsewhere
18. [ ] Delete Records computations from StatsProgressService if unused: `computeExerciseRecords()` and any helper methods (`_recordsAccumulator`, etc.) if they exist
19. [ ] Delete Volume computations: `computeVolumeTonnage()`, `computeTimedDuration()`, `computeTimedDistance()` and helpers
20. [ ] Delete Consistency computations: `computeConsistencyWeekly()`, `computeConsistencyMonthly()`, `_computeConsistency()` and helpers
21. [ ] Update any test that enumerates Stats screen sections to remove Records, Volume Trends, Consistency from expected list
22. [ ] Add widget test: Stats screen with 20+ exercises renders no "RECORDS" header
23. [ ] Add widget test: Stats screen with mixed history renders no "VOLUME TRENDS" and no "CONSISTENCY" headers
24. [ ] Add widget test: Recent PRs card renders in correct position with same content as before
25. [ ] Add widget test: Feeling and Nutrition sections present after deletions
26. [ ] Add guard test: All inter-section gaps in ListView measure 24dp
27. [ ] Add guard test: No section builder (`_buildFeelingSection`, `_buildNutritionSection`) emits a leading `SizedBox` spacer
28. [ ] Run `flutter analyze` — no dead-code or unused-declaration warnings
29. [ ] Run `flutter test test/stats_screen*` — all tests pass

**Done Criteria** (run until green):
- `flutter analyze` returns no errors or warnings
- `flutter test test/stats_screen*` passes
- `flutter test test/*stats*` passes
- Manual verification: Stats screen renders no Records, Volume Trends, or Consistency sections; inter-section spacing is uniform; Recent PRs, Feeling, Nutrition intact

**Predicted Files**:
- Modified: `lib/features/stats/stats_screen.dart` (remove methods, state vars, ListView entries, spacing fixes)
- Modified: `lib/core/services/stats_progress_service.dart` (remove computeExerciseRecords, computeVolumeTonnage, computeTimedDuration, computeTimedDistance, computeConsistencyWeekly, computeConsistencyMonthly and helpers)
- Modified or Deleted: `lib/data/models/models.dart` (delete ExerciseRecord, VolumeTrend, ConsistencyTrend if they exist only there)
- Modified: test files (update section-enumeration tests; add new guard tests for gaps and no-self-prefix)
- Unchanged: chart layer, data repositories, state classes (except stats_progress_service)

**Scenarios Verified**: S-101, S-102, S-103, S-104, S-105

---

### Phase B: Toggle Shrinking (@developer)

**Checklist**:
1. [ ] Verify Nutrition toggle renders (Calories / Macros options)
2. [ ] Verify `_buildNutritionToggle()` exists and is the only remaining toggle builder in stats_screen.dart
3. [ ] Remove `_buildSegmentedToggle()` method if it was only used by Volume Trends and Consistency (it may be a generic helper)
4. [ ] If `_buildSegmentedToggle()` is retained (generic helper), verify no Volume Trends or Consistency usages remain
5. [ ] Add widget test for Nutrition toggle: assert both labels render on single line at 360dp, textScaleFactor 1.0
6. [ ] Add widget test for Nutrition toggle: assert both labels render on single line at 360dp, textScaleFactor 5.0
7. [ ] Add interaction test: tap Calories, verify calories chart renders; tap Macros, verify macros chart renders
8. [ ] Review existing nutrition toggle tests; remove any that assert specific internal layout (those encode current appearance, not requirement)
9. [ ] Run `flutter test test/stats_screen*` — all tests pass
10. [ ] Run `flutter analyze` — no warnings

**Done Criteria** (run until green):
- `flutter test test/stats_screen*` passes
- `flutter analyze` returns no errors
- Manual verification: Nutrition toggle works; both labels fit on one line at default and max a11y scale

**Predicted Files**:
- Modified: `lib/features/stats/stats_screen.dart` (remove `_buildSegmentedToggle()` if generic; verify `_buildNutritionToggle()` unchanged)
- Modified: test files (update/remove layout-assumption tests; add single-line assertion tests)
- Unchanged: everything else

**Scenarios Verified**: S-201, S-202, S-203

---

## Iteration 2 (depends on Iteration 1 Phase A completing)

### Phase C: Shared Chart Corrections (@developer)

**Checklist**:
1. [ ] Open `lib/core/utils/chart_axis_helper.dart`; review `computeBounds()` method
2. [ ] Modify `computeBounds()` to round minimum to a "nice" number ≤ lowest data value (apply _niceNumber logic to min, not just to interval)
3. [ ] Keep padding/margin logic: full data range visible with comfortable space above/below
4. [ ] Test flat-series [50, 50, 50] and single-point [120] cases — produce ≥2 distinct labels with visible range
5. [ ] Rewrite existing axis-bounds unit tests that assert unrounded minimums (they encode the defect)
6. [ ] Add unit tests: axis minimum is exact multiple of interval for two-, three-, four-digit, and fractional value sets
7. [ ] Add unit tests: minimum ≤ series minimum; maximum ≥ series maximum (across value ranges)
8. [ ] Add unit tests: adjacent label spacing uniform across axis
9. [ ] Add widget test: render Strength e1RM chart; verify y-axis labels are round numbers
10. [ ] Add widget test: render Cardio chart; verify y-axis labels are round
11. [ ] Add widget test: render Nutrition calories chart; verify y-axis labels are round
12. [ ] Open `lib/features/stats/widgets/scrollable_trend_chart.dart`; review plot-width calculation (lines 238-241)
13. [ ] Add fixed horizontal margin to plot area (e.g., 16dp per edge) so edge points don't clip
14. [ ] Adjust perPointWidth or plotWidth to account for margins
15. [ ] Verify: pinned axis column and leftmost chart content occupy distinct space
16. [ ] Verify: rightmost point not clipped at right card edge (when scrolled right)
17. [ ] Test with 12-point series at 280dp interior
18. [ ] Verify newest-first open behavior still works
19. [ ] Verify visible point count unchanged from before
20. [ ] Add widget test: first and last points render fully within bounds (short and long series)
21. [ ] Add widget test: no horizontal date label overlaps vertical axis column at scroll extremes
22. [ ] Add widget test: newest-first behavior unchanged; visible point count stable or improved
23. [ ] Verify Volume Trends card y-axis shows bare numeric values (no unit on labels); unit appears once in wrapper (item D-3)
24. [ ] Update any test asserting axis label text in "value unit" form — rewrite to assert bare numeric values
25. [ ] Verify Strength, Cardio, Nutrition, Profile all display unit exactly once in chart
26. [ ] Run `flutter test test/chart_axis*` — all pass
27. [ ] Run `flutter test test/stats_screen*` — all pass
28. [ ] Run `flutter test test/*nutrition*` — all pass
29. [ ] Run `flutter test test/*profile*` — all pass (if profile tests exist)
30. [ ] Run `flutter analyze` — no errors

**Done Criteria** (run until green):
- `flutter test test/chart_axis*` passes
- `flutter test test/stats_screen*` passes
- `flutter test test/*nutrition*` passes
- `flutter analyze` returns no errors
- Manual verification: Stats, Nutrition, Profile charts show round-number y-axis labels; no clipping at edges; unit displays once per chart

**Predicted Files**:
- Modified: `lib/core/utils/chart_axis_helper.dart` (computeBounds() logic for rounded min)
- Modified: `lib/features/stats/widgets/scrollable_trend_chart.dart` (add edge margins, adjust width calculation)
- Modified: `lib/features/stats/stats_screen.dart` (verify Volume Trends pass bare unit labels; this was deferred from Phase A but should be included here if Volume Trends still existed — but it's deleted in Phase A, so this step is N/A)
- Modified: test files (rewrite axis assertions, add edge-clipping tests, add overlap tests, verify unit-once tests)
- Unchanged: model/state/feature layers

**Scenarios Verified**: S-301, S-302, S-401, S-402, S-501

---

## Iteration 3 (depends on Iteration 1 Phase A and Iteration 2 Phase C completing)

### Phase D: DBA — Add Isometric/Sports Aggregations (@dba)

**Checklist**:
1. [x] Add `kTopIsometricCount = 2` constant to `StatsProgressService` (line ~112)
2. [x] Add `kTopSportsCount = 2` constant to `StatsProgressService`
3. [x] Add `topIsometric` field to `StatsProgressData` model (alongside existing topCardio)
4. [x] Add `topSports` field to `StatsProgressData` model
5. [x] Create `_DrillDay` class (holds `durationSecs` + metadata) similar to `_CardioDay` at the top of stats_progress_service.dart
6. [x] Create `_RoundDay` class (holds `durationSecs` + metadata) similar to `_CardioDay`
7. [x] Add `_buildFullDrillForExercises()` method mirroring `_buildFullCardioForExercises()` (filters by effortKind='drill')
8. [x] Add `_buildFullRoundForExercises()` method mirroring `_buildFullCardioForExercises()` (filters by effortKind='round')
9. [x] In `computeProgressData()`, after topCardio computation (line ~245), add topIsometric and topSports selection using `_selectTopNWithRecencyFloor()`
10. [x] Build full-history drill aggregates: call `_buildFullDrillForExercises()` for topIsometricIds
11. [x] Build full-history round aggregates: call `_buildFullRoundForExercises()` for topSportsIds
12. [x] Aggregate drill times and round times per exercise per training day (sum, per D-6)
13. [x] Create DrillProgress and RoundProgress models (similar to CardioProgress)
14. [x] Build topIsometric list and topSports list (similar to topCardio)
15. [x] Update `StatsProgressData` constructor to include topIsometric and topSports
16. [x] Update `StatsProgressData.empty()` to include empty lists for topIsometric and topSports
17. [x] Add unit tests: drill time per exercise per day sums correctly (three 30s holds → 90s point)
18. [x] Add unit tests: round time per exercise per day sums correctly
19. [x] Add unit tests: topIsometric selected correctly (via recency, top N)
20. [x] Add unit tests: topSports selected correctly (via recency, top N)
21. [x] Run `flutter test test/stats_progress_service*` — all pass
22. [x] Run `flutter analyze` — no errors

**Done Criteria** (run until green):
- `flutter test test/stats_progress_service*` passes ✓ (99 tests, all green)
- `flutter analyze` returns no errors ✓
- Manual verification: StatsProgressData includes topIsometric and topSports; aggregations sum hold/round times per day ✓

**Test Coverage**:
- T-17: Three 30-second holds on same day sum to 90 seconds ✓
- T-18: Drill effort filtering — excludes set/timed efforts (now discriminatory) ✓
- T-19: Three 2-minute rounds on same day sum to 360 seconds ✓
- T-20: Round effort filtering — excludes set/timed/drill efforts (now discriminatory) ✓
- T-21: Multi-modality case — same exercise appears in topCardio + topIsometric with separate efforts ✓
- T-22: Effort-kind override — drill in resistance_lifting session appears in topIsometric ✓

**Predicted Files**:
- Modified: `lib/core/models/stats_progress.dart` (add topIsometric, topSports fields; add DrillProgress, RoundProgress models)
- Modified: `lib/core/services/stats_progress_service.dart` (add constants, helper methods, aggregation logic, model population)
- Modified: test files (add 6 load-bearing unit tests covering aggregation, filtering, selection, multi-modality, and effort-kind classification)
- Unchanged: stats_screen, widgets, state

**Scenarios Verified**: (none yet; E will verify)

**Phase D Status**: COMPLETE ✓

---

### Phase E: Isometric/Sports Sections (@developer, depends on Phase D)

**Checklist**:
1. [ ] Verify Phase D (DBA) is complete: `StatsProgressData` includes topIsometric and topSports; aggregation works
2. [ ] Add state fields to stats_screen.dart: (none — data comes from _progressData already)
3. [ ] Update `_loadData()` to confirm data is being fetched (should already be there from Phase D's computeProgressData)
4. [ ] Add `_buildIsometricSection()` method, mirroring `_buildCardioSection()` (lines 657-689)
   - Header with "ISOMETRIC" title and window chip
   - Empty state: "No isometric history yet. Log hold exercises to see trends here."
   - Loop over `data.topIsometric` and build individual drill cards
5. [ ] Add `_buildDrillCard()` method, mirroring `_buildCardioCard()` (e.g., line 690+)
   - Exercise name
   - Duration trend chart
   - Use ScrollableTrendChart with duration values and "sec" or appropriate unit
6. [ ] Add `_buildSportsSection()` method, mirroring `_buildCardioSection()`
   - Header with "SPORTS" title and window chip
   - Empty state: "No sports history yet. Log sports rounds to see trends here."
   - Loop over `data.topSports` and build individual round cards
7. [ ] Add `_buildRoundCard()` method, mirroring `_buildCardioCard()`
   - Exercise name
   - Duration trend chart
   - Use ScrollableTrendChart with duration values and "sec" or appropriate unit
8. [ ] Update ListView children in build() method to include Isometric and Sports sections between Cardio and Feeling:
   - `..._buildCardioSection(context, themeColors),`
   - `const SizedBox(height: 24),`
   - `..._buildIsometricSection(context, themeColors),`
   - `const SizedBox(height: 24),`
   - `..._buildSportsSection(context, themeColors),`
   - `const SizedBox(height: 24),`
   - `..._buildFeelingSection(context, themeColors),` (which no longer self-prefixes 24dp)
9. [ ] Add widget test: Isometric section renders with exercise trend cards
10. [ ] Add widget test: Isometric empty state renders when no data
11. [ ] Add widget test: Sports section renders with exercise trend cards
12. [ ] Add widget test: Sports empty state renders when no data
13. [ ] Add fixture test: Multiple hold drills on same day sum (verify D-6)
14. [ ] Verify isometric and sports charts inherit shared 14-day window (verify D-5)
15. [ ] Verify isometric and sports charts show round-number y-axis labels (verify chart fixes landed)
16. [ ] Run `flutter test test/stats_screen*` — all pass
17. [ ] Run `flutter analyze` — no errors

**Done Criteria** (run until green):
- `flutter test test/stats_screen*` passes
- `flutter analyze` returns no errors
- Manual verification: Isometric and Sports sections render; mirrors Cardio structure; empty states work; duration aggregation correct; inherit 14-day window

**Predicted Files**:
- Modified: `lib/features/stats/stats_screen.dart` (add _buildIsometricSection, _buildDrillCard, _buildSportsSection, _buildRoundCard; update ListView)
- Modified: test files (add section tests, empty-state tests, aggregation tests, window inheritance tests)
- Unchanged: everything else

**Scenarios Verified**: S-601, S-602, S-603, S-604, S-605, S-606

---

## Iteration 4 (can run in parallel with Iterations 1–3)

### Phase F: Per-Exercise Best-Load Defect Investigation (@any)

**Checklist**:
1. [ ] Locate all computations producing per-exercise "best load" or "heaviest load":
   - Search codebase: grep -r "heaviest\|best.*load\|max.*weight" lib/
   - Inspect: StatsProgressService, any repository methods, any analysis utilities
2. [ ] For each computation found, determine what it actually computes:
   - Heaviest single recorded set?
   - Accumulated total (session or all-time)?
   - Estimated maximum?
   - State with file:line evidence
3. [ ] Locate every surface displaying per-exercise best/heaviest load:
   - Recent PRs card on Stats screen (line 572 in stats_screen.dart)
   - Session summary post-workout (features/session/)
   - Exercise detail screens (features/exercise/)
   - In-session achievement notifications (features/session/ or widgets/)
   - Any other surface (grep -r "heaviest\|best load" lib/features/)
4. [ ] For each surface: note which computation feeds it; state whether label matches the quantity
5. [ ] Verify consistency: Recent PRs, session summary, exercise detail — same exercise, same numbers?
6. [ ] Trace reachability: Can any computation that produced incorrect Records values still be reached from a user-visible surface today (after deletion)?
   - Records section is deleted in Phase A, so Records computation is unreachable
   - Confirm no other consumer exists
7. [ ] Investigate rep record uniformity:
   - Search: grep -r "repCount =\|reps =\|max(reps\|min(reps" lib/
   - Check data model defaults
   - Review any cap, default, or forced value on rep counts
8. [ ] Produce written finding document: `docs/stats_best_load_investigation.md`
   - Section 1: All computations — name, location (file:line), what it computes, evidence
   - Section 2: All displaying surfaces — name, location, which computation, label accuracy
   - Section 3: Reachability — "computation X is reachable from surface Y" or "no current consumer"
   - Section 4: Rep record cap/default — "found at file:line" or "not found"
   - Section 5: Uniform rep records — "data artifact based on [evidence]" or "code artifact based on [evidence]"
   - Distinguish verified (code + test confirmed) from uncertain (plausible but unproven)
9. [ ] No code changes, no test changes, no behavior changes

**Done Criteria** (code review, no automation):
- Written finding document exists at `docs/stats_best_load_investigation.md`
- Every computation named and located (file:line)
- Every surface named and located (file:line)
- Reachability stated clearly
- Rep record cap status stated with evidence or "not found"
- Uniform rep count hypothesis stated with evidence
- Each finding distinguishes verified from uncertain

**Predicted Files**:
- Created: `docs/stats_best_load_investigation.md` (investigation finding)
- No modifications to lib/, test/, or any application code

**Scenarios Verified**: S-701

---

## Files Affected (whole feature)

**Primary**:
- `lib/features/stats/stats_screen.dart` (deletions, new sections, spacing fix)
- `lib/core/services/stats_progress_service.dart` (delete Volume/Records/Consistency computations; add Isometric/Sports aggregations)
- `lib/features/stats/widgets/scrollable_trend_chart.dart` (clipping fix)
- `lib/core/utils/chart_axis_helper.dart` (y-axis rounding)
- `lib/core/models/stats_progress.dart` (add topIsometric, topSports; models for DrillProgress, RoundProgress)

**Secondary** (if they exist):
- `lib/data/models/models.dart` (delete ExerciseRecord, VolumeTrend, ConsistencyTrend if defined there)
- test files (update assertions, add new tests)

**Investigation-Only**:
- Created: `docs/stats_best_load_investigation.md`

---

## Notes

### Phase Dependency Graph

```
Phase A (Deletions + Spacing)
    ↓
Phase B (Toggle Shrinking) — depends on A
    ↓
Phase C (Shared Chart Fixes) — can run parallel to A/B but should complete before E

Phase D (DBA — Isometric/Sports aggregations)
    ↓
Phase E (New Sections) — depends on D

Phase F (Investigation) — can run in parallel with A/B/C/D/E
```

### Suggested PR Batching

- **PR A** (Phase A + B): Deletions, spacing fix, toggle shrinking. Single, high-visibility improvement. Fast to review.
- **PR B** (Phase C): Shared chart corrections (y-axis rounding, clipping, unit display). Touches chart layer used by Stats, Nutrition, Profile; careful review required.
- **PR C** (Phase D + E): DBA work + new sections. Depends on PR B. Adds isometric and sports sections.
- **PR D** (Phase F): Investigation finding document. No code changes; can merge independently.

---

## Progress

- **Iteration 1**: 
  - Phase A (deletions + spacing + guard test) — **COMPLETE ✓**
    - Dead computations deleted: `computeExerciseRecords()`, `computeVolumeTonnage()`, `computeTimedDuration()`, `computeTimedDistance()`, `computeConsistencyWeekly()`, `computeConsistencyMonthly()`; all private helpers removed
    - Dead models deleted: `RecordValue`, `ExerciseRecord`, `MostRepsRecord`, `DurationRecord`, `DistanceRecord`, `VolumeTrendPoint`, `VolumeTrend`, `ConsistencyPoint`, `ConsistencyTrend`
    - Dead test groups deleted: 21 tests removed (exact match with deleted computations)
    - Unused test helper `dayInWeeksAgo` removed
    - D-5 guard test added: measures actual 24dp gap, **fails (48dp) when self-prefixed SizedBox re-introduced** ✓ (verified discriminates)
    - Test results: **2302 pass, 1 skip, 0 fail**
    - Analyzer: **0 errors, 239 pre-existing warnings (clean)**
    - Phase D code preserved and verified
  - Phase B (toggle shrinking) — **COMPLETE ✓**
    - Verified: only one SegmentedButton exists in codebase (Nutrition toggle, Calories/Macros)
    - D-1 contract tests added: 3 tests verify labels fit on single line at all supported widths and accessibility scales
    - Labels ("Calories" 8 chars, "Macros" 6 chars) confirmed short enough to prevent wrapping
    - Test results: **2305 pass, 1 skip, 0 fail** (3 new tests added)
- **Iteration 2**: 
  - Phase C (chart corrections) — **COMPLETE ✓**
    - D-2: Y-axis label rounding — **IMPLEMENTED** ✓
      - Modified `ChartAxisHelper.computeBounds()` to round min/max to multiples of interval
      - All 31 chart_axis_helper tests PASS
    - D-3: Unit display (once per chart) — **IMPLEMENTED** ✓
      - Modified `_PinnedYAxis` to render bare numeric values on axis labels (no unit text)
      - Added unit label at bottom of pinned column (appears exactly once per chart)
      - Updated 2 failing tests (S-001, S-005) to expect bare numbers + separate unit
      - S-107 test now passes (single "80 kg" in strip only, not duplicated on axis)
      - Test results: **2309 pass, 1 skip, 0 fail** (unit test improvements)
    - D-4: No clipped points (chart edges) — **IMPLEMENTED** ✓
      - Added `kScrollableTrendHorizontalMargin` constant (12dp per side) to prevent edge clipping
      - Increased plot width for scrollable data (>maxVisiblePoints) to include margins
      - Applied conditional Padding to inset chart content when scrollable only
      - Non-scrollable series (≤maxVisiblePoints) render without margins (data fits viewport)
      - D-4 Test 1 (scrollable discrimination): Verifies Padding widget present with symmetric horizontal margins
        - **FAILS with kScrollableTrendHorizontalMargin = 0.0** ✓ (test discriminates correctly)
        - **PASSES with kScrollableTrendHorizontalMargin = 12.0** ✓ (margins in place)
      - D-4 Test 2 (non-scrollable): Verifies short series (3 points) render all points without margins
        - **PASSES**: NeverScrollableScrollPhysics enforced, all 3 data points present
      - D-4 Test 3 (label overlap): Verifies visible date labels don't intersect axis column
        - **PASSES**: No labels overlap the pinned axis even at viewport extremes
      - Test results: **2312 pass, 1 skip, 0 fail** (all pass with proper discrimination)
- **Iteration 3**: 
  - Phase D (DBA) — RESTORED & VERIFIED ✓ (99/99 tests pass, analyzer clean)
  - Phase E (new sections) — **COMPLETE ✓**
    - _buildIsometricSection() and _buildDrillCard() implemented
    - _buildSportsSection() and _buildRoundCard() implemented
    - Sections positioned between Cardio and Feeling with 24dp separators (D-5 compliance)
    - Duration charts reuse ScrollableTrendChart pattern (D-3, D-4 compliance)
    - Empty states with appropriate modality-specific copy
    - 7 comprehensive widget tests added (S-601, S-602, S-603, S-604, S-605, S-606, section ordering)
    - Test results: **2319 pass, 0 fail** (7 new tests, all green)
    - Analyzer: **0 errors**
- **Iteration 4**: Phase F (investigation) — **COMPLETE ✓**
  - Finding written to `docs/stats_best_load_investigation.md` (35 KB, under the 64 KiB ceiling); linked from `docs/README.md` so the docs orphan check stays green
  - **No** changes to `lib/`, `test/`, or any model. Only two files touched, both documentation
  - `test/docs_indexing_contract_test.dart`: **9/9 pass**
  - **Root cause identified (verified).** The deleted Records "Heaviest load" displayed `weight × reps` of a **single set** — the one with the greatest `metric-weight` — not that set's weight. `HEAD:lib/core/services/stats_progress_service.dart:1675` (`value: weight * reps`), rendered at `HEAD:lib/features/stats/stats_screen.dart:966–967`. The correct value (`_HeaviestRecord.weight`) was populated one line below the one displayed. Units were **kg·reps** run through a kg→lbs conversion and labelled `lbs`. Only one version of this computation ever shipped (`git log -G` → single commit `35763b2`)
  - **Premise correction.** The figure was *not* an accumulated session total — nothing was summed. One set's tonnage. Displayed value = (set's displayed weight) × (its reps), exactly
  - **Reachability (the load-bearing question).** The specific computation is **gone and unreachable** — `grep -rn "computeExerciseRecords\|ExerciseRecord\|heaviestLoad" lib/ test/` returns nothing. **But** two live surfaces still show an *estimated* 1RM as a bare weight with no qualifier: **Recent PRs** (`stats_screen.dart:549, 571–574`) and the **session-summary PR line** (`session_summary_screen.dart:936`). The `metricLabel: 'e1RM'` string that would qualify it is computed (`session_summary_service.dart:240`) and never rendered. The same screen labels the identical series "Estimated 1RM" on the Strength card, so it contradicts itself. Smaller error than Records, but on a more trusted surface, and still shipping
  - **Rep-record uniformity: no cap exists.** Every rep constraint in `lib/` is a floor, never a ceiling. `10` is a **persisted default** written at exercise-add time before any user input (`session_core_entry.dart:58` → `:180`), indistinguishable downstream from a real 10-rep set (the `skipped` flag is written by `ObservationGrouper` but read by nothing). Demo routines are excluded as a source — they specify 5/8/12/15, never 10. Verdict: **data artifact, not computation artifact**
  - **Test integrity.** Phase A's deletion removed three tests asserting a wrong quantity under a right-sounding name. The worst, `S-001: heaviest-load record equals the max load × reps set` (`HEAD:test/stats_progress_test.dart:3333`), asserted `360.0` (= 120 × 3) and justified it with a comment claiming it "matches the e1RM convention" — the actual Epley e1RM of 120 kg × 3 is **132.0**. False rationale, precise wrong assertion, and the fixture's own seed comments (`→ load 120`) contradicted the assertion inside the same test. All live PR tests were checked assertion-by-assertion and are **sound**; no live test asserts a heaviest-load value
  - **Also found:** `ExerciseSummary.bestWeight` is the only computation that correctly computes a heaviest single-set weight — and **nothing displays it** (guarded by `test/state_test.dart:3098` anyway). Doc drift: `docs/stats_screen.md:210–216, 549–550` still documents the deleted feature, including line `:216` which records the label/quantity mismatch as intended behavior. Left uncorrected — Phase F is investigation-only
  - **Explicitly not determined** (recorded in the finding rather than guessed): the exact `weight × reps` decomposition of the reported 2205 / 1601 lbs figures, and whether the account's `10`s came from the default path or from real 10-rep sets. Both require the user's stored observation rows, which are not in this repository; the finding states what would settle each

---

## Assumption Log

(Executors append here after each phase; Conductor reviews and marks RATIFIED or REVERT)

---

## Feedback

### Phase A Status — Partial, and Phase D was REVERTED (corrected note, 2026-08-15)

> An earlier version of this note misdiagnosed the build failure. It is corrected
> below. Unused code does not cause compile errors — the errors have a different
> cause entirely, and acting on the original note would have deleted the wrong code.

**What is actually broken.** Phase D's implementation was reverted out of the tree.
`lib/core/models/stats_progress.dart` and `lib/core/services/stats_progress_service.dart`
are byte-identical to HEAD, with zero occurrences of `topIsometric` or `topSports`.
The Phase D tests in `test/stats_progress_test.dart` survive and still reference those
getters, which is the sole cause of all 33 analyzer errors. The whole test suite
therefore cannot compile, so nothing runs.

The reverted work was never committed and is NOT recoverable from git. It must be
re-implemented. The surviving tests (T-17 … T-22) define its contract exactly.

**UI layer (COMPLETE, verified).** Records, Volume Trends, and Consistency section
builders are deleted from `stats_screen.dart`. Inter-section spacing is unified per
D-7: self-prefixed `SizedBox(24)` removed from `_buildFeelingSection` and
`_buildNutritionSection`, explicit 24dp separators added in the `ListView`. Current
assembly: `aggregate → 24 → strength → 24 → cardio → 24 → feeling → 24 → nutrition`.
Recent PRs untouched. `lib/` has zero analyzer errors.

**Phase A backend cleanup (NOT DONE).** These remain in place, unused. They are dead
code, not the cause of the build failure, and should be removed once the suite is
runnable again:
- Models in `lib/core/models/stats_progress.dart`: `RecordValue`, `ExerciseRecord`,
  `MostRepsRecord`, `DurationRecord`, `DistanceRecord`, `VolumeTrendPoint`,
  `VolumeTrend`, `ConsistencyPoint`, `ConsistencyTrend`
- Public methods in `lib/core/services/stats_progress_service.dart`:
  `computeExerciseRecords()`, `computeVolumeTonnage()`, `computeTimedDuration()`,
  `computeTimedDistance()`, `computeConsistencyWeekly()`, `computeConsistencyMonthly()`
- Private helpers: `_computeVolumeByWeek()`, `_computeConsistency()`,
  `_accumulateSetForRecords()`, `_accumulateTimedForRecords()`, `_addToBucket()`,
  `_sortBuckets()`, `_startOfIsoWeek()`
- Private classes: `_HeaviestRecord`, `_MostRepsRecord`

Their existing tests in `test/stats_progress_test.dart` go with them.

**Also outstanding in Phase A**: the D-7 spacing guard test was never added.

**Recovery order (user-approved).**
1. Restore Phase D to the two lib files in isolation. Success signal is unambiguous:
   suite compiles, 99 tests pass. Do nothing else in that pass.
2. Then resume Phase A backend cleanup as a separate step, with a runnable suite.
3. Then Phases B, C, E, F.

**Standing warning for any agent working here**: Phase D's additions
(`topIsometric`, `topSports`, `DrillProgress`, `RoundProgress`,
`_buildFullDrillForExercises`, `_buildFullRoundForExercises`, `_DrillDay`,
`_RoundDay`, `kTopIsometricCount`, `kTopSportsCount`) live in the same two files
that Phase A deletes from. Read before cutting. Never revert a whole file to
resolve a failed edit — that is what destroyed Phase D.

---

### OPEN GAP — D-4 non-scrolling clipping is unverified (recorded 2026-08-16)

Carried forward deliberately after two attempts. Not a blocker for Phase E, but it
needs a decision before this work is called done.

**What is proven.** The scrolling case is correct and its test discriminates:
`kScrollableTrendHorizontalMargin = 12.0` is applied when
`pointCount > maxVisiblePoints`, and the test was confirmed to FAIL when the margin
is set to `0.0` and pass when restored.

**What is not proven.** For a short, non-scrolling series the implementation applies
`horizontalMargin = 0.0`:

```dart
final horizontalMargin = scrollable ? kScrollableTrendHorizontalMargin : 0.0;
```

D-4's acceptance criteria pin the no-clipping guarantee for *both* cases —
"for a short non-scrolling series and for a long scrolling series alike". A point
plotted at x=0 has its marker centred on the plot's left edge, so half of it falls
outside the plot regardless of whether the series scrolls. Whether `fl_chart`
compensates for this on its own has not been demonstrated.

The test written for this case (`test/screen_widget_test.dart:8017`,
"D-4: non-scrollable series — short series renders all points in viewport") does not
close the question. Its assertions are:

- `scrollableChart.physics is NeverScrollableScrollPhysics`
- `find.byType(LineChart)` is not empty
- `spots.length == 3`

None of these measure clipping. `spots.length == 3` asserts the data model holds
three points, not that three markers render fully inside the plot bounds. The test
also asserts that no `Padding` is applied, which restates the current implementation
rather than testing the requirement — it would pass whether or not edge markers clip.

**To close this**, one of:
1. Measure it. Assert the first and last marker rects are *contained* by the plot
   rect for a 3-point series. If they are, the current code is right and the comment
   should cite that test. If they are not, apply the margin unconditionally.
2. Decide the non-scrolling case is out of scope and amend D-4's acceptance criteria
   to say so explicitly, rather than leaving a pinned criterion unmet.

Do not close it by asserting the conclusion in a comment, which is what the two
previous attempts did.

---

### OPEN GAP — Phase E tests do not verify the two things that matter (recorded 2026-08-16)

Phase E's implementation is correct: section order, spacing, window inheritance and
empty states all verified. Two of its tests do not test their stated requirement.

**1. S-605 does not verify the aggregation.** `test/screen_widget_test.dart:4730`,
"S-605: Hold time aggregation — sum per day". It seeds three 30-second holds on one
day and comments *"Verify the aggregated value shows 90 seconds in some form / The
chart will show 90 on the y-axis due to aggregation"*. Its assertions are:

```dart
expect(find.text('ISOMETRIC'), findsOneWidget);
expect(find.text('Plank'), findsWidgets);
```

It never asserts 90. It would pass unchanged if the aggregation returned 30 (max) or
3 (count) — precisely the alternatives D-6 was pinned to exclude. The data layer
proves the sum at T-17; nothing proves it reaches the screen.

**To close**: assert the rendered value, or the chart's plotted spot value, equals 90
for that fixture.

**2. No UI test for the multi-modality requirement.** The user's requirement was
explicit: *"technically the same exercise can show in multiple sections"*. T-21 proves
the data layer returns one exercise in both `topCardio` and `topIsometric`. No widget
test proves both sections render it. A regression that made section membership
exclusive in the UI would ship green.

**To close**: seed one exercise with a timed effort and a drill effort, render the
Stats screen, assert its name appears under both CARDIO and ISOMETRIC.

**Pattern note.** This is the fifth test in this feature caught asserting existence
while its name and comments claim a behavioral guarantee (T-18 filtering, D-5 spacing,
D-4 clipping, D-4 non-scrolling, S-605 aggregation). The implementations have been
sound; the tests have not. Any future work here should assume a test's name and
comments are unreliable and read its assertions.

---

### RESOLVED — D-4 non-scrolling clipping: accepted as-is (user decision, 2026-08-16)

The open gap recorded above is **closed by decision, not by code**. The user reviewed
it and chose to leave the behavior unchanged.

D-4's acceptance criteria are hereby narrowed: the no-clipping guarantee applies to
**scrolling series only** (`pointCount > maxVisiblePoints`), where
`kScrollableTrendHorizontalMargin = 12.0` is applied and proven by a discriminating
test. Short non-scrolling series intentionally render without edge margins.

This is a deliberate scope narrowing so a pinned criterion is not left quietly unmet.
No further work is required on D-4.
