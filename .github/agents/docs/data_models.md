# Data Models Reference

## Overview

All domain models live in `lib/data/models/models.dart` as pure Dart classes (no Flutter imports). Models follow these conventions:
- Immutable fields (`final`)
- `fromMap()` factory constructor for deserialization
- `toMap()` method for serialization
- No business logic (logic lives in state classes or extensions)

---

## Core Session Models

These models represent the runtime workout tracking hierarchy:

```
TrainingSession
 └─ SessionSegment
     └─ SegmentEffort (one per exercise in the segment)
         ├─ EffortObservation (for set/timed/drill efforts)
         └─ RoundInstance (for round efforts only)
```

### TrainingSession

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `title` | `String?` | Session name (e.g., "Morning Lift") |
| `modality` | `String?` | e.g., `cardio_endurance`, `resistance_lifting`, `null` (Free Training) |
| `intent` | `String?` | Session purpose: `routine`, or intent constants like `strength`, `hypertrophy` |
| `startedAtMs` | `int` | Epoch milliseconds when session began |
| `endedAtMs` | `int?` | Epoch ms when session ended (`null` while active) |
| `note` | `String?` | User-added session note |
| `routineTemplateId` | `String?` | Links to source `WorkoutTemplate` if started from a routine |
| `sessionFeeling` | `int?` | Optional 1-5 post-session feeling score |
| `qualityRating` | `int?` | Reserved nullable quality field |
| `isRolling` | `bool` | Marks the session as using the rolling/continuous format. Exercises are grouped into named time-stamped segment blocks; session duration display is suppressed. Defaults to `false`. |

Active session persistence semantics:
- A session is considered in-progress when `endedAtMs == null`.
- Cold-start resume flow reads these in-progress rows and surfaces only the most recent session.
- No model changes were required for resume behavior.

### SessionSegment

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `sessionId` | `String` | Parent session |
| `segmentType` | `String` | Block type (e.g., `mixed`) |
| `orderIndex` | `int` | Display ordering |

### SessionBlock

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `sessionId` | `String` | Parent session |
| `name` | `String` | User-facing block label |
| `orderIndex` | `int` | Legacy block ordering field (kept for compatibility) |
| `topLevelOrderIndex` | `int?` | Canonical top-level active-session order (shared with standalone efforts) |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last update timestamp |

### SegmentEffort

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `segmentId` | `String` | Parent segment |
| `exerciseId` | `String?` | References `Exercise` |
| `effortKind` | `String` | `set`, `timed`, `round`, or `drill` |
| `modality` | `String?` | Optional modality context |
| `orderIndex` | `int` | Display ordering |
| `topLevelOrderIndex` | `int?` | Canonical top-level order for standalone efforts; aligns block members to their block's top-level slot |
| `blockOrderIndex` | `int?` | Canonical local order inside a block; null for standalone efforts |
| `note` | `String?` | Per-exercise note |

Ordering contract:
- Top-level active-session order is persisted via `SessionBlock.topLevelOrderIndex` and `SegmentEffort.topLevelOrderIndex`.
- Intra-block order is persisted via `SegmentEffort.blockOrderIndex`.
- `createdAtMs` is a tie-breaker only, never the primary ordering source.

### EffortObservation

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `effortId` | `String` | Parent effort |
| `metricId` | `String` | e.g., `metric-reps`, `metric-weight`, `metric-duration` |
| `entryIndex` | `int` | Which set/interval (0-based) |
| `valueReal` | `double?` | Decimal value (weight, distance) |
| `valueInt` | `int?` | Integer value (reps, duration seconds) |
| `valueText` | `String?` | Text value |
| `unitId` | `String?` | Unit reference (e.g., `unit-kg`) |
| `recordedAtMs` | `int` | Timestamp |
| `rpeRating` | `int?` | Optional RPE 1-10 value for richer observation payloads |
| `restDurationMs` | `int?` | Legacy field — superseded by `EntryRest` for all effort kinds; currently unpopulated |
| `valueBool` | `bool?` | Skip marker: `true` when set was explicitly skipped (with `valueInt: 0`); used by `_isSetLogged` to restore skip state on reload |

**Observation Layout by Effort Kind:**

Observations are persisted one-per-entry and grouped by effort kind:

- **`set` effort**: 2 observations per entry
  - `metric-reps` (valueInt)
  - `metric-weight` (valueReal)
  
- **`timed` effort**: 2 observations per entry
  - `metric-distance` (valueReal)
  - `metric-extra-weight` (valueReal) — enables loaded carries and weighted cardio (negative = band assist, positive = added load)
  
  > **Backward Compatibility Note**: Pre-existing timed entries (created before March 2026) contain only `metric-distance`. New entries always include both. The UI uses a guard pattern (`if (entryData['extra-weight'] != null)`) to show the extra-weight editor only for entries that have the observation.
  
- **`drill` effort**: 1 observation per entry
  - `metric-extra-weight` (valueReal) — for isometric holds with additional load
  
- **`round` effort**: Does NOT use observations; uses `RoundInstance` records instead

### RoundInstance

| Field | Type | Description |
|-------|------|-------------|
| `effortId` | `String` | Parent effort |
| `roundIndex` | `int` | 0-based position (ordering) |
| `plannedDurationSecs` | `int` | Target round length (default: 180) |
| `actualDurationSecs` | `int` | How long round actually ran (capped) |
| `state` | `RoundState` | Current lifecycle state |
| `startedAtMs` | `int` | Wall-clock epoch ms when started (0 = not started) |
| `pausedAtMs` | `int?` | Epoch ms of most recent pause |
| `totalPausedDurationMs` | `int` | Cumulative pause time |
| `finishedAtMs` | `int` | Epoch ms when round ended (0 = not finished) |
| `completed` | `bool` | `true` only when ended via natural countdown |

**Computed getters:**
- `elapsedMs` — derived from timestamps; 0 for notStarted; frozen when paused
- `remainingMs` — `(plannedDurationSecs * 1000 - elapsedMs).clamp(0, planned)`

**RoundState enum:** `notStarted` → `active` ⇄ `paused` → `finished` (terminal)

### EntryRest

Wall-clock-persisted rest record created when a set/round is logged. Tracks recovery time between entries for any effort kind. See [Rest Tracking](rest_tracking.md) for full architecture.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Deterministic key: `'rest-{effortId}-{entryIndex}'` |
| `effortId` | `String` | Parent `SegmentEffort` id |
| `entryIndex` | `int` | 0-based; identifies the set/round this rest precedes |
| `restStartMs` | `int` | Wall-clock epoch ms when the previous set was logged |
| `restEndMs` | `int?` | Wall-clock epoch ms when the next set/round was started; `null` while still resting |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last modified timestamp |

**Computed helper:**
- `elapsedSeconds(int nowMs)` — `((restEndMs ?? nowMs) - restStartMs) / 1000`, clamped to `[0, 99999]`

### Exercise

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Display name |
| `modality` | `String?` | Exercise modality key: `cardio_endurance`, `resistance_lifting`, `isometric_stretching`, `sports`; nullable for pre-feature legacy/custom exercises |
| `description` | `String?` | Optional description |
| `disciplineId` | `String?` | FK to `Discipline` |
| `isCustom` | `bool` | User-created vs seed data |
| `isArchived` | `bool` | Soft-delete flag |
| `capabilities` | `List<String>` | Capability flags (populated at query time, not stored on model) |
| `relevanceScore` | `double?` | Transient field for ranked sorting |

**Extension methods** (in `lib/core/utils/exercise_helpers.dart`):
- `supports(String capability)` — single capability check
- `supportsAny(List<String>)` — any-of check
- `copyWith({...})` — full copy constructor including `relevanceScore` and nullable `modality` (sentinel-backed)

### Discipline

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | e.g., "Running", "Boxing" |
| `categoryId` | `String?` | FK to `SportCategory` |

### SportCategory

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | e.g., `category-cardio`, `category-sports` |
| `name` | `String` | Display name |

### MuscleGroup

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | e.g., "Quads", "Chest" |
| `bodyRegion` | `String?` | Grouping (upper/lower/core) |

### Equipment

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | e.g., "Barbell", "Dumbbell" |

### Tag

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Freeform tag |

### ExerciseAlias

| Field | Type | Description |
|-------|------|-------------|
| `exerciseId` | `String` | FK to Exercise |
| `alias` | `String` | Alternative name for search matching |

---

## Measurement Models

### UserProfile

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Profile id (`local-user` for current single-user flow) |
| `displayName` | `String?` | Optional display name |
| `avatarPath` | `String?` | Native-first local file path for avatar |
| `createdAtMs` | `int` | Creation timestamp |

### BodyMeasurementEntry

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Entry UUID |
| `measurementType` | `String` | e.g., `bodyweight`, `height`, `body_fat_pct` |
| `value` | `double` | Numeric measurement value |
| `unitId` | `String` | Unit id (`unit-kg`, `unit-cm`, `unit-pct`) |
| `recordedAtMs` | `int` | Entry timestamp (save-time by default in current UI flow) |

### MetricDefinition

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | e.g., `metric-reps`, `metric-weight` |
| `key` | `String` | Stable metric key |
| `name` | `String` | Display name |
| `dataType` | `String` | `int`, `real`, `text` |
| `defaultUnitId` | `String?` | FK to `UnitModel` |
| `isCore` | `bool` | Whether metric is part of core tracking vocabulary |
| `appliesToEffortKind` | `String?` | Optional effort-kind hint |

### UnitModel

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | e.g., `unit-kg`, `unit-cm`, `unit-pct` |
| `key` | `String` | Stable short unit key (`kg`, `cm`, `pct`) |
| `name` | `String` | Display name |
| `unitType` | `String?` | Optional grouping (`weight`, `length`, `ratio`) |

### MetricApplicability

Junction model mapping which metrics apply to which effort kinds.

| Field | Type | Description |
|-------|------|-------------|
| `metricId` | `String` | FK to MetricDefinition |
| `effortKind` | `String` | `set`, `timed`, `round`, `drill` |
| `isRequired` | `bool` | Whether the metric is mandatory for this effort kind |
| `displayOrder` | `int` | Rendering order |

---

## Template Models

Used by the My Routines feature for reusable workout templates:

```
WorkoutTemplate (routine)
 └─ TemplateSegment
     └─ TemplateEffort (one per exercise)
         └─ TemplateTarget (one per metric per set)
```

### WorkoutTemplate

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `ownerUserId` | `String?` | Future: user ownership |
| `name` | `String` | Routine name (e.g., "Push Day") |
| `primaryDisciplineId` | `String?` | Optional discipline filter |
| `focusModality` | `String?` | Optional modality hint |
| `note` | `String?` | Optional notes |
| `createdAtMs` | `int` | Timestamp |
| `updatedAtMs` | `int` | Timestamp |

### TemplateSegment

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateId` | `String` | Parent template |
| `segmentType` | `String` | Usually `mixed` |
| `orderIndex` | `int` | Display ordering |

### TemplateEffort

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateSegmentId` | `String` | Parent segment |
| `orderIndex` | `int` | Display order (supports drag reordering) |
| `effortKind` | `String` | `set`, `timed`, `round`, or `drill` |
| `modality` | `String?` | Optional modality context |
| `exerciseId` | `String?` | FK to Exercise |
| `restSeconds` | `int?` | Rest duration between sets |
| `restType` | `String?` | Rest type classification |
| `note` | `String?` | Optional notes |
| `createdAtMs` | `int` | Timestamp |

### TemplateTarget

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateEffortId` | `String` | Parent effort |
| `metricId` | `String` | e.g., `metric-reps`, `metric-weight` |
| `setIndex` | `int?` | Which set (0-based) |
| `unitId` | `String?` | Optional unit |
| `targetMin` | `double?` | Used for weight values |
| `targetMax` | `double?` | Range targets (unused currently) |
| `targetInt` | `int?` | Used for reps, duration (seconds) |
| `targetText` | `String?` | Text-based targets (unused currently) |
| `createdAtMs` | `int` | Timestamp |

---

## Session Summary Models

Used by the post-workout summary screen (not persisted):

| Class | File | Purpose |
|-------|------|---------|
| `SessionSummary` | `lib/core/models/session_summary.dart` | Computed session stats |
| `SessionGroupMetrics` | same | Per-group summary card metrics (count + effort time or volume) |
| `ExerciseSummary` | same | Per-exercise stats |
| `PRAchievement` | same | New personal records |
| `GroupDelta` | same | Per-group comparison chip data vs previous session |
| `VolumeComparison` | same | Delta vs previous session |
| `SessionTemplateDraft` | same | Draft for save-as-routine |
| `SessionTemplateExercise` | same | Exercise entry in draft |
| `TemplateTargetDraft` | same | Target entry in draft |

Notable current `SessionSummary` fields consumed by UI include `totalRounds`, `totalRoundDurationMs`, `totalCardioDurationMs`, and `totalDrillDurationMs`.

See [Session Summary](session_summary.md) for details.

---

## Nutrition Models

### NutritionTarget

Represents the user's daily nutrition goals. Targets are stored per day and
roll over from the most recent ancestor day when no explicit entry exists
for the queried date (see [Daily targets persistence](db_integration.md#nutrition-targets-daily-rollover)).

| Field | Type | Description |
|---|---|---|
| `calories` | `double` (default `0.0`) | Daily calorie target. `0` means "no goal". |
| `protein` | `double` (default `0.0`) | Daily protein target in grams. `0` means "no goal". |
| `carbs` | `double` (default `0.0`) | Daily carbohydrate target in grams. `0` means "no goal". |
| `fat` | `double` (default `0.0`) | Daily fat target in grams. `0` means "no goal". |
| `dateMs` | `int?` | Start-of-day timestamp (ms since epoch, local midnight) that this target set belongs to. `null` for legacy single-row targets. |

Derived:

| Getter | Returns |
|---|---|
| `isUnset` | `true` when all four macros are `0.0` — UI uses this to render "no goal" / hide the row. |

Methods: `fromMap(Map)` and `toMap()` (use key `date_ms` for `dateMs`); `copyWith({calories, protein, carbs, fat, dateMs})` returns a new instance with overrides.

Round-trip notes:
- All four macros are non-nullable and default to `0.0`; never `null`.
- `0.0` is the canonical "no goal" sentinel — the UI hides the row and never attempts division-by-zero math against it.
- A target with `dateMs == null` indicates a legacy single-row save (kept for back-compat with `WorkoutRepository.getNutritionTarget()` / `saveNutritionTarget()`).

### FoodUnitType

Enum representing the unit system used for a food's reference amount.

| Value | Description |
|---|---|
| `count` | Discrete items (e.g., "per 1 egg", "per 1 slice") |
| `grams` | Weight-based (e.g., "per 100 g") |

Methods: `fromString(String?)` parses storage format (`'count'` or `'grams'`, defaults to `grams`); `toStorageString()` serializes to storage format.

### FoodGroup

User-created grouping category for foods (e.g., "Proteins", "Vegetables"). Foods with `groupId == null` render in a trailing "Ungrouped" section.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | UUID |
| `name` | `String` | Group display name |
| `color` | `String?` | Optional hex color (e.g., "#FF5722") |
| `isArchived` | `bool` | Soft-delete flag |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last update timestamp |

Methods: `fromMap(Map)`, `toMap()`, `copyWith()`.

### Food

A food item with macronutrient metadata. Foods exist in two collections:
- **Catalog** (`isCatalog == true`): the **global managed library** of foods. Mutated at runtime — the user can edit any catalog food (row tap in the **Library** tab of `AddFoodScreen`) and create new catalog foods (**+ New Item** tab). The bundled seed (`FoodCatalogSeed` / `assets/data/food_catalog.json`) is loaded once on first install and is then mutable.
- **Library** (`isCatalog == false`): user-owned foods, the personal logging library. Catalog copies land here via the **Add** button on a catalog row.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | UUID |
| `name` | `String` | Food display name |
| `groupId` | `String?` | Optional `FoodGroup.id`, null = Ungrouped |
| `unitType` | `FoodUnitType` | `count` or `grams` |
| `referenceAmount` | `double` | Quantity the macros are expressed per (e.g., 100.0 for "per 100 g") |
| `referenceLabel` | `String` | Display unit (e.g., "g", "egg", "tbsp") |
| `isCatalog` | `bool` | `true` = bundled catalog, `false` = user library |
| `protein` | `double` | Grams of protein per reference amount. `double` (S-001 — see [food-form-decimals-and-autofocus-plan.md](../plans/food-form-decimals-and-autofocus-plan.md)) so the food form can persist fractional grams like `0.5`. Display sites that want whole-gram rendering go through `formatGrams()` in `lib/core/utils/food_helpers.dart`. |
| `carbs` | `double` | Grams of carbs per reference amount. `double` for the same fractional-gram reason as `protein`. |
| `fiber` | `double?` | Optional grams of fiber. `double` for parity. |
| `fat` | `double` | Grams of fat per reference amount. `double` for the same reason as `protein` — the v1.5 form lets the user type `0.5` g of fat. |
| `sodium` | `double?` | Optional milligrams of sodium. `double` for parity. |
| `isArchived` | `bool` | Soft-delete flag |
| `notes` | `String?` | **Info** — optional free-form user notes. **Not** used to carry the catalog's category label; the category is stored on `groupId` instead. Catalog rows are seeded with `notes = null`; user-typed notes live on library rows. |
| `imagePath` | `String?` | Optional native-first local file path to a food photo. Mirrors the `UserProfile.avatarPath` contract: the path is opaque to the repository and only the OS / user can keep the file alive. Web has no persistent file API, so the picker is a no-op there and the field stays `null`. Legacy rows (pre-image) deserialize to `null`. |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last update timestamp |

Derived getters:
- `calories`: computed as `(protein * 4 + carbs * 4 + fat * 9).round()` — the macro math is now `double`-precision (so `0.5 g` of fat survives storage), then rounded to `int` at the display boundary because the calorie UI shows whole kcal.
- `netCarbs`: computed as `(carbs - (fiber ?? 0)).round()` — same display-boundary rationale.
- `isCatalogFood`: `true` when `isCatalog == true`
- `isLibraryFood`: `true` when `isCatalog == false`

Legacy compatibility: `servingSize` and `servingUnit` are deprecated getters that return `referenceAmount.round()` and `referenceLabel` respectively. `Food.fromMap()` falls back to these legacy fields for rows that lack the new fields.

Methods: `fromMap(Map)`, `toMap()`, `copyWith()`.

> **Note:** `copyWith()` uses a private sentinel for the two nullable fields — `groupId` and `imagePath` — so callers can clear them (`copyWith(groupId: null)` / `copyWith(imagePath: null)`) without losing the previous value. This is what the Categories tab's group-reassignment path relies on when it moves foods to "Ungrouped" (`groupId = null`), and what the Edit Food screen relies on when the user clears the image tile (`imagePath = null`). The file on disk is left intact in both cases — it is the user's responsibility.

#### Catalog `category` → `groupId` resolution

Catalog rows in `assets/data/food_catalog.json` carry a human-readable
`category` string ("Proteins", "Dairy", …). At load time
(`FoodCatalogLoader._categoryToGroupId`) the category is resolved to
the matching `FoodGroup.id` from `SeedData.defaultFoodGroups`
(case-insensitive). The result is written to `groupId`; the JSON
`category` is **not** stored in `notes`.

- Resolved group ids: `food-group-proteins`, `food-group-dairy`,
  `food-group-grains-starches`, `food-group-fruits`,
  `food-group-vegetables`, `food-group-nuts-seeds-fats`,
  `food-group-snacks-prepared`, `food-group-drinks`,
  `food-group-condiments`.
- Unknown categories (added after the seed map is updated) fall
  through to `groupId = null` (Ungrouped).
- The same lookup is mirrored in
  `scripts/generate_food_catalog_seed.dart` so the hardcoded
  `FoodCatalogSeed.sampleCatalogFoods` list stays in lockstep with
  the JSON.
- Pre-existing installs (with `notes: 'Proteins'` etc. and
  `group_id = NULL`) are backfilled by the Hive one-shot migration
  `food_category_groupid_migrated_v1` — see `db_integration.md` for
  details and the equivalent SQL block in `scripts/sqlite_schema.sql`
  for the future SQLite importer.

### ConsumedFood

A frozen snapshot of a logged food for a specific day. Stores complete state at log time to ensure historical accuracy even if the source food or targets are later edited or deleted.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | UUID |
| `loggedAtMs` | `int` | Wall-clock timestamp when logged |
| `dateMs` | `int` | Day key (local midnight ms) this entry counts toward |
| `sourceFoodId` | `String?` | Original `Food.id` at log time (nullable if food was deleted) |
| `name` | `String` | **FROZEN** food name |
| `unitType` | `FoodUnitType` | **FROZEN** unit type |
| `referenceAmount` | `double` | **FROZEN** reference amount |
| `referenceLabel` | `String` | **FROZEN** reference label |
| `protein` | `double` | **FROZEN** protein per reference. `double` so the log-time snapshot can capture fractional grams like `0.5` (S-001). |
| `carbs` | `double` | **FROZEN** carbs per reference. `double` for parity. |
| `fiber` | `double?` | **FROZEN** fiber (nullable). `double` for parity. |
| `fat` | `double` | **FROZEN** fat per reference. `double` for parity. |
| `sodium` | `double?` | **FROZEN** sodium (nullable). `double` for parity. |
| `amountConsumed` | `double` | Amount consumed in the food's own unit (g for grams-type foods, count for count-type foods) |
| `groupIdSnapshot` | `String?` | **FROZEN** group ID |
| `groupNameSnapshot` | `String?` | **FROZEN** group name |
| `targetCalories` | `double` | **FROZEN** daily calorie target |
| `targetProtein` | `double` | **FROZEN** daily protein target |
| `targetCarbs` | `double` | **FROZEN** daily carbs target |
| `targetFat` | `double` | **FROZEN** daily fat target |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last update timestamp |

Derived getters:
- `caloriesConsumed`: computed as
  `(protein * 4 + carbs * 4 + fat * 9) * (amountConsumed / referenceAmount)`,
  then rounded to an int. The macros on the snapshot are stored
  per the food's reference, so the scaling factor is
  `amountConsumed / referenceAmount`. Examples:
  - 150 g of a per-100 g food (31P / 0C / 3F = 151 kcal):
    `151 * (150 / 100) = 226.5` → 226 or 227 depending on rounding.
  - 3 of a per-1-egg food (6P / 1C / 5F = 73 kcal):
    `73 * (3 / 1) = 219`.

Methods: `fromMap(Map)`, `toMap()`, `copyWith()`.

---

## Consumed-Food State Cache (`NutritionState`)

`NutritionState` (`lib/state/nutrition_state.dart`) caches today's
consumed-food snapshots in memory so the calorie ring on the nutrition
page can rebuild without re-querying the repository on every keystroke.
The cache is single-day (local-time) and is cleared on day rollover.

| Field / method | Type | Description |
|---|---|---|
| `consumedToday` | `List<ConsumedFood>` | Unmodifiable view of today's snapshots. Empty until first load. |
| `todayConsumedCalories` | `int` | Sum of `ConsumedFood.caloriesConsumed` over `consumedToday`. Pure / derived; 0 when the cache is empty. |
| `todayConsumedProtein` | `int` | Sum of `protein * amountConsumed / referenceAmount` over `consumedToday`, accumulated as a `double` and rounded **once at the end**. Matches the `caloriesConsumed` rounding contract and avoids per-row rounding drift on fractional servings. |
| `todayConsumedCarbs` | `int` | Same shape as `todayConsumedProtein`, for carbs. |
| `todayConsumedFiber` | `int` | Same shape as `todayConsumedProtein`, for fiber. `ConsumedFood.fiber` is `int?`; `null` is treated as 0. |
| `todayConsumedFat` | `int` | Same shape as `todayConsumedProtein`, for fat. |
| `consumedTodaySorted` | `List<ConsumedFood>` | `consumedToday` sorted by `loggedAtMs` ascending. New list; the cache stays in insertion order. |
| `loadConsumedToday()` | `Future<void>` | Reloads today's snapshots from the repository, replaces the cache, and notifies listeners. Idempotent; safe to call repeatedly. |
| `getTodayConsumedFoods()` | `Future<List<ConsumedFood>>` | Convenience wrapper that does the same load and returns the resulting list. |
| `refreshConsumedToday()` | `Future<List<ConsumedFood>>` | Sugar for `loadConsumedToday()` that returns the resulting list. |
| `logConsumedFood(food, amount)` | `Future<String?>` | Builds a frozen `ConsumedFood` snapshot from the source food plus the cached daily target, persists it via the repository, and appends it to the cache so the ring updates immediately. Returns the new id, or `null` on persistence failure. Validates `amount > 0`. |
| `logConsumedFoodAt(food, amount)` | `Future<String?>` | Day-uniqueness variant: if a row for `(sourceFoodId, today)` already exists, updates its `amountConsumed` in place; otherwise delegates to `logConsumedFood`. Used by the per-row checkbox + amount-input UI on the food library card. Returns the row id, or `null` on invalid amount or persistence failure. |
| `unlogFoodToday(foodId)` | `Future<bool>` | Removes the day-log row for `foodId` (today). Returns `true` if a row was removed, `false` otherwise. |
| `findLoggedTodayForFood(foodId)` | `ConsumedFood?` | Cache-only lookup of the day's row for `foodId`. Returns `null` when not logged today. |
| `isFoodLoggedToday(foodId)` | `bool` | True when a day-log row exists for `foodId`. Drives the row's checkbox `value:` binding. |
| `deleteConsumedFood(id)` | `Future<bool>` | Removes a consumed-food row and refreshes the cache. No-op (and returns `false`) if the id is not in the cache. |
| `clearConsumedToday()` | `void` | Empties the cache and notifies listeners. Intended for day-rollover. |

Derived calorie math (`(protein*4 + carbs*4 + fat*9) * (amountConsumed / referenceAmount)`,
rounded) lives on `ConsumedFood` and is unchanged at the field level; no new
fields were added to the model, this section documents state-side caching only.

### WaterLogEntry

One row per calendar day, keyed by `dateMs` (local midnight). The day's water volume is stored as a real volume in milliliters so the historical record stays unit-clean — the on-screen glass count is derived at the display boundary (`volumeMl ~/ kWaterGlassMl`), not stored.

Water has no goal — like macros and sodium, it is tracked and stored for the historical record only. Each new day starts at 0; logging takes effect immediately and survives closing and reopening the app on the same day. Prior days are never modified automatically.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Deterministic storage key (`'water-<dateMs>'`), derived via `WaterLogEntry.idForDate(dateMs)`. |
| `dateMs` | `int` | Day key (local midnight ms) this row counts toward. |
| `volumeMl` | `int` | Stored volume in milliliters. Always `>= 0` (state layer floors at 0). |
| `createdAtMs` | `int` | First-write timestamp. |
| `updatedAtMs` | `int` | Last-write timestamp. Advances on every increment / decrement. |

Methods: `fromMap(Map)`, `toMap()`, `copyWith()`, and the static helper `WaterLogEntry.idForDate(int dateMs)`.

### Daily Water State Cache (`NutritionState`)

`NutritionState` caches the active day's water volume in memory so the bottom-right stepper on the calorie-ring card can rebuild without re-querying the repository on every tap. The cache is single-day (local-time) and is cleared on day rollover.

| Field / method | Type | Description |
|---|---|---|
| `waterTodayMl` | `int` | Cached volume in milliliters for the most recently loaded day. `0` until the first explicit load. |
| `waterTodayGlasses` | `int` | Derived from `waterTodayMl ~/ kWaterGlassMl`. The displayed count is never a volume figure — the icon + `250 ml` annotation carries the unit. |
| `loadWaterForDate(dateMs)` | `Future<void>` | Reloads the day's stored ml from the repository, updates the cache, and notifies listeners. Idempotent. |
| `loadWaterForToday()` | `Future<void>` | Convenience wrapper that delegates to `loadWaterForDate(todayMidnightMs)`. Called from `NutritionScreen.initState` alongside the target + consumed loads. |
| `incrementWaterForDate(dateMs)` | `Future<void>` | Adds `kWaterGlassMl` (250 ml), persists, updates the cache, notifies. |
| `decrementWaterForDate(dateMs)` | `Future<void>` | Subtracts `kWaterGlassMl` (floors at 0 ml), persists, updates the cache, notifies. A minus at 0 is a no-op (no write, no notification, no spurious row). |

Day rollover (`rolloverToDate(dateMs)`) clears the water cache (`_waterTodayMl = 0`) and reloads it for the new day via `loadWaterForDate(dateMs)`. Prior dates' stored ml are untouched — only the in-memory cache is cleared.

The canonical per-glass amount lives in `kWaterGlassMl` (`lib/core/constants/water_constants.dart`); the model never hard-codes `250` so a future per-glass change propagates to the widget, the state, and the storage layer in lockstep.

---

## Relationship Diagram

```
SportCategory ←── Discipline ←── Exercise ──→ MuscleGroup (junction)
                                    │          Exercise ──→ Equipment (junction)
                                    │          Exercise ──→ Tag (junction)
                                    │          Exercise ──→ ExerciseAlias
                                    │          Exercise ──→ Capability (junction table)
                                    ↓
TrainingSession → SessionSegment → SegmentEffort → EffortObservation
                                       │            → RoundInstance (round efforts only)
                                       └──→ Exercise (FK)

UserProfile → BodyMeasurementEntry

WorkoutTemplate → TemplateSegment → TemplateEffort → TemplateTarget
                                       └──→ Exercise (FK)

MetricDefinition ←── UnitModel
       └──→ MetricApplicability (junction to effort kinds)
```

---

## Code References

| Concern | File |
|---------|------|
| All domain models | `lib/data/models/models.dart` |
| Session summary models | `lib/core/models/session_summary.dart` |
| Routine manifest models | `lib/core/models/routine_session_manifest.dart` |
| Exercise extensions | `lib/core/utils/exercise_helpers.dart` |
| SQLite schema | `scripts/sqlite_schema.sql` |

---

## Related Documentation

- [My Routines](my_routines.md) — Template model usage
- [Modality Tracking](modality_tracking.md) — Session/effort creation flow
- [DB Integration](db_integration.md) — Database schema and persistence

---

**Document Version**: 1.4
**Last Updated**: June 5, 2026
