# Documentation Audit — 2026-07-26

A full audit of `.github/agents/docs/` against the `lib/` source tree.

**Scope:** documentation only. No application source file was modified. The
only non-doc file added is a test (`test/docs_indexing_contract_test.dart`).

**Method:** every claim below was checked against source — screen classes and
their `OmniNavigator` call sites, model field declarations in
`lib/data/models/models.dart` cross-checked against `scripts/sqlite_schema.sql`,
and file existence for every `lib/…` path named in the docs.

---

## 1. Contradictions — shipped features documented as out of scope

The most damaging category: an agent reading these would have refused or
deferred work that is already live.

| # | Document | Claim | Reality |
|---|----------|-------|---------|
| 1 | `app_philosophy.md` | **"Explicit Non-Goals (v1): … Nutrition tracking"** | Nutrition shipped: 4 screens, 3 state classes, home gauge card, Stats NUTRITION card, water tracking, repository APIs, SQLite tables |
| 2 | `app_philosophy.md` | **"Deferred: … Nutrition tracking"** (MVP boundary) | Same as above |
| 3 | `modality_tracking.md` | **"Phase 2 (Still Deferred): User-Created Exercise Capabilities — UI to tag custom exercises with capabilities"** | Shipped in `ExerciseEditorScreen`: per-modality capability filtering via `ModalityConfig.formCapabilities` and save-blocking validation on `formRequiredCapabilities` |
| 4 | `stats_screen.md` | **"What Is Intentionally Not in v1: … No per-exercise or per-exercise-type stats"** | Shipped, and contradicted the same document's own overview. `StatsScreen` renders per-exercise e1RM / volume / reps trend cards, per-exercise cardio trends, and per-exercise Recent PRs |
| 5 | `my_routines.md` | **"Single Segment Per Routine … segment grouping (Warm-up, Main Set, Cool-down) is deferred to a future version"** | Shipped, with nearly the labels used as the example of what was deferred. `RoutineSetupScreen` has an **Add Block** button, reorderable segments, and 5 segment types: `warmup`, `main`, `accessory`, `finisher`, `cooldown` |

The three "not in v1" claims that **remain true** on the Stats screen were
re-verified and left in place: no per-modality session breakdown, no date-range
or filter control, no week/month/year toggle.

---

## 2. Documentation describing behavior the app no longer has

| Document | Stale claim | Reality |
|----------|-------------|---------|
| `db_integration.md` | A live `DatabaseProvider.open(..., version: 7)` runtime and a `migrations.dart` of incremental SQL migrations | **The SQLite runtime was retired.** `database_provider.dart`, `db_helper.dart`, and `migrations.dart` are deleted; `sqflite` is gone from `dependencies` (only `sqflite_common_ffi` remains under `dev_dependencies`); the SQL files are no longer bundled as Flutter assets. `scripts/sqlite_schema.sql` survives as the canonical data-model contract, validated by `test/db_seed_test.dart` |
| `db_integration.md` | Schema/seed SQL "loaded from assets via `rootBundle`"; `DatabaseProvider` supports `inMemory` mode | The SQL is read from disk with `File` by the validation test and executed against in-memory `sqflite_common_ffi` |
| `rest_tracking.md` | `migrations.dart` holds the `app_entry_rest` create-table migration | That file is gone; the statement lives in `scripts/sqlite_schema.sql` |
| `widget_catalog.md` | A second `NutritionSummaryCard` ("Daily Targets" goal-line card) at `lib/features/nutrition/widgets/nutrition_summary_card.dart` | File does not exist and nothing references it. **Section deleted.** The surviving `NutritionSummaryCard` is the home gauge card |
| `widget_catalog.md` | `OmnitrainCategoryTile`, `WorkoutCategoryCard`, `ModalityTileWidget` as "legacy/alternative" and "deprecated stub" | All three classes and files deleted. `lib/widgets/cards/` holds only `energy_tile.dart`, `energy_core.dart`, `maintenance_tile.dart` |
| `widget_catalog.md` | `drill_metric_widget.dart`, `round_metric_widget.dart`, `timed_metric_widget.dart` as "stub redirects kept for import compatibility" | None exist. `DominantMetricWidget` is declared in `set_metric_widget.dart` |
| 7 docs | `ExercisePickerDialog` at `lib/widgets/pickers/exercise_picker_dialog.dart` — a **modal dialog** | Class and file gone. Exercise selection is a **full-screen page push**, `ExercisePickerScreen` at `lib/features/exercise/exercise_picker_screen.dart`, returning the selected `Exercise` on pop. Renamed across `README.md`, `create_new_exercise.md`, `exercise_ranking.md`, `modality_based_exercise_ui.md`, `modality_tracking.md`, `my_routines.md`, `widget_catalog.md` |

---

## 3. Screens missing from the inventory

`navigation_and_screens.md` listed 18 of the 24 public screen classes.

**Added — reachable in production:**

- `CalendarScreen` (was referenced in prose but had no inventory row)
- `DaySessionListScreen` — was mentioned in **no doc at all**
- `PeriodListScreen` — was mentioned in **no doc at all**
- `CreatePeriodScreen` — was mentioned in **no doc at all**

**Added — present but not reachable, now labelled as such:**

- `ExerciseDetailScreen` — a thin compatibility wrapper whose `build` returns
  `WorkoutSessionScreen(initialFocusId: …)`. No production call site; used only
  by `test/screen_widget_test.dart`.
- `MaintenancePlaceholderScreen` — **dead code**. Zero references in `lib/` or
  `test/`.

Reverse check: every screen the docs describe exists in the app.

---

## 4. Navigation drift

The documented flow diagram was corrected and **every path was verified
individually against its `OmniNavigator` call site** — 29 edges, all confirmed.

Paths that were missing and are now documented:

- `CalendarScreen` → `PeriodListScreen` → `CreatePeriodScreen` (new and edit)
- `CalendarScreen` → `DaySessionListScreen` → `SessionSummaryScreen` / `WorkoutSessionScreen`
- `RoutineSetupScreen` → `ExercisePickerScreen`
- `SessionSummaryScreen` → `ExercisePickerScreen` (from inside the save-as-routine sheet)
- `SessionSummaryScreen` → `CalendarScreen`
- `ProfileScreen` → `AvatarCropSheet`

Also corrected: the home footer entry point was labelled "Nutrition Strip",
which was superseded by `NutritionSummaryCard`.

---

## 5. Data model gaps

`data_models.md` is now field-complete in both directions, verified
programmatically.

**Four live models were entirely undocumented:**

- **`TimedInstance`** (+ the `TimedState` enum) — the sole owner of duration for
  `timed` and `drill` efforts, replacing the old duration `EffortObservation`.
  12 fields.
- **`PlannedSession`** — calendar-scheduled sessions. 12 fields.
- **`TrainingPeriod`** — named non-overlapping training blocks. 10 fields.
- **`ExerciseNote`** — persistent per-exercise notes. 6 fields.

**Documented fields that do not exist** (verified absent from both the Dart
model and the SQL schema):

| Model | Phantom field | Note |
|-------|---------------|------|
| `EffortObservation` | `entryIndex` | **The important one.** There is no such field and no `entry_index` column. The set index is encoded in the observation **id** (`obs-{effortId}-{entryIndex}-{metric}`) and parsed back with a regex |
| `EffortObservation` | `recordedAtMs` | Model has `createdAtMs` / `updatedAtMs` |
| `SegmentEffort` | `modality` | Modality lives on the parent `TrainingSession` |
| `Exercise` | `isCustom` | See the unresolved item below |
| `MuscleGroup` | `bodyRegion` | — |
| `MetricApplicability` | `isRequired`, `displayOrder` | The junction is a bare composite key |

**Missing fields added** across 18 models — including substantive ones such as
`Exercise.movementPattern` / `defaultRoundDurationSecs` / `howToSteps` /
`imageAssetPath`, `TrainingSession.locationText` / `perceivedSessionRpe`,
`SegmentEffort.blockId`, and `Food.catalogId`.

---

## 6. Other gaps closed

- **`PeriodState`** was absent from the state documentation despite being wired
  into `main.dart` and backing two screens. Now documented.
- **Five services/utilities** had no entry anywhere: `CatalogSource`,
  `BundledCatalogSource`, `DemoRoutinesValidator`,
  `StartupFailureDiagnosticWriter`, `OmniDateUtils`, `FuzzySearch`.
- **Three constants files** were missing from `constants_reference.md`:
  `water_constants.dart`, `catalog_version.dart`, `data_version.dart`.
- **The dependency graph** in `state_management.md` omitted every nutrition
  state class. Re-derived from `lib/main.dart`.
- **The architecture tree** in `README.md` omitted `features/nutrition/`,
  `calendar/`, `period/`, `stats/`, `onboarding/`, `startup/`,
  `core/navigation/`, `state/nutrition/`, and four `widgets/`
  subdirectories.
- **The maintenance-sheet description** in `app_philosophy.md` claimed three
  items (Profile, Stats, Settings). The shipped sheet has four.
- **8 broken relative links** fixed (wrong `../` depth in `db_integration.md`,
  `stats_screen.md`, and `modality_based_exercise_ui.md`).

---

## 7. The indexing problem

`.github/agents/docs/` totalled ~529 KB across 25 files. Two files were large
enough that indexers serving these docs to agents skip them outright, making
the content unreachable despite being present:

| File | Before | After |
|------|--------|-------|
| `widget_catalog.md` | **94,951 B** (~18% of the entire doc set) | 10,261 B index + 5 pages, largest 31,649 B |
| `state_management.md` | **54,669 B** | 6,353 B index + 4 pages, largest 21,386 B |

**Approach:** the original paths were kept as index pages rather than deleted,
because roughly 100 inbound references from `.github/agents/plans/` and other
docs point at `widget_catalog.md` and `state_management.md`. Every one still
resolves. Each index carries a complete **lookup table** (widget → page, class
→ page) so nothing has to be guessed at, and every part page links back.

The largest remaining file is `data_models.md` at 47,427 B — 72% of the
ceiling, and larger than before this audit because four undocumented models and
~40 missing fields were added to it. It passes, but it is the file most likely
to need splitting next; the warning-band test below will say so before it
becomes a problem.

**Validation added** — `test/docs_indexing_contract_test.dart`, modelled on the
existing `navigation_contract_enforcement_test.dart`:

1. No file exceeds the ceiling (64 KiB).
2. No file is within the 80% warning band (so drift is caught before it breaks).
3. Every relative link resolves.
4. Every page is reachable from another page — an orphan is as unfindable as an
   oversized file.

---

## 8. Unresolved — flagged in the docs, not guessed at

These are marked inline where they matter, not only here.

### 8.1 Two hub implementations disagree
*Flagged in `navigation_and_screens.md` under "Unresolved: two hub
implementations".*

| | Items | Wired up? |
|---|---|---|
| `_buildMaintenanceGrid` (`home_screen.dart`) | 4 — Calendar, Stats, Profile, Settings | **Yes** |
| `HubSheet` (`lib/widgets/hub/hub_sheet.dart`) | 5 — adds Nutrition | **No — never instantiated** |

`HubSheet` is fully built and unit-tested (`test/hub_interaction_test.dart`
asserts all five destinations route correctly), but `HubSheet(` appears nowhere
in `lib/` outside its own constructor. The docs previously described the
`HubSheet` item list *and* a third ordering matching neither implementation.

Two consequences worth knowing: the shipped sheet has **no Nutrition entry**,
and a green `hub_interaction_test.dart` does not mean the hub works in the app.

**Cannot be resolved from source** — either the wiring was missed or `HubSheet`
was abandoned. That is a product call, and fixing it would change application
behavior, which is out of scope here.

### 8.2 No way to identify a custom exercise
*Flagged in `data_models.md` under `Exercise`.*

`isCustom` was documented but never existed. `ownerUserId` is the closest
analogue — `ExerciseLibrary.createExercise` stamps `'user-1'`, and seed
exercises leave it null — but **no code anywhere reads it to branch on
custom-vs-seed**. So there is currently no supported way to ask "is this a
custom exercise?", and whether pre-existing rows carry a reliable value is
unverified.

### 8.3 The exact indexing ceiling is unknown
*Flagged on the `_maxDocBytes` constant and in `README.md`.*

No in-repo source records the actual per-file limit of the consuming indexer.
64 KiB is a documented **assumption**. Everything now sits far below it, so
tightening is cheap if the real limit turns out to be lower — the constant is
the single place to change.

### 8.4 Nutrition has no feature document
*Flagged in the `README.md` documentation map.*

Every other major feature has one. Nutrition's behavior is spread across the
navigation, state, widget, data-model, and DB docs. Writing one is authoring
new documentation rather than correcting drift, so it was left out of this
audit's scope and marked instead.

### 8.5 Pre-existing PR-definition divergence
Untouched by this audit and still open — see
[`docs/releases/2026-06-27-pr-surface-verification.md`](../../../docs/releases/2026-06-27-pr-surface-verification.md).

---

## 9. Verification

- **Full test suite before:** 1963 tests, **2 failures**.
- **Full test suite after:** 1963 tests + 5 new doc-validation tests, **same 2
  failures**, no new ones.
- Both pre-existing failures are in `test/image_storage_service_test.dart` and
  are **environmental, not defects**: they assert that writing into a
  `chmod`-restricted directory throws, but the suite runs as **root** (uid 0),
  which bypasses directory permission bits, so the write succeeds. They fail
  identically before and after this change.
- `git diff --stat` confirms **no file under `lib/` was modified**.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This document
> is a point-in-time audit record. Unlike the current-state docs it is not
> re-derived on later passes; the corrections it describes live in the docs
> themselves.
