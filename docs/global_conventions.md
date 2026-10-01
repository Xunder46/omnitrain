# Global Conventions

Read this file at the start of every task. It is the single source of truth for cross-cutting rules that apply across features. Keep this page short; follow the linked code and docs for implementation details.

## Rules

| Area | Rule | Where to look |
|------|------|---------------|
| Units + canonical storage | Any user-visible value with a unit must respect the saved preference and go through the shared formatting/conversion utilities. Never hardcode a unit label, duplicate conversion math, or persist a display-unit value. Store canonical values in the app's base units; convert only at input boundaries and display boundaries. | `lib/core/utils/unit_formatter.dart`, `docs/theme_and_settings.md`, `docs/stats_screen.md` |
| Theme tokens only | Colors, accents, surfaces, borders, and other visual styling must come from `OmniTheme` tokens or `ThemeData.colorScheme` derived from the active theme. Never hardcode colors or bypass the selected theme. | `docs/design_system.md`, `docs/theme_and_settings.md`, `lib/app.dart`, `lib/core/constants/omni_theme.dart` |
| Card chrome via `OmniSurface`; card headers via `OmniCardHeader` | Every outlined card in the app must route through `OmniSurface` (single source of truth for border, radius, shadow); every section / card header must route through `OmniCardHeader` (single source of truth for canonical D-1 typography). Raw Flutter `Card(...)` widgets and raw `Text` widgets above outlined cards are not permitted. Per-screen `_SectionHeader` / `_SectionLabel` / `_SummaryCard` / `_MeasurementRow` style widgets have been migrated to these primitives. | `docs/widget_catalog.md`, `docs/design_system.md` ("Section / Card Headers"), `lib/widgets/layout/omni_surface.dart`, `lib/widgets/layout/omni_card_header.dart`, `docs/plans/unified-card-and-header-plan.md` |
| Effort-kind drives analytics | Progress and history logic must derive from the effort actually logged (`SegmentEffort.effortKind` and recorded metrics), not from session labels or modality names. A set logged in Free Training still counts as strength; a timed effort in a lifting session still counts as cardio. | `docs/stats_screen.md` ("Effort-Type Keying"), `docs/modality_tracking.md`, `lib/core/services/stats_progress_service.dart` |
| Timestamps are source data | For log flows without explicit date entry, timestamp at save time. For timed, round, and rest flows, derive elapsed and completion state from persisted wall-clock timestamps rather than local counters so backgrounding and reloads stay correct. | `docs/profile_and_measurements.md`, `docs/state_management.md`, `docs/modality_tracking.md`, `docs/rest_tracking.md`, `lib/data/models/models.dart` |
| Reuse the canonical owner | When a shared utility, state object, or service already owns a cross-cutting concern, use it instead of rebuilding the logic locally. Preference-backed formatting goes through `SettingsState` + `UnitFormatter`; analytics classification goes through the existing progress services; theme selection goes through `SettingsState` + `OmniTheme`. | `docs/state_management.md`, `docs/theme_and_settings.md`, `docs/stats_screen.md`, `lib/core/utils/unit_formatter.dart`, `lib/core/services/stats_progress_service.dart` |
| Instrument panel, not influencer | Favor fast logging, clear status, restrained motion, and low-friction instrumentation over decorative chrome, coaching theater, or social/influencer patterns. Use defaults and inference where the existing product docs do. | `docs/app_philosophy.md`, `docs/design_system.md` |

## Usage

- Developer: satisfy every applicable rule in implementation and tests.
- Code Reviewer: verify every rule explicitly as `PASS`, `N/A`, or `FAIL` before approval.
- Handoffs: point back here; do not restate the rules elsewhere.

**Last Updated**: May 22, 2026

---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
