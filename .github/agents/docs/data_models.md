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

Active session persistence semantics:
- A session is considered in-progress when `endedAtMs == null`.
- Cold-start resume flow reads these in-progress rows and surfaces only the most recent session.
- No model changes were required for resume behavior.

Models with no behaviour beyond their fields: SessionSegment, SessionBlock.

### SegmentEffort

> **Corrected 2026-07-26 (docs audit).** `modality` was listed as a field but
> does not exist on `SegmentEffort` (nor as a column on
> `app_segment_effort`). Modality context lives on the parent
> `TrainingSession`. `blockId`, `createdAtMs`, and `updatedAtMs` were missing
> and have been added.

Ordering contract:
- Top-level active-session order is persisted via `SessionBlock.topLevelOrderIndex` and `SegmentEffort.topLevelOrderIndex`.
- Intra-block order is persisted via `SegmentEffort.blockOrderIndex`.
- `createdAtMs` is a tie-breaker only, never the primary ordering source.

### EffortObservation

> **Corrected 2026-07-26 (docs audit).** This table previously listed two
> fields that do not exist on the model or in the schema:
>
> - **`entryIndex`** — there is no such field and no `entry_index` column on
>   `app_effort_observation`. The set/interval index is encoded in the
>   observation **id**, which is built as
>   `'obs-{effortId}-{entryIndex}-{metricSuffix}'` (see
>   `lib/state/workout/session_core_entry.dart`) and parsed back out with
>   `RegExp(r'obs-.+-(\d+)-[^-]+$')`. Code that needs the index must go
>   through that id convention.
> - **`recordedAtMs`** — the model carries `createdAtMs` / `updatedAtMs`
>   instead, matching the schema.
>
> Both the Dart model and `scripts/sqlite_schema.sql` agree on the corrected
> shape above.

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

**Computed getters:**
- `elapsedMs` — derived from timestamps; 0 for notStarted; frozen when paused
- `remainingMs` — `(plannedDurationSecs * 1000 - elapsedMs).clamp(0, planned)`

**RoundState enum:** `notStarted` → `active` ⇄ `paused` → `finished` (terminal)

### EntryRest

Wall-clock-persisted rest record created when a set/round is logged. Tracks recovery time between entries for any effort kind. See [Rest Tracking](rest_tracking.md) for full architecture.

**Computed helper:**
- `elapsedSeconds(int nowMs)` — `((effectiveEndMs - restStartMs - restPausedDurationMs) / 1000).round()`, clamped to `[0, 99999]`. `effectiveEndMs` is `restEndMs` if closed, otherwise `restPausedAtMs` while paused or `nowMs` while running.

### TimedInstance

> **Added 2026-07-26 (docs audit).** This model was entirely absent from this
> document despite being live, persisted, and the sole owner of duration for
> two of the four effort kinds.

The timed counterpart to `RoundInstance`. One record per timed entry within a
`timed` or `drill` effort (`effortKind == 'timed' || effortKind == 'drill'`).
It **replaces the old duration `EffortObservation`** for these effort kinds —
companion metrics (distance for timed, extra weight for drill) remain as
`EffortObservation` rows. SQLite table: `app_timed_instance`.

**Computed helper:**
- `elapsedMs` — `now - startedAtMs - totalPausedDurationMs`. Always derived
  from wall-clock timestamps, never inferred from a stored duration, so the
  value survives backgrounding and reload.

**TimedState enum:** `notStarted` → `active` ⇄ `paused` → `finished` (terminal).
Partial entries are never discarded — session close finishes any still-active
entry via the `_persistActiveTimedEntries` safety net.

### ExerciseNote

> **Added 2026-07-26 (docs audit).** Behavior is documented in
> [Exercise Info & Notes](exercise_info_and_notes.md); the model itself was
> missing here.

One persistent note per exercise, surviving across sessions. SQLite table:
`app_exercise_note`, with a unique index on `exercise_id` enforcing the
one-note-per-exercise rule.

### Exercise

> **Corrected 2026-07-26 (docs audit).** This table listed `isCustom`
> (`bool`, "user-created vs seed data"). **No such field exists** — not on
> `Exercise`, not anywhere in `lib/`, and not as a column on `app_exercise`.
> Six real fields were missing and have been added above.
>
> ⚠️ **Unresolved:** the *intent* behind `isCustom` has no clean replacement.
> `ownerUserId` is the closest thing — `ExerciseLibrary.createExercise` stamps
> `'user-1'` on user-created exercises and the seed catalog does not set it —
> but **no code anywhere reads `ownerUserId` to branch on custom-vs-seed**
> (there is no `ownerUserId == null` / `!= null` check in `lib/`). So there is
> currently no supported way to ask "is this a custom exercise?". Do not
> introduce one on the assumption that `ownerUserId` is a reliable
> discriminator for pre-existing rows without checking migration history
> first.
>
> **2026-07-27 downstream boundary:** PR 7 needs reliable custom markers and PR 8
> needs custom-only filtering plus built-in immutability. Those plans may require
> a durable ownership migration; nullable `ownerUserId` is not yet that contract.

> **PR 7 (shipped):** `Exercise.isCustomExercise` (in
> `lib/core/utils/exercise_helpers.dart`) commits to
> `ownerUserId != null` as the canonical custom marker. The seed
> catalog leaves `ownerUserId` null on every bundled row and
> `ExerciseLibrary.createExercise` stamps `'user-1'` on every
> user-created row, so the value-as-stored is consistent on both
> sides. UI surfaces that need the marker MUST go through this
> getter; reading `ownerUserId` directly is a code-review warning.

> **PR 8 (shipped):** adds the reference-aware removal contract
> via `isArchived`. `ExerciseLibraryService.removeExercise(exercise)`
> branches on `isExerciseReferenced(exercise.id)`:
> - zero references in `app_segment_effort.exercise_id` AND
>   `app_template_effort.exercise_id` → hard-delete via
>   `WorkoutRepository.deleteExercise`.
> - any reference → soft-retire via `isArchived = true`; the row
>   stays resolvable by id (history keeps rendering) but is
>   excluded from `getExercises()` and `getExercisesRankedForModality()`.
>
> Built-in exercises (where `isCustomExercise == false`) reject
> mutation with `BuiltInExerciseImmutableError` at the service
> layer; the library UI also gates Copy/Edit/Remove on
> `isCustomExercise`.

**Extension methods** (in `lib/core/utils/exercise_helpers.dart`):
- `isCustomExercise` — `ownerUserId != null`; the canonical custom marker.
- `supports(String capability)` — single capability check
- `supportsAny(List<String>)` — any-of check
- `copyWith({...})` — full copy constructor including `relevanceScore` and nullable `modality` (sentinel-backed)

Models with no behaviour beyond their fields: Discipline, SportCategory.

### MuscleGroup

> **Corrected 2026-07-26 (docs audit).** `bodyRegion` was listed but does not
> exist on the model or as a column on `app_muscle_group`. `createdAtMs` was
> missing.

Models with no behaviour beyond their fields: Equipment, Tag, ExerciseAlias.

---

## Calendar & Period Models

> **Added 2026-07-26 (docs audit).** Both models were absent from this
> document. Their product behavior is described in
> [Calendar & Periods](calendar_periods.md); this section covers the shapes.

### PlannedSession

A session the user has scheduled on the calendar but has not necessarily
performed. SQLite table: `app_planned_session`.

### TrainingPeriod

A named, non-overlapping block of training days (e.g. "Off-Season Strength
Block"). Drives the calendar's period banding and the Stats screen's
"current-state window". Managed by `PeriodState`; SQLite table:
`app_training_period`.

Overlap between periods is rejected at the state layer by
`PeriodState.validate`, which returns an `overlapError` rather than throwing.

---

## Measurement Models

Models with no behaviour beyond their fields: UserProfile, BodyMeasurementEntry, MetricDefinition, UnitModel.

### MetricApplicability

Junction model mapping which metrics apply to which effort kinds.

> **Corrected 2026-07-26 (docs audit).** `isRequired` and `displayOrder` were
> listed but exist on neither the model nor `app_metric_applicability` — the
> junction is a bare `(metric_id, effort_kind)` composite key. Requiredness and
> ordering are driven by `ModalityConfig` / `MetricIds`, not by this table.

---

## Template Models

Used by the My Routines feature for reusable workout templates:

```
WorkoutTemplate (routine)
 └─ TemplateSegment
     └─ TemplateEffort (one per exercise)
         └─ TemplateTarget (one per metric per set)
```

Models with no behaviour beyond their fields: WorkoutTemplate, TemplateSegment, TemplateEffort, TemplateTarget.

---

## Session Summary Models

Used by the post-workout summary screen (not persisted):

| Class | File | Purpose | Status |
|-------|------|---------|--------|
| `SessionSummary` | `lib/core/models/session_summary.dart` | Computed session stats | **Active** — read by the summary screen |
| `SessionGroupMetrics` | same | Per-group summary card metrics (count + effort time or volume) | **Active** — drives the group cards |
| `ExerciseSummary` | same | Per-exercise stats | **Active** — used by the summary service. Carries `bestWeight` (volume stat), `bestE1RM` (weight-axis PR stat for loaded sets), and `bestReps` (reps-axis PR stat for bodyweight sets). `bestE1RM` and `bestReps` are populated only for `effortKind == 'set'` efforts; an exercise on the weight axis has a non-null `bestE1RM`, an exercise on the reps axis has a non-null `bestReps`, never both. See `.github/agents/plans/stats-summary-fix-pack-plan.md` Items 1 and 2. |
| `PRAchievement` | same | New personal records | **Active** — inline PR rows on the group cards. Weight-axis (Epley e1RM, `StatsProgressService.epley1RM`) and reps-axis (max reps in a single set, `StatsProgressService.getAllTimeBestReps`) variants both surface here, distinguished by `metricLabel` (`'e1RM'` or `'reps'`). One entry per exercise per session — duplicate rows from cloned blocks are collapsed. Shared source of truth with the in-workout toast and the Stats screen (`.github/agents/plans/stats-summary-fix-pack-plan.md` PR 1 + Item 2). |
| `GroupDelta` | same | Per-group comparison chip data vs previous session | **Active** — the per-group progress chip on each group card |
| `VolumeComparison` | same | Delta vs previous session | **Retained in model, not rendered.** The earlier standalone volume-comparison surface on the summary was removed; progress feedback now lives as per-group `GroupDelta` chips (see [Session Summary](session_summary.md)). The model class is preserved because the summary service still constructs one internally and tests pin the type. |
| `SessionTemplateDraft` | same | Draft for save-as-routine | **Active** — the "Save as Routine" flow |
| `SessionTemplateExercise` | same | Exercise entry in draft | **Active** — paired with the draft |
| `TemplateTargetDraft` | same | Target entry in draft | **Active** — paired with the draft |

Notable current `SessionSummary` fields consumed by UI include `totalRounds`, `totalRoundDurationMs`, `totalCardioDurationMs`, and `totalDrillDurationMs`.

See [Session Summary](session_summary.md) for details.

---

## Nutrition Models

### NutritionTarget

Represents the user's daily nutrition goals. Targets are stored per day and
roll over from the most recent ancestor day when no explicit entry exists
for the queried date (see [Daily targets persistence](db_integration.md#nutrition-targets-daily-rollover)).

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

User-created grouping category for foods (e.g., "Proteins", "Vegetables"). How a food's group decides its place in the Foods I Eat list is `foodsIEatSections` (`lib/core/utils/foods_i_eat_order.dart`) — never restated here, because the card, the sync payload and the watch all read that one function.

Methods: `fromMap(Map)`, `toMap()`, `copyWith()`.

### Food

A food item with macronutrient metadata. Foods exist in two collections:
- **Catalog** (`isCatalog == true`): the **global managed library** of foods. Mutated at runtime — the user can edit any catalog food (row tap in the **Library** tab of `AddFoodScreen`) and create new catalog foods (**+ New Item** tab). The bundled seed (`FoodCatalogSeed` / `assets/data/food_catalog.json`) is loaded once on first install and is then mutable.
- **Library** (`isCatalog == false`): user-owned foods, the personal logging library. Catalog copies land here via the **Add** button on a catalog row.

Derived getters:
- `calories`: computed as `(protein * 4 + carbs * 4 + fat * 9).round()` — the macro math is now `double`-precision (so `0.5 g` of fat survives storage), then rounded to `int` at the display boundary because the calorie UI shows whole kcal.
- `netCarbs`: computed as `(carbs - (fiber ?? 0)).round()` — same display-boundary rationale.
- `isCatalogFood`: `true` when `isCatalog == true`
- `isLibraryFood`: `true` when `isCatalog == false`

Legacy compatibility: `servingSize` and `servingUnit` are deprecated getters that return `referenceAmount.round()` and `referenceLabel` respectively. `Food.fromMap()` falls back to these legacy fields for rows that lack the new fields.

Methods: `fromMap(Map)`, `toMap()`, `copyWith()`.

> **Note:** `copyWith()` uses a private sentinel for the nullable fields — `groupId`, `imagePath`, and `lastAmountConsumed` — so callers can clear them (`copyWith(groupId: null)` / `copyWith(imagePath: null)` / `copyWith(lastAmountConsumed: null)`) without losing the previous value. This is what the Groups tab's group-reassignment path relies on when it moves foods to "Ungrouped" (`groupId = null`), what the Edit Food screen relies on when the user clears the image tile (`imagePath = null`), and what `NutritionState` relies on when it never writes `null` to `lastAmountConsumed` (the field is only ever set to a positive `double`, never cleared). The file on disk is left intact in all cases — it is the user's responsibility.

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
  details and the equivalent SQL contract block in
  `scripts/sqlite_schema.sql`.

### ConsumedFood

A frozen snapshot of a logged food for a specific day. Stores complete state at log time to ensure historical accuracy even if the source food or targets are later edited or deleted.

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

## Watch Capture Models

Covers `SensorSummary` and `WatchInboxEntry` in `lib/data/models/models.dart`,
stored through the watch-capture methods of `WorkoutRepository` (see
[DB Integration](db_integration.md#watch-capture-storage)). Decisions D-131 and
D-132 of `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`.

### SensorSummary

A heart-rate and step summary the wrist measured over one window of a wrist
session. It attaches to exactly one target, named by its scope: the
`TrainingSession` itself, a set block (`SegmentEffort`), a timed or hold entry
(`TimedInstance`), or a round (`RoundInstance`). Every summary also names the
session it belongs to, whatever its scope. The scope vocabulary is
`SensorSummary.scopes`.

Why it is its own model:
- **Not `metric-heart-rate` observations.** A summary is an average and
  maximum pair plus steps. An `EffortObservation` holds one value per metric
  per entry and cannot address a session or a `RoundInstance`. Summaries are
  measured, never entered, so they must never be read or edited as a manual
  metric; `metric-heart-rate` stays seeded and unused.
- **Not new columns on its targets.** `TrainingSession`, `TimedInstance` and
  `RoundInstance` rows are rebuilt field by field in several places (for
  example `endSession` and `updateSessionFeeling`), where a new field would be
  silently dropped.

Invariants:
- **Refused at construction.** The constructor throws `ArgumentError` for an
  unknown scope, a session summary aimed at another session, a heart-rate pair
  that is not both-or-neither, a zero average or one above the maximum,
  negative steps, steps outside a `timed_instance`, no measured value at all, a
  reversed window, or a source other than the watch. A missing reading is
  absence, never zero. Verified by `test/watch_capture_repository_parity_test.dart`
  (`D-131 refuses a zero heart rate, …`), against both repositories.
- **One per target, never rewritten.** The id derives from scope and target
  (`SensorSummary.idFor`) and `createSensorSummary` is put-if-absent
  (`D-131 stores put-if-absent by scope and target: …`).
- **Deleted with its target.** A repository delete removes the summaries of
  every row it deletes, and `deleteSession` removes all of the session's
  (the `D-131 delete… removes …` tests).

### WatchInboxEntry

One thing the phone learned about a wrist session before it became history:
a wrist event (origin `watch`), or one of the phone's own annotations on that
session (origin `phone`): its rating, and the live corrections and deletions
it sent for a wrist entry. The kind vocabularies are
`WatchInboxEntry.watchKinds` and `WatchInboxEntry.phoneKinds`. The phone mints
its annotation ids with `phoneRatingId` and `phoneChangeId`, so each is
staged at most once.

Why it exists: the wrist delivers a session's observations, rating and end in
any order, possibly more than once, and possibly across a phone restart.
Staging each on arrival lets the import into history be idempotent,
independent of arrival order, and durable.

Invariants:
- **Put-if-absent by entry id.** The first copy is the record; a redelivered
  or altered copy never replaces it (`D-132 stages put-if-absent: …`).
- **Applied once, never deleted.** A row keeps its first applied stamp
  (`D-132 marks rows applied in one batch; …`). Applied rows are the tombstones
  that keep history the user deleted from being re-created, so no history
  delete cascades into the inbox (`D-132 the inbox survives deleteSession: …`).
- **The payload is frozen.** The event is held as its JSON encoding; the map a
  caller reads is a fresh copy, and a payload that is not a JSON object is
  refused (`D-132 a staged payload is JSON, …`).
- **Kind follows origin.** A phone kind with origin `watch`, a wrist kind with
  origin `phone`, a kind outside both vocabularies, or a phone id not minted by
  the helpers is refused (`D-132 WatchInboxEntry refuses a kind outside …`).

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

SensorSummary ──→ TrainingSession (owner, every scope)
      └──→ one target: TrainingSession | SegmentEffort | TimedInstance | RoundInstance

WatchInboxEntry  (keyed by entry id; references no history row, never cascaded)
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

**Document Version**: 1.5
**Last Updated**: September 25, 2026

---

> **Doc freshness** — Last reconciled against source: 2026-07-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
