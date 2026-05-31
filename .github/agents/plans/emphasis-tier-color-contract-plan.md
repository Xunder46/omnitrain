# Feature: Emphasis-Tier Color Contract (Phase 1A)

## Overview
Rebuild OmniTrain's color system into an explicit emphasis-tier contract shared by all six themes, and migrate the entire app onto it. This phase is a **structural/wiring change only** — the app must look byte-for-byte identical after this work. Any visible difference is a regression.

## Problem Statement
Today the app has two color systems coexisting:
1. **Theme-aware accessor** — `OmniTheme.colorsForTheme(activeTheme)` returns a record of 8 slots that change per theme.
2. **Frozen constants** — `OmniTheme.textPrimary`, `textSecondary`, `surfaceColor`, `surfaceBorderColor`, `backgroundGradientTop`, `backgroundGradientBottom` — compile-time `const` values hardcoded to Abyssal Neon's palette that never respond to theme switching.

Over 103 places in `lib/` reference the frozen constants instead of the theme-aware system. This blocks the future emphasis-tier re-tune (Phase 1B) because elements wired to frozen constants will silently bypass any per-theme tuning.

## Requirements
1. Expand the `OmniThemeColors` record to include five explicit emphasis-tier slots.
2. All six themes must provide values for every new slot (structurally enforced by the record typedef).
3. Migrate all 103 frozen-constant references in `lib/` to the theme-aware system.
4. Remove the frozen constants from `OmniTheme` once nothing references them.
5. Repoint 4 test assertions that use frozen constants.
6. Modality colors are **completely untouched**.
7. No visible change to the app appearance across any theme.

## Acceptance Criteria
- [ ] `OmniThemeColors` typedef includes named emphasis slots: `textDominant`, `textSecondary`, `textMuted` (existing), `textDisabled`; primary-action semantics remain served by existing `primary`.
- [ ] All six themes provide a value for every tier; omission is a compile error (record fields are required).
- [ ] No application code outside `omni_theme.dart` references `OmniTheme.textPrimary`, `OmniTheme.textSecondary`, `OmniTheme.surfaceColor`, `OmniTheme.surfaceBorderColor`, `OmniTheme.backgroundGradientTop`, or `OmniTheme.backgroundGradientBottom`.
- [ ] Those frozen constants are deleted from `omni_theme.dart`.
- [ ] The `textMuted` constant (line 130) is also deleted — only the theme-aware `textMuted` field remains.
- [ ] The app's appearance is unchanged across all six themes (side-by-side of any screen before/after shows no visible color difference).
- [ ] The per-modality color system (`modality_colors.dart`) is byte-for-byte unchanged.
- [ ] No layout, screen structure, or functionality is altered.
- [ ] Existing tests pass unchanged except documented maintenance updates: 4 repointed frozen-constant assertions, 1 scroll-target assertion alignment in `test/interaction_flow_test.dart`, and 1 deterministic delay in `test/session_finish_timers_test.dart`.
- [ ] New unit tests validate the contract (see Testing section).

## Tier Definitions

| Tier Slot | Semantic Role | Frozen Constant It Replaces | Initial Value (all themes) |
|-----------|---------------|----------------------------|---------------------------|
| `textDominant` | Brightest hero element — large values, primary headings, back arrows, selected/active states | `OmniTheme.textPrimary` (White 90%) | `Color(0xE6FFFFFF)` |
| `textPrimaryAction` | Accent color for the main CTA and live/active state indicators | (none — already served by `primary` in the record) | N/A — use existing `primary` field |
| `textSecondary` | Editable-but-not-dominant values, supporting labels, secondary icons | `OmniTheme.textSecondary` (White 70%) | `Color(0xB3FFFFFF)` |
| `textMuted` | Status text, labels, chrome, tertiary metadata | Already exists as `textMuted` in record | (unchanged per theme) |
| `textDisabled` | Unavailable controls, disabled state | (new — no frozen constant) | `Color(0x66FFFFFF)` (White 40%) |

### Structural Colors (already exist, remain unchanged)
- `backgroundTop`, `backgroundBottom`, `surface`, `primary`, `secondary`, `divider`, `surfaceBorder`

### Decision: `textPrimaryAction`
The "primary-action" tier is semantically identical to the existing `primary` field in the record (the accent color used for CTAs). Rather than duplicating it, the contract documentation notes that `primary` serves double duty. No additional slot needed.

**Updated `OmniThemeColors` typedef will be:**
```dart
typedef OmniThemeColors = ({
  // Structural
  Color backgroundTop,
  Color backgroundBottom,
  Color surface,
  Color primary,
  Color secondary,
  Color divider,
  Color surfaceBorder,
  // Emphasis tiers
  Color textDominant,
  Color textSecondary,
  Color textMuted,
  Color textDisabled,
});
```

This is 11 fields (was 8). The `textDominant` replaces the frozen `textPrimary`; `textSecondary` replaces the frozen `textSecondary`; `textMuted` was already in the record; `textDisabled` is new.

## Scenarios

### S-001: Theme contract exposes all emphasis tiers
- Trigger: App resolves theme colors via `OmniTheme.colorsForTheme(theme)`
- Precondition: Any of the 6 supported `AppTheme` values is active
- Flow: Resolve theme tokens and access `textDominant`, `textSecondary`, `textMuted`, `textDisabled`
- Expected outcome: All emphasis-tier fields are present and non-transparent for every theme
- Edge case of: none

### S-002: Frozen constants replaced at call sites
- Trigger: UI renders any migrated screen/widget that previously used frozen constants
- Precondition: Theme tokens are resolved through `OmniTheme.colors`
- Flow: Build affected widgets and read color assignments for text/surface/background/border usage
- Expected outcome: Colors come from `OmniTheme.colors.*` (or `ThemeData` fed from those tokens), with no direct frozen-constant usage
- Edge case of: S-001

### S-003: Frozen constants removed from app code
- Trigger: Static source scan of `lib/`
- Precondition: `omni_theme.dart` cleanup completed
- Flow: Search for `OmniTheme.textPrimary`, `textSecondary`, `surfaceColor`, `surfaceBorderColor`, `backgroundGradientTop`, `backgroundGradientBottom`
- Expected outcome: No matches outside `lib/core/constants/omni_theme.dart`
- Edge case of: S-002

### S-004: Phase 1A visual parity guard
- Trigger: Resolve theme colors for Abyssal Neon and Forge & Ember
- Precondition: Emphasis-tier migration complete
- Flow: Compare `colorsForTheme(theme).textDominant` to former `textPrimary` value (`0xE6FFFFFF`)
- Expected outcome: Values are equal, preserving Phase 1A no-visual-change intent
- Edge case of: S-001

## Migration Mapping

| Frozen Constant | Replacement Expression |
|----------------|----------------------|
| `OmniTheme.textPrimary` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).textDominant` |
| `OmniTheme.textSecondary` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).textSecondary` |
| `OmniTheme.surfaceColor` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).surface` |
| `OmniTheme.surfaceBorderColor` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).surfaceBorder` |
| `OmniTheme.backgroundGradientTop` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).backgroundTop` |
| `OmniTheme.backgroundGradientBottom` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).backgroundBottom` |

**Ergonomic helper** (to avoid verbose call sites):
```dart
/// Shorthand for current theme colors. Not const — reads activeTheme at call time.
static OmniThemeColors get colors => colorsForTheme(activeTheme);
```

With this, migration becomes: `OmniTheme.textPrimary` → `OmniTheme.colors.textDominant`.

**Important note on `const`**: The frozen constants allowed `const` widget usage (e.g., `const Icon(..., color: OmniTheme.textPrimary)`). After migration, these must drop `const` since the color is no longer a compile-time constant. This is expected and acceptable — theme-awareness requires runtime resolution.

## Tier Values Per Theme (Phase 1A — preserve current appearance)

Since the frozen constants are White@90% and White@70% regardless of theme, and all themes have dark backgrounds, the initial tier values are **identical across all six themes**:

| Theme | `textDominant` | `textSecondary` | `textMuted` | `textDisabled` |
|-------|---------------|----------------|-------------|---------------|
| Abyssal Neon | `0xE6FFFFFF` | `0xB3FFFFFF` | `0xFF9BA4B5` (existing) | `0x66FFFFFF` |
| Forge & Ember | `0xE6FFFFFF` | `0xB3FFFFFF` | `0xFFA07060` (existing) | `0x66FFFFFF` |
| Obsidian Volt | `0xE6FFFFFF` | `0xB3FFFFFF` | `0xFF8A7A52` (existing) | `0x66FFFFFF` |
| Void Pulse | `0xE6FFFFFF` | `0xB3FFFFFF` | `0xFF6B5B8A` (existing) | `0x66FFFFFF` |
| Crimson Dojo | `0xE6FFFFFF` | `0xB3FFFFFF` | `0xFFC4907A` (existing) | `0x66FFFFFF` |
| Malachite Core | `0xE6FFFFFF` | `0xB3FFFFFF` | `0xFFAACFAA` (existing) | `0x66FFFFFF` |

This guarantees the app looks identical — the same colors resolve at every call site as before.

## Implementation Plan

### Phase 1: Contract Expansion (@developer)
1. [ ] Expand `OmniThemeColors` typedef to add `textDominant`, `textSecondary` (rename from implicit), `textDisabled` fields
2. [ ] Update all six `colorsForTheme()` switch cases to include the new fields with values from the table above
3. [ ] Add the ergonomic `static OmniThemeColors get colors` getter
4. [ ] Update `buildTextTheme()` call in `app.dart` to pass `textPrimary: tokens.textDominant` and `textSecondary: tokens.textSecondary`

### Phase 2: Migration — Widgets & Layout (@developer)
5. [ ] Migrate `lib/widgets/cards/energy_core.dart` (1 ref)
6. [ ] Migrate `lib/widgets/cards/energy_tile.dart` (3 refs)
7. [ ] Migrate `lib/widgets/layout/omni_back_header.dart` (3 refs + doc comment)

### Phase 3: Migration — Features (@developer)
8. [ ] Migrate `lib/features/home/home_screen.dart` (4 refs)
9. [ ] Migrate `lib/features/home/maintenance_placeholder_screen.dart` (4 refs)
10. [ ] Migrate `lib/features/session/workout_session_list_view.dart` (14 refs)
11. [ ] Migrate `lib/features/session/workout_session_edit_mode.dart` (1 ref)
12. [ ] Migrate `lib/features/exercise/exercise_picker_screen.dart` (11 refs)
13. [ ] Migrate `lib/features/calendar/calendar_screen.dart` (9 refs)
14. [ ] Migrate `lib/features/calendar/day_session_list_screen.dart` (4 refs)
15. [ ] Migrate `lib/features/stats/stats_screen.dart` (10 refs)
16. [ ] Migrate `lib/features/profile/profile_screen.dart` (9 refs)
17. [ ] Migrate `lib/features/profile/widgets/measurement_history_chart_sheet.dart` (7 refs)
18. [ ] Migrate `lib/features/settings/settings_screen.dart` (10 refs)
19. [ ] Migrate `lib/features/period/create_period_screen.dart` (6 refs)
20. [ ] Migrate `lib/features/period/period_list_screen.dart` (1 ref)
21. [ ] Migrate `lib/features/onboarding/onboarding_screen.dart` (2 refs)
22. [ ] Migrate `lib/features/routine/my_routines_screen.dart` (4 refs)

### Phase 4: Cleanup (@developer)
23. [ ] Delete frozen constants from `omni_theme.dart`: `backgroundGradientTop`, `backgroundGradientBottom`, `surfaceColor`, `surfaceBorderColor`, `textPrimary`, `textSecondary`, `textMuted` (the const on line 130)
24. [ ] Run `grep -r "OmniTheme.textPrimary\|OmniTheme.textSecondary\|OmniTheme.surfaceColor\|OmniTheme.surfaceBorderColor\|OmniTheme.backgroundGradientTop\|OmniTheme.backgroundGradientBottom" lib/` — must return zero results
25. [ ] Fix any remaining compile errors from `const` removal

### Phase 5: Tests (@developer)
26. [ ] Repoint `test/header_standardization_test.dart` assertions (3 refs) from `OmniTheme.textPrimary` → `OmniTheme.colors.textDominant`
27. [ ] Repoint `test/screen_widget_test.dart` assertion (1 ref) from `OmniTheme.textSecondary` → `OmniTheme.colors.textSecondary`
28. [ ] New test: assert all 6 themes have every tier slot non-null (compile enforced, but runtime sanity check that values are meaningful — e.g., not transparent)
29. [ ] New test: static grep/search asserting zero frozen-constant refs outside `omni_theme.dart`
30. [ ] New test: for Abyssal Neon and Forge & Ember, verify that `colors.textDominant` resolves to the same value as the former `textPrimary` constant (regression guard)
31. [ ] Maintenance: align `test/interaction_flow_test.dart` scroll expectation with intentional bottom-peek target (`maxScrollExtent - viewport * 0.05`)
32. [ ] Maintenance: stabilize `test/session_finish_timers_test.dart` rest summary assertion by ensuring measurable elapsed rest interval before session end
33. [ ] Run full test suite — all existing tests must pass

### Phase 6: Documentation (@developer)
32. [ ] Update `.github/agents/docs/design_system.md` color system section to document the tier vocabulary
33. [ ] Update `.github/agents/docs/widget_catalog.md` to reference `OmniTheme.colors.textDominant` instead of `OmniTheme.textPrimary`

## Files Affected

### Modified
- `lib/core/constants/omni_theme.dart` — contract expansion + constant deletion
- `lib/app.dart` — update `buildTheme()` call
- `lib/widgets/cards/energy_core.dart`
- `lib/widgets/cards/energy_tile.dart`
- `lib/widgets/layout/omni_back_header.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/home/maintenance_placeholder_screen.dart`
- `lib/features/session/workout_session_list_view.dart`
- `lib/features/session/workout_session_edit_mode.dart`
- `lib/features/exercise/exercise_picker_screen.dart`
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/stats/stats_screen.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/period/create_period_screen.dart`
- `lib/features/period/period_list_screen.dart`
- `lib/features/onboarding/onboarding_screen.dart`
- `lib/features/routine/my_routines_screen.dart`
- `test/header_standardization_test.dart`
- `test/interaction_flow_test.dart`
- `test/screen_widget_test.dart`
- `test/session_finish_timers_test.dart`
- `.github/agents/docs/design_system.md`
- `.github/agents/docs/widget_catalog.md`

### New
- `test/emphasis_tier_contract_test.dart` — tier completeness + regression guards

### Unchanged (explicitly)
- `lib/core/constants/modality_colors.dart` — byte-for-byte unchanged
- All repository, state, model, and service files — no changes

## Risk & Edge Cases

1. **`const` removal**: ~30+ widgets use `const` constructors with frozen color values. Removing `const` is non-breaking but may trigger lint warnings. Suppress or accept.
2. **Hot reload**: The `OmniTheme.colors` getter reads `activeTheme` at call time. Widgets that cache the color in `initState` won't update on theme switch — but this is the existing behavior (frozen constants also didn't update). No regression.
3. **Performance**: The getter calls `colorsForTheme()` which is a switch expression — trivially cheap. No caching needed.
4. **Plan files / docs referencing old constants**: Plan markdown files in `.github/agents/plans/` reference `OmniTheme.textPrimary` etc. These are documentation, not code — leave them unchanged (they describe historical context).

## Notes
- The `textPrimaryAction` tier is served by the existing `primary` field. No new slot needed.
- Phase 1B (the visible re-tune where each theme gets distinct tier values) is a separate future task.
- The `buildTextTheme()` method in `omni_theme.dart` already takes `textPrimary`/`textSecondary` as parameters — the wiring in `app.dart` just needs to pass from the new record fields.

## Progress
- [x] Contract expansion (typedef + 6 themes + getter)
- [x] Migration of all 103 frozen-constant references
- [x] Frozen constant deletion
- [x] Test repointing + new tests
- [x] Documentation update
- [x] Full test suite green

### Phase Status
Complete

## Doc Updates
- `.github/agents/docs/navigation_and_screens.md`: no update required (no route/screen map changes)
- `.github/agents/docs/state_management.md`: no update required (no state/service ownership changes)
- `.github/agents/docs/widget_catalog.md`: updated (`OmniTheme.colors.*` replacements for header/surface references)
- `.github/agents/docs/data_models.md`: no update required (no model changes)
- `.github/agents/docs/db_integration.md`: no update required (no repository/schema/backend changes)

## Feedback


---

## Iteration 2: Phase 1B — Emphasis-Tier Visual Re-Tune

### Overview

With Phase 1A complete (all elements drawing from the tier system), this iteration re-tunes the six palettes so the intended visual hierarchy actually reads. The current themes have identical white-at-opacity tier values (`textDominant` = white 90%, `textSecondary` = white 70%, `textDisabled` = white 40% across all six themes), producing a flat hierarchy where the accent color appears on too many elements at once and no clear loud-versus-quiet relationship exists.

The target: each theme gets **distinct, perceptually separated tier values** tuned to its personality, producing a deliberate two-tier visual outcome per screen — a small number of loud elements (dominant hero metric + single primary action) against quiet recessive chrome.

### Constraint Summary

- **In scope**: Color VALUE changes in `colorsForTheme()` for all 6 themes — the tier fields `textDominant`, `textSecondary`, `textMuted`, `textDisabled`, and potentially `primary`/`secondary` (accent relationship tuning).
- **Out of scope**: Per-modality color system (byte-for-byte unchanged), layout/structure/functionality, tier contract or wiring changes, screen redesign (later phases).
- **This phase intentionally changes appearance** — it is the first visible change since Phase 1A locked in "no-visual-change."

### Design Principles for Re-Tuning

1. **Dominant** is the brightest, highest-contrast tier — what the eye hits first. For light-on-dark themes this means close to full white or a luminous theme-tinted white.
2. **Primary-action (accent)** — the theme's signature hue, reserved for the single primary CTA and live/active state. Active-state usage should be the same hue at a different opacity/brightness treatment (same-hue-different-tier), not a second accent.
3. **Secondary** — clearly subordinate to dominant. Editable but not hero. Should read as "available" but not "look at me."
4. **Muted** — distinctly recessive. Chrome, labels, metadata the user glances at but does not act on.
5. **Disabled** — clearly inert. Must look unavailable without disappearing entirely.
6. **Minimum perceptual gap** — between adjacent tiers, there must be at least ~15% relative luminance difference (or ~0.05 WCAG luminance delta) so the hierarchy is obvious at a glance.
7. **Theme personality preserved** — Abyssal Neon stays cool aqua, Forge & Ember stays warm orange, etc. Only relationships between tiers change, not theme identity.

### Proposed Tier Values

Each theme's text tiers are tuned to the theme's background for contrast, and tinted to match the theme's personality where appropriate.

#### Abyssal Neon (cool aqua identity)
| Tier | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| `textDominant` | `0xE6FFFFFF` (white 90%) | `0xF2FFFFFF` (white 95%) | Push dominant brighter for clear #1 |
| `textSecondary` | `0xB3FFFFFF` (white 70%) | `0x99FFFFFF` (white 60%) | Widen gap: pull secondary down |
| `textMuted` | `0xFF9BA4B5` (steel blue) | `0xFF7A8899` (darker steel) | Darken muted for clearer separation from secondary |
| `textDisabled` | `0x66FFFFFF` (white 40%) | `0x4DFFFFFF` (white 30%) | Reduce further for inert read |
| `primary` | `0xFF00B4B8` | `0xFF2DE2E6` | Brighter neon cyan — the accent must pop against the toned-down secondary |
| `secondary` | `0xFF1B9AAA` | `0xFF1B9AAA` | Unchanged — supporting accent |

#### Forge & Ember (warm orange identity)
| Tier | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| `textDominant` | `0xE6FFFFFF` | `0xF0FFF5EA` (warm white 94%) | Warm-tinted dominant matches theme character |
| `textSecondary` | `0xB3FFFFFF` | `0x99FFFFFF` (white 60%) | Pull secondary down |
| `textMuted` | `0xFFA07060` (warm brown) | `0xFF8A5C4E` (darker warm) | Darken for clearer separation |
| `textDisabled` | `0x66FFFFFF` | `0x4DFFFFFF` (white 30%) | More inert |
| `primary` | `0xFFFF6B35` | `0xFFFF7B45` | Slightly brighter/lighter ember for accent pop |
| `secondary` | `0xFFCC4A1A` | `0xFFCC4A1A` | Unchanged |

#### Obsidian Volt (dark amber identity)
| Tier | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| `textDominant` | `0xE6FFFFFF` | `0xF2FFFFFF` (white 95%) | Bright dominant on near-black bg |
| `textSecondary` | `0xB3FFFFFF` | `0x99FFFFFF` (white 60%) | Subordinate gap |
| `textMuted` | `0xFF8A7A52` (olive gold) | `0xFF6E6240` (darker olive) | Darken for clear muted tier |
| `textDisabled` | `0x66FFFFFF` | `0x4DFFFFFF` (white 30%) | Inert |
| `primary` | `0xFFD4A017` | `0xFFE8B420` | Slightly more luminous amber — accent stands alone |
| `secondary` | `0xFF9C7400` | `0xFF9C7400` | Unchanged |

#### Void Pulse (deep violet identity)
| Tier | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| `textDominant` | `0xE6FFFFFF` | `0xF2FFFFFF` (white 95%) | Bright dominant |
| `textSecondary` | `0xB3FFFFFF` | `0x99FFFFFF` (white 60%) | Subordinate |
| `textMuted` | `0xFF6B5B8A` (muted violet) | `0xFF6B5B8A` (kept) | Preserves muted > disabled ordering on surface while keeping separation |
| `textDisabled` | `0x66FFFFFF` | `0x4DFFFFFF` (white 30%) | Inert |
| `primary` | `0xFF8B5CF6` | `0xFFA478FF` | Lighter violet — accent pop on dark bg |
| `secondary` | `0xFF6D3FD4` | `0xFF6D3FD4` | Unchanged |

#### Crimson Dojo (martial red identity)
| Tier | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| `textDominant` | `0xE6FFFFFF` | `0xF2FFFFFF` (white 95%) | Bright dominant |
| `textSecondary` | `0xB3FFFFFF` | `0x99FFFFFF` (white 60%) | Subordinate |
| `textMuted` | `0xFFC4907A` (warm blush) | `0xFFA07060` (darker warm) | Darken for tier separation |
| `textDisabled` | `0x66FFFFFF` | `0x4DFFFFFF` (white 30%) | Inert |
| `primary` | `0xFFE53935` | `0xFFFF4C47` | Brighter crimson — accent clarity |
| `secondary` | `0xFFD32F2F` | `0xFFD32F2F` | Unchanged |

#### Malachite Core (deep emerald identity)
| Tier | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| `textDominant` | `0xE6FFFFFF` | `0xF2FFFFFF` (white 95%) | Bright dominant |
| `textSecondary` | `0xB3FFFFFF` | `0x99FFFFFF` (white 60%) | Subordinate |
| `textMuted` | `0xFFAACFAA` (green tint) | `0xFF7FAA7F` (darker green) | Darken for clear muted |
| `textDisabled` | `0x66FFFFFF` | `0x4DFFFFFF` (white 30%) | Inert |
| `primary` | `0xFF1A9A4A` | `0xFF24B85A` | Brighter emerald — accent pop |
| `secondary` | `0xFF128A40` | `0xFF128A40` | Unchanged |

### Perceptual Hierarchy Verification

For every theme the luminance ordering must hold:
```
luminance(textDominant) > luminance(textSecondary) > luminance(textMuted) > luminance(textDisabled)
```
And `primary` must be chromatically distinct from all text tiers (different hue, high saturation vs neutral/low-saturation text).

### Implementation Steps (@developer)

#### Phase 1: Re-tune tier values
1. [ ] Update `colorsForTheme(AppTheme.abyssalNeon)` with proposed values
2. [ ] Update `colorsForTheme(AppTheme.forgeEmber)` with proposed values
3. [ ] Update `colorsForTheme(AppTheme.obsidianVolt)` with proposed values
4. [ ] Update `colorsForTheme(AppTheme.voidPulse)` with proposed values
5. [ ] Update `colorsForTheme(AppTheme.crimsonDojo)` with proposed values
6. [ ] Update `colorsForTheme(AppTheme.malachiteCore)` with proposed values

#### Phase 2: Unit tests
7. [ ] New test: assert for each theme that `luminance(textDominant) > luminance(textSecondary) > luminance(textMuted) > luminance(textDisabled)` with minimum gap between adjacent tiers
8. [ ] New test: assert `primary` color differs from `textDominant` and `textSecondary` in hue (chromatic distinctness) for each theme
9. [ ] Update `test/emphasis_tier_contract_test.dart`: remove or update the "preserve former textPrimary value" assertion — Phase 1B intentionally changes these values
10. [ ] Verify all other functionality tests still pass (no color-value assertions in non-theme tests)

#### Phase 3: Visual verification
11. [ ] Run the app in each of the 6 themes on a representative screen (session detail or home) and capture screenshots to `docs/releases/phase-1b-screenshots/`
12. [ ] Verify: dominant clearly brightest, secondary clearly subordinate, muted clearly recessive, disabled clearly inert, accent visually distinct from all text tiers

#### Phase 4: Documentation
13. [ ] Update `.github/agents/docs/design_system.md` "Emphasis Tiers" section with the new per-theme values
14. [ ] Update the Tier Values table in this plan file with final implemented values (if adjusted during development)

### Acceptance Criteria
- [ ] In every theme, the five tiers are perceptually well-separated: dominant clearly brightest, secondary clearly subordinate, muted clearly recessive, disabled clearly inert
- [ ] In every theme, the primary-action (accent) tier is visually distinct from the dominant and secondary tiers; primary-action and active-state usages share one hue (no second competing accent)
- [ ] Each theme retains its established identity and character (hue family preserved)
- [ ] The re-tuned tiers are verified on a representative screen in all 6 themes (screenshots committed)
- [ ] Per-modality color system (`modality_colors.dart`) is byte-for-byte unchanged
- [ ] No layout, screen structure, or functionality is altered
- [ ] New test asserts minimum contrast/separation relationship between tiers for each theme
- [ ] New test asserts primary-action tier differs from dominant and secondary tiers in each theme
- [ ] Phase 1A "preserve former textPrimary" test is updated to reflect intentional value change
- [ ] Full test suite passes

### Files Affected

#### Modified
- `lib/core/constants/omni_theme.dart` — 6 theme color value updates
- `test/emphasis_tier_contract_test.dart` — update Phase 1A regression guard, add hierarchy tests
- `.github/agents/docs/design_system.md` — updated tier value documentation

#### New
- `docs/releases/phase-1b-screenshots/` — visual verification artifacts (6 themes)

#### Unchanged (explicitly)
- `lib/core/constants/modality_colors.dart` — byte-for-byte unchanged
- All widget files, feature screens, state files — only color VALUES in `omni_theme.dart` change; every element draws from the tier system so it updates automatically
- No repository, model, or service files affected

### Risk & Edge Cases

1. **Reduced secondary opacity (70% → 60%)** may make some supporting text too dim on certain backgrounds. Developer should verify readability on surface cards (not just gradient background).
2. **Brighter primary accents** — if the primary is pushed too bright, it may conflict with `textDominant`. The test gate (chromatic distinctness) catches this.
3. **Forge & Ember warm-tinted dominant** — using a non-pure-white dominant (`0xF0FFF5EA`) risks looking yellowish. If it reads poorly, fall back to pure white `0xF2FFFFFF`.
4. **Muted tier darkening** — if muted text becomes too dark on the theme's surface color, it won't meet WCAG AA. Developer should spot-check contrast on `.surface` cards.

### Notes
- The Proposed Values table is a starting point. The Developer may adjust ±5–10% opacity or ±10° hue shift during implementation if the on-screen result doesn't read well, as long as the hierarchy ordering and minimum gaps hold.
- The `secondary` structural field (used for supporting accent, not text) is left unchanged in most themes — it's not a text tier but a UI chrome color.
- This work has **zero blast radius beyond `omni_theme.dart`** because every element already draws from the tier tokens. Changing a value here changes it everywhere, consistently.

## Progress
- [x] Phase 1A: Contract expansion (typedef + 6 themes + getter) ✓
- [x] Phase 1A: Migration of all 103 frozen-constant references ✓
- [x] Phase 1A: Frozen constant deletion ✓
- [x] Phase 1A: Test repointing + new tests ✓
- [x] Phase 1A: Documentation update ✓
- [x] Phase 1A: Full test suite green ✓
- [x] Phase 1B: Re-tune tier values in all 6 themes
- [x] Phase 1B: Add hierarchy separation unit tests
- [x] Phase 1B: Update Phase 1A regression test
- [ ] Phase 1B: Visual verification (6 theme screenshots)
- [x] Phase 1B: Documentation update

### Iteration 2 Phase Status
Blocked

## Feedback

- Blocker: automated screenshot capture is currently unavailable in this environment.
- `flutter screenshot` reports: "Screenshot not supported for My iPhone 16 (wireless)."
- Dart MCP `launch_app` failed to launch a desktop target due missing Flutter binary path (`/Users/irinakutsenko/flutter/bin/flutter`).
- Result: Phase 1B visual-verification artifact generation is pending manual capture.
- Reviewer note: Phase 1B cannot be approved until `docs/releases/phase-1b-screenshots/` contains all 6 theme screenshots and the visual-verification checklist is marked complete. This is an explicit acceptance criterion and remains unmet.
