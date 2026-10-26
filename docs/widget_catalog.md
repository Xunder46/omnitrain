# Widget Catalog

> **This page is an index.** The catalog was split into five part pages on
> 2026-07-26 so that no single documentation file exceeds the per-file size
> ceiling that the tools indexing this folder enforce. The previous
> single-file catalog was ~95 KB and the tail of it was not retrievable.
> Nothing was dropped in the split — every section moved verbatim into one of
> the pages below (the one deletion is recorded under
> [What changed in the split](#what-changed-in-the-split)).
>
> Links to `widget_catalog.md` from plans and other docs still resolve here;
> use the lookup table to jump to the right page.

## Overview

Reusable UI components live in `lib/widgets/` and are organized by purpose. All widgets follow these conventions:
- Presentation-only (no repository or service access)
- Local UI state only (e.g., `_isPressed`, animation controllers)
- Design tokens from `OmniTheme` (never hardcoded colors/sizes)

Note on cold-start resume:
- There is no resume dialog. A dangling in-progress session is restored silently on `HomeScreen` (post-frame callback calls `checkForInProgressSession()` and `loadHistoricalSession()`); no prompt is shown.
- Verified by `test/interaction_flow_test.dart`, group `HomeScreen active-session affordance`, test `cold-start loaded session shows active tile without launch modal and tap resumes`.

Note on the Stats screen's Instruments widgets:
- The Stats screen's Instruments list is built from four feature-local widgets: `InstrumentList` in `lib/features/stats/widgets/instrument_list.dart` (the sections, the row cap and the expand control), `InstrumentRowTile` and `InstrumentChangeChip` in `lib/features/stats/widgets/instrument_row.dart` (one exercise's figure and its movement against the previous window), `InstrumentSparkline` in `lib/features/stats/widgets/instrument_sparkline.dart` (that exercise's trend line), and `StatsWindowChip` in `lib/features/stats/widgets/window_chip.dart` (the header chip naming the resolved window, carried by the first section header).
- They are feature-scoped rather than `lib/widgets/` material, but they are presentation-only and theme-reactive in the same sense as the catalogued widgets. Their behaviour is owned by [Stats Screen](stats_screen.md) and verified by `test/instrument_list_screen_test.dart`.

Note on the Stats screen's Mix layer:
- `MixLayerSection` in `lib/features/stats/widgets/mix_layer.dart` is the Mix layer's body: the explainer sentence naming the measure in words, the modality bar and its legend (a colour dot and the share per modality, omitting the modalities with no share), the usual bar with its `In this window` / `Your usual` labels, the baseline note, the unrated line, the week strip titled `Week by week · last 8 weeks` with its `7 weeks ago` / `This week so far` caption, and the empty-strip line that replaces the strip when all eight weeks are empty. Its input is a `MixLayerData` (from `StatsProgressService.computeMixLayer()`), the theme colours and the resolved window; it reads no repository.
- It is feature-scoped rather than `lib/widgets/` material, but it is presentation-only and theme-reactive in the same sense as the catalogued widgets. Its only host is the Stats screen (`lib/features/stats/stats_screen.dart`), where it is the first block in the body. Its behaviour is owned by [Stats Screen](stats_screen.md) and verified by `test/mix_layer_screen_test.dart` (groups `S-3201`–`S-3208` on top of the `S-16xx` groups).

Note on the Stats screen's Signals layer:
- `SignalsLayerSection` in `lib/features/stats/widgets/signals_layer.dart` is the Signals layer's body: the `SIGNALS` header, up to `kSignalMaxCards` signal cards (each a kind label and icon, an observation, an optional suggestion and a dismiss control) and the quiet line. Its inputs are a `SignalsData` (from `resolveSignals`), the theme colours and a dismiss callback; it reads no repository, no service and no clock. A gate-unmet screen instead renders the sibling `SignalsLockedSection` — the `SIGNALS` header and the locked line built from the payload's rated weeks alone.
- It is feature-scoped rather than `lib/widgets/` material, but it is presentation-only and theme-reactive in the same sense as the catalogued widgets. Its only host is the Stats screen (`lib/features/stats/stats_screen.dart`), where it is the second block in the body, directly under the Mix layer. Its behaviour is owned by [Stats Screen](stats_screen.md) and verified by `test/signals_layer_screen_test.dart`.

Note on the nutrition trend card:
- `NutritionTrendCard` in `lib/features/nutrition/widgets/nutrition_trend_card.dart` is the nutrition trend's body — the Calories / Macros toggle, both charts, the shared empty state that replaces the charts when no day is logged, the single-point fallbacks and the legend.
- It is feature-scoped rather than `lib/widgets/` material, but it is presentation-only and theme-reactive in the same sense as the catalogued widgets. Its only host is the full-history nutrition trend screen (`lib/features/nutrition/nutrition_trend_screen.dart`), reached from the Stats screen's Fuel row. Its behaviour is owned by [Nutrition](nutrition.md) and verified by `test/nutrition_trend_screen_test.dart`.

Note on the Stats screen's Fuel row:
- `FuelSection` in `lib/features/stats/widgets/fuel_section.dart` is the Fuel row's body: the logged-days indicator, the calories and protein figures with their comparison readouts, and the training / rest split. Its inputs are a `FuelSummary` (from `StatsProgressService.computeFuelSummary()`), the theme colours and the tap callback; it reads no repository.
- It is feature-scoped rather than `lib/widgets/` material, but it is presentation-only and theme-reactive in the same sense as the catalogued widgets. The section root and the row's tap target carry keys (`fuel_section`, `fuel_row`); every other key the row's tests address is declared in the same file. Its behaviour is owned by [Stats Screen](stats_screen.md) and verified by `test/fuel_row_screen_test.dart`.

Note on the Stats screen's primer sheet:
- `StatsPrimerSheet` in `lib/features/stats/widgets/stats_primer_sheet.dart` is the one-shot explanation sheet: three labelled blocks (what the page shows, the Signals cards, the chart icon) over a single `Got it` CTA. It is presentation only — it imports no state class and reads no repository; the host owns the seen flag. Its block and CTA keys are `stats_primer_block_page`, `stats_primer_block_signals`, `stats_primer_block_records` and `stats_primer_dismiss`. Its `Got it` CTA sets `shape` explicitly (the design-system rule), never the Material 3 default.
- It is feature-scoped rather than `lib/widgets/` material, but it is presentation-only and theme-reactive in the same sense as the catalogued widgets. Its hosts are the Stats screen (`lib/features/stats/stats_screen.dart`, the "?" and the empty-card button) and the home screen (`lib/features/home/home_screen.dart`, the once-per-install auto-open). Its behaviour is owned by [Stats Screen](stats_screen.md) and verified by `test/stats_primer_screen_test.dart` and `test/stats_primer_home_test.dart`.

Note on home-screen nutrition summary card:
- The home-screen gauge card is implemented as a screen-local widget in `lib/features/home/widgets/nutrition_summary_card.dart` (`NutritionSummaryCard`).
- It is feature-scoped (only the home screen needs it) but is still presentation-only and theme-reactive. Iteration 5 (Phase 5) supersedes the Phase 4.1 (D-8) `NutritionStripBar` (a full-bleed bottom strip with chevron-shaped fill) with a self-contained gauge card that visually belongs to the same instrument-panel family as the training tiles — rounded corners, raised/lit look, hairline border, and inset horizontal margin. The previous Phase 2 placeholder `NutritionStripButton` widget was already removed.

---

## Catalog Pages

| Page | Covers |
|------|--------|
| [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) | Foundational layout wrappers, card/section chrome, bottom CTA, input field wrappers, the shared message and empty-state widgets |
| [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) | Home tiles, the home gauge card, and the calorie-ring / water / macro-donut cards |
| [Session, Picker & Presentation Widgets](widget_catalog/session_widgets.md) | In-session metric editors, metric popups, PR toast, the effort rating sheet, picker dialogs, presentation models |
| [Nutrition Widgets](widget_catalog/nutrition_widgets.md) | Primer sheet, food rows, thumbnails, the shared food form, group management |
| [Routine, Profile & Brand Widgets](widget_catalog/feature_primitives.md) | Routine badges, avatar crop, measurement sparkline, logo and Zen Halo |

---

## Widget → Page Lookup

Alphabetical. Use this rather than guessing which page a component lives on.

| Widget | Page |
|--------|------|
| `AnimatedZenHalo` | [Routine, Profile & Brand](widget_catalog/feature_primitives.md) |
| `AvatarCropSheet` | [Routine, Profile & Brand](widget_catalog/feature_primitives.md) |
| `CalorieRing` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `CalorieRingCard` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `DemoRoutineBadge` | [Routine, Profile & Brand](widget_catalog/feature_primitives.md) |
| `DominantMetricWidget` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `EffortRatingSheet` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `EnergyCore` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `EnergyTile` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `ExercisePickerScreen` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `FoodForm` | [Nutrition Widgets](widget_catalog/nutrition_widgets.md) |
| `FoodLibraryBrowseSection` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `FoodThumbnail` | [Nutrition Widgets](widget_catalog/nutrition_widgets.md) |
| `HomeLogoButton` | [Routine, Profile & Brand](widget_catalog/feature_primitives.md) |
| `InlineMetricEditor` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `LoadFailureView` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `LogFoodRow` | [Nutrition Widgets](widget_catalog/nutrition_widgets.md) |
| `MacroDonutChart` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `MacroFocusContent` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `MaintenanceTile` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `MeasurementSparkline` | [Routine, Profile & Brand](widget_catalog/feature_primitives.md) |
| `MetricChooserDialog` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `MetricCrownWidget` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `MetricStepCalc` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `ModalityPickerDialog` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `MusclePicker` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `NoiseOverlayPainter` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `NumericFieldWithDoneBar` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `NutritionPrimerSheet` | [Nutrition Widgets](widget_catalog/nutrition_widgets.md) |
| `NutritionSummaryCard` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `OmniBackHeader` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `OmniBottomCTA` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `OmniCardHeader` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `OmniEmptyState` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `OmniGradientBackground` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `OmniMessage` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `OmniSurface` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `PRToast` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `SelectAllOnFocus` | [Layout & Input Primitives](widget_catalog/layout_and_inputs.md) |
| `SessionDistanceCard` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `UiSetData` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `WaterTrackerControl` | [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) |
| `ZenHaloPainter` | [Routine, Profile & Brand](widget_catalog/feature_primitives.md) |
| `showDurationEntryDialog` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |
| `showMetricEditPopup` | [Session, Picker & Presentation](widget_catalog/session_widgets.md) |

### Not yet catalogued

These widgets exist in the source tree but have no catalog entry. Listed here
so the gap is visible rather than silent.

| Widget | File | Note |
|--------|------|------|
| `InteractiveLogo` | `lib/widgets/common/interactive_logo.dart` | Undocumented. |
| `ScrollableTrendChart` | `lib/widgets/chart/scrollable_trend_chart.dart` | Behavior is documented in [Profile & Measurements](profile_and_measurements.md), but it has no catalog entry. |
| `FoodThumbnailImage` | `lib/features/nutrition/widgets/food_thumbnail_io.dart` | Platform-conditional implementation behind `FoodThumbnail`. |
| `ConfirmationDialog` | `lib/widgets/dialogs/confirmation_dialog.dart` | Shared two-choice confirmation dialog factory (`showTwoChoice`, `twoChoice`) plus the unsaved-changes prompt (`showUnsavedChanges`: Keep editing / Discard, returns true on Discard). One look and one action-style helper; see [Design system — Destructive vs Routine Confirmation Dialogs](design_system.md#destructive-vs-routine-confirmation-dialogs). |
| `OverheadPressIcon` | `lib/widgets/icons/overhead_press_icon.dart` | Tile artwork builder for the resistance home tile. |
| `chart_primitives.dart` helpers (`kChartBottomAxisReservedSize`, `buildLegendItem`, `buildSinglePointCard`) | `lib/widgets/chart/chart_primitives.dart` | Shared chart chrome: reserved bottom-axis height, legend swatch+label row, single-history-point card. |
| `buildEdgeAwareDateLabel` (+ `kEdgeLabelHorizontalShift`) | `lib/widgets/chart/edge_aware_date_label.dart` | Bottom-axis date label that insets first/last labels so they clear the y-axis and card border. |

---

## Directory Structure

```
lib/widgets/
├── buttons/              # (empty — reserved for future button components)
├── cards/                # Tile and card components for the home screen
├── chart/                # Chart primitives shared by stats and profile
├── common/               # Cross-feature odds and ends (InteractiveLogo, OmniEmptyState)
├── dialogs/              # Shared confirmation dialogs (ConfirmationDialog)
├── exercise/             # Exercise editor widgets (MusclePicker)
├── feedback/             # Shared transient messages (OmniMessage)
├── icons/                # Custom icon widgets
├── inputs/               # Reusable input field wrappers (select-all, done bar)
├── layout/               # Foundational layout primitives
├── logo/                 # Brand elements (Zen Halo)
├── models/               # Presentation-layer data classes
├── pickers/              # Selection dialogs
└── session/              # Workout session metric widgets
```

---

## Composition Pattern

```
OmniGradientBackground              ← Full-screen cosmic backdrop
  └── OmniSurface                   ← Dark navy card with border + deep shadow
       └── Content                  ← Text, icons, interactive elements

GestureDetector (press tracking)
  └── AnimatedScale (press feedback)
       └── EnergyTile (gradient + shadows)
            └── EnergyCore (icon circle) + Label
```

---

## What Changed in the Split

- The catalog's 16 top-level sections were distributed across the five part
  pages above, verbatim.
- **One section was deleted**: a second `### NutritionSummaryCard` entry
  documented `lib/features/nutrition/widgets/nutrition_summary_card.dart`
  (a "Daily Targets" goal-line card). That file does not exist in the source
  tree and nothing references it. The surviving `NutritionSummaryCard` is the
  home gauge card at `lib/features/home/widgets/nutrition_summary_card.dart`.
- The `Directory Structure` block gained the `chart/`, `common/`, and
  `icons/` directories, which exist in `lib/widgets/` but were missing.
- The **Not yet catalogued** table above is new.

---

## Related Documentation

- [Design System](design_system.md) — Design tokens, color system, typography, animation rules
- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — How metric widgets are used in the workout screen

---

> **Doc freshness** — Last reconciled against source: 2026-10-13. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
