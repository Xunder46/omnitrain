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
`martial_arts`, `strength_resistance`, `skill_technique`, `conditioning_mixed`, `mobility_flexibility`, `recovery_rehab`, `competition_match`

> **Note**: `martial_arts` was unified under `sports` in Feb 2026. The constant remains for data compatibility.

### Category Mappings

- `modalityToCategoryId` — maps each primary modality to one `SportCategory` ID
  - `cardio_endurance` → `category-cardio`
  - `resistance_lifting` → `category-resistance`
  - `sports` → `category-martial-arts` (primary)
  - `isometric_stretching` → `category-isometric`

- `modalityToCategoryIds` — plural version for exercise ranking
  - `sports` maps to `['category-martial-arts', 'category-sports']` (unified coverage)

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
| `timed` | `'timed'` | Duration timer + distance |
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
| `extraWeight` | `'metric-extra-weight'` | drill (negative = band assist, positive = added load) |

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
| `timed` | 0 seconds duration |
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

## Home Tile Configuration

**File**: `lib/core/constants/home_tiles.dart`

Defines the 6-tile grid as `HomeTileConfig` objects:

| Key | Label | Modality | Gradient Colors |
|-----|-------|----------|----------------|
| `cardio` | Cardio / Endurance | `cardio_endurance` | Orange tones |
| `resistance` | Resistance / Lifting | `resistance_lifting` | Blue tones |
| `sports` | Sports | `sports` | Red tones |
| `isometric` | Isometric / Stretching | `isometric_stretching` | Green tones |
| `free_training` | Free Training | `null` | Purple tones |
| `my_routines` | My Routines | `null` (special) | Grey tones |

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

---

## Related Documentation

- [Design System](design_system.md) — Visual design tokens and rules
- [Modality Tracking](modality_tracking.md) — How constants drive the modality system
- [Exercise Ranking](exercise_ranking.md) — How ModalityConfig drives exercise scoring

---

**Document Version**: 1.0
**Last Updated**: February 28, 2026
