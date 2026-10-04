# Constants & Configuration Reference

## Overview

Foundational constants live in `lib/core/constants/`. These define the vocabulary of the application: modalities, capabilities, effort kinds, metrics, intents, display mappings, and design tokens.

---

## Modality Constants

**File**: `lib/core/constants/modality.dart`

### Primary Modalities (Home Screen Tiles)

| Constant | Value | Home Tile |
|----------|-------|-----------|
| `cardioEndurance` | `'cardio_endurance'` | Cardio / Endurance |
| `resistanceLifting` | `'resistance_lifting'` | Resistance / Lifting |
| `sports` | `'sports'` | Sports |
| `isometricStretching` | `'isometric_stretching'` | Isometric / Stretching |
| (null) | `null` | Free Training |

### Legacy Modalities (for backward compatibility)
`strength_resistance`, `skill_technique`, `conditioning_mixed`, `mobility_flexibility`, `recovery_rehab`, `competition_match`

> **Note**: `martial_arts` was fully retired in Apr 2026 (see `retire-martial-arts-category-plan.md`). Boxing, BJJ, and Muay Thai disciplines were reparented under `category-sports`. The constant and compat guard have been removed.

### Category Mappings

- `modalityToCategoryId` — maps each primary modality to one `SportCategory` ID
  - `cardio_endurance` → `category-cardio`
  - `resistance_lifting` → `category-resistance`
  - `sports` → `category-sports`
  - `isometric_stretching` → `category-isometric`

- `modalityToCategoryIds` — plural version for exercise ranking
  - `sports` maps to `['category-sports']`

---

## Capability Constants

**File**: `lib/core/constants/capability.dart`

Exercise capability flags indicating what an exercise can track:

| Constant | Value | Description |
|----------|-------|-------------|
| `time` | `'time'` | Continuous duration |
| `hold` | `'hold'` | Isometric hold duration |
| `reps` | `'reps'` | Repetition counting |
| `sets` | `'sets'` | Set grouping |
| `load` | `'load'` | External weight/resistance |
| `distance` | `'distance'` | Distance covered |
| `rounds` | `'rounds'` | Round/period segments |

---

## Effort Kind & Block Type Constants

**File**: `lib/core/constants/block_types.dart`

### Effort Kinds (unit of logged work)

| Constant | Value | UI Rendering |
|----------|-------|-------------|
| `set` | `'set'` | Reps + weight editors |
| `timed` | `'timed'` | Duration timer + distance + optional extra weight |
| `round` | `'round'` | Round counter + countdown |
| `drill` | `'drill'` | Hold timer + extra weight |

Additional effort kinds (less commonly used): `interval`, `amrap`, `note`

### Segment Types (structural blocks)

`strength_sets`, `timed_activity`, `distance_intervals`, `round_based`, `amrap_for_time`, `drill_skill`, `freeform`

---

## Metric ID Constants

**File**: `lib/core/constants/metric_ids.dart`

| Constant | Value | Used In |
|----------|-------|---------|
| `reps` | `'metric-reps'` | set |
| `weight` | `'metric-weight'` | set |
| `duration` | `'metric-duration'` | timed, round, drill |
| `distance` | `'metric-distance'` | timed |
| `rounds` | `'metric-rounds'` | round |
| `roundDuration` | `'metric-round-duration'` | round |
| `rpe` | `'metric-rpe'` | set, timed, round, amrap |
| `extraWeight` | `'metric-extra-weight'` | timed, drill (negative = band assist, positive = added load) |

---

## Profile Measurement Constants

**File**: `lib/core/constants/profile_measurements.dart`

Defines the canonical profile measurement vocabulary and unit mapping shared by `ProfileState`, `ProfileScreen`, and measurement history UI.

### Primary Measurements

| Constant | Type Value | Label | Unit ID |
|----------|------------|-------|---------|
| `bodyweight` | `bodyweight` | Body Weight | `unit-kg` |
| `height` | `height` | Height | `unit-cm` |

### Additional Measurements

| Constant | Type Value | Label | Unit ID |
|----------|------------|-------|---------|
| `bodyFatPct` | `body_fat_pct` | BODY FAT | `unit-pct` |
| `leanMass` | `lean_mass` | Lean Mass | `unit-kg` |
| `waist` | `waist_cm` | Waist | `unit-cm` |
| `chest` | `chest_cm` | Chest | `unit-cm` |
| `hips` | `hips_cm` | Hips | `unit-cm` |
| `thigh` | `thigh_cm` | Thigh | `unit-cm` |
| `arm` | `arm_cm` | Arm | `unit-cm` |

### Helper APIs

- `definitionFor(type)` returns the matching `ProfileMeasurementDefinition` for a measurement type string.
- `unitLabelFor(unitId)` maps ids to display labels (`kg`, `cm`, `%`).
- `formatValue(value)` formats whole numbers without decimals and keeps one decimal when needed.

---

## Intent Constants

**File**: `lib/core/constants/intent.dart`

Session purpose classification:

| Constant | Value | Display Name |
|----------|-------|-------------|
| `easyBase` | `'easy_base'` | Easy / Base |
| `intervalsSpeed` | `'intervals_speed'` | Intervals / Speed |
| `tempoThreshold` | `'tempo_threshold'` | Tempo / Threshold |
| `strength` | `'strength'` | Strength |
| `hypertrophy` | `'hypertrophy'` | Hypertrophy |
| `power` | `'power'` | Power |
| `techniqueDrills` | `'technique_drills'` | Technique / Drills |
| `sparringLive` | `'sparring_live'` | Sparring / Live |
| `recovery` | `'recovery'` | Recovery |
| `testBenchmark` | `'test_benchmark'` | Test / Benchmark |

Plus the special `routine` intent for sessions started from a routine template.

---

## Modality Configuration

**File**: `lib/core/constants/modality_config.dart`

`ModalityConfig` maps each modality to its scoring rules and default effort kind:

| Property | Purpose |
|----------|---------|
| `primaryCapabilities` | Strong positive signals for exercise ranking |
| `secondaryCapabilities` | Weaker positive signals |
| `antiCapabilities` | Negative signals (reduce score) |
| `categoryId` | Discipline-category affinity bonus |
| `effortKind` | Default UI rendering mode |
| `primaryMetric` | Main tracking metric |

**Key static methods**:
- `ModalityConfig.forModality(String? modality)` — returns config for a modality
- `ModalityConfig.effortKindFromMetric(String metric)` — derives effort kind from chosen metric
- `calculateRelevanceScore({exerciseCapabilities, exerciseCategoryId})` — computes numeric relevance score

---

## Modality Display

**File**: `lib/core/constants/modality_display.dart`

Maps modality keys to UI display information:
- Display names (e.g., `cardio_endurance` → "Cardio / Endurance")
- Icons
- Terminology overrides (e.g., `sports` uses "Period" instead of "Round")

---

## Effort Defaults

**File**: `lib/core/constants/effort_defaults.dart`

Default target values when creating new sets/entries:

| Effort Kind | Default Targets |
|-------------|----------------|
| `set` | 10 reps, 0 weight |
| `timed` | 0 seconds duration, 0 distance, 0.0 extra weight |
| `round` | 180 seconds (3 min), 1 round |
| `drill` | 0 seconds, 0.0 extra weight |

---

## Workout Constants

**File**: `lib/core/constants/workout_constants.dart`

| Constant | Value | Purpose |
|----------|-------|---------|
| `defaultRoundDurationSecs` | `180` | Default 3-minute round |
| `roundActualDurationCapFactor` | `2` | Safety cap: actual ≤ planned × 2 |

---

## Health Sync Constants

**File**: `lib/core/constants/health_constants.dart`

Vocabulary for the opt-in platform health integration (Apple Health / Health Connect). Kept free of
plugin types so the mapping logic is testable everywhere; the native gateway translates
`HealthActivityKind` to a platform activity type per platform.

| Symbol | Purpose |
|--------|---------|
| `HealthPrefs` | Preference keys for the two toggles and the written-session ledger, plus the ledger cap and read lookback window |
| `HealthToggleState` | `off` / `on` / `permissionDenied` — the third state is what lets a denied toggle stay visibly denied instead of reading as off |
| `HealthActivityKind` | App-owned workout vocabulary (`strength`, `cardio`, `flexibility`, `sport`, `conditioning`, `other`) that modality maps onto |
| `parseHealthToggleState` / `healthToggleStateValue` | The single serialization pair for the toggle states; unknown persisted values resolve to `off` |

---

## Training Load Constants

**File**: `lib/core/models/training_load.dart`

The figures behind the training-load mix. Named here so a reader can find the
owner; the file itself states each rule.

| Constant | Rule it governs |
|----------|-----------------|
| `kMixStripWeeks` | How many weeks a weekly strip holds |
| `kTrainingLoadBaselineWeeks` | How many 7-calendar-day blocks the baseline spans |
| `kTrainingLoadMinRatedWeeks` | How many rated baseline weeks the load measure needs before it is shown |
| `kTrainingLoadMaxUnratedShare` | The largest share of a window's time that may be unrated for the load measure to be shown; the boundary is inclusive |

Verified by `test/training_load_test.dart` (the constants group).

---

## Modality Mix Shift Constants

**File**: `lib/core/models/modality_mix_shift.dart`

The figures behind the Modality Mix Shift rule. Named here so a reader can find
the owner; the file itself states each rule.

| Constant | Rule it governs |
|----------|-----------------|
| `kModalityMixShiftPeriodDays` | The span of the period the rule compares against its baseline |
| `kModalityMixShiftMinBaselineShare` | The smallest baseline share a modality needs before it can be reported |
| `kModalityMixShiftPriority` | The signal's priority |

Verified by `test/modality_mix_shift_test.dart` (the constant contracts).

---

## Signals Constants

**File**: `lib/core/models/signals.dart`

The framework's caps and the keys its store persists under. Named here so a
reader can find the owner; the file itself states each rule.

| Constant | Rule it governs |
|----------|-----------------|
| `kSignalMaxCards` | How many cards one load may yield |
| `kSignalDismissalDays` | How many local calendar days a dismissal hides its signal |
| `kSignalDismissalsKey` | The repository preference key the dismissal store persists under |
| `kSignalQuietLine` | The sentence a gate-met load reports when no card qualifies |
| `kSignalPositiveLabel` / `kSignalCautionLabel` | The two kind labels, resolved by `signalKindLabel` |

Verified by `test/signals_framework_test.dart` (the selection group, the kind
vocabulary group and the dismissal-window group) and `test/signals_service_test.dart`
(the dismissal-store key group).

---

## Progression Rate Constants

**File**: `lib/core/models/progression_rate.dart`

The two windows, the three thresholds the card needs and the signal's priority.
Named here so a reader can find the owner; the file itself states each rule.

| Constant | Rule it governs |
|----------|-----------------|
| `kProgressionRateWindowDays` | The span of each of the two windows the rate compares |
| `kProgressionRateMinCounted` | How many counted exercise-sessions each window needs before the card may appear |
| `kProgressionRateMinRate` | The recent rate the card needs |
| `kProgressionRateMinImprovement` | How far the recent rate must exceed the prior rate |
| `kProgressionRatePriority` | The signal's priority, the highest among positives |

Verified by `test/progression_rate_test.dart` (the two windows and the
qualification test group).

---

## Interference Constants

**File**: `lib/core/models/interference.dart`

The windows, the boundaries and the priority behind the Cross-Modality
Interference rule. Named here so a reader can find the owner; the file itself
states each rule.

| Constant | Rule it governs |
|----------|-----------------|
| `kInterferenceHardWindowDays` | How far back the hard-session window reaches; both ends inclusive |
| `kInterferenceMinRatedSportsSessions` | The smallest rated-sports-session population that can classify anything |
| `kInterferenceHardPercentile` | The nearest-rank percentile that separates hard sessions from the rest; the boundary is inclusive |
| `kInterferenceFollowUpHours` | How long after a hard session's end a follow-up may start; the upper bound is inclusive |
| `kInterferenceDipWindowDays` | The lookback a follow-up's comparable exercises are averaged over; the lower bound inclusive, the upper exclusive |
| `kInterferenceMinDip` | The mean shortfall at which a follow-up dips; the boundary is inclusive within the rule's tolerance |
| `kInterferencePatternWindowDays` | The window the pattern is counted over; both ends inclusive |
| `kInterferenceMinDippedFollowUps` | How many dipped follow-ups the pattern needs |
| `kInterferenceSportsLoadWindowDays` | The recent span the optional second sentence compares |
| `kInterferenceSportsLoadRisePercent` | The rise that second sentence needs; the boundary is inclusive |
| `kCrossModalityInterferencePriority` | The signal's priority, the highest among cautions |

Verified by `test/interference_test.dart` (the constant contracts group, plus
the boundary scenarios S-2003, S-2004, S-2010 and S-2015); the caution order it
sits at the top of is pinned by `test/modality_mix_shift_test.dart`.

---

## Home Tile Configuration

**File**: `lib/core/constants/home_tiles.dart`

Defines the 6-tile grid as `HomeTileConfig` objects. Each tile's `accentColor` is sourced from `ModalityColors` (see below). Tile labels shown on screen are short forms; full display names are in `ModalityDisplay`.

| Key | Short Label | Full Label | Modality | Gradient Colors |
|-----|-------------|------------|----------|----------------|
| `cardio` | Cardio | Cardio / Endurance | `cardio_endurance` | Dark green tones |
| `resistance` | Resistance | Resistance / Lifting | `resistance_lifting` | Blue tones |
| `sports` | Sports | Sports | `sports` | Red tones |
| `isometric` | Isometric | Isometric / Stretching | `isometric_stretching` | Amber tones |
| `free_training` | Free | Free Training | `null` | Purple tones |
| `my_routines` | Routines | My Routines | `null` (special) | Grey tones |

---

## Modality Colors

**File**: `lib/core/constants/modality_colors.dart`

> **Single source of truth** for modality accent colors. All modality-specific UI must import from this file instead of redefining color hex values.

| Constant | Used for |
|----------|----------|
| `ModalityColors.cardioEndurance` | Cardio sessions, calendar dots, chips |
| `ModalityColors.resistanceLifting` | Strength sessions, calendar dots, chips |
| `ModalityColors.sports` | Sports sessions, calendar dots, chips |
| `ModalityColors.isometricStretching` | Isometric sessions, calendar dots, chips |
| `ModalityColors.freeTraining` | Free Training / fallback |

**Helper methods**:
- `ModalityColors.forModality(String? modality)` — returns accent for a modality key; null → `freeTraining`
- `ModalityColors.forSummaryGroupLabel(String groupKey)` — returns accent for a session summary group key (`'strength'`, `'cardio'`, `'rounds'`, `'isometric'`)

`ModalityColorUtils.colorForModality(String? modality)` (in `lib/core/utils/modality_color_utils.dart`) is a thin wrapper around `ModalityColors.forModality` kept for backward compatibility.

---

## Design Tokens

**File**: `lib/core/constants/omni_theme.dart`

See [Design System](design_system.md) for the full token reference. Key categories:
- Colors (gradients, surfaces, accents, text)
- Typography (letter spacing, font weights)
- Spacing (border radius, padding, touch targets)
- Animation (press scale, durations, curves)
- Shadows (deep shadow, glow shadow)
- Button dimensions (primary height, utility radius, icon size)
- Large-screen content column (`kColumnMaxWidth`,
  `kColumnMinActivationWidth`) — see the
  [Design System](design_system.md) "Large-screen content column"
  rule. Used by `OmniGradientBackground` to cap the content
  column on tablets and large unfolded foldables.

---

## Versioning & Water Constants

> **Added 2026-07-26 (docs audit).** These three constants files exist in
> `lib/core/constants/` but had no entry in this reference.

### `water_constants.dart`

| Constant | Value | Notes |
|----------|-------|-------|
| `kWaterGlassMl` | `250` | Milliliters per logged glass |

Water has **no goal** — like macros and sodium it is tracked for the historical
record only. The day's stored **volume in ml** is the source of truth; the
on-screen glass count is derived at the display boundary
(`volumeMl ~/ kWaterGlassMl`). Never hardcode `250` — go through the constant
so storage, unit, and widget agree.

### `catalog_version.dart`

| Constant | Value | Notes |
|----------|-------|-------|
| `bundledCatalogVersion` | `3` | Content version of the bundled catalog (exercises, capability / muscle-group / equipment links, food catalog, demo routines) |

At app start the device compares its stored version against
`bundledCatalogVersion`; when the bundled version is newer,
`CatalogRefreshService` writes new / changed entries in place. **Bumping this
integer by 1 is the only step required for a catalog change to reach existing
users.** Versions are monotonically increasing integers; there is no
cross-version schema compatibility story, because the refresh always reads the
bundled catalog directly.

`SeedEntryType` (same file) holds the stable entity-type strings used in
seed-entry tombstone markers — `exercise`, `food_catalog`, `routine_template` —
stored under the meta-box key `seed_entry_touched_<entityType>_<id>`. These
strings persist across app upgrades; keep them stable.

### `data_version.dart`

| Constant | Value | Notes |
|----------|-------|-------|
| `currentDataVersion` | `14` | Version a device reaches once the last consolidated migration step has run |

Replaces the former ~13 independent one-time `bool`-gated steps with a single
ordered sequence tracked by the device's `data_version` integer. Steps are
appended in order and gated by a version check; each must remain idempotent. A
failing step does **not** advance the version past itself, so the next launch
retries from there. To ship a new data change, append a `DataMigrationStep` to
`HiveWorkoutRepository._dataMigrationSteps` (and the Mock mirror) and bump
`currentDataVersion`.

`DataMigrationStep` is the step interface: `targetVersion` (version the device
lands at after `run()`), `name` (diagnostics), and `run()`.

Catalog content versioning is explicitly **out of scope** for this file — see
`catalog_version.dart` above.

See [DB Integration](db_integration.md) for how both versioning mechanisms run
at startup.

---

## Related Documentation


- [Design System](design_system.md) — Visual design tokens and rules
- [Modality Tracking](modality_tracking.md) — How constants drive the modality system
- [Exercise Ranking](exercise_ranking.md) — How ModalityConfig drives exercise scoring

---

**Document Version**: 1.1
**Last Updated**: July 26, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
