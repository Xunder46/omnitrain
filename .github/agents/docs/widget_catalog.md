# Widget Catalog

## Overview

Reusable UI components live in `lib/widgets/` and are organized by purpose. All widgets follow these conventions:
- Presentation-only (no repository or service access)
- Local UI state only (e.g., `_isPressed`, animation controllers)
- Design tokens from `OmniTheme` (never hardcoded colors/sizes)

Note on resume dialog:
- The cold-start `Unfinished Session` dialog is implemented as a private, screen-local widget in `HomeScreen` (`_ResumeSessionDialog`).
- It is intentionally not promoted into `lib/widgets/` because it is feature-specific and not reused across screens.

Note on home-screen nutrition summary card:
- The home-screen gauge card is implemented as a screen-local widget in `lib/features/home/widgets/nutrition_summary_card.dart` (`NutritionSummaryCard`).
- It is feature-scoped (only the home screen needs it) but is still presentation-only and theme-reactive. Iteration 5 (Phase 5) supersedes the Phase 4.1 (D-8) `NutritionStripBar` (a full-bleed bottom strip with chevron-shaped fill) with a self-contained gauge card that visually belongs to the same instrument-panel family as the training tiles — rounded corners, raised/lit look, hairline border, and inset horizontal margin. The previous Phase 2 placeholder `NutritionStripButton` widget was already removed.

---

## Directory Structure

```
lib/widgets/
├── buttons/              # (empty — reserved for future button components)
├── cards/                # Tile and card components for the home screen
├── layout/               # Foundational layout primitives
├── logo/                 # Brand elements (Zen Halo)
├── models/               # Presentation-layer data classes
├── pickers/              # Selection dialogs
└── session/              # Workout session metric widgets
```

---

## Layout Primitives

### `OmniGradientBackground`

**File**: `lib/widgets/layout/omni_gradient_background.dart`

Full-screen cosmic gradient backdrop used on every screen. **Also the
single source of truth for the app-wide large-screen content column
cap** — see the [Design System](design_system.md) "Large-screen
content column" rule.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content to overlay |
| `showRadialHighlight` | `bool` | `true` | White radial glow at top-center |

**Layers** (bottom to top):
1. Vertical linear gradient (`backgroundGradientTop` → `backgroundGradientBottom`)
2. Optional radial white highlight (10% opacity)
3. Optional film-grain noise overlay (`NoiseOverlayPainter`) — controlled by `OmniTheme.enableBackgroundNoise`
4. The `child`, wrapped automatically in a centered column on large screens (see below)

**Large-screen content column (built-in)**:

The `child` is wrapped in a `Center` + `ConstrainedBox(maxWidth:
OmniTheme.kColumnMaxWidth)` when the surface is at least
`OmniTheme.kColumnMinActivationWidth` dp wide. Below the threshold
the child passes through unchanged. This is the **only** place the
app's centered-column behavior is implemented, and every screen
reaches it for free because every screen-level route wraps its page
in `OmniGradientBackground` (per the navigation contract), and the
home / onboarding surfaces are wrapped in the gradient inside
`MaterialApp.builder` in `app.dart`.

- **Phone-class widths** (≤ 500 dp, includes every phone and a
  foldable in folded state): cap is fully inert. `child` fills the
  surface.
- **Tablet-class widths** (> 500 dp, includes every tablet and a
  large unfolded foldable): `child` sits in a centered column of
  `OmniTheme.kColumnMaxWidth` (480) dp, with equal empty margins on
  both sides. The column is a hard cap — it does not grow with the
  surface.
- **Vertical sizes are unchanged at every width** — the gradient
  `Container` and the radial highlight / noise overlays continue to
  fill the full surface; only the `child`'s horizontal extent is
  capped.

Per-screen opt-outs are not supported. The cap is a single global
behavior; the design system is intentionally phone-shaped.

### `OmniBackHeader`

**File**: `lib/widgets/layout/omni_back_header.dart`

Standardized back-and-title header used by all secondary screens. Implements `PreferredSizeWidget` so it slots directly into `Scaffold.appBar`. **Screen-level chrome** — lives above the body and is distinct from `OmniCardHeader` (per-card title, see below).

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Primary header text |
| `subtitle` | `String?` | `null` | Optional second line below the title in `bodySmall` + `OmniTheme.colors.textSecondary` |
| `onBack` | `VoidCallback?` | `null` | Called on back arrow tap; defaults to `Navigator.of(context).pop()` |
| `actions` | `List<Widget>?` | `null` | Trailing widgets forwarded to `AppBar.actions` |

**Behavior**:
- `preferredSize` is always `Size.fromHeight(kToolbarHeight)` (56 px)
- `backgroundColor` and `surfaceTintColor` are `Colors.transparent`, `elevation: 0` — gradient background shows through
- Back arrow color: `OmniTheme.colors.textDominant` (never inherits from theme's `foregroundColor`)
- `titleTextStyle`: `titleLarge` + `FontWeight.w600` + `OmniTheme.titleLetterSpacing` (0.4) + `OmniTheme.colors.textDominant`
- Screens must set `extendBodyBehindAppBar: true` on their `Scaffold` for the gradient to render behind the transparent header

**Usage notes**:
- Calendar uses `actions: [FilledButton('+')]` for the Periods shortcut
- `SessionSummaryScreen` uses `actions: [PopupMenuButton]` for the Edit/Save/Discard overflow
- `SessionOverviewScreen` and `RoutineSetupScreen` use `subtitle` for contextual secondary text

### `OmniCardHeader`

**File**: `lib/widgets/layout/omni_card_header.dart`

Canonical per-card header rendered above an outlined card. Single source of truth for section/card header typography across the app. **Card-level chrome** — distinct from `OmniBackHeader` (screen-level, above the body).

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Header title (left-aligned) |
| `actions` | `List<Widget>?` | `null` | Trailing widgets (icon buttons, controls) rendered in a right-aligned cluster. `null` or empty list renders no cluster. |
| `padding` | `EdgeInsetsGeometry?` | `EdgeInsets.fromLTRB(0, 0, 0, 8)` | Padding around the row. The default leaves an 8 dp gap below the row so the header sits cleanly above the card beneath it. |

**Behavior**:
- Title typography is the canonical D-1 quartet: `theme.textTheme.labelSmall` + `FontWeight.w600` + `letterSpacing: 2.0` + `color: OmniTheme.colors.textMuted`. The widget enforces this — callers cannot override the style.
- Title has `maxLines: 1, overflow: TextOverflow.ellipsis` (Phase 2.2 / A8) so long titles truncate gracefully rather than wrap.
- Layout: `Row(MainAxisAlignment.spaceBetween)` with the title inside `Expanded` (so it shrinks/truncates when actions take space) and the actions cluster as a `Row(mainAxisSize: MainAxisSize.min, children: actions)`. Keys: `Key('omniCardHeader_title')` on the title `Text`; `Key('omniCardHeader_actions')` on the actions cluster `Row`.
- Presentation-only: no repository or service access, no business logic.
- Use cases (every section/card header in the app routes through this widget):
  - **Settings screen** (Phase 1): `PREFERENCES`, `SOUNDS & ALERTS`, `WORKOUT`, `APPEARANCE`.
  - **Session Summary screen** (Phase 2 / 2.1 / 2.2): the date header above the combined session info card (with the modality chip in actions), the `SESSION NOTE` header above the note card, and the month label header above the calendar card (with the `Open Calendar` button in actions).
  - **Daily Nutrition screen** (Phase 3): `Today` header (with the `edit_targets_icon` `IconButton` in actions), `Foods I Eat` header (with the `food_library_manage_pencil` `IconButton` in actions).
  - **Profile screen** (Phase 4): one `OmniCardHeader` per measurement definition (label + the `+` add `OutlinedButton` in actions).
  - **Stats screen** (Phase 5): `ALL TIME`, `STRENGTH` / `CARDIO` (with the window chip in actions), `NUTRITION`.

**Forbidden**:
- Raw `Text` widgets above outlined cards are **not permitted** for section/card headers. Any pre-existing per-screen `_SectionHeader` / `_SectionLabel` / in-card `Text(definition.label)` widget has been migrated to this primitive (see `.github/agents/plans/unified-card-and-header-plan.md`).
- Hard-coded overrides of the title style — the typography is canonical and enforced by the widget.

### `OmniSurface`

**File**: `lib/widgets/layout/omni_surface.dart`

Base container for all cards and panels. Dark navy with border + shadow. **Single source of truth for outlined card chrome** — every outlined card in the app routes through this widget.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content |
| `padding` | `EdgeInsets?` | `null` | Optional inner padding |
| `showShadow` | `bool` | `true` | Deep shadow toggle |

**Behavior**:
- Uses `OmniTheme.colors.surface`, `surfaceBorderRadius`, `OmniTheme.colors.surfaceBorder`, `surfaceBorderWidth`, `deepShadow`. The widget is the only authority for outlined card chrome across the app.
- No call-site may re-declare border, radius, or shadow for an outlined card. Pre-existing per-screen `_SummaryCard` (Session Summary), raw Flutter `Card()` (Foods I Eat on the Daily Nutrition screen, Phase 3) and the calorie ring card's internal `Card()` (Daily Nutrition "Today" card, A20) have been migrated to this primitive.

### `OmniBottomCTA`

**File**: `lib/widgets/layout/omni_bottom_cta.dart`

Shared full-width bottom call-to-action used by screens with a single persistent footer action. **Single source of truth for primary bottom CTA placement and width** — see `.github/agents/plans/primary-bottom-cta-anchor-width-plan.md`.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `String` | required | Button text; a leading `+` triggers the shared add affordance |
| `onPressed` | `VoidCallback?` | required | Tap handler; `null` disables the CTA |
| `isDestructive` | `bool` | `false` | Uses the active theme’s destructive/error colors |
| `buttonKey` | `Key?` | `null` | Optional `Key` forwarded to the rendered `FilledButton`. Used by host screens that need a stable test target (e.g. the `food_form_save` key on the food library host screens) |

**Behavior**:
- **Height**: `OmniTheme.buttonPrimaryHeight` (56 dp).
- **Width**: `double.infinity` inset by `OmniTheme.bottomCTAHorizontalPadding` (16) on each side. The button's left/right edges sit at exactly the same horizontal margin on every screen.
- **Corner radius**: `OmniTheme.buttonBorderRadius` (12 dp).
- **Vertical anchor**: `SafeArea(top: false)` (bottom on by default) plus `OmniTheme.bottomCTAVerticalBottomPadding` (16). The button clears the device home indicator (iOS) and gesture / 3-button nav bar (Android) uniformly.
- **Top padding**: `OmniTheme.bottomCTAVerticalTopPadding` (24) — the gap between content above and the CTA so the gradient fade reads as a deliberate break.
- **Footer treatment**: theme-reactive fade gradient using `colorScheme.surface` so the CTA lifts above scrollable content.
- Prevents per-screen CTA styling drift by centralizing footer layout, colors, and safe-area handling.

**Call-site contract**:
- All primary bottom CTAs use this widget. Inline `Spacer() + SizedBox + FilledButton` is **not** permitted at the bottom of a screen — that pattern has been removed in favour of `Scaffold.bottomNavigationBar: OmniBottomCTA(...)`.
- Form bodies that need clearance for the bottom CTA use `OmniTheme.formBottomCTAClearance` (112) as the scroll view's bottom padding.

### `NoiseOverlayPainter`

**File**: `lib/widgets/layout/noise_overlay_painter.dart`

`CustomPainter` that renders a subtle film-grain texture over the gradient background. Creates a premium aesthetic without being distracting.

---

## Home Screen Cards

### `EnergyTile`

**File**: `lib/widgets/cards/energy_tile.dart`

Primary home-screen modality tile. `StatefulWidget` with press-scale animation. Renders one of two visual tiers (primary or secondary) and optionally an active-state pulse dot.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Tile label (e.g., "Cardio / Endurance") |
| `icon` | `IconData?` | `null` | Tile icon (use when `iconWidget` is null) |
| `iconWidget` | `Widget?` | `null` | Custom icon widget (e.g. `OverheadPressIcon`) |
| `accentColor` | `Color` | required | Per-tile accent color (used for fill, glow, label) |
| `onTap` | `VoidCallback` | required | Tap handler |
| `isSecondary` | `bool` | `false` | Secondary-tier rendering (8% fill, 56-pt icon at white @ 75%, no rim/shadow). Used for Free and Routines. |
| `isActive` | `bool` | `false` | Highlights when session matches this modality; renders the pulsing "Workout in progress" dot. |

**Behavior**:
- Press scale: `OmniTheme.pressedScale` (0.96) with 180ms animation.
- Solid low-opacity accent fill (primary ~18%, secondary ~8%) — no gradient.
- Primary tier: 1-px white top rim highlight (white @ 8%) + 1-px black bottom inner shadow (black @ 20%), full width, clipped to the 20-pt rounded corners.
- Secondary tier: no rim highlight, no inner shadow, no drop shadow.
- Active state: enhanced accent-color glow (blur 48/28, no animation) + a small pulsing white dot (~8-pt, top-right ~10-pt inset) that animates opacity 80% → 100% → 80% over a 1.8-s `TweenSequence` cycle. Dot is decorative (`ExcludeSemantics`); tile announces `<title>, Workout in progress` via `Semantics`.
- Content layout: `Positioned.fill` + `Column` with `Expanded(flex: 3)` for the icon band and a fixed `Padding(bottom: 12)` for the label — the label baseline is anchored to a fixed bottom offset so it does not float when the icon size changes.
- Responsive: text labels hide below 100-px width via `LayoutBuilder`.

### `EnergyCore`

**File**: `lib/widgets/cards/energy_core.dart`

Circular icon widget inside `EnergyTile`. Radial gradient background with glow shadow.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `icon` | `IconData` | required | Center icon |
| `gradientColors` | `List<Color>` | required | Radial fill |
| `glowColor` | `Color` | required | Outer glow |
| `isActive` | `bool` | `false` | Glow intensity boost |
| `size` | `double` | `OmniTheme.energyCoreSize` | Circle diameter |

### `MaintenanceTile`

**File**: `lib/widgets/cards/maintenance_tile.dart`

Small tile used inside the home screen's maintenance bottom sheet for system features (Profile, Stats, Settings). Simpler styling than `EnergyTile`.

### `OmnitrainCategoryTile` / `WorkoutCategoryCard`

**Files**: `lib/widgets/cards/omnitrain_category_tile.dart`, `lib/widgets/cards/workout_category_card.dart`

Legacy/alternative tile implementations. May be deprecated stubs — check code for current usage.

### `ModalityTileWidget`

**File**: `lib/widgets/cards/modality_tile_widget.dart`

**DEPRECATED.** Returns `SizedBox.shrink()`. Replaced by `EnergyTile`.

---

## Home Screen Footer

### `NutritionSummaryCard`

**File**: `lib/features/home/widgets/nutrition_summary_card.dart`

Self-contained gauge card on the home screen (Iteration 5 / S-100..S-106 — supersedes the Phase 4.1 `NutritionStripBar` full-bleed bottom strip). Sits BELOW the training-tile grid with top gap = 2 × `standardGridSpacing` and is INSET from the screen edges (16 px horizontal padding, matching the tile grid's side margin) — NOT a full-bleed rectangle. The card chrome matches the training-tile visual family: 20 px `OmniTheme.surfaceBorderRadius`, `OmniTheme.surfaceBorder` hairline border, `OmniTheme.deepShadow` lift. Pure presentation — no state access, no business logic, no math. All colors come from `OmniTheme.colors`; per-macro calorie math lives on `NutritionState` (D-4 getters) and is passed in.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `consumedCalories` | `int` | required | Today's consumed calories (already rounded by the caller) |
| `targetCalories` | `int?` | required | Today's calorie target, or `null` for "no goal" |
| `proteinKcal` | `int` | required | Protein calorie contribution (D-4: `protein × 4`) |
| `carbsKcal` | `int` | required | Net-carbs calorie contribution (`carbs - fiber`, then × 4 — matches the donut chart's percentage calculation) |
| `fatKcal` | `int` | required | Fat calorie contribution (D-4: `fat × 9`) |
| `onTap` | `VoidCallback` | required | Tap handler — the card is always tappable (S-104). The ENTIRE card body is one tap target; the chevron is a visual cue only. |

**Behavior (S-100..S-106)**:
- **Geometry**: the card is a `Column` of three regions inside a `Material` + `InkWell` + `Ink` with rounded-corner `BoxDecoration` chrome. The three regions:
  1. **Headline row** (`Key('nutrition_card_headline')`): small `Icons.local_dining_outlined` (18 px, `textDominant`) + 8-px gap + the headline `Text` `"{consumed} / {target} Cal"` (comma-grouped thousands) — the LARGEST, BRIGHTEST text on the card (`theme.textTheme.headlineSmall` + `FontWeight.w800` + `textDominant`) + 8-px gap + `Icons.chevron_right` (22 px, `textDominant`) at the right edge. The headline is the only element that earns white emphasis.
  2. **Gauge row** (`Key('nutrition_card_gauge')`): a `Stack` of two layers — the `track` (full-width `divider`-colored pill, 12 px tall, `Key('nutrition_card_gauge_track')`) and the `fill` (a clipped `Row` of three macro `Container`s with `Key('nutrition_card_gauge_segment_0'..'2')`). The fill width = `clamp(consumed / target, 0, 1) × trackWidth` (S-102); the segments are sized as a share of CONSUMED calories (S-103), so they live INSIDE the fill, not across the full bar.
  3. **Caption row** (`Key('nutrition_card_caption')`): a `spaceBetween` `Row` of three `(colorMarker, "M N%")` groups with keys `nutrition_card_caption_protein` / `_carbs` / `_fat`. The caption percentages are the macro's share of CONSUMED calories (S-103). The empty state renders DASHES (`—`), NOT `0%` (S-104).
- **Tap target** (S-101): the ENTIRE card is wrapped in a single `InkWell(onTap: onTap)`. Tapping ANY region of the card (headline text, gauge track, fill, caption row, chevron) fires `onTap`. The empty state is still tappable.
- **Empty state** (S-104): when `consumedCalories <= 0` OR `targetCalories` is null / `<= 0`:
  - Headline renders `"0 / {target ?? "—"} Cal"` in `textDominant` (NOT a warning tone — there is no data to warn about).
  - Gauge fill is not rendered (zero width / absent).
  - Caption row renders DASHES (`—`) for each macro, NOT `0%`. We do not imply a real split when there is no data.
- **Over-budget state** (S-105): when `consumedCalories > targetCalories > 0`:
  - Headline text color switches to `Theme.of(context).colorScheme.error` (the theme's restrained warning tone — no celebration, no alarm).
  - Gauge fill clamps to 100% of the track width (no overflow past `trackWidth`).
  - Caption percentages still render with real values (the data is real, not absent).
- The widget never picks a color of its own — `OmniTheme.colors.stripMacros.{protein,carbs,fat}` for the macro markers and fill segments (a MUTED palette tuned per theme — terracotta / steel-blue / amber; deliberately NOT the saturated `macroChart` palette), `OmniTheme.colors.divider` for the gauge track, `OmniTheme.colors.surface` for the card fill, `OmniTheme.surfaceBorder` + `OmniTheme.surfaceBorderWidth` for the hairline border, and `OmniTheme.deepShadow` for the raised shadow.
- The card's outer `Padding(EdgeInsets.symmetric(horizontal: 16))` provides the screen-edge inset (matching the tile grid's side margin). The home screen owns the top gap (2 × `standardGridSpacing`) and the bottom safe-area clearance.

---

### `NutritionSummaryCard`

**File**: `lib/features/nutrition/widgets/nutrition_summary_card.dart`

A card that displays the user's current daily nutrition targets as
"goal" lines (e.g., `Calories: 2500`).

| Prop | Type | Description |
|---|---|---|
| `nutritionState` | `NutritionState` | Source of the current target. Required. |

**Behavior**:
- Displays a title "Daily Targets".
- Renders one row per non-zero macro (`Calories`, `Protein`, `Carbs`,
  `Fat`). Macros whose target is `0.0` are hidden — they would otherwise
  render as `0 / 0` and trip the "no goal" / division-by-zero guard.
- Renders "No nutrition targets set." when `nutritionTarget` is `null`
  or `isUnset` (all four macros are `0.0`).
- Reads only the target side of `NutritionState`; the calorie ring on
  the page above owns the consumed-vs-target visualization.

### `CalorieRing`

**File**: `lib/features/nutrition/widgets/calorie_ring.dart`

Pure-presentation donut widget for the top of the nutrition page. Paints
a track + filled arc and centers a label column with today's consumed
calories vs the daily target.

| Prop | Type | Default | Description |
|---|---|---|---|
| `consumed` | `double` | required | Today's consumed calories (non-negative). Fractional values are rounded for display. |
| `target` | `double?` | required | Daily calorie target. `null` OR `<= 0` means consumed-only mode (no goal arc). |
| `size` | `double` | `160` | Outer diameter in logical pixels. |
| `strokeWidth` | `double` | `14` | Track and arc stroke width. |
| `emptyHint` | `String` | `'Log a food to start filling'` | Subtext shown when consumed is zero (both target set and target unset). |
| `centerOverride` | `Widget?` | `null` | Optional widget to render in the ring's center in place of the default calories text. When `null` (the default), the ring renders its standard `consumed / target kcal` view. When non-null, the override is shown in the same centered column and the default calories text is hidden. An internal `AnimatedSwitcher` cross-fades the swap. Used by `CalorieRingCard` to show a focused macro's `MacroFocusContent` while a section is focused. |

**Behavior**:
- Renders four label branches in the center column:
  - Target set + consumed > 0: `"<consumed> / <target> kcal"` and a
    secondary `"over by N"` caption when consumed > target.
  - Target set + consumed == 0: `"0 / <target> kcal"` with the
    `emptyHint` subtext.
  - Target null + consumed > 0: `"<consumed> kcal"` with `"no goal set"`
    subtext.
  - Target null + consumed == 0: `"0 kcal"` with the `emptyHint` subtext.
- Fill fraction is `consumed / target` clamped to `0..1` (no overflow
  past the track). The numeric label still shows the real `consumed`
  value so the user can see they exceeded the target.
- Track color: `OmniTheme.colors.divider`. Arc color:
  `OmniTheme.colors.primary`. No hardcoded colors.
- Numbers use `FontFeature.tabularFigures()` for stable column
  alignment, comma-grouped via an in-widget helper.
- Wraps the painter + label in a `Semantics(container: true, label: ...)`
  node announcing `"Calories: X of Y"` (or `"X, no goal set"`).
- Pure presentation — no `BuildContext` lookups, no repository access,
  no business logic. All math is local; safe to use in tests with no
  extra setup.

### `CalorieRingCard`

**File**: `lib/features/nutrition/widgets/calorie_ring_card.dart`

`OmniSurface` wrapper around `CalorieRing` for the top of `NutritionScreen`.
The "Today" section title and the small edit-targets icon button live
in an `OmniCardHeader` *above* the card (rendered by `NutritionScreen`,
not by this widget) — see `.github/agents/plans/unified-card-and-header-plan.md`
Phase 3. The card body itself renders the chart, the sodium chip, and the water tracker in an `OmniSurface` so its chrome matches every other outlined card in the app (radius 20, 1 px `surfaceBorder`, `deepShadow`).

Reads consumed + target data from the injected `NutritionState` and
rebuilds on every notification. Owns the **focus state** that drives
the macro-donut tap-to-focus interaction.

| Prop | Type | Description |
|---|---|---|
| `nutritionState` | `NutritionState` | Source of today's target and consumed-foods cache. Required. |
| `onEditTap` | `VoidCallback` | Tap handler for the edit icon. The widget does not navigate itself — the parent screen owns the routing contract. |

**Behavior**:
- Treats `nutritionTarget.calories == 0` (or a `null` target) as
  "no goal" so the ring renders consumed-only.
- Composes the new `MacroDonutChart` (outer) with the existing
  `CalorieRing` (inner) in a `Stack` so the calorie ring sits inside
  the macro donut's hollow center. The donut **hides** when no macros
  are logged (sum of the four macro grams is 0) — the calorie ring
  stays visible alone at its full 160 px size. The macro donut sits on
  top of the calorie ring in the `Stack` so its `GestureDetector` owns
  hit testing for the entire chart area; the calorie ring is never the
  tap target.
- **Tap-to-focus** (Iteration 2, S-008..S-014): the card owns the
  focused-section index. Tapping a section focuses it; tapping the same
  section again, or tapping the empty center, deselects. The card passes
  per-section opacities (1.0 for the focused section, 0.4 for the rest —
  tuned per the Q&A as a mild fade so all sections remain readable) to
  the donut, wraps the calorie ring in `AnimatedOpacity(opacity: 0.4)`
  when a section is focused, and passes a `MacroFocusContent` as the
  ring's `centerOverride`. The ring cross-fades to the override via its
  built-in `AnimatedSwitcher`. On first paint, no section is focused —
  the donut is at full opacity, the ring is at full opacity, the center
  shows calories (the existing default). When the focused section's
  grams drop to 0 (e.g. the user deletes the only protein food), the
  card's focus falls back to `null` and the default state returns.
- The four macro grams are read from `NutritionState`:
  `protein = todayConsumedProtein`,
  `netCarbs = max(0, todayConsumedCarbs - todayConsumedFiber)`,
  `fiber = todayConsumedFiber`, `fat = todayConsumedFat`.
- Edit icon (`Icons.tune`, `Key('edit_targets_icon')`, tooltip "Edit
  targets") lives in the `OmniCardHeader` actions slot above the card
  (rendered by `NutritionScreen`). The icon button has an explicit
  `shape:` override (`OmniTheme.buttonIconRadius` = 10) to avoid
  Material 3's default `StadiumBorder`. The icon is **not** part of the
  focus state — tapping it navigates to the targets editor as before.
- `ListenableBuilder` over `nutritionState` — every `notifyListeners()`
  (target load/save, consumed-food load, water increment / decrement,
  log/delete) rebuilds the ring, the donut, the sodium chip, and the
  water tracker. The focus survives a rebuild as long as the focused
  section still has non-zero grams (S-013); it clears if the section
  disappears (S-014), but does not flicker because the fallback is a no-op.
- **Bottom row** is a single `Row(spaceBetween)` with the sodium chip on
  the left and the `WaterTrackerControl` on the right. The two are
  siblings so they horizontally mirror each other. Both rebuild via the
  same `ListenableBuilder`, so each tap on either persists immediately
  and the ring reflects the new totals on the next frame.
- Pure presentation — no repository access, no business logic. The
  water tracker's increment / decrement is wired to
  `nutritionState.incrementWaterForDate(todayMs)` /
  `nutritionState.decrementWaterForDate(todayMs)`.
- Card chrome is `OmniSurface` with symmetric 16 dp padding (A20); no
  call-site may re-declare border, radius, or shadow.

### `WaterTrackerControl`

**File**: `lib/features/nutrition/widgets/water_tracker_control.dart`

Compact, tap-only +/− stepper for the day's water volume. Lives in
the bottom-right of `CalorieRingCard`, horizontally opposite the
sodium chip in the bottom-left. The on-screen glass count is
derived from the stored ml (`volumeMl ~/ kWaterGlassMl`); the icon +
literal `250 ml` annotation carries the unit so the user can decode
the per-glass amount at a glance. Water has no goal — the widget
carries no progress bar, target, or percentage.

Composition (left-to-right):
1. **Glass icon + `250 ml` annotation** stacked vertically. The icon
   (`Icons.local_drink_outlined`) sits on top and reads as a tumbler /
   glass with water; the literal `250 ml` caption sits beneath it so
   the per-glass amount is decoded at a glance. Muted-text color via
   `OmniTheme.colors.textMuted`. The annotation is sourced from
   `kWaterGlassMl` so a future per-glass change propagates here
   automatically. Vertical stacking keeps the row's total width tight
   (~22 dp narrower than the horizontal layout) so the control fits
   alongside the sodium chip on the same card row without crowding.
2. **Minus `IconButton`** — disabled (`onPressed: null`) at 0 glasses.
   `Icons.remove`. Disabled state uses `themeColors.textDisabled`; the
   active state uses `theme.colorScheme.primary`.
4. **Glass count** — tabular-figures `Text` showing the integer count.
   `Key('water_tracker_count')`.
5. **Plus `IconButton`** — enabled. `Icons.add`. `theme.colorScheme.primary`.

| Prop | Type | Description |
|---|---|---|
| `glasses` | `int` | Current glass count for the day. Always `>= 0`. The widget does not accept a typed amount — the count is the only signal the parent can pass in. |
| `onIncrement` | `VoidCallback` | Tap handler for the plus button. The widget does not invoke the state directly; the parent screen owns the persistence wiring. |
| `onDecrement` | `VoidCallback` | Tap handler for the minus button. The widget also passes `null` to the `IconButton.onPressed` (disabled state) when `glasses <= 0` so the visual and the no-op agree. |

**Behavior**:
- Pure presentation: no repository access, no business logic, no
  keyboard / text-entry field. The widget never reads or writes
  ml; the count is the only input.
- All buttons follow the explicit `shape:` + `OmniTheme.buttonIconRadius`
  (10) contract — Material 3's default `StadiumBorder` is never used.
  Both `IconButton`s are 36×36 with `visualDensity: compact` and
  `padding: EdgeInsets.zero` so the control fits the calorie-ring
  card's bottom row without crowding the sodium chip.
- Colors are theme-derived: `theme.colorScheme.primary` for active
  state, `themeColors.textDisabled` for the disabled minus, and
  `themeColors.textMuted` for the icon and `250 ml` label.
- The glass count uses tabular figures (`FontFeature.tabularFigures()`)
  so the value does not reflow as the count grows from 1 to 2 to 3
  digits.
- The widget is rebuilt by its parent's `ListenableBuilder` —
  no internal state. Every state change (increment, decrement, load,
  day rollover) flows through `NutritionState` and the
  `ListenableBuilder` rebuilds the row with the new `glasses` value.

### `MacroDonutChart`

**File**: `lib/features/nutrition/widgets/macro_donut_chart.dart`

Interactive donut widget that wraps the calorie ring on the daily
nutrition screen. Renders up to four colored arc sections — **Net
Carbs** (blue), **Fiber** (green), **Fat** (yellow), **Protein**
(white) — in fixed visual order. **Iteration 2** removed the
external labels and made the donut thicker (`strokeWidth` default
raised from 14 to 36, ~2.5× the calorie ring's stroke) and
**tap-to-focusable**: tapping a section focuses it. The chart owns
its own internal focus state (and surfaces a `Semantics` label of
`"<name> focused, <N> grams, <P> percent. Tap again or tap the
center to clear."` for screen readers and tests). The parent
**drives the visible focus via `sectionOpacities`** and an
`onSectionFocusChange` callback — typical use is for the parent to
compute per-section opacities (1.0 for the focused index, 0.4 for
the rest) and pass them in. When all four macros are 0, renders an
empty `SizedBox` so the parent can fall back to the calorie ring
alone.

**Iteration 3 polish** added:

- **In-band labels** at each section's mid-angle, on the band's
  mid-radius, drawn upright (not rotated). Format is
  `"<initial> <N>g"` with initials:
  - **N**  — Net Carbs
  - **Fb** — Fiber (disambiguated from Fat's single-letter F)
  - **F**  — Fat
  - **P**  — Protein
  Example: a 22 g net carbs section renders `"N 22g"`. The label
  color is picked per section via
  `ThemeData.estimateBrightnessForColor`: light section colors
  (e.g. protein's near-white, fat's amber) get the theme's
  `macroChart.chartLabelDark` slot; dark section colors
  (e.g. net carbs' blue, fiber's green) get the theme's
  `textDominant` slot. No hardcoded colors. Labels inherit the
  section's focus opacity (S-018) — when a section is unfocused
  and at 0.4 opacity, its label also fades to 0.4.
- **Fit test** (S-017): a section's label is hidden when the
  painted text width exceeds the section's arc length at
  mid-radius minus an 8 px breathing pad. A single 1 g Fiber
  slice next to three 200 g macros therefore renders no label
  in the Fiber slot, while the other three sections keep theirs.
- **Even gaps** (S-015): every inter-section gap (including the
  wrap-around seam at 12 o'clock) is exactly `gapDegrees` wide.
  The cursor in `computeMacroSections` now advances by
  `sweep + gap` per boundary (not `sweep + gap/2`), so the
  leftover half-gap that previously piled up at 12 o'clock is
  gone. Verified for n = 1..4 sections.

| Prop | Type | Default | Description |
|---|---|---|---|
| `protein` | `int` | required | Today's consumed protein grams. Negative inputs are clamped to 0. |
| `netCarbs` | `int` | required | Today's consumed net carbs (`carbs − fiber`) grams. The parent computes this — the chart does not derive it. Negative inputs are clamped to 0. |
| `fiber` | `int` | required | Today's consumed fiber grams. Negative inputs are clamped to 0. |
| `fat` | `int` | required | Today's consumed fat grams. Negative inputs are clamped to 0. |
| `size` | `double` | `240` | Outer diameter in logical pixels. The calorie ring should be sized to fit inside the donut's hole. |
| `strokeWidth` | `double` | `36` | Donut band thickness. Substantially thicker than the calorie ring's 14 px stroke so the donut reads as a wide ring around the ring. |
| `gapDegrees` | `double` | `1.5` | Angular gap between adjacent sections in degrees. `0` produces a seamless donut. |
| `sectionOpacities` | `List<double>?` | `null` | Per-section opacity values (length must equal the number of non-zero sections). When `null`, every section renders at 1.0. The parent passes 0.4 for unfocused sections when a focus is active. |
| `onSectionFocusChange` | `ValueChanged<int?>?` | `null` | Fired when the user taps inside the donut and the focus changes. Receives the new focused section index, or `null` when the focus is cleared (tap on the same section, or tap on the empty center). Not fired when the focus is unchanged. |

**Behavior**:
- Section sweep angles are proportional to grams. Non-zero sections
  share the full 360°; the gap between every adjacent pair of
  sections (including the wrap-around seam at 12 o'clock) is exactly
  `gapDegrees` wide — no wide notch at the seam (S-015, Iteration 3
  polish). The first section's leading edge is offset by `gap/2`
  from 12 o'clock so the seam is centered at 12 o'clock rather than
  on the section's leading edge; the cursor in `computeMacroSections`
  advances by `sweep + gap` per boundary so the gap math closes the
  circle exactly for any n = 1..4 sections.
- A `GestureDetector` with `HitTestBehavior.opaque` wraps the
  `CustomPaint` and owns hit testing for the entire chart. Tap
  regions are the donut sections themselves; taps inside the inner
  edge of the band (where the calorie ring lives) resolve to the
  `resolveSectionHitCenterSentinel` and deselect; taps outside the
  chart are a no-op. Hit-test math is the pure top-level function
  `resolveSectionHit(...)`, which takes the section list, the local
  tap position, the chart size, and the band's inner/outer radii.
  Unit-testable without a widget tree.
- **Angle convention.** The hit-test uses the raw `atan2(dy, dx)`
  angle directly — no offset. This matches `Canvas.drawArc`, which
  also measures angles from the +X axis (3 o'clock) CCW. A section
  whose `startAngleRadians == -π/2` is drawn from 12 o'clock and
  sweeps clockwise; the matching atan2 angle for a tap at 12
  o'clock is also `-π/2`, so the section range is hit-testable
  directly. Each section's range is treated as the half-open
  interval `[start, start+sweep)` so a tap on a boundary between
  two sections resolves to the **next** section (the boundary is
  owned by the section whose range contains it on its leading
  edge, not its trailing edge). When only one macro is non-zero,
  the single section wraps past the 0/2π boundary; the resolver
  splits the range accordingly.
- Tapping a section focuses it; the chart's internal state updates
  (so the `Semantics` label reflects the focus) and the
  `onSectionFocusChange` callback fires with the new index. Tapping
  the same section again, or tapping the empty center, fires the
  callback with `null` (deselect).
- In-band labels are drawn at each section's mid-angle, on the
  band's mid-radius, upright (no rotation). The label text is the
  documented initial + grams (e.g. `"N 22g"`, `"Fb 8g"`, `"F 30g"`,
  `"P 100g"`); the label color is picked per section via a luminance
  check (`ThemeData.estimateBrightnessForColor`): light section
  colors get `OmniTheme.colors.macroChart.chartLabelDark`; dark
  section colors get `OmniTheme.colors.textDominant`. No hardcoded
  colors. A section's label is hidden when the painted text width
  exceeds the section's arc length at mid-radius minus an 8 px pad
  (S-017). Label alpha inherits the section's `sectionOpacities`
  value, so labels fade to 0.4 alongside their section when a focus
  is active (S-018). The label-decision math is factored into the
  pure top-level `computeMacroLabels(...)` function (returns a
  `List<MacroLabel>`) so it can be unit-tested without a widget tree.
- Per-section opacity is applied by the painter as the alpha channel
  of the section's color. A section whose opacity is 0 is skipped
  entirely (no transparent arc rendered), keeping the donut quiet
  when one macro is focused.
- Colors come from `OmniTheme.colors.macroChart.protein / .netCarbs /
  .fiber / .fat` (themed palette; defined for all six themes). No
  hardcoded colors.
- A `Semantics(container: true, label: ...)` wrapper announces the
  current focus state (or `"Macro distribution. Tap a section for
  details."` when no section is focused).
- The section-angles math is factored into the pure top-level
  `computeMacroSections(...)` function (returns a `List<MacroSection>`)
  so it can be unit-tested without a widget tree.
- The widget mounts a `Key('macro_donut_chart')` on its `SizedBox`
  when at least one section is rendered (the key is absent in the
  empty-day branch by design). The key is the stable handle tests
  use to find the chart.
- Pure presentation — no repository access, no business logic, no
  `BuildContext` lookups beyond `Theme.of(context).textTheme`.

### `MacroFocusContent`

**File**: `lib/features/nutrition/widgets/macro_donut_chart.dart`

Small `StatelessWidget` rendered in the calorie ring's center when
a macro section is focused. Shows the macro name on line 1 with a
small colored dot (using the focused macro's color) and
`"<N>g · <P>%"` on line 2. Sized to fit inside the 160 px calorie
ring with its 8 px horizontal padding (144 px usable width).

| Prop | Type | Description |
|---|---|---|
| `name` | `String` | Section name (e.g. `"Protein"`). |
| `grams` | `int` | Section weight in grams. |
| `percent` | `int` | Section percentage of today's macros (0..100). |
| `color` | `Color` | Accent color for the dot beside the name. Comes from `OmniTheme.colors.macroChart.<slot>`. |

Used as the `centerOverride` argument on `CalorieRing` by
`CalorieRingCard` when a section is focused.

---

### `FoodLibraryBrowseSection` (private to `NutritionScreen`)

**File**: `lib/features/nutrition/nutrition_screen.dart` (private `_FoodLibraryBrowseSection`,
plus private `_GroupBlock` and `_FoodRow` helpers)

Read-only, scrollable, grouped list of foods for the "Food Library" card on `NutritionScreen`.
Drives three branches from `FoodLibraryState`:

| State | Renders |
|---|---|
| `isLoadingGroups \|\| isLoadingFoods` | Centered `CircularProgressIndicator` |
| `foodGroups.isEmpty && foods.isEmpty` | Centered muted "No foods in library" text |
| Data | One header per sorted `FoodGroup` (alphabetical, case-insensitive) followed by its sorted foods, then a trailing "Ungrouped" section for any foods with `groupId == null` |

| Prop | Type | Description |
|---|---|---|
| `foodLibraryState` | `FoodLibraryState` | Source of groups + foods cache. Required. |

**Behavior**:
- Renders one `LogFoodRow` per food. The `LogFoodRow` is the actual
  logging affordance (thumbnail toggle + amount input + single-line
  macros); this section is responsible for the grouped list layout +
  the per-row hairline dividers (S-006) only.
- **`_GroupBlock` dividers (S-006)**: between rows within a group, a
  1 px hairline divider (`OmniTheme.colors.divider`) is rendered. No
  divider is rendered above the first row, and no divider is rendered
  after the last row (so the existing 16 px bottom padding on the group
  block provides the gap to the next group). The per-divider key is
  `Key('group_<groupName>_divider_<i>')` where `<i>` is the row index
  that follows the divider (so `divider_1` sits between row 0 and row 1
  in a group; for a 3-row group the dividers are `_divider_1` and
  `_divider_2`, never `_divider_3`). Tests can assert presence by index
  and absence of the post-last-row index in one test each.
- Computes calories per food with `calculateCalories(food)` from
  `lib/core/utils/food_helpers.dart`; calories are never stored on
  the `Food` model.
- Excludes archived groups and archived foods (the default
  `includeArchived: false` is used by `loadFoodGroups()` /
  `loadFoods()`).
- Theme tokens only — colors come from `OmniTheme.colors` and the
  active `ThemeData`; no hardcoded colors.

---

## Logo & Brand

### `HomeLogoButton`

**File**: `lib/widgets/common/home_logo_button.dart`

Circular menu/avatar control for the home-screen AppBar that hosts the brand logo. Tapping opens the Hub sheet (Calendar / Stats / Profile / Nutrition / Settings).

**Visual chrome** (rendered in this order, back to front):
- 56×56 circular surface with a subtle ~6% white overlay (`Color(0x0FFFFFFF)`, matching the `OmniTheme.colors.surfaceBorder` token value) so the button has presence on the dark navy header
- 1px `surfaceBorder` ring (~6% white) reinforcing the circle edge — stays monochrome
- `OmniTheme.softShadow` for a low-elevation drop that gives the button its 3D feel against the dark header
- Brand logo artwork (`assets/icon/omnitrain_logo.png`) centered inside, sized to fill the circle (default 55×55 in a 55×55 circle)

**Theme tint** (logo recolor):
- The brand logo's own aqua-cyan matches the **Abyssal Neon** primary (`0xFF2DE2E6`), so on Abyssal Neon the logo is rendered untouched
- On every other theme the logo is recolored to that theme's `OmniTheme.colors.primary` via a `ColorFiltered` with `BlendMode.srcATop` (preserves the alpha mask, replaces RGB with the tint color — silhouette stays crisp)
- Tint comes from an existing `OmniTheme` token, so the button stays in-palette without introducing a new color

**Press reaction**:
- AnimatedScale to `OmniTheme.pressedScale` (0.9) on finger-down; settles back on release / cancel
- Subtle white `ColorFilter` highlight (~10% white) on the logo while pressed
- `HapticFeedback.lightImpact()` fires on `onTapUp`, guarded by `!kIsWeb`
- Reduced-motion users get the scale applied instantly without animation

**Hit target & accessibility**:
- 8px horizontal + 4px vertical transparent `Padding` around the visible circle brings the gesture bounds to 72×64 — well above the 44×44pt minimum
- Explicit `ConstrainedBox(minWidth: 44, minHeight: 44)` + `HitTestBehavior.opaque` keep the guarantee even if `tileSize` is later reduced
- `Semantics(button: true, label: 'Open menu')` wraps the whole control; the ring is decorative and the screen reader only hears the parent's label

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onTap` | `VoidCallback` | required | Fires on tap (after the gesture is released) |
| `size` | `double` | `55` | Logo artwork side length in logical pixels |
| `tileSize` | `double` | `55` | Outer circle diameter; matches `kToolbarHeight` (56) exactly so the AppBar toolbar height stays unchanged |

**Constraints**:
- Body-centered "TRAIN" title in the home `Column` is unaffected — the button is in the AppBar `title:` slot and its visible circle (56px) matches `kToolbarHeight` (56) exactly
- The control is a presentation-only widget: no repository or service access; only local `_isPressed` state

### `AnimatedZenHalo`

**File**: `lib/widgets/logo/animated_zen_halo.dart`

Animated brand mark with slow rotation (8000ms) and breathing pulse (3000ms). Used on the splash screen.

### `ZenHaloPainter`

**File**: `lib/widgets/logo/zen_halo_painter.dart`

`CustomPainter` for the Enso arc (zen circle). Stroke reveal animation at 1200ms.

---

## Picker Dialogs

### `ExercisePickerDialog`

**File**: `lib/widgets/pickers/exercise_picker_dialog.dart`

Modal dialog for searching and selecting exercises. Receives `sessionModality` to rank exercises by relevance.

**Key features**:
- Real-time search with `TextField`
- Exercises ranked by `getExercisesRankedForModality()` (relevance score)
- Filter by discipline or muscle group
- "New Exercise" button → opens `ExerciseEditorScreen` with picker/session modality prefilled via `contextModality`
- Returns selected `Exercise` on tap

### `MetricChooserDialog`

**File**: `lib/widgets/pickers/metric_chooser_dialog.dart`

Modal dialog for choosing a tracking method. Shown in Free Training mode and routine creation.

**Key features**:
- Displays only capabilities the selected exercise supports
- Each capability shown as tappable tile with icon and label
- Returns chosen metric string (e.g., `'time'`, `'reps'`, `'hold'`, `'rounds'`)

### `ModalityPickerDialog`

**File**: `lib/widgets/pickers/modality_picker_dialog.dart`

Modal dialog for selecting a modality for an exercise being added.

**Where it appears**:
- Live Free Training sessions (null modality)
- Routine building when the routine's **Focus Modality is "Mixed / Not set"** (null)
- Per-exercise `Change Tracking` override on an already-added exercise (both focus-set and Mixed routines)

**Where it does NOT appear**:
- Live Resistance / Cardio / Sports / Isometric sessions (the session's modality is already known)
- Routine building when the routine's Focus Modality is set — the new exercise silently inherits the focus modality's `effortKind`

**Key features**:
- Shows all five modalities plus a "General" option
- Returns `(true, String? modality)` record when the user picks an option:
  - Specific modality: `(true, 'cardio_endurance')` etc.
  - "General": `(true, null)`
- Returns `null` when the user cancels (so callers can distinguish cancel from "General")
- Callers use `showDialog<(bool, String?)>` and check for `null` before destructuring

---

## Session Metric Widgets

### `DominantMetricWidget`

**File**: `lib/widgets/session/set_metric_widget.dart`

Unified large-metric display widget used across all effort kinds. Renders exactly **one** large metric value.

| Prop | Type | Description |
|------|------|-------------|
| `displayText` | `String` | The value to show (e.g., "10", "03:00", "Round 1\n03:00") |
| `isMultiline` | `bool` | Multi-line rendering for round display |
| `onTap` | `VoidCallback?` | Tap handler (edit reps, toggle timer) |

The following files are **stub redirects** to `DominantMetricWidget`, kept for import compatibility:
- `lib/widgets/session/drill_metric_widget.dart`
- `lib/widgets/session/round_metric_widget.dart`
- `lib/widgets/session/timed_metric_widget.dart`

### `InlineMetricEditor`

**File**: `lib/widgets/session/inline_metric_editor.dart`

Touch-optimized value input for workout environments. Tap the number to open a numeric-entry modal (the crown scrub control is present in the codebase but not rendered — see `MetricCrownWidget`).

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight`, `duration`, `rpe`, `extra-weight` |
| `currentValue` | `dynamic` | Value to display |
| `unitLabel` | `String` | Label below value (e.g., "REPS", "LBS") |
| `emphasisTier` | `MetricEmphasisTier?` | Optional value emphasis: `dominant`, `secondary`, `muted`; default keeps legacy displayLarge styling |
| `isReadOnly` | `bool` | When true: disables tap-to-edit popup. Used for live timer displays. |
| `onTap` | `VoidCallback?` | When provided, tapping the number calls this instead of opening the generic popup (e.g. timer toggle, duration dialog). |
| `onValueChanged` | `Function(dynamic)` | Immediate callback on value change |

**Interaction model**:
- Number tap is the sole value-change mechanism.
  - `onTap` provided → delegates to `onTap`.
  - `onTap` null and `!isReadOnly` → opens `showMetricEditPopup`.
  - `isReadOnly: true` → no interactive affordance.
- The crown scrub control (`MetricCrownWidget`) is dormant — it remains in the codebase at `lib/widgets/session/metric_crown_widget.dart` and can be re-enabled in the row without rebuilding the widget.

**Visual**: Value size and styling unchanged. The crown is not rendered. When `isReadOnly` and `emphasisTier` are both set, the emphasis tier wins and the value is not dimmed.

**Session context (live timed/round/drill)**: In `WorkoutSessionScreen` detail view, the `InlineMetricEditor` for live timer-based efforts (`timed`, `round`, `drill`) uses `onTap` wired to `showDurationEntryDialog` so tapping the time value opens the h/m/s editor. When the effort is finished (`isTimedFinished`, `isFinished`, `isDrillFinished`), `isReadOnly: true` is set so the value cannot be edited from live mode (use edit mode for corrections). Play/pause control is a separate Start button — not a tap on the value display. Timed and drill timers render at the dominant tier; the play/pause status label sits on a line below the value.

---

### `MetricCrownWidget`

**File**: `lib/widgets/session/metric_crown_widget.dart`

**Status: dormant.** The widget is fully implemented and constructible but is not rendered by `InlineMetricEditor` in the default interaction path. It can be re-enabled by adding it to the `InlineMetricEditor` row without any other changes.

A rotatable thumb-wheel (crown) control painted as a thick vertical wheel edge-on.

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | Metric type (forwarded to `MetricStepCalc`) |
| `currentValue` | `dynamic` | Current metric value; read on each drag tick |
| `onValueChanged` | `Function(dynamic)` | Fires on each 10px drag step |

**Behavior**: drag fires `onValueChanged` via `MetricStepCalc.apply`. Crown rotates `2π / 120px` radians per pixel. Rotation accumulates for the widget's lifetime but stops immediately on drag release (no momentum). No `AnimationController` or `Timer`.

**Style**: `44×60` touch target; `CustomPaint` centred inside; all colours from `OmniTheme.colors.textMuted`/`textSecondary` with opacity overlays.

**Drag step sensitivity** (from `MetricStepCalc.apply`):
| Metric | Increment per 10px | Range |
|--------|-------------------|-------|
| `reps` | ±1 | 0–999 |
| `weight` | ±0.5 | 0.0–999.0 |
| `duration` | ±5 sec | 0–3600 |
| `rpe` | ±1 | 1–10 |
| `extra-weight` | ±0.5 | -100.0–200.0 |

---

### `showMetricEditPopup`

**File**: `lib/widgets/session/metric_crown_widget.dart` (top-level function)

Opens an `AlertDialog` for exact numeric entry of a metric value.

```dart
Future<void> showMetricEditPopup(
  BuildContext context, {
  required String metricType,
  required dynamic currentValue,
  required String unitLabel,
  required Function(dynamic) onValueChanged,
})
```

- Pre-fills field with formatted current value; selects all text on open.
- Confirm ("Ok"): parses + clamps → `onValueChanged` → closes.
- Barrier tap (outside dialog): closes without calling `onValueChanged`. There is NO Cancel button.
- Empty or unparseable text → treated as dismiss (no value change).
- Keyboard: `signed: true` for `weight`/`extra-weight`; `signed: false` for all other metric types (e.g., `reps`).
- Ok button has explicit `shape: RoundedRectangleBorder(borderRadius: OmniTheme.buttonUtilityRadius)`.

---

### `showDurationEntryDialog`

**File**: `lib/widgets/session/duration_entry_dialog.dart` (top-level function)

Shared h/m/s duration-entry dialog. Used by `WorkoutSessionScreen` (both live and edit modes) and `RoutineSetupScreen` (round effort duration targets).

```dart
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
})
```

- Returns confirmed duration in whole seconds (`h*3600 + m*60 + s`), or `null` if dismissed.
- Three `TextField` instances for hours, minutes, seconds. Pre-filled from `initialSecs`.
- Single "Ok" `FilledButton`. No Cancel button. Barrier tap dismisses without applying.
- `TextEditingController`s are deferred-disposed (300 ms after dialog close) to avoid use-after-dispose errors.

**Usage**: Wire to `onTap` on `InlineMetricEditor` when `metricType == 'duration'`.

---

### `MetricStepCalc`

**File**: `lib/widgets/session/metric_crown_widget.dart` (static class)

Shared utility for value-adjustment math and popup parsing. Used by both `MetricCrownWidget` and `showMetricEditPopup`.

- `MetricStepCalc.apply(metricType, currentValue, deltaY)` — drag step math (identical to previous `InlineMetricEditor._calculateNewValue`).
- `MetricStepCalc.parseAndClamp(metricType, text)` — parse popup input, clamp to metric range, return typed result (`int` for reps, `double` for others). Returns `null` if unparseable.

### `PRToast`

**File**: `lib/widgets/session/pr_toast.dart`

Static factory for the in-session "Congrats! New PR" celebration `SnackBar` that fires when a strength set beats the user's all-time best e1RM (per the Stats screen's PR definition). Non-blocking, auto-dismissing, theme-token-only.

- `PRToast.buildPRSnackBar(ThemeData theme)` → `SnackBar` with:
  - `duration: 2.0 s` — auto-dismisses; never blocks the rest timer or the next set.
  - `behavior: SnackBarBehavior.floating` — does not push the bottom controls up; the user can keep typing in the numeric editor.
  - `margin: EdgeInsets.only(bottom: 168, left: 16, right: 16)` — the 168 px bottom lift clears `WorkoutSessionScreen._kBottomControlsClearance` (140 px CTA + 24 px scroll padding) + 4 px tolerance.
  - `backgroundColor: theme.colorScheme.surface` — derived from the active theme, never hardcoded.
  - `content`: trophy `Icon(Icons.emoji_events, size: 18, color: theme.colorScheme.primary)` + `SizedBox(width: 8)` + `Text('Congrats! New PR', style: bodyMedium.copyWith(color: theme.colorScheme.onSurface))`.
  - **No `action:`** field — the user is never asked to tap "Dismiss" or anything similar.

**Where it is triggered**: `WorkoutSessionScreen._logSet()` calls `_maybeShowPRToast()` after `_persistEntryValues(...)` and before the rest-timer / advance logic. The check is gated on `effortKind == 'set' && !isSkippedSetKindEntry`, and the helper additionally blocks in `widget.editMode` (edit-mode suppression) and on `epley1RM == null` (zero reps or non-positive weight). The SnackBar call is fire-and-forget — `showSnackBar` is synchronous and the call chain continues immediately to `recordRestStart` and the set advance.

**PR definition source of truth**: the in-session check uses `StatsProgressService.epley1RM(weight, reps)` and `StatsProgressService.getAllTimeBestE1RM(exerciseId)` — the same helpers the Stats screen's PR detection loop uses. There is exactly one PR definition; both surfaces change together. S-009 in the in-session PR toast plan is the structural-guard test that enforces this.

---

## Presentation Models

### `UiSetData`

**File**: `lib/widgets/models/ui_set_data.dart`

Mutable presentation-layer data class for set tracking. **Not a persistence model.**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier |
| `exerciseId` | `String` | Parent exercise |
| `reps` | `int` | Mutable — current reps value |
| `weight` | `double` | Mutable — current weight value |
| `duration` | `int` | Mutable — current duration in seconds |
| `timestamp` | `DateTime` | When created |

Used by `WorkoutSessionScreen` and `RoutineSetupScreen` for ephemeral UI state.

---

## Nutrition Widgets

Nutrition-feature widgets live under `lib/features/nutrition/widgets/`. They are
feature-scoped (only `NutritionScreen` uses them) but follow the catalog
conventions: pure presentation, theme-reactive, no repository access, state
injected via constructor.

### `LogFoodRow`

**File**: `lib/features/nutrition/widgets/log_food_row.dart`

A single food-library row that doubles as the "log a food as consumed"
affordance on the nutrition page. Layout, left to right:

```
[ thumb toggle ]  [ name (1 line) + "<cal> cal · <P>P · <C>C · <F>F" ]  [ amount input + unit label ]
```

**Iteration 1 (thumbnail toggle)** replaced the leading `Checkbox`
with a tappable food thumbnail. The thumb IS the log/unlog toggle
(S-001): tapping it logs the food at the current amount (or unlogs).
Foods with `imagePath` show the image; foods without show the muted
placeholder from `FoodThumbnail` (S-002 — the common case on web
where the image picker is a no-op). The visible thumb is 40×40 and
the tap target is padded to **48×48** (design-system gym-glove rule).
The thumb's `Semantics(checked: isLogged, label: "Log <name>" /
"Unlog <name>", button: true)` wrapper exposes the toggle to screen
readers and tests via `flagsCollection.isChecked` (S-005).

**Selected state** (S-003): 2 px primary border + a 16×16 check badge
in the top-right corner filled with `primary`. The transition is
animated via `AnimatedContainer` (border) and `AnimatedOpacity`
(badge) at `OmniTheme.animationDuration` (180 ms) and
`OmniTheme.animationCurve` (`easeInOut`). **Unselected state**
(S-004): 1 px hairline `divider` border, no badge. **Press feedback**
(S-003 / S-004): an `AnimatedScale` shrinks the visible thumb to
0.96× its size while pressed.

The amount input behavior is unchanged from prior iterations — the
typed value is the food's own-unit amount for grams foods and a
multiplier for count foods. Editing the amount on a logged row
auto-commits the new amount to the day log (debounced ~250 ms).
Validation: amount must be `> 0`; an invalid amount makes the thumb
tap a no-op and renders an inline error.

**Iteration 1 (single-line macros — S-007)** replaced the 2×2 macro
grid with a single `Text` line in the format
`"<cal> cal · <P>P · <C>C · <F>F"` (e.g. `"90 cal · 0P · 0C · 10F"`)
for format parity with `AddFoodScreen` rows. The line is one `Text`
widget with `maxLines: 1` and `TextOverflow.ellipsis`.

| Prop | Type | Description |
|------|------|-------------|
| `food` | `Food` | The library food to render and toggle. |
| `nutritionState` | `NutritionState` | Day-log state (read for `isFoodLoggedToday`; mutate via `logConsumedFoodAt` / `unlogFoodToday`). |
| `foodLibraryState` | `FoodLibraryState` | Symmetric constructor parameter; not mutated by the row. |

**Stable keys (for tests)**:
- `Key('log_food_thumb_<food.id>')` — mounted on the `Semantics`
  wrapper of the thumb toggle (not the inner `GestureDetector`).
  Tests look up the toggle's checked state via
  `tester.getSemantics(find.byKey(...)).getSemanticsData().flagsCollection.isChecked`
  (returns `CheckedState.isTrue` when logged, `CheckedState.isFalse`
  when not). The key is on `Semantics` (not `GestureDetector`) so
  that semantics-tree lookups find the correct node carrying the
  `checked` / `label` properties.
- `Key('log_food_amount_<food.id>')` — mounted on the amount input.

**Row separation (S-006)**: hairline dividers (`divider` color,
1 px) render between rows in a group, never after the last row.
Implemented in `_GroupBlock` (the private widget in
`nutrition_screen.dart` that renders each food group). The
per-divider key is `Key('group_<groupName>_divider_<i>')` where
`<i>` is the row index that follows the divider.

The widget rebuilds via `ListenableBuilder(listenable: nutritionState)`
so the thumb's checked state and the amount input's pre-fill update
the moment a log is written.

---

### `FoodThumbnail`

**File**: `lib/features/nutrition/widgets/food_thumbnail.dart`
(platform image renderer split into
`food_thumbnail_io.dart` / `food_thumbnail_stub.dart` via
conditional import — same pattern as `ProfileAvatarImage` in
`lib/features/profile/widgets/`).

A 40×40 rounded thumbnail for a food item, with a placeholder
when no image is set. Mirrors the contract of `ProfileAvatarImage`:
the image is loaded from a local file path on native and falls
back to a placeholder on web or when the file is missing.

Used as the leading slot on each catalog row in the **Library**
tab of `AddFoodScreen` (key `food_catalog_thumb_<id>`). The slot
is always present (placeholder when no image) so the trailing
Add / Remove button column does not reflow when an image is
added or removed. The same widget is also used inside the
`FoodForm`'s image picker tile.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `imagePath` | `String?` | required | Local file path to a food photo. `null` / empty / unreadable path falls back to the placeholder. |
| `size` | `double` | `40` | Diameter in logical pixels. |
| `radius` | `double` | `8` | Corner radius — matches the `OmniTheme.buttonUtilityRadius` token. |

**Behavior**:
- Always renders a fixed-size slot. The slot is filled with the
  image (`Image.file` on native with an `errorBuilder` fallback)
  or a placeholder (`Icons.restaurant_outlined` tinted with
  `OmniTheme.colors.textMuted` on a `surface` background).
- Pure presentation — no repository / state access, no business
  logic. The `imagePath` is a plain `String?` read at build time.
- The `kIsWeb` short-circuit keeps `dart:io` out of the web build.

### `FoodForm`

**File**: `lib/features/nutrition/widgets/food_form.dart`

Shared form widget used by both the **+ New Item** flow on
`AddFoodScreen` and the **Edit Food** screen
(`EditFoodScreen`). Parameterized by an optional `Food?` initial
value: `null` → create mode, non-null → edit mode.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `initial` | `Food?` | required | Pre-fill the form with this food's values when non-null. |
| `foodLibraryState` | `FoodLibraryState` | required | Source for the categories dropdown (re-reads `activeFoodGroups` on every notification). |
| `onSave` | `Future<bool> Function(FoodDraft draft)` | required | Save callback. Returns `true` to pop, `false` to surface a snackbar. |
| `saveLabel` | `String` | `'Save'` | Primary CTA label. |
| `showNotesField` | `bool` | `false` | When true, renders a "Notes (optional)" multi-line field. Edit mode only. |
| `onImageSave` | `Future<bool> Function(FoodDraft draft)?` | `null` | Optional partial-save callback fired after a successful photo pick **or** after the × (clear) overlay clears the photo in **edit mode** (`initial != null`). Wired by `EditFoodScreen` to `FoodLibraryState.updateCatalogFood` so the new or cleared `imagePath` lands in the data layer immediately, even on screens that have no Save button. The draft is built from `initial` with only `imagePath` swapped, so concurrent edits to the form's text controllers (a half-typed name, for example) are preserved. **Not fired in create mode** — the image is just stored locally until the user saves the whole food. |

**Form fields (top to bottom)**:
1. Image picker tile (`FoodFormImageTile`, key `food_form_image_tile`) — square 96×96 with × (clear) and edit (change) overlays; opens a Camera / Gallery bottom sheet on tap; web is a no-op with a snackbar.
2. Name (`food_form_name`) — `TextFormField` with `TextCapitalization.words`.
3. Category (`food_form_group`) — `DropdownButtonFormField<String?>` of the active groups + an "Ungrouped" `null` entry.
4. Unit type (`food_form_unit_type`) — `DropdownButtonFormField<FoodUnitType>` of `count` / `grams`. Swapping units pre-fills sensible defaults for the reference amount + label.
5. Reference amount (`food_form_reference_amount`) + Reference label (`food_form_reference_label`).
6. Macros (per the reference above) — `Protein (g)` (required), `Carbs (g)` (required), `Fiber (g)` (optional, blank = unset), `Fat (g)` (required), `Sodium (mg)` (optional, blank = unset). All accept **decimal** input (e.g. `0.5`, `1.25`) via the `^\d*\.?\d*$` regex filter, mirroring the reference-amount field. Macros are stored as `double` on `Food` / `FoodDraft` so fractional grams persist (S-001).
7. Notes (`food_form_notes`) — when `showNotesField: true`.

**Save CTA**: the form does **not** render an inline save button. The host screen owns the primary bottom CTA via the shared `OmniBottomCTA` (see `.github/agents/plans/primary-bottom-cta-anchor-width-plan.md`). The host wires the CTA's `onPressed` to `FoodFormController.submit`, which routes through the form's validation + save pipeline — the same pipeline the inline button used to trigger.

**Behavior**:
- The form owns validation, the image picker, and the
  translation from controllers to a typed `FoodDraft`. The caller
  hands the draft to `FoodLibraryState.createCustomFood` (create)
  or `FoodLibraryState.updateCustomFood` / `updateCatalogFood`
  (edit) — never to the repository directly.
- "Save on upload" (edit mode): when `onImageSave` is provided
  and `initial != null`, the photo pick handler persists the new
  `imagePath` to the data layer immediately (D-7 cleanup of the
  previous managed file is the state method's responsibility —
  the form does not call the service directly). On hosts that
  have no Save button (`EditFoodScreen` with
  `autoSaveOnBlur: true`), this is the **only** path that writes
  the picked photo to the data layer before the user navigates
  away, so without it the photo would not persist.
- "Save on clear" (edit mode): symmetric to "Save on upload".
  Tapping the × (clear) overlay invokes `clearImage()` which
  sets `_imagePath = null` locally and fires `onImageSave` with
  a partial draft (`imagePath: null`). The state method's
  `previousPath != draft.imagePath` branch handles D-7 cleanup
  of the previous managed file. **Not fired in create mode**
  (no source food to partial-save against).
- Fiber is exposed alongside carbs in the macro list, matching
  the `Food.fiber` field on the model. The existing
  `calculateNetCarbs(food)` helper handles the net-carb math.
- **Auto-select on focus** (S-004..S-006): every `TextFormField`
  on the form (name, reference amount, reference label, all five
  macros, notes) has a per-field `FocusNode` wired to a
  `_selectAllOnFocus` handler. Tapping a pre-filled field
  highlights the entire value via
  `controller.selection = TextSelection(baseOffset: 0,
  extentOffset: controller.text.length)`, so the user can
  retype a value without first clearing it. Empty fields are a
  no-op (no select-all across an empty range). The handler is
  separate from the form-level `FocusNode` that drives
  `autoSaveOnBlur`; the two co-exist without conflict.
- All colors come from `OmniTheme.colors` /
  `ThemeData.colorScheme`. No hardcoded colors.

**Test seam**: `handlePickedImage(XFile)` and `clearImage()` are
both `@visibleForTesting` on the form's state. Production callers
go through the OS picker via `_pickImage(ImageSource)` and the
× overlay via the `FoodFormImageTile.onClear` callback; tests
invoke the seams directly to bypass the platform channel and
overlay tap.

---

### `_CategoriesTab` (private to `AddFoodScreen`)

**File**: `lib/features/nutrition/add_food_screen.dart` (private
`_CategoriesTab`, `_CategoryRow`, `_UngroupedRow`, `_DeleteCategoryDialog`)

The third tab of `AddFoodScreen`. Manages the food groups that
organize the user's library. Layout (top to bottom):

- A scrollable list of `_CategoryRow` widgets, one per active
  `FoodGroup` (alphabetical, case-insensitive).
- A trailing read-only `_UngroupedRow` (foods with `groupId == null`).
- A "+ New Category" `OutlinedButton.icon` (key `new_category_button`)
  that calls `FoodLibraryState.createFoodGroup('New Category')`.

The list rebuilds via `ListenableBuilder(listenable: foodLibraryState)`
so add / rename / archive operations reflect immediately.

### `_CategoryRow` (private to `_CategoriesTab`)

| Param | Type | Purpose |
|---|---|---|
| `group` | `FoodGroup` | The group to render |
| `controller` | `TextEditingController` | Stable per-group controller (held by `_CategoriesTabState._controllers`); preserves in-progress rename text across rebuilds |
| `foodCount` | `int` | Number of foods in this group; rendered in the `suffixText` |
| `onRename(String)` | `Future<void> Function(String)` | Calls `FoodLibraryState.renameFoodGroup(id, newName)` |
| `onDelete()` | `Future<void> Function()` | Opens the confirm dialog (or silent-deletes when `foodCount == 0`) |

The `TextField` is keyed `category_name_<group.id>` and commits the
rename on `onEditingComplete` (IME action / unfocus) and on
`onSubmitted` (Enter). The trash `IconButton` is keyed
`category_delete_<group.id>`. Both use `OmniTheme.colors` and
`theme.colorScheme` — no hardcoded colors.

### `_UngroupedRow` (private to `_CategoriesTab`)

A read-only, single-row summary of foods with `groupId == null`.
Renders an `Icons.label_off_outlined` icon, the label "Ungrouped"
(italic, muted), and the food count. No `TextField`, no trash
affordance — the row is purely informational.

### `_DeleteCategoryDialog`

Confirmation dialog for deleting a non-empty category. Title
"Delete category?"; body shows the count of foods to be moved and a
`DropdownButtonFormField` (key `delete_category_destination`) for
the destination group. Options: "Ungrouped" (the default, value
`null`) plus every other active group. Actions: `TextButton("Cancel")`
returns the private `_cancelledSentinel`; `FilledButton("Delete")`
(red `theme.colorScheme.error`, key `delete_category_confirm`)
returns the picked destination id (which may be `null` for
Ungrouped). The caller uses the sentinel to distinguish cancel from
"Ungrouped".

---

## Profile Widgets

### `MeasurementSparkline`

**File**: `lib/features/profile/widgets/measurement_sparkline.dart`

Small history visualization for a single body measurement on the Profile screen. Renders one of three branches based on the entry count read from `ProfileState.getMeasurementHistory`:

- **0 entries** — centered muted text `"No history yet"` at the sparkline's full height.
- **1 entry** — the same full chart frame as the 2+ branch (Y-axis line, X-axis line, Y-axis scale labels, X-axis date strip) with **a single horizontal line** crossing **a single filled dot** at the entry's value. Both Y-axis labels show the same value (since `minV == maxV`); both X-axis labels show the same date (since `minMs == maxMs`). The line and dot both render at the chart's visual centre via the existing `xForTimestamp` / `yForValue` fallbacks (`timeRange == 0` → data-area mid; `range == 0` → `xAxisLineY / 2`). Replaces the legacy `Divider`-only hairline so the chart frame stays visually stable across the 0/1/2+ branch transitions.
- **2+ entries** — a compact chart inside a **60 dp** container:
  - **Axes**: a vertical Y-axis line on the **left** (boundary between the y-axis label column and the data area) and a horizontal X-axis line at the **bottom** of the chart area (boundary between the data area and the x-axis date strip). Both are 1 dp `theme.dividerColor` strokes drawn by the painter inside the same `CustomPaint` as the data line + dots.
  - **Y-axis scale**: a max value label at top-LEFT and a min value label at bottom-LEFT of the chart area, in a 38 dp wide LEFT column to the left of the Y-axis line. Right-aligned so the rendered text visually anchors to the line. Rendered in `labelSmall` + `textMuted` + 9 pt. Format is the raw numeric value via `toStringAsFixed(1)` — the unit is intentionally **dropped** (the header above names the measurement and the value column shows the unit), so the LEFT column fits at the same font size as the X-axis labels. `overflow: TextOverflow.ellipsis` clips gracefully for edge cases.
  - **X-axis scale**: a first date label at bottom-left and a last date label at bottom-right via `ChartAxisHelper.formatDateLabel` (`MMM d`, e.g. `Jun 17`). The labels live in the bottom 22 dp of the container; the data + axes live in the top 38 dp.
  - **Line + dots**: `theme.colorScheme.primary` 1.5 dp stroke line through the points with a 2 dp filled dot at **every** entry. X positioning is **time-based** (each entry's `recordedAtMs` is mapped linearly across the chart width) so two entries months apart sit at the chart's leftmost and rightmost x positions while many entries clustered in time sit close together. Falls back to chart mid when all timestamps are equal.

The whole sparkline area is wrapped in an `InkWell` whose `onTap` opens the existing `MeasurementHistoryChartSheet` for the measurement.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `definition` | `ProfileMeasurementDefinition` | required | Which measurement to read history for (e.g. `ProfileMeasurements.bodyweight`). Drives the entry-fetch and the title-key. |
| `profileState` | `ProfileState` | required | Source of the measurement history (`getMeasurementHistory`). |
| `settingsState` | `SettingsState` | required | Injected for symmetry with the surrounding surface chrome. No longer used internally (A18 dropped the unit suffix from the y-axis labels). Reserved for future hooks. |
| `onTap` | `VoidCallback?` | `null` | Tapping anywhere inside the sparkline area fires this callback. The host wires it to `_showMeasurementHistory(definition)`. |

**Behavior**:
- Sized at **60 dp tall** (A19; was 56 dp intermediate A18, 38 dp with axes but smaller, 40 dp in A17, 60 dp pre-A17). The chart now **fills** the entire 60 dp card row — the user wants the chart to use the available vertical space rather than sit with breathing room. The host card padding (`EdgeInsets.symmetric(horizontal: 18, vertical: 14)`) wraps the sparkline; total card height stays 88 dp (60 dp chart + 28 dp padding).
- **Refresh model**: the entry list is loaded asynchronously in `initState` via `profileState.getMeasurementHistory(definition.type)`; the widget subscribes to `profileState` (added in `initState`, removed in `dispose`) and re-fetches on every `notifyListeners`; `didUpdateWidget` also reloads when the `definition.type` changes. The listener is the only reliable way to refresh the chart after a new measurement is added via the log sheet — `didUpdateWidget` does not fire when the parent rebuilds with the same `definition` (the common case after a save).
- Keys (for testability): `Key('measurement_sparkline')` on the container `SizedBox`; `Key('measurement_sparkline_tap')` on the `InkWell` gesture area; `Key('measurement_sparkline_y_max')` / `Key('measurement_sparkline_y_min')` on the y-axis value `Positioned`s (LEFT column); `Key('measurement_sparkline_x_first')` / `Key('measurement_sparkline_x_last')` on the x-axis date label `Positioned`s (BOTTOM strip).
- Presentation-only: no repository access of its own (delegates to the injected `ProfileState`), no service access, no business logic. All chart math is local; the painter is a small private class inside the same file. Scale math delegates to the canonical `ChartAxisHelper` and `UnitFormatter` owners (per `docs/global_conventions.md` "Reuse the canonical owner").
- Host layout (per A16, Phase 4 refinement, updated by A17): the per-measurement card body is a 3-section row `[chart rectangle | current value | + button]`. The chart rectangle occupies the available width (`Expanded`), the value column is a fixed 90 dp wide text centred horizontally (`textAlign: TextAlign.center`, `maxLines: 1`, `overflow: TextOverflow.ellipsis`), and the `+` button is the standard 60 × 60 dp outlined `OutlinedButton`. The `OmniCardHeader` is **title-only — no actions cluster** and **uppercased** (A17: `definitions[index].label.toUpperCase()`, so the rendered eyebrow reads e.g. `BODY WEIGHT` not `Body Weight`). Tapping the chart rectangle opens the existing history sheet; tapping the `+` button opens the existing log sheet. Only the titles (`MEASUREMENTS` / `ADDITIONAL` section eyebrows) were extracted into the header in Phase 4; the card body's column structure stays intact.

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

## Related Documentation

- [Design System](design_system.md) — Design tokens, color system, typography, animation rules
- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — How metric widgets are used in the workout screen

---

**Document Version**: 1.3
**Last Updated**: June 8, 2026
